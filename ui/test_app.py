import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))
import app


class UiSmokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.environment = patch.dict(
            os.environ,
            {
                "POSTGRES_URL": "",
                "DATABASE_URL": "",
                "TNS_ADMIN": "",
                "PRISON_CLOUD_TNS": "",
            },
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.flask_app = app.create_app()
        self.flask_app.config["TESTING"] = True
        self.client = self.flask_app.test_client()

    def test_home_page_has_security_headers(self) -> None:
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Prison operations", response.data)
        self.assertEqual(response.headers["X-Frame-Options"], "DENY")

    def test_security_policy_allows_only_configured_realtime_origin(self) -> None:
        with patch.dict(
            os.environ,
            {"NEON_REALTIME_URL": "https://realtime.example/live"},
        ):
            response = self.client.get("/")

        policy = response.headers["Content-Security-Policy"]
        self.assertIn("https://realtime.example", policy)
        self.assertIn("wss://realtime.example", policy)
        self.assertNotIn(" https: ", policy)

    def test_dashboard_requires_login(self) -> None:
        response = self.client.get("/api/dashboard")
        self.assertEqual(response.status_code, 401)

    def test_owner_account_is_not_accepted_as_a_ui_role(self) -> None:
        response = self.client.post(
            "/api/login",
            json={"username": "PRISON_OWNER", "password": "not-used"},
        )
        self.assertEqual(response.status_code, 400)

    def test_assigned_role_requires_postgres_configuration(self) -> None:
        response = self.client.post(
            "/api/login",
            json={"username": "PRISON_U_FRONTDESK", "password": "not-used"},
        )
        self.assertEqual(response.status_code, 503)
        self.assertIn("PostgreSQL connection is not configured", response.get_json()["error"])

    def test_role_login_uses_postgres_role_and_logout_requires_csrf(self) -> None:
        class FakeConnection:
            closed = False

            def close(self) -> None:
                self.closed = True

        fake_connection = FakeConnection()
        with patch.dict(
            os.environ,
            {
                "POSTGRES_URL": "",
                "DATABASE_URL": "postgresql://db-owner:secret@example.test/prison",
            },
        ), patch.object(app.psycopg, "connect", return_value=fake_connection) as connect:
            response = self.client.post(
                "/api/login",
                json={"username": "PRISON_U_FRONTDESK", "password": "test-password"},
            )
            self.assertEqual(response.status_code, 200)
            connect.assert_called_once_with(
                "postgresql://db-owner:secret@example.test/prison",
                user="prison_u_frontdesk",
                password="test-password",
                connect_timeout=10,
            )
            identity = response.get_json()

            forbidden = self.client.post("/api/logout", json={})
            self.assertEqual(forbidden.status_code, 403)
            logged_out = self.client.post(
                "/api/logout",
                json={},
                headers={"X-CSRF-Token": identity["csrf"]},
            )
            self.assertEqual(logged_out.status_code, 200)
            self.assertTrue(fake_connection.closed)

    def test_realtime_proxy_uses_the_authenticated_role_scope(self) -> None:
        class FakeConnection:
            def close(self) -> None:
                pass

        class FakeResponse:
            def __enter__(self) -> "FakeResponse":
                return self

            def __exit__(self, *_args: object) -> None:
                pass

            def read(self) -> bytes:
                return b'{"query":{"id":"sealed-query"}}'

        with patch.dict(
            os.environ,
            {
                "POSTGRES_URL": "postgresql://db-owner@example.test/prison",
                "NEON_BRANCH_ID": "br-test",
                "NEON_FUNCTION_HOST_SUFFIX": ".compute.example",
                "NEON_REALTIME_URL": "https://realtime.example",
                "PRISON_APP_API_KEY": "server-only-test-key",
            },
        ), patch.object(app.psycopg, "connect", return_value=FakeConnection()), patch.object(
            app, "urlopen", return_value=FakeResponse()
        ) as urlopen:
            login = self.client.post(
                "/api/login",
                json={"username": "PRISON_U_FRONTDESK", "password": "test-password"},
            )
            identity = login.get_json()
            response = self.client.post(
                "/api/realtime/visits",
                json={"username": "PRISON_U_ADMIN", "visitDate": "2099-01-01"},
                headers={"X-CSRF-Token": identity["csrf"]},
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["query"], {"id": "sealed-query"})
        function_request = urlopen.call_args.args[0]
        self.assertEqual(
            json.loads(function_request.data),
            {
                "username": "prison_u_frontdesk",
                "visitDate": app.date.today().isoformat(),
            },
        )
        self.assertEqual(function_request.get_header("X-prison-app-key"), "server-only-test-key")

    def test_storage_check_rejects_non_admin_roles(self) -> None:
        class FakeConnection:
            def close(self) -> None:
                pass

        with patch.dict(
            os.environ,
            {"POSTGRES_URL": "postgresql://db-owner@example.test/prison"},
        ), patch.object(app.psycopg, "connect", return_value=FakeConnection()):
            login = self.client.post(
                "/api/login",
                json={"username": "PRISON_U_FRONTDESK", "password": "test-password"},
            )
            response = self.client.post(
                "/api/storage/check",
                json={},
                headers={"X-CSRF-Token": login.get_json()["csrf"]},
            )

        self.assertEqual(response.status_code, 403)
        self.assertIn("administrators only", response.get_json()["error"])


if __name__ == "__main__":
    unittest.main()

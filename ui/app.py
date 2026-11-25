from __future__ import annotations

import logging
import os
import secrets
import threading
import time
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import psycopg
from dotenv import load_dotenv
from flask import Flask, jsonify, render_template, request, session


ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

ROLE_USERS = {
    "PRISON_U_ADMIN": "admin",
    "PRISON_U_WARDEN": "warden",
    "PRISON_U_WARDEN2": "warden",
    "PRISON_U_FRONTDESK": "frontdesk",
    "PRISON_U_AUDITOR": "auditor",
}
VISIT_SLOTS = (
    "09:00-10:00",
    "10:00-11:00",
    "11:00-12:00",
    "14:00-15:00",
    "15:00-16:00",
    "16:00-17:00",
)
SESSION_TTL_SECONDS = 30 * 60
PAGE_SIZE_MAX = 100


def json_value(value: Any) -> Any:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    return value


@dataclass
class DbSession:
    username: str
    role: str
    connection: Any
    csrf_token: str
    last_seen: float = field(default_factory=time.monotonic)
    lock: threading.Lock = field(default_factory=threading.Lock)


class SessionRegistry:
    def __init__(self) -> None:
        self._sessions: dict[str, DbSession] = {}
        self._lock = threading.Lock()

    def add(self, db_session: DbSession) -> str:
        token = secrets.token_urlsafe(32)
        with self._lock:
            self._expire_locked()
            self._sessions[token] = db_session
        return token

    def get(self, token: str | None) -> DbSession | None:
        if not token:
            return None
        with self._lock:
            self._expire_locked()
            db_session = self._sessions.get(token)
            if db_session:
                db_session.last_seen = time.monotonic()
            return db_session

    def remove(self, token: str | None) -> None:
        if not token:
            return
        with self._lock:
            db_session = self._sessions.pop(token, None)
        if db_session:
            with db_session.lock:
                db_session.connection.close()

    def _expire_locked(self) -> None:
        now = time.monotonic()
        expired = [
            token
            for token, db_session in self._sessions.items()
            if now - db_session.last_seen > SESSION_TTL_SECONDS
        ]
        for token in expired:
            db_session = self._sessions.pop(token)
            try:
                with db_session.lock:
                    db_session.connection.close()
            except psycopg.Error:
                logging.getLogger(__name__).exception("Failed to close expired PostgreSQL session")


def create_app() -> Flask:
    app = Flask(__name__)
    configured_secret = os.environ.get("UI_SECRET_KEY", "")
    if configured_secret.startswith("change_me"):
        configured_secret = ""
    app.config.update(
        SECRET_KEY=configured_secret or secrets.token_hex(32),
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict",
        SESSION_COOKIE_SECURE=os.environ.get("UI_HTTPS", "").lower() == "true",
        MAX_CONTENT_LENGTH=16 * 1024,
    )
    app.logger.setLevel(logging.INFO)
    registry = SessionRegistry()

    def database_configured() -> bool:
        return bool(os.environ.get("POSTGRES_URL"))

    def connect(username: str, password: str) -> Any:
        return psycopg.connect(
            os.environ["POSTGRES_URL"],
            user=username.lower(),
            password=password,
            connect_timeout=10,
        )

    def current_session() -> DbSession | None:
        return registry.get(session.get("db_session"))

    def require_session() -> tuple[DbSession | None, Any | None]:
        db_session = current_session()
        if not db_session:
            session.clear()
            return None, (jsonify(error="Please sign in again."), 401)
        csrf = request.headers.get("X-CSRF-Token", "")
        if not secrets.compare_digest(csrf, db_session.csrf_token):
            return None, (jsonify(error="Invalid request token. Refresh and retry."), 403)
        return db_session, None

    def query_rows(
        db_session: DbSession,
        statement: str,
        binds: tuple[Any, ...] | None = None,
    ) -> list[dict[str, Any]]:
        with db_session.lock:
            try:
                with db_session.connection.cursor() as cursor:
                    cursor.execute(statement, binds or ())
                    columns = [column.name.lower() for column in cursor.description]
                    rows = [
                        {key: json_value(value) for key, value in zip(columns, row)}
                        for row in cursor
                    ]
                db_session.connection.commit()
                return rows
            except psycopg.Error:
                db_session.connection.rollback()
                raise

    @app.after_request
    def security_headers(response: Any) -> Any:
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "same-origin"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; style-src 'self'; script-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'"
        )
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/")
    def index() -> Any:
        return render_template("index.html")

    @app.get("/api/health")
    def health() -> Any:
        return jsonify(configured=database_configured())

    @app.post("/api/login")
    def login() -> Any:
        body = request.get_json(silent=True) or {}
        username = str(body.get("username", "")).strip().upper()
        password = body.get("password", "")
        if username not in ROLE_USERS or not isinstance(password, str) or not password:
            return jsonify(error="Use a project role account and its database password."), 400
        if not database_configured():
            return jsonify(error="PostgreSQL connection is not configured. See the setup instructions."), 503

        try:
            connection = connect(username, password)
        except psycopg.Error:
            app.logger.exception("PostgreSQL login failed for configured role account")
            return jsonify(error="Database sign-in failed. Check the role credentials and database URL."), 401

        registry.remove(session.get("db_session"))
        db_session = DbSession(
            username=username,
            role=ROLE_USERS[username],
            connection=connection,
            csrf_token=secrets.token_urlsafe(32),
        )
        session.clear()
        session["db_session"] = registry.add(db_session)
        return jsonify(username=username, role=db_session.role, csrf=db_session.csrf_token)

    @app.post("/api/logout")
    def logout() -> Any:
        db_session, error = require_session()
        if error:
            return error
        del db_session
        registry.remove(session.pop("db_session", None))
        session.clear()
        return jsonify(ok=True)

    @app.get("/api/me")
    def me() -> Any:
        db_session = current_session()
        if not db_session:
            return jsonify(authenticated=False), 401
        return jsonify(
            authenticated=True,
            username=db_session.username,
            role=db_session.role,
            csrf=db_session.csrf_token,
        )

    @app.get("/api/dashboard")
    def dashboard() -> Any:
        db_session, error = require_session()
        if error:
            return error
        try:
            stats = query_rows(
                db_session,
                """
                SELECT
                    (SELECT COUNT(*) FROM v_fac_visits
                      WHERE visit_date = CURRENT_DATE) AS visits_today,
                    (SELECT COUNT(*) FROM v_fac_visits
                      WHERE status = 'SCHEDULED') AS scheduled_visits
                """,
            )[0]
            stats["today_visits"] = query_rows(
                db_session,
                """
                SELECT slot, status, inmate_no, inmate_name, visitor_name, block_name
                  FROM v_fac_visits
                 WHERE visit_date = CURRENT_DATE
                 ORDER BY slot
                 LIMIT 6
                """,
            )
            if db_session.role != "frontdesk":
                stats["active_inmates"] = query_rows(
                    db_session,
                    "SELECT COUNT(*) AS active_inmates FROM v_fac_inmates WHERE status = 'ACTIVE'",
                )[0]["active_inmates"]
                stats["block_count"] = query_rows(
                    db_session,
                    "SELECT COUNT(*) AS block_count FROM v_fac_blocks",
                )[0]["block_count"]
            return jsonify(stats)
        except psycopg.Error:
            app.logger.exception("Dashboard query failed for %s", db_session.username)
            return jsonify(error="Could not load dashboard data. Check database grants and connection."), 503

    @app.get("/api/inmates")
    def inmates() -> Any:
        db_session, error = require_session()
        if error:
            return error
        if db_session.role == "frontdesk":
            return jsonify(error="Inmate roster is not available for this role."), 403
        page = request.args.get("page", default=1, type=int)
        if page < 1:
            return jsonify(error="Page must be 1 or greater."), 400
        offset = (page - 1) * 20
        try:
            total = query_rows(
                db_session,
                "SELECT COUNT(*) AS total FROM v_fac_inmates WHERE status = 'ACTIVE'",
            )[0]["total"]
            rows = query_rows(
                db_session,
                """
                SELECT inmate_no, full_name, block_name, risk_level, sentence_end
                  FROM v_fac_inmates
                 WHERE status = 'ACTIVE'
                 ORDER BY inmate_no
                  LIMIT %s OFFSET %s
                """,
                (20, offset),
            )
            return jsonify(rows=rows, page=page, page_size=20, total=total)
        except psycopg.Error:
            app.logger.exception("Inmate roster query failed for %s", db_session.username)
            return jsonify(error="Could not load the inmate roster."), 503

    @app.get("/api/visits")
    def visits() -> Any:
        db_session, error = require_session()
        if error:
            return error
        page = request.args.get("page", default=1, type=int)
        if page < 1:
            return jsonify(error="Page must be 1 or greater."), 400
        offset = (page - 1) * 20
        try:
            total = query_rows(db_session, "SELECT COUNT(*) AS total FROM v_fac_visits")[0]["total"]
            rows = query_rows(
                db_session,
                """
                SELECT visit_id, visit_date, slot, status, inmate_no, inmate_name,
                       visitor_name, block_name
                  FROM v_fac_visits
                 ORDER BY visit_date DESC, slot, visit_id
                  LIMIT %s OFFSET %s
                """,
                (20, offset),
            )
            return jsonify(rows=rows, page=page, page_size=20, total=total)
        except psycopg.Error:
            app.logger.exception("Visit list query failed for %s", db_session.username)
            return jsonify(error="Could not load visits."), 503

    @app.get("/api/visitors")
    def visitors() -> Any:
        db_session, error = require_session()
        if error:
            return error
        if db_session.role not in ("frontdesk", "admin", "auditor"):
            return jsonify(error="Visitor directory is not available for this role."), 403
        try:
            rows = query_rows(
                db_session,
                """
                SELECT visitor_id, full_name, id_proof_type, id_proof_masked, approval_status
                  FROM v_visitors_masked
                 WHERE approval_status IN ('APPROVED', 'BLACKLISTED')
                 ORDER BY full_name
                 LIMIT 100
                """,
            )
            return jsonify(rows=rows)
        except psycopg.Error:
            app.logger.exception("Visitor list query failed for %s", db_session.username)
            return jsonify(error="Could not load the masked visitor directory."), 503

    @app.post("/api/bookings")
    def book_visit() -> Any:
        db_session, error = require_session()
        if error:
            return error
        if db_session.role not in ("frontdesk", "admin"):
            return jsonify(error="Visit booking is not available for this role."), 403

        body = request.get_json(silent=True) or {}
        try:
            inmate_id = int(body.get("inmate_id"))
            visitor_id = int(body.get("visitor_id"))
            visit_date = date.fromisoformat(str(body.get("visit_date", "")))
            slot = str(body.get("slot", ""))
        except (TypeError, ValueError):
            return jsonify(error="Enter valid inmate and visitor IDs, a date, and a slot."), 400
        if inmate_id <= 0 or visitor_id <= 0 or slot not in VISIT_SLOTS:
            return jsonify(error="IDs must be positive and the slot must be a listed visit time."), 400

        try:
            with db_session.lock:
                with db_session.connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT status, visit_id, message FROM fn_schedule_visit(%s, %s, %s, %s)",
                        (inmate_id, visitor_id, visit_date, slot),
                    )
                    booking_status, visit_id, message = cursor.fetchone()
                db_session.connection.commit()
            return jsonify(status=booking_status, visit_id=json_value(visit_id), message=message)
        except psycopg.Error:
            with db_session.lock:
                db_session.connection.rollback()
            app.logger.exception("Visit booking call failed for %s", db_session.username)
            return jsonify(error="Visit request failed. Check the database connection and function grants."), 503

    @app.errorhandler(413)
    def request_too_large(_: Any) -> Any:
        return jsonify(error="Request is too large."), 413

    return app


app = create_app()


if __name__ == "__main__":
    app.run(
        host=os.environ.get("UI_HOST", "127.0.0.1"),
        port=int(os.environ.get("UI_PORT", "5000")),
        debug=False,
        threaded=True,
    )

# PostgreSQL Cloud Setup

The active app and schema use PostgreSQL. Neon is the suggested hosted option; a PostgreSQL-compatible provider that allows creating database roles can also work. Check the provider's current free-tier quotas before deploying.

## What is migrated

- 11 tables, synthetic seed data, constraints, indexes and 17 views.
- PL/pgSQL functions and triggers for visitor eligibility, visit booking, facility assignment, block capacity, security levels, movement history and audit logging.
- Five role-login accounts and facility-scoped views.
- Three explicit-cursor procedures and the Flask UI using psycopg.

The previous Oracle scripts remain in `sql/` as a reference. PostgreSQL equivalents for Oracle `DBMS_SCHEDULER`, `FLASHBACK TABLE`, the two-session concurrency demo and all query demos are not complete. The old 191-check Oracle run is not a PostgreSQL test result.

## 1. Create a PostgreSQL database

1. Create a PostgreSQL project on [Neon](https://neon.com/pricing) or another PostgreSQL provider.
2. Select the direct (non-pooler) connection endpoint for the database. The UI logs in as distinct PostgreSQL roles, so the endpoint must accept those role credentials.
3. Keep the provider's owner/admin connection URL private. Do not share it in chat or commit it to Git.

## 2. Configure `.env`

Copy `.env.example` to `.env` only if you do not already have one. If `.env` exists, add or update the PostgreSQL settings without overwriting unrelated local settings. `.env` is ignored by Git.

```ini
POSTGRES_CONTAINER=prison-postgres
POSTGRES_DB=prison_db
POSTGRES_PORT=5432
POSTGRES_LOCAL_PASSWORD=<strong local Docker password>
POSTGRES_DEMO_PASSWORD=<strong password for the five demo logins>
POSTGRES_ADMIN_URL=postgresql://<provider-owner>:<encoded-password>@<host>/<database>?sslmode=require
POSTGRES_URL=postgresql://<host>/<database>?sslmode=require
```

For local development, set `POSTGRES_URL=postgresql://localhost:5432/prison_db`. The UI overrides the URL's user and password with the selected role login and password entered on the sign-in screen. Keep the URL's TLS option (`sslmode=require`) for hosted databases.

## 3. Install locally or in the cloud

Docker Desktop is used to run a local PostgreSQL container; it also supplies `psql` for deployment. Start the container:

```powershell
.\scripts\start_postgres.ps1
```

Install into the local database:

```powershell
.\scripts\install_postgres.ps1
```

Install into the configured cloud database:

```powershell
.\scripts\install_postgres.ps1 -Cloud
```

The cloud installer uses `POSTGRES_ADMIN_URL` to create the five demo logins and build the schema. `POSTGRES_DEMO_PASSWORD` is assigned to those demo roles. Only run it on a new or intentionally reset project database. `-Fresh` drops every object in the target `public` schema before reinstalling.

## 4. Test and start the UI

Run the database checks locally or against the cloud target:

```powershell
.\scripts\run_postgres_tests.ps1
.\scripts\run_postgres_tests.ps1 -Cloud
```

Start the app:

```powershell
ui\.venv\Scripts\python.exe -m pip install -r ui\requirements.txt
ui\.venv\Scripts\python.exe ui\app.py
```

Open `http://127.0.0.1:5000`. The app accepts `PRISON_U_ADMIN`, `PRISON_U_WARDEN`, `PRISON_U_WARDEN2`, `PRISON_U_FRONTDESK`, and `PRISON_U_AUDITOR`, using the shared `POSTGRES_DEMO_PASSWORD` configured during installation.

## 5. Backup and security notes

- Use the provider's dashboard to review its current backup, restore, network and free-tier policies. Do not claim Oracle Flashback or Oracle backup behavior for PostgreSQL.
- For a portable backup, use `pg_dump` and test restoring it into a separate database before relying on it. Do not test destructive restores against the only copy.
- Store owner and demo passwords only in `.env` or a password manager. Never expose the owner URL to the browser or commit it.
- The UI is configured for localhost demonstration. Public hosting requires HTTPS, a production WSGI server, secret management and persistent session storage.

## 6. Legacy Oracle guide

The former Oracle instructions are retained at [Oracle_Cloud_Setup_Legacy.md](Oracle_Cloud_Setup_Legacy.md); do not use them to deploy the active PostgreSQL version.

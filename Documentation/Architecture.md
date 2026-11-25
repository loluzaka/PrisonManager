# PostgreSQL Architecture

The active database is PostgreSQL. SQL schema and routines are under `postgres/`; the Flask UI connects through psycopg using a separate PostgreSQL login for each demo role. The old Oracle implementation is retained for comparison in `sql/` and `Documentation/*_Oracle_Legacy.md`.

## Layers

```text
Browser
  └── Flask UI (CSRF, short-lived server-side sessions, role-aware routes)
       └── psycopg connections (PRISON_U_* PostgreSQL login roles)
            ├── Facility-filtered views and masked visitor views
            ├── SECURITY DEFINER functions for controlled mutations
            ├── PL/pgSQL triggers for visit rules, inmate placement, movement and audit
            └── Tables, constraints and indexes
```

The schema has 11 tables and 17 views. `postgres/003_routines_triggers.sql` holds the business functions, explicit-cursor procedures and trigger functions; `postgres/004_views.sql` defines reports and facility-scoped views; `postgres/005_security.sql` grants role privileges.

## Visit booking

1. The UI connects as `prison_u_frontdesk` (or `prison_u_admin`).
2. The backend calls `fn_schedule_visit`.
3. The function locks the inmate row and visit-slot row, checks the login's facility mapping and validates the visitor, date, weekly limit and slot capacity.
4. The visit trigger rechecks database rules, and the audit trigger records successful bookings.
5. Denials returned by the function are written to `audit_log` and returned as status codes. The client commits the function call.

PostgreSQL does not provide Oracle's autonomous-transaction pragma. A failure that raises inside a trigger is rolled back with its statement; procedure-level denied booking attempts are recorded as normal rows before returning a denial result.

## Placement and movement

The inmate trigger locks relevant block rows in a stable order and checks security level, capacity and rival placement. The transfer function locks the inmate and source/target blocks before changing `block_id`. The movement trigger records admissions and transfers, and the audit trigger protects `audit_log` from update/delete.

## PostgreSQL replacements and remaining work

PostgreSQL has no Oracle compound triggers or packages, so the active implementation uses row triggers and standalone PL/pgSQL functions. Explicit cursors are retained in the report procedures. Oracle `DBMS_SCHEDULER`, `FLASHBACK TABLE`, `PIVOT`, the 2-session concurrency demonstration, and all legacy query demos still need PostgreSQL-specific equivalents or verification; they are not claimed as ported.

## Build order

`postgres/install.sql` runs roles → schema → synthetic data → functions/triggers → views → grants. `scripts/install_postgres.ps1` provides the local and cloud entry points; use `-Fresh` only when intentionally dropping the target public schema.

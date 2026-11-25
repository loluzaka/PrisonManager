# Run and Demonstrate the Prison Management System

This is the practical runbook for starting the PostgreSQL database and Flask UI, running the checks, and demonstrating the implemented features. It uses the local database by default so the demo does not depend on cloud connectivity.

For detailed database object descriptions, see [PostgreSQL_SQL_Detailed_Report.md](PostgreSQL_SQL_Detailed_Report.md). For Neon-specific configuration, see [Cloud_Setup.md](Cloud_Setup.md).

## 1. What you need

- Windows with PowerShell.
- Docker Desktop installed and running.
- Python installed.
- Node.js/npm installed (needed to build the Realtime browser bundle).
- This repository checked out locally.

Open PowerShell in the repository root:

```powershell
cd C:\Users\Huzaifa\Documents\PrisonManagement
```

## 2. First-time local setup

Create `.env` only if you do not already have one. Do not overwrite an existing `.env`; it may contain your working settings.

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
notepad .env
```

Set your own values for at least:

```ini
POSTGRES_DB=prison_db
POSTGRES_PORT=5432
POSTGRES_LOCAL_PASSWORD=<your-local-PostgreSQL-password>
POSTGRES_DEMO_PASSWORD=<your-shared-demo-role-password>
POSTGRES_URL=postgresql://localhost:5432/prison_db
```

The demo password is shared by the five sample database logins. Use the same value at the UI sign-in screen. Keep `.env` private; do not paste its contents into chat or commit it. The local Docker database uses `POSTGRES_LOCAL_PASSWORD`; the UI demo accounts use `POSTGRES_DEMO_PASSWORD`.

If you are using Neon for a separate cloud test, keep the direct and pooled Neon connection variables private. For a local demo, `POSTGRES_URL` must point to `localhost`; the app uses it before `DATABASE_URL`.

## 3. Start and initialize local PostgreSQL

Start Docker Desktop, then start the project database:

```powershell
.\scripts\start_postgres.ps1
```

On the first install, run:

```powershell
.\scripts\install_postgres.ps1
```

This creates the demo roles, schema, synthetic seed records, PL/pgSQL routines, triggers, views, and permissions. If you have intentionally changed or damaged the local demo database and want to rebuild it, use:

```powershell
.\scripts\install_postgres.ps1 -Fresh
```

> **Warning:** `-Fresh` drops all objects in the target `public` schema. Use it only for a local database you are willing to erase. Never use it against a database containing data you need.

The sample data is synthetic: two facilities, five blocks, 50 inmates, 40 visitors, six time slots, 100 visits, and related conflict/movement records.

## 4. Build and verify the project

Install the JavaScript packages and build the browser Realtime client:

```powershell
npm.cmd install
npm.cmd run build
```

Create the Python environment and install the Flask app's dependencies:

```powershell
python -m venv ui\.venv
ui\.venv\Scripts\python.exe -m pip install -r ui\requirements.txt
```

Run the PostgreSQL schema/data assertions and tests for each of the five database roles:

```powershell
.\scripts\run_postgres_tests.ps1
```

Run the Flask unit tests:

```powershell
ui\.venv\Scripts\python.exe -m unittest discover -s ui -p test_app.py
```

The database test script checks 23 assertions, including constraints, eligibility helpers, views, trigger rejections, and audit-log protection. It then runs role checks for admin, both wardens, front desk, and auditor. The Flask unit tests do not require a live database; the database role and booking walkthrough below does.

## 5. Start the UI

In a PowerShell window:

```powershell
ui\.venv\Scripts\python.exe ui\app.py
```

Wait for Flask to report that it is serving on `http://127.0.0.1:5000`, then open that address in a browser. Keep this terminal open while using the app. Press `Ctrl+C` in it when finished.

If sign-in fails, confirm that PostgreSQL is running, the schema/roles were installed, `POSTGRES_URL` points to the local database, and the password entered is the current `POSTGRES_DEMO_PASSWORD`.

## 6. Demo accounts and role differences

Select one of these role names in the sign-in screen and enter the shared `POSTGRES_DEMO_PASSWORD`:

| Login | Demonstrate |
|---|---|
| `PRISON_U_FRONTDESK` | Today's visit dashboard, visit schedule, masked visitor directory, and visit booking. Cannot open the inmate roster or storage check. Assigned to Facility 1. |
| `PRISON_U_WARDEN` | Facility 1 inmate/visit rosters and dashboard counts. Does not have the front-desk booking or visitor-directory screen. |
| `PRISON_U_WARDEN2` | Facility 2-scoped inmate/visit rosters. Compare its results with the Facility 1 warden to show facility isolation. |
| `PRISON_U_AUDITOR` | Read-oriented dashboard, rosters, and masked visitor directory across facilities. Cannot book visits. |
| `PRISON_U_ADMIN` | Administrative visibility, booking, and—when Neon storage settings are configured—the private-storage round-trip test. |

These are demonstration database roles, not production credentials.

## 7. Suggested 8–10 minute presentation walkthrough

### A. Explain the dashboard and scope

1. Sign in as `PRISON_U_FRONTDESK`.
2. Show visit counts and today's visit schedule on **Overview**.
3. Open **Visit schedule** and use the pagination controls.
4. Open **Visitor directory** and point out that identity numbers are masked.
5. Explain that front desk has no inmate-roster link and sees only its assigned facility's data.

### B. Book an allowed visit

On **Book a visit**, enter:

- Inmate ID: `12`
- Visitor ID: `1`
- Date: a date about 30 days in the future
- Slot: `09:00-10:00`

Submit the form. In the seeded local data, inmate 12 is active in Facility 1 and visitor 1 is approved. The expected result is `BOOKED`. Refresh the overview or visit schedule to show the stored visit.

If that particular date/slot has already been used during a prior demo, choose a later date and a different slot. The database, not the browser, checks the booking rules.

### C. Show a rejected visit and audit evidence

Try a second booking with:

- Inmate ID: `12`
- Visitor ID: `36` (seeded as blacklisted)
- Date: a date about 31 days in the future
- Slot: `11:00-12:00`

The expected result is a denial such as `DENIED_BLACKLISTED`. Explain that the database function checks visitor eligibility and writes a denied-attempt audit record. The attempt does not create a visit.

Optional facility-isolation example: while still signed in as front desk, try booking for inmate ID `31` with visitor ID `1` and a future date. In the seed data, inmate 31 belongs to Facility 2. The expected result is `DENIED_FACILITY`.

### D. Compare facility roles

1. Sign out and sign in as `PRISON_U_WARDEN`.
2. Show Facility 1 rosters and dashboard.
3. Sign out and sign in as `PRISON_U_WARDEN2`.
4. Show that its records are limited to Facility 2.

The test fixtures check 33 total inmate rows/3 blocks for Facility 1 and 17 total inmate rows/2 blocks for Facility 2. The dashboard's active-inmate metric filters out transferred/released records, so it will be lower than those total roster counts.

### E. Show admin-only storage (cloud setup only)

Sign in as `PRISON_U_ADMIN`. If Neon Object Storage environment variables and the private `uploads` bucket are configured, select **Test private object storage**. It uploads a temporary object, downloads and compares it, then deletes it. A successful result confirms the round trip and cleanup.

This check is not expected to work in a local-only setup without cloud storage credentials. Do not show credentials on screen.

### F. Finish with the database objects

Use the SQL demonstration in the next section to show a view, eligibility function, cursor report, and audit rows. Explain that table constraints and triggers also reject invalid direct writes, so the rules are not dependent on the Flask form.

### What this UI walkthrough does not cover

The local UI exposes dashboards, rosters, masked visitors, role-aware navigation, and visit booking. It does not have a separate screen for every database operation. To explain the full SQL scope, also show the relevant definitions and selected results from [PostgreSQL_SQL_Detailed_Report.md](PostgreSQL_SQL_Detailed_Report.md):

- The three procedures and the explicit/implicit cursor patterns.
- The eligibility, registration, visitor-status, conflict, rivalry, transfer, and maintenance functions.
- The visit and placement validation triggers, audit triggers, and append-only audit protection.
- The remaining report views, keys/constraints, and the ten indexes.
- Role grants and facility-scoped views; use the two wardens to compare facilities.

The SQL assertion and role-test scripts are useful for showing guard-rail evidence, but they are not a live UI for every operation and do not test every function individually. Do not describe unported Oracle features or the uninstalled cloud schema as completed PostgreSQL features.

## 8. Optional SQL demonstration

Open a second PowerShell window and connect to the local database as its owner:

```powershell
docker exec -it prison-postgres psql -U postgres -d prison_db
```

If `POSTGRES_CONTAINER` or `POSTGRES_DB` in `.env` has a non-default value, replace `prison-postgres` or `prison_db` accordingly.

At the `prison_db=#` prompt, try:

```sql
-- View active storage capacity and occupancy.
SELECT block_name, capacity, occupied, free_beds, occupancy_flag
FROM v_block_occupancy
ORDER BY block_id;

-- Visitor 1 is approved for active inmate 12 in the seed data.
SELECT fn_is_visitor_eligible(1, 12);

-- Visitor 36 is blacklisted in the seed data.
SELECT fn_is_visitor_eligible(36, 12);

-- Display the daily roster through the explicit-cursor procedure.
CALL pr_daily_roster(CURRENT_DATE);

-- Display block counts through another explicit-cursor procedure.
CALL pr_block_occupancy();

-- Show recent audit actions.
SELECT action_type, table_name, record_id, changed_by, changed_at, details
FROM audit_log
ORDER BY changed_at DESC
LIMIT 10;
```

`CALL` procedures print rows as PostgreSQL notices in the terminal. The daily roster and occupancy procedures demonstrate declared cursors with `OPEN`, `FETCH`, and `CLOSE`. `pr_upcoming_releases(30)` demonstrates a PL/pgSQL query loop.

To demonstrate the roster `refcursor`, keep all commands in the same SQL session and transaction:

```sql
BEGIN;
SELECT fn_roster_refcursor(CURRENT_DATE);
FETCH ALL FROM roster_cursor;
COMMIT;
```

The `refcursor` exists only for that session/transaction. Booking via the UI is preferred for the successful/denied booking demo because the database function also checks `session_user` against `staff_access`; a database-owner login is not one of the assigned demo staff accounts.

If you want to show a state-changing function without keeping the change, use a local demo database and wrap the call in a transaction that you roll back:

```sql
BEGIN;
SELECT * FROM fn_transfer_inmate(12, 2, 'Presentation-only transfer');
ROLLBACK;
```

Check `v_block_occupancy` first if the transfer returns a capacity denial. The rollback also undoes the movement and audit rows produced by a successful transfer. Use the same `BEGIN`/`ROLLBACK` pattern for other write-function demonstrations, and never run a destructive experiment against data you need to keep.

Exit `psql` with:

```sql
\q
```

## 9. Neon/cloud features: what is and is not ready

The repository is configured for Neon Functions, Realtime, and private Object Storage. Function health and the private-storage round trip were previously verified. However, the latest recorded check found no project tables on the Neon production branch, and the schema installer could not reach its PostgreSQL endpoint from the environment. Therefore, use the local PostgreSQL setup above for the complete database/UI demonstration unless cloud schema installation has since been completed and tested.

If you later prepare a separate cloud demo branch/database:

1. Confirm the Neon project, branch, and database target before running any installer.
2. Keep the owner/direct URL, pooled app URL, demo password, and Function secrets only in the ignored `.env`.
3. Apply the declared Neon service configuration and build with the commands in [Cloud_Setup.md](Cloud_Setup.md).
4. Install and test the schema using `.\scripts\install_postgres.ps1 -Cloud` and `.\scripts\run_postgres_tests.ps1 -Cloud` only after confirming the target is disposable/test data and the direct endpoint is reachable.
5. Do not use `-Fresh` on a cloud database with data to preserve.
6. Only claim live Realtime visit updates after a successful login against the installed cloud schema and a verified subscription.

The Neon health/storage checks do not prove that the PostgreSQL schema, roles, booking flow, or Realtime data feed are working; demonstrate those separately.

## 10. Troubleshooting checklist

- **PowerShell says script execution is disabled:** allow scripts only in the current PowerShell process, then retry. This does not change the machine-wide policy and resets when the process closes:

  ```powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
  .\scripts\start_postgres.ps1
  ```

  Alternatively, run just this script in a one-off process:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_postgres.ps1
  ```

  Do not set `Unrestricted` or change `LocalMachine` policy for this project. If an organization-managed policy blocks the process-scoped option, use an approved terminal or ask the administrator.
- **Docker is unavailable:** start Docker Desktop, then rerun `.\scripts\start_postgres.ps1`.
- **PostgreSQL is not ready:** check `docker ps` and `docker logs prison-postgres`; ensure port 5432 is not already occupied.
- **Database login fails:** verify `.env` `POSTGRES_URL`, confirm the role was installed, and use the current `POSTGRES_DEMO_PASSWORD`.
- **App says PostgreSQL is not configured:** check that `POSTGRES_URL` or `DATABASE_URL` exists in `.env`. For a local demo, set `POSTGRES_URL=postgresql://localhost:5432/prison_db`.
- **Booking returns a denial:** read the status/message shown by the app. Check the visitor approval/conflict, inmate status/facility, date, weekly limit, duplicate booking, and slot capacity.
- **Realtime says Unavailable:** local setup does not provide Neon Realtime. In a cloud setup, verify the deployed Function, Realtime service, environment variables, and installed database schema.
- **Storage check fails:** use an administrator role and verify the private bucket and its S3 environment settings. The check is not a local database feature.
- **Only need to stop the local database:** run `docker stop prison-postgres` (replace the name if configured otherwise).

## 11. Suggested closing explanation

> “The Flask interface is the demonstration layer. PostgreSQL stores the data and applies the actual rules through constraints, functions, triggers, roles, and cursor-based reports. We can show an allowed and denied booking, facility-specific access, masked visitor IDs, movement/audit history, and the roster/occupancy cursors. The local PostgreSQL flow is the complete demo path; Neon service checks are separate from the cloud database schema, which must be installed and verified before claiming a live cloud database demo.”

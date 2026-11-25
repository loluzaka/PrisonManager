# Prison Visitor & Inmate Roster Management System

DBMS Lab (24B15CS213) · Semester III · Session 2026-27 · Batch B9
Team: Huzayfa Yousuf (2501030340), Saksham Dixit (2501030342), Saksham Azad (2501030367)
Submitted to: Mr. Abhishek Chaudhary, Ms. Aarti Goel

> All data is **synthetic**. No real inmate, visitor or identity document appears anywhere in this repository.

## 1. Problem statement
A prison must know, at every moment, **who is housed where**, **who may visit whom**, and **who did what**. Paper rosters allow double-booked visiting slots,
visits by blacklisted people or by victims' relatives, overfilled cells and inmates moved without a record. This project puts those rules **inside the database**, so
they hold no matter which program or person touches the data, and keeps a tamper-proof trail of every decision.

## 2. Objectives
1. A properly normalised (BCNF) relational schema with full integrity constraints.
2. Business rules enforced by **triggers**, **stored procedures** and **functions** (visit eligibility, capacity, security levels, slot limits).
3. **Explicit cursors** that process many records row by row to produce the daily roster, block occupancy and release reports.
4. Transactions, locking and concurrency control, shown with a two-session demonstration.
5. Role-based access, masking, facility isolation and an append-only audit log.
6. Deployment to a **cloud database** with backup/restore and secure access.
7. Repeatable seed data, an automated test suite and complete documentation.

## 3. DBMS and technologies
**PostgreSQL (SQL + PL/pgSQL)** is now the active database. The former Oracle implementation is retained in `sql/` and `tests/` as a historical reference; it is not used by the current UI or PostgreSQL setup scripts.

| Purpose | Tool |
|---|---|
| Local database | PostgreSQL 17 in Docker (`postgres:17-alpine`) |
| Cloud target | Neon PostgreSQL free tier (optional; configure your own database URL) |
| Client | `psql` in the PostgreSQL Docker container; any PostgreSQL client also works |
| Python driver | psycopg 3 |
| Automation | PowerShell scripts in `scripts/` |

## 4. Current PostgreSQL status
The PostgreSQL port currently builds 11 tables, 17 views, business functions, triggers, role grants, explicit cursor procedures, and synthetic seed data. Its current database checks and remaining migration work are tracked in [Documentation/Feature_Traceability.md](Documentation/Feature_Traceability.md).

**Validation status:** the latest PostgreSQL install passed 23 database checks and all five role checks locally. The UI smoke tests and live local PostgreSQL integration checks passed. The previous 191-check log is an Oracle-only historical run; it is not evidence that the PostgreSQL port has equivalent feature coverage. A live Neon deployment has not been configured.

## 5. Repository layout
```
postgres/       active PostgreSQL schema, seed, PL/pgSQL routines, views, roles and tests
sql/            historical Oracle SQL/PLSQL source (not used by the active app)
tests/          historical Oracle test suite
scripts/        PostgreSQL: start_postgres, install_postgres, run_postgres_tests;
                Oracle scripts are retained for reference
ui/             Flask + psycopg UI (role-based dashboard and visit booking)
Documentation/  Current PostgreSQL docs plus explicitly named Oracle legacy references;
                Help_Files/ contains beginner guides to the historical Oracle files
.vscode/        Python interpreter default for the UI environment
.env.example    template for local/cloud settings (copy to .env, which is git-ignored)
```

## 6. Web UI

The role-based UI provides a facility-scoped dashboard and rosters, masked visitor details, and visit booking through the PostgreSQL `fn_schedule_visit` function.
The backend connects using a PostgreSQL role account; browser code never connects directly to the database.

Configure `POSTGRES_URL` and `POSTGRES_DEMO_PASSWORD` in the git-ignored `.env`, then run:

```powershell
python -m venv ui\.venv
ui\.venv\Scripts\python.exe -m pip install -r ui\requirements.txt
ui\.venv\Scripts\python.exe ui\app.py
```

Open `http://127.0.0.1:5000`. See [Documentation/Cloud_Setup.md](Documentation/Cloud_Setup.md) for local and Neon configuration.
Run the UI smoke checks with `ui\.venv\Scripts\python.exe -m unittest discover -s ui -p test_app.py`.

## 7. Setup – local PostgreSQL (Windows, PowerShell)
Copy `.env.example` to `.env` if needed. Set `POSTGRES_LOCAL_PASSWORD` and `POSTGRES_DEMO_PASSWORD` to strong values; keep `.env` private.
Prerequisite: Docker Desktop running.

```powershell
cd C:\Users\Huzaifa\Documents\PrisonManagement
.\scripts\start_postgres.ps1           # starts PostgreSQL 17 in Docker
.\scripts\install_postgres.ps1         # creates demo roles, schema, routines, views and seed data
.\scripts\install_postgres.ps1 -Fresh  # DROPS the target public schema, then rebuilds it
.\scripts\run_postgres_tests.ps1       # runs database checks and checks each database role
```

The installer and test runner use `psql` inside the container. PostgreSQL seed data is synthetic and can be rebuilt with `-Fresh`.

## 8. Setup – cloud database
Create a PostgreSQL database with a provider such as Neon, put its owner connection URL in `POSTGRES_ADMIN_URL`, and set the credential-free host/database URL in `POSTGRES_URL`. Then run:

```powershell
.\scripts\start_postgres.ps1        # local container also supplies the psql client
.\scripts\install_postgres.ps1 -Cloud
.\scripts\run_postgres_tests.ps1 -Cloud
```

See [Documentation/Cloud_Setup.md](Documentation/Cloud_Setup.md) before deploying. It is not yet a verified live cloud deployment.

The original Oracle design documents and scripts remain as references; Oracle-specific features such as `DBMS_SCHEDULER`, `FLASHBACK TABLE`, and `PIVOT` have not all been replaced with PostgreSQL equivalents yet.

## 10. Documentation map
* [Documentation/Help_Files/File_Index.md](Documentation/Help_Files/File_Index.md) – a beginner-friendly help file for **every** project file (keywords, walkthrough, examples, viva questions)
* [Documentation/Architecture.md](Documentation/Architecture.md), [ER_Diagram.md](Documentation/ER_Diagram.md), [Data_Dictionary.md](Documentation/Data_Dictionary.md)
* [Documentation/Testing_Guide.md](Documentation/Testing_Guide.md), [Cloud_Setup.md](Documentation/Cloud_Setup.md), [Feature_Traceability.md](Documentation/Feature_Traceability.md)

## 11. Original work division

This division describes the team's original Oracle-era feature allocation; it is not a claim that every feature has been ported to PostgreSQL. See the current [feature traceability](Documentation/Feature_Traceability.md) for verified migration status.

| Member | Area |
|---|---|
| Member 1 | Schema, constraints, indexes, DML, queries, seed data, pagination (F1-F5, F7-F11, F33, F36) |
| Member 2 | Triggers, procedures, functions, cursors, audit, exceptions, transactions (F13-F24) |
| Member 3 | Views, reports, roles, security, cloud, backup, tests, documentation, PIVOT report, UI (F6, F12, F25-F32, F34-F37) |

All three work on **one shared schema**; the file headers state the owner of every script.

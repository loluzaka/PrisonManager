# PostgreSQL Testing Guide

## Current PostgreSQL results

- Database install: 23 checks passed on a temporary local PostgreSQL 17 database.
- Five role accounts: facility views returned 33 and 17 inmates for the two wardens; the front-desk role successfully booked a visit without direct access to inmate/visitor base tables.
- UI smoke suite: 5 tests passed.
- Live local UI integration: PostgreSQL login, dashboard, paginated roster, visitor masking, front-desk access control, visit booking and logout passed.
- Live Neon integration: not configured or tested.

The 191-check report at `Documentation/Test_Results/latest_test_run.log` is an earlier Oracle-only run. The old Oracle testing guide is [Testing_Guide_Oracle_Legacy.md](Testing_Guide_Oracle_Legacy.md).

## Run locally (Windows / PowerShell)

Set `POSTGRES_LOCAL_PASSWORD` and `POSTGRES_DEMO_PASSWORD` in the git-ignored `.env`, then:

```powershell
.\scripts\start_postgres.ps1
.\scripts\install_postgres.ps1 -Fresh
.\scripts\run_postgres_tests.ps1
ui\.venv\Scripts\python.exe -m unittest discover -s ui -p test_app.py
```

`-Fresh` drops the `public` schema in the selected database. Use it only when you intend to rebuild that database.

## Run against a hosted PostgreSQL database

Set `POSTGRES_ADMIN_URL` and `POSTGRES_URL` as described in [Cloud_Setup.md](Cloud_Setup.md), then run:

```powershell
.\scripts\start_postgres.ps1
.\scripts\install_postgres.ps1 -Cloud
.\scripts\run_postgres_tests.ps1 -Cloud
```

This connects from the local Docker container to the hosted service. It does not imply the hosted checks have passed; run them and retain the actual output.

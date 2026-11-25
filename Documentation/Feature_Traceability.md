# PostgreSQL Feature Traceability

This is the status of the **active PostgreSQL port**. The previous Oracle matrix is retained in [Feature_Traceability_Oracle_Legacy.md](Feature_Traceability_Oracle_Legacy.md). Do not treat the Oracle test log as evidence for PostgreSQL.

| Area | PostgreSQL implementation | Current evidence | Status |
|---|---|---|---|
| Relational schema, constraints, indexes | `postgres/001_schema.sql` | 11 tables, 11 primary keys, 10 indexes checked | Implemented and locally checked |
| Synthetic data | `postgres/002_seed.sql` | 50 inmates, 40 visitors, 100 visits, 5 blocks, 8 conflicts, 58 movements | Implemented and locally checked |
| Business functions and triggers | `postgres/003_routines_triggers.sql` | Eligibility, visit limits, placement, movement and append-only audit checks | Implemented; 23 local SQL checks pass |
| Cursor reports | `postgres/003_routines_triggers.sql` | Daily roster and block occupancy use explicit PL/pgSQL cursors | Implemented |
| Views and reports | `postgres/004_views.sql` | 17 views; visitor ID masking and facility-filtered views | Implemented; role-scope checked locally |
| Database roles | `postgres/00_roles.sql`, `postgres/005_security.sql` | Five login accounts, four permission groups, restricted front-desk access | Implemented; local role tests pass |
| Flask UI | `ui/app.py`, `ui/test_app.py` | psycopg login, scoped dashboard/rosters, masked visitors, visit booking | Five UI smoke tests pass; live DB route test pending |
| Automated PostgreSQL checks | `postgres/tests.sql`, `postgres/tests_roles.sql`, `scripts/run_postgres_tests.ps1` | 23 database assertions and role tests | Local PostgreSQL validation passed |
| Cloud deployment | `scripts/install_postgres.ps1`, `Documentation/Cloud_Setup.md` | Neon setup is documented | Not run against a real cloud database |
| Advanced SQL demos | Historical files in `sql/` | Oracle `PIVOT`, query demos and pagination not yet ported to PostgreSQL | Pending |
| Nightly job and recovery | Historical Oracle implementation only | No PostgreSQL scheduler or provider restore demo yet | Pending |
| Concurrency demonstration | Historical Oracle scripts only | PostgreSQL-specific two-session test not yet ported | Pending |

The historical 191-check result is in [latest_test_run.log](Test_Results/latest_test_run.log) and applies only to the Oracle version run in November 2026.

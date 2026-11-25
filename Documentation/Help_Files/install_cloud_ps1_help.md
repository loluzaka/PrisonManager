# Help: `install_cloud.ps1`

## 1. File overview

* **Exact filename:** `install_cloud.ps1`
* **Location:** `scripts/`
* **Purpose:** Deploys the project to an Oracle Autonomous Database using a wallet: copies the wallet into the client container, creates users as ADMIN, builds the schema as PRISON_OWNER and runs the connection check.
* **Feature(s):** F29 (cloud deployment), F32 (secure cloud access)
* **Member responsibility:** Member 3 (integration, cloud and tests)
* **Role in the system:** Automation of the build and test workflow on Windows PowerShell.
* **Execution order:** After the manual cloud setup in `Cloud_Setup.md`.

## 2. Required database objects and dependencies

* **STATUS: PREPARED, NEVER RUN against a real cloud database.**
* **Needs:** `.env` values `TNS_ADMIN` (unzipped wallet folder), `PRISON_CLOUD_TNS`, `PRISON_CLOUD_ADMIN_PASSWORD`, `PRISON_CLOUD_OWNER_PASSWORD`, `PRISON_CLOUD_DEMO_PASSWORD`; the local container as a SQL*Plus client.
* **Runs:** `00_admin_setup.sql` as ADMIN, optional `99_drop_all.sql`, `run_all.sql` as PRISON_OWNER, `cloud/connection_check.sql`.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

This file is PowerShell, not SQL, so there are no SQL keywords. PowerShell ideas used: `param(...)` (command-line switches), `. file.ps1` ("dot-sourcing": run another script in the current scope so its functions become available), `$ErrorActionPreference = 'Stop'` (turn errors into exceptions), `docker exec` (run a command inside the container), pipes (`|`), `ForEach-Object`, `Start-Job` (a background worker), `Out-Null` (discard output), `exit <n>` (return a code).

## 4. Tables and columns involved

No tables are touched by the script itself; it launches SQL*Plus scripts that do.

## 5. Walkthrough

1. Refuse to start if any variable is missing or still a `change_me`/placeholder value.
2. `docker cp` the wallet to `/tmp/wallet` in the container and rewrite `?/network/admin` in `sqlnet.ora` to that path.
3. `Invoke-CloudSql` = `docker exec -e TNS_ADMIN=/tmp/wallet ... sqlplus user/pwd@<service alias> @script`.
4. ADMIN creates users (`00_admin_setup.sql`), PRISON_OWNER builds (`run_all.sql`), then the connection check prints the evidence.
Passwords come from `.env`; nothing secret is stored in the repository.

## 6. Actual execution example

Not available: no cloud database existed during development. Expected on success: the same install messages as locally, then the `connection_check.sql` table with `network protocol tcps`.

## 7. Data flow and integration

```
 .env + wallet ─► docker cp ─► sqlplus (TLS, wallet) ─► Autonomous Database ─► users, schema, data
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `Set TNS_ADMIN in .env first` | Placeholder values | Edit `.env` (see `.env.example`). |
| `ORA-12170 TNS connect timeout` | IP not on the ACL | Add your IP in the console. |
| `ORA-28759` | sqlnet.ora path | The script rewrites it; check the wallet folder is complete. |
| `ORA-01017` | Wrong password / quoting | Letters and digits only. |

## 9. Viva questions and answers

**Q1. Why separate ADMIN and PRISON_OWNER?**  
The administrative account is used once; the application owner has only the needed rights (F32).

**Q2. Where do passwords live?**  
In `.env` / a password manager, never in Git or SQL files.

**Q3. What does the wallet contain?**  
Certificates and connection aliases for mutual-TLS access.

## 10. Important practical commands

```
.\scripts\install_cloud.ps1
.\scripts\install_cloud.ps1 -Fresh
docker exec -e TNS_ADMIN=/tmp/wallet prison-oracle tnsping prisondb_medium
```

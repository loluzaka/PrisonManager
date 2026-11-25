# Help: `start_local_db.ps1`

## 1. File overview

* **Exact filename:** `start_local_db.ps1`
* **Location:** `scripts/`
* **Purpose:** Creates or starts the local Oracle Database Free container, mounts the project at /prison and waits until the database accepts connections.
* **Feature(s):** F29 (local stand-in for the cloud database)
* **Member responsibility:** Member 3 (integration, cloud and tests)
* **Role in the system:** Automation of the build and test workflow on Windows PowerShell.
* **Execution order:** First step of the local workflow.

## 2. Required database objects and dependencies

* **Needs:** Docker Desktop running; image `gvenzl/oracle-free:slim-faststart` (about 6.5 GB on disk; downloaded on first use).
* **Uses:** `common.ps1`.
* **Creates:** container `prison-oracle`, port 1521.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

This file is PowerShell, not SQL, so there are no SQL keywords. PowerShell ideas used: `param(...)` (command-line switches), `. file.ps1` ("dot-sourcing": run another script in the current scope so its functions become available), `$ErrorActionPreference = 'Stop'` (turn errors into exceptions), `docker exec` (run a command inside the container), pipes (`|`), `ForEach-Object`, `Start-Job` (a background worker), `Out-Null` (discard output), `exit <n>` (return a code).

## 4. Tables and columns involved

No tables are touched by the script itself; it launches SQL*Plus scripts that do.

## 5. Walkthrough

1. `Initialize-Env` (creates `.env` if needed).
2. `docker ps -a --filter name=...`: no container -> `docker run -d --name prison-oracle -p 1521:1521 -e ORACLE_PASSWORD=<sys pwd> -v <project>:/prison gvenzl/oracle-free:slim-faststart`; stopped -> `docker start`; running -> message.
3. Poll `healthcheck.sh` inside the container every 5 s (up to 90 times) until it returns 0, then print *Database is ready.*

## 6. Actual execution example

Real output of the first start: `Created ...\.env ...` / `Creating container prison-oracle ...` / `Waiting for the database ...` / `Database is ready.`

## 7. Data flow and integration

```
 docker run ──► Oracle FREE (CDB + pluggable DB FREEPDB1) ──► healthcheck ──► ready
 project folder ◄──mounted at──► /prison (SQL*Plus reads /prison/sql/*.sql)
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `failed to connect to the docker API` | Docker Desktop not running | Start Docker Desktop. |
| `unexpected EOF` while pulling | Network drop during the large download | Run `docker pull gvenzl/oracle-free:slim-faststart` again; finished layers are reused. |
| Port 1521 already in use | Another Oracle | Change `PRISON_DB_PORT` in `.env` and delete the container. |
| Never becomes ready | First start unpacks files | Wait; check `docker logs prison-oracle`. |

## 9. Viva questions and answers

**Q1. Why a container?**  
Reproducible Oracle without installing it; same SQL/PLSQL as the cloud service.

**Q2. Why mount the project folder?**  
So SQL*Plus inside the container can run the scripts directly.

## 10. Important practical commands

```
.\scripts\start_local_db.ps1
docker ps
docker logs prison-oracle --tail 20
docker stop prison-oracle
```

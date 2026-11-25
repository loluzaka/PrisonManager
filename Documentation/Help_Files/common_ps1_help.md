# Help: `common.ps1`

## 1. File overview

* **Exact filename:** `common.ps1`
* **Location:** `scripts/`
* **Purpose:** Shared helpers: creates `.env` with random passwords on first run, loads it into the environment and provides `Invoke-LocalSql` to run SQL*Plus inside the container.
* **Feature(s):** F29, F32 (credentials from .env, never from the repo)
* **Member responsibility:** Member 3 (integration, cloud and tests)
* **Role in the system:** Automation of the build and test workflow on Windows PowerShell.
* **Execution order:** Dot-sourced by every other script.

## 2. Required database objects and dependencies

* **Needs:** Docker container `prison-oracle` running (for `Invoke-LocalSql`).
* **Creates:** `.env` (git-ignored).
* **Used by:** `start_local_db.ps1`, `install.ps1`, `run_tests.ps1`, `concurrency_demo.ps1`, `install_cloud.ps1`.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

This file is PowerShell, not SQL, so there are no SQL keywords. PowerShell ideas used: `param(...)` (command-line switches), `. file.ps1` ("dot-sourcing": run another script in the current scope so its functions become available), `$ErrorActionPreference = 'Stop'` (turn errors into exceptions), `docker exec` (run a command inside the container), pipes (`|`), `ForEach-Object`, `Start-Job` (a background worker), `Out-Null` (discard output), `exit <n>` (return a code).

## 4. Tables and columns involved

No tables are touched by the script itself; it launches SQL*Plus scripts that do.

## 5. Walkthrough

* `New-RandomPassword` - letter first (Oracle rule) + 14 random letters/digits + `9x`; no special characters so connect strings stay simple.
* `Initialize-Env` - if `.env` does not exist, writes container name, port, service and three random passwords; then reads each `KEY=VALUE` into the process environment.
* `Get-Setting name default` - reads an environment value.
* `Invoke-LocalSql` - with `-Script` runs `sqlplus @script args` in `/prison/sql` inside the container; with `-Inline` sends SQL text as **base64** (`echo ... | base64 -d | sqlplus`), which avoids the UTF-8 byte-order mark that PowerShell 5.1 otherwise puts in front of piped text (SP2-0734 error found during testing). Throws if SQL*Plus returns a non-zero code. Note: SQL*Plus returns 0 even after a failed statement unless the script has `WHENEVER SQLERROR EXIT`.

## 6. Actual execution example

First run prints `Created ...\.env with random passwords (git-ignored).` Later runs print nothing.

## 7. Data flow and integration

```
 .env  <-- Initialize-Env --> process environment --> Get-Setting --> Invoke-LocalSql --> docker exec --> sqlplus
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `Cannot find path ... .env` | Script run from another directory | It uses `$PSScriptRoot`, so run it by full path. |
| `SP2-0734: unknown command beginning "﻿SELECT"` | BOM in piped text | Use `-Inline` (base64) as implemented. |
| `No such container` | Database container not created | Run `start_local_db.ps1`. |
| `running scripts is disabled on this system` | PowerShell execution policy | `powershell -ExecutionPolicy Bypass -File ...` |

## 9. Viva questions and answers

**Q1. Why is `.env` not committed?**  
It holds passwords; `.gitignore` excludes it and `.env.example` documents the keys.

**Q2. Why random passwords?**  
No default credentials to leak or guess.

## 10. Important practical commands

```
. .\scripts\common.ps1; Initialize-Env
Get-Setting 'PRISON_OWNER_PASSWORD'
Invoke-LocalSql -User prison_owner -Password (Get-Setting PRISON_OWNER_PASSWORD) -Inline "SELECT COUNT(*) FROM inmates;"
```

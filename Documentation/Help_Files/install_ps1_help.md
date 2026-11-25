# Help: `install.ps1`

## 1. File overview

* **Exact filename:** `install.ps1`
* **Location:** `scripts/`
* **Purpose:** Builds the whole schema on the local container in three steps; options `-Fresh` (drop first) and `-WithDemos` (also run demo/report scripts).
* **Feature(s):** F29 (deployment), F4 (repeatable setup)
* **Member responsibility:** Member 3 (integration, cloud and tests)
* **Role in the system:** Automation of the build and test workflow on Windows PowerShell.
* **Execution order:** After `start_local_db.ps1`.

## 2. Required database objects and dependencies

* **Runs:** `00_admin_setup.sql` as SYSTEM, optional `99_drop_all.sql`, `run_all.sql` as PRISON_OWNER, optional demos 12-16 and 19.
* **Uses:** `common.ps1`, `.env`.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

This file is PowerShell, not SQL, so there are no SQL keywords. PowerShell ideas used: `param(...)` (command-line switches), `. file.ps1` ("dot-sourcing": run another script in the current scope so its functions become available), `$ErrorActionPreference = 'Stop'` (turn errors into exceptions), `docker exec` (run a command inside the container), pipes (`|`), `ForEach-Object`, `Start-Job` (a background worker), `Out-Null` (discard output), `exit <n>` (return a code).

## 4. Tables and columns involved

No tables are touched by the script itself; it launches SQL*Plus scripts that do.

## 5. Walkthrough

1. **Users:** `00_admin_setup.sql` as SYSTEM with the owner and demo passwords as arguments.
2. **-Fresh:** `99_drop_all.sql` as PRISON_OWNER.
3. **Build:** `run_all.sql` as PRISON_OWNER.
4. **-WithDemos:** runs `12_dml_demo`, `13`, `14`, `15`, `16_reports`, `19_transactions_demo` and prints each output.

## 6. Actual execution example

Real run: `== 1/3 Creating schema owner ... ==` ... `*** run_all.sql complete ***` ... `Install finished.` (about a minute). Demo output of a `-Fresh -WithDemos` run is saved in `Documentation/Test_Results/demo_output.log`.

## 7. Data flow and integration

```
 00 (SYSTEM) -> [99 drop] -> run_all.sql (01..11,17,18) -> [demos 12..19]
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Install stops with an ORA error | `WHENEVER SQLERROR EXIT FAILURE` in run_all.sql | Fix the cause, then `install.ps1 -Fresh`. |
| `ORA-00955` name already used | Schema already built | Use `-Fresh`. |
| `SQL*Plus exited with code 1` | Any failing script | Read the last ORA- lines above it. |

## 9. Viva questions and answers

**Q1. How do you rebuild from scratch?**  
`install.ps1 -Fresh` (drops all objects and rebuilds).

**Q2. Why separate admin and owner steps?**  
Least privilege: the DBA account is used once; everything else runs as the schema owner.

## 10. Important practical commands

```
.\scripts\install.ps1
.\scripts\install.ps1 -Fresh
.\scripts\install.ps1 -Fresh -WithDemos
```

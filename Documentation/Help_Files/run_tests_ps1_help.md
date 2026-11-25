# Help: `run_tests.ps1`

## 1. File overview

* **Exact filename:** `run_tests.ps1`
* **Location:** `scripts/`
* **Purpose:** Runs the complete automated test suite: re-seed, role tests as five users, re-seed, main suite, concurrency demo; saves a log and returns exit code 1 on any failure.
* **Feature(s):** F34 (test suite)
* **Member responsibility:** Member 3 (integration, cloud and tests)
* **Role in the system:** Automation of the build and test workflow on Windows PowerShell.
* **Execution order:** After `install.ps1`.

## 2. Required database objects and dependencies

* **Runs:** `04_seed_data.sql`, `tests/31_test_roles.sql` (x5 users), `tests/30_test_suite.sql`, `scripts/concurrency_demo.ps1`.
* **Writes:** `Documentation/Test_Results/latest_test_run.log`.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

This file is PowerShell, not SQL, so there are no SQL keywords. PowerShell ideas used: `param(...)` (command-line switches), `. file.ps1` ("dot-sourcing": run another script in the current scope so its functions become available), `$ErrorActionPreference = 'Stop'` (turn errors into exceptions), `docker exec` (run a command inside the container), pipes (`|`), `ForEach-Object`, `Start-Job` (a background worker), `Out-Null` (discard output), `exit <n>` (return a code).

## 4. Tables and columns involved

No tables are touched by the script itself; it launches SQL*Plus scripts that do.

## 5. Walkthrough

1. Re-seed. 2. For each of FRONTDESK, AUDITOR, WARDEN, WARDEN2, ADMIN run the role tests (`Run-Container`). 3. Re-seed again (the front-desk test booked a visit). 4. Main suite as owner. 5. Concurrency demo (`-Quiet`, returns the CONCURRENCY lines). 6. Save all lines to the log, print `TEST|`, `SUMMARY|` and `CONCURRENCY|` lines (red for FAIL), print totals; `exit 1` if any FAIL.

## 6. Actual execution example

Last recorded run: `Total checks: 191   Failed: 0` (189 TEST lines + 2 CONCURRENCY lines; the 138-check main suite and 51 role checks). Two main-suite checks and one role check have since been added, so the next run should report 194 total checks. The runner also writes the aggregate `SUMMARY|passed=...|failed=...|total=...` line to the log.

## 7. Data flow and integration

```
 seed ─► role tests ─► seed ─► main suite ─► concurrency ─► latest_test_run.log ─► exit code
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Exit code 1 | At least one FAIL | Open the log and search for `|FAIL`. |
| Concurrency lines FAIL | Container too slow / sessions did not overlap | Re-run; increase the hold time in `concurrency_demo.ps1`. |
| Role tests all DENIED | Roles not installed | Run `install.ps1`. |

## 9. Viva questions and answers

**Q1. Why re-seed twice?**  
The role tests change data; the main suite must start from the known state.

**Q2. How do CI-style pass/fail results work?**  
Non-zero exit code when any test fails.

## 10. Important practical commands

```
.\scripts\run_tests.ps1
Select-String Documentation\Test_Results\latest_test_run.log -Pattern '\|FAIL'
Get-Content Documentation\Test_Results\latest_test_run.log -Tail 5
```

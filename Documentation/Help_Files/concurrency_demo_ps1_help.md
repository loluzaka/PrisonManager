# Help: `concurrency_demo.ps1`

## 1. File overview

* **Exact filename:** `concurrency_demo.ps1`
* **Location:** `scripts/`
* **Purpose:** Runs two SQL*Plus sessions in parallel to fight for the last place in a visit slot, first without locking (NAIVE), then with `sp_schedule_visit` (SAFE).
* **Feature(s):** F24 (concurrency control)
* **Member responsibility:** Member 3 (integration, cloud and tests)
* **Role in the system:** Automation of the build and test workflow on Windows PowerShell.
* **Execution order:** Standalone demo or step 4 of `run_tests.ps1`.

## 2. Required database objects and dependencies

* **Runs:** `sql/20_concurrency_setup.sql` (SETUP / CHECK / CLEANUP) and two copies of `sql/21_concurrency_session.sql`.
* **Uses:** `common.ps1`, `Start-Job`.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

This file is PowerShell, not SQL, so there are no SQL keywords. PowerShell ideas used: `param(...)` (command-line switches), `. file.ps1` ("dot-sourcing": run another script in the current scope so its functions become available), `$ErrorActionPreference = 'Stop'` (turn errors into exceptions), `docker exec` (run a command inside the container), pipes (`|`), `ForEach-Object`, `Start-Job` (a background worker), `Out-Null` (discard output), `exit <n>` (return a code).

## 4. Tables and columns involved

No tables are touched by the script itself; it launches SQL*Plus scripts that do.

## 5. Walkthrough

For each mode: SETUP (4 of 5 places taken) -> start clerk A (inmate 6, visitor 25, delay 0, hold 6 s) and clerk B (inmate 7, visitor 26, delay 2, hold 0) as **PowerShell background jobs**, each running `docker exec ... sqlplus @21_concurrency_session.sql` -> wait for both -> print their output -> CHECK -> CLEANUP. Finally emits `CONCURRENCY|X01|...` (expects 6 visits for NAIVE) and `X02` (expects 5 for SAFE).

Two things found while building it: launching the sessions with `Start-Process` lost the quoted connect string (empty output); `Start-Job` with a single-quoted connect string works. The NAIVE script originally slept *before* inserting, which hid the race - fixed in script 21.

## 6. Actual execution example

Real output is shown in the `21_concurrency_session` help file; the last two lines are `CONCURRENCY|X01|...|6 visits|PASS` and `CONCURRENCY|X02|...|5 visits|PASS`.

## 7. Data flow and integration

```
 SETUP ─► job A ─┐
          job B ─┴► both sessions on the same slot ─► CHECK ─► CLEANUP ─► X01/X02
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Both results are 4 visits | Sessions produced no output (quoting) | Fixed by single-quoted connect string in a background job. |
| X01 FAIL (not 6) | Timing: B finished before A inserted | Keep the INSERT before the sleep in script 21. |
| X02 FAIL | Procedure without locks | Check the two FOR UPDATE selects in `sp_schedule_visit`. |

## 9. Viva questions and answers

**Q1. How can you simulate two users on one machine?**  
Two independent database sessions (processes/jobs), one holding an open transaction while the other works.

## 10. Important practical commands

```
.\scripts\concurrency_demo.ps1
.\scripts\concurrency_demo.ps1 -Quiet
```

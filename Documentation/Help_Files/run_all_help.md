# Help: `run_all.sql`

## 1. File overview

* **Exact filename:** `run_all.sql`
* **Location:** `sql/`
* **Purpose:** Master install script: runs the build scripts in dependency order and stops at the first error.
* **Feature(s):** F4 (dependency order), F29 (repeatable deployment)
* **Member responsibility:** Member 3 (integration)
* **Role in the system:** One command builds the entire database.
* **Execution order:** Run as PRISON_OWNER after `00_admin_setup.sql`.

## 2. Required database objects and dependencies

* **Calls:** 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 17, 18 (in that order).
* **Does not call:** demos 12-16, 19-21 (optional), 99 (destructive).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **WHENEVER SQLERROR** | Tells SQL*Plus to stop (EXIT) or continue when a statement fails. | `WHENEVER SQLERROR EXIT FAILURE` | `EXIT FAILURE` stops the whole install at the first failing statement. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | SERVEROUTPUT / ECHO. |

**Common mistakes with these keywords**

* *WHENEVER SQLERROR*: Without it SQL*Plus keeps going after an error and still returns exit code 0.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.

**`@@file`** runs another script located relative to the *calling* script (so it works from any directory); `@file` would be relative to the current directory. **`PROMPT text`** prints a message.

## 4. Tables and columns involved

None directly; it triggers the creation of all objects.

## 5. Walkthrough

Each `@@` line runs one script. The order matters: tables (01-02), indexes (03), data (04), package and functions (05) before the triggers that use them (06-08), procedures (09) after the functions and triggers, cursors (10), views (11), roles (17) after the views and procedures they grant, job (18) after the procedures it calls.

## 6. Actual execution example

Real ending of an install:

```
18_scheduled_jobs.sql finished.
*** run_all.sql complete ***
Install finished.
```

## 7. Data flow and integration

```
 run_all.sql ──► 01 ─► 02 ─► 03 ─► 04 ─► 05 ─► 06 ─► 07 ─► 08 ─► 09 ─► 10 ─► 11 ─► 17 ─► 18
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Install stops at a script | WHENEVER SQLERROR EXIT FAILURE caught an error | Read the last ORA- message; fix; run `99_drop_all.sql` and start again. |
| `SP2-0310: unable to open file` | Run from the wrong directory without `@@` | Start SQL*Plus in `sql/` or keep `@@`. |

## 9. Viva questions and answers

**Q1. What is the difference between `@` and `@@`?**  
`@@` resolves the path relative to the script containing it.

**Q2. Why does order matter?**  
Objects reference each other: triggers call functions, procedures call triggers' tables, roles grant on views and procedures.

## 10. Important practical commands

```
cd sql
sqlplus prison_owner/<pwd>@//localhost:1521/FREEPDB1 @run_all.sql
.\scripts\install.ps1
```

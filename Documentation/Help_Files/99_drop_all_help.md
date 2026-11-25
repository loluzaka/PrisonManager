# Help: `99_drop_all.sql`

## 1. File overview

* **Exact filename:** `99_drop_all.sql`
* **Location:** `sql/`
* **Purpose:** Removes every project object in dependency order so the schema can be rebuilt from nothing.
* **Feature(s):** F4 (clean teardown, correct DROP order)
* **Member responsibility:** Member 1
* **Role in the system:** Clean-slate tool used by `install.ps1 -Fresh`.
* **Execution order:** Run on demand BEFORE rebuilding. Never part of `run_all.sql`.

## 2. Required database objects and dependencies

* **Needs:** the objects to exist (but each DROP ignores "does not exist").
* **Order:** scheduler job -> views -> procedures -> functions -> package -> tables child-first (staff_access, inmate_conflicts, visit_slots, conflicts, movements, visits, audit_log, visitors, inmates, blocks, facilities).
* **Does not remove:** roles and demo users (not owned by the schema).
* **DESTROYS ALL DATA.**

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **DROP TABLE** | Removes a table and its data. PURGE also skips the recycle bin. | `DROP TABLE t PURGE;` | PURGE skips the recycle bin; triggers and indexes disappear with their table. |
| **EXECUTE IMMEDIATE** | Runs a SQL string built at run time (needed for DDL inside PL/SQL). | `EXECUTE IMMEDIATE 'ALTER TABLE ...';` | A helper `run(sql)` executes each DROP dynamically and prints ok/skipped. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | `WHEN OTHERS` in the helper turns "object does not exist" into a message, so the script is re-runnable. |
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | One block with a nested procedure. |
| **DBMS_SCHEDULER** | Oracle's job scheduler: runs a stored procedure on a calendar. | `DBMS_SCHEDULER.CREATE_JOB(job_name=>..., repeat_interval=>'FREQ=DAILY;BYHOUR=2')` | `DROP_JOB(..., force => TRUE)` removes the nightly job. |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | Orders the dictionary loop: views, then procedures, functions, packages. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | SERVEROUTPUT for the messages. |

**Common mistakes with these keywords**

* *DROP TABLE*: Dropping a parent first -> ORA-02449; drop children first.
* *EXECUTE IMMEDIATE*: SQL injection risk if the string contains user input; DDL commits implicitly.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.
* *DBMS_SCHEDULER*: Needs the CREATE JOB privilege.
* *CASE*: Missing ELSE returns NULL.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.

## 4. Tables and columns involved

All eleven tables are dropped, parents last. A parent cannot be dropped while a child still references it (ORA-02449), which is why the order is the reverse of creation.

## 5. Walkthrough

1. Drop the scheduler job (ignore error if absent).
2. Loop over `user_objects` for VIEW, PROCEDURE, FUNCTION, PACKAGE and drop each (ordered by type).
3. Drop tables: STAFF_ACCESS, INMATE_CONFLICTS, VISIT_SLOTS, CONFLICTS, MOVEMENTS, VISITS, AUDIT_LOG, VISITORS, INMATES, BLOCKS, FACILITIES, then leftovers `tmp_visit_test` and `visits_big`.

## 6. Actual execution example

Real output (excerpt):

```
ok      DROP VIEW V_TODAYS_VISITS
ok      DROP PROCEDURE SP_TRANSFER_INMATE
ok      DROP PACKAGE PKG_PRISON_RULES
ok      DROP TABLE staff_access PURGE
...
ok      DROP TABLE facilities PURGE
skipped DROP TABLE tmp_visit_test PURGE  (ORA-00942: table or view ... does not exist)
99_drop_all.sql finished: schema is empty.
```

## 7. Data flow and integration

```
 99_drop_all.sql ──► job, views, code, tables (child first) ──► empty schema ──► run_all.sql rebuilds
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-02449: unique/primary keys in table referenced by foreign keys` | A parent was dropped before a child | Keep the order; `DROP TABLE ... CASCADE CONSTRAINTS` is the emergency alternative. |
| `ORA-00942` messages | Object already gone | Harmless; the script prints "skipped". |

## 9. Viva questions and answers

**Q1. Why is the drop order the reverse of the creation order?**  
Foreign keys: a table can only be dropped after everything that references it.

**Q2. Why PURGE?**  
It frees the space at once and avoids recycle-bin names such as BIN$...

## 10. Important practical commands

```
@99_drop_all.sql
SELECT object_type, COUNT(*) FROM user_objects GROUP BY object_type;     -- empty afterwards
.\scripts\install.ps1 -Fresh        -- drop and rebuild from PowerShell
```

# Help: `18_scheduled_jobs.sql`

## 1. File overview

* **Exact filename:** `18_scheduled_jobs.sql`
* **Location:** `sql/`
* **Purpose:** Creates the nightly maintenance procedure and the DBMS_SCHEDULER job that runs it at 02:00.
* **Feature(s):** F28 (scheduled jobs - stretch)
* **Member responsibility:** Member 3
* **Role in the system:** Automation: releases inmates whose sentence ended and marks past SCHEDULED visits as MISSED.
* **Execution order:** After the cursors/procedures (it calls `pr_upcoming_releases`, `sp_log_audit`).

## 2. Required database objects and dependencies

* **Writes:** INMATES (status), VISITS (status), AUDIT_LOG.
* **Calls:** `sp_log_audit`, `pr_upcoming_releases`.
* **Needs:** CREATE JOB privilege (script 00).
* **Triggers fired:** `trg_audit_inmates`, `trg_audit_visits`, `trg_visit_slot_rules`.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CURSOR** | A named pointer to a query result that PL/SQL walks row by row. Explicit lifecycle: DECLARE -> OPEN -> FETCH -> check %NOTFOUND -> CLOSE. | `CURSOR c (p DATE) IS SELECT ...; OPEN c(d); FETCH c INTO r; EXIT WHEN c%NOTFOUND; CLOSE c;` | `c_due_release ... FOR UPDATE OF status` locks the rows; `UPDATE ... WHERE CURRENT OF c_due_release` changes exactly the row just fetched. |
| **FOR UPDATE / WHERE CURRENT OF** | A cursor declared FOR UPDATE locks its rows; UPDATE ... WHERE CURRENT OF changes exactly the row just fetched. | `CURSOR c IS SELECT ... FOR UPDATE OF col; UPDATE t SET ... WHERE CURRENT OF c;` | See above. |
| **Cursor FOR loop** | Opens, fetches and closes a cursor automatically; the loop variable is a record. | `FOR r IN c(10) LOOP ... END LOOP;` | `FOR r IN c_due_release LOOP`. |
| **DBMS_SCHEDULER** | Oracle's job scheduler: runs a stored procedure on a calendar. | `DBMS_SCHEDULER.CREATE_JOB(job_name=>..., repeat_interval=>'FREQ=DAILY;BYHOUR=2')` | `CREATE_JOB(job_type=>'STORED_PROCEDURE', repeat_interval=>'FREQ=DAILY; BYHOUR=2; ...')`; start_date is *tomorrow 02:00* so it does not fire during an install. |
| **PROCEDURE** | A stored program that performs an action; values go back through OUT parameters; called as a statement. | `CREATE PROCEDURE p (a IN NUMBER, b OUT VARCHAR2) IS ...` | `pr_nightly_maintenance(p_released OUT, p_missed OUT)` and a wrapper `pr_nightly_job` without parameters, because the scheduler calls a plain procedure. |
| **SQL%ROWCOUNT** | Number of rows touched by the most recent INSERT/UPDATE/DELETE (implicit cursor). | `IF SQL%ROWCOUNT = 0 THEN ...` | Counts missed visits. |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | COMMIT after the loop, ROLLBACK + RAISE on error. |
| **UPDATE** | Changes values of existing rows. | `UPDATE t SET col = val WHERE cond;` | Visits to MISSED. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | Rolls back and re-raises. |
| **DBMS_OUTPUT** | Buffered text output of PL/SQL, shown by the client after the block ends. | `SET SERVEROUTPUT ON; DBMS_OUTPUT.PUT_LINE('text');` | Prints released inmate numbers. |

**Common mistakes with these keywords**

* *CURSOR*: Not closing the cursor (ORA-01000 too many open cursors) or testing %NOTFOUND before the first FETCH.
* *FOR UPDATE / WHERE CURRENT OF*: COMMIT inside the loop releases the locks and invalidates the cursor (ORA-01002).
* *Cursor FOR loop*: Referring to r after the loop.
* *DBMS_SCHEDULER*: Needs the CREATE JOB privilege.
* *PROCEDURE*: Trying to use a procedure inside SELECT (that needs a function).
* *SQL%ROWCOUNT*: Read it immediately; the next statement overwrites it.
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.
* *UPDATE*: Forgetting WHERE changes every row.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *DBMS_OUTPUT*: Forgetting SET SERVEROUTPUT ON - then nothing is printed.

## 4. Tables and columns involved

INMATES (`status`, `sentence_end`), VISITS (`status`, `visit_date`), AUDIT_LOG (one JOB row per run). See the Data Dictionary.

## 5. Walkthrough

1. Cursor selects ACTIVE inmates whose `sentence_end < TRUNC(SYSDATE)`, locking them.
2. For each: `UPDATE inmates SET status='RELEASED' WHERE CURRENT OF c_due_release` (audit trigger records old -> new).
3. One UPDATE sets `MISSED` for SCHEDULED visits before today; `SQL%ROWCOUNT` is saved.
4. `sp_log_audit('INMATES','JOB', NULL, 'pr_nightly_maintenance: released=..; visits marked missed=..')`, COMMIT.
5. `pr_upcoming_releases(7)` lists the releases of the next week.
6. The script drops any old job and creates `JOB_NIGHTLY_PRISON_MAINTENANCE`, then runs the body once manually.
Tests I08-I11 insert a fixture (inmate whose sentence ended yesterday + a SCHEDULED visit two days ago), call the procedure and check RELEASED, MISSED, exactly one new JOB audit row, and that the job exists and is enabled.

## 6. Actual execution example

Real output of the manual run on the seed data (nothing is due yet):

```
JOB_NAME                           ENABL REPEAT_INTERVAL
JOB_NIGHTLY_PRISON_MAINTENANCE     TRUE  FREQ=DAILY; BYHOUR=2; BYMINUTE=0; BYSECOND=0
===== RELEASES DUE WITHIN 7 DAYS =====
inmates due for release: 0
result: released=0, missed=0
```
With the test fixture: `released INM-T900`, status RELEASED, visit status MISSED (tests I08, I09 PASS). *Honest note:* the real 02:00 firing was not waited for; the job body was run directly.

## 7. Data flow and integration

```
 DBMS_SCHEDULER 02:00 ─► pr_nightly_job ─► pr_nightly_maintenance ─► INMATES.status / VISITS.status ─► triggers ─► AUDIT_LOG
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-27486: insufficient privileges` | No CREATE JOB | Granted in script 00. |
| Job runs immediately at creation | start_date in the past/now | Use tomorrow 02:00 (as here). |
| `ORA-01002: fetch out of sequence` | COMMIT inside a FOR UPDATE cursor loop | COMMIT after the loop. |
| Job fails silently | Errors only in the scheduler log | `SELECT * FROM user_scheduler_job_run_details ORDER BY log_date DESC`. |

## 9. Viva questions and answers

**Q1. Why FOR UPDATE and WHERE CURRENT OF?**  
Lock the rows being processed and update exactly the fetched row without a second lookup.

**Q2. Why a wrapper procedure?**  
DBMS_SCHEDULER can only call a procedure without OUT parameters.

**Q3. How do you run the job on demand?**  
`EXEC DBMS_SCHEDULER.RUN_JOB('JOB_NIGHTLY_PRISON_MAINTENANCE')`.

**Q4. What is the FREQ string?**  
A calendaring expression: daily at 02:00:00.

## 10. Important practical commands

```
SELECT job_name, enabled, next_run_date FROM user_scheduler_jobs;
SELECT log_date, status, additional_info FROM user_scheduler_job_run_details ORDER BY log_date DESC;
EXEC DBMS_SCHEDULER.RUN_JOB('JOB_NIGHTLY_PRISON_MAINTENANCE');
EXEC DBMS_SCHEDULER.DISABLE('JOB_NIGHTLY_PRISON_MAINTENANCE');
```

# Help: `30_test_suite.sql`

## 1. File overview

* **Exact filename:** `30_test_suite.sql`
* **Location:** `tests/`
* **Purpose:** The main automated test suite: 140 positive and negative checks of schema, constraints, functions, procedures, triggers, audit trail, cursors, views, the nightly job, flashback recovery, transactions and advanced queries.
* **Feature(s):** F34 (test suite); exercises F1-F28 and F36
* **Member responsibility:** Member 3
* **Role in the system:** Executable proof that the rules work. Prints `TEST|id|purpose|expected|actual|PASS/FAIL` lines.
* **Execution order:** Run as PRISON_OWNER on a freshly seeded database (`scripts/run_tests.ps1` re-seeds first).

## 2. Required database objects and dependencies

* **Creates and drops** the helper package `pkg_test` (assertion `chk`, `try_sql`, `summary`) and a scratch table `tmp_backup_test`.
* **Needs everything:** tables, data (04), functions, triggers, procedures, cursors, views, job.
* **Changes data** (transfers, visitors, bookings, conflicts) and commits some of it - hence the re-seed before every run.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | Eleven blocks, one per area (A structure ... K transactions). |
| **EXECUTE IMMEDIATE** | Runs a SQL string built at run time (needed for DDL inside PL/SQL). | `EXECUTE IMMEDIATE 'ALTER TABLE ...';` | `pkg_test.try_sql(sql)` runs a statement and returns 0 or the SQLCODE (so a refused INSERT becomes a testable number). |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | `WHEN OTHERS THEN RETURN SQLCODE` inside `try_sql`. |
| **SQLCODE / SQLERRM** | Error number and message of the exception being handled. | `WHEN OTHERS THEN v := SQLCODE; m := SQLERRM;` | Expected codes: -2290 (CHECK), -1 (UNIQUE), -1400, -2291, -2292, -20101...-20301. |
| **PROCEDURE** | A stored program that performs an action; values go back through OUT parameters; called as a statement. | `CREATE PROCEDURE p (a IN NUMBER, b OUT VARCHAR2) IS ...` | Calls every business procedure and compares the returned status with the expected code. |
| **FUNCTION** | A stored program that RETURNs exactly one value and can be used inside SQL. | `CREATE FUNCTION f (x NUMBER) RETURN NUMBER IS ... RETURN v;` | C-tests compare function results with hand-written COUNT queries. |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | ROLLBACK after destructive negative tests. |
| **SAVEPOINT** | A bookmark inside a transaction; ROLLBACK TO SAVEPOINT undoes only the work after it. | `SAVEPOINT s1; ... ROLLBACK TO SAVEPOINT s1;` | K01/K02. |
| **CURSOR** | A named pointer to a query result that PL/SQL walks row by row. Explicit lifecycle: DECLARE -> OPEN -> FETCH -> check %NOTFOUND -> CLOSE. | `CURSOR c (p DATE) IS SELECT ...; OPEN c(d); FETCH c INTO r; EXIT WHEN c%NOTFOUND; CLOSE c;` | H-tests run the cursor procedures and capture DBMS_OUTPUT with `DBMS_OUTPUT.GET_LINES`. |
| **FLASHBACK TABLE** | Rewinds a table to an earlier point in time using undo data (needs ROW MOVEMENT enabled). | `FLASHBACK TABLE t TO TIMESTAMP ts;` | J01/J02: delete 20 rows of a scratch table and bring them back. |
| **CREATE TABLE** | Defines a new table: its columns, data types and constraints. The table starts empty. | `CREATE TABLE name (col type [constraint], ..., [table constraint]);` | `tmp_backup_test ... ENABLE ROW MOVEMENT`. |
| **DBMS_OUTPUT** | Buffered text output of PL/SQL, shown by the client after the block ends. | `SET SERVEROUTPUT ON; DBMS_OUTPUT.PUT_LINE('text');` | Test result lines. |
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | COUNT checks of the catalogue and tables. |
| **CREATE OR REPLACE** | Creates a stored program or replaces its previous version without dropping it (grants survive). | `CREATE OR REPLACE PROCEDURE p IS BEGIN ... END;` | The helper package. |

**Common mistakes with these keywords**

* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.
* *EXECUTE IMMEDIATE*: SQL injection risk if the string contains user input; DDL commits implicitly.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *SQLCODE / SQLERRM*: Calling them outside an exception handler gives 0 / "normal".
* *PROCEDURE*: Trying to use a procedure inside SELECT (that needs a function).
* *FUNCTION*: A function with no RETURN on some path -> ORA-06503 at run time.
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.
* *SAVEPOINT*: Rolling back to a savepoint keeps the transaction open (and earlier locks).
* *CURSOR*: Not closing the cursor (ORA-01000 too many open cursors) or testing %NOTFOUND before the first FETCH.
* *FLASHBACK TABLE*: Fails (ORA-08180) when undo has expired.
* *CREATE TABLE*: Creating a child table before its parent (the FOREIGN KEY target must exist) -> ORA-00942.
* *DBMS_OUTPUT*: Forgetting SET SERVEROUTPUT ON - then nothing is printed.
* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *CREATE OR REPLACE*: Compilation errors still create the object as INVALID - check with SHOW ERRORS.

**Test design.** Positive test = the right thing succeeds (BOOKED, TRANSFERRED). Negative test = the wrong thing is refused with a *specific* code (ORA-20103, DENIED_CONFLICT, ORA-02292). Each line records ID, purpose, expected and actual value, so a failure is self-explanatory. `GET_LINES` discards earlier buffered output, so the H-section collects all results first and reports them at the end (a real bug fixed during development: H01-H06 were counted but not printed).

## 4. Tables and columns involved

All eleven tables and views. Fixtures (all on far-future dates or seed rows): inmate 12 + visitor 1 (booking), visitor 36 (blacklisted), 31 (pending), visitor 5 / inmate 3 (conflict), inmate 46 (transferred), inmate 13 (weekly limit week), inmates 16, 17, 18, 20, 21 (fill a slot), inmate 14 (leaves in 19 days), inmate 1 -> D-Block, inmate 2 -> E-Block (full), inmate 27 (HIGH risk), inmate 4 (rival 14).

## 5. Walkthrough

| Section | IDs | Area |
|---|---|---|
| A | A01-A13 | 11 tables, 11 PK, 12 FK, 19 CHECK, 7 UNIQUE, triggers, 10 indexes, 17 views, seed counts |
| B | B01-B10 | CHECK, UNIQUE, NOT NULL, FK, RESTRICT negative tests |
| C | C01-C18 | functions return correct values; usable in SELECT |
| D | D01-D29 | registration, booking, every denial status, audit rows, trigger refusals, autonomous log survives ROLLBACK |
| E | E01-E15 | conflicts, visitor status, rivalry |
| F | F01-F23 | transfers, rollback leaves nothing, movement trigger, placement trigger, admissions |
| G | G01-G06 | audit log immutability and old/new value logging |
| H | H01-H08 | cursors process multiple records |
| I | I01-I11 | views, nightly job (fixture), scheduler job exists |
| J | J01-J02 | recovery after accidental DELETE (local Flashback) |
| K | K01-K02 | SAVEPOINT and ROLLBACK |
| L | L01-L02 | OFFSET/FETCH pagination and PIVOT totals (added after the last recorded run) |

The last recorded run ended with `SUMMARY|passed=138|failed=0|total=138`. With L01-L02, the next successful main-suite run should report 140 checks.

## 6. Actual execution example

Real output (excerpt, last run):

```
TEST|D07|blacklisted visitor is denied|DENIED_BLACKLISTED|DENIED_BLACKLISTED|PASS
TEST|D08|blacklisted attempt is logged as VISIT_DENIED|3|3|PASS
TEST|D22|trigger refuses a blacklisted visitor on a direct INSERT (ORA-20102)|-20102|-20102|PASS
TEST|D23|denial survives the ROLLBACK (autonomous transaction)|2|2|PASS
TEST|F07|full block rejects a transfer|BLOCK_FULL|BLOCK_FULL|PASS
TEST|F09|rejected transfer left NO partial MOVEMENTS row (rollback)|59|59|PASS
TEST|G01|UPDATE of an audit row is refused (ORA-20301)|-20301|-20301|PASS
TEST|H01|c_daily_roster fetched every visit of today (%ROWCOUNT)|8|8|PASS
TEST|J02|FLASHBACK TABLE restored the 20 rows|20|20|PASS
SUMMARY|passed=138|failed=0|total=138
```
Full table: `Documentation/Testing_Guide.md`.

## 7. Data flow and integration

```
 04_seed_data.sql ─► 30_test_suite.sql ─► calls procedures/triggers/functions ─► TEST| lines ─► Documentation/Test_Results/latest_test_run.log
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Many FAIL lines after a manual run | Database not freshly seeded | Run `04_seed_data.sql` (or `run_tests.ps1`). |
| `ORA-08180: no snapshot found` in J02 | Undo expired / row movement off | Table is created with ENABLE ROW MOVEMENT; keep the 3 s pauses. |
| `PLS-00201 identifier PKG_TEST` on a rerun | Package dropped by an earlier failure | The script recreates it at the top. |
| H-tests missing from the output | GET_LINES swallowed buffered lines | Report H results after all captures (already done). |
| Test blocks stop at ORA-06550 | A procedure signature changed | `DESC` the procedure and update the call. |

## 9. Viva questions and answers

**Q1. What is the difference between a positive and a negative test?**  
Positive: valid input must succeed. Negative: invalid input must be refused in a specific way.

**Q2. How do you test that a trigger raises an error?**  
Run the statement through `try_sql` and compare the returned SQLCODE with the expected -20xxx.

**Q3. How do you test an autonomous-transaction log?**  
Count audit rows, perform the refused INSERT, ROLLBACK, count again: it must be +1 (D23).

**Q4. Why re-seed before the suite?**  
Tests assume known data; a repeatable start makes results comparable.

**Q5. Why not utPLSQL?**  
Not installed in the container; a small assertion package gives the same expected/actual/pass output with no dependency.

## 10. Important practical commands

```
.\scripts\run_tests.ps1
docker exec -i prison-oracle bash -c "cd /prison/tests && sqlplus -S prison_owner/<pwd>@//localhost:1521/FREEPDB1 @30_test_suite.sql"
SELECT * FROM audit_log WHERE action_type = 'VISIT_DENIED' ORDER BY audit_id DESC;
```

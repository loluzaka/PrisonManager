# Help: `06_audit_trail.sql`

## 1. File overview

* **Exact filename:** `06_audit_trail.sql`
* **Location:** `sql/`
* **Purpose:** Builds the append-only audit trail: two logging procedures (normal and autonomous), the immutability trigger on AUDIT_LOG and change-logging triggers on INMATES, VISITORS and VISITS.
* **Feature(s):** F22 (tamper-proof audit trail); supports F13, F17, F21
* **Member responsibility:** Member 2
* **Role in the system:** Records who changed what, every denied visit, and refuses any attempt to edit or delete history.
* **Execution order:** After the functions (05); before the rule triggers (07, 08) which call `sp_log_audit_auto`.

## 2. Required database objects and dependencies

* **Writes:** AUDIT_LOG. **Reads (via :OLD/:NEW):** INMATES, VISITORS, VISITS.
* **Creates:** SP_LOG_AUDIT, SP_LOG_AUDIT_AUTO, FN_DIFF, TRG_AUDIT_LOG_IMMUTABLE, TRG_AUDIT_INMATES, TRG_AUDIT_VISITORS, TRG_AUDIT_VISITS.
* **Used by:** triggers 07/08, procedures 09, scheduler job 18.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **PROCEDURE** | A stored program that performs an action; values go back through OUT parameters; called as a statement. | `CREATE PROCEDURE p (a IN NUMBER, b OUT VARCHAR2) IS ...` | `sp_log_audit` and `sp_log_audit_auto` are the only code that inserts into AUDIT_LOG. |
| **PRAGMA AUTONOMOUS_TRANSACTION** | Makes a subprogram run in its OWN transaction that commits independently of the caller. | `PRAGMA AUTONOMOUS_TRANSACTION; ... COMMIT;` | In `sp_log_audit_auto`: the insert and its COMMIT live in a separate transaction, so the row **survives the ROLLBACK** that follows when a trigger raises an error (the "denied visits" decision). |
| **CREATE TRIGGER** | Code that the database runs automatically when a table is changed. Cannot be bypassed by application code. | `CREATE TRIGGER t BEFORE|AFTER INSERT OR UPDATE ON tbl [FOR EACH ROW] ...` | Four triggers. |
| **BEFORE / AFTER** | Timing: BEFORE fires before the row change (good for validation / modifying :NEW), AFTER fires after it (good for logging to other tables). | `BEFORE INSERT ON visits` | `trg_audit_log_immutable` is BEFORE (refuse before anything changes); the three audit triggers are AFTER (log only changes that really happened). |
| **FOR EACH ROW** | Row-level trigger: runs once per affected row and can use :OLD and :NEW. Without it the trigger is statement-level (once per statement). | `CREATE TRIGGER ... FOR EACH ROW BEGIN ... END;` | All four are row-level. |
| **:OLD / :NEW** | Column values of the row before (:OLD) and after (:NEW) the change. INSERT has no :OLD, DELETE has no :NEW. | `:NEW.status, :OLD.block_id` | Old and new column values are compared with `fn_diff` to log `column: old -> new`. |
| **INSERTING / UPDATING** | Boolean flags telling a multi-event trigger which statement fired it. | `IF INSERTING THEN ... ELSIF UPDATING THEN ...` | One trigger body handles INSERT, UPDATE and DELETE. |
| **RAISE_APPLICATION_ERROR** | Raises a custom error with a code in -20000..-20999 and a message; rolls back the statement. | `RAISE_APPLICATION_ERROR(-20102, 'Visitor is blacklisted');` | `-20301 AUDIT_LOG is append-only: UPDATE is not allowed`. |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | Only the autonomous procedure commits; the normal one leaves the decision to the caller. |
| **FUNCTION** | A stored program that RETURNs exactly one value and can be used inside SQL. | `CREATE FUNCTION f (x NUMBER) RETURN NUMBER IS ... RETURN v;` | `fn_diff(col, old, new)` returns NULL when equal, else `col: old -> new; ` (NULL-safe). |
| **Scalar functions** | Row-level functions: UPPER, TRIM, SUBSTR, INSTR, REPLACE, LENGTH, ROUND, MOD, TO_CHAR, ADD_MONTHS, TRUNC(date) ... | `UPPER(TRIM(name))` | TO_CHAR for dates, NVL for NULL text, SUBSTR to fit 4000 characters. |

**Common mistakes with these keywords**

* *PROCEDURE*: Trying to use a procedure inside SELECT (that needs a function).
* *PRAGMA AUTONOMOUS_TRANSACTION*: Forgetting the COMMIT -> ORA-06519.
* *CREATE TRIGGER*: A trigger that queries its own table in a row trigger -> ORA-04091 (mutating table).
* *BEFORE / AFTER*: Trying to change :NEW in an AFTER trigger.
* *FOR EACH ROW*: Using :NEW in a statement-level trigger -> PLS-00049.
* *:OLD / :NEW*: In the WHEN clause write NEW/OLD without the colon.
* *RAISE_APPLICATION_ERROR*: Codes outside -20000..-20999 are rejected (ORA-21000).
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.
* *FUNCTION*: A function with no RETURN on some path -> ORA-06503 at run time.
* *Scalar functions*: Dates: SYSDATE includes the time; use TRUNC(SYSDATE) for "today".

## 4. Tables and columns involved

### AUDIT_LOG

Append-only trail of changes, transfers, allowed and denied visit attempts (F22). No foreign keys.

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **AUDIT_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **TABLE_NAME** | VARCHAR2(30) | NOT NULL | `—` | — | Table the event concerns. |
| 3 | **ACTION_TYPE** | VARCHAR2(20) | NOT NULL | `—` | CK CK_AUDIT_ACTION | INSERT, UPDATE, DELETE, TRANSFER, VISIT_BOOKED, VISIT_DENIED or JOB. |
| 4 | **RECORD_ID** | NUMBER | NULL | `—` | — | Id of the affected record. For VISIT_DENIED it is the VISITOR_ID (no visit row exists). |
| 5 | **DETAILS** | VARCHAR2(4000) | NULL | `—` | — | Old -> new values or the denial reason (reason=...). |
| 6 | **CHANGED_BY** | VARCHAR2(60) | NOT NULL | `SYS_CONTEXT('USERENV','SESSION_USER')` | — | Database user. |
| 7 | **CHANGED_AT** | TIMESTAMP(6) | NOT NULL | `SYSTIMESTAMP` | — | Timestamp of the event. |

Check constraints:

* `CK_AUDIT_ACTION` — `action_type IN ('INSERT','UPDATE','DELETE','TRANSFER',					     'VISIT_BOOKED','VISIT_DENIED','JOB')`

**Why this structure:** Append-only: no UPDATE/DELETE is ever legal, which is what makes it an audit trail.

Action types written: `INSERT/UPDATE/DELETE` (generic triggers), `TRANSFER` (trg_log_movement), `VISIT_BOOKED` (trg_audit_visits on INSERT), `VISIT_DENIED` (sp_log_audit_auto; `record_id` = visitor id), `JOB` (nightly job).

## 5. Walkthrough

1. **`sp_log_audit`** inserts a row in the caller's transaction: if the caller rolls back, the audit row goes too (correct for normal changes).
2. **`sp_log_audit_auto`** does the same inside `PRAGMA AUTONOMOUS_TRANSACTION` and commits. Because AUDIT_LOG has no foreign keys it can never wait for an uncommitted row of the caller, so there is no deadlock.
3. **`trg_audit_log_immutable`** (BEFORE UPDATE OR DELETE ... FOR EACH ROW) always raises -20301. TRUNCATE is DDL and cannot be blocked by a DML trigger - that is why no role is ever granted TRUNCATE/DROP.
4. **`trg_audit_inmates`**: INSERT -> inmate number, name, block, risk, status; UPDATE -> only the changed columns among name, status, risk, sentence dates (a change of `block_id` alone is skipped: `trg_log_movement` writes a TRANSFER row for it); DELETE -> a record of what was deleted.
5. **`trg_audit_visitors`** and **`trg_audit_visits`** follow the same pattern; a visit INSERT is stored as `VISIT_BOOKED`.

## 6. Actual execution example

Real behaviour:

```
UPDATE inmates SET risk_level = 'MEDIUM' WHERE inmate_id = 13;
ACTION_TYPE   DETAILS
UPDATE        risk_level: LOW -> MEDIUM;

UPDATE audit_log SET details = 'x' WHERE audit_id = 1;
ORA-20301: AUDIT_LOG is append-only: UPDATE is not allowed
ORA-06512: at "PRISON_OWNER.TRG_AUDIT_LOG_IMMUTABLE", line 3

DELETE FROM audit_log WHERE audit_id = 1;
ORA-20301: AUDIT_LOG is append-only: DELETE is not allowed
```
Tests G01-G06 and R-AUDIT-1..3 (five roles) assert this.

## 7. Data flow and integration

```
 change on INMATES/VISITORS/VISITS ──AFTER row──► trg_audit_* ──► sp_log_audit ──► AUDIT_LOG   (same transaction)
 refused visit (trigger / procedure) ───────────► sp_log_audit_auto ─autonomous COMMIT─► AUDIT_LOG  (survives ROLLBACK)
 UPDATE / DELETE on AUDIT_LOG ──BEFORE row──► trg_audit_log_immutable ──► ORA-20301
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-06519: active autonomous transaction detected and rolled back` | Autonomous procedure ended without COMMIT/ROLLBACK | End it with COMMIT (as `sp_log_audit_auto` does). |
| Audit row missing for a denied attempt | Used `sp_log_audit` (normal) in a path that rolls back | Use `sp_log_audit_auto` where the row must survive. |
| `ORA-20301` when seeding/cleaning | DELETE FROM audit_log | TRUNCATE (owner only) or disable the trigger temporarily. |
| `ORA-04091 mutating table` | Audit trigger querying its own table | These triggers only INSERT into AUDIT_LOG and read :OLD/:NEW. |

## 9. Viva questions and answers

**Q1. What is an autonomous transaction and why is it needed here?**  
An independent transaction inside another. A trigger that refuses a visit raises an error and everything in that transaction is rolled back, including a normal audit insert; the autonomous insert is committed separately, so the denial is kept.

**Q2. How is the audit log made tamper-proof?**  
A BEFORE UPDATE/DELETE trigger always raises an error, roles get only INSERT/SELECT, and nobody but the owner has DDL rights.

**Q3. Why no foreign keys on AUDIT_LOG?**  
Denied attempts concern records that never existed, and audit rows must outlive the rows they describe.

**Q4. Why log changes in an AFTER trigger?**  
Only then is the change certain to have been accepted by the constraints.

**Q5. Limit of this design?**  
The schema owner could still TRUNCATE or DROP it; therefore the owner account is protected and roles never receive DDL rights.

## 10. Important practical commands

```
SELECT action_type, COUNT(*) FROM audit_log GROUP BY action_type;
SELECT audit_id, action_type, record_id, details FROM audit_log ORDER BY audit_id DESC FETCH FIRST 10 ROWS ONLY;
SELECT trigger_name, status FROM user_triggers WHERE table_name = 'AUDIT_LOG';
UPDATE audit_log SET details = 'x' WHERE audit_id = 1;       -- ORA-20301
```

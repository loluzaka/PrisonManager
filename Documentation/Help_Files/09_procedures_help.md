# Help: `09_procedures.sql`

## 1. File overview

* **Exact filename:** `09_procedures.sql`
* **Location:** `sql/`
* **Purpose:** Seven business procedures that return status codes: visitor registration and approval, conflict management, rivalry, SP_SCHEDULE_VISIT and SP_TRANSFER_INMATE.
* **Feature(s):** F14 (conflict management), F17 (sp_schedule_visit), F18 (sp_transfer_inmate), F23 (exception handling), F24 (SAVEPOINT / COMMIT / ROLLBACK / row locking)
* **Member responsibility:** Member 2
* **Role in the system:** The "front door" of the system: staff call these instead of touching tables; each one is a single atomic transaction with clear statuses.
* **Execution order:** After the triggers (07, 08).

## 2. Required database objects and dependencies

* **Reads/Writes:** VISITORS, VISITS, INMATES, BLOCKS, CONFLICTS, INMATE_CONFLICTS, VISIT_SLOTS (row locks). MOVEMENTS and AUDIT_LOG are written *by the triggers*.
* **Calls:** `fn_is_visitor_eligible`, `fn_weekly_visit_count`, `fn_slot_visit_count`, `fn_block_occupancy`, `fn_level_rank`, `sp_log_audit_auto`, package PKG_PRISON_RULES.
* **Granted to roles in 17:** FRONT_DESK (`sp_register_visitor`, `sp_schedule_visit`), WARDEN (transfer/conflict), ADMIN (all).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **PROCEDURE** | A stored program that performs an action; values go back through OUT parameters; called as a statement. | `CREATE PROCEDURE p (a IN NUMBER, b OUT VARCHAR2) IS ...` | Seven procedures; each returns `p_status` and `p_message`. |
| **IN / OUT / IN OUT** | Parameter modes: IN is read-only input, OUT is output, IN OUT both. | `p_status OUT VARCHAR2` | Inputs are IN; `p_status`, `p_message`, `p_visit_id`, `p_visitor_id` are OUT; `p_auto_commit IN VARCHAR2 DEFAULT 'Y'` is an optional IN. |
| **SAVEPOINT** | A bookmark inside a transaction; ROLLBACK TO SAVEPOINT undoes only the work after it. | `SAVEPOINT s1; ... ROLLBACK TO SAVEPOINT s1;` | `SAVEPOINT sp_visit_start` at the top; every failure does `ROLLBACK TO SAVEPOINT` so only this procedure's work is undone (and locks taken after it are released). |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | COMMIT on success unless `p_auto_commit = 'N'`. |
| **SELECT ... FOR UPDATE** | Reads rows and LOCKS them until COMMIT/ROLLBACK; other sessions that try to lock or change them wait. | `SELECT ... FROM t WHERE ... FOR UPDATE;` | Locks the inmate row, then the visit_slots row (booking), or the inmate row then the target block row (transfer): always the same order, so sessions cannot deadlock. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | Predefined (`NO_DATA_FOUND`, `DUP_VAL_ON_INDEX`), user-defined (`pkg_prison_rules.e_slot_full` ...) and `WHEN OTHERS`. |
| **SQLCODE / SQLERRM** | Error number and message of the exception being handled. | `WHEN OTHERS THEN v := SQLCODE; m := SQLERRM;` | Maps -2290 (CHECK), -1400 (NOT NULL), -2291 (FK) to statuses INVALID_DATA / NOT_FOUND. |
| **SQL%ROWCOUNT** | Number of rows touched by the most recent INSERT/UPDATE/DELETE (implicit cursor). | `IF SQL%ROWCOUNT = 0 THEN ...` | `sp_set_visitor_status` reports NOT_FOUND when the UPDATE touched no row. |
| **%TYPE / %ROWTYPE** | Declare a variable with the same type as a column (%TYPE) or the same shape as a row/cursor (%ROWTYPE), so code survives column changes. | `v inmates.status%TYPE; r c_cur%ROWTYPE;` | Variables typed from columns. |
| **INSERT** | Adds rows. | `INSERT INTO t (cols) VALUES (...); INSERT INTO t (cols) SELECT ...;` | `INSERT ... RETURNING visit_id INTO p_visit_id` gives the generated identity back. |
| **UPDATE** | Changes values of existing rows. | `UPDATE t SET col = val WHERE cond;` | Status changes, cancellations. |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | Message texts. |
| **Definer's rights** | A stored procedure runs with the privileges of its OWNER, so a user with only EXECUTE can change tables he cannot touch directly. | `default for CREATE PROCEDURE (AUTHID DEFINER)` | Procedures run with the owner's rights: FRONT_DESK can book visits with no privilege on VISITS. |
| **Scalar functions** | Row-level functions: UPPER, TRIM, SUBSTR, INSTR, REPLACE, LENGTH, ROUND, MOD, TO_CHAR, ADD_MONTHS, TRUNC(date) ... | `UPPER(TRIM(name))` | TRIM/UPPER clean input, TRUNC strips time from dates, LEAST/GREATEST order a pair. |

**Common mistakes with these keywords**

* *PROCEDURE*: Trying to use a procedure inside SELECT (that needs a function).
* *IN / OUT / IN OUT*: An OUT parameter is NULL until assigned; a failed call may leave it NULL or reset it.
* *SAVEPOINT*: Rolling back to a savepoint keeps the transaction open (and earlier locks).
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.
* *SELECT ... FOR UPDATE*: Forgetting to end the transaction leaves the rows locked for everybody else.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *SQLCODE / SQLERRM*: Calling them outside an exception handler gives 0 / "normal".
* *SQL%ROWCOUNT*: Read it immediately; the next statement overwrites it.
* *INSERT*: Omitting the column list - breaks when columns are added later.
* *UPDATE*: Forgetting WHERE changes every row.
* *CASE*: Missing ELSE returns NULL.
* *Definer's rights*: Assuming the caller's privileges apply inside the procedure.
* *Scalar functions*: Dates: SYSDATE includes the time; use TRUNC(SYSDATE) for "today".

## 4. Tables and columns involved

### VISITS

Associative table: one row per booked visit (INMATES <-> VISITORS many-to-many).

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **VISIT_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **INMATE_ID** | NUMBER | NOT NULL | `—` | FK → INMATES | Inmate being visited. |
| 3 | **VISITOR_ID** | NUMBER | NOT NULL | `—` | FK → VISITORS | Visitor. |
| 4 | **VISIT_DATE** | DATE | NOT NULL | `—` | CK CK_VISITS_DATE_ONLY | Date only (time part must be midnight). |
| 5 | **SLOT** | VARCHAR2(11) | NOT NULL | `—` | CK CK_VISITS_SLOT | One of the six fixed one-hour slots, e.g. 09:00-10:00. |
| 6 | **STATUS** | VARCHAR2(10) | NOT NULL | `'SCHEDULED'` | CK CK_VISITS_STATUS | SCHEDULED, COMPLETED, MISSED or CANCELLED. |
| 7 | **BOOKED_ON** | TIMESTAMP(6) | NOT NULL | `SYSTIMESTAMP` | — | Timestamp when the booking was made. |

Unique constraints: `UQ_VISITS_INMATE_SLOT`

Check constraints:

* `CK_VISITS_DATE_ONLY` — `visit_date = TRUNC(visit_date)`
* `CK_VISITS_SLOT` — `slot IN ('09:00-10:00','10:00-11:00','11:00-12:00', 			      '14:00-15:00','15:00-16:00','16:00-17:00')`
* `CK_VISITS_STATUS` — `status IN ('SCHEDULED','COMPLETED','MISSED','CANCELLED')`

Relationships: `INMATE_ID` → **INMATES** (`FK_VISITS_INMATE`, on delete NO ACTION); `VISITOR_ID` → **VISITORS** (`FK_VISITS_VISITOR`, on delete NO ACTION)

### CONFLICTS

Associative table: a visitor who must not meet a given inmate (F14).

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **CONFLICT_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **INMATE_ID** | NUMBER | NOT NULL | `—` | FK → INMATES | Inmate. |
| 3 | **VISITOR_ID** | NUMBER | NOT NULL | `—` | FK → VISITORS | Visitor. |
| 4 | **REASON** | VARCHAR2(20) | NOT NULL | `—` | CK CK_CONF_REASON | RIVAL, VICTIM_RELATIVE, GANG_AFFILIATION or OTHER. |
| 5 | **FLAGGED_DATE** | DATE | NOT NULL | `TRUNC(SYSDATE)` | CK CK_CONF_EXPIRY | Day the conflict was recorded. |
| 6 | **RESOLVED** | CHAR(1) | NOT NULL | `'N'` | CK CK_CONF_RESOLVED | Y when the conflict is resolved (added by ALTER). |
| 7 | **RESOLVED_ON** | DATE | NULL | `—` | — | Resolution date. |
| 8 | **EXPIRY_DATE** | DATE | NULL | `—` | CK CK_CONF_EXPIRY | Optional date after which the conflict no longer applies. |

Unique constraints: `UQ_CONF_PAIR`

Check constraints:

* `CK_CONF_EXPIRY` — `expiry_date IS NULL OR expiry_date >= flagged_date`
* `CK_CONF_REASON` — `reason IN ('RIVAL','VICTIM_RELATIVE','GANG_AFFILIATION','OTHER')`
* `CK_CONF_RESOLVED` — `resolved IN ('Y','N')`

Relationships: `INMATE_ID` → **INMATES** (`FK_CONF_INMATE`, on delete NO ACTION); `VISITOR_ID` → **VISITORS** (`FK_CONF_VISITOR`, on delete NO ACTION)

**Why this structure:** Procedures never expose raw ORA- errors: constraint failures are translated to statuses (F23).

## 5. Walkthrough

**`sp_register_visitor`** inserts (trimmed name, upper-cased ID type) and COMMITs -> `REGISTERED` (status PENDING by DEFAULT). `DUP_VAL_ON_INDEX` -> `DUPLICATE_ID`; CHECK/NOT NULL -> `INVALID_DATA`.

**`sp_set_visitor_status`** updates `approval_status`; for BLACKLISTED/REJECTED also cancels future SCHEDULED visits. -> `UPDATED`, `NOT_FOUND`, `INVALID_DATA`.

**`sp_add_conflict`** inserts a conflict; if the pair exists (maybe resolved) it **reactivates** it (inner exception block); cancels the pair's future visits. **`sp_resolve_conflict`** locks the row, sets `resolved='Y'`. **`sp_add_inmate_rivalry`** stores the pair as (smaller id, larger id).

**`sp_schedule_visit(inmate, visitor, date, slot, status OUT, visit_id OUT, message OUT, auto_commit)`** in order:
1. SAVEPOINT. 2. Lock the inmate row (no row -> `DENIED_NO_INMATE`). 3. Enforce the caller's `STAFF_ACCESS` facility (`DENIED_FACILITY` for an unmapped user or another facility). 4. Lock the slot row (`DENIED_INVALID_SLOT`). 5. `fn_is_visitor_eligible` -> `DENIED_UNAPPROVED / _BLACKLISTED / _CONFLICT / _INMATE_INACTIVE / _NO_VISITOR`. 6. Past date -> `DENIED_PAST_DATE`; outside sentence -> `DENIED_OUTSIDE_SENTENCE`. 7. Duplicate -> `DENIED_DUPLICATE`; weekly limit -> `DENIED_WEEKLY_LIMIT`; slot full -> `SLOT_FULL`. 8. INSERT (triggers re-check) -> `BOOKED`.
Every denial calls the local `deny` helper: write the autonomous audit row, `ROLLBACK TO SAVEPOINT`, fill the OUT parameters. The exception section also turns trigger errors (ORA-201xx) into the same statuses.

**`sp_transfer_inmate(inmate, to_block, reason, status OUT, message OUT, auto_commit)`**: SAVEPOINT; lock inmate (`NOT_FOUND`, `INMATE_NOT_ACTIVE`); lock target block (`BLOCK_NOT_FOUND`, `SAME_BLOCK`); `BLOCK_FULL` if `fn_block_occupancy >= capacity`; `SECURITY_MISMATCH`; `RIVAL_IN_BLOCK`; set `g_transfer_reason`, `UPDATE inmates SET block_id` (triggers write MOVEMENTS + audit), clear the variable, COMMIT -> `TRANSFERRED`.

**Why `p_auto_commit`?** Normal callers get an atomic unit of work. The concurrency demo calls with `'N'` to keep the locks while sleeping, then COMMITs from its own block.

## 6. Actual execution example

Real output of `sp_schedule_visit` calls (fresh seed):

```
inmate 12 visitor 1  +40d 09:00-10:00 => BOOKED                  | Visit 101 booked
inmate 12 visitor 36 +40d 10:00-11:00 => DENIED_BLACKLISTED      | Visitor is blacklisted
inmate 12 visitor 31 +40d 10:00-11:00 => DENIED_UNAPPROVED       | Visitor is not approved
inmate 3  visitor 5  +40d 10:00-11:00 => DENIED_CONFLICT         | A conflict exists between this visitor and inmate
inmate 46 visitor 1  +40d 10:00-11:00 => DENIED_INMATE_INACTIVE  | Inmate is not ACTIVE
inmate 12 visitor 1  +40d 09:00-10:00 => DENIED_DUPLICATE        | The inmate already has a booking in this slot
inmate 12 visitor 1  +-3d 09:00-10:00 => DENIED_PAST_DATE        | Visits cannot be booked in the past
inmate 14 visitor 1  +60d 10:00-11:00 => DENIED_OUTSIDE_SENTENCE | Date is outside the inmate's sentence period
```

`sp_transfer_inmate` calls:

```
inmate 1    -> block 4  => TRANSFERRED      | Inmate 1 moved from block 1 to D-Block
inmate 2    -> block 4  => BLOCK_FULL       | D-Block is full (10/10)
inmate 27   -> block 1  => SECURITY_MISMATCH| Inmate risk HIGH exceeds A-Block security level LOW
inmate 4    -> block 2  => RIVAL_IN_BLOCK   | A rival of this inmate is housed in B-Block
inmate 9999 -> block 2  => NOT_FOUND        | Inmate 9999 does not exist
inmate 5    -> block 99 => BLOCK_NOT_FOUND  | Block 99 does not exist
inmate 46   -> block 2  => INMATE_NOT_ACTIVE| Only ACTIVE inmates can be moved (status is TRANSFERRED)
inmate 5    -> block 1  => SAME_BLOCK       | Inmate is already in A-Block
```

Registration / conflicts:

```
register: REGISTERED | Visitor 41 registered with status PENDING
register again: DUPLICATE_ID | A visitor with this ID proof is already registered
approve: UPDATED | Visitor 41 is now APPROVED
add conflict: CONFLICT_ADDED | Conflict recorded
book while in conflict: DENIED_CONFLICT
resolve: RESOLVED | Conflict 27 resolved
book after resolve: BOOKED
blacklist: UPDATED | Visitor 41 is now BLACKLISTED; 1 future visit(s) cancelled
```
Call from SQL*Plus:

```sql
VARIABLE s VARCHAR2(40)
VARIABLE v NUMBER
VARIABLE m VARCHAR2(400)
EXEC sp_schedule_visit(12, 1, TRUNC(SYSDATE)+40, '09:00-10:00', :s, :v, :m);
PRINT s v m
```

## 7. Data flow and integration

```
 sp_schedule_visit ─lock─► INMATES row ─lock─► VISIT_SLOTS row ─► fn_is_visitor_eligible ─► counts
        │ denial ─► sp_log_audit_auto (autonomous) ─► ROLLBACK TO SAVEPOINT ─► status DENIED_* / SLOT_FULL
        └ ok ─► INSERT VISITS ─► triggers 07 ─► trg_audit_visits ─► COMMIT ─► BOOKED
 sp_transfer_inmate ─lock─► INMATES row ─lock─► BLOCKS row ─► checks ─► UPDATE INMATES ─► triggers 08 (MOVEMENTS, AUDIT_LOG) ─► COMMIT
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-06550` / `PLS-00905: object is invalid` | A dependency (function/trigger table) is missing or invalid | `SELECT object_name, status FROM user_objects WHERE status <> 'VALID'`; recompile with `ALTER PROCEDURE x COMPILE`. |
| Procedure hangs | Another session holds the inmate/slot/block lock (e.g. demo session with `p_auto_commit => 'N'`) | COMMIT/ROLLBACK the other session; see `V$LOCK` or `DBA_BLOCKERS`. |
| `PLS-00306: wrong number or types of arguments` | Wrong parameter list | Check with `DESC sp_schedule_visit`. |
| OUT parameter is NULL after a failed registration | Failure paths set `p_visitor_id := NULL` | Use a separate variable per call (found while writing the examples). |
| `ORA-01403 no data found` in your own block | SELECT INTO with no row | Handle NO_DATA_FOUND. |

## 9. Viva questions and answers

**Q1. Why status codes instead of letting the error propagate?**  
Staff get a clear business answer (SLOT_FULL), the caller is never exposed to ORA- text, and the procedure can still roll back cleanly (F23).

**Q2. Explain SELECT ... FOR UPDATE in sp_transfer_inmate.**  
It locks the inmate and target-block rows until COMMIT/ROLLBACK, so two concurrent transfers into the last bed are serialised and the second sees the true occupancy.

**Q3. Why lock in a fixed order?**  
If two sessions locked the same rows in opposite orders they could deadlock.

**Q4. What does ROLLBACK TO SAVEPOINT do versus ROLLBACK?**  
It undoes only the work after the savepoint and keeps earlier work and the transaction open.

**Q5. What is definer's rights good for?**  
The front desk can book visits through the procedure while having no privilege on the VISITS table.

**Q6. Why log denials with an autonomous transaction when the procedure rolls back?**  
The rollback would erase a normal audit row; the autonomous commit keeps it.

**Q7. IN, OUT, IN OUT?**  
Read-only input, write-only output, both.

## 10. Important practical commands

```
DESC sp_schedule_visit
SELECT text FROM user_source WHERE name = 'SP_SCHEDULE_VISIT' ORDER BY line;
SELECT object_name, status FROM user_objects WHERE object_type = 'PROCEDURE';
-- test a transfer
EXEC sp_transfer_inmate(1, 4, 'manual test', :s, :m)
-- see locks held by other sessions
SELECT * FROM user_errors;
```

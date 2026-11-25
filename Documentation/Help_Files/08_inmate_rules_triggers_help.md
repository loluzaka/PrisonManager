# Help: `08_inmate_rules_triggers.sql`

## 1. File overview

* **Exact filename:** `08_inmate_rules_triggers.sql`
* **Location:** `sql/`
* **Purpose:** Two triggers on INMATES: TRG_INMATE_PLACEMENT_RULES (compound: security level, capacity, rivals) and TRG_LOG_MOVEMENT (writes MOVEMENTS and a TRANSFER audit row).
* **Feature(s):** F15 (block capacity and security-level rules), F21 (movement logging trigger)
* **Member responsibility:** Member 2
* **Role in the system:** Guarantees that no inmate can be placed in a full or too-low-security block, or next to a rival, and that no move is ever unrecorded - even by a direct UPDATE.
* **Execution order:** After 07; before procedures (09).

## 2. Required database objects and dependencies

* **Fires on:** INMATES. **Reads:** BLOCKS, INMATES (AFTER STATEMENT), INMATE_CONFLICTS. **Writes:** MOVEMENTS, AUDIT_LOG.
* **Calls:** `fn_level_rank`, `sp_log_audit`, package variable `pkg_prison_rules.g_transfer_reason`.
* **Used with:** `sp_transfer_inmate` (09).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **COMPOUND TRIGGER** | One trigger with several timing sections (BEFORE STATEMENT, BEFORE EACH ROW, AFTER EACH ROW, AFTER STATEMENT) sharing variables. The standard cure for the mutating-table problem: collect keys per row, query in AFTER STATEMENT. | `FOR INSERT OR UPDATE ON t COMPOUND TRIGGER ... AFTER STATEMENT IS BEGIN ... END AFTER STATEMENT; END;` | `trg_inmate_placement_rules`: BEFORE EACH ROW checks the risk/security match; AFTER EACH ROW collects (inmate, block); AFTER STATEMENT counts occupants and looks for rivals. |
| **CREATE TRIGGER** | Code that the database runs automatically when a table is changed. Cannot be bypassed by application code. | `CREATE TRIGGER t BEFORE|AFTER INSERT OR UPDATE ON tbl [FOR EACH ROW] ...` | `trg_log_movement` is a normal AFTER row trigger. |
| **BEFORE / AFTER** | Timing: BEFORE fires before the row change (good for validation / modifying :NEW), AFTER fires after it (good for logging to other tables). | `BEFORE INSERT ON visits` | Security check BEFORE the row; movement logging AFTER (the inmate row must exist for the foreign key of MOVEMENTS). |
| **:OLD / :NEW** | Column values of the row before (:OLD) and after (:NEW) the change. INSERT has no :OLD, DELETE has no :NEW. | `:NEW.status, :OLD.block_id` | `:OLD.block_id` -> `:NEW.block_id` is the movement. |
| **INSERTING / UPDATING** | Boolean flags telling a multi-event trigger which statement fired it. | `IF INSERTING THEN ... ELSIF UPDATING THEN ...` | `INSERTING` = admission (from_block NULL); `UPDATING AND :OLD.block_id <> :NEW.block_id` = a real transfer (UPDATE OF fires even if the value is unchanged). |
| **RAISE_APPLICATION_ERROR** | Raises a custom error with a code in -20000..-20999 and a message; rolls back the statement. | `RAISE_APPLICATION_ERROR(-20102, 'Visitor is blacklisted');` | -20201 block full, -20202 risk above security, -20203 rival in block. |
| **INSERT** | Adds rows. | `INSERT INTO t (cols) VALUES (...); INSERT INTO t (cols) SELECT ...;` | Into MOVEMENTS from the trigger. |
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | Capacity, occupancy and rival queries. |
| **JOIN** | Combines rows of two tables on a condition. INNER keeps matches; LEFT/RIGHT keep all rows of one side; FULL keeps both; SELF joins a table to itself. | `FROM a INNER JOIN b ON a.id = b.a_id` | Rival query joins INMATE_CONFLICTS to INMATES using a CASE to pick "the other inmate". |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | Picks the other member of a rivalry pair. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | `NO_DATA_FOUND` for an unknown block is ignored (the FK reports it). |

**Common mistakes with these keywords**

* *COMPOUND TRIGGER*: Querying the triggering table in AFTER EACH ROW is still ORA-04091.
* *CREATE TRIGGER*: A trigger that queries its own table in a row trigger -> ORA-04091 (mutating table).
* *BEFORE / AFTER*: Trying to change :NEW in an AFTER trigger.
* *:OLD / :NEW*: In the WHEN clause write NEW/OLD without the colon.
* *RAISE_APPLICATION_ERROR*: Codes outside -20000..-20999 are rejected (ORA-21000).
* *INSERT*: Omitting the column list - breaks when columns are added later.
* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *JOIN*: Forgetting the ON condition produces a Cartesian product (rows x rows).
* *CASE*: Missing ELSE returns NULL.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.

## 4. Tables and columns involved

### INMATES

A person serving a sentence. Never deleted: status changes instead (soft delete).

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **INMATE_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **INMATE_NO** | VARCHAR2(20) | NOT NULL | `—` | — | Unique prisoner number, e.g. INM-0001. |
| 3 | **FULL_NAME** | VARCHAR2(100) | NOT NULL | `—` | — | Synthetic name. |
| 4 | **DATE_OF_BIRTH** | DATE | NOT NULL | `—` | — | Date of birth (synthetic). |
| 5 | **ADMISSION_DATE** | DATE | NOT NULL | `TRUNC(SYSDATE)` | — | Day the inmate was admitted; defaults to today. |
| 6 | **SENTENCE_START** | DATE | NOT NULL | `—` | CK CK_INMATES_SENTENCE | First day of the sentence. |
| 7 | **SENTENCE_END** | DATE | NOT NULL | `—` | CK CK_INMATES_SENTENCE | Release date; must be after SENTENCE_START. Visits are only allowed inside the sentence period. |
| 8 | **STATUS** | VARCHAR2(12) | NOT NULL | `'ACTIVE'` | CK CK_INMATES_STATUS | ACTIVE (housed), TRANSFERRED (moved to an outside prison) or RELEASED. Only ACTIVE inmates count towards block occupancy and can receive visits. |
| 9 | **BLOCK_ID** | NUMBER | NOT NULL | `—` | FK → BLOCKS | Block where the inmate lives (or last lived). |
| 10 | **RISK_LEVEL** | VARCHAR2(10) | NOT NULL | `'LOW'` | CK CK_INMATES_RISK | LOW, MEDIUM or HIGH (added by ALTER, F15). Must not exceed the block security level. |

Unique constraints: `UQ_INMATES_NO`

Check constraints:

* `CK_INMATES_RISK` — `risk_level IN ('LOW','MEDIUM','HIGH')`
* `CK_INMATES_SENTENCE` — `sentence_end > sentence_start`
* `CK_INMATES_STATUS` — `status IN ('ACTIVE','TRANSFERRED','RELEASED')`

Relationships: `BLOCK_ID` → **BLOCKS** (`FK_INMATES_BLOCK`, on delete NO ACTION)

### MOVEMENTS

History of every block change, including admission. References BLOCKS twice.

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **MOVEMENT_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **INMATE_ID** | NUMBER | NOT NULL | `—` | FK → INMATES | Inmate moved. |
| 3 | **FROM_BLOCK** | NUMBER | NULL | `—` | FK → BLOCKS; CK CK_MOV_DIFF | Origin block; NULL for an admission. |
| 4 | **TO_BLOCK** | NUMBER | NOT NULL | `—` | FK → BLOCKS; CK CK_MOV_DIFF | Destination block. |
| 5 | **MOVEMENT_DATE** | TIMESTAMP(6) | NOT NULL | `SYSTIMESTAMP` | — | When the move happened. |
| 6 | **REASON** | VARCHAR2(200) | NULL | `—` | — | Free text reason (ADMISSION, transfer reason, ...). |
| 7 | **MOVED_BY** | VARCHAR2(60) | NOT NULL | `SYS_CONTEXT('USERENV','SESSION_USER')` | — | Database user who made the change. |

Check constraints:

* `CK_MOV_DIFF` — `from_block IS NULL OR from_block <> to_block`

Relationships: `FROM_BLOCK` → **BLOCKS** (`FK_MOV_FROM`, on delete NO ACTION); `INMATE_ID` → **INMATES** (`FK_MOV_INMATE`, on delete NO ACTION); `TO_BLOCK` → **BLOCKS** (`FK_MOV_TO`, on delete NO ACTION)

**Why this structure:** Occupancy is *counted* (ACTIVE inmates per block), never stored, so it can never drift. The reason for a transfer travels in a package variable because a trigger cannot receive parameters.

## 5. Walkthrough

**Placement trigger.**
1. *BEFORE EACH ROW* (only for ACTIVE rows): read the block's security level; if `fn_level_rank(:NEW.risk_level) > fn_level_rank(security)` -> -20202.
2. *AFTER EACH ROW*: remember (inmate_id, block_id).
3. *AFTER STATEMENT*: for each remembered pair count ACTIVE inmates in that block; `> capacity` -> -20201 (the new row is already counted). Then look for an unresolved rival of the inmate who is ACTIVE in the same block -> -20203.

**Movement trigger.** INSERT -> row (inmate, NULL -> block, 'ADMISSION'). UPDATE with a changed block -> movement (old -> new) with the reason from `g_transfer_reason` or the default text *Direct update of INMATES.block_id*, plus a `TRANSFER` row in AUDIT_LOG (`Block 1 -> 4; reason=...`).

**Why both?** `sp_transfer_inmate` checks the same rules first and answers with friendly statuses; these triggers are the safety net for direct SQL. Neither can see another session's *uncommitted* rows, so the procedure also locks the target block row.

## 6. Actual execution example

Real output:

```
full block: ORA-20201: Placement refused: block E-Block is full (capacity 6)
security:   ORA-20202: Placement refused: inmate risk HIGH exceeds block security level LOW
rival:      ORA-20203: Placement refused: a rival of inmate 4 lives in block B-Block
```

Movement written by the trigger after `sp_transfer_inmate(1, 4, 'help-file demo')`:

```
MOVEMENT_ID INMATE_ID FROM_BLOCK TO_BLOCK REASON          MOVED_BY
         59         1                   1 ADMISSION       SEED
        117         1          1        4 help-file demo  PRISON_OWNER

AUDIT_ID ACTION_TYPE RECORD_ID DETAILS
      26 TRANSFER            1 Block 1 -> 4; reason=help-file demo
```
Tests F16-F23 assert the direct-UPDATE and INSERT cases.

## 7. Data flow and integration

```
 UPDATE/INSERT INMATES ──► trg_inmate_placement_rules  (security | collect | capacity + rivals) ──► may refuse with ORA-2020x
                       ──► trg_log_movement ──► MOVEMENTS + AUDIT_LOG 'TRANSFER'
                       ──► trg_audit_inmates (status/risk/name changes only)
 sp_transfer_inmate ─sets g_transfer_reason─► UPDATE ─► (the triggers above)
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-04091` on INMATES | A row trigger queried INMATES | Only AFTER STATEMENT may count INMATES. |
| Movement reason always "Direct update..." | `g_transfer_reason` not set or reset too early | Set it just before the UPDATE; the procedure clears it afterwards. |
| `ORA-02291` on MOVEMENTS insert | AFTER trigger missing: used BEFORE | Keep `trg_log_movement` AFTER so the inmate row exists. |
| Two movement rows for one transfer | Both the procedure and trigger insert | Only the trigger inserts; the procedure just updates INMATES. |

## 9. Viva questions and answers

**Q1. How do you avoid the mutating-table error?**  
Compound trigger: collect in AFTER EACH ROW, query in AFTER STATEMENT.

**Q2. Why does the movement trigger use UPDATE OF block_id?**  
It fires only when that column appears in the SET list; the body still compares :OLD and :NEW.

**Q3. Can a race still overfill a block?**  
Via direct UPDATEs yes, because triggers cannot see uncommitted rows of other sessions; sp_transfer_inmate prevents it by locking the target block row (X02-style test for slots shows the effect).

**Q4. Why store risk and security as LOW/MEDIUM/HIGH text but compare numerically?**  
Readable data, comparable via `fn_level_rank`.

**Q5. What do :OLD and :NEW contain on INSERT?**  
:OLD is null; :NEW has the inserted values.

## 10. Important practical commands

```
SELECT trigger_name, trigger_type, triggering_event FROM user_triggers WHERE table_name = 'INMATES';
SELECT * FROM v_movement_history WHERE inmate_id = 1 ORDER BY movement_date;
SELECT * FROM audit_log WHERE action_type = 'TRANSFER' ORDER BY audit_id DESC;
UPDATE inmates SET block_id = 5 WHERE inmate_id = 2;          -- ORA-20201 (E-Block is full)
```

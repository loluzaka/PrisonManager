# Help: `07_visit_rules_triggers.sql`

## 1. File overview

* **Exact filename:** `07_visit_rules_triggers.sql`
* **Location:** `sql/`
* **Purpose:** Two triggers on VISITS: TRG_BLOCK_CONFLICT_VISIT refuses ineligible visitors; TRG_VISIT_SLOT_RULES (compound) enforces the sentence period, weekly limit and slot capacity.
* **Feature(s):** F13 (visit eligibility trigger), F16 (visit slot rules - trigger part)
* **Member responsibility:** Member 2
* **Role in the system:** Last line of defence: protects VISITS even when someone inserts rows directly instead of using `sp_schedule_visit`.
* **Execution order:** After 05 and 06; before the procedures (09).

## 2. Required database objects and dependencies

* **Fires on:** VISITS. **Reads:** VISITORS, INMATES, CONFLICTS (via `fn_is_visitor_eligible`), INMATES (sentence), VISIT_SLOTS, VISITS (in AFTER STATEMENT only).
* **Calls:** `fn_is_visitor_eligible`, `sp_log_audit_auto`, `pkg_prison_rules.c_max_visits_per_week`.
* **Interacts with:** `trg_audit_visits` (logs successful bookings), `sp_schedule_visit`.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CREATE TRIGGER** | Code that the database runs automatically when a table is changed. Cannot be bypassed by application code. | `CREATE TRIGGER t BEFORE|AFTER INSERT OR UPDATE ON tbl [FOR EACH ROW] ...` | `trg_block_conflict_visit` (simple) and `trg_visit_slot_rules` (compound). |
| **BEFORE / AFTER** | Timing: BEFORE fires before the row change (good for validation / modifying :NEW), AFTER fires after it (good for logging to other tables). | `BEFORE INSERT ON visits` | Eligibility is checked BEFORE the row is written; counts are checked AFTER the statement. |
| **FOR EACH ROW** | Row-level trigger: runs once per affected row and can use :OLD and :NEW. Without it the trigger is statement-level (once per statement). | `CREATE TRIGGER ... FOR EACH ROW BEGIN ... END;` | The eligibility trigger runs per row. |
| **:OLD / :NEW** | Column values of the row before (:OLD) and after (:NEW) the change. INSERT has no :OLD, DELETE has no :NEW. | `:NEW.status, :OLD.block_id` | `:NEW.visitor_id`, `:NEW.inmate_id`, `:NEW.visit_date`, `:NEW.slot`, `:NEW.status`. |
| **COMPOUND TRIGGER** | One trigger with several timing sections (BEFORE STATEMENT, BEFORE EACH ROW, AFTER EACH ROW, AFTER STATEMENT) sharing variables. The standard cure for the mutating-table problem: collect keys per row, query in AFTER STATEMENT. | `FOR INSERT OR UPDATE ON t COMPOUND TRIGGER ... AFTER STATEMENT IS BEGIN ... END AFTER STATEMENT; END;` | Four sections of one trigger share the collection `g_keys`: BEFORE EACH ROW (sentence), AFTER EACH ROW (remember the row), AFTER STATEMENT (count weekly / slot totals). |
| **RAISE_APPLICATION_ERROR** | Raises a custom error with a code in -20000..-20999 and a message; rolls back the statement. | `RAISE_APPLICATION_ERROR(-20102, 'Visitor is blacklisted');` | Codes -20101 unapproved, -20102 blacklisted, -20103 conflict, -20104 inmate inactive, -20105 weekly limit, -20106 slot full, -20107 outside sentence. |
| **PRAGMA AUTONOMOUS_TRANSACTION** | Makes a subprogram run in its OWN transaction that commits independently of the caller. | `PRAGMA AUTONOMOUS_TRANSACTION; ... COMMIT;` | Used indirectly through `sp_log_audit_auto` before every RAISE so the refusal is logged. |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | Maps the reason text to the right error code. |
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | `SELECT ... INTO` and COUNT in the AFTER STATEMENT section. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | `NO_DATA_FOUND` is ignored for an unknown inmate: the FOREIGN KEY will report it. |
| **SQLCODE / SQLERRM** | Error number and message of the exception being handled. | `WHEN OTHERS THEN v := SQLCODE; m := SQLERRM;` | Callers see ORA-201xx in SQLERRM. |

**Common mistakes with these keywords**

* *CREATE TRIGGER*: A trigger that queries its own table in a row trigger -> ORA-04091 (mutating table).
* *BEFORE / AFTER*: Trying to change :NEW in an AFTER trigger.
* *FOR EACH ROW*: Using :NEW in a statement-level trigger -> PLS-00049.
* *:OLD / :NEW*: In the WHEN clause write NEW/OLD without the colon.
* *COMPOUND TRIGGER*: Querying the triggering table in AFTER EACH ROW is still ORA-04091.
* *RAISE_APPLICATION_ERROR*: Codes outside -20000..-20999 are rejected (ORA-21000).
* *PRAGMA AUTONOMOUS_TRANSACTION*: Forgetting the COMMIT -> ORA-06519.
* *CASE*: Missing ELSE returns NULL.
* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *SQLCODE / SQLERRM*: Calling them outside an exception handler gives 0 / "normal".

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

**Why this structure:** `uq_visits_inmate_slot` and `ck_visits_slot` are enforced by the database engine itself; the triggers cover the rules a constraint cannot express (they need other tables or other rows).

## 5. Walkthrough

**`trg_block_conflict_visit` (BEFORE INSERT, row).**
1. Call `fn_is_visitor_eligible(:NEW.visitor_id, :NEW.inmate_id)`.
2. `ELIGIBLE`, `NO_VISITOR` or `NO_INMATE` -> `RETURN` (unknown ids are left to the foreign keys, which raise ORA-02291).
3. Otherwise **log first** with `sp_log_audit_auto('VISITORS','VISIT_DENIED', visitor_id, ...)` (autonomous), **then** `RAISE_APPLICATION_ERROR` with the reason-specific code. The INSERT is rolled back; the log row stays.

**`trg_visit_slot_rules` (compound).** A plain row trigger that counted VISITS would raise ORA-04091 (mutating table). So:
* *BEFORE EACH ROW*: for non-cancelled rows read the inmate's sentence dates (INMATES is another table, so this is allowed); outside the period -> -20107.
* *AFTER EACH ROW*: only store (inmate, visitor, date, slot) in `g_keys`; no query on VISITS is allowed here.
* *AFTER STATEMENT*: for each stored key count non-cancelled visits in the same ISO week (> 3 -> -20105) and in the same date+slot (> `max_visitors` -> -20106). The new rows are already inserted, hence `>` not `>=`.
Local procedure `refuse` logs the denial and raises.

**Limit:** triggers see only committed rows of *other* sessions, so two sessions filling the last place simultaneously can both pass. `sp_schedule_visit` closes that gap with row locks; script 20/21 demonstrates both outcomes.

## 6. Actual execution example

Real output (direct INSERT of a blacklisted visitor):

```
BEGIN INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (22, 37, TRUNC(SYSDATE)+45, '10:00-11:00');
ORA-20102: Visit refused: visitor is blacklisted
ORA-06512: at "PRISON_OWNER.TRG_BLOCK_CONFLICT_VISIT", line 19
ORA-04088: error during execution of trigger 'PRISON_OWNER.TRG_BLOCK_CONFLICT_VISIT'
```

Tests D22-D29 (all PASS): -20102, -20101, -20103, -20104, weekly -20105, slot -20106, sentence -20107. D23 proves the denial row exists after the ROLLBACK (count 2 = 1 seed + 1 new).

## 7. Data flow and integration

```
 INSERT INTO visits ──► trg_block_conflict_visit ──ineligible──► sp_log_audit_auto ──► AUDIT_LOG (committed)
                                                 └──────────────► ORA-2010x, row rolled back
                  ──► trg_visit_slot_rules: BEFORE ROW (sentence) ► AFTER ROW (collect) ► AFTER STATEMENT (weekly, slot)
                  ──► constraints (UNIQUE, CHECK, FK) ──► trg_audit_visits (VISIT_BOOKED)
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-04091: table PRISON_OWNER.VISITS is mutating` | A ROW trigger queried VISITS | Move the query into AFTER STATEMENT of a compound trigger (as done here). |
| `ORA-04088` wrapping `ORA-201xx` | Normal: Oracle wraps errors raised inside triggers | Read the first ORA- line; the code tells the rule. |
| Denial not in the audit log | The log call was after the RAISE | Log first, then raise. |
| `PLS-00201 identifier SP_LOG_AUDIT_AUTO must be declared` | Script 06 not run yet | Run scripts in order. |
| Seed fails with ORA-04091 | INSERT...SELECT into VISITS with triggers enabled | The seed disables triggers while loading. |

## 9. Viva questions and answers

**Q1. BEFORE vs AFTER trigger?**  
BEFORE runs before the row is written (validation, changing :NEW); AFTER runs once the change is accepted (logging, cross-table effects).

**Q2. What are :OLD and :NEW?**  
The row before and after the change; INSERT has only :NEW, DELETE only :OLD.

**Q3. Why a compound trigger?**  
To avoid the mutating-table error: collect keys row by row, count in AFTER STATEMENT.

**Q4. Why log before raising?**  
RAISE_APPLICATION_ERROR rolls back the statement; the autonomous log is committed independently and so survives.

**Q5. Why is the trigger still needed if the procedure already checks?**  
Someone may INSERT directly; the trigger makes the rule impossible to bypass.

**Q6. Row-level vs statement-level?**  
Row-level fires per row (can use :NEW); statement-level once per statement.

## 10. Important practical commands

```
SELECT trigger_name, trigger_type, triggering_event, status FROM user_triggers WHERE table_name = 'VISITS';
SELECT text FROM user_source WHERE name = 'TRG_BLOCK_CONFLICT_VISIT' ORDER BY line;
ALTER TRIGGER trg_visit_slot_rules DISABLE;       -- demos only; re-enable with ENABLE
INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (22, 37, TRUNC(SYSDATE)+45, '10:00-11:00');
```

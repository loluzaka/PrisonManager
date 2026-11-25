# Help: `05_package_and_functions.sql`

## 1. File overview

* **Exact filename:** `05_package_and_functions.sql`
* **Location:** `sql/`
* **Purpose:** Defines package PKG_PRISON_RULES (constants, named exceptions, transfer-reason variable) and ten stored functions, including the shared visitor-eligibility rule.
* **Feature(s):** F19 (functions), F23 (user-defined exceptions), supports F13-F18
* **Member responsibility:** Member 2
* **Role in the system:** The "rule library": triggers and procedures call these functions so each rule exists in exactly one place.
* **Execution order:** After the seed (04); before the audit/trigger scripts (06-08) that call the functions.

## 2. Required database objects and dependencies

* **Reads:** VISITS, VISITORS, INMATES, CONFLICTS, VISIT_SLOTS, BLOCKS (functions are read-only).
* **Used by:** `trg_block_conflict_visit`, `trg_visit_slot_rules`, `trg_inmate_placement_rules`, `trg_log_movement` (package variable), all procedures, views `v_active_inmates`, `v_eligible_visitors`, cursor procedures.
* **Creates:** package PKG_PRISON_RULES; FN_LEVEL_RANK, FN_INMATE_VISIT_COUNT, FN_VISITOR_VISIT_COUNT, FN_BLOCK_OCCUPANCY, FN_HAS_ACTIVE_CONFLICT, FN_IS_VISITOR_ELIGIBLE, FN_DAYS_REMAINING, FN_WEEKLY_VISIT_COUNT, FN_SLOT_VISIT_COUNT, FN_NEXT_FREE_SLOT.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CREATE OR REPLACE** | Creates a stored program or replaces its previous version without dropping it (grants survive). | `CREATE OR REPLACE PROCEDURE p IS BEGIN ... END;` | Every object can be re-run without dropping it. |
| **FUNCTION** | A stored program that RETURNs exactly one value and can be used inside SQL. | `CREATE FUNCTION f (x NUMBER) RETURN NUMBER IS ... RETURN v;` | Ten functions, each RETURNs one value; **procedure vs function:** a function can be called inside SELECT (see the demo), a procedure is called as a statement and reports through OUT parameters. |
| **EXCEPTION_INIT** | Gives a name to an Oracle error number so it can be caught with WHEN name. | `e_x EXCEPTION; PRAGMA EXCEPTION_INIT(e_x, -20101);` | Eleven named exceptions in the package, e.g. `PRAGMA EXCEPTION_INIT(e_slot_full, -20106)`, so handlers can say `WHEN pkg_prison_rules.e_slot_full`. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | `NO_DATA_FOUND` is caught inside `fn_is_visitor_eligible` and `fn_days_remaining` to return a code / NULL instead of failing. |
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | `SELECT COUNT(*) INTO v ...` pattern in every counter function. |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | `fn_level_rank` maps LOW/MEDIUM/HIGH to 1/2/3 so levels can be compared with > and <. |
| **Scalar functions** | Row-level functions: UPPER, TRIM, SUBSTR, INSTR, REPLACE, LENGTH, ROUND, MOD, TO_CHAR, ADD_MONTHS, TRUNC(date) ... | `UPPER(TRIM(name))` | TRUNC(SYSDATE), TRUNC(date,'IW') (Monday of the ISO week), GREATEST, UPPER. |
| **IN / OUT / IN OUT** | Parameter modes: IN is read-only input, OUT is output, IN OUT both. | `p_status OUT VARCHAR2` | All function parameters are IN. |
| **%TYPE / %ROWTYPE** | Declare a variable with the same type as a column (%TYPE) or the same shape as a row/cursor (%ROWTYPE), so code survives column changes. | `v inmates.status%TYPE; r c_cur%ROWTYPE;` | `visitors.approval_status%TYPE` keeps the variable in step with the column. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | Formatting for the demo query at the end. |

**Common mistakes with these keywords**

* *CREATE OR REPLACE*: Compilation errors still create the object as INVALID - check with SHOW ERRORS.
* *FUNCTION*: A function with no RETURN on some path -> ORA-06503 at run time.
* *EXCEPTION_INIT*: Must be in the same declarative part as the exception.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *CASE*: Missing ELSE returns NULL.
* *Scalar functions*: Dates: SYSDATE includes the time; use TRUNC(SYSDATE) for "today".
* *IN / OUT / IN OUT*: An OUT parameter is NULL until assigned; a failed call may leave it NULL or reset it.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.

**DETERMINISTIC** (on `fn_level_rank`, `fn_diff`) promises the same input always gives the same output, letting Oracle cache results. **Package** = a named container; the *specification* (`CREATE PACKAGE`) declares what is public; here it only holds constants, exceptions and one variable so no body is needed.

## 4. Tables and columns involved

| Function | Reads | Returns |
|---|---|---|
| `fn_level_rank(level)` | - | 1/2/3 |
| `fn_inmate_visit_count(inmate_id)` | VISITS (SCHEDULED + COMPLETED) | count |
| `fn_visitor_visit_count(visitor_id)` | VISITS | count |
| `fn_block_occupancy(block_id)` | INMATES (status ACTIVE) | count |
| `fn_has_active_conflict(visitor, inmate)` | CONFLICTS (resolved = N and not expired) | 0 / 1 |
| `fn_is_visitor_eligible(visitor, inmate)` | VISITORS, INMATES, CONFLICTS | `ELIGIBLE`, `NO_VISITOR`, `NO_INMATE`, `BLACKLISTED`, `UNAPPROVED`, `CONFLICT`, `INMATE_INACTIVE` |
| `fn_days_remaining(inmate_id)` | INMATES | days left, 0 if over, NULL if unknown |
| `fn_weekly_visit_count(inmate, date)` | VISITS (non-cancelled, same ISO week) | count |
| `fn_slot_visit_count(date, slot)` | VISITS | count |
| `fn_next_free_slot(inmate, date)` | VISIT_SLOTS, VISITS | first slot with room, or NULL |

See the Data Dictionary for the tables themselves (`Documentation/Data_Dictionary.md`).

## 5. Walkthrough

**Package.** Constant `c_max_visits_per_week = 3`; variable `g_transfer_reason` is the "message in a bottle" `sp_transfer_inmate` fills so `trg_log_movement` can store the reason; eleven exceptions bound to the codes the triggers raise (-20101 ... -20301).

**`fn_is_visitor_eligible` - the heart.** 1) read the visitor's status (no row -> `NO_VISITOR`); 2) read the inmate's status (no row -> `NO_INMATE`); 3) `BLACKLISTED` first, then anything not APPROVED -> `UNAPPROVED`; 4) `fn_has_active_conflict = 1` -> `CONFLICT`; 5) inmate not ACTIVE -> `INMATE_INACTIVE`; otherwise `ELIGIBLE`. The order is deliberate: blacklisting is the strongest reason and is reported first.

**Counting functions.** All use `SELECT COUNT(*) INTO`. `fn_weekly_visit_count` compares `TRUNC(visit_date,'IW')` so Monday-Sunday is one bucket. `fn_next_free_slot` loops over the slots in time order and returns the first where the inmate has no visit and the slot is below its limit. (Its first version used a SQL `NOT EXISTS` directly inside a PL/SQL `IF`, which is illegal and gave a compile error; it now counts into a variable first.)

## 6. Actual execution example

Real output of the demo queries at the end of the file (fresh seed):

```
 INMATE_ID FULL_NAME              VISITS  DAYS_LEFT
         1 Dmitri Hussain              1        954
         3 Jamal Verma                 2          8
         8 Zane Garcia                 1       1332
        24 Wen Singh                   3       2896
        50 Arjun Ahmed                 0          0

BLACKLISTED   UNAPPROVED   CONFLICT   INMATE_INACTIVE   ELIGIBLE
```

(the second query calls `fn_is_visitor_eligible` for visitor 36, 31, 5/inmate 3, inactive inmate 46, and a normal pair.)

## 7. Data flow and integration

```
 FN_IS_VISITOR_ELIGIBLE ◄── trg_block_conflict_visit (BEFORE INSERT on VISITS)
                        ◄── sp_schedule_visit
 FN_BLOCK_OCCUPANCY     ◄── sp_transfer_inmate, pr_block_occupancy
 FN_WEEKLY/SLOT_VISIT_COUNT ◄── sp_schedule_visit, fn_next_free_slot
 PKG_PRISON_RULES.g_transfer_reason ──► trg_log_movement
```
Functions only read data; they modify nothing.

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `Warning: Function created with compilation errors` | Syntax/semantic error | `SHOW ERRORS FUNCTION fn_next_free_slot` or `SELECT * FROM user_errors WHERE name = ...`. |
| `PLS-00382: expression is of wrong type` / SQL inside IF | SQL clauses such as EXISTS cannot be used as PL/SQL conditions | SELECT COUNT(*) INTO a variable, then test the variable. |
| `ORA-06503: function returned without value` | A path has no RETURN | Make sure every branch ends in RETURN. |
| `ORA-04091` when used in a trigger | Function reads the table the trigger is firing on | Row triggers must not call functions that query their own table; the rules here avoid it (compound triggers). |

## 9. Viva questions and answers

**Q1. Procedure vs function?**  
A function returns one value and can be used in SQL; a procedure performs an action and returns through OUT parameters.

**Q2. Why is the eligibility rule a function?**  
The trigger and the procedure share it, so the rule is written once and cannot disagree.

**Q3. What does DETERMINISTIC mean?**  
Same input, same output, no side effects: Oracle may cache results.

**Q4. Why a package for constants and exceptions?**  
One public place; changing the weekly limit means editing one line.

**Q5. Why does `fn_days_remaining` return NULL for an unknown inmate but 0 for a released one?**  
NULL means "no such inmate", 0 means "sentence over" - different facts.

## 10. Important practical commands

```
SELECT fn_inmate_visit_count(12), fn_days_remaining(3) FROM dual;
SELECT fn_is_visitor_eligible(36, 12) FROM dual;                 -- BLACKLISTED
SELECT fn_next_free_slot(12, TRUNC(SYSDATE)) FROM dual;
SELECT object_name, status FROM user_objects WHERE object_type IN ('FUNCTION','PACKAGE');
SHOW ERRORS FUNCTION fn_next_free_slot
```

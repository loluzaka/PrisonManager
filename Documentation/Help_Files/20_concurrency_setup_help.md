# Help: `20_concurrency_setup.sql`

## 1. File overview

* **Exact filename:** `20_concurrency_setup.sql`
* **Location:** `sql/`
* **Purpose:** Prepares, checks and cleans the two-session concurrency scenario: slot 16:00-17:00 on day +21 gets four bookings so only one place is left.
* **Feature(s):** F24 (two-session concurrency demonstration)
* **Member responsibility:** Member 2
* **Role in the system:** Fixture for `21_concurrency_session.sql` and `scripts/concurrency_demo.ps1`.
* **Execution order:** Run with an argument: SETUP, then the two sessions, then CHECK, then CLEANUP.

## 2. Required database objects and dependencies

* **Calls:** `sp_schedule_visit` (4 times). **Reads/Deletes:** VISITS of that date and slot, VISIT_SLOTS.
* **Argument:** `&1` = SETUP | CHECK | CLEANUP.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **Substitution variables (&1, DEFINE)** | SQL*Plus replaces &name with text BEFORE sending the statement to the database. Script arguments are &1, &2, ... | `DEFINE pwd = &1` | `DEFINE action = &1` selects the branch. |
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | One block with IF/ELSIF on the action. |
| **DELETE** | Removes rows (can be rolled back, fires triggers). | `DELETE FROM t WHERE cond;` | Removes previous demo visits (SETUP, CLEANUP). |
| **PROCEDURE** | A stored program that performs an action; values go back through OUT parameters; called as a statement. | `CREATE PROCEDURE p (a IN NUMBER, b OUT VARCHAR2) IS ...` | Bookings through `sp_schedule_visit`. |
| **RAISE_APPLICATION_ERROR** | Raises a custom error with a code in -20000..-20999 and a message; rolls back the statement. | `RAISE_APPLICATION_ERROR(-20102, 'Visitor is blacklisted');` | Rejects unknown actions (-20999). |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | VERIFY/FEEDBACK off for clean output. |

**Common mistakes with these keywords**

* *Substitution variables (&1, DEFINE)*: A literal & in text triggers a prompt: use SET DEFINE OFF.
* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.
* *DELETE*: Forgetting WHERE deletes everything.
* *PROCEDURE*: Trying to use a procedure inside SELECT (that needs a function).
* *RAISE_APPLICATION_ERROR*: Codes outside -20000..-20999 are rejected (ORA-21000).
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.

## 4. Tables and columns involved

VISITS (inmates 1, 2, 4, 5 with visitors 21-24), VISIT_SLOTS (`max_visitors` 5).

## 5. Walkthrough

* **SETUP:** delete earlier demo rows, book four visits -> `slot ... now has 4 of 5 places taken`.
* **CHECK:** count non-cancelled visits of the slot, compare with `max_visitors` and print *capacity rule held* or *CAPACITY RULE BROKEN*.
* **CLEANUP:** delete the demo visits.

## 6. Actual execution example

Real output:

```
setup booking 1: BOOKED   ... setup booking 4: BOOKED
slot 16:00-17:00 on 24-NOV-2026 now has 4 of 5 places taken
RESULT: slot holds 5 visits, capacity is 5  --> capacity rule held        (SAFE scenario)
RESULT: slot holds 6 visits, capacity is 5  --> CAPACITY RULE BROKEN      (NAIVE scenario)
```

## 7. Data flow and integration

```
 SETUP ─► 4 bookings ─► [two sessions, script 21] ─► CHECK ─► CLEANUP
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-20999` | Wrong argument | Use SETUP, CHECK or CLEANUP. |
| A setup booking is denied | Previous run left rows or an inmate has a conflict | Run CLEANUP; the chosen inmates/visitors are conflict-free in the seed. |

## 9. Viva questions and answers

**Q1. Why set up exactly one free place?**  
The race only matters at the last place.

**Q2. Why use the procedure for the setup?**  
It also shows normal bookings working.

## 10. Important practical commands

```
@20_concurrency_setup.sql SETUP
@20_concurrency_setup.sql CHECK
@20_concurrency_setup.sql CLEANUP
```

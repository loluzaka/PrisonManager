# Help: `21_concurrency_session.sql`

## 1. File overview

* **Exact filename:** `21_concurrency_session.sql`
* **Location:** `sql/`
* **Purpose:** One of two competing sessions that try to take the last place in the slot, in NAIVE (no lock) or SAFE (sp_schedule_visit with row locks) mode.
* **Feature(s):** F24 (concurrency control, lost update / check-then-act race)
* **Member responsibility:** Member 2
* **Role in the system:** Shows with two real parallel sessions that triggers alone cannot prevent the race but row locks can.
* **Execution order:** Run twice in parallel after `20_concurrency_setup.sql SETUP` (`scripts/concurrency_demo.ps1` does it).

## 2. Required database objects and dependencies

* **Arguments:** `<NAIVE|SAFE> <label> <inmate> <visitor> <start_delay_s> <hold_s>`.
* **Calls:** `sp_schedule_visit(..., p_auto_commit => 'N')`, DBMS_SESSION.SLEEP. **Writes:** VISITS.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **SELECT ... FOR UPDATE** | Reads rows and LOCKS them until COMMIT/ROLLBACK; other sessions that try to lock or change them wait. | `SELECT ... FROM t WHERE ... FOR UPDATE;` | Taken inside `sp_schedule_visit` on the inmate row and slot row. |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | The session COMMITs after sleeping, holding locks (SAFE) or the uncommitted row (NAIVE) meanwhile. |
| **Isolation levels** | How much a transaction sees of other sessions' work. READ COMMITTED (default) = per statement; SERIALIZABLE = one snapshot for the transaction (ORA-08177 on conflict); READ ONLY = snapshot, no changes. | `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;` | Default READ COMMITTED: a session never sees another's uncommitted row. |
| **Substitution variables (&1, DEFINE)** | SQL*Plus replaces &name with text BEFORE sending the statement to the database. Script arguments are &1, &2, ... | `DEFINE pwd = &1` | Six arguments. |
| **IN / OUT / IN OUT** | Parameter modes: IN is read-only input, OUT is output, IN OUT both. | `p_status OUT VARCHAR2` | The procedure's OUT parameters return status. |
| **INSERT** | Adds rows. | `INSERT INTO t (cols) VALUES (...); INSERT INTO t (cols) SELECT ...;` | NAIVE inserts directly. |

**Common mistakes with these keywords**

* *SELECT ... FOR UPDATE*: Forgetting to end the transaction leaves the rows locked for everybody else.
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.
* *Isolation levels*: SET TRANSACTION must be the first statement of a transaction (ORA-01453).
* *Substitution variables (&1, DEFINE)*: A literal & in text triggers a prompt: use SET DEFINE OFF.
* *IN / OUT / IN OUT*: An OUT parameter is NULL until assigned; a failed call may leave it NULL or reset it.
* *INSERT*: Omitting the column list - breaks when columns are added later.

## 4. Tables and columns involved

VISITS and VISIT_SLOTS (slot 16:00-17:00, day +21).

## 5. Walkthrough

**NAIVE (check-then-act, no lock):** read the count (4), INSERT, sleep, COMMIT. Clerk B reads the count while A's row is uncommitted (still 4), inserts and commits at once. The compound trigger counts only committed rows plus the session's own, so it passes for both. After A commits the slot holds **6** in a 5-place slot.

**SAFE:** `sp_schedule_visit(..., 'N')` locks the inmate row and the slot row and books, the session sleeps 6 s holding the locks, then COMMITs. Clerk B calls the same procedure 2 s later and **waits** on the slot-row lock. When A commits, B's counts see 5 -> `SLOT_FULL`.

## 6. Actual execution example

Real output of one run (copied from `scripts/concurrency_demo.ps1`):

```
---- NAIVE scenario
[18:25:51.73] ClerkA (NAIVE) starts: inmate 6, visitor 25
[18:25:51.73] ClerkA sees 4 of 5 places taken
[18:25:53.73] ClerkB (NAIVE) starts: inmate 7, visitor 26
[18:25:53.74] ClerkB sees 4 of 5 places taken
[18:25:53.77] ClerkB finished: BOOKED (no lock)
[18:25:57.74] ClerkA finished: BOOKED (no lock)
RESULT: slot holds 6 visits, capacity is 5  --> CAPACITY RULE BROKEN (lost update / over-booking)

---- SAFE scenario
[18:26:00.95] ClerkA (SAFE) starts: inmate 6, visitor 25
[18:26:00.95] ClerkA procedure returned BOOKED (transaction still open)
[18:26:03.02] ClerkB (SAFE) starts: inmate 7, visitor 26
[18:26:06.95] ClerkA finished: BOOKED
[18:26:06.95] ClerkB procedure returned SLOT_FULL (transaction still open)   <- waited ~3.9 s for A's lock
RESULT: slot holds 5 visits, capacity is 5  --> capacity rule held
```
Tests X01 (6 visits - problem shown) and X02 (5 visits - fix works) PASS.

*(During development the first NAIVE version slept **before** inserting; clerk B then committed first and the trigger caught A's insert, hiding the problem. The sleep now sits between INSERT and COMMIT, the real race window.)*

## 7. Data flow and integration

```
 NAIVE: A: read 4, INSERT ........ COMMIT      B: read 4, INSERT, COMMIT   => 6 rows
 SAFE : A: lock inmate+slot, INSERT .... COMMIT   B: waits at the lock ...... sees 5 => SLOT_FULL
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Both sessions BOOKED in SAFE mode | Procedure called without locking (an old version) or different slots | Check `sp_schedule_visit` has the two FOR UPDATE selects. |
| `ORA-00060: deadlock detected` | Sessions locked in opposite order | Always lock inmate first, then slot (as the procedure does). |
| Demo sessions print nothing | Quoting problem when launching two processes from PowerShell | `concurrency_demo.ps1` uses background jobs with a single-quoted connect string. |

## 9. Viva questions and answers

**Q1. What is a lost update / check-then-act race?**  
Two sessions read the same state, both decide it is safe and both write; one decision is based on stale data.

**Q2. Why does the trigger not stop it?**  
A session cannot see another session's uncommitted rows, so each count looks fine.

**Q3. How do row locks fix it?**  
The second session waits for the first to commit and then sees the true count.

**Q4. Why lock in a fixed order?**  
To avoid deadlocks.

**Q5. What is READ COMMITTED?**  
Each statement sees only data committed before it started.

## 10. Important practical commands

```
.\scripts\concurrency_demo.ps1
-- by hand in two SQL*Plus windows:
@20_concurrency_setup.sql SETUP
@21_concurrency_session.sql SAFE ClerkA 6 25 0 6      -- window 1
@21_concurrency_session.sql SAFE ClerkB 7 26 2 0      -- window 2 (start within 2 s)
@20_concurrency_setup.sql CHECK
```

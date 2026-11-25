# Help: `19_transactions_demo.sql`

## 1. File overview

* **Exact filename:** `19_transactions_demo.sql`
* **Location:** `sql/`
* **Purpose:** Single-session demonstration of atomicity, durability, SAVEPOINT, consistency (failed transfer leaves nothing), isolation levels and row locks.
* **Feature(s):** F24 (transactions: COMMIT, ROLLBACK, SAVEPOINT, isolation levels, locks)
* **Member responsibility:** Member 2
* **Role in the system:** Teaching script for the ACID properties.
* **Execution order:** Demo; after the install.

## 2. Required database objects and dependencies

* **Writes (temporarily):** VISITORS rows `SYN-TXN%`, deleted at the end.
* **Calls:** `sp_transfer_inmate`. **Locks:** BLOCKS row 3.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | Parts A and B. |
| **SAVEPOINT** | A bookmark inside a transaction; ROLLBACK TO SAVEPOINT undoes only the work after it. | `SAVEPOINT s1; ... ROLLBACK TO SAVEPOINT s1;` | Part C: `ROLLBACK TO SAVEPOINT after_first_insert` keeps the first insert. |
| **Isolation levels** | How much a transaction sees of other sessions' work. READ COMMITTED (default) = per statement; SERIALIZABLE = one snapshot for the transaction (ORA-08177 on conflict); READ ONLY = snapshot, no changes. | `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;` | `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE` and `SET TRANSACTION READ ONLY`. |
| **SELECT ... FOR UPDATE** | Reads rows and LOCKS them until COMMIT/ROLLBACK; other sessions that try to lock or change them wait. | `SELECT ... FROM t WHERE ... FOR UPDATE;` | Locks block 3 until ROLLBACK. |
| **INSERT** | Adds rows. | `INSERT INTO t (cols) VALUES (...); INSERT INTO t (cols) SELECT ...;` | Demo rows. |
| **DELETE** | Removes rows (can be rolled back, fires triggers). | `DELETE FROM t WHERE cond;` | Cleanup. |
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | Part D block. |

**Common mistakes with these keywords**

* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.
* *SAVEPOINT*: Rolling back to a savepoint keeps the transaction open (and earlier locks).
* *Isolation levels*: SET TRANSACTION must be the first statement of a transaction (ORA-01453).
* *SELECT ... FOR UPDATE*: Forgetting to end the transaction leaves the rows locked for everybody else.
* *INSERT*: Omitting the column list - breaks when columns are added later.
* *DELETE*: Forgetting WHERE deletes everything.
* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.

**ACID:** Atomicity (all or nothing), Consistency (rules hold before and after), Isolation (concurrent transactions do not see each other's uncommitted work), Durability (committed data survives).

## 4. Tables and columns involved

VISITORS (demo rows), INMATES / MOVEMENTS (read to prove nothing changed), BLOCKS (locked).

## 5. Walkthrough

A. Insert, `SELECT COUNT(*)` shows 1 *inside* the transaction, ROLLBACK, count is 0 -> **atomicity**.
B. Insert, COMMIT -> row stays -> **durability**.
C. Two inserts with a SAVEPOINT between them; `ROLLBACK TO SAVEPOINT` removes only the second -> **partial rollback**.
D. `sp_transfer_inmate(27, 1, ...)` tries to move a HIGH-risk inmate to a LOW block: status SECURITY_MISMATCH, block and movement count unchanged -> **consistency / all-or-nothing**.
E. `COMMIT` first (SET TRANSACTION must be the first statement of a transaction - found when the script failed with ORA-01453), then SERIALIZABLE and READ ONLY snapshots, then a `FOR UPDATE` row lock released by ROLLBACK.
Cleanup deletes the demo visitors.

## 6. Actual execution example

Real output:

```
VISIBLE_INSIDE_MY_TRANSACTION 1      AFTER_ROLLBACK 0      AFTER_COMMIT 1
BOTH_ROWS_PRESENT 2                  ONLY_FIRST_ROW_LEFT SYN-TXN-C1
status=SECURITY_MISMATCH | Inmate risk HIGH exceeds A-Block security level LOW
block before=3 after=3 | movements before=1 after=1  (unchanged = rollback worked)
SERIALIZABLE_SNAPSHOT_COUNT 1      READ_ONLY_SNAPSHOT_COUNT 50
BLOCK_ID 3 C-Block 8 (locked)      TXN_DEMO_ROWS_LEFT 0
```

## 7. Data flow and integration

```
 session ─► INSERT (visible only to me) ─► ROLLBACK | COMMIT | ROLLBACK TO SAVEPOINT
 sp_transfer_inmate ─► check fails ─► ROLLBACK TO SAVEPOINT ─► no MOVEMENTS row
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-01453: SET TRANSACTION must be first statement of transaction` | A transaction is already open | COMMIT/ROLLBACK first. |
| `ORA-08177: can't serialize access` | SERIALIZABLE and another session changed the same rows | Retry the transaction. |
| Rows stay locked | Forgot COMMIT/ROLLBACK | End the transaction. |

## 9. Viva questions and answers

**Q1. Explain ACID with an example from this project.**  
Atomic: a failed transfer leaves no MOVEMENTS row; Consistent: capacity rules; Isolated: other sessions do not see uncommitted visits; Durable: committed bookings persist.

**Q2. What is a SAVEPOINT?**  
A bookmark inside a transaction to roll back part of it.

**Q3. Default isolation level in Oracle?**  
READ COMMITTED (statement-level read consistency).

**Q4. What does SELECT FOR UPDATE do?**  
Locks the selected rows until the transaction ends.

## 10. Important practical commands

```
@19_transactions_demo.sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT * FROM blocks WHERE block_id = 3 FOR UPDATE;
ROLLBACK;
```

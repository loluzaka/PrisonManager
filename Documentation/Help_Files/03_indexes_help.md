# Help: `03_indexes.sql`

## 1. File overview

* **Exact filename:** `03_indexes.sql`
* **Location:** `sql/`
* **Purpose:** Creates ten B-tree indexes on join/filter columns and proves with EXPLAIN PLAN that the optimizer uses an index (cost 89 -> 21).
* **Feature(s):** F5 (indexes for performance)
* **Member responsibility:** Member 1
* **Role in the system:** Performance layer; no behaviour change.
* **Execution order:** After `02_alter_schema.sql`; before the seed.

## 2. Required database objects and dependencies

* **Needs:** INMATES, VISITS, MOVEMENTS, AUDIT_LOG, BLOCKS.
* **Creates:** 10 `IDX_*` indexes; a scratch table `visits_big` (100,000 rows) that is dropped at the end.
* **Note:** CONFLICTS(inmate_id, visitor_id) is already indexed by `UQ_CONF_PAIR`, so no second index is created (it would raise ORA-01408).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CREATE INDEX** | Builds a B-tree structure that lets the optimizer find rows without scanning the whole table. | `CREATE INDEX idx ON t (col1, col2);` | Single-column indexes on foreign keys / filters and one composite `(inmate_id, visit_date)`. |
| **EXPLAIN PLAN** | Asks the optimizer how it WOULD run a statement without running it; DBMS_XPLAN.DISPLAY prints the plan. | `EXPLAIN PLAN FOR select...; SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);` | Run twice on the same query - before and after the index - to compare plans. |
| **CONNECT BY LEVEL** | Row generator: produces N rows from DUAL. | `SELECT LEVEL FROM dual CONNECT BY LEVEL <= 100` | Generates 100,000 rows for a realistic size. |
| **CREATE TABLE** | Defines a new table: its columns, data types and constraints. The table starts empty. | `CREATE TABLE name (col type [constraint], ..., [table constraint]);` | `visits_big AS SELECT ...` builds the demo table from a query. |
| **DROP TABLE** | Removes a table and its data. PURGE also skips the recycle bin. | `DROP TABLE t PURGE;` | Removes the scratch table. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | `SET ECHO ON/OFF`, `SET LINESIZE 160` format the plan output. |

**Common mistakes with these keywords**

* *CREATE INDEX*: Indexing a column that is already covered by a UNIQUE constraint -> ORA-01408.
* *EXPLAIN PLAN*: Reading the plan on an empty/small table: the optimizer then prefers a full scan.
* *CONNECT BY LEVEL*: Forgetting the upper bound gives an endless query.
* *CREATE TABLE*: Creating a child table before its parent (the FOREIGN KEY target must exist) -> ORA-00942.
* *DROP TABLE*: Dropping a parent first -> ORA-02449; drop children first.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.

## 4. Tables and columns involved

Indexed columns: `inmates(block_id)`, `inmates(status)`, `visits(visit_date)`, `visits(inmate_id, visit_date)`, `visits(visitor_id)`, `movements(inmate_id)`, `movements(to_block)`, `audit_log(table_name, record_id)`, `audit_log(action_type, changed_at)`, `blocks(facility_id)`.

Why: Oracle indexes primary and unique keys automatically but **not foreign keys**; unindexed FKs slow joins and make deleting a parent lock the child table. Composite order matters: `(inmate_id, visit_date)` serves `WHERE inmate_id = ?` and `WHERE inmate_id = ? AND visit_date = ?`, not a filter on `visit_date` alone. `idx_visits_inmate_date` overlaps the leading columns of `uq_visits_inmate_slot`; it is kept because the specification asks for it.

## 5. Walkthrough

1. Ten CREATE INDEX statements.
2. `visits_big` is created with 100,000 rows (`inmate_id` 1..5000, `visit_date` over 1000 days) and statistics are gathered.
3. `EXPLAIN PLAN` for `WHERE inmate_id = 43 AND visit_date = TRUNC(SYSDATE) - 42` -> **TABLE ACCESS FULL**, cost 89.
4. A composite index is created, statistics regathered, the same plan is explained -> **INDEX RANGE SCAN**, cost 21 (index step cost 1).
5. The scratch table is dropped.

## 6. Actual execution example

Real plans from the run:

```
---- Plan WITHOUT an index
| Id | Operation          | Name       | Cost (%CPU)|
|  1 |  TABLE ACCESS FULL | VISITS_BIG |    89   (2)|

---- Plan WITH the composite index
| Id | Operation                            | Name           | Cost (%CPU)|
|  1 |  TABLE ACCESS BY INDEX ROWID BATCHED | VISITS_BIG     |    21   (0)|
|  2 |   INDEX RANGE SCAN                   | IDX_VISITS_BIG |     1   (0)|
```

*(Lesson learned while building it: the first version used only 500 distinct inmates, 200 rows each, and the optimizer correctly kept the full scan. Index choice depends on selectivity.)*

## 7. Data flow and integration

```
 03_indexes.sql ──► indexes on INMATES / VISITS / MOVEMENTS / AUDIT_LOG / BLOCKS (used automatically by every later query)
                └─► scratch table visits_big (created, explained, dropped)
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-01408: such column list already indexed` | A UNIQUE constraint already created that index | Skip the CREATE INDEX or change the column order. |
| Plan still shows TABLE ACCESS FULL | Query returns too many rows, or statistics are stale | `EXEC DBMS_STATS.GATHER_TABLE_STATS(USER,'T')`; test with a more selective predicate. |
| `ORA-00955` | Index name exists | Drop the old index or pick another name. |

## 9. Viva questions and answers

**Q1. Why index foreign keys?**  
Joins and parent-row deletes use them; Oracle does not index FKs automatically.

**Q2. Does the order of columns in a composite index matter?**  
Yes: it can be used for a prefix of its columns (leftmost first).

**Q3. Do indexes always speed things up?**  
No: they cost space and slow INSERT/UPDATE; the optimizer ignores them when most of the table is needed.

**Q4. How do you see whether an index is used?**  
EXPLAIN PLAN / DBMS_XPLAN.DISPLAY: look for INDEX RANGE SCAN versus TABLE ACCESS FULL.

## 10. Important practical commands

```
SELECT index_name, table_name, uniqueness FROM user_indexes ORDER BY table_name;
SELECT index_name, column_position, column_name FROM user_ind_columns WHERE table_name='VISITS' ORDER BY index_name, column_position;
EXPLAIN PLAN FOR SELECT * FROM visits WHERE inmate_id = 12 AND visit_date = TRUNC(SYSDATE);
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

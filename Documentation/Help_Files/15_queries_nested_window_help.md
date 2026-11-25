# Help: `15_queries_nested_window.sql`

## 1. File overview

* **Exact filename:** `15_queries_nested_window.sql`
* **Location:** `sql/`
* **Purpose:** Subqueries, set operations, window functions, and OFFSET/FETCH pagination.
* **Feature(s):** F11 (nested queries and set operations), F12 (window functions), F36 (pagination)
* **Member responsibility:** Member 1 (F11) / Member 3 (F12)
* **Role in the system:** Advanced query collection.
* **Execution order:** Demo; after the install and the views.

## 2. Required database objects and dependencies

* **Reads:** INMATES, VISITS, VISITORS, BLOCKS, CONFLICTS, MOVEMENTS, AUDIT_LOG, views `v_block_occupancy`, `v_monthly_visit_stats`.
* **Modifies nothing.**

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **Subquery / EXISTS** | A SELECT inside another statement. EXISTS is true if the inner query returns any row; correlated subqueries refer to the outer row. | `WHERE NOT EXISTS (SELECT 1 FROM c WHERE c.x = o.x)` | Scalar subquery in HAVING, IN, EXISTS, NOT EXISTS, correlated subquery with MAX, inline view with ROWNUM. |
| **ANY / ALL** | Compare a value with every row of a subquery: ANY = at least one, ALL = every one. | `WHERE cap > ALL (SELECT cap FROM ...)` | N2: `capacity > ALL (...)`; N3: `capacity > ANY (...)`. |
| **UNION / INTERSECT / MINUS** | Set operations on two queries with matching columns: UNION (all distinct rows), INTERSECT (common rows), MINUS (rows only in the first; EXCEPT elsewhere). | `SELECT a FROM x MINUS SELECT a FROM y` | S1-S4; MINUS is Oracle's EXCEPT. |
| **Window functions** | Compute a value per row over a "window" of related rows without collapsing them. | `RANK() OVER (PARTITION BY g ORDER BY x DESC)` | RANK, DENSE_RANK, ROW_NUMBER with PARTITION BY; SUM() OVER (ORDER BY) running total; LAG; SUM() OVER (). |
| **GROUP BY / HAVING** | GROUP BY collapses rows into groups for aggregate functions; HAVING filters the groups (WHERE cannot, because it runs earlier). | `SELECT col, COUNT(*) FROM t GROUP BY col HAVING COUNT(*) > 1` | N1 compares each inmate's count with the average. |
| **JOIN** | Combines rows of two tables on a condition. INNER keeps matches; LEFT/RIGHT keep all rows of one side; FULL keeps both; SELF joins a table to itself. | `FROM a INNER JOIN b ON a.id = b.a_id` | Inside the window demo. |
| **Aggregate functions** | COUNT, SUM, AVG, MIN, MAX compute one value from many rows. | `COUNT(*), SUM(x), AVG(x), MIN(x), MAX(x)` | COUNT, AVG, MAX. |
| **OFFSET / FETCH** | Skips sorted rows and returns a bounded page. | `ORDER BY key OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY` | P1 returns the second five-row page of active inmates. |

**Common mistakes with these keywords**

* *Subquery / EXISTS*: NOT IN returns nothing if the subquery yields a NULL; prefer NOT EXISTS.
* *ANY / ALL*: > ALL over an empty set is TRUE.
* *UNION / INTERSECT / MINUS*: Column count/type mismatch -> ORA-01789.
* *Window functions*: Using them in WHERE: wrap the query and filter outside.
* *GROUP BY / HAVING*: Putting an aggregate in WHERE -> ORA-00934.
* *JOIN*: Forgetting the ON condition produces a Cartesian product (rows x rows).
* *Aggregate functions*: COUNT(col) skips NULLs, COUNT(*) does not.
* *OFFSET / FETCH*: Without a deterministic ORDER BY, rows can move between pages.

**Correlated subquery:** the inner query refers to a column of the outer row (`m2.inmate_id = m.inmate_id`) and is evaluated per outer row. **Inline view:** a subquery in FROM, used here to apply ROWNUM after sorting. **UNION ALL** keeps duplicates (UNION removes them).

## 4. Tables and columns involved

See `Documentation/Data_Dictionary.md`. Columns of note: `visits.inmate_id/visitor_id/visit_date`, `conflicts.resolved`, `movements.from_block`, `blocks.capacity/facility_id/security_level`.

## 5. Walkthrough

| ID | Technique | Question answered |
|---|---|---|
| N1 | scalar subquery in HAVING | inmates with more visits than average (12 inmates with 3 visits) |
| N2 | `> ALL` | facility-1 blocks bigger than every facility-2 block (A 14, B 12) |
| N3 | `> ANY` | blocks bigger than at least one HIGH block |
| N4 | NOT EXISTS | approved visitors with no conflict at all |
| N5 | EXISTS | visitors with at least one completed visit |
| N6 | correlated + MAX | latest movement of each inmate moved twice |
| N7 | IN subquery | inmates in HIGH-security blocks |
| N8 | inline view | block with the highest occupancy % (E-Block 100) |
| S1 | UNION | blacklisted visitors + visitors with active conflicts (10 rows) |
| S2 | INTERSECT | inmates with both a visit and a real transfer (7) |
| S3 | MINUS | inmates with visits but never transferred |
| S4 | UNION ALL | 108 rows = 100 visits + 8 audit denials |
| W1 | RANK/DENSE_RANK/ROW_NUMBER by block | ranking inmates by visits within each block |
| W2 | running total + LAG | cumulative visits by month and month-on-month change |
| W3 | ROW_NUMBER = 1 | most recent visit of each inmate |
| W4 | SUM() OVER () | block share of all inmates |
| P1 | OFFSET / FETCH | second page of five active inmates, ordered by inmate number |

## 6. Actual execution example

Real output:

```
W2  VISIT_M  VISITS RUNNING_TOTAL CHANGE_VS_PREV_MONTH
    2026-08      17            17
    2026-09      33            50                   16
    2026-10      34            84                    1
    2026-11      16           100                  -18

W1  A-Block INM-0003 3 rank 1 row 1 | INM-0007 3 rank 1 row 2 | INM-0010 3 rank 1 row 3 | INM-0002 2 rank 4 ... (RANK skips 2,3; DENSE_RANK does not)

S1  3 4 5 7 9 12 20 ACTIVE CONFLICT / 36 37 38 BLACKLISTED
```

## 7. Data flow and integration

```
 tables/views ──nested queries / set ops / windows──► result sets (read-only)
 inmates ──ORDER BY + OFFSET / FETCH──► one deterministic page of rows
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-01427: single-row subquery returns more than one row` | Scalar subquery returned several rows | Use IN/ANY/ALL or aggregate. |
| `ORA-01789: query block has incorrect number of result columns` | UNION/INTERSECT/MINUS branches differ in column count | Match columns and types. |
| `ORA-30483: window functions are not allowed here` | Window function in WHERE / GROUP BY | Wrap in an inline view and filter outside. |
| Pages repeat or skip rows | ORDER BY does not uniquely order records | Add a stable tie-breaker, such as a primary key. |
| NOT IN returns nothing | Subquery contains NULL | Use NOT EXISTS. |

## 9. Viva questions and answers

**Q1. Correlated vs ordinary subquery?**  
A correlated subquery refers to the outer row and runs per row; an ordinary one runs once.

**Q2. EXISTS vs IN?**  
EXISTS stops at the first match and handles NULLs safely; IN compares against a list.

**Q3. RANK vs DENSE_RANK vs ROW_NUMBER?**  
RANK leaves gaps after ties, DENSE_RANK does not, ROW_NUMBER never ties.

**Q4. UNION vs UNION ALL?**  
UNION removes duplicates (sorts); UNION ALL keeps them and is faster.

**Q5. What is MINUS?**  
Rows in the first query that are not in the second (EXCEPT in standard SQL).

**Q6. What does PARTITION BY do?**  
Restarts the window calculation for each group without collapsing rows.

## 10. Important practical commands

```
@15_queries_nested_window.sql
SELECT inmate_id, RANK() OVER (ORDER BY fn_inmate_visit_count(inmate_id) DESC) AS r FROM inmates FETCH FIRST 5 ROWS ONLY;
```

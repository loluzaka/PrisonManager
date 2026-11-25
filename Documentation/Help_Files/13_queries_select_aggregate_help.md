# Help: `13_queries_select_aggregate.sql`

## 1. File overview

* **Exact filename:** `13_queries_select_aggregate.sql`
* **Location:** `sql/`
* **Purpose:** Sixteen read-only queries showing WHERE, ORDER BY, string/date/numeric functions, NULL handling, aggregates, GROUP BY, HAVING, ROLLUP.
* **Feature(s):** F8 (SELECT, filters, functions), F9 (aggregation and grouping)
* **Member responsibility:** Member 1
* **Role in the system:** Query collection for the lab and the viva.
* **Execution order:** Demo; after the install.

## 2. Required database objects and dependencies

* **Reads:** INMATES, VISITORS, VISITS, BLOCKS, MOVEMENTS, AUDIT_LOG; calls `fn_inmate_visit_count`, `fn_days_remaining`.
* **Modifies nothing.**

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | All queries. |
| **WHERE** | Filters rows BEFORE grouping. | `WHERE a = 1 AND (b = 2 OR c IS NULL)` | AND/OR/NOT, IN, BETWEEN, LIKE. |
| **ORDER BY** | Sorts the result; the only way to get a guaranteed order. | `ORDER BY col DESC, col2` | Ascending/descending, several columns. |
| **Scalar functions** | Row-level functions: UPPER, TRIM, SUBSTR, INSTR, REPLACE, LENGTH, ROUND, MOD, TO_CHAR, ADD_MONTHS, TRUNC(date) ... | `UPPER(TRIM(name))` | UPPER, TRIM, SUBSTR, INSTR, LENGTH, REPLACE; MONTHS_BETWEEN, ADD_MONTHS, NEXT_DAY, TO_CHAR; ROUND, CEIL, FLOOR, MOD; NVL. |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | Size class, NULL handling. |
| **Aggregate functions** | COUNT, SUM, AVG, MIN, MAX compute one value from many rows. | `COUNT(*), SUM(x), AVG(x), MIN(x), MAX(x)` | COUNT, SUM, AVG, MIN, MAX. |
| **GROUP BY / HAVING** | GROUP BY collapses rows into groups for aggregate functions; HAVING filters the groups (WHERE cannot, because it runs earlier). | `SELECT col, COUNT(*) FROM t GROUP BY col HAVING COUNT(*) > 1` | Occupancy per block; visits per inmate per month with `HAVING COUNT(*) >= 2`. |
| **JOIN** | Combines rows of two tables on a condition. INNER keeps matches; LEFT/RIGHT keep all rows of one side; FULL keeps both; SELF joins a table to itself. | `FROM a INNER JOIN b ON a.id = b.a_id` | LEFT JOIN so empty blocks show 0. |
| **Window functions** | Compute a value per row over a "window" of related rows without collapsing them. | `RANK() OVER (PARTITION BY g ORDER BY x DESC)` | `COUNT(*)/SUM(COUNT(*)) OVER ()` for percentages. |

**Common mistakes with these keywords**

* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *WHERE*: Comparing with NULL using = (use IS NULL).
* *ORDER BY*: Assuming rows come back in insertion order.
* *Scalar functions*: Dates: SYSDATE includes the time; use TRUNC(SYSDATE) for "today".
* *CASE*: Missing ELSE returns NULL.
* *Aggregate functions*: COUNT(col) skips NULLs, COUNT(*) does not.
* *GROUP BY / HAVING*: Putting an aggregate in WHERE -> ORA-00934.
* *JOIN*: Forgetting the ON condition produces a Cartesian product (rows x rows).
* *Window functions*: Using them in WHERE: wrap the query and filter outside.

**ROLLUP** adds subtotal/total rows to GROUP BY (Q9.7). **FETCH FIRST n ROWS ONLY** limits output. **SQL*Plus COLUMN ... FORMAT** only changes how columns print.

## 4. Tables and columns involved

Columns used: `inmates(inmate_id, inmate_no, full_name, status, risk_level, block_id, sentence_start, sentence_end)`, `visitors(approval_status, id_proof_number, phone)`, `visits(visit_date, slot, status)`, `blocks(capacity)`, `movements(from_block, to_block, reason)`, `audit_log(action_type, record_id)`. Full definitions: `Documentation/Data_Dictionary.md`.

## 5. Walkthrough

| ID | Query | Concept |
|---|---|---|
| Q8.1 | active inmates in block 2, newest sentence first | WHERE + AND + ORDER BY DESC |
| Q8.2 | visitors that are not approved | NOT IN |
| Q8.3 | visits in a date range for HIGH/MEDIUM risk | BETWEEN, OR in parentheses |
| Q8.4 | name pattern search | UPPER + LIKE |
| Q8.5 | string functions on visitor names / masked ID | UPPER, TRIM, SUBSTR, INSTR, REPLACE |
| Q8.6 | days left, months served, weekday, +6 months, next Monday | date arithmetic |
| Q8.7 | rounding and remainder on block capacities | numeric functions + CASE |
| Q8.8 | admissions have no origin block | NVL |
| Q8.9 | our own functions inside SELECT | `fn_inmate_visit_count`, `fn_days_remaining` |
| Q9.1 | blocks, beds, average, min, max | aggregates |
| Q9.2 | occupancy per block | LEFT JOIN + GROUP BY |
| Q9.3 | inmates with 2+ visits in a month | GROUP BY + HAVING |
| Q9.4 | busiest slots | GROUP BY + ORDER BY |
| Q9.5 | denied attempts per visitor | aggregate over AUDIT_LOG |
| Q9.6 | status mix with percentage | window SUM over aggregate |
| Q9.7 | inmates per status and risk with subtotals | ROLLUP |

Order of evaluation to remember: FROM/JOIN -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY.

## 6. Actual execution example

Real output:

```
Q8.6   INMATE_NO DAYS_LEFT MONTHS_SERVED RELEASE_DAY      DATE_PLUS_6_MONTHS NEXT_MONDAY_AFTER
       INM-0003          8            49 WED 11-NOV-2026  11-MAY-27          16-NOV-26
       INM-0014         19          48.6 SUN 22-NOV-2026  22-MAY-27          23-NOV-26

Q9.2   BLOCK_NAME CAPACITY OCCUPIED       Q9.4  SLOT         BOOKINGS
       A-Block        14       12              10:00-11:00        17
       B-Block        12       11              14:00-15:00        17
       C-Block         8        7              15:00-16:00        17
       D-Block        10        9              09:00-10:00        16
       E-Block         6        6              11:00-12:00        15
                                               16:00-17:00        14
Q9.6   STATUS     VISITS PCT        Q9.7  ACTIVE ALL 45 / ACTIVE HIGH 3 / ACTIVE LOW 34 / ACTIVE MEDIUM 8 / ALL ALL 50
       COMPLETED      78  78
       SCHEDULED      14  14
```

## 7. Data flow and integration

```
 INMATES/VISITORS/VISITS/BLOCKS/MOVEMENTS/AUDIT_LOG ──read──► result sets only
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-00937: not a single-group group function` | Selected a plain column with an aggregate without GROUP BY | Add the column to GROUP BY. |
| `ORA-00979: not a GROUP BY expression` | Select-list column missing from GROUP BY | Add it or aggregate it. |
| `ORA-00934: group function is not allowed here` | Aggregate in WHERE | Use HAVING. |
| `ORA-01722: invalid number` | Comparing text column with a number | Convert with TO_NUMBER/TO_CHAR. |
| Dates print without time | Default NLS format hides time | `TO_CHAR(d, 'YYYY-MM-DD HH24:MI')`. |

## 9. Viva questions and answers

**Q1. WHERE vs HAVING?**  
WHERE filters rows before grouping, HAVING filters groups after aggregation.

**Q2. COUNT(*) vs COUNT(col)?**  
COUNT(*) counts rows; COUNT(col) skips NULLs.

**Q3. What does ROLLUP do?**  
Adds subtotal and grand-total rows to a GROUP BY.

**Q4. How do you compute days left in a sentence?**  
Date subtraction: `sentence_end - TRUNC(SYSDATE)`.

**Q5. Why LEFT JOIN in Q9.2?**  
So a block with no inmates still appears with 0.

## 10. Important practical commands

```
@13_queries_select_aggregate.sql
SET LINESIZE 170 PAGESIZE 60
SELECT block_id, COUNT(*) FROM inmates WHERE status = 'ACTIVE' GROUP BY block_id;
```

# Help: `14_queries_joins.sql`

## 1. File overview

* **Exact filename:** `14_queries_joins.sql`
* **Location:** `sql/`
* **Purpose:** Nine join queries: inner, left, right, full outer, self and multi-table (including BLOCKS joined twice).
* **Feature(s):** F10 (joins)
* **Member responsibility:** Member 1
* **Role in the system:** Join collection for the lab and viva.
* **Execution order:** Demo; after the install.

## 2. Required database objects and dependencies

* **Reads:** VISITS, INMATES, VISITORS, BLOCKS, FACILITIES, MOVEMENTS, INMATE_CONFLICTS, CONFLICTS.
* **Modifies nothing.**

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **JOIN** | Combines rows of two tables on a condition. INNER keeps matches; LEFT/RIGHT keep all rows of one side; FULL keeps both; SELF joins a table to itself. | `FROM a INNER JOIN b ON a.id = b.a_id` | INNER, LEFT, RIGHT, FULL OUTER and self joins. |
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | All. |
| **WHERE** | Filters rows BEFORE grouping. | `WHERE a = 1 AND (b = 2 OR c IS NULL)` | Filters including `IS NULL` to find non-matches. |
| **ORDER BY** | Sorts the result; the only way to get a guaranteed order. | `ORDER BY col DESC, col2` | - |
| **GROUP BY / HAVING** | GROUP BY collapses rows into groups for aggregate functions; HAVING filters the groups (WHERE cannot, because it runs earlier). | `SELECT col, COUNT(*) FROM t GROUP BY col HAVING COUNT(*) > 1` | J3 counts visits per visitor. |
| **Aggregate functions** | COUNT, SUM, AVG, MIN, MAX compute one value from many rows. | `COUNT(*), SUM(x), AVG(x), MIN(x), MAX(x)` | COUNT(v.visit_id) counts only matched rows. |

**Common mistakes with these keywords**

* *JOIN*: Forgetting the ON condition produces a Cartesian product (rows x rows).
* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *WHERE*: Comparing with NULL using = (use IS NULL).
* *ORDER BY*: Assuming rows come back in insertion order.
* *GROUP BY / HAVING*: Putting an aggregate in WHERE -> ORA-00934.
* *Aggregate functions*: COUNT(col) skips NULLs, COUNT(*) does not.

**ON vs WHERE in outer joins:** a filter on the *optional* table belongs in ON; in WHERE it turns the outer join back into an inner join. **Table aliases** (`a`, `b`, `fb`, `tb`) are mandatory in self joins and when the same table is joined twice.

## 4. Tables and columns involved

Key relationships used: `visits.inmate_id -> inmates`, `visits.visitor_id -> visitors`, `inmates.block_id -> blocks`, `blocks.facility_id -> facilities`, `movements.from_block/to_block -> blocks` (twice), `inmate_conflicts.inmate_a/inmate_b -> inmates` (twice). See `ER_Diagram.md`.

## 5. Walkthrough

| ID | Join type | What it answers |
|---|---|---|
| J1 | INNER (3 tables) | today's visits with inmate and visitor names |
| J2 | LEFT + `IS NULL` | inmates who never had a visit (real result: the 5 non-active inmates 46-50) |
| J3 | RIGHT | every visitor with a visit count (pending/blacklisted show 0) |
| J4 | FULL OUTER | facilities vs blocks (no unmatched rows in the seed; a facility without blocks would show) |
| J5 | multi-table, BLOCKS twice | movement history with origin and destination names; LEFT JOIN for admissions |
| J6 | SELF-style (INMATES joined twice) | every rival pair with both names and blocks |
| J7 | SELF | pairs of inmates in the same block; `a.inmate_id < b.inmate_id` removes mirror pairs |
| J8 | INNER x3 | all inmate-visitor conflicts |
| J9 | INNER x4 | visits with facility, block, inmate, visitor |

## 6. Actual execution example

Real output:

```
J2  INMATE_NO FULL_NAME      STATUS      VISIT_ID
    INM-0046  Nikhil Walker  TRANSFERRED
    INM-0047  Qasim Evans    TRANSFERRED
    INM-0048  Tariq Lopez    RELEASED
    INM-0049  Wen Singh      RELEASED
    INM-0050  Arjun Ahmed    RELEASED

J5  MOVEMENT_DATE (excerpt)        INMATE_NO INMATE_NAME     FROM_BLOCK TO_BLOCK  REASON
    17-OCT-26 06.11.09.955535 PM   INM-0002  Gabriel Okafor  B-Block    A-Block   Behaviour review transfer
    10-OCT-26 ...                  INM-0009  Chen Novak      B-Block    A-Block   Behaviour review transfer

J6  INM-0004 Mateo Dubois (A-Block)  <-> INM-0014 Rohan Xu (B-Block)   RIVAL
    INM-0006 Samuel Rossi (A-Block)  <-> INM-0025 Arjun Ahmed (C-Block) GANG_AFFILIATION
    INM-0018 Ethan Brown  (B-Block)  <-> INM-0026 Dmitri Hussain (C-Block) RIVAL
```

## 7. Data flow and integration

```
 11 tables ──joins──► result sets (read-only)
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Huge/duplicated result | Missing ON condition (Cartesian product) | Every JOIN needs an ON. |
| `ORA-00918: column ambiguously defined` | Same column name in two tables without alias | Prefix with the table alias. |
| Outer join acts like inner join | Filter on the optional table in WHERE | Move it to the ON clause. |
| Mirror duplicates in self join | No `a.id < b.id` | Add the inequality. |

## 9. Viva questions and answers

**Q1. Inner vs left vs right vs full join?**  
Inner = matches only; left/right keep all rows of one side; full keeps all rows of both.

**Q2. What is a self join?**  
A table joined to itself using two aliases, e.g. pairs of inmates in the same block.

**Q3. How do you find rows with no match?**  
LEFT JOIN and test the right-hand key `IS NULL`.

**Q4. Why join BLOCKS twice for movements?**  
MOVEMENTS holds two block ids (from and to); each needs its own alias to show its name.

## 10. Important practical commands

```
@14_queries_joins.sql
SELECT i.inmate_no, b.block_name FROM inmates i JOIN blocks b ON b.block_id = i.block_id WHERE i.status = 'ACTIVE';
```

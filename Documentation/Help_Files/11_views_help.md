# Help: `11_views.sql`

## 1. File overview

* **Exact filename:** `11_views.sql`
* **Location:** `sql/`
* **Purpose:** Creates 17 views: the four required views, masking, report views and facility-scoped views.
* **Feature(s):** F6 (views), F26 (masked ID numbers), F27 (reports), F31 (facility-scoped access)
* **Member responsibility:** Member 3
* **Role in the system:** Staff roles are granted views, never base tables, so a view can hide columns and rows.
* **Execution order:** After the cursors (10); before roles (17), which grant these views.

## 2. Required database objects and dependencies

* **Reads:** INMATES, BLOCKS, FACILITIES, VISITS, VISITORS, CONFLICTS, MOVEMENTS, AUDIT_LOG, STAFF_ACCESS.
* **Uses functions:** `fn_days_remaining`, `fn_visitor_visit_count`.
* **Used by:** `16_reports.sql`, `17_roles_security.sql`, tests I01-I07, R-*.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CREATE VIEW** | A stored query with a name; behaves like a read-only table and can hide columns and rows. | `CREATE OR REPLACE VIEW v AS SELECT ...;` | `CREATE OR REPLACE VIEW` x17. |
| **JOIN** | Combines rows of two tables on a condition. INNER keeps matches; LEFT/RIGHT keep all rows of one side; FULL keeps both; SELF joins a table to itself. | `FROM a INNER JOIN b ON a.id = b.a_id` | INNER, LEFT (admissions have no origin block; blocks with no inmates) and CROSS JOIN (every visitor x inmate for `v_visit_eligibility`). |
| **GROUP BY / HAVING** | GROUP BY collapses rows into groups for aggregate functions; HAVING filters the groups (WHERE cannot, because it runs earlier). | `SELECT col, COUNT(*) FROM t GROUP BY col HAVING COUNT(*) > 1` | `v_frequent_visitors` keeps visitors with 3+ visits; occupancy and statistics views. |
| **Aggregate functions** | COUNT, SUM, AVG, MIN, MAX compute one value from many rows. | `COUNT(*), SUM(x), AVG(x), MIN(x), MAX(x)` | COUNT, SUM(CASE ...), MAX. |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | Occupancy flag, conflict state, SUM(CASE WHEN status = ...). |
| **Subquery / EXISTS** | A SELECT inside another statement. EXISTS is true if the inner query returns any row; correlated subqueries refer to the outer row. | `WHERE NOT EXISTS (SELECT 1 FROM c WHERE c.x = o.x)` | `NOT EXISTS` in `v_visit_eligibility`; `EXISTS` on STAFF_ACCESS in the facility views. |
| **Scalar functions** | Row-level functions: UPPER, TRIM, SUBSTR, INSTR, REPLACE, LENGTH, ROUND, MOD, TO_CHAR, ADD_MONTHS, TRUNC(date) ... | `UPPER(TRIM(name))` | `SUBSTR(id_proof_number, -4)` masks IDs; `REGEXP_SUBSTR` extracts `inmate_id=` and `reason=` from audit text; TO_CHAR for months. |
| **WHERE** | Filters rows BEFORE grouping. | `WHERE a = 1 AND (b = 2 OR c IS NULL)` | Row filters, e.g. `status = 'ACTIVE'`. |

**Common mistakes with these keywords**

* *CREATE VIEW*: Granting users the base table as well defeats the purpose.
* *JOIN*: Forgetting the ON condition produces a Cartesian product (rows x rows).
* *GROUP BY / HAVING*: Putting an aggregate in WHERE -> ORA-00934.
* *Aggregate functions*: COUNT(col) skips NULLs, COUNT(*) does not.
* *CASE*: Missing ELSE returns NULL.
* *Subquery / EXISTS*: NOT IN returns nothing if the subquery yields a NULL; prefer NOT EXISTS.
* *Scalar functions*: Dates: SYSDATE includes the time; use TRUNC(SYSDATE) for "today".
* *WHERE*: Comparing with NULL using = (use IS NULL).

**SYS_CONTEXT('USERENV','SESSION_USER')** returns the login name of the connected user; the facility views compare it with `staff_access.db_username` so each user sees only rows of their facility (row-level security by view).

## 4. Tables and columns involved

| View | What it shows | Feature |
|---|---|---|
| `v_active_inmates` | ACTIVE inmates, block, facility, days remaining | F6 |
| `v_todays_visits` | today's visits | F6 |
| `v_eligible_visitors` | APPROVED visitors, ID masked | F6 |
| `v_visit_eligibility` | every eligible (visitor, inmate) pair | F6 |
| `v_block_occupancy` | capacity, occupied, free beds, %, flag | F6/F27 |
| `v_visitors_masked` | visitors with `****1234` IDs | F26 |
| `v_inmate_conflicts` | conflicts with state ACTIVE/RESOLVED/EXPIRED | F27 |
| `v_denied_attempts` | denied attempts parsed from AUDIT_LOG | F27 |
| `v_movement_history` | movements with block names | F27 |
| `v_blacklisted_visitors` | blacklisted visitors + denied attempts | F27 |
| `v_frequent_visitors` | visitors with 3+ visits | F27 |
| `v_upcoming_releases` | releases within 60 days | F27 |
| `v_visit_stats_per_inmate` | visits per inmate | F27 |
| `v_monthly_visit_stats` | visits per month | F27 |
| `v_fac_blocks`, `v_fac_inmates`, `v_fac_visits` | rows of the caller's facility only | F31 |

Base tables: see `Documentation/Data_Dictionary.md`.

## 5. Walkthrough

* **Masking:** `'****' || SUBSTR(id_proof_number, -4)` - the last four characters survive; front desk and auditor use these views.
* **`v_block_occupancy`:** a LEFT JOIN to an inline view that counts ACTIVE inmates per block, so a block with no inmates still appears (occupied 0). Flags: OVER CAPACITY, AT CAPACITY, NEARLY FULL (>= 90 %), AVAILABLE.
* **`v_denied_attempts`:** audit rows of type VISIT_DENIED; `record_id` is the visitor, `REGEXP_SUBSTR(details, 'reason=([A-Z_]+)', 1, 1, NULL, 1)` pulls the reason out of the text.
* **`v_visit_eligibility`:** CROSS JOIN of approved visitors and ACTIVE inmates, minus pairs with an active conflict (`NOT EXISTS`).
* **Facility views:** `v_fac_blocks` keeps a block when STAFF_ACCESS has a row for the current user whose `facility_id` is NULL (all) or equals the block's facility. `v_fac_inmates` and `v_fac_visits` join through `v_fac_blocks`, so the filter cascades.

## 6. Actual execution example

Real output:

```
SELECT * FROM v_visitors_masked WHERE visitor_id <= 3;
VISITOR_ID FULL_NAME      ID_PROOF_TYPE    ID_PROOF_MASKED APPROVAL_STATUS
         1 Hassan Okafor  NATIONAL_ID     ****7919        APPROVED
         2 Mateo Ahmed    DRIVING_LICENCE ****5838        APPROVED
         3 Rohan Lopez    VOTER_ID        ****3757        APPROVED

SELECT block_name, occupied, free_beds, occupancy_pct, occupancy_flag FROM v_block_occupancy;
A-Block 12 2  85.7 AVAILABLE
B-Block 11 1  91.7 NEARLY FULL
C-Block  7 1  87.5 AVAILABLE
D-Block  9 1  90   NEARLY FULL
E-Block  6 0 100   AT CAPACITY
```
Facility isolation (tests R-WA-6/7): `PRISON_U_WARDEN` sees 33 inmates / 3 blocks, `PRISON_U_WARDEN2` sees 17 / 2, admin and auditor see all 50 / 5.

## 7. Data flow and integration

```
 base tables ──► views ──► granted to roles (17) ──► users
 v_fac_* ◄── STAFF_ACCESS (login -> facility) ◄── SYS_CONTEXT('USERENV','SESSION_USER')
```
Views store no data: they always show the current state.

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-00942` for a role user selecting a view | No SELECT granted on the view | Grant it to the role in script 17. |
| `ORA-01031` creating a view over a table granted without GRANT OPTION | Owner of the view is not the owner of the table | Create views in the table-owning schema (done here). |
| View returns no rows for a warden | No STAFF_ACCESS row for that login | Run the MERGE at the end of 17. |
| `ORA-01445: cannot select ROWID from a join view` | FOR UPDATE on a join view | Not used here; update base tables. |

## 9. Viva questions and answers

**Q1. What is a view and why use one?**  
A stored query with a name: hides columns/rows, simplifies reports and lets users query without base-table rights.

**Q2. How is the ID number masked?**  
The view returns `****` plus the last four characters; the raw column is never granted to front desk.

**Q3. How does facility isolation work?**  
Facility views filter on STAFF_ACCESS using the connected user name.

**Q4. Can you insert through these views?**  
No - aggregates/joins make them read-only, which is what we want.

**Q5. Difference between a view and a table?**  
A view stores the query, not the data.

## 10. Important practical commands

```
SELECT view_name FROM user_views ORDER BY 1;
SELECT text FROM user_views WHERE view_name = 'V_BLOCK_OCCUPANCY';
SELECT * FROM v_block_occupancy;
SELECT * FROM v_fac_inmates;          -- depends on who is logged in
```

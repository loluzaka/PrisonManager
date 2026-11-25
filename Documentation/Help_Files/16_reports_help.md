# Help: `16_reports.sql`

## 1. File overview

* **Exact filename:** `16_reports.sql`
* **Location:** `sql/`
* **Purpose:** Runs eleven reports, including monthly visit totals by status using PIVOT.
* **Feature(s):** F27 (reports), F36 (PIVOT)
* **Member responsibility:** Member 3
* **Role in the system:** Report pack for the demonstration; also runnable by the auditor role.
* **Execution order:** Demo; after views and cursors.

## 2. Required database objects and dependencies

* **Calls:** `pr_daily_roster`, `pr_block_occupancy`, `pr_upcoming_releases` (cursors).
* **Reads views:** `v_block_occupancy`, `v_visit_stats_per_inmate`, `v_monthly_visit_stats`, `v_movement_history`, `v_denied_attempts`, `v_blacklisted_visitors`, `v_frequent_visitors`, `v_upcoming_releases`, `v_inmate_conflicts`.
* **Modifies nothing.**

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | One query per report. |
| **ORDER BY** | Sorts the result; the only way to get a guaranteed order. | `ORDER BY col DESC, col2` | Sort for readability. |
| **DBMS_OUTPUT** | Buffered text output of PL/SQL, shown by the client after the block ends. | `SET SERVEROUTPUT ON; DBMS_OUTPUT.PUT_LINE('text');` | Cursor reports print through it. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | `COLUMN x FORMAT A22` sets display widths; `SET SERVEROUTPUT ON`. |
| **CURSOR** | A named pointer to a query result that PL/SQL walks row by row. Explicit lifecycle: DECLARE -> OPEN -> FETCH -> check %NOTFOUND -> CLOSE. | `CURSOR c (p DATE) IS SELECT ...; OPEN c(d); FETCH c INTO r; EXIT WHEN c%NOTFOUND; CLOSE c;` | R1, R2, R9 run explicit cursors. |
| **CREATE VIEW** | A stored query with a name; behaves like a read-only table and can hide columns and rows. | `CREATE OR REPLACE VIEW v AS SELECT ...;` | Other reports are plain SELECTs on views. |
| **PIVOT** | Turns row values into output columns and aggregates each group. | `PIVOT (COUNT(id) FOR status IN ('OPEN' AS open))` | R11 displays monthly visit totals as status columns. |

**Common mistakes with these keywords**

* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *ORDER BY*: Assuming rows come back in insertion order.
* *DBMS_OUTPUT*: Forgetting SET SERVEROUTPUT ON - then nothing is printed.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.
* *CURSOR*: Not closing the cursor (ORA-01000 too many open cursors) or testing %NOTFOUND before the first FETCH.
* *CREATE VIEW*: Granting users the base table as well defeats the purpose.
* *PIVOT*: Values not listed in the `IN` clause do not get output columns.

## 4. Tables and columns involved

Report <- source: R1 `pr_daily_roster`; R2 `pr_block_occupancy` + `v_block_occupancy`; R3 `v_visit_stats_per_inmate`; R4 `v_monthly_visit_stats`; R5 `v_movement_history`; R6 `v_denied_attempts`; R7 `v_blacklisted_visitors`; R8 `v_frequent_visitors`; R9 `pr_upcoming_releases` + `v_upcoming_releases`; R10 `v_inmate_conflicts`; R11 `visits` with PIVOT.

## 5. Walkthrough

Each report is one `PROMPT` heading followed by an `EXEC` of a cursor procedure or a `SELECT`. R11 uses an inline query and PIVOT to turn visit statuses into monthly columns. The other report logic lives in views and procedures.

## 6. Actual execution example

Real output (excerpts):

```
R4  VISIT_M  VISITS COMPLETED MISSED CANCELLED DISTINCT_VISITORS
    2026-08      17        15      1         1                17
    2026-09      33        29      2         2                24
    2026-10      34        32      1         1                25
    2026-11      16         2      0         0                15

R7  VISITOR_ID FULL_NAME      ID_PROOF_TYPE   ID_PROOF_MASKED DENIED_ATTEMPTS
           36 Hassan Young    PASSPORT        ****5084                  2
           37 Mateo Khan      NATIONAL_ID     ****3003                  1
           38 Rohan Verma     DRIVING_LICENCE ****0922                  1

R9  INM-0003 Jamal Verma  A-Block 11-NOV-26  8 | INM-0014 ... 19 | INM-0019 ... 24 | INM-0027 ... 32 | INM-0033 ... 38 | INM-0041 ... 46
R10 conflicts 1-6 ACTIVE, 8 EXPIRED (inmate 10), 7 RESOLVED (inmate 1)
```
R1 and R2 are shown in full in the `10_cursors` help file.

## 7. Data flow and integration

```
 views + cursor procedures ──► 16_reports.sql ──► screen / SPOOL file (CSV export from SQL Developer or DBeaver)
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Report R1/R2 print nothing | SERVEROUTPUT off | SET SERVEROUTPUT ON. |
| `ORA-00942` for the auditor | View not granted | See grants in 17. |
| Columns wrap | LINESIZE too small | `SET LINESIZE 170`. |

## 9. Viva questions and answers

**Q1. Why build reports on views?**  
One definition, consistent numbers, access control through the view.

**Q2. Which reports use cursors?**  
Daily roster, block occupancy, upcoming releases.

**Q3. How would you export a report to CSV?**  
SQL Developer / DBeaver export, or `SET MARKUP CSV ON` and `SPOOL`.

## 10. Important practical commands

```
@16_reports.sql
SET MARKUP CSV ON
SPOOL denied.csv
SELECT * FROM v_denied_attempts;
SPOOL OFF
```

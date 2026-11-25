# Help: `10_cursors.sql`

## 1. File overview

* **Exact filename:** `10_cursors.sql`
* **Location:** `sql/`
* **Purpose:** Explicit cursors that process many rows one by one: c_daily_roster (parameterised), c_block_occupancy, c_upcoming_release (cursor FOR loop) and a REF CURSOR function.
* **Feature(s):** F20 (cursors) - the lab objective "handling multiple records"
* **Member responsibility:** Member 2
* **Role in the system:** Produces the daily roster, occupancy and release reports with DBMS_OUTPUT.
* **Execution order:** After the procedures (09); before views (11). Reports (16) and tests call these procedures.

## 2. Required database objects and dependencies

* **Reads:** VISITS, INMATES, BLOCKS, VISITORS, FACILITIES.
* **Calls:** `fn_block_occupancy`, `fn_days_remaining`.
* **Creates:** PR_DAILY_ROSTER, PR_BLOCK_OCCUPANCY, PR_UPCOMING_RELEASES, FN_ROSTER_REFCURSOR.
* **Needs:** `SET SERVEROUTPUT ON` in the client.

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CURSOR** | A named pointer to a query result that PL/SQL walks row by row. Explicit lifecycle: DECLARE -> OPEN -> FETCH -> check %NOTFOUND -> CLOSE. | `CURSOR c (p DATE) IS SELECT ...; OPEN c(d); FETCH c INTO r; EXIT WHEN c%NOTFOUND; CLOSE c;` | Three declared cursors. Lifecycle shown line by line in `pr_daily_roster`: declaration -> `OPEN c_daily_roster(p_date)` -> `FETCH ... INTO r_row` -> `EXIT WHEN c%NOTFOUND` -> process -> `CLOSE`. |
| **Cursor attributes** | %NOTFOUND (last fetch found nothing), %FOUND, %ROWCOUNT (rows fetched so far), %ISOPEN. | `EXIT WHEN c%NOTFOUND; c%ROWCOUNT` | `%NOTFOUND` ends the loop, `%ROWCOUNT` numbers the lines and prints the total, `%ISOPEN` is tested in the exception handler (and displayed by `pr_block_occupancy`). |
| **Cursor FOR loop** | Opens, fetches and closes a cursor automatically; the loop variable is a record. | `FOR r IN c(10) LOOP ... END LOOP;` | `pr_upcoming_releases`: `FOR r IN c_upcoming_release(p_days) LOOP` - Oracle opens, fetches and closes automatically. |
| **SYS_REFCURSOR** | A cursor variable that can be returned to a client program, which fetches and closes it. | `OPEN rc FOR SELECT ...; RETURN rc;` | `fn_roster_refcursor` returns an open cursor that SQL*Plus (`PRINT rc`) or any client fetches. |
| **%TYPE / %ROWTYPE** | Declare a variable with the same type as a column (%TYPE) or the same shape as a row/cursor (%ROWTYPE), so code survives column changes. | `v inmates.status%TYPE; r c_cur%ROWTYPE;` | `r_row c_daily_roster%ROWTYPE` is a record with exactly the cursor's columns. |
| **JOIN** | Combines rows of two tables on a condition. INNER keeps matches; LEFT/RIGHT keep all rows of one side; FULL keeps both; SELF joins a table to itself. | `FROM a INNER JOIN b ON a.id = b.a_id` | The roster query joins four tables. |
| **ORDER BY** | Sorts the result; the only way to get a guaranteed order. | `ORDER BY col DESC, col2` | Block, then slot, then inmate number - required for the control break (new block heading). |
| **DBMS_OUTPUT** | Buffered text output of PL/SQL, shown by the client after the block ends. | `SET SERVEROUTPUT ON; DBMS_OUTPUT.PUT_LINE('text');` | All report text. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | Closes an open cursor and re-raises with `RAISE`. |
| **Scalar functions** | Row-level functions: UPPER, TRIM, SUBSTR, INSTR, REPLACE, LENGTH, ROUND, MOD, TO_CHAR, ADD_MONTHS, TRUNC(date) ... | `UPPER(TRIM(name))` | RPAD/LPAD for columns, ROUND, TRUNC, TO_CHAR. |
| **CASE** | Conditional expression inside SQL or PL/SQL. | `CASE WHEN x > 1 THEN 'a' ELSE 'b' END` | Flag text: `** AT CAPACITY`, `*** OVER CAPACITY`, `ok`. |
| **CHAR(10) / CHR(10)** | CHR(10) is the line-feed character, used to put newlines into output. | `'text' || CHR(10)` | Blank line before each block heading. |

**Common mistakes with these keywords**

* *CURSOR*: Not closing the cursor (ORA-01000 too many open cursors) or testing %NOTFOUND before the first FETCH.
* *Cursor attributes*: Reading %ROWCOUNT after CLOSE raises INVALID_CURSOR.
* *Cursor FOR loop*: Referring to r after the loop.
* *SYS_REFCURSOR*: Leaving it open on the server side.
* *JOIN*: Forgetting the ON condition produces a Cartesian product (rows x rows).
* *ORDER BY*: Assuming rows come back in insertion order.
* *DBMS_OUTPUT*: Forgetting SET SERVEROUTPUT ON - then nothing is printed.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *Scalar functions*: Dates: SYSDATE includes the time; use TRUNC(SYSDATE) for "today".
* *CASE*: Missing ELSE returns NULL.

## 4. Tables and columns involved

Cursor queries:

* **c_daily_roster(cp_date)** - `visits` ⋈ `inmates` ⋈ `blocks` ⋈ `visitors` where `visit_date = TRUNC(cp_date)` and `status <> 'CANCELLED'`, ordered by block name, slot, inmate no.
* **c_block_occupancy** - `blocks` ⋈ `facilities`; occupancy comes from `fn_block_occupancy` for each fetched block.
* **c_upcoming_release(cp_days)** - ACTIVE inmates with `sentence_end` between today and today + cp_days.

See `Documentation/Data_Dictionary.md` for the columns.

## 5. Walkthrough

**Why a cursor instead of a plain SELECT?** A SELECT hands all rows to the client; an explicit cursor lets PL/SQL *process* each row - detect when the block changes, number lines, compute a percentage per block, count rows, stop early.

**`pr_daily_roster(p_date)`**: OPEN with the date parameter; in the loop a *control break* prints a block heading whenever `block_id` changes; each line shows `%ROWCOUNT`, slot, inmate, visitor and status; after the loop `%ROWCOUNT` is the total (still valid until CLOSE); empty day prints "(no visits scheduled)"; the exception section closes the cursor if still open.

**`pr_block_occupancy`**: for each block fetch -> `fn_block_occupancy` -> percentage -> flag (`AT CAPACITY` when equal, `OVER CAPACITY` when above) -> print line.

**`pr_upcoming_releases(p_days)`**: cursor FOR loop with a parameter; prints days remaining via `fn_days_remaining`.

**`fn_roster_refcursor(p_date)`**: opens a REF CURSOR and returns it; the *caller* fetches and closes.

## 6. Actual execution example

Real output (seed data, today = 03-NOV-2026):

```
===== DAILY VISIT ROSTER for 03-NOV-2026 =====

--- A-Block ---
  1. 10:00-11:00  INM-0012 Liam Jensen       <- Wen Walker      [SCHEDULED]
  2. 15:00-16:00  INM-0005 Pavel Khan        <- Rohan Brown     [SCHEDULED]

--- B-Block ---
  3. 09:00-10:00  INM-0015 Umar Fischer      <- Rohan Garcia    [SCHEDULED]
  4. 14:00-15:00  INM-0022 Qasim Evans       <- Wen Walker      [SCHEDULED]
  5. 15:00-16:00  INM-0019 Hassan Ibrahim    <- Chen Novak      [SCHEDULED]

--- C-Block ---
  6. 09:00-10:00  INM-0029 Mateo Dubois      <- Chen Singh      [SCHEDULED]

--- D-Block ---
  7. 14:00-15:00  INM-0036 Ivan Chatterjee   <- Hassan Okafor   [SCHEDULED]

--- E-Block ---
  8. 10:00-11:00  INM-0043 Ethan Brown       <- Mateo Fischer   [SCHEDULED]

Total visits listed: 8

===== BLOCK OCCUPANCY =====
cursor open? YES
A-Block  LOW      12/14    85.7%  ok               Central Correctional Facility
B-Block  MEDIUM   11/12    91.7%  ok               Central Correctional Facility
C-Block  HIGH      7/8     87.5%  ok               Central Correctional Facility
D-Block  LOW       9/10    90.0%  ok               Riverside Detention Centre
E-Block  MEDIUM    6/6    100.0%  ** AT CAPACITY   Riverside Detention Centre
blocks processed: 5

===== RELEASES DUE WITHIN 30 DAYS =====
INM-0003  Jamal Verma      11-NOV-2026  in 8 day(s)   block 1
INM-0014  Rohan Xu         22-NOV-2026  in 19 day(s)  block 2
INM-0019  Hassan Ibrahim   27-NOV-2026  in 24 day(s)  block 2
inmates due for release: 3
```
Tests H01-H08 assert: 8 rows fetched (equals a COUNT), 3+ block headings, empty day handled, 5 blocks listed, E-Block flagged, 3 releases.

## 7. Data flow and integration

```
 VISITS+INMATES+BLOCKS+VISITORS ──c_daily_roster(date)──► row by row ──► DBMS_OUTPUT (grouped by block)
 BLOCKS ──c_block_occupancy──► fn_block_occupancy per row ──► percentage + flag
 INMATES ──c_upcoming_release(days) [FOR loop]──► fn_days_remaining
 fn_roster_refcursor ──► client fetches (PRINT rc)
```
Read-only: no table is modified, no trigger fires.

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Nothing is printed | `SET SERVEROUTPUT ON` missing | Run `SET SERVEROUTPUT ON SIZE UNLIMITED` first. |
| `ORA-01000: maximum open cursors exceeded` | Cursors opened but never closed | CLOSE in normal flow and in the EXCEPTION handler (or use a FOR loop). |
| `ORA-01001: invalid cursor` | FETCH/CLOSE on a cursor that is not open | Test `%ISOPEN` before closing. |
| `ORA-06511: cursor already open` | OPEN twice | CLOSE first. |
| Loop never ends / extra last row | Tested %NOTFOUND after processing instead of right after FETCH | Put `EXIT WHEN c%NOTFOUND` immediately after FETCH. |
| Headings repeat | ORDER BY missing | Control break needs rows sorted by the break column. |

## 9. Viva questions and answers

**Q1. Explain the cursor lifecycle.**  
Declare the query, OPEN executes it, FETCH moves one row into variables, test %NOTFOUND, process, CLOSE releases it.

**Q2. Implicit vs explicit cursor?**  
Oracle opens an implicit cursor for every SQL statement (SQL%ROWCOUNT); an explicit cursor is declared and controlled by the programmer for multi-row queries.

**Q3. Why a parameterised cursor?**  
The same query serves any date or day count, and the parameter is visible in the declaration.

**Q4. When is a cursor FOR loop better?**  
When every row is processed: no OPEN/FETCH/CLOSE code and no leak.

**Q5. What is %ROWCOUNT?**  
Number of rows fetched so far.

**Q6. What is a REF CURSOR for?**  
To return a result set to a client program.

**Q7. Why not just a SELECT?**  
We need per-row logic: block headings, numbering, percentages and flags.

## 10. Important practical commands

```
SET SERVEROUTPUT ON SIZE UNLIMITED
EXEC pr_daily_roster(TRUNC(SYSDATE));
EXEC pr_daily_roster(TRUNC(SYSDATE) + 1);
EXEC pr_block_occupancy;
EXEC pr_upcoming_releases(60);
VARIABLE rc REFCURSOR
EXEC :rc := fn_roster_refcursor(TRUNC(SYSDATE));
PRINT rc
```

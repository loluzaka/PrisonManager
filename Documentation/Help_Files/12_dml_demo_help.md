# Help: `12_dml_demo.sql`

## 1. File overview

* **Exact filename:** `12_dml_demo.sql`
* **Location:** `sql/`
* **Purpose:** Demonstrates INSERT (single, bulk), UPDATE, DELETE and the rejection of invalid rows, then rolls everything back.
* **Feature(s):** F7 (data entry and changes)
* **Member responsibility:** Member 1
* **Role in the system:** Shows the DML statements and what the constraints do to bad data.
* **Execution order:** Demo; after the install (needs data and triggers).

## 2. Required database objects and dependencies

* **Tables:** VISITORS (inserted/updated/deleted), BLOCKS, INMATES, VISITS (rejected inserts).
* **Triggers that fire:** `trg_audit_visitors` on each visitor change; `trg_block_conflict_visit` on the rejected visit insert.
* **Leaves the data unchanged** (ends with ROLLBACK).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **INSERT** | Adds rows. | `INSERT INTO t (cols) VALUES (...); INSERT INTO t (cols) SELECT ...;` | Single row, `INSERT ... SELECT ... UNION ALL` (3 rows in one statement), `INSERT ... SELECT ... CONNECT BY LEVEL` (5 generated rows). |
| **UPDATE** | Changes values of existing rows. | `UPDATE t SET col = val WHERE cond;` | One row by key, then several rows with `LIKE`. |
| **DELETE** | Removes rows (can be rolled back, fires triggers). | `DELETE FROM t WHERE cond;` | Removes the generated rows (allowed: no history). |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | `ROLLBACK` at the end undoes all changes. |
| **CONNECT BY LEVEL** | Row generator: produces N rows from DUAL. | `SELECT LEVEL FROM dual CONNECT BY LEVEL <= 100` | Row generator for bulk data. |
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | A block with a local procedure `attempt(title, sql)` that runs each bad statement and prints the error. |
| **EXECUTE IMMEDIATE** | Runs a SQL string built at run time (needed for DDL inside PL/SQL). | `EXECUTE IMMEDIATE 'ALTER TABLE ...';` | Runs the bad statements as text so each can be caught individually. |
| **EXCEPTION** | Section that catches errors: predefined (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ...), user-defined, or WHEN OTHERS. | `EXCEPTION WHEN NO_DATA_FOUND THEN ... WHEN OTHERS THEN ...` | `WHEN OTHERS THEN` prints `SQLERRM` - the constraint name shows which rule fired. |
| **CHECK** | A condition every row must satisfy (domain integrity). | `CONSTRAINT ck_x CHECK (capacity > 0)` | Several rejected rows violate CHECK constraints. |
| **FOREIGN KEY** | Makes a column (or columns) point at the primary key of another table so orphans cannot exist (referential integrity). | `col type CONSTRAINT fk_x REFERENCES parent (key)` | Unknown inmate; delete of a parent with children. |
| **UNIQUE** | No two rows may share the value (or combination of values); NULLs are ignored. Creates an index. | `CONSTRAINT uq_x UNIQUE (col1, col2)` | Duplicate ID proof. |
| **NOT NULL** | Column must always have a value. | `col type NOT NULL` | Missing full_name. |

**Common mistakes with these keywords**

* *INSERT*: Omitting the column list - breaks when columns are added later.
* *UPDATE*: Forgetting WHERE changes every row.
* *DELETE*: Forgetting WHERE deletes everything.
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.
* *CONNECT BY LEVEL*: Forgetting the upper bound gives an endless query.
* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.
* *EXECUTE IMMEDIATE*: SQL injection risk if the string contains user input; DDL commits implicitly.
* *EXCEPTION*: A bare WHEN OTHERS THEN NULL hides bugs.
* *CHECK*: A CHECK cannot contain a subquery or SYSDATE - use a trigger for rules that need other rows or the clock.
* *FOREIGN KEY*: Inserting a child before its parent -> ORA-02291; deleting a parent that has children -> ORA-02292.
* *UNIQUE*: Expecting UNIQUE to forbid several NULLs - it does not.
* *NOT NULL*: Inserting without the column and without a DEFAULT -> ORA-01400.

**Why not `INSERT ALL`?** With an IDENTITY column Oracle evaluates the generator once per statement, so every row would receive the same new ID (found while testing: ORA-00001 on `PK_VISITORS`). The bulk demo therefore uses `INSERT ... SELECT ... UNION ALL`.

## 4. Tables and columns involved

### VISITORS

A person who wants to visit inmates.

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **VISITOR_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **FULL_NAME** | VARCHAR2(100) | NOT NULL | `—` | — | Synthetic name. |
| 3 | **ID_PROOF_TYPE** | VARCHAR2(20) | NOT NULL | `—` | CK CK_VISITORS_IDTYPE | PASSPORT, NATIONAL_ID, DRIVING_LICENCE or VOTER_ID. |
| 4 | **ID_PROOF_NUMBER** | VARCHAR2(30) | NOT NULL | `—` | — | Synthetic identity number (SYN-nnnnnn). Masked in views (F26). |
| 5 | **PHONE** | VARCHAR2(20) | NULL | `—` | — | Optional synthetic phone number. |
| 6 | **APPROVAL_STATUS** | VARCHAR2(12) | NOT NULL | `'PENDING'` | CK CK_VISITORS_APPROVAL | PENDING (default), APPROVED, REJECTED or BLACKLISTED. Only APPROVED visitors may book. |
| 7 | **REGISTERED_ON** | DATE | NOT NULL | `TRUNC(SYSDATE)` | — | Registration date; defaults to today. |

Unique constraints: `UQ_VISITORS_IDPROOF`

Check constraints:

* `CK_VISITORS_APPROVAL` — `approval_status IN ('PENDING','APPROVED','REJECTED','BLACKLISTED')`
* `CK_VISITORS_IDTYPE` — `id_proof_type IN ('PASSPORT','NATIONAL_ID','DRIVING_LICENCE','VOTER_ID')`

**Why this structure:** The default `approval_status = PENDING` and the constraints are what make the demo statements behave as shown.

## 5. Walkthrough

1. Insert one visitor without an approval status -> PENDING by DEFAULT.
2. Bulk insert three visitors with one statement; five more generated with CONNECT BY.
3. Count the demo rows (9). Update one visitor to APPROVED; update the phone of the five generated; delete those five.
4. PL/SQL block runs nine bad statements and prints the Oracle message for each (see below).
5. ROLLBACK; the count of demo rows is 0 again.

## 6. Actual execution example

Real output of step 4:

```
rejected  negative block capacity          ORA-02290: check constraint (PRISON_OWNER.CK_BLOCKS_CAPACITY) violated
rejected  unknown security level           ORA-02290: check constraint (PRISON_OWNER.CK_BLOCKS_SECURITY) violated
rejected  sentence ends before it starts   ORA-02290: check constraint (PRISON_OWNER.CK_INMATES_SENTENCE) violated
rejected  duplicate ID proof               ORA-00001: unique constraint (PRISON_OWNER.UQ_VISITORS_IDPROOF) violated
rejected  missing NOT NULL (full_name)     ORA-01400: cannot insert NULL into ("PRISON_OWNER"."VISITORS"."FULL_NAME")
rejected  visit with unknown inmate (FK)   ORA-02291: integrity constraint (PRISON_OWNER.FK_VISITS_INMATE) violated - parent key not found
rejected  visit with invalid slot name     ORA-02290: check constraint (PRISON_OWNER.CK_VISITS_SLOT) violated
rejected  delete inmate that has history   ORA-02292: integrity constraint (PRISON_OWNER.FK_VISITS_INMATE) violated - child record found
rejected  delete block that has inmates    ORA-02292: integrity constraint (PRISON_OWNER.FK_MOV_TO) violated - child record found
```
Steps 1-3: `1 row created. 3 rows created. 5 rows created. DEMO_VISITORS_NOW 9. 1 row updated. 5 rows updated. 5 rows deleted.`

## 7. Data flow and integration

```
 INSERT/UPDATE/DELETE on VISITORS ─► trg_audit_visitors ─► AUDIT_LOG (rolled back with the rest)
 rejected statements ─► constraint names in the error text; a rejected visit still leaves a VISIT_DENIED row only if the TRIGGER refused it
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-00001 PK_VISITORS` on bulk insert | INSERT ALL with an identity column | Use INSERT ... SELECT. |
| Demo rows remain | Script aborted before ROLLBACK | Run `DELETE FROM visitors WHERE id_proof_number LIKE 'SYN-DEMO%'; COMMIT;`. |
| `ORA-00001 UQ_VISITORS_IDPROOF` on re-run | Previous run committed | Clean up as above. |

## 9. Viva questions and answers

**Q1. Difference between DELETE, TRUNCATE, DROP?**  
Rows (rollback-able) vs all rows (instant) vs the table itself.

**Q2. What does INSERT ... SELECT give you?**  
Bulk loading from a query in one statement.

**Q3. How can you tell which rule rejected a row?**  
The error message names the constraint, e.g. `CK_BLOCKS_CAPACITY`.

**Q4. Why can an inmate with history not be deleted?**  
Foreign keys without CASCADE refuse it (ORA-02292); use the status column instead.

## 10. Important practical commands

```
@12_dml_demo.sql
SELECT COUNT(*) FROM visitors WHERE id_proof_number LIKE 'SYN-DEMO%';
ROLLBACK;
```

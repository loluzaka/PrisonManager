# Help: `02_alter_schema.sql`

## 1. File overview

* **Exact filename:** `02_alter_schema.sql`
* **Location:** `sql/`
* **Purpose:** Evolves the base schema with ALTER TABLE and adds the supporting tables (facilities, rivalries, slot capacities, staff access); demonstrates TRUNCATE and DROP.
* **Feature(s):** F4 (ALTER / DROP / TRUNCATE), F14 (conflict lifecycle, rivalries), F15 (risk_level), F16 (visit slots), F31 (facilities)
* **Member responsibility:** Member 1 (schema) supporting Members 2 and 3
* **Role in the system:** Shows schema evolution exactly as the specification describes: columns arrive after the first design.
* **Execution order:** After `01_create_tables.sql`; before `03_indexes.sql`. Not re-runnable alone (ALTER ADD fails on an existing column) - use `99_drop_all.sql` first.

## 2. Required database objects and dependencies

* **Needs:** tables BLOCKS, INMATES, VISITS, CONFLICTS from script 01.
* **Creates:** FACILITIES, INMATE_CONFLICTS, VISIT_SLOTS, STAFF_ACCESS (+ a temporary `tmp_visit_test`, dropped at the end).
* **Alters:** BLOCKS (+`facility_id`), INMATES (+`risk_level`), CONFLICTS (+`resolved`, `resolved_on`, `expiry_date`).
* **Needed by:** seed (04), rules (07-09), views (11), roles (17).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **ALTER TABLE** | Changes an existing table: add/modify/drop columns, add constraints. | `ALTER TABLE t ADD (col type ...); ALTER TABLE t MODIFY (col NOT NULL); ALTER TABLE t ADD CONSTRAINT ...` | `ADD (col ...)` for new columns; `ADD CONSTRAINT ck_conf_expiry CHECK (...)` for a rule added later. |
| **CREATE TABLE** | Defines a new table: its columns, data types and constraints. The table starts empty. | `CREATE TABLE name (col type [constraint], ..., [table constraint]);` | Four supporting tables; `tmp_visit_test` is built with `AS SELECT ... WHERE 1 = 0` (structure copy, no rows). |
| **TRUNCATE** | Deletes all rows instantly, resets the high-water mark, cannot be rolled back, fires no row triggers. | `TRUNCATE TABLE t;` | Empties `tmp_visit_test` instantly - the output shows 1 row before and 0 after. |
| **DROP TABLE** | Removes a table and its data. PURGE also skips the recycle bin. | `DROP TABLE t PURGE;` | `DROP TABLE tmp_visit_test PURGE` removes the demo table completely. |
| **FOREIGN KEY** | Makes a column (or columns) point at the primary key of another table so orphans cannot exist (referential integrity). | `col type CONSTRAINT fk_x REFERENCES parent (key)` | `blocks.facility_id -> facilities`, `inmate_conflicts.inmate_a/b -> inmates`, `staff_access.facility_id -> facilities`. |
| **CHECK** | A condition every row must satisfy (domain integrity). | `CONSTRAINT ck_x CHECK (capacity > 0)` | `ck_ic_order (inmate_a < inmate_b)` stores each rivalry pair once; `ck_slots_max (max_visitors > 0)`. |
| **DEFAULT** | Value used when an INSERT does not mention the column. | `col type DEFAULT expr NOT NULL` | `risk_level DEFAULT 'LOW' NOT NULL` lets the ALTER succeed even though INMATES may already have rows. |
| **INSERT** | Adds rows. | `INSERT INTO t (cols) VALUES (...); INSERT INTO t (cols) SELECT ...;` | Six rows into VISIT_SLOTS - fixed reference data. |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | COMMIT after the slot inserts. |

**Common mistakes with these keywords**

* *ALTER TABLE*: MODIFY ... NOT NULL fails (ORA-02296) if existing rows contain NULL - load data first.
* *CREATE TABLE*: Creating a child table before its parent (the FOREIGN KEY target must exist) -> ORA-00942.
* *TRUNCATE*: Using it on a table referenced by an enabled foreign key -> ORA-02266.
* *DROP TABLE*: Dropping a parent first -> ORA-02449; drop children first.
* *FOREIGN KEY*: Inserting a child before its parent -> ORA-02291; deleting a parent that has children -> ORA-02292.
* *CHECK*: A CHECK cannot contain a subquery or SYSDATE - use a trigger for rules that need other rows or the clock.
* *DEFAULT*: Writing the DEFAULT after NOT NULL (Oracle wants DEFAULT first).
* *INSERT*: Omitting the column list - breaks when columns are added later.
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.

## 4. Tables and columns involved

### FACILITIES

A prison facility (F31 multi-facility access).

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **FACILITY_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **FACILITY_NAME** | VARCHAR2(100) | NOT NULL | `—` | — | Unique facility name. |
| 3 | **CITY** | VARCHAR2(60) | NOT NULL | `—` | — | City where the facility is located. |

Unique constraints: `UQ_FACILITIES_NAME`

### INMATE_CONFLICTS

Rivalry between two inmates; rivals may never be housed in the same block.

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **RIVALRY_ID** | NUMBER | NOT NULL | `identity (auto-generated)` | PK (identity) | Surrogate primary key. |
| 2 | **INMATE_A** | NUMBER | NOT NULL | `—` | FK → INMATES; CK CK_IC_ORDER | Smaller inmate id of the pair. |
| 3 | **INMATE_B** | NUMBER | NOT NULL | `—` | FK → INMATES; CK CK_IC_ORDER | Larger inmate id of the pair. |
| 4 | **REASON** | VARCHAR2(20) | NOT NULL | `—` | CK CK_IC_REASON | RIVAL, GANG_AFFILIATION or OTHER. |
| 5 | **FLAGGED_DATE** | DATE | NOT NULL | `TRUNC(SYSDATE)` | — | Day recorded. |
| 6 | **RESOLVED** | CHAR(1) | NOT NULL | `'N'` | CK CK_IC_RESOLVED | Y when no longer active. |

Unique constraints: `UQ_IC_PAIR`

Check constraints:

* `CK_IC_ORDER` — `inmate_a < inmate_b`
* `CK_IC_REASON` — `reason IN ('RIVAL','GANG_AFFILIATION','OTHER')`
* `CK_IC_RESOLVED` — `resolved IN ('Y','N')`

Relationships: `INMATE_A` → **INMATES** (`FK_IC_A`, on delete NO ACTION); `INMATE_B` → **INMATES** (`FK_IC_B`, on delete NO ACTION)

### VISIT_SLOTS

Reference data: capacity of each fixed visit slot (F16). The slot row is locked during booking.

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **SLOT_CODE** | VARCHAR2(11) | NOT NULL | `—` | PK | Primary key, e.g. 09:00-10:00. |
| 2 | **START_TIME** | VARCHAR2(5) | NOT NULL | `—` | — | Start time text. |
| 3 | **END_TIME** | VARCHAR2(5) | NOT NULL | `—` | — | End time text. |
| 4 | **MAX_VISITORS** | NUMBER(3) | NOT NULL | `5` | CK CK_SLOTS_MAX | Maximum non-cancelled visits in this slot per date. |

Check constraints:

* `CK_SLOTS_MAX` — `max_visitors > 0`

### STAFF_ACCESS

Maps a database login to the facility whose rows it may see (F31). NULL facility = all.

| # | Column | Data type | Null? | Default | Constraints | Description |
|---|---|---|---|---|---|---|
| 1 | **DB_USERNAME** | VARCHAR2(30) | NOT NULL | `—` | PK | Primary key: Oracle user name. |
| 2 | **FACILITY_ID** | NUMBER | NULL | `—` | FK → FACILITIES | Facility the user is bound to; NULL means every facility. |

Relationships: `FACILITY_ID` → **FACILITIES** (`FK_STAFF_FACILITY`, on delete NO ACTION)

**Why this structure:** Reference data (slots), isolation scope (facilities, staff access) and the recursive rivalry relationship each get their own table instead of extra columns, keeping BCNF. `blocks.facility_id` is added NULLABLE and tightened to NOT NULL by `04_seed_data.sql` after rows exist (the "add the constraint after loading data" technique).

## 5. Walkthrough

1. `CREATE TABLE facilities`, then `ALTER TABLE blocks ADD (facility_id ... REFERENCES facilities)` - the FK column is nullable for now.
2. `ALTER TABLE inmates ADD (risk_level ... CHECK ...)` - F15 groundwork.
3. `ALTER TABLE conflicts ADD (resolved, resolved_on, expiry_date)` plus a second ALTER adding `ck_conf_expiry` - F14 lifecycle.
4. `inmate_conflicts` and `visit_slots` created; six slots inserted with capacity 5.
5. `staff_access` created (filled by script 17).
6. **TRUNCATE vs DROP demo**: a throw-away copy of VISITS gets one row, is counted, truncated (row count 0, table still exists), then dropped.

## 6. Actual execution example

Real output (excerpt):

```
Table altered.   (x4: blocks, inmates, conflicts, conflicts-constraint)
ROWS_BEFORE_TRUNCATE
--------------------
                   1
Table truncated.
ROWS_AFTER_TRUNCATE
-------------------
                  0
Table dropped.
02_alter_schema.sql finished: schema evolved to 11 tables.
```

## 7. Data flow and integration

```
 01 tables ──ALTER──► +facility_id, +risk_level, +resolved/expiry
          └─CREATE──► FACILITIES, INMATE_CONFLICTS, VISIT_SLOTS, STAFF_ACCESS
 later: 04 fills them · 08/09 use risk_level + INMATE_CONFLICTS · 09 locks VISIT_SLOTS rows · 11/17 use STAFF_ACCESS
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-01430: column being added already exists` | Script run twice | Run `99_drop_all.sql`, then rebuild. |
| `ORA-02296: cannot enable - null values found` | MODIFY ... NOT NULL on a column that has NULLs | Fill the column first (the seed does this before `ALTER ... facility_id NOT NULL`). |
| `ORA-02266: unique/primary keys in table referenced by enabled foreign keys` on TRUNCATE | Parent table referenced by a foreign key | Truncate only unreferenced tables, or delete child-first. |

## 9. Viva questions and answers

**Q1. Why use ALTER instead of putting every column in script 01?**  
It demonstrates schema evolution (F4): real systems change after go-live and ALTER lets the change happen without losing data.

**Q2. TRUNCATE vs DELETE vs DROP?**  
DELETE removes chosen rows, can be rolled back and fires triggers; TRUNCATE removes all rows instantly, cannot be rolled back, no row triggers; DROP removes the table itself.

**Q3. Why is `facility_id` added nullable first?**  
Existing rows have no facility yet; after loading data the NOT NULL constraint is added (F4).

**Q4. Why store each rivalry once with `inmate_a < inmate_b`?**  
Otherwise (3,7) and (7,3) would be two rows for the same fact; the CHECK plus UNIQUE guarantees one.

## 10. Important practical commands

```
DESC inmates
SELECT column_name, data_type, nullable, data_default FROM user_tab_columns WHERE table_name='INMATES' ORDER BY column_id;
SELECT * FROM visit_slots;
SELECT constraint_name, search_condition_vc FROM user_constraints WHERE table_name='CONFLICTS' AND constraint_type='C';
```

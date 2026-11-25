# Detailed PostgreSQL and SQL Report

## 1. Purpose and scope

This report describes the PostgreSQL implementation of the Prison Visitor and Inmate Management System. It inventories the database tables, constraints, views, functions, procedures, cursors, and triggers, and explains the main data operations.

The database is the core of the project: it stores the records, enforces operational rules, records changes, and supplies reports to the Flask interface. Seed records are synthetic.

The installation script runs the SQL files in this order: roles, schema, seed data, routines and triggers, views, and permissions (`postgres/install.sql`). The project contains 11 tables, 17 views, 26 functions, 3 procedures, 7 triggers, and 10 named performance indexes.

## 2. Relational tables

| Table | Important columns | Purpose and relationships |
|---|---|---|
| `facilities` | `facility_id`, `facility_name`, `city` | Facility directory. A facility has multiple blocks. |
| `blocks` | `block_id`, `block_name`, `capacity`, `security_level`, `facility_id` | Housing units belonging to a facility. Capacity must be positive; security is `LOW`, `MEDIUM`, or `HIGH`. |
| `inmates` | `inmate_id`, `inmate_no`, `full_name`, `date_of_birth`, `admission_date`, `sentence_start`, `sentence_end`, `status`, `block_id`, `risk_level` | Inmate record and current placement. References a block; status is `ACTIVE`, `TRANSFERRED`, or `RELEASED`. |
| `visitors` | `visitor_id`, `full_name`, `id_proof_type`, `id_proof_number`, `phone`, `approval_status`, `registered_on` | Visitor registration and approval state. A unique constraint prevents the same ID proof type/number being registered twice. |
| `visits` | `visit_id`, `inmate_id`, `visitor_id`, `visit_date`, `slot`, `status`, `booked_on` | Visit bookings linking one inmate and one visitor. Status is `SCHEDULED`, `COMPLETED`, `MISSED`, or `CANCELLED`. |
| `movements` | `movement_id`, `inmate_id`, `from_block`, `to_block`, `movement_date`, `reason`, `moved_by` | Historical admissions and transfers between blocks. |
| `conflicts` | `conflict_id`, `inmate_id`, `visitor_id`, `reason`, `flagged_date`, `resolved`, `resolved_on`, `expiry_date` | Restrictions between an inmate and a visitor. A unique inmate/visitor pair is recorded once and can later be resolved or expired. |
| `inmate_conflicts` | `rivalry_id`, `inmate_a`, `inmate_b`, `reason`, `flagged_date`, `resolved` | Rivalry or other placement restriction between two inmates. The ordered pair constraint avoids duplicate/reversed pairs and self-conflicts. |
| `visit_slots` | `slot_code`, `start_time`, `end_time`, `max_visitors` | Valid visit periods and the maximum number of visits allowed in a slot. |
| `staff_access` | `db_username`, `facility_id` | Maps a database login to a facility. A `NULL` facility represents all-facility access. |
| `audit_log` | `audit_id`, `table_name`, `action_type`, `record_id`, `details`, `changed_by`, `changed_at` | Append-only history of important record changes, visit bookings/denials, transfers, and maintenance runs. |

### Keys, constraints, and indexes

- Each table has a primary key; generated IDs use PostgreSQL identity columns where appropriate.
- Foreign keys connect blocks to facilities, inmates to blocks, visits to inmates and visitors, and history/conflict records to their related entities.
- `NOT NULL`, `CHECK`, and `UNIQUE` constraints reject missing or invalid values, bad statuses, unsupported ID types, invalid dates, nonpositive capacities, and duplicate records.
- `UNIQUE (inmate_id, visit_date, slot)` prevents an inmate from being booked twice in the same slot. The visit trigger additionally checks total slot capacity and weekly limits.
- `CHECK (inmate_a < inmate_b)` in `inmate_conflicts` gives each inmate pair one canonical order.
- Ten named indexes support common lookups: inmates by block/status, visits by date/inmate/visitor, movements by inmate/destination block, audit entries by table/record or action/time, and blocks by facility.

## 3. Data and SQL operations

### Demo dataset

`postgres/002_seed.sql` creates synthetic data for two facilities, five blocks, 50 inmates, 40 visitors, six visit slots, 100 visits, eight visitor conflicts, three inmate-rivalry records, and 58 movements. It uses `generate_series`, arrays, `CASE`, date arithmetic, common table expressions, and a PL/pgSQL loop to create repeatable demo records while observing booking rules.

### Main operations

1. **Set up facilities and housing:** insert facilities and blocks; constraints validate capacity and security level.
2. **Register a visitor:** `fn_register_visitor` creates a visitor as `PENDING`, rejects duplicate identity documents, and returns a status/message rather than exposing raw constraint errors for expected invalid data.
3. **Approve or restrict a visitor:** `fn_set_visitor_status` changes approval state. Setting a visitor to `REJECTED` or `BLACKLISTED` cancels their future scheduled visits.
4. **Record and resolve conflicts:** `fn_add_conflict` records an inmate/visitor conflict and cancels matching future visits. `fn_resolve_conflict` marks it resolved. `fn_add_inmate_rivalry` records an inmate-to-inmate restriction.
5. **Book a visit:** `fn_schedule_visit` checks the caller's facility access, inmate and visitor existence/status, conflicts, slot validity, visit date, sentence period, duplicate bookings, weekly limit, and slot capacity. It returns a result such as `BOOKED`, `DENIED_FACILITY`, `DENIED_BLACKLISTED`, `DENIED_WEEKLY_LIMIT`, or `SLOT_FULL`, plus a message and visit ID when booked.
6. **Transfer an inmate:** `fn_transfer_inmate` checks that the inmate is active, the target block exists and has capacity, the risk level fits the block security, and no active rival is housed there. A successful update creates movement and audit history.
7. **Run maintenance:** `fn_nightly_maintenance` marks inmates whose sentence has passed as `RELEASED`, marks past scheduled visits as `MISSED`, and logs counts. It is a callable function; a PostgreSQL scheduler/job is not configured in this project.
8. **Read screens and reports:** the application and staff roles query the views described below rather than each rebuilding the joins and calculations.

Typical calls (use valid IDs and dates from the installed demo data):

```sql
SELECT * FROM fn_register_visitor(
    'Demo Visitor', 'PASSPORT', 'DEMO-12345', '+00-555-0000'
);

SELECT * FROM fn_schedule_visit(
    12, 1, CURRENT_DATE + 30, '09:00-10:00'
);

SELECT * FROM fn_transfer_inmate(12, 2, 'Approved housing transfer');

SELECT * FROM fn_nightly_maintenance();
```

### SQL techniques used

- DDL: `CREATE TABLE`, identity columns, constraints, indexes, views, functions, procedures, and triggers.
- DML: `INSERT`, `UPDATE`, `DELETE`, `INSERT ... RETURNING`, `ON CONFLICT`, and conditional updates.
- Querying: inner/left/cross joins, subqueries, `EXISTS`, aggregates (`COUNT`, `SUM`, `MAX`), `GROUP BY`, `HAVING`, `CASE`, date functions, and string formatting.
- Procedural SQL: PL/pgSQL variables, conditionals, loops, records, exceptions, diagnostics such as `GET DIAGNOSTICS ... ROW_COUNT`, and cursor handling.
- Data generation: CTEs, `generate_series`, arrays, window function `row_number`, and date/time arithmetic.
- Concurrency and integrity: transactions, `FOR UPDATE` row locks, foreign keys, unique constraints, and trigger validation.
- Authorization: database login roles, group roles, `GRANT`/`REVOKE`, `session_user`, facility mapping, and `SECURITY DEFINER` routines with a fixed `search_path`.

## 4. Views and reports

The 17 views in `postgres/004_views.sql` are read models for the UI, role-scoped access, and operational reporting.

| View | What it returns |
|---|---|
| `v_active_inmates` | Active inmates with block/facility, risk, sentence end, and calculated days remaining. |
| `v_todays_visits` | Today's visits with slot, block, inmate, visitor, and status. |
| `v_eligible_visitors` | Approved visitors, masked identity number, and visit count. |
| `v_visit_eligibility` | Approved-visitor/active-inmate pairs without an active conflict. |
| `v_block_occupancy` | Occupied beds, free beds, occupancy percentage, and an availability flag per block. |
| `v_visitors_masked` | Visitor directory with ID numbers masked except for the final four characters. |
| `v_inmate_conflicts` | Visitor conflict details and a derived state of active, expired, or resolved. |
| `v_denied_attempts` | Audited denied-booking attempts, parsed reason/inmate ID, visitor, and database user. |
| `v_movement_history` | Inmate movement timeline with source and destination block names. |
| `v_blacklisted_visitors` | Blacklisted visitors with masked IDs and the count of denied attempts. |
| `v_frequent_visitors` | Visitors with at least three scheduled/completed visits, distinct inmates visited, and last visit. |
| `v_upcoming_releases` | Active inmates whose sentence ends within the next 60 days. |
| `v_visit_stats_per_inmate` | Total/completed/missed visits, distinct visitors, and last visit per inmate. |
| `v_monthly_visit_stats` | Monthly visit totals, status counts, and distinct visitors. |
| `v_fac_blocks` | Blocks visible to the current database login's assigned facility, or all blocks for an all-facility login. |
| `v_fac_inmates` | Inmates joined to the current login's allowed blocks. |
| `v_fac_visits` | Visits joined to the inmate's block and limited by the facility-scoped block view. |

The views centralize joins, calculations, masking, and facility filtering. Role permissions determine which views each group can select.

## 5. All 26 functions

The function definitions are in `postgres/003_routines_triggers.sql`. Five functions are trigger handlers; the others are reusable checks, operations, and report helpers.

### Calculation and validation helpers

| Function | Purpose |
|---|---|
| `fn_level_rank(text)` | Converts `LOW`, `MEDIUM`, `HIGH` to ordered ranks 1–3 for risk/security comparisons. |
| `fn_inmate_visit_count(bigint)` | Counts an inmate's scheduled and completed visits. |
| `fn_visitor_visit_count(bigint)` | Counts a visitor's scheduled and completed visits. |
| `fn_block_occupancy(bigint)` | Counts active inmates in a block. |
| `fn_has_active_conflict(bigint, bigint)` | Checks for an unresolved, non-expired visitor/inmate conflict. |
| `fn_is_visitor_eligible(bigint, bigint)` | Returns `NO_VISITOR`, `NO_INMATE`, `BLACKLISTED`, `UNAPPROVED`, `CONFLICT`, `INMATE_INACTIVE`, or `ELIGIBLE`. |
| `fn_days_remaining(bigint)` | Returns nonnegative days until an inmate's sentence end. |
| `fn_weekly_visit_count(bigint, date)` | Counts non-cancelled visits for an inmate in the given calendar week. |
| `fn_slot_visit_count(date, text)` | Counts non-cancelled bookings in a date and slot. |
| `fn_next_free_slot(bigint, date)` | Finds the earliest slot with no inmate duplicate and remaining slot capacity; returns `NULL` if none exists. |
| `fn_diff(text, text, text)` | Formats an old/new value difference for audit details, or returns `NULL` if unchanged. |

### Audit and trigger-handler functions

| Function | Purpose |
|---|---|
| `log_audit(text, text, bigint, text)` | Inserts one audit record and limits details to the column's maximum length. |
| `trigger_audit_row()` | Audits inserts, deletes, and relevant updates to inmates, visitors, and visits. |
| `trigger_audit_immutable()` | Rejects an update or delete against the append-only audit log. |
| `trigger_validate_inmate()` | Checks active placement against block security, capacity, and active inmate rivalries; locks affected blocks while validating. |
| `trigger_log_movement()` | Adds an admission or transfer movement when an inmate is inserted or changes block; records transfer reason in the audit log. |
| `trigger_validate_visit()` | For non-cancelled visits, locks the inmate/slot and checks date, sentence range, eligibility, weekly limit, and slot capacity. |

### Application and business-operation functions

| Function | Purpose |
|---|---|
| `fn_register_visitor(text, text, text, text)` | Registers a visitor as pending; returns a structured outcome for duplicate IDs or invalid data. |
| `fn_set_visitor_status(bigint, text)` | Changes approval status; blacklisting/rejection cancels future scheduled visits. |
| `fn_add_conflict(bigint, bigint, text, date)` | Adds or reopens a visitor conflict and cancels matching future bookings. |
| `fn_resolve_conflict(bigint)` | Resolves a conflict and reports resolved/already-resolved/not-found. |
| `fn_add_inmate_rivalry(bigint, bigint, text)` | Adds a canonicalized inmate pair; avoids duplicate/reversed pair entries. |
| `fn_schedule_visit(bigint, bigint, date, text)` | Checks staff facility scope and booking rules, books a valid visit, and audits denials. |
| `fn_transfer_inmate(bigint, bigint, text)` | Checks inmate state, target block, capacity, security, and rival placement before transfer. |
| `fn_nightly_maintenance()` | Releases inmates past sentence end, marks past scheduled visits missed, and logs affected counts. |
| `fn_roster_refcursor(date)` | Opens and returns a `refcursor` for a date's visit roster. |

The trigger-handler functions are not intended to be called directly by application users; PostgreSQL invokes them through their associated triggers.

## 6. All seven triggers

| Trigger | Table and timing | Effect |
|---|---|---|
| `trg_audit_log_immutable` | `audit_log`, before `UPDATE` or `DELETE` | Raises an exception; existing audit entries cannot be edited or removed through ordinary DML. |
| `trg_audit_inmates` | `inmates`, after `INSERT`, `UPDATE`, or `DELETE` | Records creation/deletion and meaningful field changes. |
| `trg_audit_visitors` | `visitors`, after `INSERT`, `UPDATE`, or `DELETE` | Records registration/deletion and changes such as approval status or contact/identity fields. |
| `trg_audit_visits` | `visits`, after `INSERT`, `UPDATE`, or `DELETE` | Records bookings, deletions, and changes to visit status/date/slot. |
| `trg_inmate_placement_rules` | `inmates`, before insert or update of `block_id`, `status`, or `risk_level` | Rejects an active inmate placement if block security is insufficient, capacity is full, or an active rival is in that block. |
| `trg_log_movement` | `inmates`, after insert or update of `block_id` | Creates admission/transfer movement history; a transfer also gets an audit entry. |
| `trg_visit_rules` | `visits`, before insert or update of booking fields/status | Independently validates visit eligibility, date range, weekly limit, and slot capacity, including direct SQL writes. |

The audit triggers fire as part of the same transaction as the underlying change: if that transaction rolls back, its audit insert rolls back too.

## 7. Procedures and cursors

PostgreSQL distinguishes functions (called with `SELECT` and able to return values) from procedures (called with `CALL`, often used here to emit report output through `RAISE NOTICE`).

### `pr_daily_roster(p_date date DEFAULT CURRENT_DATE)`

- Declares explicit cursor `c_daily_roster`.
- The cursor selects visits for `p_date` and joins the inmate, block, and visitor names.
- Uses `OPEN`, repeated `FETCH`, `EXIT WHEN NOT FOUND`, and `CLOSE`.
- Groups output by block using `RAISE NOTICE`; reports when no visits are scheduled.

Example:

```sql
CALL pr_daily_roster(CURRENT_DATE);
```

### `pr_block_occupancy()`

- Declares explicit cursor `c_block_occupancy` over blocks and facilities.
- Opens, fetches each block, calls `fn_block_occupancy`, and emits occupied/capacity/facility through `RAISE NOTICE`.
- Closes the cursor after iteration.

Example:

```sql
CALL pr_block_occupancy();
```

### `pr_upcoming_releases(p_days integer DEFAULT 30)`

- Iterates inmates whose sentence end falls between today and today plus `p_days`.
- Uses a PL/pgSQL `FOR record IN SELECT ... LOOP` query loop (an implicit cursor), rather than a declared `OPEN`/`FETCH` cursor.
- Emits inmate number, name, and days remaining with `RAISE NOTICE`.

Example:

```sql
CALL pr_upcoming_releases(30);
```

### `fn_roster_refcursor(p_date date)`

This is a function, not a procedure. It opens and returns a named `refcursor` (`roster_cursor`) for the requested date. The caller must fetch from that cursor in the same database session and transaction.

## 8. Roles, permissions, and facility scope

`postgres/00_roles.sql` creates five login accounts:

- `prison_u_admin`
- `prison_u_warden`
- `prison_u_warden2`
- `prison_u_frontdesk`
- `prison_u_auditor`

`postgres/005_security.sql` assigns these logins to four `NOLOGIN` permission groups: `prison_admin`, `prison_warden`, `prison_front_desk`, and `prison_auditor`. It grants table, sequence, view, function, and procedure privileges according to role. For example, front desk receives view access and booking/registration functions rather than direct access to inmate, visitor, or audit tables.

Facility-specific views use `staff_access` and `session_user` to select the facility scope. Admin and auditor entries can use a `NULL` facility for all-facility visibility. The same facility check is performed inside `fn_schedule_visit`; hiding other facilities in the UI is not the only control. Visitor ID values are masked in user-facing views.

## 9. Testing evidence and limits

`postgres/tests.sql` contains 23 assertions across schema/data presence, helper behavior, views, and expected database failures. Examples include invalid capacity, missing foreign keys, blacklisted visit attempts, audit-log modification, and an inmate risk/security mismatch. `postgres/tests_roles.sql` exercises the five login roles, checks front-desk table restrictions, verifies masking, checks facility row counts, and tests allowed/denied booking outcomes.

The project documentation records these local PostgreSQL checks as passed. The most recent recorded Neon status is different: the production branch had zero project tables, and a schema installation attempt could not connect to its PostgreSQL endpoint from the environment. Thus these SQL features and tests are implemented locally, but the live cloud database schema and cloud-backed app flows were not yet verified. Neon Function health and private storage checks had been verified separately.

## 10. Notes for explaining the SQL contribution

- **A constraint** protects data at the table level; **a trigger** runs automatically for a matching table event; **a function** performs a callable operation or returns a value; **a procedure** performs a command-style task; **a cursor** processes query rows sequentially.
- The main database demonstration can show a valid booking, an invalid/denied booking, a transfer rejected for capacity/security/rivalry, a movement/audit record, a role-scoped view, and one cursor report.
- `fn_nightly_maintenance` is implemented, but no PostgreSQL scheduler is installed/configured to run it automatically.
- Historical Oracle-only demonstrations, such as `DBMS_SCHEDULER`, Oracle `PIVOT`, and Oracle flashback, are not part of this active PostgreSQL implementation.

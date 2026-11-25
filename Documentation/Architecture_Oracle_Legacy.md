# Legacy Oracle Architecture (reference only)

The database contains the business rules, and the optional web front end is in `ui/`. It connects from the server to Oracle with the wallet
and uses one of the least-privilege project role accounts. SQL clients (SQL*Plus, SQL Developer, DBeaver) remain supported.

## 1. Layers

```
 ┌────────────────────────────── USERS (SQL client, TLS to the cloud) ──────────────────────────────┐
 │  PRISON_ADMIN        PRISON_WARDEN        PRISON_FRONT_DESK         PRISON_AUDITOR              │
 └───────┬───────────────────┬───────────────────────┬───────────────────────┬──────────────────────┘
         │ EXECUTE / SELECT only - roles hold NO direct table rights for front desk / auditor      │
 ┌───────▼───────────────────▼───────────────────────▼───────────────────────▼──────────────────────┐
 │ REPORT & ACCESS LAYER   views: v_*  (masking, facility scope)   cursor reports: pr_*             │
 ├──────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ PROCEDURE LAYER (definer's rights, return status codes)                                           │
 │   sp_schedule_visit   sp_transfer_inmate   sp_register_visitor   sp_set_visitor_status            │
 │   sp_add_conflict     sp_resolve_conflict  sp_add_inmate_rivalry pr_nightly_maintenance (job)     │
 ├──────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ RULE LAYER (cannot be bypassed)       functions fn_*          package pkg_prison_rules            │
 │   trg_block_conflict_visit  trg_visit_slot_rules  trg_inmate_placement_rules  trg_log_movement   │
 │   trg_audit_inmates/visitors/visits   trg_audit_log_immutable                                     │
 ├──────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ DATA LAYER   11 tables + constraints + indexes                                                    │
 │   FACILITIES BLOCKS INMATES VISITORS VISITS MOVEMENTS CONFLICTS INMATE_CONFLICTS                  │
 │   VISIT_SLOTS STAFF_ACCESS AUDIT_LOG                                                              │
 └──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Defence in depth.** A rule is checked three times: (1) by the *procedure*, which returns a friendly status such as `SLOT_FULL`; (2) by a *trigger*, which stops anyone who
inserts or updates the table directly; (3) by a *constraint* where one expression is enough (CHECK / UNIQUE / FOREIGN KEY).
The eligibility rule lives in one function (`fn_is_visitor_eligible`) used by both the trigger and the procedure.

## 2. Main modules and the scripts that build them

| Module | Objects | Script |
|---|---|---|
| Accounts | PRISON_OWNER, 5 demo users | `sql/00_admin_setup.sql` |
| Schema | 7 core tables | `sql/01_create_tables.sql` |
| Schema evolution | FACILITIES, INMATE_CONFLICTS, VISIT_SLOTS, STAFF_ACCESS, new columns | `sql/02_alter_schema.sql` |
| Performance | 10 indexes | `sql/03_indexes.sql` |
| Data | synthetic dataset | `sql/04_seed_data.sql` |
| Rules support | package, 10 functions | `sql/05_package_and_functions.sql` |
| Audit | 2 logging procedures, 4 triggers | `sql/06_audit_trail.sql` |
| Visit rules | 2 triggers (1 compound) | `sql/07_visit_rules_triggers.sql` |
| Placement rules | 2 triggers (1 compound) | `sql/08_inmate_rules_triggers.sql` |
| Business procedures | 7 procedures | `sql/09_procedures.sql` |
| Cursors | 3 cursor procedures + REF CURSOR function | `sql/10_cursors.sql` |
| Views | 17 views | `sql/11_views.sql` |
| Security | 4 roles, grants | `sql/17_roles_security.sql` |
| Automation | 1 scheduler job | `sql/18_scheduled_jobs.sql` |

## 3. Data flow: booking a visit

```
 front-desk user ──CALL──► sp_schedule_visit(inmate, visitor, date, slot)
                              │ 1 SAVEPOINT
                              │ 2 SELECT ... FOR UPDATE  INMATES row, then VISIT_SLOTS row   (locks → no race)
                              │ 3 fn_is_visitor_eligible ──reads──► VISITORS, INMATES, CONFLICTS
                              │ 4 date rules, duplicate, weekly limit (fn_weekly_visit_count), slot capacity (fn_slot_visit_count)
                              │      any failure ─► sp_log_audit_auto  (autonomous commit: AUDIT_LOG VISIT_DENIED)
                              │                     ROLLBACK TO SAVEPOINT, return status 'DENIED_*' / 'SLOT_FULL'
                              │ 5 INSERT INTO VISITS ──fires──► trg_block_conflict_visit   (BEFORE, re-checks eligibility)
                              │                          ──────► trg_visit_slot_rules      (compound: sentence, weekly, slot)
                              │                          ──────► trg_audit_visits          (AFTER: AUDIT_LOG VISIT_BOOKED)
                              ▼ 6 COMMIT, status 'BOOKED'
```

## 4. Data flow: transferring an inmate

```
 warden ──CALL──► sp_transfer_inmate(inmate, target_block, reason)
                    │ SELECT ... FOR UPDATE INMATES row ; SELECT ... FOR UPDATE BLOCKS (target) row
                    │ checks: ACTIVE? same block? capacity (fn_block_occupancy)? security (fn_level_rank)? rival present?
                    │ pkg_prison_rules.g_transfer_reason := reason
                    │ UPDATE INMATES SET block_id ──fires──► trg_inmate_placement_rules (compound safety net)
                    │                             ──────► trg_log_movement  ─► INSERT MOVEMENTS + AUDIT_LOG 'TRANSFER'
                    ▼ COMMIT (or ROLLBACK TO SAVEPOINT on any problem → nothing partial remains)
```

## 5. Why these design decisions

| Decision | Reason |
|---|---|
| Oracle PL/SQL | The syllabus emphasises PL/SQL; Oracle Autonomous Database Always Free provides a managed cloud instance with the same syntax. |
| Denials logged with `PRAGMA AUTONOMOUS_TRANSACTION` | A trigger that raises an error rolls back its own transaction – including a normal audit insert. The autonomous log commits independently, so every refusal is kept. |
| Compound triggers for capacity and slot rules | A row trigger that counts its own table raises ORA-04091 (mutating table). A compound trigger collects keys per row and counts in `AFTER STATEMENT`. |
| Row locks in the procedures | Triggers only see committed data of other sessions, so two simultaneous bookings could both pass. Locking the inmate and slot rows (always in the same order, so no deadlock) serialises them. Demonstrated in `scripts/concurrency_demo.ps1`. |
| Procedures commit unless `p_auto_commit = 'N'` | Normal callers get one atomic unit of work; the two-session demo can keep the transaction open to hold locks. |
| Views instead of row-level-security policies | Same effect for F31 with no licensed option; users get privileges on views only. |
| Status codes instead of exceptions | F23: a clerk sees `DENIED_CONFLICT`, not `ORA-20103`. |
| AUDIT_LOG without foreign keys, append-only trigger | Audit rows must outlive and describe even records that never existed. |

## 6. Trigger and procedure interaction summary

| Event | Fires (in order) | Result |
|---|---|---|
| `INSERT INTO visits` | `trg_block_conflict_visit` → `trg_visit_slot_rules` (3 sections) → `trg_audit_visits` | booked + logged, or refused + denial logged |
| `UPDATE inmates SET block_id` | `trg_inmate_placement_rules` → `trg_log_movement` | movement + TRANSFER audit |
| `INSERT INTO inmates` | `trg_inmate_placement_rules`, `trg_log_movement` (admission), `trg_audit_inmates` | admission movement + INSERT audit |
| `UPDATE/DELETE audit_log` | `trg_audit_log_immutable` | always ORA-20301 |
| any change to INMATES / VISITORS / VISITS | `trg_audit_*` | old → new values in AUDIT_LOG |
| nightly 02:00 | `JOB_NIGHTLY_PRISON_MAINTENANCE` → `pr_nightly_job` → `pr_nightly_maintenance` | releases, missed visits, JOB audit row |

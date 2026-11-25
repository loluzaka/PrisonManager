# Legacy Oracle Testing Guide (F34)

**Last recorded run: 191 checks passed · 0 failed.** (Test run started 2026-11-04 00:01:02; raw output: `Documentation/Test_Results/latest_test_run.log`). Since that run, L01-L02 and the new role check R-FD-11 were added and are pending execution.

Every number in the tables below was copied from that log — nothing is hand-written. The database was Oracle Database 23ai Free in Docker; the cloud has **not** been tested (see section 5).

## 1. How to run

```powershell
.\scripts\start_local_db.ps1      # once
.\scripts\install.ps1 -Fresh       # build everything
.\scripts\run_tests.ps1            # re-seeds, runs all tests, saves the log
```

What `run_tests.ps1` does: re-seed (`04_seed_data.sql`) → role tests as five demo users (`tests/31_test_roles.sql`) → re-seed → main suite as the owner (`tests/30_test_suite.sql`) → concurrency demo (`scripts/concurrency_demo.ps1`). Exit code 1 if any check fails.

Single test files can be run by hand: `docker exec -i prison-oracle bash -c "cd /prison/tests && sqlplus -S prison_owner/<pwd>@//localhost:1521/FREEPDB1 @30_test_suite.sql"`.
UI smoke tests (not requiring a live Oracle instance) run with `ui\.venv\Scripts\python.exe -m unittest discover -s ui -p test_app.py`.

## 2. Mapping to the 20 required test areas

| # | Required test | Test IDs | Status |
|---|---|---|---|
| 1 | Successful visitor registration | D01, D02, R-AD-2 | automated – PASS |
| 2 | Successful visit booking | D05, D06, D18, D20, E05, R-FD-9 | automated – PASS |
| 3 | Blacklisted visitor denied and logged | D07, D08, D22, D23, R-FD-10 | automated – PASS |
| 4 | Unapproved visitor denied | D09, D24 | automated – PASS |
| 5 | Conflicting visitor denied | D10, D25, E02 | automated – PASS |
| 6 | Inactive inmate denied | D11, D26 | automated – PASS |
| 7 | Duplicate visit slot rejected | D12 | automated – PASS |
| 8 | Full block rejects a transfer | F07, F18, F21 | automated – PASS |
| 9 | Insufficient security level rejects a transfer | F10, F19 | automated – PASS |
| 10 | Successful transfer records MOVEMENTS | F01–F04, F16, F17, F23 | automated – PASS |
| 11 | Successful transfer creates AUDIT_LOG entries | F05, G05, G06 | automated – PASS |
| 12 | Invalid foreign-key references rejected | B06, B08, B09 | automated – PASS |
| 13 | Transaction rollback leaves no partial records | F08, F09, K01, K02 | automated – PASS |
| 14 | Audit log cannot be modified by ordinary users | G01–G03, R-AUDIT-1..3 (5 roles), R-AU-2 | automated – PASS |
| 15 | Cursor reports process multiple records | H01–H08 | automated – PASS |
| 16 | Functions return correct results | C01–C18 | automated – PASS |
| 17 | Procedures return correct status codes | D01–D21, E01–E15, F01–F15 | automated – PASS |
| 18 | Concurrent booking preserves integrity | X01 (shows the problem), X02 (shows the fix) | automated – PASS |
| 19 | Cloud database connection succeeds | — | **NOT RUN – pending manual step** (needs a cloud account; see `Cloud_Setup.md` section 5) |
| 20 | Backup and restore can be demonstrated | J01, J02 (local Flashback Table recovery) | local equivalent PASS; **cloud backup/restore NOT RUN – pending** |

Additional regression added since the recorded run: **R-FD-11** verifies the front desk cannot book visits for an inmate assigned to another facility. It is pending execution.

## 3. Complete results

| Test ID | Purpose | Expected | Actual | Result |
|---|---|---|---|---|
| R-AUDIT-1 | PRISON_U_FRONTDESK: cannot UPDATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-2 | PRISON_U_FRONTDESK: cannot DELETE from audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-3 | PRISON_U_FRONTDESK: cannot TRUNCATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-FD-1 | PRISON_U_FRONTDESK: cannot read the INMATES table | `DENIED` | `DENIED` | ✅ PASS |
| R-FD-2 | PRISON_U_FRONTDESK: cannot read raw VISITORS (full ID numbers) | `DENIED` | `DENIED` | ✅ PASS |
| R-FD-3 | PRISON_U_FRONTDESK: cannot DELETE visits directly | `DENIED` | `DENIED` | ✅ PASS |
| R-FD-4 | PRISON_U_FRONTDESK: cannot INSERT into VISITS directly (procedure only) | `DENIED` | `DENIED` | ✅ PASS |
| R-FD-5 | PRISON_U_FRONTDESK: cannot read the audit log | `DENIED` | `DENIED` | ✅ PASS |
| R-FD-6 | PRISON_U_FRONTDESK: cannot call sp_transfer_inmate | `DENIED` | `DENIED` | ✅ PASS |
| R-FD-7 | PRISON_U_FRONTDESK: CAN read masked visitors | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-FD-8 | PRISON_U_FRONTDESK: masked view hides all but 4 characters | `****7919` | `****7919` | ✅ PASS |
| R-FD-9 | PRISON_U_FRONTDESK: CAN book a visit through sp_schedule_visit (definer rights) | `BOOKED` | `BOOKED` | ✅ PASS |
| R-FD-10 | PRISON_U_FRONTDESK: procedure still refuses a blacklisted visitor | `DENIED_BLACKLISTED` | `DENIED_BLACKLISTED` | ✅ PASS |
| R-AUDIT-1 | PRISON_U_AUDITOR: cannot UPDATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-2 | PRISON_U_AUDITOR: cannot DELETE from audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-3 | PRISON_U_AUDITOR: cannot TRUNCATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AU-1 | PRISON_U_AUDITOR: CAN read the audit log | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-AU-2 | PRISON_U_AUDITOR: cannot INSERT into the audit log | `DENIED` | `DENIED` | ✅ PASS |
| R-AU-3 | PRISON_U_AUDITOR: cannot change inmates | `DENIED` | `DENIED` | ✅ PASS |
| R-AU-4 | PRISON_U_AUDITOR: cannot book visits | `DENIED` | `DENIED` | ✅ PASS |
| R-AU-5 | PRISON_U_AUDITOR: CAN read report views | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-AU-6 | PRISON_U_AUDITOR: cannot read raw visitors | `DENIED` | `DENIED` | ✅ PASS |
| R-AU-7 | PRISON_U_AUDITOR: auditor sees every facility (STAFF_ACCESS facility_id NULL) | `50` | `50` | ✅ PASS |
| R-AUDIT-1 | PRISON_U_WARDEN: cannot UPDATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-2 | PRISON_U_WARDEN: cannot DELETE from audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-3 | PRISON_U_WARDEN: cannot TRUNCATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-1 | PRISON_U_WARDEN: CAN update inmates | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-WA-2 | PRISON_U_WARDEN: cannot DELETE inmates | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-3 | PRISON_U_WARDEN: cannot touch visitors | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-4 | PRISON_U_WARDEN: cannot call sp_schedule_visit (front desk duty) | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-5 | PRISON_U_WARDEN: CAN read movement history | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-WA-6 | PRISON_U_WARDEN: facility-scoped view shows only the warden's own facility | `33` | `33` | ✅ PASS |
| R-WA-7 | PRISON_U_WARDEN: facility-scoped blocks | `3` | `3` | ✅ PASS |
| R-AUDIT-1 | PRISON_U_WARDEN2: cannot UPDATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-2 | PRISON_U_WARDEN2: cannot DELETE from audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-3 | PRISON_U_WARDEN2: cannot TRUNCATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-1 | PRISON_U_WARDEN2: CAN update inmates | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-WA-2 | PRISON_U_WARDEN2: cannot DELETE inmates | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-3 | PRISON_U_WARDEN2: cannot touch visitors | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-4 | PRISON_U_WARDEN2: cannot call sp_schedule_visit (front desk duty) | `DENIED` | `DENIED` | ✅ PASS |
| R-WA-5 | PRISON_U_WARDEN2: CAN read movement history | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-WA-6 | PRISON_U_WARDEN2: facility-scoped view shows only the warden's own facility | `17` | `17` | ✅ PASS |
| R-WA-7 | PRISON_U_WARDEN2: facility-scoped blocks | `2` | `2` | ✅ PASS |
| R-AUDIT-1 | PRISON_U_ADMIN: cannot UPDATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-2 | PRISON_U_ADMIN: cannot DELETE from audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AUDIT-3 | PRISON_U_ADMIN: cannot TRUNCATE audit_log | `DENIED` | `DENIED` | ✅ PASS |
| R-AD-1 | PRISON_U_ADMIN: CAN read and change visitors | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-AD-2 | PRISON_U_ADMIN: CAN call sp_register_visitor | `ALLOWED` | `ALLOWED` | ✅ PASS |
| R-AD-3 | PRISON_U_ADMIN: admin sees both facilities | `50` | `50` | ✅ PASS |
| R-AD-4 | PRISON_U_ADMIN: admin is still refused by the audit trigger / has no UPDATE right | `DENIED` | `DENIED` | ✅ PASS |
| R-AD-5 | PRISON_U_ADMIN: admin cannot DROP a table (no DDL privilege) | `DENIED` | `DENIED` | ✅ PASS |
| A01 | all 11 tables exist (7 core + 4 supporting) | `11` | `11` | ✅ PASS |
| A02 | every table has a PRIMARY KEY | `11` | `11` | ✅ PASS |
| A03 | FOREIGN KEY constraints present | `12` | `12` | ✅ PASS |
| A04 | named CHECK constraints present | `19` | `19` | ✅ PASS |
| A04b | UNIQUE constraints present | `7` | `7` | ✅ PASS |
| A05 | triggers installed (>=8) | `TRUE` | `TRUE` | ✅ PASS |
| A06 | performance indexes created (F5) | `10` | `10` | ✅ PASS |
| A07 | views created (F6) | `17` | `17` | ✅ PASS |
| A08 | seed: inmates | `50` | `50` | ✅ PASS |
| A09 | seed: visitors | `40` | `40` | ✅ PASS |
| A10 | seed: visits | `100` | `100` | ✅ PASS |
| A11 | seed: blocks | `5` | `5` | ✅ PASS |
| A12 | seed: conflicts | `8` | `8` | ✅ PASS |
| A13 | seed: movements | `58` | `58` | ✅ PASS |
| B01 | CHECK: block capacity must be > 0 (ORA-02290) | `-2290` | `-2290` | ✅ PASS |
| B02 | CHECK: security_level list (ORA-02290) | `-2290` | `-2290` | ✅ PASS |
| B03 | CHECK: sentence_end > sentence_start (ORA-02290) | `-2290` | `-2290` | ✅ PASS |
| B04 | UNIQUE: duplicate (id_proof_type, id_proof_number) (ORA-00001) | `-1` | `-1` | ✅ PASS |
| B05 | NOT NULL: visitor name required (ORA-01400) | `-1400` | `-1400` | ✅ PASS |
| B06 | FOREIGN KEY: unknown inmate in a visit (ORA-02291) | `-2291` | `-2291` | ✅ PASS |
| B07 | CHECK: slot must be one of the fixed slots (ORA-02290) | `-2290` | `-2290` | ✅ PASS |
| B08 | RESTRICT: inmate with history cannot be deleted (ORA-02292) | `-2292` | `-2292` | ✅ PASS |
| B09 | RESTRICT: block with inmates cannot be deleted (ORA-02292) | `-2292` | `-2292` | ✅ PASS |
| B10 | CHECK: rivalry stored once, smaller id first (ORA-02290) | `-2290` | `-2290` | ✅ PASS |
| C01 | fn_inmate_visit_count equals a hand-written COUNT | `2` | `2` | ✅ PASS |
| C02 | fn_visitor_visit_count equals a hand-written COUNT | `2` | `2` | ✅ PASS |
| C03 | fn_block_occupancy(E-Block) = 6 active inmates | `6` | `6` | ✅ PASS |
| C04 | fn_block_occupancy ignores RELEASED / TRANSFERRED (A-Block = 12 active of 14 rows) | `12` | `12` | ✅ PASS |
| C05 | fn_days_remaining for inmate due in 8 days (inmate 3) | `8` | `8` | ✅ PASS |
| C06 | fn_days_remaining of unknown inmate is NULL | `NULL` | `NULL` | ✅ PASS |
| C07 | fn_days_remaining of a released inmate is 0 | `0` | `0` | ✅ PASS |
| C08 | fn_is_visitor_eligible: approved visitor, active inmate | `ELIGIBLE` | `ELIGIBLE` | ✅ PASS |
| C09 | fn_is_visitor_eligible: blacklisted | `BLACKLISTED` | `BLACKLISTED` | ✅ PASS |
| C10 | fn_is_visitor_eligible: pending = unapproved | `UNAPPROVED` | `UNAPPROVED` | ✅ PASS |
| C11 | fn_is_visitor_eligible: active conflict | `CONFLICT` | `CONFLICT` | ✅ PASS |
| C12 | fn_is_visitor_eligible: RESOLVED conflict does not block | `ELIGIBLE` | `ELIGIBLE` | ✅ PASS |
| C13 | fn_is_visitor_eligible: EXPIRED conflict does not block | `ELIGIBLE` | `ELIGIBLE` | ✅ PASS |
| C14 | fn_is_visitor_eligible: inmate not active | `INMATE_INACTIVE` | `INMATE_INACTIVE` | ✅ PASS |
| C15 | fn_is_visitor_eligible: unknown visitor | `NO_VISITOR` | `NO_VISITOR` | ✅ PASS |
| C16 | fn_level_rank orders LOW < MEDIUM < HIGH | `1,2,3` | `1,2,3` | ✅ PASS |
| C17 | fn_next_free_slot on an empty day is the first slot | `09:00-10:00` | `09:00-10:00` | ✅ PASS |
| C18 | functions can be used inside a SELECT over all inmates | `50` | `50` | ✅ PASS |
| D01 | sp_register_visitor registers a new visitor | `REGISTERED` | `REGISTERED` | ✅ PASS |
| D02 | new visitor starts as PENDING (DEFAULT) | `PENDING` | `PENDING` | ✅ PASS |
| D03 | duplicate ID proof returns DUPLICATE_ID (no raw ORA error) | `DUPLICATE_ID` | `DUPLICATE_ID` | ✅ PASS |
| D04 | invalid ID type returns INVALID_DATA | `INVALID_DATA` | `INVALID_DATA` | ✅ PASS |
| D05 | sp_schedule_visit books an eligible visit | `BOOKED` | `BOOKED` | ✅ PASS |
| D06 | allowed visit is written to AUDIT_LOG (VISIT_BOOKED) | `1` | `1` | ✅ PASS |
| D07 | blacklisted visitor is denied | `DENIED_BLACKLISTED` | `DENIED_BLACKLISTED` | ✅ PASS |
| D08 | blacklisted attempt is logged as VISIT_DENIED | `3` | `3` | ✅ PASS |
| D09 | unapproved (PENDING) visitor is denied | `DENIED_UNAPPROVED` | `DENIED_UNAPPROVED` | ✅ PASS |
| D10 | visitor with a conflict is denied | `DENIED_CONFLICT` | `DENIED_CONFLICT` | ✅ PASS |
| D11 | inactive (TRANSFERRED) inmate is denied | `DENIED_INMATE_INACTIVE` | `DENIED_INMATE_INACTIVE` | ✅ PASS |
| D12 | same inmate/date/slot twice is denied (duplicate) | `DENIED_DUPLICATE` | `DENIED_DUPLICATE` | ✅ PASS |
| D13 | booking in the past is denied | `DENIED_PAST_DATE` | `DENIED_PAST_DATE` | ✅ PASS |
| D14 | unknown slot is denied | `DENIED_INVALID_SLOT` | `DENIED_INVALID_SLOT` | ✅ PASS |
| D15 | unknown inmate is denied (NOT an ORA error) | `DENIED_NO_INMATE` | `DENIED_NO_INMATE` | ✅ PASS |
| D16 | unknown visitor is denied (NOT an ORA error) | `DENIED_NO_VISITOR` | `DENIED_NO_VISITOR` | ✅ PASS |
| D17 | date after the inmate's release is denied (inmate 14 leaves in 19 days) | `DENIED_OUTSIDE_SENTENCE` | `DENIED_OUTSIDE_SENTENCE` | ✅ PASS |
| D18 | three visits in one week are accepted (last status) | `BOOKED` | `BOOKED` | ✅ PASS |
| D19 | fourth visit in the same week is denied | `DENIED_WEEKLY_LIMIT` | `DENIED_WEEKLY_LIMIT` | ✅ PASS |
| D20 | fifth booking in a 5-place slot succeeds (last status) | `BOOKED` | `BOOKED` | ✅ PASS |
| D21 | sixth booking in the slot returns SLOT_FULL | `SLOT_FULL` | `SLOT_FULL` | ✅ PASS |
| D22 | trigger refuses a blacklisted visitor on a direct INSERT (ORA-20102) | `-20102` | `-20102` | ✅ PASS |
| D23 | denial survives the ROLLBACK (autonomous transaction) | `2` | `2` | ✅ PASS |
| D24 | trigger refuses an unapproved visitor (ORA-20101) | `-20101` | `-20101` | ✅ PASS |
| D25 | trigger refuses a conflicting visitor (ORA-20103) | `-20103` | `-20103` | ✅ PASS |
| D26 | trigger refuses a non-ACTIVE inmate (ORA-20104) | `-20104` | `-20104` | ✅ PASS |
| D27 | compound trigger enforces the weekly limit on a direct INSERT (ORA-20105) | `-20105` | `-20105` | ✅ PASS |
| D28 | compound trigger enforces slot capacity on a direct INSERT (ORA-20106) | `-20106` | `-20106` | ✅ PASS |
| D29 | trigger enforces the sentence period on a direct INSERT (ORA-20107) | `-20107` | `-20107` | ✅ PASS |
| E01 | sp_add_conflict records a new conflict | `CONFLICT_ADDED` | `CONFLICT_ADDED` | ✅ PASS |
| E02 | the new conflict immediately blocks booking | `DENIED_CONFLICT` | `DENIED_CONFLICT` | ✅ PASS |
| E03 | sp_resolve_conflict resolves it | `RESOLVED` | `RESOLVED` | ✅ PASS |
| E04 | resolving twice reports ALREADY_RESOLVED | `ALREADY_RESOLVED` | `ALREADY_RESOLVED` | ✅ PASS |
| E05 | after resolution the visit can be booked | `BOOKED` | `BOOKED` | ✅ PASS |
| E06 | re-flagging a resolved pair re-activates it | `CONFLICT_REACTIVATED` | `CONFLICT_REACTIVATED` | ✅ PASS |
| E07 | adding a conflict cancels that pair's future visit | `CANCELLED` | `CANCELLED` | ✅ PASS |
| E08 | resolving an unknown conflict returns NOT_FOUND | `NOT_FOUND` | `NOT_FOUND` | ✅ PASS |
| E09 | conflict for unknown inmate returns NOT_FOUND | `NOT_FOUND` | `NOT_FOUND` | ✅ PASS |
| E10 | sp_set_visitor_status blacklists a visitor | `UPDATED` | `UPDATED` | ✅ PASS |
| E11 | blacklisting cancels the visitor's future visits | `CANCELLED` | `CANCELLED` | ✅ PASS |
| E12 | unknown visitor returns NOT_FOUND | `NOT_FOUND` | `NOT_FOUND` | ✅ PASS |
| E13 | invalid status returns INVALID_DATA | `INVALID_DATA` | `INVALID_DATA` | ✅ PASS |
| E14 | sp_add_inmate_rivalry stores a pair (larger id given first) | `RIVALRY_ADDED` | `RIVALRY_ADDED` | ✅ PASS |
| E15 | same rivalry twice returns ALREADY_EXISTS | `ALREADY_EXISTS` | `ALREADY_EXISTS` | ✅ PASS |
| F01 | sp_transfer_inmate moves an inmate to a block with room | `TRANSFERRED` | `TRANSFERRED` | ✅ PASS |
| F02 | INMATES.block_id was updated | `4` | `4` | ✅ PASS |
| F03 | successful transfer wrote a MOVEMENTS row (by trg_log_movement) | `2` | `2` | ✅ PASS |
| F04 | MOVEMENTS row carries the reason passed to the procedure | `Test: rehousing to D-Block` | `Test: rehousing to D-Block` | ✅ PASS |
| F05 | successful transfer wrote an AUDIT_LOG TRANSFER row | `1` | `1` | ✅ PASS |
| F06 | D-Block is now exactly full | `10` | `10` | ✅ PASS |
| F07 | full block rejects a transfer | `BLOCK_FULL` | `BLOCK_FULL` | ✅ PASS |
| F08 | rejected transfer left the inmate where he was | `1` | `1` | ✅ PASS |
| F09 | rejected transfer left NO partial MOVEMENTS row (rollback) | `59` | `59` | ✅ PASS |
| F10 | insufficient security level rejects a transfer | `SECURITY_MISMATCH` | `SECURITY_MISMATCH` | ✅ PASS |
| F11 | moving next to a rival is rejected | `RIVAL_IN_BLOCK` | `RIVAL_IN_BLOCK` | ✅ PASS |
| F12 | unknown inmate returns NOT_FOUND | `NOT_FOUND` | `NOT_FOUND` | ✅ PASS |
| F13 | unknown block returns BLOCK_NOT_FOUND | `BLOCK_NOT_FOUND` | `BLOCK_NOT_FOUND` | ✅ PASS |
| F14 | a TRANSFERRED (non-active) inmate cannot be moved | `INMATE_NOT_ACTIVE` | `INMATE_NOT_ACTIVE` | ✅ PASS |
| F15 | moving to the block the inmate is already in returns SAME_BLOCK | `SAME_BLOCK` | `SAME_BLOCK` | ✅ PASS |
| F16 | direct UPDATE of block_id is still logged by trg_log_movement | `2` | `2` | ✅ PASS |
| F17 | direct update gets the default reason text | `Direct update of INMATES.block_id` | `Direct update of INMATES.block_id` | ✅ PASS |
| F18 | compound trigger blocks a direct move into a full block (ORA-20201) | `-20201` | `-20201` | ✅ PASS |
| F19 | trigger blocks risk above block security on direct UPDATE (ORA-20202) | `-20202` | `-20202` | ✅ PASS |
| F20 | trigger blocks housing a rival in the same block (ORA-20203) | `-20203` | `-20203` | ✅ PASS |
| F21 | admitting a new inmate into the full E-Block is refused (ORA-20201) | `-20201` | `-20201` | ✅ PASS |
| F22 | admitting a HIGH-risk inmate into C-Block (one free bed) works | `0` | `0` | ✅ PASS |
| F23 | admission INSERT created an ADMISSION movement | `1` | `1` | ✅ PASS |
| G01 | UPDATE of an audit row is refused (ORA-20301) | `-20301` | `-20301` | ✅ PASS |
| G02 | DELETE of an audit row is refused (ORA-20301) | `-20301` | `-20301` | ✅ PASS |
| G03 | mass DELETE of the audit log is refused (ORA-20301) | `-20301` | `-20301` | ✅ PASS |
| G04 | audit log still holds rows after the tamper attempts | `TRUE` | `TRUE` | ✅ PASS |
| G05 | UPDATE trigger records old and new values | `1` | `1` | ✅ PASS |
| G06 | inmate change is audited (risk_level LOW -> MEDIUM) | `1` | `1` | ✅ PASS |
| H01 | c_daily_roster fetched every visit of today (%ROWCOUNT) | `8` | `8` | ✅ PASS |
| H02 | c_daily_roster grouped the rows under 3 or more block headings | `TRUE` | `TRUE` | ✅ PASS |
| H03 | c_daily_roster processed MULTIPLE records (>= 5) | `TRUE` | `TRUE` | ✅ PASS |
| H04 | c_daily_roster handles an empty result set (%ROWCOUNT = 0) | `1` | `1` | ✅ PASS |
| H05 | c_block_occupancy listed all 5 blocks | `5` | `5` | ✅ PASS |
| H06 | c_block_occupancy flagged the full E-Block as AT CAPACITY | `1` | `1` | ✅ PASS |
| H07 | c_upcoming_release (cursor FOR loop) lists releases within 30 days | `3` | `3` | ✅ PASS |
| H08 | upcoming releases returned more than one inmate | `TRUE` | `TRUE` | ✅ PASS |
| I01 | v_block_occupancy flags E-Block | `AT CAPACITY` | `AT CAPACITY` | ✅ PASS |
| I02 | v_block_occupancy percentage for a full block | `100` | `100` | ✅ PASS |
| I03 | v_visitors_masked shows only the last four characters | `****7919` | `****7919` | ✅ PASS |
| I04 | v_denied_attempts parses reasons from the audit log (>= 4) | `TRUE` | `TRUE` | ✅ PASS |
| I05 | v_active_inmates shows only ACTIVE inmates (45 + test admissions rolled back) | `45` | `45` | ✅ PASS |
| I06 | v_todays_visits lists today's visits | `8` | `8` | ✅ PASS |
| I07 | v_inmate_conflicts separates ACTIVE from RESOLVED/EXPIRED (6 seed + 1 from section E) | `7` | `7` | ✅ PASS |
| I08 | nightly job releases an inmate whose sentence ended (WHERE CURRENT OF) | `RELEASED` | `RELEASED` | ✅ PASS |
| I09 | nightly job marks a past SCHEDULED visit as MISSED | `1` | `1` | ✅ PASS |
| I10 | nightly job wrote exactly one new JOB audit row | `1` | `1` | ✅ PASS |
| I11 | DBMS_SCHEDULER job exists and is enabled | `1` | `1` | ✅ PASS |
| J01 | accidental DELETE removed all 20 test rows | `0` | `0` | ✅ PASS |
| J02 | FLASHBACK TABLE restored the 20 rows | `20` | `20` | ✅ PASS |
| K01 | ROLLBACK TO SAVEPOINT undoes only the later insert | `1` | `1` | ✅ PASS |
| K02 | ROLLBACK leaves no partial data | `0` | `0` | ✅ PASS |
| X01 | without locking two clerks overbook the last place (demonstrates the problem) | `6 visits in a 5-place slot` | `6 visits` | ✅ PASS |
| X02 | sp_schedule_visit row locks keep the slot at its capacity | `5 visits in a 5-place slot` | `5 visits` | ✅ PASS |

Input/SQL for each ID is the statement on the line of that ID in `tests/30_test_suite.sql` (IDs A–K), `tests/31_test_roles.sql` (IDs R-*) and `sql/20`/`21` + `scripts/concurrency_demo.ps1` (IDs X*).

## 4. How the concurrency test works (F24)

Slot 16:00-17:00 on day +21 holds 5 visits; four are booked first, so one place is left. Two SQL*Plus sessions (clerk A and clerk B, B starts 2 s later) try to take it.

| Mode | What the clerks do | Real result in this run |
|---|---|---|
| NAIVE | read the count (4), insert, wait 6 s, commit — no lock | **6 visits in a 5-place slot** (both commits succeed because the trigger cannot see the other session's uncommitted row) |
| SAFE | `sp_schedule_visit(..., p_auto_commit => 'N')` locks the inmate row and slot row | clerk A `BOOKED`; clerk B blocked ~4 s, then `SLOT_FULL`; **5 visits** |

Run it with commentary: `.\scripts\concurrency_demo.ps1`.

## 5. Known limitations and honest gaps

* **Cloud (tests 19 and the cloud half of 20): not executed.** No cloud account was available. The local Oracle container is the same engine; `Cloud_Setup.md` lists the manual steps and evidence to capture.
* The test suite re-seeds the database; it is meant for the lab database, not for production data.
* Role tests treat ORA-00942, ORA-01031 and ORA-41900 (Oracle 23ai "missing privilege") as *DENIED*.
* `TRUNCATE`/`DROP` of `AUDIT_LOG` by the schema owner is possible (DDL cannot be blocked by a DML trigger); no role is ever granted those rights (tests R-AUDIT-3).
* Rebooking a cancelled slot is refused as a duplicate because `UQ_VISITS_INMATE_SLOT` covers cancelled rows too.
* utPLSQL was not used; the suite is plain PL/SQL with a tiny assertion package that is created and dropped by the test script.
* The scheduler job is created and enabled (test I11) but its 02:00 firing was not waited for; its body is tested directly (I08–I10).

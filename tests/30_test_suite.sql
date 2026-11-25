-- =============================================================================
-- 30_test_suite.sql
-- Feature : F34 (test suite - positive and negative cases)
-- Owner   : Member 3
-- RUN AS  : PRISON_OWNER, on a FRESHLY SEEDED database (scripts\run_tests.ps1 re-seeds first)
--
-- Output: one line per test   TEST|<id>|<purpose>|<expected>|<actual>|<PASS or FAIL>
-- Tests that need a second login (roles) are in 31_test_roles.sql; the two-session concurrency
-- test is scripts\concurrency_demo.ps1; cloud connection / backup tests are manual (see
-- Documentation/Testing_Guide.md).
-- All fixtures use far-future dates and rows of the seed data (see 04_seed_data.sql).
-- =============================================================================
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 250
SET TRIMOUT ON

CREATE OR REPLACE PACKAGE pkg_test AS
  g_pass PLS_INTEGER := 0;
  g_fail PLS_INTEGER := 0;
  PROCEDURE chk (p_id VARCHAR2, p_purpose VARCHAR2, p_expected VARCHAR2, p_actual VARCHAR2);
  FUNCTION  try_sql (p_sql VARCHAR2) RETURN NUMBER;        -- 0 = success, else SQLCODE
  PROCEDURE summary;
END pkg_test;
/
CREATE OR REPLACE PACKAGE BODY pkg_test AS
  PROCEDURE chk (p_id VARCHAR2, p_purpose VARCHAR2, p_expected VARCHAR2, p_actual VARCHAR2) IS
    v_ok BOOLEAN := (p_expected = p_actual) OR (p_expected IS NULL AND p_actual IS NULL);
  BEGIN
    IF v_ok THEN g_pass := g_pass + 1; ELSE g_fail := g_fail + 1; END IF;
    DBMS_OUTPUT.PUT_LINE('TEST|' || p_id || '|' || p_purpose || '|' || p_expected || '|' || p_actual || '|' ||
                         CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);
  END chk;
  FUNCTION try_sql (p_sql VARCHAR2) RETURN NUMBER IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    RETURN 0;
  EXCEPTION WHEN OTHERS THEN RETURN SQLCODE;
  END try_sql;
  PROCEDURE summary IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('SUMMARY|passed=' || g_pass || '|failed=' || g_fail || '|total=' || (g_pass + g_fail));
  END summary;
END pkg_test;
/

-- ============================================================ A. structure and seed data
DECLARE
  v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables
   WHERE table_name IN ('BLOCKS','INMATES','VISITORS','VISITS','MOVEMENTS','CONFLICTS','AUDIT_LOG',
                        'FACILITIES','INMATE_CONFLICTS','VISIT_SLOTS','STAFF_ACCESS');
  pkg_test.chk('A01', 'all 11 tables exist (7 core + 4 supporting)', '11', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM user_constraints WHERE constraint_type = 'P';
  pkg_test.chk('A02', 'every table has a PRIMARY KEY', '11', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM user_constraints WHERE constraint_type = 'R';
  pkg_test.chk('A03', 'FOREIGN KEY constraints present', '12', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM user_constraints WHERE constraint_type = 'C' AND constraint_name LIKE 'CK\_%' ESCAPE '\';
  pkg_test.chk('A04', 'named CHECK constraints present', '19', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM user_constraints WHERE constraint_type = 'U';
  pkg_test.chk('A04b', 'UNIQUE constraints present', '7', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM user_triggers;
  pkg_test.chk('A05', 'triggers installed (>=8)', 'TRUE', CASE WHEN v >= 8 THEN 'TRUE' ELSE 'FALSE' END);
  SELECT COUNT(*) INTO v FROM user_indexes WHERE index_name LIKE 'IDX\_%' ESCAPE '\';
  pkg_test.chk('A06', 'performance indexes created (F5)', '10', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM user_objects WHERE object_type = 'VIEW';
  pkg_test.chk('A07', 'views created (F6)', '17', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM inmates;     pkg_test.chk('A08', 'seed: inmates',   '50',  TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM visitors;    pkg_test.chk('A09', 'seed: visitors',  '40',  TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM visits;      pkg_test.chk('A10', 'seed: visits',    '100', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM blocks;      pkg_test.chk('A11', 'seed: blocks',    '5',   TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM conflicts;   pkg_test.chk('A12', 'seed: conflicts', '8',   TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM movements;   pkg_test.chk('A13', 'seed: movements', '58',  TO_CHAR(v));
END;
/

-- ============================================================ B. integrity constraints (negative tests)
DECLARE
  v NUMBER;
BEGIN
  v := pkg_test.try_sql('INSERT INTO blocks (block_name, capacity, security_level, facility_id) VALUES (''T'', -1, ''LOW'', 1)');
  pkg_test.chk('B01', 'CHECK: block capacity must be > 0 (ORA-02290)', '-2290', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO blocks (block_name, capacity, security_level, facility_id) VALUES (''T'', 5, ''EXTREME'', 1)');
  pkg_test.chk('B02', 'CHECK: security_level list (ORA-02290)', '-2290', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO inmates (inmate_no, full_name, date_of_birth, sentence_start, sentence_end, block_id) ' ||
                        'VALUES (''T1'', ''T'', DATE ''1990-01-01'', DATE ''2030-01-01'', DATE ''2029-01-01'', 1)');
  pkg_test.chk('B03', 'CHECK: sentence_end > sentence_start (ORA-02290)', '-2290', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES (''T'', ''NATIONAL_ID'', ''SYN-' ||
                        LPAD(MOD(1 * 7919, 1000000), 6, '0') || ''')');
  pkg_test.chk('B04', 'UNIQUE: duplicate (id_proof_type, id_proof_number) (ORA-00001)', '-1', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visitors (id_proof_type, id_proof_number) VALUES (''PASSPORT'', ''SYN-NN'')');
  pkg_test.chk('B05', 'NOT NULL: visitor name required (ORA-01400)', '-1400', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (9999, 1, TRUNC(SYSDATE)+90, ''09:00-10:00'')');
  pkg_test.chk('B06', 'FOREIGN KEY: unknown inmate in a visit (ORA-02291)', '-2291', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (12, 1, TRUNC(SYSDATE)+90, ''23:00-24:00'')');
  pkg_test.chk('B07', 'CHECK: slot must be one of the fixed slots (ORA-02290)', '-2290', TO_CHAR(v));
  v := pkg_test.try_sql('DELETE FROM inmates WHERE inmate_id = 1');
  pkg_test.chk('B08', 'RESTRICT: inmate with history cannot be deleted (ORA-02292)', '-2292', TO_CHAR(v));
  v := pkg_test.try_sql('DELETE FROM blocks WHERE block_id = 1');
  pkg_test.chk('B09', 'RESTRICT: block with inmates cannot be deleted (ORA-02292)', '-2292', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO inmate_conflicts (inmate_a, inmate_b, reason) VALUES (9, 5, ''RIVAL'')');
  pkg_test.chk('B10', 'CHECK: rivalry stored once, smaller id first (ORA-02290)', '-2290', TO_CHAR(v));
  ROLLBACK;
END;
/

-- ============================================================ C. functions
DECLARE
  v NUMBER; s VARCHAR2(40);
BEGIN
  SELECT COUNT(*) INTO v FROM visits WHERE inmate_id = 12 AND status IN ('SCHEDULED','COMPLETED');
  pkg_test.chk('C01', 'fn_inmate_visit_count equals a hand-written COUNT', TO_CHAR(v), TO_CHAR(fn_inmate_visit_count(12)));
  SELECT COUNT(*) INTO v FROM visits WHERE visitor_id = 1 AND status IN ('SCHEDULED','COMPLETED');
  pkg_test.chk('C02', 'fn_visitor_visit_count equals a hand-written COUNT', TO_CHAR(v), TO_CHAR(fn_visitor_visit_count(1)));
  pkg_test.chk('C03', 'fn_block_occupancy(E-Block) = 6 active inmates', '6', TO_CHAR(fn_block_occupancy(5)));
  pkg_test.chk('C04', 'fn_block_occupancy ignores RELEASED / TRANSFERRED (A-Block = 12 active of 14 rows)', '12', TO_CHAR(fn_block_occupancy(1)));
  pkg_test.chk('C05', 'fn_days_remaining for inmate due in 8 days (inmate 3)', '8', TO_CHAR(fn_days_remaining(3)));
  pkg_test.chk('C06', 'fn_days_remaining of unknown inmate is NULL', 'NULL', NVL(TO_CHAR(fn_days_remaining(9999)), 'NULL'));
  pkg_test.chk('C07', 'fn_days_remaining of a released inmate is 0', '0', TO_CHAR(fn_days_remaining(48)));
  pkg_test.chk('C08', 'fn_is_visitor_eligible: approved visitor, active inmate', 'ELIGIBLE', fn_is_visitor_eligible(1, 12));
  pkg_test.chk('C09', 'fn_is_visitor_eligible: blacklisted', 'BLACKLISTED', fn_is_visitor_eligible(36, 12));
  pkg_test.chk('C10', 'fn_is_visitor_eligible: pending = unapproved', 'UNAPPROVED', fn_is_visitor_eligible(31, 12));
  pkg_test.chk('C11', 'fn_is_visitor_eligible: active conflict', 'CONFLICT', fn_is_visitor_eligible(5, 3));
  pkg_test.chk('C12', 'fn_is_visitor_eligible: RESOLVED conflict does not block', 'ELIGIBLE', fn_is_visitor_eligible(2, 1));
  pkg_test.chk('C13', 'fn_is_visitor_eligible: EXPIRED conflict does not block', 'ELIGIBLE', fn_is_visitor_eligible(4, 10));
  pkg_test.chk('C14', 'fn_is_visitor_eligible: inmate not active', 'INMATE_INACTIVE', fn_is_visitor_eligible(1, 46));
  pkg_test.chk('C15', 'fn_is_visitor_eligible: unknown visitor', 'NO_VISITOR', fn_is_visitor_eligible(9999, 12));
  pkg_test.chk('C16', 'fn_level_rank orders LOW < MEDIUM < HIGH', '1,2,3', fn_level_rank('LOW') || ',' || fn_level_rank('MEDIUM') || ',' || fn_level_rank('HIGH'));
  s := fn_next_free_slot(12, TRUNC(SYSDATE) + 200);
  pkg_test.chk('C17', 'fn_next_free_slot on an empty day is the first slot', '09:00-10:00', s);
  SELECT COUNT(*) INTO v FROM (SELECT fn_inmate_visit_count(inmate_id) FROM inmates);
  pkg_test.chk('C18', 'functions can be used inside a SELECT over all inmates', '50', TO_CHAR(v));
END;
/

-- ============================================================ D. visit booking: procedure, trigger, audit
DECLARE
  st VARCHAR2(40); vid NUMBER; msg VARCHAR2(400);
  v NUMBER; v_before NUMBER; v_after NUMBER;
  d_far   DATE := TRUNC(SYSDATE) + 40;
  d_week  DATE := TRUNC(SYSDATE + 50, 'IW');         -- Monday of a week ~50 days away
  d_full  DATE := TRUNC(SYSDATE) + 60;
BEGIN
  -- visitor registration
  DECLARE new_id NUMBER; BEGIN
    sp_register_visitor('  test visitor  ', 'passport', 'SYN-T-0001', '+00-555-7001', new_id, st, msg);
    pkg_test.chk('D01', 'sp_register_visitor registers a new visitor', 'REGISTERED', st);
    SELECT approval_status INTO msg FROM visitors WHERE visitor_id = new_id;
    pkg_test.chk('D02', 'new visitor starts as PENDING (DEFAULT)', 'PENDING', msg);
    sp_register_visitor('Other', 'PASSPORT', 'SYN-T-0001', NULL, new_id, st, msg);
    pkg_test.chk('D03', 'duplicate ID proof returns DUPLICATE_ID (no raw ORA error)', 'DUPLICATE_ID', st);
    sp_register_visitor('Bad Type', 'LIBRARY_CARD', 'SYN-T-0002', NULL, new_id, st, msg);
    pkg_test.chk('D04', 'invalid ID type returns INVALID_DATA', 'INVALID_DATA', st);
  END;

  -- happy path
  sp_schedule_visit(12, 1, d_far, '09:00-10:00', st, vid, msg);
  pkg_test.chk('D05', 'sp_schedule_visit books an eligible visit', 'BOOKED', st);
  SELECT COUNT(*) INTO v FROM audit_log WHERE action_type = 'VISIT_BOOKED' AND record_id = vid;
  pkg_test.chk('D06', 'allowed visit is written to AUDIT_LOG (VISIT_BOOKED)', '1', TO_CHAR(v));

  -- denials through the procedure, each logged
  SELECT COUNT(*) INTO v_before FROM audit_log WHERE action_type = 'VISIT_DENIED' AND record_id = 36;
  sp_schedule_visit(12, 36, d_far, '10:00-11:00', st, vid, msg);
  pkg_test.chk('D07', 'blacklisted visitor is denied', 'DENIED_BLACKLISTED', st);
  SELECT COUNT(*) INTO v_after FROM audit_log WHERE action_type = 'VISIT_DENIED' AND record_id = 36;
  pkg_test.chk('D08', 'blacklisted attempt is logged as VISIT_DENIED', TO_CHAR(v_before + 1), TO_CHAR(v_after));
  sp_schedule_visit(12, 31, d_far, '10:00-11:00', st, vid, msg);
  pkg_test.chk('D09', 'unapproved (PENDING) visitor is denied', 'DENIED_UNAPPROVED', st);
  sp_schedule_visit(3, 5, d_far, '10:00-11:00', st, vid, msg);
  pkg_test.chk('D10', 'visitor with a conflict is denied', 'DENIED_CONFLICT', st);
  sp_schedule_visit(46, 1, d_far, '10:00-11:00', st, vid, msg);
  pkg_test.chk('D11', 'inactive (TRANSFERRED) inmate is denied', 'DENIED_INMATE_INACTIVE', st);
  sp_schedule_visit(12, 1, d_far, '09:00-10:00', st, vid, msg);
  pkg_test.chk('D12', 'same inmate/date/slot twice is denied (duplicate)', 'DENIED_DUPLICATE', st);
  sp_schedule_visit(12, 1, TRUNC(SYSDATE) - 3, '09:00-10:00', st, vid, msg);
  pkg_test.chk('D13', 'booking in the past is denied', 'DENIED_PAST_DATE', st);
  sp_schedule_visit(12, 1, d_far, '23:00-24:00', st, vid, msg);
  pkg_test.chk('D14', 'unknown slot is denied', 'DENIED_INVALID_SLOT', st);
  sp_schedule_visit(9999, 1, d_far, '10:00-11:00', st, vid, msg);
  pkg_test.chk('D15', 'unknown inmate is denied (NOT an ORA error)', 'DENIED_NO_INMATE', st);
  sp_schedule_visit(12, 9999, d_far, '10:00-11:00', st, vid, msg);
  pkg_test.chk('D16', 'unknown visitor is denied (NOT an ORA error)', 'DENIED_NO_VISITOR', st);
  sp_schedule_visit(14, 1, d_full, '10:00-11:00', st, vid, msg);
  pkg_test.chk('D17', 'date after the inmate''s release is denied (inmate 14 leaves in 19 days)', 'DENIED_OUTSIDE_SENTENCE', st);

  -- weekly limit: 3 visits Mon/Tue/Wed of the same ISO week, the 4th is refused
  FOR i IN 0 .. 2 LOOP
    sp_schedule_visit(13, i + 1, d_week + i, '09:00-10:00', st, vid, msg);
  END LOOP;
  pkg_test.chk('D18', 'three visits in one week are accepted (last status)', 'BOOKED', st);
  sp_schedule_visit(13, 4, d_week + 3, '09:00-10:00', st, vid, msg);
  pkg_test.chk('D19', 'fourth visit in the same week is denied', 'DENIED_WEEKLY_LIMIT', st);

  -- slot capacity: 5 places, the 6th booking gets SLOT_FULL
  FOR r IN (SELECT column_value AS inm, ROWNUM AS n FROM TABLE(SYS.ODCINUMBERLIST(16, 17, 18, 20, 21))) LOOP
    sp_schedule_visit(r.inm, 20 + r.n, d_full, '09:00-10:00', st, vid, msg);
  END LOOP;
  pkg_test.chk('D20', 'fifth booking in a 5-place slot succeeds (last status)', 'BOOKED', st);
  sp_schedule_visit(22, 26, d_full, '09:00-10:00', st, vid, msg);
  pkg_test.chk('D21', 'sixth booking in the slot returns SLOT_FULL', 'SLOT_FULL', st);

  -- trigger = last line of defence when the procedure is bypassed
  SELECT COUNT(*) INTO v_before FROM audit_log WHERE action_type = 'VISIT_DENIED' AND record_id = 37;
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (22, 37, TRUNC(SYSDATE)+45, ''10:00-11:00'')');
  pkg_test.chk('D22', 'trigger refuses a blacklisted visitor on a direct INSERT (ORA-20102)', '-20102', TO_CHAR(v));
  ROLLBACK;
  SELECT COUNT(*) INTO v_after FROM audit_log WHERE action_type = 'VISIT_DENIED' AND record_id = 37;
  pkg_test.chk('D23', 'denial survives the ROLLBACK (autonomous transaction)', TO_CHAR(v_before + 1), TO_CHAR(v_after));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (22, 31, TRUNC(SYSDATE)+45, ''10:00-11:00'')');
  pkg_test.chk('D24', 'trigger refuses an unapproved visitor (ORA-20101)', '-20101', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (3, 5, TRUNC(SYSDATE)+1, ''10:00-11:00'')');
  pkg_test.chk('D25', 'trigger refuses a conflicting visitor (ORA-20103)', '-20103', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (47, 1, TRUNC(SYSDATE)+45, ''10:00-11:00'')');
  pkg_test.chk('D26', 'trigger refuses a non-ACTIVE inmate (ORA-20104)', '-20104', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (13, 5, TRUNC(SYSDATE+50,''IW'')+4, ''10:00-11:00'')');
  pkg_test.chk('D27', 'compound trigger enforces the weekly limit on a direct INSERT (ORA-20105)', '-20105', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (23, 27, TRUNC(SYSDATE)+60, ''09:00-10:00'')');
  pkg_test.chk('D28', 'compound trigger enforces slot capacity on a direct INSERT (ORA-20106)', '-20106', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (14, 1, TRUNC(SYSDATE)+60, ''11:00-12:00'')');
  pkg_test.chk('D29', 'trigger enforces the sentence period on a direct INSERT (ORA-20107)', '-20107', TO_CHAR(v));
  ROLLBACK;
END;
/

-- ============================================================ E. conflicts, visitor status
DECLARE
  st VARCHAR2(40); vid NUMBER; msg VARCHAR2(400); v NUMBER; cid NUMBER;
  d DATE := TRUNC(SYSDATE) + 70;
BEGIN
  sp_add_conflict(18, 21, 'rival', NULL, st, msg);
  pkg_test.chk('E01', 'sp_add_conflict records a new conflict', 'CONFLICT_ADDED', st);
  sp_schedule_visit(18, 21, d, '09:00-10:00', st, vid, msg);
  pkg_test.chk('E02', 'the new conflict immediately blocks booking', 'DENIED_CONFLICT', st);
  SELECT conflict_id INTO cid FROM conflicts WHERE inmate_id = 18 AND visitor_id = 21;
  sp_resolve_conflict(cid, st, msg);
  pkg_test.chk('E03', 'sp_resolve_conflict resolves it', 'RESOLVED', st);
  sp_resolve_conflict(cid, st, msg);
  pkg_test.chk('E04', 'resolving twice reports ALREADY_RESOLVED', 'ALREADY_RESOLVED', st);
  sp_schedule_visit(18, 21, d, '09:00-10:00', st, vid, msg);
  pkg_test.chk('E05', 'after resolution the visit can be booked', 'BOOKED', st);
  sp_add_conflict(18, 21, 'gang_affiliation', NULL, st, msg);
  pkg_test.chk('E06', 're-flagging a resolved pair re-activates it', 'CONFLICT_REACTIVATED', st);
  SELECT status INTO msg FROM visits WHERE visit_id = vid;
  pkg_test.chk('E07', 'adding a conflict cancels that pair''s future visit', 'CANCELLED', msg);
  sp_resolve_conflict(99999, st, msg);
  pkg_test.chk('E08', 'resolving an unknown conflict returns NOT_FOUND', 'NOT_FOUND', st);
  sp_add_conflict(9999, 21, 'RIVAL', NULL, st, msg);
  pkg_test.chk('E09', 'conflict for unknown inmate returns NOT_FOUND', 'NOT_FOUND', st);

  sp_schedule_visit(19 + 2, 22, d + 1, '09:00-10:00', st, vid, msg);          -- inmate 21, visitor 22
  sp_set_visitor_status(22, 'blacklisted', st, msg);
  pkg_test.chk('E10', 'sp_set_visitor_status blacklists a visitor', 'UPDATED', st);
  SELECT status INTO msg FROM visits WHERE visit_id = vid;
  pkg_test.chk('E11', 'blacklisting cancels the visitor''s future visits', 'CANCELLED', msg);
  sp_set_visitor_status(22, 'approved', st, msg);
  sp_set_visitor_status(9999, 'APPROVED', st, msg);
  pkg_test.chk('E12', 'unknown visitor returns NOT_FOUND', 'NOT_FOUND', st);
  sp_set_visitor_status(22, 'MAYBE', st, msg);
  pkg_test.chk('E13', 'invalid status returns INVALID_DATA', 'INVALID_DATA', st);
  sp_add_inmate_rivalry(30, 12, 'RIVAL', st, msg);
  pkg_test.chk('E14', 'sp_add_inmate_rivalry stores a pair (larger id given first)', 'RIVALRY_ADDED', st);
  sp_add_inmate_rivalry(12, 30, 'RIVAL', st, msg);
  pkg_test.chk('E15', 'same rivalry twice returns ALREADY_EXISTS', 'ALREADY_EXISTS', st);
END;
/

-- ============================================================ F. transfers and movement logging
DECLARE
  st VARCHAR2(40); msg VARCHAR2(400);
  v NUMBER; v_mov NUMBER; v_aud NUMBER; v_blk NUMBER; v_blk0 NUMBER; v_mov2 NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_mov FROM movements WHERE inmate_id = 1;
  SELECT COUNT(*) INTO v_aud FROM audit_log WHERE action_type = 'TRANSFER' AND record_id = 1;
  sp_transfer_inmate(1, 4, 'Test: rehousing to D-Block', st, msg);
  pkg_test.chk('F01', 'sp_transfer_inmate moves an inmate to a block with room', 'TRANSFERRED', st);
  SELECT block_id INTO v_blk FROM inmates WHERE inmate_id = 1;
  pkg_test.chk('F02', 'INMATES.block_id was updated', '4', TO_CHAR(v_blk));
  SELECT COUNT(*) INTO v FROM movements WHERE inmate_id = 1;
  pkg_test.chk('F03', 'successful transfer wrote a MOVEMENTS row (by trg_log_movement)', TO_CHAR(v_mov + 1), TO_CHAR(v));
  SELECT reason INTO msg FROM movements WHERE inmate_id = 1 ORDER BY movement_id DESC FETCH FIRST 1 ROW ONLY;
  pkg_test.chk('F04', 'MOVEMENTS row carries the reason passed to the procedure', 'Test: rehousing to D-Block', msg);
  SELECT COUNT(*) INTO v FROM audit_log WHERE action_type = 'TRANSFER' AND record_id = 1;
  pkg_test.chk('F05', 'successful transfer wrote an AUDIT_LOG TRANSFER row', TO_CHAR(v_aud + 1), TO_CHAR(v));

  -- D-Block (10 beds) is now full: 10 of 10
  pkg_test.chk('F06', 'D-Block is now exactly full', '10', TO_CHAR(fn_block_occupancy(4)));
  SELECT COUNT(*) INTO v_mov FROM movements;
  SELECT block_id INTO v_blk0 FROM inmates WHERE inmate_id = 2;
  sp_transfer_inmate(2, 4, 'should not fit', st, msg);
  pkg_test.chk('F07', 'full block rejects a transfer', 'BLOCK_FULL', st);
  SELECT block_id INTO v_blk FROM inmates WHERE inmate_id = 2;
  SELECT COUNT(*) INTO v_mov2 FROM movements;
  pkg_test.chk('F08', 'rejected transfer left the inmate where he was', TO_CHAR(v_blk0), TO_CHAR(v_blk));
  pkg_test.chk('F09', 'rejected transfer left NO partial MOVEMENTS row (rollback)', TO_CHAR(v_mov), TO_CHAR(v_mov2));

  sp_transfer_inmate(27, 1, 'HIGH risk into LOW block', st, msg);
  pkg_test.chk('F10', 'insufficient security level rejects a transfer', 'SECURITY_MISMATCH', st);
  sp_transfer_inmate(4, 2, 'rival lives in B-Block', st, msg);
  pkg_test.chk('F11', 'moving next to a rival is rejected', 'RIVAL_IN_BLOCK', st);
  sp_transfer_inmate(9999, 2, 'x', st, msg);
  pkg_test.chk('F12', 'unknown inmate returns NOT_FOUND', 'NOT_FOUND', st);
  sp_transfer_inmate(5, 99, 'x', st, msg);
  pkg_test.chk('F13', 'unknown block returns BLOCK_NOT_FOUND', 'BLOCK_NOT_FOUND', st);
  sp_transfer_inmate(46, 2, 'x', st, msg);
  pkg_test.chk('F14', 'a TRANSFERRED (non-active) inmate cannot be moved', 'INMATE_NOT_ACTIVE', st);
  sp_transfer_inmate(5, 1, 'x', st, msg);
  pkg_test.chk('F15', 'moving to the block the inmate is already in returns SAME_BLOCK', 'SAME_BLOCK', st);

  -- bypassing the procedure: movement trigger and placement trigger still protect the data
  SELECT COUNT(*) INTO v_mov FROM movements WHERE inmate_id = 5;
  UPDATE inmates SET block_id = 2 WHERE inmate_id = 5;
  SELECT COUNT(*) INTO v FROM movements WHERE inmate_id = 5;
  pkg_test.chk('F16', 'direct UPDATE of block_id is still logged by trg_log_movement', TO_CHAR(v_mov + 1), TO_CHAR(v));
  SELECT reason INTO msg FROM movements WHERE inmate_id = 5 ORDER BY movement_id DESC FETCH FIRST 1 ROW ONLY;
  pkg_test.chk('F17', 'direct update gets the default reason text', 'Direct update of INMATES.block_id', msg);
  ROLLBACK;
  v := pkg_test.try_sql('UPDATE inmates SET block_id = 5 WHERE inmate_id = 2');
  pkg_test.chk('F18', 'compound trigger blocks a direct move into a full block (ORA-20201)', '-20201', TO_CHAR(v));
  v := pkg_test.try_sql('UPDATE inmates SET block_id = 1 WHERE inmate_id = 27');
  pkg_test.chk('F19', 'trigger blocks risk above block security on direct UPDATE (ORA-20202)', '-20202', TO_CHAR(v));
  v := pkg_test.try_sql('UPDATE inmates SET block_id = 2 WHERE inmate_id = 4');
  pkg_test.chk('F20', 'trigger blocks housing a rival in the same block (ORA-20203)', '-20203', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO inmates (inmate_no, full_name, date_of_birth, sentence_start, sentence_end, block_id, risk_level) ' ||
                        'VALUES (''INM-T001'', ''Test Inmate'', DATE ''1990-01-01'', TRUNC(SYSDATE)-10, TRUNC(SYSDATE)+400, 5, ''LOW'')');
  pkg_test.chk('F21', 'admitting a new inmate into the full E-Block is refused (ORA-20201)', '-20201', TO_CHAR(v));
  v := pkg_test.try_sql('INSERT INTO inmates (inmate_no, full_name, date_of_birth, sentence_start, sentence_end, block_id, risk_level) ' ||
                        'VALUES (''INM-T002'', ''Test Inmate'', DATE ''1990-01-01'', TRUNC(SYSDATE)-10, TRUNC(SYSDATE)+400, 3, ''HIGH'')');
  pkg_test.chk('F22', 'admitting a HIGH-risk inmate into C-Block (one free bed) works', '0', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM movements m JOIN inmates i ON i.inmate_id = m.inmate_id
   WHERE i.inmate_no = 'INM-T002' AND m.from_block IS NULL AND m.reason = 'ADMISSION';
  pkg_test.chk('F23', 'admission INSERT created an ADMISSION movement', '1', TO_CHAR(v));
  ROLLBACK;
END;
/

-- ============================================================ G. audit trail
DECLARE
  v NUMBER; c NUMBER;
BEGIN
  v := pkg_test.try_sql('UPDATE audit_log SET details = ''tampered'' WHERE audit_id = (SELECT MIN(audit_id) FROM audit_log)');
  pkg_test.chk('G01', 'UPDATE of an audit row is refused (ORA-20301)', '-20301', TO_CHAR(v));
  v := pkg_test.try_sql('DELETE FROM audit_log WHERE audit_id = (SELECT MIN(audit_id) FROM audit_log)');
  pkg_test.chk('G02', 'DELETE of an audit row is refused (ORA-20301)', '-20301', TO_CHAR(v));
  v := pkg_test.try_sql('DELETE FROM audit_log');
  pkg_test.chk('G03', 'mass DELETE of the audit log is refused (ORA-20301)', '-20301', TO_CHAR(v));
  ROLLBACK;
  SELECT COUNT(*) INTO c FROM audit_log;
  pkg_test.chk('G04', 'audit log still holds rows after the tamper attempts', 'TRUE', CASE WHEN c > 0 THEN 'TRUE' ELSE 'FALSE' END);

  UPDATE visitors SET phone = '+00-555-4242' WHERE visitor_id = 8;
  SELECT COUNT(*) INTO v FROM audit_log WHERE table_name = 'VISITORS' AND action_type = 'UPDATE' AND record_id = 8
     AND details LIKE 'phone: +00-555-0008 -> +00-555-4242%';
  pkg_test.chk('G05', 'UPDATE trigger records old and new values', '1', TO_CHAR(v));
  ROLLBACK;
  UPDATE inmates SET risk_level = 'MEDIUM' WHERE inmate_id = 13;
  SELECT COUNT(*) INTO v FROM audit_log WHERE table_name = 'INMATES' AND action_type = 'UPDATE' AND record_id = 13
     AND details LIKE 'risk_level: LOW -> MEDIUM%';
  pkg_test.chk('G06', 'inmate change is audited (risk_level LOW -> MEDIUM)', '1', TO_CHAR(v));
  ROLLBACK;
END;
/

-- ============================================================ H. cursors process multiple records
-- DBMS_OUTPUT.GET_LINES also removes any TEST lines already buffered, so every capture is done
-- first and all results are reported at the very end of the block.
DECLARE
  l DBMS_OUTPUT.CHARARR; n INTEGER;
  v_blocks NUMBER := 0; v_total NUMBER := -1; v_expected NUMBER;
  v_empty NUMBER := 0; v_occ_lines NUMBER := 0; v_full_flag NUMBER := 0; v_rel NUMBER := -1; v_exp_rel NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_expected FROM visits WHERE visit_date = TRUNC(SYSDATE) AND status <> 'CANCELLED';
  SELECT COUNT(*) INTO v_exp_rel FROM inmates WHERE status = 'ACTIVE' AND sentence_end BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 30;

  n := 2000; DBMS_OUTPUT.GET_LINES(l, n);                  -- discard anything buffered so far
  pr_daily_roster(TRUNC(SYSDATE));
  n := 2000; DBMS_OUTPUT.GET_LINES(l, n);
  FOR i IN 1 .. n LOOP
    IF l(i) LIKE '%--- %---' THEN v_blocks := v_blocks + 1; END IF;
    IF l(i) LIKE '%Total visits listed:%' THEN v_total := TO_NUMBER(REGEXP_SUBSTR(l(i), '[0-9]+$')); END IF;
  END LOOP;

  pr_daily_roster(TRUNC(SYSDATE) + 300);                   -- an empty day
  n := 2000; DBMS_OUTPUT.GET_LINES(l, n);
  FOR i IN 1 .. n LOOP IF l(i) LIKE '%no visits scheduled%' THEN v_empty := 1; END IF; END LOOP;

  pr_block_occupancy;
  n := 2000; DBMS_OUTPUT.GET_LINES(l, n);
  FOR i IN 1 .. n LOOP
    IF l(i) LIKE '%-Block %' THEN v_occ_lines := v_occ_lines + 1; END IF;
    IF l(i) LIKE 'E-Block%AT CAPACITY%' THEN v_full_flag := 1; END IF;
  END LOOP;

  pr_upcoming_releases(30);
  n := 2000; DBMS_OUTPUT.GET_LINES(l, n);
  FOR i IN 1 .. n LOOP
    IF l(i) LIKE 'inmates due for release:%' THEN v_rel := TO_NUMBER(REGEXP_SUBSTR(l(i), '[0-9]+$')); END IF;
  END LOOP;

  pkg_test.chk('H01', 'c_daily_roster fetched every visit of today (%ROWCOUNT)', TO_CHAR(v_expected), TO_CHAR(v_total));
  pkg_test.chk('H02', 'c_daily_roster grouped the rows under 3 or more block headings', 'TRUE', CASE WHEN v_blocks >= 3 THEN 'TRUE' ELSE 'FALSE' END);
  pkg_test.chk('H03', 'c_daily_roster processed MULTIPLE records (>= 5)', 'TRUE', CASE WHEN v_total >= 5 THEN 'TRUE' ELSE 'FALSE' END);
  pkg_test.chk('H04', 'c_daily_roster handles an empty result set (%ROWCOUNT = 0)', '1', TO_CHAR(v_empty));
  pkg_test.chk('H05', 'c_block_occupancy listed all 5 blocks', '5', TO_CHAR(v_occ_lines));
  pkg_test.chk('H06', 'c_block_occupancy flagged the full E-Block as AT CAPACITY', '1', TO_CHAR(v_full_flag));
  pkg_test.chk('H07', 'c_upcoming_release (cursor FOR loop) lists releases within 30 days', TO_CHAR(v_exp_rel), TO_CHAR(v_rel));
  pkg_test.chk('H08', 'upcoming releases returned more than one inmate', 'TRUE', CASE WHEN v_rel >= 2 THEN 'TRUE' ELSE 'FALSE' END);
END;
/

-- ============================================================ I. views, scheduled job, flashback
DECLARE
  v NUMBER; s VARCHAR2(60); rel NUMBER; mis NUMBER; n_id NUMBER; v_jobs NUMBER;
BEGIN
  SELECT occupancy_flag INTO s FROM v_block_occupancy WHERE block_name = 'E-Block';
  pkg_test.chk('I01', 'v_block_occupancy flags E-Block', 'AT CAPACITY', s);
  SELECT occupancy_pct INTO v FROM v_block_occupancy WHERE block_name = 'E-Block';
  pkg_test.chk('I02', 'v_block_occupancy percentage for a full block', '100', TO_CHAR(v));
  SELECT id_proof_masked INTO s FROM v_visitors_masked WHERE visitor_id = 1;
  pkg_test.chk('I03', 'v_visitors_masked shows only the last four characters', '****7919', s);
  SELECT COUNT(*) INTO v FROM v_denied_attempts WHERE reason = 'BLACKLISTED';
  pkg_test.chk('I04', 'v_denied_attempts parses reasons from the audit log (>= 4)', 'TRUE', CASE WHEN v >= 4 THEN 'TRUE' ELSE 'FALSE' END);
  SELECT COUNT(*) INTO v FROM v_active_inmates;
  pkg_test.chk('I05', 'v_active_inmates shows only ACTIVE inmates (45 + test admissions rolled back)', '45', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM v_todays_visits;
  pkg_test.chk('I06', 'v_todays_visits lists today''s visits', '8', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM v_inmate_conflicts WHERE conflict_state = 'ACTIVE';
  pkg_test.chk('I07', 'v_inmate_conflicts separates ACTIVE from RESOLVED/EXPIRED (6 seed + 1 from section E)', '7', TO_CHAR(v));

  -- scheduled job body: fixture = an inmate whose sentence ended yesterday + a SCHEDULED visit in the past
  INSERT INTO inmates (inmate_no, full_name, date_of_birth, sentence_start, sentence_end, block_id, risk_level)
    VALUES ('INM-T900', 'Job Fixture', DATE '1985-05-05', TRUNC(SYSDATE) - 300, TRUNC(SYSDATE) - 1, 1, 'LOW')
    RETURNING inmate_id INTO n_id;
  INSERT INTO visits (inmate_id, visitor_id, visit_date, slot, status)
    VALUES (n_id, 1, TRUNC(SYSDATE) - 2, '09:00-10:00', 'SCHEDULED');
  SELECT COUNT(*) INTO v_jobs FROM audit_log WHERE action_type = 'JOB';
  pr_nightly_maintenance(rel, mis);
  SELECT status INTO s FROM inmates WHERE inmate_id = n_id;
  pkg_test.chk('I08', 'nightly job releases an inmate whose sentence ended (WHERE CURRENT OF)', 'RELEASED', s);
  SELECT COUNT(*) INTO v FROM visits WHERE inmate_id = n_id AND status = 'MISSED';
  pkg_test.chk('I09', 'nightly job marks a past SCHEDULED visit as MISSED', '1', TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM audit_log WHERE action_type = 'JOB' AND details LIKE 'pr_nightly_maintenance:%';
  pkg_test.chk('I10', 'nightly job wrote exactly one new JOB audit row', TO_CHAR(v_jobs + 1), TO_CHAR(v));
  SELECT COUNT(*) INTO v FROM user_scheduler_jobs WHERE job_name = 'JOB_NIGHTLY_PRISON_MAINTENANCE' AND enabled = 'TRUE';
  pkg_test.chk('I11', 'DBMS_SCHEDULER job exists and is enabled', '1', TO_CHAR(v));
  DELETE FROM visits WHERE inmate_id = n_id;
  DELETE FROM movements WHERE inmate_id = n_id;
  DELETE FROM inmates WHERE inmate_id = n_id;
  COMMIT;
END;
/

-- ============================================================ J. recovery after accidental deletion (local equivalent of F30)
-- Oracle Flashback Table undoes an accidental DELETE using undo data. It works on a throw-away
-- table, never on project data. The managed-cloud automatic backup / point-in-time restore is
-- a manual, console-based test (Documentation/Cloud_Setup.md).
CREATE TABLE tmp_backup_test (id NUMBER PRIMARY KEY, note VARCHAR2(40)) ENABLE ROW MOVEMENT;
INSERT INTO tmp_backup_test SELECT LEVEL, 'synthetic row ' || LEVEL FROM dual CONNECT BY LEVEL <= 20;
COMMIT;
DECLARE
  v_ts TIMESTAMP; v NUMBER;
BEGIN
  DBMS_SESSION.SLEEP(3);
  v_ts := SYSTIMESTAMP;
  DBMS_SESSION.SLEEP(3);
  DELETE FROM tmp_backup_test;                             -- the "accident"
  COMMIT;
  SELECT COUNT(*) INTO v FROM tmp_backup_test;
  pkg_test.chk('J01', 'accidental DELETE removed all 20 test rows', '0', TO_CHAR(v));
  EXECUTE IMMEDIATE 'FLASHBACK TABLE tmp_backup_test TO TIMESTAMP TO_TIMESTAMP(''' ||
                    TO_CHAR(v_ts, 'YYYY-MM-DD HH24:MI:SS.FF6') || ''', ''YYYY-MM-DD HH24:MI:SS.FF6'')';
  SELECT COUNT(*) INTO v FROM tmp_backup_test;
  pkg_test.chk('J02', 'FLASHBACK TABLE restored the 20 rows', '20', TO_CHAR(v));
END;
/
DROP TABLE tmp_backup_test PURGE;

-- ============================================================ K. transactions
DECLARE
  v NUMBER;
BEGIN
  INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES ('Txn One', 'PASSPORT', 'SYN-TXN-K1');
  SAVEPOINT sp1;
  INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES ('Txn Two', 'PASSPORT', 'SYN-TXN-K2');
  ROLLBACK TO SAVEPOINT sp1;
  SELECT COUNT(*) INTO v FROM visitors WHERE id_proof_number IN ('SYN-TXN-K1', 'SYN-TXN-K2');
  pkg_test.chk('K01', 'ROLLBACK TO SAVEPOINT undoes only the later insert', '1', TO_CHAR(v));
  ROLLBACK;
  SELECT COUNT(*) INTO v FROM visitors WHERE id_proof_number LIKE 'SYN-TXN-K%';
  pkg_test.chk('K02', 'ROLLBACK leaves no partial data', '0', TO_CHAR(v));
END;
/

-- ============================================================ L. advanced query features
DECLARE
  v_page_rows NUMBER;
  v_pivot_total NUMBER;
  v_visit_total NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_page_rows
    FROM (
      SELECT inmate_no
        FROM inmates
       WHERE status = 'ACTIVE'
       ORDER BY inmate_no
       OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY
    );
  pkg_test.chk('L01', 'OFFSET/FETCH returns a five-row page', '5', TO_CHAR(v_page_rows));

  SELECT NVL(scheduled, 0) + NVL(completed, 0) + NVL(missed, 0) + NVL(cancelled, 0)
    INTO v_pivot_total
    FROM (
      SELECT visit_id, status FROM visits
    )
    PIVOT (
      COUNT(visit_id) FOR status IN (
        'SCHEDULED' AS scheduled,
        'COMPLETED' AS completed,
        'MISSED' AS missed,
        'CANCELLED' AS cancelled
      )
    );
  SELECT COUNT(*) INTO v_visit_total FROM visits;
  pkg_test.chk('L02', 'PIVOT status totals account for every visit', TO_CHAR(v_visit_total), TO_CHAR(v_pivot_total));
END;
/

BEGIN pkg_test.summary; END;
/
DROP PACKAGE pkg_test;

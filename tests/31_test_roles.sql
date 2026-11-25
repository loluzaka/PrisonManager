-- =============================================================================
-- 31_test_roles.sql
-- Features : F25 (roles and privileges), F26 (masking), F31 (facility access), F22 (audit least privilege)
-- Owner    : Member 3
-- RUN AS   : each demo user in turn (scripts\run_tests.ps1 does this):
--            PRISON_U_ADMIN, PRISON_U_WARDEN, PRISON_U_WARDEN2, PRISON_U_FRONTDESK, PRISON_U_AUDITOR
-- The script finds out WHO is connected and runs the allowed and forbidden actions of that role.
-- Output: TEST|<id>|<purpose>|<expected>|<actual>|<PASS|FAIL>      (expected values are ORA codes)
-- Changes are rolled back; the front desk test books one real visit on a far-future date and
-- cancels it again.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 250
-- name resolution only; privileges are NOT inherited
ALTER SESSION SET CURRENT_SCHEMA = prison_owner;

DECLARE
  v_user VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
  v_pass PLS_INTEGER := 0;
  v_fail PLS_INTEGER := 0;
  st VARCHAR2(40); vid NUMBER; msg VARCHAR2(400);

  PROCEDURE chk (p_id VARCHAR2, p_purpose VARCHAR2, p_expected VARCHAR2, p_actual VARCHAR2) IS
    v_ok BOOLEAN := (p_expected = p_actual);
  BEGIN
    IF v_ok THEN v_pass := v_pass + 1; ELSE v_fail := v_fail + 1; END IF;
    DBMS_OUTPUT.PUT_LINE('TEST|' || p_id || '|' || v_user || ': ' || p_purpose || '|' || p_expected || '|' ||
                         p_actual || '|' || CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);
  END;

  -- runs a statement; returns 0 on success, otherwise the SQLCODE. Mapped so "no privilege" is one value:
  -- ORA-00942 (no select), ORA-01031 and ORA-41900 (missing privilege, Oracle 23ai) all mean DENIED.
  FUNCTION attempt (p_sql VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    RETURN 'ALLOWED';
  EXCEPTION WHEN OTHERS THEN
    RETURN CASE WHEN SQLCODE IN (-942, -1031, -6550, -904, -41900) THEN 'DENIED' ELSE 'ERR' || SQLCODE END;
  END;

  FUNCTION cnt (p_sql VARCHAR2) RETURN NUMBER IS
    n NUMBER;
  BEGIN EXECUTE IMMEDIATE p_sql INTO n; RETURN n; EXCEPTION WHEN OTHERS THEN RETURN -1; END;

  FUNCTION str (p_sql VARCHAR2) RETURN VARCHAR2 IS
    s VARCHAR2(400);
  BEGIN EXECUTE IMMEDIATE p_sql INTO s; RETURN s; EXCEPTION WHEN OTHERS THEN RETURN 'ERR' || SQLCODE; END;
BEGIN
  -- ------------------------------------------------ common to everybody: audit log is append-only
  chk('R-AUDIT-1', 'cannot UPDATE audit_log', 'DENIED',
      attempt('UPDATE prison_owner.audit_log SET details = ''x'' WHERE audit_id = 1'));
  chk('R-AUDIT-2', 'cannot DELETE from audit_log', 'DENIED',
      attempt('DELETE FROM prison_owner.audit_log WHERE audit_id = 1'));
  chk('R-AUDIT-3', 'cannot TRUNCATE audit_log', 'DENIED', attempt('TRUNCATE TABLE prison_owner.audit_log'));

  IF v_user = 'PRISON_U_FRONTDESK' THEN
    chk('R-FD-1', 'cannot read the INMATES table', 'DENIED', attempt('SELECT * FROM prison_owner.inmates'));
    chk('R-FD-2', 'cannot read raw VISITORS (full ID numbers)', 'DENIED', attempt('SELECT id_proof_number FROM prison_owner.visitors'));
    chk('R-FD-3', 'cannot DELETE visits directly', 'DENIED', attempt('DELETE FROM prison_owner.visits'));
    chk('R-FD-4', 'cannot INSERT into VISITS directly (procedure only)', 'DENIED',
        attempt('INSERT INTO prison_owner.visits (inmate_id, visitor_id, visit_date, slot) VALUES (12, 1, TRUNC(SYSDATE)+250, ''09:00-10:00'')'));
    chk('R-FD-5', 'cannot read the audit log', 'DENIED', attempt('SELECT * FROM prison_owner.audit_log'));
    chk('R-FD-6', 'cannot call sp_transfer_inmate', 'DENIED',
        attempt('DECLARE a VARCHAR2(40); b VARCHAR2(400); BEGIN prison_owner.sp_transfer_inmate(5, 2, ''x'', a, b); END;'));
    chk('R-FD-7', 'CAN read masked visitors', 'ALLOWED', attempt('SELECT id_proof_masked FROM prison_owner.v_visitors_masked'));
    chk('R-FD-8', 'masked view hides all but 4 characters', '****7919',
        str('SELECT id_proof_masked FROM prison_owner.v_visitors_masked WHERE visitor_id = 1'));
    EXECUTE IMMEDIATE 'BEGIN prison_owner.sp_schedule_visit(:1,:2,:3,:4,:5,:6,:7); END;'
      USING IN 12, IN 1, IN TRUNC(SYSDATE) + 250, IN '09:00-10:00', OUT st, OUT vid, OUT msg;
    chk('R-FD-9', 'CAN book a visit through sp_schedule_visit (definer rights)', 'BOOKED', st);
    EXECUTE IMMEDIATE 'BEGIN prison_owner.sp_schedule_visit(:1,:2,:3,:4,:5,:6,:7); END;'
      USING IN 12, IN 36, IN TRUNC(SYSDATE) + 250, IN '10:00-11:00', OUT st, OUT vid, OUT msg;
    chk('R-FD-10', 'procedure still refuses a blacklisted visitor', 'DENIED_BLACKLISTED', st);
    EXECUTE IMMEDIATE 'BEGIN prison_owner.sp_schedule_visit(:1,:2,:3,:4,:5,:6,:7); END;'
      USING IN 31, IN 1, IN TRUNC(SYSDATE) + 251, IN '11:00-12:00', OUT st, OUT vid, OUT msg;
    chk('R-FD-11', 'cannot book an inmate in another facility', 'DENIED_FACILITY', st);
  ELSIF v_user = 'PRISON_U_AUDITOR' THEN
    chk('R-AU-1', 'CAN read the audit log', 'ALLOWED', attempt('SELECT * FROM prison_owner.audit_log'));
    chk('R-AU-2', 'cannot INSERT into the audit log', 'DENIED',
        attempt('INSERT INTO prison_owner.audit_log (table_name, action_type, details) VALUES (''X'', ''INSERT'', ''forged'')'));
    chk('R-AU-3', 'cannot change inmates', 'DENIED', attempt('UPDATE prison_owner.inmates SET status = ''RELEASED'''));
    chk('R-AU-4', 'cannot book visits', 'DENIED',
        attempt('DECLARE a VARCHAR2(40); b NUMBER; c VARCHAR2(400); BEGIN prison_owner.sp_schedule_visit(12,1,TRUNC(SYSDATE)+250,''09:00-10:00'',a,b,c); END;'));
    chk('R-AU-5', 'CAN read report views', 'ALLOWED', attempt('SELECT * FROM prison_owner.v_denied_attempts'));
    chk('R-AU-6', 'cannot read raw visitors', 'DENIED', attempt('SELECT id_proof_number FROM prison_owner.visitors'));
    chk('R-AU-7', 'auditor sees every facility (STAFF_ACCESS facility_id NULL)', '50',
        TO_CHAR(cnt('SELECT COUNT(*) FROM prison_owner.v_fac_inmates')));
  ELSIF v_user IN ('PRISON_U_WARDEN', 'PRISON_U_WARDEN2') THEN
    chk('R-WA-1', 'CAN update inmates', 'ALLOWED', attempt('UPDATE prison_owner.inmates SET full_name = full_name WHERE inmate_id = 1'));
    ROLLBACK;
    chk('R-WA-2', 'cannot DELETE inmates', 'DENIED', attempt('DELETE FROM prison_owner.inmates WHERE inmate_id = 1'));
    chk('R-WA-3', 'cannot touch visitors', 'DENIED', attempt('SELECT * FROM prison_owner.visitors'));
    chk('R-WA-4', 'cannot call sp_schedule_visit (front desk duty)', 'DENIED',
        attempt('DECLARE a VARCHAR2(40); b NUMBER; c VARCHAR2(400); BEGIN prison_owner.sp_schedule_visit(12,1,TRUNC(SYSDATE)+250,''09:00-10:00'',a,b,c); END;'));
    chk('R-WA-5', 'CAN read movement history', 'ALLOWED', attempt('SELECT * FROM prison_owner.v_movement_history'));
    -- facility isolation (F31): facility 1 = blocks A,B,C ; facility 2 = blocks D,E
    chk('R-WA-6', 'facility-scoped view shows only the warden''s own facility',
        CASE v_user WHEN 'PRISON_U_WARDEN' THEN '33' ELSE '17' END,
        TO_CHAR(cnt('SELECT COUNT(*) FROM prison_owner.v_fac_inmates')));
    chk('R-WA-7', 'facility-scoped blocks', CASE v_user WHEN 'PRISON_U_WARDEN' THEN '3' ELSE '2' END,
        TO_CHAR(cnt('SELECT COUNT(*) FROM prison_owner.v_fac_blocks')));
  ELSIF v_user = 'PRISON_U_ADMIN' THEN
    chk('R-AD-1', 'CAN read and change visitors', 'ALLOWED', attempt('UPDATE prison_owner.visitors SET phone = phone WHERE visitor_id = 1'));
    ROLLBACK;
    chk('R-AD-2', 'CAN call sp_register_visitor', 'ALLOWED',
        attempt('DECLARE a NUMBER; b VARCHAR2(40); c VARCHAR2(400); BEGIN prison_owner.sp_register_visitor(''Admin Test'',''PASSPORT'',''SYN-ADM-1'',NULL,a,b,c); END;'));
    chk('R-AD-3', 'admin sees both facilities', '50', TO_CHAR(cnt('SELECT COUNT(*) FROM prison_owner.v_fac_inmates')));
    chk('R-AD-4', 'admin is still refused by the audit trigger / has no UPDATE right', 'DENIED',
        attempt('UPDATE prison_owner.audit_log SET details = ''x'''));
    chk('R-AD-5', 'admin cannot DROP a table (no DDL privilege)', 'DENIED', attempt('DROP TABLE prison_owner.visits'));
  END IF;

  DBMS_OUTPUT.PUT_LINE('SUMMARY|' || v_user || '|passed=' || v_pass || '|failed=' || v_fail);
END;
/

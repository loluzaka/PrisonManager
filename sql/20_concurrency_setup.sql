-- =============================================================================
-- 20_concurrency_setup.sql
-- Feature : F24 (two-session concurrency demonstration - preparation, check and cleanup)
-- Owner   : Member 2
-- RUN AS  : PRISON_OWNER
-- USAGE   : @20_concurrency_setup.sql SETUP | CHECK | CLEANUP
--
-- Scenario: slot 16:00-17:00 on the date TODAY+21 has capacity 5. SETUP books 4 visits so exactly
-- ONE place is left. Two staff members (script 21, two sessions) then try to take the last place.
--   MODE NAIVE: check-then-insert without locking  -> BOTH succeed -> 6 visits in a 5-place slot
--   MODE SAFE : sp_schedule_visit (row locks)       -> exactly ONE succeeds, the other gets SLOT_FULL
-- CHECK prints how many visits the slot holds; CLEANUP removes the demo visits.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
DEFINE action = &1

DECLARE
  c_date CONSTANT DATE := TRUNC(SYSDATE) + 21;
  c_slot CONSTANT VARCHAR2(11) := '16:00-17:00';
  v_status VARCHAR2(40); v_vid NUMBER; v_msg VARCHAR2(400);
  v_cnt NUMBER;
BEGIN
  IF UPPER('&action') IN ('SETUP', 'CLEANUP') THEN
    DELETE FROM visits WHERE visit_date = c_date AND slot = c_slot;
    COMMIT;
  END IF;
  IF UPPER('&action') = 'SETUP' THEN
    -- inmates 1,2,4,5 visited by approved visitors 21..24 through the safe procedure
    FOR i IN 1 .. 4 LOOP
      sp_schedule_visit(CASE i WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 4 ELSE 5 END,
                        20 + i, c_date, c_slot, v_status, v_vid, v_msg);
      DBMS_OUTPUT.PUT_LINE('setup booking ' || i || ': ' || v_status);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('slot ' || c_slot || ' on ' || TO_CHAR(c_date, 'DD-MON-YYYY') || ' now has 4 of 5 places taken');
  ELSIF UPPER('&action') = 'CHECK' THEN
    SELECT COUNT(*) INTO v_cnt FROM visits WHERE visit_date = c_date AND slot = c_slot AND status <> 'CANCELLED';
    SELECT max_visitors INTO v_status FROM visit_slots WHERE slot_code = c_slot;
    DBMS_OUTPUT.PUT_LINE('RESULT: slot holds ' || v_cnt || ' visits, capacity is ' || v_status ||
                         CASE WHEN v_cnt > TO_NUMBER(v_status) THEN '  --> CAPACITY RULE BROKEN (lost update / over-booking)'
                              ELSE '  --> capacity rule held' END);
  ELSIF UPPER('&action') = 'CLEANUP' THEN
    DBMS_OUTPUT.PUT_LINE('demo visits removed');
  ELSE
    RAISE_APPLICATION_ERROR(-20999, 'Use SETUP, CHECK or CLEANUP');
  END IF;
END;
/

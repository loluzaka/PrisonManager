-- =============================================================================
-- 21_concurrency_session.sql
-- Feature : F24 (one of the TWO competing sessions)
-- Owner   : Member 2
-- RUN AS  : PRISON_OWNER, in two separate sessions at the same time (scripts/concurrency_demo.ps1 does this)
-- USAGE   : @21_concurrency_session.sql <NAIVE|SAFE> <label> <inmate_id> <visitor_id> <start_delay_s> <hold_s>
--
-- NAIVE: read the count, INSERT, wait <hold_s> seconds (a "slow clerk") and only then COMMIT - no lock.
--        The other clerk cannot see the uncommitted row, so the trigger's count passes for both -> 6 bookings.
--        (Classic check-then-act race / lost update. Triggers alone cannot prevent it.)
-- SAFE : sp_schedule_visit(..., p_auto_commit => 'N') locks the inmate row and the slot row,
--        the session waits <hold_s> seconds holding those locks, then COMMITs. The second
--        session blocks inside the procedure until the first commits, then sees 5 and gets SLOT_FULL.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
DEFINE mode_    = &1
DEFINE label_   = &2
DEFINE inmate_  = &3
DEFINE visitor_ = &4
DEFINE delay_   = &5
DEFINE hold_    = &6

DECLARE
  c_date CONSTANT DATE := TRUNC(SYSDATE) + 21;
  c_slot CONSTANT VARCHAR2(11) := '16:00-17:00';
  v_status VARCHAR2(40); v_vid NUMBER; v_msg VARCHAR2(400); v_cnt NUMBER;
  FUNCTION ts RETURN VARCHAR2 IS BEGIN RETURN TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS.FF2'); END;
BEGIN
  DBMS_SESSION.SLEEP(&delay_);
  DBMS_OUTPUT.PUT_LINE('[' || ts || '] &label_ (&mode_) starts: inmate &inmate_, visitor &visitor_');

  IF UPPER('&mode_') = 'NAIVE' THEN
    SELECT COUNT(*) INTO v_cnt FROM visits WHERE visit_date = c_date AND slot = c_slot AND status <> 'CANCELLED';
    DBMS_OUTPUT.PUT_LINE('[' || ts || '] &label_ sees ' || v_cnt || ' of 5 places taken');
    IF v_cnt < 5 THEN
      INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (&inmate_, &visitor_, c_date, c_slot);
      DBMS_SESSION.SLEEP(&hold_);                        -- the slow clerk: row inserted but NOT yet committed
      COMMIT;
      v_status := 'BOOKED (no lock)';
    ELSE
      v_status := 'SLOT_FULL (checked by application)';
    END IF;
  ELSE
    sp_schedule_visit(&inmate_, &visitor_, c_date, c_slot, v_status, v_vid, v_msg, 'N');
    DBMS_OUTPUT.PUT_LINE('[' || ts || '] &label_ procedure returned ' || v_status || ' (transaction still open)');
    DBMS_SESSION.SLEEP(&hold_);                          -- hold the locks
    COMMIT;
  END IF;
  DBMS_OUTPUT.PUT_LINE('[' || ts || '] &label_ finished: ' || v_status);
END;
/

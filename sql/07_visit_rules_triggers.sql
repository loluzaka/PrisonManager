-- =============================================================================
-- 07_visit_rules_triggers.sql
-- Features : F13 (visit eligibility trigger), F16 (visit slot rules - trigger part)
-- Owner    : Member 2
-- RUN AS   : PRISON_OWNER, after 06_audit_trail.sql
--
-- TRG_BLOCK_CONFLICT_VISIT  BEFORE INSERT, row-level. Refuses a visit when the visitor is not
--                           APPROVED / is BLACKLISTED / has an active conflict with the inmate,
--                           or when the inmate is not ACTIVE. The refusal is written to
--                           AUDIT_LOG through an AUTONOMOUS transaction so it is not rolled
--                           back with the failed INSERT (the "denied visits" decision).
-- TRG_VISIT_SLOT_RULES      COMPOUND trigger. Enforces sentence period, max visits per inmate
--                           per week and max visitors per slot. A plain row trigger that counted
--                           rows of VISITS would raise ORA-04091 (mutating table); a compound
--                           trigger collects the keys row by row and counts in the AFTER
--                           STATEMENT section, when the table is stable again.
-- These triggers are the LAST LINE OF DEFENCE; sp_schedule_visit checks the same rules first
-- and returns friendly status codes.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

CREATE OR REPLACE TRIGGER trg_block_conflict_visit
BEFORE INSERT ON visits
FOR EACH ROW
DECLARE
  v_result VARCHAR2(30);
BEGIN
  v_result := fn_is_visitor_eligible(:NEW.visitor_id, :NEW.inmate_id);

  -- Unknown inmate / visitor: do nothing here, the FOREIGN KEY will reject the row (ORA-02291).
  IF v_result IN ('ELIGIBLE', 'NO_VISITOR', 'NO_INMATE') THEN
    RETURN;
  END IF;

  -- Log first (autonomous => survives the error below), then refuse.
  sp_log_audit_auto('VISITORS', 'VISIT_DENIED', :NEW.visitor_id,
    'trg_block_conflict_visit: inmate_id=' || :NEW.inmate_id ||
    '; date=' || TO_CHAR(:NEW.visit_date, 'YYYY-MM-DD') || '; slot=' || :NEW.slot ||
    '; reason=' || v_result);

  CASE v_result
    WHEN 'UNAPPROVED'      THEN RAISE_APPLICATION_ERROR(-20101, 'Visit refused: visitor is not approved');
    WHEN 'BLACKLISTED'     THEN RAISE_APPLICATION_ERROR(-20102, 'Visit refused: visitor is blacklisted');
    WHEN 'CONFLICT'        THEN RAISE_APPLICATION_ERROR(-20103, 'Visit refused: conflict exists between visitor and inmate');
    WHEN 'INMATE_INACTIVE' THEN RAISE_APPLICATION_ERROR(-20104, 'Visit refused: inmate is not ACTIVE');
  END CASE;
END trg_block_conflict_visit;
/

CREATE OR REPLACE TRIGGER trg_visit_slot_rules
FOR INSERT OR UPDATE OF visit_date, slot, status ON visits
COMPOUND TRIGGER

  TYPE t_key IS RECORD (inmate_id NUMBER, visitor_id NUMBER, visit_date DATE, slot VARCHAR2(11));
  TYPE t_keys IS TABLE OF t_key INDEX BY PLS_INTEGER;
  g_keys t_keys;                    -- rows touched by the current statement

  PROCEDURE refuse (p_key IN t_key, p_code IN NUMBER, p_reason IN VARCHAR2, p_msg IN VARCHAR2) IS
  BEGIN
    sp_log_audit_auto('VISITORS', 'VISIT_DENIED', p_key.visitor_id,
      'trg_visit_slot_rules: inmate_id=' || p_key.inmate_id ||
      '; date=' || TO_CHAR(p_key.visit_date, 'YYYY-MM-DD') || '; slot=' || p_key.slot ||
      '; reason=' || p_reason);
    RAISE_APPLICATION_ERROR(p_code, p_msg);
  END refuse;

  -- 1) per row, BEFORE the row is written: the sentence period (reads INMATES, not VISITS)
  BEFORE EACH ROW IS
    v_start DATE;
    v_end   DATE;
    v_key   t_key;
  BEGIN
    IF :NEW.status <> 'CANCELLED' THEN
      BEGIN
        SELECT sentence_start, sentence_end INTO v_start, v_end
          FROM inmates WHERE inmate_id = :NEW.inmate_id;
        IF :NEW.visit_date < v_start OR :NEW.visit_date > v_end THEN
          v_key.inmate_id := :NEW.inmate_id; v_key.visitor_id := :NEW.visitor_id;
          v_key.visit_date := :NEW.visit_date; v_key.slot := :NEW.slot;
          refuse(v_key, -20107, 'OUTSIDE_SENTENCE', 'Visit refused: date is outside the inmate''s sentence period');
        END IF;
      EXCEPTION WHEN NO_DATA_FOUND THEN NULL;   -- unknown inmate: the FOREIGN KEY reports it
      END;
    END IF;
  END BEFORE EACH ROW;

  -- 2) per row, AFTER the row is written: only REMEMBER it (no query on VISITS allowed here)
  AFTER EACH ROW IS
  BEGIN
    IF :NEW.status <> 'CANCELLED' THEN
      g_keys(g_keys.COUNT + 1).inmate_id  := :NEW.inmate_id;
      g_keys(g_keys.COUNT).visitor_id     := :NEW.visitor_id;
      g_keys(g_keys.COUNT).visit_date     := :NEW.visit_date;
      g_keys(g_keys.COUNT).slot           := :NEW.slot;
    END IF;
  END AFTER EACH ROW;

  -- 3) once per statement: the table is no longer mutating, so counting is allowed
  AFTER STATEMENT IS
    v_cnt NUMBER;
    v_max NUMBER;
  BEGIN
    FOR i IN 1 .. g_keys.COUNT LOOP
      SELECT COUNT(*) INTO v_cnt FROM visits
       WHERE inmate_id = g_keys(i).inmate_id AND status <> 'CANCELLED'
         AND TRUNC(visit_date, 'IW') = TRUNC(g_keys(i).visit_date, 'IW');
      IF v_cnt > pkg_prison_rules.c_max_visits_per_week THEN
        refuse(g_keys(i), -20105, 'WEEKLY_LIMIT',
               'Visit refused: inmate already has the maximum of ' ||
               pkg_prison_rules.c_max_visits_per_week || ' visits this week');
      END IF;

      SELECT max_visitors INTO v_max FROM visit_slots WHERE slot_code = g_keys(i).slot;
      SELECT COUNT(*) INTO v_cnt FROM visits
       WHERE visit_date = g_keys(i).visit_date AND slot = g_keys(i).slot AND status <> 'CANCELLED';
      IF v_cnt > v_max THEN
        refuse(g_keys(i), -20106, 'SLOT_FULL', 'Visit refused: slot ' || g_keys(i).slot || ' is full');
      END IF;
    END LOOP;
  END AFTER STATEMENT;

END trg_visit_slot_rules;
/

PROMPT 07_visit_rules_triggers.sql finished.

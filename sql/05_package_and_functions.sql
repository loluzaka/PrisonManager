-- =============================================================================
-- 05_package_and_functions.sql
-- Features : F19 (functions), F23 (user-defined exceptions), support for F13-F18
-- Owner    : Member 2
-- RUN AS   : PRISON_OWNER, after 04_seed_data.sql
--
-- PKG_PRISON_RULES  - the single place for business constants, user-defined exceptions with
--                     their ORA-20xxx codes, and a "message in a bottle" variable used to pass
--                     the transfer reason from sp_transfer_inmate to trigger trg_log_movement.
-- Functions         - FN_LEVEL_RANK, FN_INMATE_VISIT_COUNT, FN_VISITOR_VISIT_COUNT,
--                     FN_BLOCK_OCCUPANCY, FN_HAS_ACTIVE_CONFLICT, FN_IS_VISITOR_ELIGIBLE,
--                     FN_DAYS_REMAINING, FN_WEEKLY_VISIT_COUNT, FN_SLOT_VISIT_COUNT,
--                     FN_NEXT_FREE_SLOT.
-- PROCEDURE vs FUNCTION: a function RETURNs one value and can be used inside SELECT / WHERE;
-- a procedure returns values through OUT parameters and is called as a statement.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

CREATE OR REPLACE PACKAGE pkg_prison_rules AS
  -- business constants
  c_max_visits_per_week CONSTANT NUMBER := 3;

  -- hand-over of the reason text from sp_transfer_inmate to trg_log_movement
  g_transfer_reason VARCHAR2(200);

  -- user-defined exceptions bound to error numbers raised by triggers and procedures
  e_unapproved        EXCEPTION;  PRAGMA EXCEPTION_INIT(e_unapproved,        -20101);
  e_blacklisted       EXCEPTION;  PRAGMA EXCEPTION_INIT(e_blacklisted,       -20102);
  e_conflict          EXCEPTION;  PRAGMA EXCEPTION_INIT(e_conflict,          -20103);
  e_inmate_inactive   EXCEPTION;  PRAGMA EXCEPTION_INIT(e_inmate_inactive,   -20104);
  e_weekly_limit      EXCEPTION;  PRAGMA EXCEPTION_INIT(e_weekly_limit,      -20105);
  e_slot_full         EXCEPTION;  PRAGMA EXCEPTION_INIT(e_slot_full,         -20106);
  e_outside_sentence  EXCEPTION;  PRAGMA EXCEPTION_INIT(e_outside_sentence,  -20107);
  e_block_full        EXCEPTION;  PRAGMA EXCEPTION_INIT(e_block_full,        -20201);
  e_security_mismatch EXCEPTION;  PRAGMA EXCEPTION_INIT(e_security_mismatch, -20202);
  e_rival_in_block    EXCEPTION;  PRAGMA EXCEPTION_INIT(e_rival_in_block,    -20203);
  e_audit_immutable   EXCEPTION;  PRAGMA EXCEPTION_INIT(e_audit_immutable,   -20301);
END pkg_prison_rules;
/

-- LOW < MEDIUM < HIGH as numbers, so security levels can be compared with < and >.
CREATE OR REPLACE FUNCTION fn_level_rank (p_level IN VARCHAR2) RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN CASE UPPER(p_level) WHEN 'LOW' THEN 1 WHEN 'MEDIUM' THEN 2 WHEN 'HIGH' THEN 3 END;
END fn_level_rank;
/

-- Visits that really take (or took) place: SCHEDULED + COMPLETED.
CREATE OR REPLACE FUNCTION fn_inmate_visit_count (p_inmate_id IN NUMBER) RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM visits
   WHERE inmate_id = p_inmate_id AND status IN ('SCHEDULED','COMPLETED');
  RETURN v_count;
END fn_inmate_visit_count;
/

CREATE OR REPLACE FUNCTION fn_visitor_visit_count (p_visitor_id IN NUMBER) RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM visits
   WHERE visitor_id = p_visitor_id AND status IN ('SCHEDULED','COMPLETED');
  RETURN v_count;
END fn_visitor_visit_count;
/

-- Occupancy counts only ACTIVE inmates: released / transferred-out inmates free their bed.
CREATE OR REPLACE FUNCTION fn_block_occupancy (p_block_id IN NUMBER) RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM inmates
   WHERE block_id = p_block_id AND status = 'ACTIVE';
  RETURN v_count;
END fn_block_occupancy;
/

-- 1 when an unresolved, unexpired conflict links this visitor and inmate, else 0.
CREATE OR REPLACE FUNCTION fn_has_active_conflict (p_visitor_id IN NUMBER, p_inmate_id IN NUMBER)
  RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM conflicts
   WHERE visitor_id = p_visitor_id AND inmate_id = p_inmate_id
     AND resolved = 'N'
     AND (expiry_date IS NULL OR expiry_date >= TRUNC(SYSDATE));
  RETURN CASE WHEN v_count > 0 THEN 1 ELSE 0 END;
END fn_has_active_conflict;
/

-- THE eligibility rule. Used by trigger trg_block_conflict_visit AND by sp_schedule_visit, so
-- the rule lives in exactly one place. Returns 'ELIGIBLE' or the reason code:
-- NO_VISITOR, NO_INMATE, BLACKLISTED, UNAPPROVED, CONFLICT, INMATE_INACTIVE.
CREATE OR REPLACE FUNCTION fn_is_visitor_eligible (p_visitor_id IN NUMBER, p_inmate_id IN NUMBER)
  RETURN VARCHAR2 IS
  v_visitor_status visitors.approval_status%TYPE;
  v_inmate_status  inmates.status%TYPE;
BEGIN
  BEGIN
    SELECT approval_status INTO v_visitor_status FROM visitors WHERE visitor_id = p_visitor_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 'NO_VISITOR';
  END;
  BEGIN
    SELECT status INTO v_inmate_status FROM inmates WHERE inmate_id = p_inmate_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 'NO_INMATE';
  END;

  IF v_visitor_status = 'BLACKLISTED' THEN RETURN 'BLACKLISTED'; END IF;
  IF v_visitor_status <> 'APPROVED'   THEN RETURN 'UNAPPROVED';  END IF;
  IF fn_has_active_conflict(p_visitor_id, p_inmate_id) = 1 THEN RETURN 'CONFLICT'; END IF;
  IF v_inmate_status <> 'ACTIVE'      THEN RETURN 'INMATE_INACTIVE'; END IF;
  RETURN 'ELIGIBLE';
END fn_is_visitor_eligible;
/

-- Days of sentence left (0 if already over). NULL when the inmate does not exist.
CREATE OR REPLACE FUNCTION fn_days_remaining (p_inmate_id IN NUMBER) RETURN NUMBER IS
  v_end DATE;
BEGIN
  SELECT sentence_end INTO v_end FROM inmates WHERE inmate_id = p_inmate_id;
  RETURN GREATEST(v_end - TRUNC(SYSDATE), 0);
EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
END fn_days_remaining;
/

-- Non-cancelled visits of an inmate in the ISO week (Mon-Sun) that contains p_date.
CREATE OR REPLACE FUNCTION fn_weekly_visit_count (p_inmate_id IN NUMBER, p_date IN DATE) RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM visits
   WHERE inmate_id = p_inmate_id AND status <> 'CANCELLED'
     AND TRUNC(visit_date, 'IW') = TRUNC(p_date, 'IW');
  RETURN v_count;
END fn_weekly_visit_count;
/

CREATE OR REPLACE FUNCTION fn_slot_visit_count (p_date IN DATE, p_slot IN VARCHAR2) RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM visits
   WHERE visit_date = TRUNC(p_date) AND slot = p_slot AND status <> 'CANCELLED';
  RETURN v_count;
END fn_slot_visit_count;
/

-- First slot of the day that still has room AND where the inmate has no visit yet; NULL if none.
CREATE OR REPLACE FUNCTION fn_next_free_slot (p_inmate_id IN NUMBER, p_date IN DATE) RETURN VARCHAR2 IS
  v_has_visit NUMBER;
BEGIN
  FOR s IN (SELECT slot_code, max_visitors FROM visit_slots ORDER BY start_time) LOOP
    SELECT COUNT(*) INTO v_has_visit FROM visits
     WHERE inmate_id = p_inmate_id AND visit_date = TRUNC(p_date) AND slot = s.slot_code;
    IF v_has_visit = 0 AND fn_slot_visit_count(p_date, s.slot_code) < s.max_visitors THEN
      RETURN s.slot_code;
    END IF;
  END LOOP;
  RETURN NULL;
END fn_next_free_slot;
/

-- ---------------------------------------------------------------- demo: functions inside SELECT
COLUMN full_name FORMAT A22
SELECT inmate_id, full_name,
       fn_inmate_visit_count(inmate_id) AS visits,
       fn_days_remaining(inmate_id)     AS days_left
  FROM inmates WHERE inmate_id IN (1, 3, 8, 24, 50) ORDER BY inmate_id;

SELECT fn_is_visitor_eligible(36, 5)  AS blacklisted_visitor,
       fn_is_visitor_eligible(31, 5)  AS pending_visitor,
       fn_is_visitor_eligible(5, 3)   AS conflict_pair,
       fn_is_visitor_eligible(1, 46)  AS inactive_inmate,
       fn_is_visitor_eligible(1, 1)   AS ok_pair
  FROM dual;

PROMPT 05_package_and_functions.sql finished.

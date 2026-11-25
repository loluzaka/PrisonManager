-- =============================================================================
-- 06_audit_trail.sql
-- Feature : F22 (tamper-proof audit trail)
-- Owner   : Member 2
-- RUN AS  : PRISON_OWNER, after 05_package_and_functions.sql
--
-- Contents
--   SP_LOG_AUDIT          writes an audit row INSIDE the caller's transaction
--                         (rolled back together with the change it describes).
--   SP_LOG_AUDIT_AUTO     writes an audit row in an AUTONOMOUS transaction and commits it
--                         on its own - used for DENIED visits, which must survive the
--                         rollback caused by the error that rejects them.
--   TRG_AUDIT_LOG_IMMUTABLE  makes AUDIT_LOG append-only: UPDATE and DELETE raise ORA-20301.
--   TRG_AUDIT_INMATES / _VISITORS / _VISITS  record old and new values of every change.
--   FN_DIFF               helper that builds "column: old -> new; " text, NULL-safe.
-- Least privilege (ordinary roles may only INSERT / SELECT on AUDIT_LOG) is granted in script 17.
-- LIMITATION: the schema owner could still TRUNCATE or DROP the table (DDL); that is why only
-- PRISON_OWNER holds those privileges and no role is ever granted them.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

CREATE OR REPLACE PROCEDURE sp_log_audit (
  p_table_name IN VARCHAR2,
  p_action     IN VARCHAR2,
  p_record_id  IN NUMBER,
  p_details    IN VARCHAR2
) IS
BEGIN
  INSERT INTO audit_log (table_name, action_type, record_id, details)
  VALUES (p_table_name, p_action, p_record_id, SUBSTR(p_details, 1, 4000));
END sp_log_audit;
/

CREATE OR REPLACE PROCEDURE sp_log_audit_auto (
  p_table_name IN VARCHAR2,
  p_action     IN VARCHAR2,
  p_record_id  IN NUMBER,
  p_details    IN VARCHAR2
) IS
  PRAGMA AUTONOMOUS_TRANSACTION;          -- own transaction: its COMMIT does not touch the caller's work
BEGIN
  INSERT INTO audit_log (table_name, action_type, record_id, details)
  VALUES (p_table_name, p_action, p_record_id, SUBSTR(p_details, 1, 4000));
  COMMIT;                                  -- mandatory: an autonomous transaction must end with COMMIT or ROLLBACK
END sp_log_audit_auto;
/

CREATE OR REPLACE TRIGGER trg_audit_log_immutable
BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW
BEGIN
  RAISE_APPLICATION_ERROR(-20301,
    'AUDIT_LOG is append-only: ' || CASE WHEN UPDATING THEN 'UPDATE' ELSE 'DELETE' END || ' is not allowed');
END trg_audit_log_immutable;
/

-- NULL-safe "column: old -> new; " (empty string when nothing changed)
CREATE OR REPLACE FUNCTION fn_diff (p_col IN VARCHAR2, p_old IN VARCHAR2, p_new IN VARCHAR2)
  RETURN VARCHAR2 DETERMINISTIC IS
BEGIN
  IF p_old = p_new OR (p_old IS NULL AND p_new IS NULL) THEN
    RETURN NULL;
  END IF;
  RETURN p_col || ': ' || NVL(p_old, 'NULL') || ' -> ' || NVL(p_new, 'NULL') || '; ';
END fn_diff;
/

-- ---------------------------------------------------------------- INMATES
-- A block_id-only change is skipped here: trg_log_movement records it as a TRANSFER.
CREATE OR REPLACE TRIGGER trg_audit_inmates
AFTER INSERT OR UPDATE OR DELETE ON inmates
FOR EACH ROW
DECLARE
  v_details VARCHAR2(4000);
BEGIN
  IF INSERTING THEN
    sp_log_audit('INMATES', 'INSERT', :NEW.inmate_id,
      'inmate_no=' || :NEW.inmate_no || '; name=' || :NEW.full_name ||
      '; block_id=' || :NEW.block_id || '; risk=' || :NEW.risk_level || '; status=' || :NEW.status);
  ELSIF UPDATING THEN
    v_details := fn_diff('full_name',      :OLD.full_name,                :NEW.full_name)
              || fn_diff('status',         :OLD.status,                   :NEW.status)
              || fn_diff('risk_level',     :OLD.risk_level,               :NEW.risk_level)
              || fn_diff('sentence_start', TO_CHAR(:OLD.sentence_start, 'YYYY-MM-DD'),
                                           TO_CHAR(:NEW.sentence_start, 'YYYY-MM-DD'))
              || fn_diff('sentence_end',   TO_CHAR(:OLD.sentence_end, 'YYYY-MM-DD'),
                                           TO_CHAR(:NEW.sentence_end, 'YYYY-MM-DD'));
    IF v_details IS NOT NULL THEN
      sp_log_audit('INMATES', 'UPDATE', :NEW.inmate_id, v_details);
    END IF;
  ELSE
    sp_log_audit('INMATES', 'DELETE', :OLD.inmate_id,
      'inmate_no=' || :OLD.inmate_no || '; name=' || :OLD.full_name || '; status=' || :OLD.status);
  END IF;
END trg_audit_inmates;
/

-- ---------------------------------------------------------------- VISITORS
CREATE OR REPLACE TRIGGER trg_audit_visitors
AFTER INSERT OR UPDATE OR DELETE ON visitors
FOR EACH ROW
DECLARE
  v_details VARCHAR2(4000);
BEGIN
  IF INSERTING THEN
    sp_log_audit('VISITORS', 'INSERT', :NEW.visitor_id,
      'name=' || :NEW.full_name || '; id_type=' || :NEW.id_proof_type ||
      '; approval_status=' || :NEW.approval_status);
  ELSIF UPDATING THEN
    v_details := fn_diff('approval_status',  :OLD.approval_status,  :NEW.approval_status)
              || fn_diff('full_name',        :OLD.full_name,        :NEW.full_name)
              || fn_diff('id_proof_number',  :OLD.id_proof_number,  :NEW.id_proof_number)
              || fn_diff('phone',            :OLD.phone,            :NEW.phone);
    IF v_details IS NOT NULL THEN
      sp_log_audit('VISITORS', 'UPDATE', :NEW.visitor_id, v_details);
    END IF;
  ELSE
    sp_log_audit('VISITORS', 'DELETE', :OLD.visitor_id,
      'name=' || :OLD.full_name || '; approval_status=' || :OLD.approval_status);
  END IF;
END trg_audit_visitors;
/

-- ---------------------------------------------------------------- VISITS
-- A successful INSERT is an allowed visit attempt (VISIT_BOOKED); denied ones are logged by
-- trg_block_conflict_visit / sp_schedule_visit through sp_log_audit_auto.
CREATE OR REPLACE TRIGGER trg_audit_visits
AFTER INSERT OR UPDATE OR DELETE ON visits
FOR EACH ROW
DECLARE
  v_details VARCHAR2(4000);
BEGIN
  IF INSERTING THEN
    sp_log_audit('VISITS', 'VISIT_BOOKED', :NEW.visit_id,
      'inmate_id=' || :NEW.inmate_id || '; visitor_id=' || :NEW.visitor_id ||
      '; date=' || TO_CHAR(:NEW.visit_date, 'YYYY-MM-DD') || '; slot=' || :NEW.slot);
  ELSIF UPDATING THEN
    v_details := fn_diff('status',     :OLD.status, :NEW.status)
              || fn_diff('visit_date', TO_CHAR(:OLD.visit_date, 'YYYY-MM-DD'), TO_CHAR(:NEW.visit_date, 'YYYY-MM-DD'))
              || fn_diff('slot',       :OLD.slot,   :NEW.slot);
    IF v_details IS NOT NULL THEN
      sp_log_audit('VISITS', 'UPDATE', :NEW.visit_id, v_details);
    END IF;
  ELSE
    sp_log_audit('VISITS', 'DELETE', :OLD.visit_id,
      'inmate_id=' || :OLD.inmate_id || '; visitor_id=' || :OLD.visitor_id ||
      '; date=' || TO_CHAR(:OLD.visit_date, 'YYYY-MM-DD'));
  END IF;
END trg_audit_visits;
/

PROMPT 06_audit_trail.sql finished.

-- =============================================================================
-- 09_procedures.sql
-- Features : F14 (conflict management), F17 (sp_schedule_visit), F18 (sp_transfer_inmate),
--            F23 (exception handling), F24 (SAVEPOINT / COMMIT / ROLLBACK / row locking)
-- Owner    : Member 2
-- RUN AS   : PRISON_OWNER, after 08_inmate_rules_triggers.sql
--
-- Every procedure returns a STATUS CODE and a MESSAGE through OUT parameters instead of
-- letting a raw ORA- error reach the user (F23). Procedures that change data begin with a
-- SAVEPOINT; on any failure they ROLLBACK TO that savepoint (only their own work is undone)
-- and on success they COMMIT - unless p_auto_commit = 'N', which lets the caller keep the
-- transaction (and its locks) open. That option is what the two-session demo (F24) uses.
--
--   SP_REGISTER_VISITOR   SP_SET_VISITOR_STATUS   SP_ADD_CONFLICT   SP_RESOLVE_CONFLICT
--   SP_ADD_INMATE_RIVALRY SP_SCHEDULE_VISIT       SP_TRANSFER_INMATE
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

-- ---------------------------------------------------------------- visitor registration
CREATE OR REPLACE PROCEDURE sp_register_visitor (
  p_full_name       IN  VARCHAR2,
  p_id_proof_type   IN  VARCHAR2,
  p_id_proof_number IN  VARCHAR2,
  p_phone           IN  VARCHAR2,
  p_visitor_id      OUT NUMBER,
  p_status          OUT VARCHAR2,
  p_message         OUT VARCHAR2
) IS
BEGIN
  INSERT INTO visitors (full_name, id_proof_type, id_proof_number, phone)
  VALUES (TRIM(p_full_name), UPPER(TRIM(p_id_proof_type)), TRIM(p_id_proof_number), p_phone)
  RETURNING visitor_id INTO p_visitor_id;                 -- approval_status defaults to PENDING
  COMMIT;
  p_status  := 'REGISTERED';
  p_message := 'Visitor ' || p_visitor_id || ' registered with status PENDING';
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN                              -- UNIQUE (id_proof_type, id_proof_number)
    ROLLBACK;
    p_visitor_id := NULL; p_status := 'DUPLICATE_ID';
    p_message := 'A visitor with this ID proof is already registered';
  WHEN OTHERS THEN
    ROLLBACK;
    p_visitor_id := NULL;
    IF SQLCODE IN (-2290, -1400) THEN                     -- CHECK violated / NOT NULL missing
      p_status := 'INVALID_DATA'; p_message := 'Invalid or missing visitor data: ' || SQLERRM;
    ELSE
      p_status := 'ERROR';        p_message := SQLERRM;
    END IF;
END sp_register_visitor;
/

-- Approve / reject / blacklist. Blacklisting or rejecting also cancels future SCHEDULED visits.
CREATE OR REPLACE PROCEDURE sp_set_visitor_status (
  p_visitor_id IN  NUMBER,
  p_new_status IN  VARCHAR2,
  p_status     OUT VARCHAR2,
  p_message    OUT VARCHAR2
) IS
  v_cancelled NUMBER := 0;
  v_new       VARCHAR2(12) := UPPER(TRIM(p_new_status));
BEGIN
  SAVEPOINT sp_set_vs;
  UPDATE visitors SET approval_status = v_new WHERE visitor_id = p_visitor_id;
  IF SQL%ROWCOUNT = 0 THEN                               -- implicit cursor attribute
    p_status := 'NOT_FOUND'; p_message := 'Visitor ' || p_visitor_id || ' does not exist';
    RETURN;
  END IF;
  IF v_new IN ('BLACKLISTED', 'REJECTED') THEN
    UPDATE visits SET status = 'CANCELLED'
     WHERE visitor_id = p_visitor_id AND status = 'SCHEDULED' AND visit_date >= TRUNC(SYSDATE);
    v_cancelled := SQL%ROWCOUNT;
  END IF;
  COMMIT;
  p_status  := 'UPDATED';
  p_message := 'Visitor ' || p_visitor_id || ' is now ' || v_new ||
               CASE WHEN v_cancelled > 0 THEN '; ' || v_cancelled || ' future visit(s) cancelled' END;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK TO SAVEPOINT sp_set_vs;
    IF SQLCODE = -2290 THEN
      p_status := 'INVALID_DATA'; p_message := 'Status must be PENDING, APPROVED, REJECTED or BLACKLISTED';
    ELSE
      p_status := 'ERROR'; p_message := SQLERRM;
    END IF;
END sp_set_visitor_status;
/

-- ---------------------------------------------------------------- conflict management (F14)
CREATE OR REPLACE PROCEDURE sp_add_conflict (
  p_inmate_id  IN  NUMBER,
  p_visitor_id IN  NUMBER,
  p_reason     IN  VARCHAR2,
  p_expiry     IN  DATE,
  p_status     OUT VARCHAR2,
  p_message    OUT VARCHAR2
) IS
  v_cancelled NUMBER;
BEGIN
  SAVEPOINT sp_add_conf;
  BEGIN
    INSERT INTO conflicts (inmate_id, visitor_id, reason, expiry_date)
    VALUES (p_inmate_id, p_visitor_id, UPPER(p_reason), p_expiry);
    p_status := 'CONFLICT_ADDED';
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN                           -- the pair exists (maybe resolved): re-activate it
      UPDATE conflicts
         SET resolved = 'N', resolved_on = NULL, reason = UPPER(p_reason),
             flagged_date = TRUNC(SYSDATE), expiry_date = p_expiry
       WHERE inmate_id = p_inmate_id AND visitor_id = p_visitor_id;
      p_status := 'CONFLICT_REACTIVATED';
  END;
  UPDATE visits SET status = 'CANCELLED'
   WHERE inmate_id = p_inmate_id AND visitor_id = p_visitor_id
     AND status = 'SCHEDULED' AND visit_date >= TRUNC(SYSDATE);
  v_cancelled := SQL%ROWCOUNT;
  COMMIT;
  p_message := 'Conflict recorded' ||
               CASE WHEN v_cancelled > 0 THEN '; ' || v_cancelled || ' future visit(s) cancelled' END;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK TO SAVEPOINT sp_add_conf;
    IF SQLCODE IN (-2291) THEN
      p_status := 'NOT_FOUND'; p_message := 'Inmate or visitor does not exist';
    ELSIF SQLCODE = -2290 THEN
      p_status := 'INVALID_DATA'; p_message := 'Invalid reason or expiry date';
    ELSE
      p_status := 'ERROR'; p_message := SQLERRM;
    END IF;
END sp_add_conflict;
/

CREATE OR REPLACE PROCEDURE sp_resolve_conflict (
  p_conflict_id IN  NUMBER,
  p_status      OUT VARCHAR2,
  p_message     OUT VARCHAR2
) IS
  v_resolved conflicts.resolved%TYPE;
BEGIN
  SELECT resolved INTO v_resolved FROM conflicts WHERE conflict_id = p_conflict_id FOR UPDATE;
  IF v_resolved = 'Y' THEN
    ROLLBACK;
    p_status := 'ALREADY_RESOLVED'; p_message := 'Conflict ' || p_conflict_id || ' was already resolved';
    RETURN;
  END IF;
  UPDATE conflicts SET resolved = 'Y', resolved_on = TRUNC(SYSDATE) WHERE conflict_id = p_conflict_id;
  COMMIT;
  p_status := 'RESOLVED'; p_message := 'Conflict ' || p_conflict_id || ' resolved';
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    p_status := 'NOT_FOUND'; p_message := 'Conflict ' || p_conflict_id || ' does not exist';
  WHEN OTHERS THEN
    ROLLBACK; p_status := 'ERROR'; p_message := SQLERRM;
END sp_resolve_conflict;
/

CREATE OR REPLACE PROCEDURE sp_add_inmate_rivalry (
  p_inmate_1 IN  NUMBER,
  p_inmate_2 IN  NUMBER,
  p_reason   IN  VARCHAR2,
  p_status   OUT VARCHAR2,
  p_message  OUT VARCHAR2
) IS
  v_a NUMBER := LEAST(p_inmate_1, p_inmate_2);           -- store each pair once, smaller id first
  v_b NUMBER := GREATEST(p_inmate_1, p_inmate_2);
BEGIN
  INSERT INTO inmate_conflicts (inmate_a, inmate_b, reason) VALUES (v_a, v_b, UPPER(p_reason));
  COMMIT;
  p_status := 'RIVALRY_ADDED'; p_message := 'Inmates ' || v_a || ' and ' || v_b || ' are now rivals';
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    ROLLBACK; p_status := 'ALREADY_EXISTS'; p_message := 'This rivalry is already recorded';
  WHEN OTHERS THEN
    ROLLBACK;
    IF SQLCODE = -2291 THEN p_status := 'NOT_FOUND'; p_message := 'One of the inmates does not exist';
    ELSIF SQLCODE = -2290 THEN p_status := 'INVALID_DATA'; p_message := 'An inmate cannot be a rival of itself / bad reason';
    ELSE p_status := 'ERROR'; p_message := SQLERRM; END IF;
END sp_add_inmate_rivalry;
/

-- ---------------------------------------------------------------- F17  sp_schedule_visit
-- Status codes: BOOKED | DENIED_NO_INMATE | DENIED_NO_VISITOR | DENIED_INVALID_SLOT |
--   DENIED_UNAPPROVED | DENIED_BLACKLISTED | DENIED_CONFLICT | DENIED_INMATE_INACTIVE |
--   DENIED_PAST_DATE | DENIED_OUTSIDE_SENTENCE | DENIED_DUPLICATE | DENIED_WEEKLY_LIMIT |
--   DENIED_FACILITY |
--   SLOT_FULL | ERROR
-- Lock order (always the same, so sessions can never deadlock): inmate row, then slot row.
CREATE OR REPLACE PROCEDURE sp_schedule_visit (
  p_inmate_id   IN  NUMBER,
  p_visitor_id  IN  NUMBER,
  p_visit_date  IN  DATE,
  p_slot        IN  VARCHAR2,
  p_status      OUT VARCHAR2,
  p_visit_id    OUT NUMBER,
  p_message     OUT VARCHAR2,
  p_auto_commit IN  VARCHAR2 DEFAULT 'Y'
) IS
  v_date      DATE := TRUNC(p_visit_date);
  v_start     DATE;
  v_end       DATE;
  v_max_slot  visit_slots.max_visitors%TYPE;
  v_elig      VARCHAR2(30);
  v_cnt       NUMBER;
  v_facility  NUMBER;
  v_access_facility NUMBER;

  -- local helper: record the refusal (autonomous, so it survives), undo our own work, set outputs
  PROCEDURE deny (p_code IN VARCHAR2, p_msg IN VARCHAR2) IS
  BEGIN
    sp_log_audit_auto('VISITORS', 'VISIT_DENIED', p_visitor_id,
      'sp_schedule_visit: inmate_id=' || p_inmate_id || '; date=' || TO_CHAR(v_date, 'YYYY-MM-DD') ||
      '; slot=' || p_slot || '; reason=' || p_code);
    ROLLBACK TO SAVEPOINT sp_visit_start;               -- also releases the row locks taken below
    p_status := p_code; p_message := p_msg; p_visit_id := NULL;
  END deny;
BEGIN
  SAVEPOINT sp_visit_start;
  p_visit_id := NULL;

  -- 1. lock and read the inmate (serialises bookings for the same inmate: weekly limit)
  BEGIN
    SELECT sentence_start, sentence_end INTO v_start, v_end
      FROM inmates WHERE inmate_id = p_inmate_id FOR UPDATE;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    deny('DENIED_NO_INMATE', 'Inmate ' || p_inmate_id || ' does not exist'); RETURN;
  END;

  BEGIN
    SELECT b.facility_id INTO v_facility
      FROM inmates i JOIN blocks b ON b.block_id = i.block_id
     WHERE i.inmate_id = p_inmate_id;
    SELECT facility_id INTO v_access_facility
      FROM staff_access
     WHERE db_username = SYS_CONTEXT('USERENV', 'SESSION_USER');
  EXCEPTION WHEN NO_DATA_FOUND THEN
    deny('DENIED_FACILITY', 'No facility access is assigned to this database user'); RETURN;
  END;
  IF v_access_facility IS NOT NULL AND v_access_facility <> v_facility THEN
    deny('DENIED_FACILITY', 'This database user cannot book visits for that facility'); RETURN;
  END IF;

  -- 2. lock and read the slot (serialises bookings for the same slot: slot capacity)
  BEGIN
    SELECT max_visitors INTO v_max_slot FROM visit_slots WHERE slot_code = p_slot FOR UPDATE;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    deny('DENIED_INVALID_SLOT', 'Slot ' || p_slot || ' is not a valid visit slot'); RETURN;
  END;

  -- 3. eligibility: visitor approved, not blacklisted, no conflict, inmate ACTIVE (shared function)
  v_elig := fn_is_visitor_eligible(p_visitor_id, p_inmate_id);
  IF v_elig <> 'ELIGIBLE' THEN
    deny('DENIED_' || v_elig,
         CASE v_elig WHEN 'NO_VISITOR'      THEN 'Visitor ' || p_visitor_id || ' does not exist'
                     WHEN 'UNAPPROVED'      THEN 'Visitor is not approved'
                     WHEN 'BLACKLISTED'     THEN 'Visitor is blacklisted'
                     WHEN 'CONFLICT'        THEN 'A conflict exists between this visitor and inmate'
                     WHEN 'INMATE_INACTIVE' THEN 'Inmate is not ACTIVE'
                     ELSE v_elig END);
    RETURN;
  END IF;

  -- 4. date rules
  IF v_date < TRUNC(SYSDATE) THEN
    deny('DENIED_PAST_DATE', 'Visits cannot be booked in the past'); RETURN;
  END IF;
  IF v_date < v_start OR v_date > v_end THEN
    deny('DENIED_OUTSIDE_SENTENCE', 'Date is outside the inmate''s sentence period'); RETURN;
  END IF;

  -- 5. slot rules (locks held, so these counts cannot change under us)
  SELECT COUNT(*) INTO v_cnt FROM visits
   WHERE inmate_id = p_inmate_id AND visit_date = v_date AND slot = p_slot;
  IF v_cnt > 0 THEN
    deny('DENIED_DUPLICATE', 'The inmate already has a booking in this slot'); RETURN;
  END IF;
  IF fn_weekly_visit_count(p_inmate_id, v_date) >= pkg_prison_rules.c_max_visits_per_week THEN
    deny('DENIED_WEEKLY_LIMIT', 'Inmate already has ' || pkg_prison_rules.c_max_visits_per_week ||
                                ' visits in that week'); RETURN;
  END IF;
  IF fn_slot_visit_count(v_date, p_slot) >= v_max_slot THEN
    deny('SLOT_FULL', 'Slot ' || p_slot || ' is full on ' || TO_CHAR(v_date, 'YYYY-MM-DD')); RETURN;
  END IF;

  -- 6. all checks passed: book (triggers re-verify everything as a safety net)
  INSERT INTO visits (inmate_id, visitor_id, visit_date, slot)
  VALUES (p_inmate_id, p_visitor_id, v_date, p_slot)
  RETURNING visit_id INTO p_visit_id;

  IF UPPER(p_auto_commit) = 'Y' THEN COMMIT; END IF;
  p_status := 'BOOKED'; p_message := 'Visit ' || p_visit_id || ' booked';

EXCEPTION
  WHEN pkg_prison_rules.e_slot_full        THEN deny('SLOT_FULL', 'Slot is full');
  WHEN pkg_prison_rules.e_weekly_limit     THEN deny('DENIED_WEEKLY_LIMIT', 'Weekly visit limit reached');
  WHEN pkg_prison_rules.e_outside_sentence THEN deny('DENIED_OUTSIDE_SENTENCE', 'Date outside sentence period');
  WHEN pkg_prison_rules.e_blacklisted      THEN deny('DENIED_BLACKLISTED', 'Visitor is blacklisted');
  WHEN pkg_prison_rules.e_unapproved       THEN deny('DENIED_UNAPPROVED', 'Visitor is not approved');
  WHEN pkg_prison_rules.e_conflict         THEN deny('DENIED_CONFLICT', 'Visitor/inmate conflict');
  WHEN pkg_prison_rules.e_inmate_inactive  THEN deny('DENIED_INMATE_INACTIVE', 'Inmate is not ACTIVE');
  WHEN DUP_VAL_ON_INDEX                    THEN deny('DENIED_DUPLICATE', 'Duplicate booking');
  WHEN OTHERS THEN
    ROLLBACK TO SAVEPOINT sp_visit_start;
    p_status := 'ERROR'; p_message := SUBSTR(SQLERRM, 1, 400); p_visit_id := NULL;
END sp_schedule_visit;
/

-- ---------------------------------------------------------------- F18  sp_transfer_inmate
-- Status codes: TRANSFERRED | NOT_FOUND | INMATE_NOT_ACTIVE | BLOCK_NOT_FOUND | SAME_BLOCK |
--   BLOCK_FULL | SECURITY_MISMATCH | RIVAL_IN_BLOCK | ERROR
-- The UPDATE fires trg_log_movement, which writes the MOVEMENTS row and the TRANSFER audit row;
-- trg_inmate_placement_rules re-checks capacity / security as a safety net.
CREATE OR REPLACE PROCEDURE sp_transfer_inmate (
  p_inmate_id   IN  NUMBER,
  p_to_block_id IN  NUMBER,
  p_reason      IN  VARCHAR2,
  p_status      OUT VARCHAR2,
  p_message     OUT VARCHAR2,
  p_auto_commit IN  VARCHAR2 DEFAULT 'Y'
) IS
  v_from_block  inmates.block_id%TYPE;
  v_inm_status  inmates.status%TYPE;
  v_risk        inmates.risk_level%TYPE;
  v_capacity    blocks.capacity%TYPE;
  v_security    blocks.security_level%TYPE;
  v_block_name  blocks.block_name%TYPE;
  v_rivals      NUMBER;

  PROCEDURE fail (p_code IN VARCHAR2, p_msg IN VARCHAR2) IS
  BEGIN
    ROLLBACK TO SAVEPOINT sp_transfer_start;            -- undo only this procedure's work, release locks
    p_status := p_code; p_message := p_msg;
  END fail;
BEGIN
  SAVEPOINT sp_transfer_start;

  -- 1. lock the inmate row (FOR UPDATE) - nobody else can change or move this inmate now
  BEGIN
    SELECT block_id, status, risk_level INTO v_from_block, v_inm_status, v_risk
      FROM inmates WHERE inmate_id = p_inmate_id FOR UPDATE;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    fail('NOT_FOUND', 'Inmate ' || p_inmate_id || ' does not exist'); RETURN;
  END;
  IF v_inm_status <> 'ACTIVE' THEN
    fail('INMATE_NOT_ACTIVE', 'Only ACTIVE inmates can be moved (status is ' || v_inm_status || ')'); RETURN;
  END IF;

  -- 2. lock the target block row: concurrent transfers INTO this block now queue up here,
  --    so the capacity count below can never be out of date
  BEGIN
    SELECT capacity, security_level, block_name INTO v_capacity, v_security, v_block_name
      FROM blocks WHERE block_id = p_to_block_id FOR UPDATE;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    fail('BLOCK_NOT_FOUND', 'Block ' || p_to_block_id || ' does not exist'); RETURN;
  END;
  IF v_from_block = p_to_block_id THEN
    fail('SAME_BLOCK', 'Inmate is already in ' || v_block_name); RETURN;
  END IF;

  -- 3. capacity, security level, rivals
  IF fn_block_occupancy(p_to_block_id) >= v_capacity THEN
    fail('BLOCK_FULL', v_block_name || ' is full (' || v_capacity || '/' || v_capacity || ')'); RETURN;
  END IF;
  IF fn_level_rank(v_risk) > fn_level_rank(v_security) THEN
    fail('SECURITY_MISMATCH', 'Inmate risk ' || v_risk || ' exceeds ' || v_block_name ||
                              ' security level ' || v_security); RETURN;
  END IF;
  SELECT COUNT(*) INTO v_rivals
    FROM inmate_conflicts ic
    JOIN inmates other ON other.inmate_id = CASE WHEN ic.inmate_a = p_inmate_id THEN ic.inmate_b ELSE ic.inmate_a END
   WHERE (ic.inmate_a = p_inmate_id OR ic.inmate_b = p_inmate_id)
     AND ic.resolved = 'N' AND other.status = 'ACTIVE' AND other.block_id = p_to_block_id;
  IF v_rivals > 0 THEN
    fail('RIVAL_IN_BLOCK', 'A rival of this inmate is housed in ' || v_block_name); RETURN;
  END IF;

  -- 4. do the move; the triggers write MOVEMENTS + AUDIT_LOG in the SAME transaction
  pkg_prison_rules.g_transfer_reason := p_reason;
  UPDATE inmates SET block_id = p_to_block_id WHERE inmate_id = p_inmate_id;
  pkg_prison_rules.g_transfer_reason := NULL;

  IF UPPER(p_auto_commit) = 'Y' THEN COMMIT; END IF;
  p_status  := 'TRANSFERRED';
  p_message := 'Inmate ' || p_inmate_id || ' moved from block ' || v_from_block || ' to ' || v_block_name;

EXCEPTION
  WHEN pkg_prison_rules.e_block_full        THEN pkg_prison_rules.g_transfer_reason := NULL; fail('BLOCK_FULL', 'Block is full');
  WHEN pkg_prison_rules.e_security_mismatch THEN pkg_prison_rules.g_transfer_reason := NULL; fail('SECURITY_MISMATCH', 'Security level too low');
  WHEN pkg_prison_rules.e_rival_in_block    THEN pkg_prison_rules.g_transfer_reason := NULL; fail('RIVAL_IN_BLOCK', 'Rival in block');
  WHEN OTHERS THEN
    pkg_prison_rules.g_transfer_reason := NULL;
    ROLLBACK TO SAVEPOINT sp_transfer_start;
    p_status := 'ERROR'; p_message := SUBSTR(SQLERRM, 1, 400);
END sp_transfer_inmate;
/

PROMPT 09_procedures.sql finished.

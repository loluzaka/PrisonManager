-- =============================================================================
-- 08_inmate_rules_triggers.sql
-- Features : F15 (block capacity and security-level rules), F21 (movement logging trigger)
-- Owner    : Member 2
-- RUN AS   : PRISON_OWNER, after 07_visit_rules_triggers.sql
--
-- TRG_INMATE_PLACEMENT_RULES  COMPOUND trigger on INMATES (safety net behind sp_transfer_inmate)
--     BEFORE EACH ROW  - risk level may not exceed the block's security level (reads BLOCKS only)
--     AFTER EACH ROW   - remember which blocks / inmates were touched (no query on INMATES here)
--     AFTER STATEMENT  - capacity check (count of ACTIVE inmates <= capacity) and rival check.
--     A row trigger that counted INMATES would hit ORA-04091 (mutating table).
-- TRG_LOG_MOVEMENT            AFTER INSERT OR UPDATE OF block_id, row-level. Writes MOVEMENTS and a
--     TRANSFER audit row for every admission and every block change, even a direct UPDATE,
--     so nobody can move an inmate without a trace. Uses :OLD and :NEW.
-- Race-condition note: these triggers see only COMMITTED rows of other sessions, so two sessions
-- filling the last bed at once could both pass. sp_transfer_inmate prevents that by locking the
-- target block row first (see F24 demo in scripts 20 / 21).
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

CREATE OR REPLACE TRIGGER trg_inmate_placement_rules
FOR INSERT OR UPDATE OF block_id, status, risk_level ON inmates
COMPOUND TRIGGER

  TYPE t_placement IS RECORD (inmate_id NUMBER, block_id NUMBER);
  TYPE t_placements IS TABLE OF t_placement INDEX BY PLS_INTEGER;
  g_rows t_placements;

  BEFORE EACH ROW IS
    v_security blocks.security_level%TYPE;
  BEGIN
    IF :NEW.status = 'ACTIVE' THEN
      BEGIN
        SELECT security_level INTO v_security FROM blocks WHERE block_id = :NEW.block_id;
        IF fn_level_rank(:NEW.risk_level) > fn_level_rank(v_security) THEN
          RAISE_APPLICATION_ERROR(-20202,
            'Placement refused: inmate risk ' || :NEW.risk_level ||
            ' exceeds block security level ' || v_security);
        END IF;
      EXCEPTION WHEN NO_DATA_FOUND THEN NULL;     -- unknown block: the FOREIGN KEY reports it
      END;
    END IF;
  END BEFORE EACH ROW;

  AFTER EACH ROW IS
  BEGIN
    IF :NEW.status = 'ACTIVE' THEN
      g_rows(g_rows.COUNT + 1).inmate_id := :NEW.inmate_id;
      g_rows(g_rows.COUNT).block_id      := :NEW.block_id;
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_occupied NUMBER;
    v_capacity NUMBER;
    v_name     blocks.block_name%TYPE;
    v_rivals   NUMBER;
  BEGIN
    FOR i IN 1 .. g_rows.COUNT LOOP
      SELECT capacity, block_name INTO v_capacity, v_name FROM blocks WHERE block_id = g_rows(i).block_id;
      SELECT COUNT(*) INTO v_occupied FROM inmates
       WHERE block_id = g_rows(i).block_id AND status = 'ACTIVE';
      IF v_occupied > v_capacity THEN
        RAISE_APPLICATION_ERROR(-20201,
          'Placement refused: block ' || v_name || ' is full (capacity ' || v_capacity || ')');
      END IF;

      SELECT COUNT(*) INTO v_rivals
        FROM inmate_conflicts ic
        JOIN inmates other ON other.inmate_id = CASE WHEN ic.inmate_a = g_rows(i).inmate_id
                                                     THEN ic.inmate_b ELSE ic.inmate_a END
       WHERE (ic.inmate_a = g_rows(i).inmate_id OR ic.inmate_b = g_rows(i).inmate_id)
         AND ic.resolved = 'N' AND other.status = 'ACTIVE' AND other.block_id = g_rows(i).block_id;
      IF v_rivals > 0 THEN
        RAISE_APPLICATION_ERROR(-20203,
          'Placement refused: a rival of inmate ' || g_rows(i).inmate_id || ' lives in block ' || v_name);
      END IF;
    END LOOP;
  END AFTER STATEMENT;

END trg_inmate_placement_rules;
/

CREATE OR REPLACE TRIGGER trg_log_movement
AFTER INSERT OR UPDATE OF block_id ON inmates
FOR EACH ROW
DECLARE
  v_reason movements.reason%TYPE;
BEGIN
  IF INSERTING THEN
    INSERT INTO movements (inmate_id, from_block, to_block, reason)
    VALUES (:NEW.inmate_id, NULL, :NEW.block_id, 'ADMISSION');
  ELSIF UPDATING AND :OLD.block_id <> :NEW.block_id THEN
    v_reason := NVL(pkg_prison_rules.g_transfer_reason, 'Direct update of INMATES.block_id');
    INSERT INTO movements (inmate_id, from_block, to_block, reason)
    VALUES (:NEW.inmate_id, :OLD.block_id, :NEW.block_id, v_reason);
    sp_log_audit('INMATES', 'TRANSFER', :NEW.inmate_id,
      'Block ' || :OLD.block_id || ' -> ' || :NEW.block_id || '; reason=' || v_reason);
  END IF;
END trg_log_movement;
/

PROMPT 08_inmate_rules_triggers.sql finished.

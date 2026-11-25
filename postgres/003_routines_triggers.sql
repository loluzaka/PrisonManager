CREATE OR REPLACE FUNCTION fn_level_rank(p_level text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE upper(p_level) WHEN 'LOW' THEN 1 WHEN 'MEDIUM' THEN 2 WHEN 'HIGH' THEN 3 END
$$;

CREATE OR REPLACE FUNCTION fn_inmate_visit_count(p_inmate_id bigint)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*) FROM visits
    WHERE inmate_id = p_inmate_id AND status IN ('SCHEDULED', 'COMPLETED')
$$;

CREATE OR REPLACE FUNCTION fn_visitor_visit_count(p_visitor_id bigint)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*) FROM visits
    WHERE visitor_id = p_visitor_id AND status IN ('SCHEDULED', 'COMPLETED')
$$;

CREATE OR REPLACE FUNCTION fn_block_occupancy(p_block_id bigint)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*) FROM inmates
    WHERE block_id = p_block_id AND status = 'ACTIVE'
$$;

CREATE OR REPLACE FUNCTION fn_has_active_conflict(p_visitor_id bigint, p_inmate_id bigint)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM conflicts
        WHERE visitor_id = p_visitor_id AND inmate_id = p_inmate_id
          AND resolved = 'N' AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)
    )
$$;

CREATE OR REPLACE FUNCTION fn_is_visitor_eligible(p_visitor_id bigint, p_inmate_id bigint)
RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    visitor_state text;
    inmate_state text;
BEGIN
    SELECT approval_status INTO visitor_state FROM visitors WHERE visitor_id = p_visitor_id;
    IF NOT FOUND THEN RETURN 'NO_VISITOR'; END IF;
    SELECT status INTO inmate_state FROM inmates WHERE inmate_id = p_inmate_id;
    IF NOT FOUND THEN RETURN 'NO_INMATE'; END IF;
    IF visitor_state = 'BLACKLISTED' THEN RETURN 'BLACKLISTED'; END IF;
    IF visitor_state <> 'APPROVED' THEN RETURN 'UNAPPROVED'; END IF;
    IF fn_has_active_conflict(p_visitor_id, p_inmate_id) THEN RETURN 'CONFLICT'; END IF;
    IF inmate_state <> 'ACTIVE' THEN RETURN 'INMATE_INACTIVE'; END IF;
    RETURN 'ELIGIBLE';
END
$$;

CREATE OR REPLACE FUNCTION fn_days_remaining(p_inmate_id bigint)
RETURNS integer
LANGUAGE sql STABLE
AS $$
    SELECT greatest(sentence_end - CURRENT_DATE, 0)
    FROM inmates WHERE inmate_id = p_inmate_id
$$;

CREATE OR REPLACE FUNCTION fn_weekly_visit_count(p_inmate_id bigint, p_date date)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*) FROM visits
    WHERE inmate_id = p_inmate_id AND status <> 'CANCELLED'
      AND date_trunc('week', visit_date)::date = date_trunc('week', p_date)::date
$$;

CREATE OR REPLACE FUNCTION fn_slot_visit_count(p_date date, p_slot text)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*) FROM visits
    WHERE visit_date = p_date AND slot = p_slot AND status <> 'CANCELLED'
$$;

CREATE OR REPLACE FUNCTION fn_next_free_slot(p_inmate_id bigint, p_date date)
RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    slot_row record;
BEGIN
    FOR slot_row IN SELECT slot_code, max_visitors FROM visit_slots ORDER BY start_time LOOP
        IF NOT EXISTS (
            SELECT 1 FROM visits
            WHERE inmate_id = p_inmate_id AND visit_date = p_date AND slot = slot_row.slot_code
        ) AND fn_slot_visit_count(p_date, slot_row.slot_code) < slot_row.max_visitors THEN
            RETURN slot_row.slot_code;
        END IF;
    END LOOP;
    RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION fn_diff(p_column text, p_old text, p_new text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
    SELECT CASE WHEN p_old IS NOT DISTINCT FROM p_new THEN NULL
                ELSE format('%s: %s -> %s; ', p_column, coalesce(p_old, 'NULL'), coalesce(p_new, 'NULL'))
           END
$$;

CREATE OR REPLACE FUNCTION log_audit(p_table text, p_action text, p_record_id bigint, p_details text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
    INSERT INTO audit_log (table_name, action_type, record_id, details)
    VALUES (p_table, p_action, p_record_id, left(p_details, 4000))
$$;

CREATE OR REPLACE FUNCTION trigger_audit_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    details_text text;
BEGIN
    IF TG_TABLE_NAME = 'inmates' THEN
        IF TG_OP = 'INSERT' THEN
            PERFORM log_audit('INMATES', 'INSERT', NEW.inmate_id,
                format('inmate_no=%s; name=%s; block_id=%s; risk=%s; status=%s',
                       NEW.inmate_no, NEW.full_name, NEW.block_id, NEW.risk_level, NEW.status));
            RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
            PERFORM log_audit('INMATES', 'DELETE', OLD.inmate_id,
                format('inmate_no=%s; name=%s; status=%s', OLD.inmate_no, OLD.full_name, OLD.status));
            RETURN OLD;
        END IF;
        details_text := concat_ws('',
            fn_diff('full_name', OLD.full_name, NEW.full_name),
            fn_diff('status', OLD.status, NEW.status),
            fn_diff('risk_level', OLD.risk_level, NEW.risk_level),
            fn_diff('sentence_start', OLD.sentence_start::text, NEW.sentence_start::text),
            fn_diff('sentence_end', OLD.sentence_end::text, NEW.sentence_end::text));
        IF details_text <> '' THEN PERFORM log_audit('INMATES', 'UPDATE', NEW.inmate_id, details_text); END IF;
        RETURN NEW;
    ELSIF TG_TABLE_NAME = 'visitors' THEN
        IF TG_OP = 'INSERT' THEN
            PERFORM log_audit('VISITORS', 'INSERT', NEW.visitor_id,
                format('name=%s; id_type=%s; approval_status=%s', NEW.full_name, NEW.id_proof_type, NEW.approval_status));
            RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
            PERFORM log_audit('VISITORS', 'DELETE', OLD.visitor_id,
                format('name=%s; approval_status=%s', OLD.full_name, OLD.approval_status));
            RETURN OLD;
        END IF;
        details_text := concat_ws('',
            fn_diff('approval_status', OLD.approval_status, NEW.approval_status),
            fn_diff('full_name', OLD.full_name, NEW.full_name),
            fn_diff('id_proof_number', OLD.id_proof_number, NEW.id_proof_number),
            fn_diff('phone', OLD.phone, NEW.phone));
        IF details_text <> '' THEN PERFORM log_audit('VISITORS', 'UPDATE', NEW.visitor_id, details_text); END IF;
        RETURN NEW;
    ELSE
        IF TG_OP = 'INSERT' THEN
            PERFORM log_audit('VISITS', 'VISIT_BOOKED', NEW.visit_id,
                format('inmate_id=%s; visitor_id=%s; date=%s; slot=%s',
                       NEW.inmate_id, NEW.visitor_id, NEW.visit_date, NEW.slot));
            RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
            PERFORM log_audit('VISITS', 'DELETE', OLD.visit_id,
                format('inmate_id=%s; visitor_id=%s; date=%s', OLD.inmate_id, OLD.visitor_id, OLD.visit_date));
            RETURN OLD;
        END IF;
        details_text := concat_ws('',
            fn_diff('status', OLD.status, NEW.status),
            fn_diff('visit_date', OLD.visit_date::text, NEW.visit_date::text),
            fn_diff('slot', OLD.slot, NEW.slot));
        IF details_text <> '' THEN PERFORM log_audit('VISITS', 'UPDATE', NEW.visit_id, details_text); END IF;
        RETURN NEW;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION trigger_audit_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'AUDIT_LOG is append-only: % is not allowed', TG_OP
        USING ERRCODE = 'P0001';
END
$$;

CREATE OR REPLACE FUNCTION trigger_validate_inmate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    target_security text;
    target_capacity integer;
    target_name text;
    old_inmate_id bigint := -1;
BEGIN
    IF NEW.status <> 'ACTIVE' THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' THEN old_inmate_id := OLD.inmate_id; END IF;

    PERFORM 1 FROM blocks
    WHERE block_id IN (NEW.block_id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.block_id ELSE NEW.block_id END)
    ORDER BY block_id FOR UPDATE;

    SELECT security_level, capacity, block_name
    INTO target_security, target_capacity, target_name
    FROM blocks WHERE block_id = NEW.block_id;
    IF NOT FOUND THEN RETURN NEW; END IF;
    IF fn_level_rank(NEW.risk_level) > fn_level_rank(target_security) THEN
        RAISE EXCEPTION 'Placement refused: inmate risk % exceeds block security level %',
            NEW.risk_level, target_security USING ERRCODE = 'P0001';
    END IF;

    IF (SELECT count(*) FROM inmates
        WHERE block_id = NEW.block_id AND status = 'ACTIVE'
          AND inmate_id <> old_inmate_id) >= target_capacity THEN
        RAISE EXCEPTION 'Placement refused: block % is full (capacity %)',
            target_name, target_capacity USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM inmate_conflicts ic
        JOIN inmates other ON other.inmate_id =
            CASE WHEN ic.inmate_a = NEW.inmate_id THEN ic.inmate_b ELSE ic.inmate_a END
        WHERE (ic.inmate_a = NEW.inmate_id OR ic.inmate_b = NEW.inmate_id)
          AND ic.resolved = 'N' AND other.status = 'ACTIVE' AND other.block_id = NEW.block_id
    ) THEN
        RAISE EXCEPTION 'Placement refused: a rival of inmate % lives in block %',
            NEW.inmate_id, target_name USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION trigger_log_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    transfer_reason text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO movements (inmate_id, from_block, to_block, reason)
        VALUES (NEW.inmate_id, NULL, NEW.block_id, 'ADMISSION');
    ELSIF OLD.block_id IS DISTINCT FROM NEW.block_id THEN
        transfer_reason := coalesce(nullif(current_setting('app.transfer_reason', true), ''),
                                    'Direct update of inmates.block_id');
        INSERT INTO movements (inmate_id, from_block, to_block, reason)
        VALUES (NEW.inmate_id, OLD.block_id, NEW.block_id, transfer_reason);
        PERFORM log_audit('INMATES', 'TRANSFER', NEW.inmate_id,
            format('Block %s -> %s; reason=%s', OLD.block_id, NEW.block_id, transfer_reason));
    END IF;
    RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION trigger_validate_visit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    inmate_start date;
    inmate_end date;
    max_slot_visitors integer;
    eligibility text;
    weekly_count bigint;
    slot_count bigint;
    current_visit bigint := -1;
BEGIN
    IF NEW.status = 'CANCELLED' THEN RETURN NEW; END IF;

    PERFORM 1 FROM inmates WHERE inmate_id = NEW.inmate_id FOR UPDATE;
    IF NOT FOUND THEN RETURN NEW; END IF;
    PERFORM 1 FROM visit_slots WHERE slot_code = NEW.slot FOR UPDATE;
    IF NOT FOUND THEN RETURN NEW; END IF;

    SELECT sentence_start, sentence_end INTO inmate_start, inmate_end
    FROM inmates WHERE inmate_id = NEW.inmate_id;
    IF NEW.visit_date < CURRENT_DATE THEN
        RAISE EXCEPTION 'Visit refused: visits cannot be booked in the past' USING ERRCODE = 'P0001';
    END IF;
    IF NEW.visit_date < inmate_start OR NEW.visit_date > inmate_end THEN
        RAISE EXCEPTION 'Visit refused: date is outside the inmate sentence period' USING ERRCODE = 'P0001';
    END IF;
    eligibility := fn_is_visitor_eligible(NEW.visitor_id, NEW.inmate_id);
    IF eligibility <> 'ELIGIBLE' THEN
        RAISE EXCEPTION 'Visit refused: %', eligibility USING ERRCODE = 'P0001';
    END IF;

    IF TG_OP = 'UPDATE' THEN current_visit := OLD.visit_id; END IF;
    SELECT max_visitors INTO max_slot_visitors FROM visit_slots WHERE slot_code = NEW.slot;
    SELECT count(*) INTO weekly_count
    FROM visits
    WHERE inmate_id = NEW.inmate_id AND status <> 'CANCELLED'
      AND visit_id <> current_visit
      AND date_trunc('week', visit_date)::date = date_trunc('week', NEW.visit_date)::date;
    IF weekly_count >= 3 THEN
        RAISE EXCEPTION 'Visit refused: inmate already has the maximum of 3 visits this week' USING ERRCODE = 'P0001';
    END IF;

    SELECT count(*) INTO slot_count
    FROM visits
    WHERE visit_date = NEW.visit_date AND slot = NEW.slot
      AND status <> 'CANCELLED' AND visit_id <> current_visit;
    IF slot_count >= max_slot_visitors THEN
        RAISE EXCEPTION 'Visit refused: slot % is full', NEW.slot USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION fn_register_visitor(
    p_full_name text, p_id_proof_type text, p_id_proof_number text, p_phone text
)
RETURNS TABLE(visitor_id bigint, status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    new_id bigint;
BEGIN
    INSERT INTO visitors (full_name, id_proof_type, id_proof_number, phone)
    VALUES (btrim(p_full_name), upper(btrim(p_id_proof_type)), btrim(p_id_proof_number), p_phone)
    RETURNING visitors.visitor_id INTO new_id;
    RETURN QUERY SELECT new_id, 'REGISTERED'::text, format('Visitor %s registered with status PENDING', new_id);
EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT NULL::bigint, 'DUPLICATE_ID'::text, 'A visitor with this ID proof is already registered'::text;
WHEN check_violation OR not_null_violation THEN
    RETURN QUERY SELECT NULL::bigint, 'INVALID_DATA'::text, 'Invalid or missing visitor data'::text;
END
$$;

CREATE OR REPLACE FUNCTION fn_set_visitor_status(p_visitor_id bigint, p_new_status text)
RETURNS TABLE(status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    new_status text := upper(btrim(p_new_status));
    cancelled_count bigint := 0;
BEGIN
    UPDATE visitors SET approval_status = new_status WHERE visitor_id = p_visitor_id;
    IF NOT FOUND THEN RETURN QUERY SELECT 'NOT_FOUND'::text, format('Visitor %s does not exist', p_visitor_id); RETURN; END IF;
    IF new_status IN ('BLACKLISTED', 'REJECTED') THEN
        UPDATE visits SET status = 'CANCELLED'
        WHERE visitor_id = p_visitor_id AND status = 'SCHEDULED' AND visit_date >= CURRENT_DATE;
        GET DIAGNOSTICS cancelled_count = ROW_COUNT;
    END IF;
    RETURN QUERY SELECT 'UPDATED'::text,
        format('Visitor %s is now %s%s', p_visitor_id, new_status,
               CASE WHEN cancelled_count > 0 THEN format('; %s future visit(s) cancelled', cancelled_count) ELSE '' END);
EXCEPTION WHEN check_violation THEN
    RETURN QUERY SELECT 'INVALID_DATA'::text, 'Status must be PENDING, APPROVED, REJECTED or BLACKLISTED'::text;
END
$$;

CREATE OR REPLACE FUNCTION fn_add_conflict(
    p_inmate_id bigint, p_visitor_id bigint, p_reason text, p_expiry date
)
RETURNS TABLE(status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    cancelled_count bigint;
BEGIN
    INSERT INTO conflicts (inmate_id, visitor_id, reason, expiry_date)
    VALUES (p_inmate_id, p_visitor_id, upper(p_reason), p_expiry)
    ON CONFLICT (inmate_id, visitor_id) DO UPDATE
       SET resolved = 'N', resolved_on = NULL, reason = EXCLUDED.reason,
           flagged_date = CURRENT_DATE, expiry_date = EXCLUDED.expiry_date;
    UPDATE visits SET status = 'CANCELLED'
    WHERE inmate_id = p_inmate_id AND visitor_id = p_visitor_id
      AND status = 'SCHEDULED' AND visit_date >= CURRENT_DATE;
    GET DIAGNOSTICS cancelled_count = ROW_COUNT;
    RETURN QUERY SELECT 'CONFLICT_RECORDED'::text,
        format('Conflict recorded%s', CASE WHEN cancelled_count > 0
            THEN format('; %s future visit(s) cancelled', cancelled_count) ELSE '' END);
EXCEPTION WHEN foreign_key_violation THEN
    RETURN QUERY SELECT 'NOT_FOUND'::text, 'Inmate or visitor does not exist'::text;
WHEN check_violation THEN
    RETURN QUERY SELECT 'INVALID_DATA'::text, 'Invalid conflict reason or expiry date'::text;
END
$$;

CREATE OR REPLACE FUNCTION fn_resolve_conflict(p_conflict_id bigint)
RETURNS TABLE(status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    UPDATE conflicts SET resolved = 'Y', resolved_on = CURRENT_DATE
    WHERE conflict_id = p_conflict_id AND resolved = 'N';
    IF FOUND THEN RETURN QUERY SELECT 'RESOLVED'::text, format('Conflict %s resolved', p_conflict_id); RETURN; END IF;
    IF EXISTS (SELECT 1 FROM conflicts WHERE conflict_id = p_conflict_id) THEN
        RETURN QUERY SELECT 'ALREADY_RESOLVED'::text, format('Conflict %s was already resolved', p_conflict_id);
    ELSE
        RETURN QUERY SELECT 'NOT_FOUND'::text, format('Conflict %s does not exist', p_conflict_id);
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION fn_add_inmate_rivalry(p_inmate_1 bigint, p_inmate_2 bigint, p_reason text)
RETURNS TABLE(status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    inmate_low bigint := least(p_inmate_1, p_inmate_2);
    inmate_high bigint := greatest(p_inmate_1, p_inmate_2);
BEGIN
    INSERT INTO inmate_conflicts (inmate_a, inmate_b, reason)
    VALUES (inmate_low, inmate_high, upper(p_reason))
    ON CONFLICT (inmate_a, inmate_b) DO NOTHING;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ALREADY_EXISTS'::text, 'This rivalry is already recorded'::text;
    ELSE
        RETURN QUERY SELECT 'RIVALRY_ADDED'::text, format('Inmates %s and %s are now rivals', inmate_low, inmate_high);
    END IF;
EXCEPTION WHEN foreign_key_violation THEN
    RETURN QUERY SELECT 'NOT_FOUND'::text, 'One of the inmates does not exist'::text;
WHEN check_violation THEN
    RETURN QUERY SELECT 'INVALID_DATA'::text, 'An inmate cannot be a rival of itself / bad reason'::text;
END
$$;

CREATE OR REPLACE FUNCTION fn_schedule_visit(
    p_inmate_id bigint, p_visitor_id bigint, p_visit_date date, p_slot text
)
RETURNS TABLE(status text, visit_id bigint, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    inmate_start date;
    inmate_end date;
    inmate_facility bigint;
    assigned_facility bigint;
    slot_limit integer;
    new_id bigint;
    eligibility text;
    denial text;
BEGIN
    SELECT sentence_start, sentence_end INTO inmate_start, inmate_end
    FROM inmates WHERE inmate_id = p_inmate_id FOR UPDATE;
    IF NOT FOUND THEN
        denial := 'DENIED_NO_INMATE';
        PERFORM log_audit('VISITORS', 'VISIT_DENIED', p_visitor_id,
            format('fn_schedule_visit: inmate_id=%s; date=%s; slot=%s; reason=%s', p_inmate_id, p_visit_date, p_slot, denial));
        RETURN QUERY SELECT denial, NULL::bigint, format('Inmate %s does not exist', p_inmate_id);
        RETURN;
    END IF;

    SELECT b.facility_id INTO inmate_facility
    FROM inmates i JOIN blocks b USING (block_id) WHERE i.inmate_id = p_inmate_id;
    SELECT facility_id INTO assigned_facility FROM staff_access
    WHERE db_username = lower(session_user);
    IF NOT FOUND OR (assigned_facility IS NOT NULL AND assigned_facility <> inmate_facility) THEN
        denial := 'DENIED_FACILITY';
        PERFORM log_audit('VISITORS', 'VISIT_DENIED', p_visitor_id,
            format('fn_schedule_visit: inmate_id=%s; date=%s; slot=%s; reason=%s', p_inmate_id, p_visit_date, p_slot, denial));
        RETURN QUERY SELECT denial, NULL::bigint, 'This database user cannot book visits for that facility'::text;
        RETURN;
    END IF;

    SELECT max_visitors INTO slot_limit FROM visit_slots WHERE slot_code = p_slot FOR UPDATE;
    IF NOT FOUND THEN
        denial := 'DENIED_INVALID_SLOT';
        PERFORM log_audit('VISITORS', 'VISIT_DENIED', p_visitor_id,
            format('fn_schedule_visit: inmate_id=%s; date=%s; slot=%s; reason=%s', p_inmate_id, p_visit_date, p_slot, denial));
        RETURN QUERY SELECT denial, NULL::bigint, format('Slot %s is not a valid visit slot', p_slot);
        RETURN;
    END IF;

    eligibility := fn_is_visitor_eligible(p_visitor_id, p_inmate_id);
    IF eligibility <> 'ELIGIBLE' THEN
        denial := 'DENIED_' || eligibility;
        PERFORM log_audit('VISITORS', 'VISIT_DENIED', p_visitor_id,
            format('fn_schedule_visit: inmate_id=%s; date=%s; slot=%s; reason=%s', p_inmate_id, p_visit_date, p_slot, denial));
        RETURN QUERY SELECT denial, NULL::bigint,
            CASE eligibility
                WHEN 'NO_VISITOR' THEN format('Visitor %s does not exist', p_visitor_id)
                WHEN 'UNAPPROVED' THEN 'Visitor is not approved'
                WHEN 'BLACKLISTED' THEN 'Visitor is blacklisted'
                WHEN 'CONFLICT' THEN 'A conflict exists between this visitor and inmate'
                WHEN 'INMATE_INACTIVE' THEN 'Inmate is not ACTIVE'
                ELSE eligibility
            END;
        RETURN;
    END IF;

    IF p_visit_date < CURRENT_DATE THEN
        denial := 'DENIED_PAST_DATE';
    ELSIF p_visit_date < inmate_start OR p_visit_date > inmate_end THEN
        denial := 'DENIED_OUTSIDE_SENTENCE';
    ELSIF EXISTS (SELECT 1 FROM visits WHERE inmate_id = p_inmate_id AND visit_date = p_visit_date AND slot = p_slot) THEN
        denial := 'DENIED_DUPLICATE';
    ELSIF fn_weekly_visit_count(p_inmate_id, p_visit_date) >= 3 THEN
        denial := 'DENIED_WEEKLY_LIMIT';
    ELSIF fn_slot_visit_count(p_visit_date, p_slot) >= slot_limit THEN
        denial := 'SLOT_FULL';
    ELSE
        denial := NULL;
    END IF;

    IF denial IS NOT NULL THEN
        PERFORM log_audit('VISITORS', 'VISIT_DENIED', p_visitor_id,
            format('fn_schedule_visit: inmate_id=%s; date=%s; slot=%s; reason=%s', p_inmate_id, p_visit_date, p_slot, denial));
        RETURN QUERY SELECT denial, NULL::bigint, replace(denial, '_', ' ');
        RETURN;
    END IF;

    INSERT INTO visits (inmate_id, visitor_id, visit_date, slot)
    VALUES (p_inmate_id, p_visitor_id, p_visit_date, p_slot)
    RETURNING visits.visit_id INTO new_id;
    RETURN QUERY SELECT 'BOOKED'::text, new_id, format('Visit %s booked', new_id);
EXCEPTION
    WHEN unique_violation THEN
        PERFORM log_audit('VISITORS', 'VISIT_DENIED', p_visitor_id,
            format('fn_schedule_visit: inmate_id=%s; date=%s; slot=%s; reason=DENIED_DUPLICATE', p_inmate_id, p_visit_date, p_slot));
        RETURN QUERY SELECT 'DENIED_DUPLICATE'::text, NULL::bigint, 'The inmate already has a booking in this slot'::text;
    WHEN raise_exception THEN
        PERFORM log_audit('VISITORS', 'VISIT_DENIED', p_visitor_id,
            format('fn_schedule_visit: inmate_id=%s; date=%s; slot=%s; reason=DENIED_RULE', p_inmate_id, p_visit_date, p_slot));
        RETURN QUERY SELECT 'DENIED_RULE'::text, NULL::bigint, 'Visit refused by a database rule'::text;
END
$$;

CREATE OR REPLACE FUNCTION fn_transfer_inmate(p_inmate_id bigint, p_to_block_id bigint, p_reason text)
RETURNS TABLE(status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    from_block bigint;
    inmate_state text;
    inmate_risk text;
    target_capacity integer;
    target_security text;
    target_name text;
BEGIN
    SELECT block_id, status, risk_level INTO from_block, inmate_state, inmate_risk
    FROM inmates WHERE inmate_id = p_inmate_id FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT 'NOT_FOUND'::text, format('Inmate %s does not exist', p_inmate_id); RETURN; END IF;
    IF inmate_state <> 'ACTIVE' THEN RETURN QUERY SELECT 'INMATE_NOT_ACTIVE'::text, format('Only ACTIVE inmates can be moved (status is %s)', inmate_state); RETURN; END IF;

    PERFORM 1 FROM blocks
    WHERE block_id IN (from_block, p_to_block_id)
    ORDER BY block_id FOR UPDATE;
    SELECT capacity, security_level, block_name INTO target_capacity, target_security, target_name
    FROM blocks WHERE block_id = p_to_block_id;
    IF NOT FOUND THEN RETURN QUERY SELECT 'BLOCK_NOT_FOUND'::text, format('Block %s does not exist', p_to_block_id); RETURN; END IF;
    IF from_block = p_to_block_id THEN RETURN QUERY SELECT 'SAME_BLOCK'::text, format('Inmate is already in %s', target_name); RETURN; END IF;
    IF fn_block_occupancy(p_to_block_id) >= target_capacity THEN
        RETURN QUERY SELECT 'BLOCK_FULL'::text, format('%s is full (%s/%s)', target_name, target_capacity, target_capacity); RETURN;
    END IF;
    IF fn_level_rank(inmate_risk) > fn_level_rank(target_security) THEN
        RETURN QUERY SELECT 'SECURITY_MISMATCH'::text, format('Inmate risk %s exceeds %s security level %s', inmate_risk, target_name, target_security); RETURN;
    END IF;
    IF EXISTS (
        SELECT 1 FROM inmate_conflicts ic
        JOIN inmates other ON other.inmate_id = CASE WHEN ic.inmate_a = p_inmate_id THEN ic.inmate_b ELSE ic.inmate_a END
        WHERE (ic.inmate_a = p_inmate_id OR ic.inmate_b = p_inmate_id)
          AND ic.resolved = 'N' AND other.status = 'ACTIVE' AND other.block_id = p_to_block_id
    ) THEN
        RETURN QUERY SELECT 'RIVAL_IN_BLOCK'::text, format('A rival of this inmate is housed in %s', target_name); RETURN;
    END IF;

    PERFORM set_config('app.transfer_reason', coalesce(p_reason, ''), true);
    UPDATE inmates SET block_id = p_to_block_id WHERE inmate_id = p_inmate_id;
    RETURN QUERY SELECT 'TRANSFERRED'::text,
        format('Inmate %s moved from block %s to %s', p_inmate_id, from_block, target_name);
END
$$;

CREATE OR REPLACE FUNCTION fn_nightly_maintenance()
RETURNS TABLE(released integer, missed integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    released_count integer;
    missed_count integer;
BEGIN
    UPDATE inmates SET status = 'RELEASED'
    WHERE status = 'ACTIVE' AND sentence_end < CURRENT_DATE;
    GET DIAGNOSTICS released_count = ROW_COUNT;
    UPDATE visits SET status = 'MISSED'
    WHERE status = 'SCHEDULED' AND visit_date < CURRENT_DATE;
    GET DIAGNOSTICS missed_count = ROW_COUNT;
    PERFORM log_audit('INMATES', 'JOB', NULL,
        format('fn_nightly_maintenance: released=%s; visits marked missed=%s', released_count, missed_count));
    RETURN QUERY SELECT released_count, missed_count;
END
$$;

CREATE OR REPLACE PROCEDURE pr_daily_roster(p_date date DEFAULT CURRENT_DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    c_daily_roster CURSOR FOR
        SELECT b.block_id, b.block_name, v.slot, v.status AS visit_status,
               i.inmate_no, i.full_name AS inmate_name, vr.full_name AS visitor_name
        FROM visits v
        JOIN inmates i USING (inmate_id)
        JOIN blocks b USING (block_id)
        JOIN visitors vr USING (visitor_id)
        WHERE v.visit_date = p_date AND v.status <> 'CANCELLED'
        ORDER BY b.block_name, v.slot, i.inmate_no;
    roster_row record;
    row_count integer := 0;
    previous_block bigint := -1;
BEGIN
    OPEN c_daily_roster;
    LOOP
        FETCH c_daily_roster INTO roster_row;
        EXIT WHEN NOT FOUND;
        row_count := row_count + 1;
        IF roster_row.block_id <> previous_block THEN
            RAISE NOTICE '--- % ---', roster_row.block_name;
            previous_block := roster_row.block_id;
        END IF;
        RAISE NOTICE '%: % % <- % [%]', row_count, roster_row.slot,
            roster_row.inmate_no, roster_row.visitor_name, roster_row.visit_status;
    END LOOP;
    CLOSE c_daily_roster;
    IF row_count = 0 THEN RAISE NOTICE '(no visits scheduled)'; END IF;
END
$$;

CREATE OR REPLACE PROCEDURE pr_block_occupancy()
LANGUAGE plpgsql
AS $$
DECLARE
    c_block_occupancy CURSOR FOR
        SELECT b.block_id, b.block_name, b.capacity, b.security_level, f.facility_name
        FROM blocks b JOIN facilities f USING (facility_id) ORDER BY b.block_id;
    block_row record;
    occupied bigint;
BEGIN
    OPEN c_block_occupancy;
    LOOP
        FETCH c_block_occupancy INTO block_row;
        EXIT WHEN NOT FOUND;
        occupied := fn_block_occupancy(block_row.block_id);
        RAISE NOTICE '% %/% %', block_row.block_name, occupied, block_row.capacity, block_row.facility_name;
    END LOOP;
    CLOSE c_block_occupancy;
END
$$;

CREATE OR REPLACE PROCEDURE pr_upcoming_releases(p_days integer DEFAULT 30)
LANGUAGE plpgsql
AS $$
DECLARE
    release_row record;
BEGIN
    FOR release_row IN
        SELECT inmate_no, full_name, sentence_end
        FROM inmates
        WHERE status = 'ACTIVE' AND sentence_end BETWEEN CURRENT_DATE AND CURRENT_DATE + p_days
        ORDER BY sentence_end
    LOOP
        RAISE NOTICE '% % % days', release_row.inmate_no, release_row.full_name,
            release_row.sentence_end - CURRENT_DATE;
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION fn_roster_refcursor(p_date date)
RETURNS refcursor
LANGUAGE plpgsql
AS $$
DECLARE
    roster_cursor refcursor := 'roster_cursor';
BEGIN
    OPEN roster_cursor FOR
        SELECT b.block_name, v.slot, i.inmate_no, i.full_name AS inmate, vr.full_name AS visitor
        FROM visits v
        JOIN inmates i USING (inmate_id)
        JOIN blocks b USING (block_id)
        JOIN visitors vr USING (visitor_id)
        WHERE v.visit_date = p_date AND v.status <> 'CANCELLED'
        ORDER BY b.block_name, v.slot;
    RETURN roster_cursor;
END
$$;

CREATE TRIGGER trg_audit_log_immutable
BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION trigger_audit_immutable();

CREATE TRIGGER trg_audit_inmates
AFTER INSERT OR UPDATE OR DELETE ON inmates
FOR EACH ROW EXECUTE FUNCTION trigger_audit_row();

CREATE TRIGGER trg_audit_visitors
AFTER INSERT OR UPDATE OR DELETE ON visitors
FOR EACH ROW EXECUTE FUNCTION trigger_audit_row();

CREATE TRIGGER trg_audit_visits
AFTER INSERT OR UPDATE OR DELETE ON visits
FOR EACH ROW EXECUTE FUNCTION trigger_audit_row();

CREATE TRIGGER trg_inmate_placement_rules
BEFORE INSERT OR UPDATE OF block_id, status, risk_level ON inmates
FOR EACH ROW EXECUTE FUNCTION trigger_validate_inmate();

CREATE TRIGGER trg_log_movement
AFTER INSERT OR UPDATE OF block_id ON inmates
FOR EACH ROW EXECUTE FUNCTION trigger_log_movement();

CREATE TRIGGER trg_visit_rules
BEFORE INSERT OR UPDATE OF inmate_id, visitor_id, visit_date, slot, status ON visits
FOR EACH ROW EXECUTE FUNCTION trigger_validate_visit();

\set ON_ERROR_STOP on
BEGIN;

DO $role_tests$
DECLARE
    active_count bigint;
    facility_count bigint;
    booking_status text;
    masked_id text;
BEGIN
    IF session_user = 'prison_u_frontdesk' THEN
        IF has_table_privilege(session_user, 'inmates', 'SELECT')
           OR has_table_privilege(session_user, 'visitors', 'SELECT')
           OR has_table_privilege(session_user, 'audit_log', 'SELECT') THEN
            RAISE EXCEPTION 'Front desk unexpectedly has direct access to protected tables';
        END IF;
        SELECT id_proof_masked INTO masked_id FROM v_visitors_masked WHERE visitor_id = 1;
        IF masked_id <> '****7919' THEN RAISE EXCEPTION 'Unexpected masked ID: %', masked_id; END IF;

        SELECT status INTO booking_status
        FROM fn_schedule_visit(12, 1, CURRENT_DATE + 300, '09:00-10:00');
        IF booking_status <> 'BOOKED' THEN RAISE EXCEPTION 'Expected BOOKED; got %', booking_status; END IF;
        SELECT status INTO booking_status
        FROM fn_schedule_visit(31, 1, CURRENT_DATE + 301, '10:00-11:00');
        IF booking_status <> 'DENIED_FACILITY' THEN RAISE EXCEPTION 'Expected DENIED_FACILITY; got %', booking_status; END IF;
        SELECT status INTO booking_status
        FROM fn_schedule_visit(12, 36, CURRENT_DATE + 302, '11:00-12:00');
        IF booking_status <> 'DENIED_BLACKLISTED' THEN RAISE EXCEPTION 'Expected DENIED_BLACKLISTED; got %', booking_status; END IF;

    ELSIF session_user = 'prison_u_warden' THEN
        SELECT count(*) INTO active_count FROM v_fac_inmates;
        SELECT count(*) INTO facility_count FROM v_fac_blocks;
        IF active_count <> 33 OR facility_count <> 3 THEN
            RAISE EXCEPTION 'Facility 1 scope mismatch: inmates %, blocks %', active_count, facility_count;
        END IF;
    ELSIF session_user = 'prison_u_warden2' THEN
        SELECT count(*) INTO active_count FROM v_fac_inmates;
        SELECT count(*) INTO facility_count FROM v_fac_blocks;
        IF active_count <> 17 OR facility_count <> 2 THEN
            RAISE EXCEPTION 'Facility 2 scope mismatch: inmates %, blocks %', active_count, facility_count;
        END IF;
    ELSIF session_user IN ('prison_u_admin', 'prison_u_auditor') THEN
        SELECT count(*) INTO active_count FROM v_fac_inmates;
        IF active_count <> 50 THEN RAISE EXCEPTION 'All-facility access mismatch: % inmates', active_count; END IF;
    ELSE
        RAISE EXCEPTION 'Unexpected role test account: %', session_user;
    END IF;

    RAISE NOTICE 'ROLE TESTS PASS for %', session_user;
END
$role_tests$;

ROLLBACK;

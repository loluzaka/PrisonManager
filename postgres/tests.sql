\set ON_ERROR_STOP on

CREATE TEMP TABLE migration_test_results (
    test_id text,
    purpose text,
    expected text,
    actual text,
    passed boolean
);

CREATE FUNCTION pg_temp.check_result(p_id text, p_purpose text, p_expected text, p_actual text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO migration_test_results
    VALUES (p_id, p_purpose, p_expected, p_actual, p_expected IS NOT DISTINCT FROM p_actual);
END
$$;

CREATE FUNCTION pg_temp.expect_sqlstate(p_id text, p_purpose text, p_statement text, p_expected_state text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    actual_state text := '00000';
BEGIN
    BEGIN
        EXECUTE p_statement;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
    END;
    PERFORM pg_temp.check_result(p_id, p_purpose, p_expected_state, actual_state);
END
$$;

SELECT pg_temp.check_result('A01', 'all 11 project tables installed', '11',
    count(*)::text)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
SELECT pg_temp.check_result('A02', '50 synthetic inmates seeded', '50', count(*)::text) FROM inmates;
SELECT pg_temp.check_result('A03', '40 synthetic visitors seeded', '40', count(*)::text) FROM visitors;
SELECT pg_temp.check_result('A04', '100 synthetic visits seeded', '100', count(*)::text) FROM visits;
SELECT pg_temp.check_result('A05', '5 blocks seeded', '5', count(*)::text) FROM blocks;
SELECT pg_temp.check_result('A06', '8 visitor conflicts seeded', '8', count(*)::text) FROM conflicts;
SELECT pg_temp.check_result('A07', '58 movements seeded', '58', count(*)::text) FROM movements;
SELECT pg_temp.check_result('A08', 'all primary keys installed', '11',
    count(*)::text)
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace AND contype = 'p';
SELECT pg_temp.check_result('A09', '10 project performance indexes installed', '10',
    count(*)::text)
FROM pg_indexes
WHERE schemaname = 'public' AND indexname LIKE 'idx_%';

SELECT pg_temp.check_result('B01', 'LOW < MEDIUM < HIGH ranks', '1,2,3',
    fn_level_rank('LOW') || ',' || fn_level_rank('MEDIUM') || ',' || fn_level_rank('HIGH'));
SELECT pg_temp.check_result('B02', 'block 1 active occupancy is 12', '12',
    fn_block_occupancy(1)::text);
SELECT pg_temp.check_result('B03', 'inmate 3 has 8 sentence days remaining', '8',
    fn_days_remaining(3)::text);
SELECT pg_temp.check_result('B04', 'approved visitor and active inmate are eligible', 'ELIGIBLE',
    fn_is_visitor_eligible(1, 12));
SELECT pg_temp.check_result('B05', 'blacklisted visitor is not eligible', 'BLACKLISTED',
    fn_is_visitor_eligible(36, 12));
SELECT pg_temp.check_result('B06', 'unapproved visitor is not eligible', 'UNAPPROVED',
    fn_is_visitor_eligible(31, 12));
SELECT pg_temp.check_result('B07', 'active visitor conflict is enforced', 'CONFLICT',
    fn_is_visitor_eligible(5, 3));
SELECT pg_temp.check_result('B08', 'next available empty-day slot is the first slot', '09:00-10:00',
    fn_next_free_slot(12, CURRENT_DATE + 200));
SELECT pg_temp.check_result('B09', 'all 17 views installed', '17',
    count(*)::text)
FROM pg_views WHERE schemaname = 'public';

SELECT pg_temp.expect_sqlstate('C01', 'negative block capacity violates CHECK', $q$
    INSERT INTO blocks (block_name, capacity, security_level, facility_id)
    VALUES ('INVALID-CAPACITY', -1, 'LOW', 1)
$q$, '23514');
SELECT pg_temp.expect_sqlstate('C02', 'unknown inmate violates visit foreign key', $q$
    INSERT INTO visits (inmate_id, visitor_id, visit_date, slot)
    VALUES (99999, 1, CURRENT_DATE + 30, '09:00-10:00')
$q$, '23503');
SELECT pg_temp.expect_sqlstate('C03', 'blacklisted visitor is blocked by visit trigger', $q$
    INSERT INTO visits (inmate_id, visitor_id, visit_date, slot)
    VALUES (12, 36, CURRENT_DATE + 300, '09:00-10:00')
$q$, 'P0001');
SELECT pg_temp.expect_sqlstate('C04', 'audit log cannot be modified', $q$
    UPDATE audit_log SET details = 'changed' WHERE audit_id = 1
$q$, 'P0001');
SELECT pg_temp.expect_sqlstate('C05', 'risk cannot exceed block security', $q$
    UPDATE inmates SET block_id = 1 WHERE inmate_id = 24
$q$, 'P0001');

SELECT format('TEST|%s|%s|%s|%s|%s', test_id, purpose, expected, actual,
              CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END)
FROM migration_test_results
ORDER BY test_id;
SELECT format('SUMMARY|passed=%s|failed=%s|total=%s',
              count(*) FILTER (WHERE passed),
              count(*) FILTER (WHERE NOT passed),
              count(*))
FROM migration_test_results;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM migration_test_results WHERE NOT passed) THEN
        RAISE EXCEPTION 'One or more PostgreSQL migration checks failed';
    END IF;
END
$$;

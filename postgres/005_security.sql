DO $roles$
BEGIN
    CREATE ROLE prison_admin NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END
$roles$;
DO $roles$
BEGIN
    CREATE ROLE prison_warden NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END
$roles$;
DO $roles$
BEGIN
    CREATE ROLE prison_front_desk NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END
$roles$;
DO $roles$
BEGIN
    CREATE ROLE prison_auditor NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END
$roles$;

GRANT prison_admin TO prison_u_admin;
GRANT prison_warden TO prison_u_warden, prison_u_warden2;
GRANT prison_front_desk TO prison_u_frontdesk;
GRANT prison_auditor TO prison_u_auditor;

GRANT USAGE ON SCHEMA public TO prison_admin, prison_warden, prison_front_desk, prison_auditor;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE, DELETE ON blocks, facilities, inmates, visitors, visits,
    conflicts, inmate_conflicts, visit_slots, staff_access TO prison_admin;
GRANT SELECT, INSERT ON movements, audit_log TO prison_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO prison_admin;

GRANT SELECT, INSERT, UPDATE ON inmates, blocks TO prison_warden;
GRANT SELECT ON movements, conflicts, inmate_conflicts, visits, facilities TO prison_warden;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO prison_warden;

GRANT SELECT ON audit_log TO prison_auditor;

GRANT SELECT ON v_fac_inmates, v_fac_blocks, v_fac_visits, v_active_inmates,
    v_block_occupancy, v_movement_history, v_denied_attempts, v_inmate_conflicts,
    v_upcoming_releases, v_visitors_masked TO prison_admin;
GRANT SELECT ON v_fac_inmates, v_fac_blocks, v_fac_visits, v_active_inmates,
    v_block_occupancy, v_movement_history, v_inmate_conflicts, v_upcoming_releases TO prison_warden;
GRANT SELECT ON v_todays_visits, v_eligible_visitors, v_visitors_masked,
    v_visit_eligibility, v_fac_visits TO prison_front_desk;
GRANT SELECT ON v_active_inmates, v_todays_visits, v_block_occupancy, v_visitors_masked,
    v_inmate_conflicts, v_denied_attempts, v_movement_history, v_blacklisted_visitors,
    v_frequent_visitors, v_upcoming_releases, v_visit_stats_per_inmate,
    v_monthly_visit_stats, v_fac_inmates, v_fac_blocks, v_fac_visits TO prison_auditor;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_schedule_visit(bigint, bigint, date, text) TO prison_admin, prison_front_desk;
GRANT EXECUTE ON FUNCTION fn_register_visitor(text, text, text, text) TO prison_admin, prison_front_desk;
GRANT EXECUTE ON FUNCTION fn_set_visitor_status(bigint, text) TO prison_admin;
GRANT EXECUTE ON FUNCTION fn_add_conflict(bigint, bigint, text, date),
    fn_resolve_conflict(bigint), fn_add_inmate_rivalry(bigint, bigint, text),
    fn_transfer_inmate(bigint, bigint, text) TO prison_admin, prison_warden;
GRANT EXECUTE ON FUNCTION fn_nightly_maintenance() TO prison_admin;
GRANT EXECUTE ON FUNCTION fn_roster_refcursor(date) TO prison_admin, prison_front_desk, prison_auditor;
GRANT EXECUTE ON FUNCTION fn_level_rank(text), fn_inmate_visit_count(bigint),
    fn_visitor_visit_count(bigint), fn_block_occupancy(bigint),
    fn_has_active_conflict(bigint, bigint), fn_is_visitor_eligible(bigint, bigint),
    fn_days_remaining(bigint), fn_weekly_visit_count(bigint, date),
    fn_slot_visit_count(date, text), fn_next_free_slot(bigint, date),
    fn_diff(text, text, text) TO prison_admin, prison_warden, prison_front_desk, prison_auditor;

GRANT EXECUTE ON PROCEDURE pr_daily_roster(date) TO prison_admin, prison_warden, prison_front_desk, prison_auditor;
GRANT EXECUTE ON PROCEDURE pr_block_occupancy() TO prison_admin, prison_warden, prison_auditor;
GRANT EXECUTE ON PROCEDURE pr_upcoming_releases(integer) TO prison_admin, prison_warden, prison_auditor;

INSERT INTO staff_access (db_username, facility_id) VALUES
    ('prison_u_admin', NULL),
    ('prison_u_warden', 1),
    ('prison_u_warden2', 2),
    ('prison_u_frontdesk', 1),
    ('prison_u_auditor', NULL)
ON CONFLICT (db_username) DO UPDATE SET facility_id = EXCLUDED.facility_id;

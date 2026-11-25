-- =============================================================================
-- 17_roles_security.sql
-- Features : F25 (roles and privileges), F26 (sensitive data protection), F31 (facility access),
--            F22 (least privilege on AUDIT_LOG)
-- Owner    : Member 3
-- RUN AS   : PRISON_OWNER, after 16_reports.sql (needs the demo users from 00_admin_setup.sql)
--
-- Four roles. Object privileges are granted TO ROLES (never directly to users), then roles are
-- granted to the demo users. Because procedures run with their OWNER's rights (definer's rights),
-- granting EXECUTE on sp_schedule_visit lets FRONT_DESK book visits without any privilege on the
-- VISITS table: "book visits through the procedure only".
--
--   PRISON_ADMIN      all tables (but AUDIT_LOG is SELECT + INSERT only), all procedures
--   PRISON_WARDEN     manage inmates / blocks / transfers / conflicts; read reports
--   PRISON_FRONT_DESK register visitors, book visits (procedures); sees masked data only
--   PRISON_AUDITOR    read-only on report views and the audit log
-- Nobody - not even ADMIN - is granted UPDATE or DELETE on AUDIT_LOG, and the trigger
-- trg_audit_log_immutable refuses those statements even for the owner.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

-- ---------------------------------------------------------------- (re)create roles
DECLARE
  PROCEDURE make_role(p_role VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE ' || p_role;
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE <> -1921 THEN RAISE; END IF;          -- ORA-01921: role already exists
  END;
BEGIN
  make_role('PRISON_ADMIN');
  make_role('PRISON_WARDEN');
  make_role('PRISON_FRONT_DESK');
  make_role('PRISON_AUDITOR');
END;
/

-- ---------------------------------------------------------------- PRISON_ADMIN
GRANT SELECT, INSERT, UPDATE, DELETE ON blocks            TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON facilities        TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON inmates           TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON visitors          TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON visits            TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON conflicts         TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON inmate_conflicts  TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON visit_slots       TO prison_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON staff_access      TO prison_admin;
GRANT SELECT, INSERT                 ON movements         TO prison_admin;
-- append-only
GRANT SELECT, INSERT                 ON audit_log         TO prison_admin;
GRANT SELECT ON v_fac_inmates           TO prison_admin;
GRANT SELECT ON v_fac_blocks            TO prison_admin;
GRANT SELECT ON v_fac_visits            TO prison_admin;
GRANT SELECT ON v_active_inmates        TO prison_admin;
GRANT SELECT ON v_block_occupancy       TO prison_admin;
GRANT SELECT ON v_movement_history      TO prison_admin;
GRANT SELECT ON v_denied_attempts       TO prison_admin;
GRANT SELECT ON v_inmate_conflicts      TO prison_admin;
GRANT SELECT ON v_upcoming_releases     TO prison_admin;
GRANT SELECT ON v_visitors_masked       TO prison_admin;
GRANT EXECUTE ON sp_register_visitor    TO prison_admin;
GRANT EXECUTE ON sp_set_visitor_status  TO prison_admin;
GRANT EXECUTE ON sp_add_conflict        TO prison_admin;
GRANT EXECUTE ON sp_resolve_conflict    TO prison_admin;
GRANT EXECUTE ON sp_add_inmate_rivalry  TO prison_admin;
GRANT EXECUTE ON sp_schedule_visit      TO prison_admin;
GRANT EXECUTE ON sp_transfer_inmate     TO prison_admin;
GRANT EXECUTE ON pr_daily_roster        TO prison_admin;
GRANT EXECUTE ON pr_block_occupancy     TO prison_admin;
GRANT EXECUTE ON pr_upcoming_releases   TO prison_admin;

-- ---------------------------------------------------------------- PRISON_WARDEN
-- admit / update; NO delete
GRANT SELECT, INSERT, UPDATE ON inmates TO prison_warden;
GRANT SELECT, INSERT, UPDATE ON blocks  TO prison_warden;
-- Oracle allows one object per GRANT
GRANT SELECT ON movements         TO prison_warden;
GRANT SELECT ON conflicts         TO prison_warden;
GRANT SELECT ON inmate_conflicts  TO prison_warden;
GRANT SELECT ON visits            TO prison_warden;
GRANT SELECT ON facilities        TO prison_warden;
GRANT EXECUTE ON sp_transfer_inmate     TO prison_warden;
GRANT EXECUTE ON sp_add_conflict        TO prison_warden;
GRANT EXECUTE ON sp_resolve_conflict    TO prison_warden;
GRANT EXECUTE ON sp_add_inmate_rivalry  TO prison_warden;
GRANT EXECUTE ON pr_block_occupancy     TO prison_warden;
GRANT EXECUTE ON pr_upcoming_releases   TO prison_warden;
-- facility-scoped rows (F31)
GRANT SELECT ON v_fac_inmates          TO prison_warden;
GRANT SELECT ON v_fac_blocks           TO prison_warden;
GRANT SELECT ON v_fac_visits           TO prison_warden;
GRANT SELECT ON v_active_inmates       TO prison_warden;
GRANT SELECT ON v_block_occupancy      TO prison_warden;
GRANT SELECT ON v_movement_history     TO prison_warden;
GRANT SELECT ON v_inmate_conflicts     TO prison_warden;
GRANT SELECT ON v_upcoming_releases    TO prison_warden;

-- ---------------------------------------------------------------- PRISON_FRONT_DESK
-- No table privilege at all: procedures and masked views only.
GRANT EXECUTE ON sp_register_visitor    TO prison_front_desk;
GRANT EXECUTE ON sp_schedule_visit      TO prison_front_desk;
GRANT EXECUTE ON pr_daily_roster        TO prison_front_desk;
GRANT SELECT ON v_todays_visits         TO prison_front_desk;
-- masked ID numbers
GRANT SELECT ON v_eligible_visitors     TO prison_front_desk;
GRANT SELECT ON v_visitors_masked       TO prison_front_desk;
GRANT SELECT ON v_visit_eligibility     TO prison_front_desk;
GRANT SELECT ON v_fac_visits            TO prison_front_desk;

-- ---------------------------------------------------------------- PRISON_AUDITOR
GRANT SELECT ON audit_log               TO prison_auditor;
GRANT SELECT ON v_active_inmates        TO prison_auditor;
GRANT SELECT ON v_todays_visits         TO prison_auditor;
GRANT SELECT ON v_block_occupancy       TO prison_auditor;
GRANT SELECT ON v_visitors_masked       TO prison_auditor;
GRANT SELECT ON v_inmate_conflicts      TO prison_auditor;
GRANT SELECT ON v_denied_attempts       TO prison_auditor;
GRANT SELECT ON v_movement_history      TO prison_auditor;
GRANT SELECT ON v_blacklisted_visitors  TO prison_auditor;
GRANT SELECT ON v_frequent_visitors     TO prison_auditor;
GRANT SELECT ON v_upcoming_releases     TO prison_auditor;
GRANT SELECT ON v_visit_stats_per_inmate TO prison_auditor;
GRANT SELECT ON v_monthly_visit_stats   TO prison_auditor;
GRANT SELECT ON v_fac_inmates           TO prison_auditor;
GRANT SELECT ON v_fac_blocks            TO prison_auditor;
GRANT SELECT ON v_fac_visits            TO prison_auditor;
GRANT EXECUTE ON pr_daily_roster        TO prison_auditor;
GRANT EXECUTE ON pr_block_occupancy     TO prison_auditor;

-- ---------------------------------------------------------------- roles -> demo users
GRANT prison_admin      TO prison_u_admin;
GRANT prison_warden     TO prison_u_warden, prison_u_warden2;
GRANT prison_front_desk TO prison_u_frontdesk;
GRANT prison_auditor    TO prison_u_auditor;

-- ---------------------------------------------------------------- F31 facility binding
MERGE INTO staff_access s
USING (SELECT 'PRISON_OWNER' u, CAST(NULL AS NUMBER) f FROM dual UNION ALL
       SELECT 'PRISON_U_ADMIN',     NULL FROM dual UNION ALL
       SELECT 'PRISON_U_AUDITOR',   NULL FROM dual UNION ALL
       SELECT 'PRISON_U_WARDEN',    1    FROM dual UNION ALL
       SELECT 'PRISON_U_WARDEN2',   2    FROM dual UNION ALL
       SELECT 'PRISON_U_FRONTDESK', 1    FROM dual) d
ON (s.db_username = d.u)
WHEN MATCHED THEN UPDATE SET s.facility_id = d.f
WHEN NOT MATCHED THEN INSERT (db_username, facility_id) VALUES (d.u, d.f);
COMMIT;

-- ---------------------------------------------------------------- REVOKE demo (F25)
PROMPT GRANT and REVOKE in action: give the auditor a table privilege, show it, take it away.
GRANT SELECT ON visitors TO prison_auditor;
SELECT privilege, table_name FROM user_tab_privs_made WHERE grantee = 'PRISON_AUDITOR' AND table_name = 'VISITORS';
REVOKE SELECT ON visitors FROM prison_auditor;
SELECT COUNT(*) AS auditor_privileges_on_visitors_after_revoke
  FROM user_tab_privs_made WHERE grantee = 'PRISON_AUDITOR' AND table_name = 'VISITORS';

PROMPT 17_roles_security.sql finished: 4 roles, 5 demo users bound.

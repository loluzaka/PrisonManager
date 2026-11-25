-- =============================================================================
-- 99_drop_all.sql
-- Feature : F4 (clean teardown in dependency order)
-- Owner   : Member 1
-- RUN AS  : PRISON_OWNER      *** DESTROYS THE WHOLE PROJECT SCHEMA - ALL DATA IS LOST ***
--
-- Order: scheduler job, roles' dependents (views), procedures/functions/package, triggers go with
-- their tables, then tables CHILD FIRST (a parent cannot be dropped while a foreign key still
-- points at it). Each DROP ignores "does not exist" so the script can be run repeatedly.
-- Roles and the demo users are not owned by the schema: drop them separately as a DBA if wanted
-- (DROP ROLE ...; DROP USER ... CASCADE;).
-- =============================================================================
SET ECHO OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON

DECLARE
  PROCEDURE run(p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('ok      ' || p_sql);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('skipped ' || p_sql || '  (' || SUBSTR(SQLERRM, 1, 60) || ')');
  END;
BEGIN
  BEGIN DBMS_SCHEDULER.DROP_JOB('JOB_NIGHTLY_PRISON_MAINTENANCE', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- views, then stored code
  FOR o IN (SELECT object_type, object_name FROM user_objects
             WHERE object_type IN ('VIEW','PROCEDURE','FUNCTION','PACKAGE')
             ORDER BY CASE object_type WHEN 'VIEW' THEN 1 WHEN 'PROCEDURE' THEN 2
                                       WHEN 'FUNCTION' THEN 3 ELSE 4 END) LOOP
    run('DROP ' || o.object_type || ' ' || o.object_name);
  END LOOP;

  -- tables, children before parents (triggers and indexes are dropped with their table)
  run('DROP TABLE staff_access PURGE');
  run('DROP TABLE inmate_conflicts PURGE');
  run('DROP TABLE visit_slots PURGE');
  run('DROP TABLE conflicts PURGE');
  run('DROP TABLE movements PURGE');
  run('DROP TABLE visits PURGE');
  run('DROP TABLE audit_log PURGE');
  run('DROP TABLE visitors PURGE');
  run('DROP TABLE inmates PURGE');
  run('DROP TABLE blocks PURGE');
  run('DROP TABLE facilities PURGE');
  run('DROP TABLE tmp_visit_test PURGE');
  run('DROP TABLE visits_big PURGE');
END;
/
PROMPT 99_drop_all.sql finished: schema is empty.

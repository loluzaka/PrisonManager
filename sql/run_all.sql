-- =============================================================================
-- run_all.sql  -  master install script
-- RUN AS : PRISON_OWNER, from the sql/ directory:   sqlplus owner/pwd@service @run_all.sql
-- Runs the build in dependency order and stops at the first error.
-- (00_admin_setup.sql is run beforehand by a DBA account; demos 12-16, 19-21 are optional.)
-- =============================================================================
WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET ECHO OFF
@@01_create_tables.sql
@@02_alter_schema.sql
@@03_indexes.sql
@@04_seed_data.sql
@@05_package_and_functions.sql
@@06_audit_trail.sql
@@07_visit_rules_triggers.sql
@@08_inmate_rules_triggers.sql
@@09_procedures.sql
@@10_cursors.sql
@@11_views.sql
@@17_roles_security.sql
@@18_scheduled_jobs.sql
PROMPT *** run_all.sql complete ***

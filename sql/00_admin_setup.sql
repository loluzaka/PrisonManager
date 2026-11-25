-- =============================================================================
-- 00_admin_setup.sql
-- Prison Visitor & Inmate Roster Management System  (Oracle 19c / 23ai)
-- Features: F25 (demo users), F29/F32 (separate admin and application accounts)
--
-- RUN AS : a DBA account (SYSTEM on the local container, ADMIN on Autonomous DB)
-- USAGE  : @00_admin_setup.sql <owner_password> <demo_user_password>
--
-- Creates the schema owner PRISON_OWNER and four demo accounts, one per role.
-- Passwords are passed as arguments - they are NEVER stored in this file.
-- Safe to re-run: existing users are kept (their password is re-set).
-- =============================================================================
SET VERIFY OFF
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT FAILURE

DEFINE owner_pwd = &1
DEFINE demo_pwd  = &2

DECLARE
  PROCEDURE ensure_user(p_name VARCHAR2, p_pwd VARCHAR2) IS
    v_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = UPPER(p_name);
    IF v_cnt = 0 THEN
      EXECUTE IMMEDIATE 'CREATE USER ' || p_name || ' IDENTIFIED BY "' || p_pwd || '"';
      DBMS_OUTPUT.PUT_LINE('created user ' || p_name);
    ELSE
      EXECUTE IMMEDIATE 'ALTER USER ' || p_name || ' IDENTIFIED BY "' || p_pwd || '"';
      DBMS_OUTPUT.PUT_LINE('user ' || p_name || ' already exists - password reset');
    END IF;
  END;
BEGIN
  ensure_user('PRISON_OWNER',      '&owner_pwd');
  ensure_user('PRISON_U_ADMIN',    '&demo_pwd');
  ensure_user('PRISON_U_WARDEN',   '&demo_pwd');   -- bound to facility 1 (F31)
  ensure_user('PRISON_U_WARDEN2',  '&demo_pwd');   -- bound to facility 2 (F31)
  ensure_user('PRISON_U_FRONTDESK','&demo_pwd');
  ensure_user('PRISON_U_AUDITOR',  '&demo_pwd');
END;
/

-- The schema owner needs rights to create every object type used by the project.
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE, CREATE ROLE,
      CREATE JOB, CREATE SYNONYM, UNLIMITED TABLESPACE
   TO prison_owner;

-- Demo accounts get only the right to log in. Everything else arrives through roles (script 17).
GRANT CREATE SESSION TO prison_u_admin, prison_u_warden, prison_u_warden2,
                        prison_u_frontdesk, prison_u_auditor;

PROMPT 00_admin_setup.sql finished: PRISON_OWNER and 5 demo users are ready.

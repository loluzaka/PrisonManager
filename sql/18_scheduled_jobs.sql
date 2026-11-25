-- =============================================================================
-- 18_scheduled_jobs.sql
-- Feature : F28 (scheduled jobs - stretch)
-- Owner   : Member 3
-- RUN AS  : PRISON_OWNER (needs CREATE JOB), after 17_roles_security.sql
--
-- PR_NIGHTLY_MAINTENANCE does three things:
--   1. marks ACTIVE inmates RELEASED once their sentence has ended
--      (cursor FOR UPDATE + UPDATE ... WHERE CURRENT OF)
--   2. marks SCHEDULED visits in the past as MISSED
--   3. lists inmates due for release in the next 7 days (cursor procedure) and writes one JOB row
--      into AUDIT_LOG.
-- JOB_NIGHTLY_PRISON_MAINTENANCE runs it every night at 02:00 with DBMS_SCHEDULER.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PROCEDURE pr_nightly_maintenance (
  p_released OUT NUMBER,
  p_missed   OUT NUMBER
) IS
  -- FOR UPDATE locks the selected rows; WHERE CURRENT OF updates exactly the row just fetched
  CURSOR c_due_release IS
    SELECT inmate_id, inmate_no FROM inmates
     WHERE status = 'ACTIVE' AND sentence_end < TRUNC(SYSDATE)
       FOR UPDATE OF status;
BEGIN
  p_released := 0;
  FOR r IN c_due_release LOOP
    UPDATE inmates SET status = 'RELEASED' WHERE CURRENT OF c_due_release;
    p_released := p_released + 1;
    DBMS_OUTPUT.PUT_LINE('released ' || r.inmate_no);
  END LOOP;

  UPDATE visits SET status = 'MISSED'
   WHERE status = 'SCHEDULED' AND visit_date < TRUNC(SYSDATE);
  p_missed := SQL%ROWCOUNT;

  sp_log_audit('INMATES', 'JOB', NULL,
    'pr_nightly_maintenance: released=' || p_released || '; visits marked missed=' || p_missed);
  COMMIT;
  pr_upcoming_releases(7);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END pr_nightly_maintenance;
/

-- wrapper without OUT parameters, because DBMS_SCHEDULER calls a plain procedure
CREATE OR REPLACE PROCEDURE pr_nightly_job IS
  v_rel NUMBER; v_mis NUMBER;
BEGIN
  pr_nightly_maintenance(v_rel, v_mis);
END pr_nightly_job;
/

BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB('JOB_NIGHTLY_PRISON_MAINTENANCE', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;                 -- first run: job does not exist yet
  END;
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_NIGHTLY_PRISON_MAINTENANCE',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'PR_NIGHTLY_JOB',
    start_date      => CAST(TRUNC(SYSDATE) + 1 + 2/24 AS TIMESTAMP WITH TIME ZONE),   -- first run: next 02:00, not now
    repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0; BYSECOND=0',
    enabled         => TRUE,
    comments        => 'Marks finished sentences RELEASED and past visits MISSED');
END;
/

PROMPT Job definition:
COLUMN job_name FORMAT A34
COLUMN repeat_interval FORMAT A45
SELECT job_name, enabled, repeat_interval FROM user_scheduler_jobs;

PROMPT Manual test run (the job body, in this session):
DECLARE
  v_rel NUMBER; v_mis NUMBER;
BEGIN
  pr_nightly_maintenance(v_rel, v_mis);
  DBMS_OUTPUT.PUT_LINE('result: released=' || v_rel || ', missed=' || v_mis);
END;
/
PROMPT 18_scheduled_jobs.sql finished.

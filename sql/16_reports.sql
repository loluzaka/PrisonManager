-- =============================================================================
-- 16_reports.sql
-- Feature : F27 (reports built from views, joins, aggregates and cursors),
--            F36 (PIVOT report)
-- Owner   : Member 3
-- RUN AS  : PRISON_OWNER (read-only; also runnable by PRISON_AUDITOR), after 15_queries_nested_window.sql
--
-- R1  Daily roster                  (cursor procedure pr_daily_roster)
-- R2  Block occupancy               (cursor procedure pr_block_occupancy + view v_block_occupancy)
-- R3  Visit statistics per inmate   (view v_visit_stats_per_inmate)
-- R4  Monthly visitation statistics (view v_monthly_visit_stats)
-- R5  Complete movement history of one inmate (view v_movement_history)
-- R6  Denied visit attempts         (view v_denied_attempts)
-- R7  Blacklisted visitors          (view v_blacklisted_visitors)
-- R8  Frequent visitors             (view v_frequent_visitors)
-- R9  Upcoming releases             (cursor procedure pr_upcoming_releases + view v_upcoming_releases)
-- R10 Conflict list                 (view v_inmate_conflicts)
-- R11 Monthly visits by status      (PIVOT)
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 170
SET PAGESIZE 60
COLUMN inmate_name FORMAT A22
COLUMN full_name FORMAT A22
COLUMN visitor_name FORMAT A22
COLUMN from_block FORMAT A10
COLUMN to_block FORMAT A10
COLUMN reason FORMAT A40
COLUMN details FORMAT A60
COLUMN block_name FORMAT A10
COLUMN facility_name FORMAT A30

PROMPT ##### R1  DAILY ROSTER (today) #####
EXEC pr_daily_roster(TRUNC(SYSDATE));

PROMPT ##### R2  BLOCK OCCUPANCY #####
EXEC pr_block_occupancy;
SELECT block_name, facility_name, security_level, capacity, occupied, free_beds, occupancy_pct, occupancy_flag
  FROM v_block_occupancy ORDER BY block_id;

PROMPT ##### R3  VISIT STATISTICS PER INMATE (top 10 by total visits) #####
SELECT inmate_no, full_name, total_visits, completed, missed, distinct_visitors, last_visit
  FROM v_visit_stats_per_inmate ORDER BY total_visits DESC, inmate_no FETCH FIRST 10 ROWS ONLY;

PROMPT ##### R4  MONTHLY VISITATION STATISTICS #####
SELECT * FROM v_monthly_visit_stats ORDER BY visit_month;

PROMPT ##### R5  COMPLETE MOVEMENT HISTORY of inmate 2 #####
SELECT movement_date, inmate_no, from_block, to_block, reason, moved_by
  FROM v_movement_history WHERE inmate_id = 2 ORDER BY movement_date;

PROMPT ##### R6  DENIED VISIT ATTEMPTS #####
SELECT audit_id, changed_at, visitor_id, visitor_name, inmate_id, reason, changed_by
  FROM v_denied_attempts ORDER BY changed_at DESC;

PROMPT ##### R7  BLACKLISTED VISITORS #####
SELECT * FROM v_blacklisted_visitors ORDER BY visitor_id;

PROMPT ##### R8  FREQUENT VISITORS (3 or more visits) #####
SELECT * FROM v_frequent_visitors ORDER BY visits DESC, visitor_id;

PROMPT ##### R9  UPCOMING RELEASES (30 days, cursor) and (60 days, view) #####
EXEC pr_upcoming_releases(30);
SELECT inmate_no, full_name, block_name, sentence_end, days_left FROM v_upcoming_releases ORDER BY days_left;

PROMPT ##### R10 CONFLICT LIST #####
SELECT conflict_id, inmate_no, inmate_name, visitor_name, reason, flagged_date, expiry_date, conflict_state
  FROM v_inmate_conflicts ORDER BY conflict_state, conflict_id;

PROMPT ##### R11 MONTHLY VISITS BY STATUS (PIVOT) #####
SELECT visit_month, scheduled, completed, missed, cancelled
  FROM (
    SELECT TO_CHAR(visit_date, 'YYYY-MM') AS visit_month, status, visit_id
      FROM visits
  )
  PIVOT (
    COUNT(visit_id) FOR status IN (
      'SCHEDULED' AS scheduled,
      'COMPLETED' AS completed,
      'MISSED' AS missed,
      'CANCELLED' AS cancelled
    )
  )
 ORDER BY visit_month;

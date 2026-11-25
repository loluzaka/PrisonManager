-- =============================================================================
-- 11_views.sql
-- Features : F6 (views), F26 (masked ID numbers), F27 (report views), F31 (facility-scoped views)
-- Owner    : Member 3
-- RUN AS   : PRISON_OWNER, after 10_cursors.sql
--
-- A VIEW is a stored SELECT with a name. Staff roles receive access to views, never to base
-- tables (script 17), so a view can hide columns (V_VISITORS_MASKED hides all but the last four
-- digits of the ID number) and rows (V_FAC_* show only the caller's facility).
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

-- ================================================================ F6 core views
CREATE OR REPLACE VIEW v_active_inmates AS
SELECT i.inmate_id, i.inmate_no, i.full_name, i.risk_level,
       b.block_name, b.security_level, f.facility_name,
       i.sentence_end, fn_days_remaining(i.inmate_id) AS days_remaining
  FROM inmates i
  JOIN blocks b     ON b.block_id    = i.block_id
  JOIN facilities f ON f.facility_id = b.facility_id
 WHERE i.status = 'ACTIVE';

CREATE OR REPLACE VIEW v_todays_visits AS
SELECT v.visit_id, v.slot, b.block_name,
       i.inmate_no, i.full_name AS inmate_name,
       vr.full_name AS visitor_name, v.status
  FROM visits v
  JOIN inmates  i  ON i.inmate_id   = v.inmate_id
  JOIN blocks   b  ON b.block_id    = i.block_id
  JOIN visitors vr ON vr.visitor_id = v.visitor_id
 WHERE v.visit_date = TRUNC(SYSDATE);

-- Visitors who may currently book visits (APPROVED); ID number is masked.
CREATE OR REPLACE VIEW v_eligible_visitors AS
SELECT visitor_id, full_name, id_proof_type,
       '****' || SUBSTR(id_proof_number, -4) AS id_proof_masked,
       phone, fn_visitor_visit_count(visitor_id) AS visits_made
  FROM visitors
 WHERE approval_status = 'APPROVED';

-- Every (visitor, inmate) pair that is eligible right now: approved visitor, ACTIVE inmate, no active conflict.
CREATE OR REPLACE VIEW v_visit_eligibility AS
SELECT vr.visitor_id, vr.full_name AS visitor_name, i.inmate_id, i.inmate_no, i.full_name AS inmate_name
  FROM visitors vr
  CROSS JOIN inmates i
 WHERE vr.approval_status = 'APPROVED' AND i.status = 'ACTIVE'
   AND NOT EXISTS (SELECT 1 FROM conflicts c
                    WHERE c.visitor_id = vr.visitor_id AND c.inmate_id = i.inmate_id
                      AND c.resolved = 'N' AND (c.expiry_date IS NULL OR c.expiry_date >= TRUNC(SYSDATE)));

CREATE OR REPLACE VIEW v_block_occupancy AS
SELECT b.block_id, b.block_name, f.facility_name, b.security_level, b.capacity,
       NVL(o.occupied, 0)                                     AS occupied,
       b.capacity - NVL(o.occupied, 0)                        AS free_beds,
       ROUND(NVL(o.occupied, 0) / b.capacity * 100, 1)        AS occupancy_pct,
       CASE WHEN NVL(o.occupied, 0) > b.capacity THEN 'OVER CAPACITY'
            WHEN NVL(o.occupied, 0) = b.capacity THEN 'AT CAPACITY'
            WHEN NVL(o.occupied, 0) >= 0.9 * b.capacity THEN 'NEARLY FULL'
            ELSE 'AVAILABLE' END                              AS occupancy_flag
  FROM blocks b
  JOIN facilities f ON f.facility_id = b.facility_id
  LEFT JOIN (SELECT block_id, COUNT(*) AS occupied FROM inmates WHERE status = 'ACTIVE' GROUP BY block_id) o
         ON o.block_id = b.block_id;

-- ================================================================ F26 masking
CREATE OR REPLACE VIEW v_visitors_masked AS
SELECT visitor_id, full_name, id_proof_type,
       '****' || SUBSTR(id_proof_number, -4) AS id_proof_masked,
       approval_status, registered_on
  FROM visitors;

-- ================================================================ F27 report views
CREATE OR REPLACE VIEW v_inmate_conflicts AS
SELECT c.conflict_id, i.inmate_id, i.inmate_no, i.full_name AS inmate_name,
       vr.visitor_id, vr.full_name AS visitor_name, c.reason, c.flagged_date,
       c.expiry_date, c.resolved,
       CASE WHEN c.resolved = 'Y' THEN 'RESOLVED'
            WHEN c.expiry_date IS NOT NULL AND c.expiry_date < TRUNC(SYSDATE) THEN 'EXPIRED'
            ELSE 'ACTIVE' END AS conflict_state
  FROM conflicts c
  JOIN inmates  i  ON i.inmate_id   = c.inmate_id
  JOIN visitors vr ON vr.visitor_id = c.visitor_id;

CREATE OR REPLACE VIEW v_denied_attempts AS
SELECT a.audit_id, a.changed_at, a.record_id AS visitor_id, vr.full_name AS visitor_name,
       REGEXP_SUBSTR(a.details, 'inmate_id=([0-9]+)', 1, 1, NULL, 1) AS inmate_id,
       REGEXP_SUBSTR(a.details, 'reason=([A-Z_]+)',   1, 1, NULL, 1) AS reason,
       a.changed_by, a.details
  FROM audit_log a
  LEFT JOIN visitors vr ON vr.visitor_id = a.record_id
 WHERE a.action_type = 'VISIT_DENIED';

CREATE OR REPLACE VIEW v_movement_history AS
SELECT m.movement_id, m.movement_date, i.inmate_id, i.inmate_no, i.full_name AS inmate_name,
       fb.block_name AS from_block, tb.block_name AS to_block, m.reason, m.moved_by
  FROM movements m
  JOIN inmates i ON i.inmate_id = m.inmate_id
  LEFT JOIN blocks fb ON fb.block_id = m.from_block      -- LEFT: admissions have no origin
  JOIN blocks tb ON tb.block_id = m.to_block;

CREATE OR REPLACE VIEW v_blacklisted_visitors AS
SELECT visitor_id, full_name, id_proof_type, '****' || SUBSTR(id_proof_number, -4) AS id_proof_masked,
       (SELECT COUNT(*) FROM audit_log a WHERE a.action_type = 'VISIT_DENIED' AND a.record_id = v.visitor_id)
         AS denied_attempts
  FROM visitors v
 WHERE approval_status = 'BLACKLISTED';

CREATE OR REPLACE VIEW v_frequent_visitors AS
SELECT vr.visitor_id, vr.full_name, COUNT(*) AS visits, COUNT(DISTINCT v.inmate_id) AS inmates_visited,
       MAX(v.visit_date) AS last_visit
  FROM visitors vr JOIN visits v ON v.visitor_id = vr.visitor_id
 WHERE v.status IN ('SCHEDULED','COMPLETED')
 GROUP BY vr.visitor_id, vr.full_name
HAVING COUNT(*) >= 3;

CREATE OR REPLACE VIEW v_upcoming_releases AS
SELECT i.inmate_id, i.inmate_no, i.full_name, b.block_name, i.sentence_end,
       i.sentence_end - TRUNC(SYSDATE) AS days_left
  FROM inmates i JOIN blocks b ON b.block_id = i.block_id
 WHERE i.status = 'ACTIVE' AND i.sentence_end BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 60;

CREATE OR REPLACE VIEW v_visit_stats_per_inmate AS
SELECT i.inmate_id, i.inmate_no, i.full_name,
       COUNT(v.visit_id)                                       AS total_visits,
       SUM(CASE WHEN v.status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed,
       SUM(CASE WHEN v.status = 'MISSED'    THEN 1 ELSE 0 END) AS missed,
       COUNT(DISTINCT v.visitor_id)                            AS distinct_visitors,
       MAX(v.visit_date)                                       AS last_visit
  FROM inmates i LEFT JOIN visits v ON v.inmate_id = i.inmate_id
 GROUP BY i.inmate_id, i.inmate_no, i.full_name;

CREATE OR REPLACE VIEW v_monthly_visit_stats AS
SELECT TO_CHAR(visit_date, 'YYYY-MM') AS visit_month,
       COUNT(*)                                                 AS visits,
       SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END)    AS completed,
       SUM(CASE WHEN status = 'MISSED'    THEN 1 ELSE 0 END)    AS missed,
       SUM(CASE WHEN status = 'CANCELLED' THEN 1 ELSE 0 END)    AS cancelled,
       COUNT(DISTINCT visitor_id)                               AS distinct_visitors
  FROM visits
 GROUP BY TO_CHAR(visit_date, 'YYYY-MM');

-- ================================================================ F31 facility-scoped views
-- A user sees a row only if STAFF_ACCESS maps their login to that row's facility
-- (facility_id NULL in STAFF_ACCESS = all facilities, e.g. admin and auditor).
CREATE OR REPLACE VIEW v_fac_blocks AS
SELECT b.*
  FROM blocks b
 WHERE EXISTS (SELECT 1 FROM staff_access s
                WHERE s.db_username = SYS_CONTEXT('USERENV', 'SESSION_USER')
                  AND (s.facility_id IS NULL OR s.facility_id = b.facility_id));

CREATE OR REPLACE VIEW v_fac_inmates AS
SELECT i.inmate_id, i.inmate_no, i.full_name, i.status, i.risk_level, i.sentence_end,
       b.block_id, b.block_name, b.facility_id
  FROM inmates i JOIN v_fac_blocks b ON b.block_id = i.block_id;

CREATE OR REPLACE VIEW v_fac_visits AS
SELECT v.visit_id, v.visit_date, v.slot, v.status,
       i.inmate_no, i.full_name AS inmate_name, vr.full_name AS visitor_name,
       b.block_name, b.facility_id
  FROM visits v
  JOIN inmates i    ON i.inmate_id = v.inmate_id
  JOIN visitors vr  ON vr.visitor_id = v.visitor_id
  JOIN v_fac_blocks b ON b.block_id = i.block_id;

PROMPT 11_views.sql finished.

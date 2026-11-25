CREATE OR REPLACE VIEW v_active_inmates AS
SELECT i.inmate_id, i.inmate_no, i.full_name, i.risk_level,
       b.block_name, b.security_level, f.facility_name,
       i.sentence_end, fn_days_remaining(i.inmate_id) AS days_remaining
FROM inmates i
JOIN blocks b USING (block_id)
JOIN facilities f USING (facility_id)
WHERE i.status = 'ACTIVE';

CREATE OR REPLACE VIEW v_todays_visits AS
SELECT v.visit_id, v.slot, b.block_name, i.inmate_no,
       i.full_name AS inmate_name, vr.full_name AS visitor_name, v.status
FROM visits v
JOIN inmates i USING (inmate_id)
JOIN blocks b USING (block_id)
JOIN visitors vr USING (visitor_id)
WHERE v.visit_date = CURRENT_DATE;

CREATE OR REPLACE VIEW v_eligible_visitors AS
SELECT visitor_id, full_name, id_proof_type,
       '****' || right(id_proof_number, 4) AS id_proof_masked,
       phone, fn_visitor_visit_count(visitor_id) AS visits_made
FROM visitors
WHERE approval_status = 'APPROVED';

CREATE OR REPLACE VIEW v_visit_eligibility AS
SELECT vr.visitor_id, vr.full_name AS visitor_name,
       i.inmate_id, i.inmate_no, i.full_name AS inmate_name
FROM visitors vr
CROSS JOIN inmates i
WHERE vr.approval_status = 'APPROVED'
  AND i.status = 'ACTIVE'
  AND NOT fn_has_active_conflict(vr.visitor_id, i.inmate_id);

CREATE OR REPLACE VIEW v_block_occupancy AS
SELECT b.block_id, b.block_name, f.facility_name, b.security_level, b.capacity,
       coalesce(o.occupied, 0) AS occupied,
       b.capacity - coalesce(o.occupied, 0) AS free_beds,
       round(coalesce(o.occupied, 0)::numeric / b.capacity * 100, 1) AS occupancy_pct,
       CASE WHEN coalesce(o.occupied, 0) > b.capacity THEN 'OVER CAPACITY'
            WHEN coalesce(o.occupied, 0) = b.capacity THEN 'AT CAPACITY'
            WHEN coalesce(o.occupied, 0) >= 0.9 * b.capacity THEN 'NEARLY FULL'
            ELSE 'AVAILABLE' END AS occupancy_flag
FROM blocks b
JOIN facilities f USING (facility_id)
LEFT JOIN (
    SELECT block_id, count(*) AS occupied FROM inmates
    WHERE status = 'ACTIVE' GROUP BY block_id
) o USING (block_id);

CREATE OR REPLACE VIEW v_visitors_masked AS
SELECT visitor_id, full_name, id_proof_type,
       '****' || right(id_proof_number, 4) AS id_proof_masked,
       approval_status, registered_on
FROM visitors;

CREATE OR REPLACE VIEW v_inmate_conflicts AS
SELECT c.conflict_id, i.inmate_id, i.inmate_no, i.full_name AS inmate_name,
       vr.visitor_id, vr.full_name AS visitor_name, c.reason, c.flagged_date,
       c.expiry_date, c.resolved,
       CASE WHEN c.resolved = 'Y' THEN 'RESOLVED'
            WHEN c.expiry_date IS NOT NULL AND c.expiry_date < CURRENT_DATE THEN 'EXPIRED'
            ELSE 'ACTIVE' END AS conflict_state
FROM conflicts c
JOIN inmates i USING (inmate_id)
JOIN visitors vr USING (visitor_id);

CREATE OR REPLACE VIEW v_denied_attempts AS
SELECT a.audit_id, a.changed_at, a.record_id AS visitor_id, vr.full_name AS visitor_name,
       substring(a.details FROM 'inmate_id=([0-9]+)') AS inmate_id,
       substring(a.details FROM 'reason=([A-Z_]+)') AS reason,
       a.changed_by, a.details
FROM audit_log a
LEFT JOIN visitors vr ON vr.visitor_id = a.record_id
WHERE a.action_type = 'VISIT_DENIED';

CREATE OR REPLACE VIEW v_movement_history AS
SELECT m.movement_id, m.movement_date, i.inmate_id, i.inmate_no,
       i.full_name AS inmate_name, fb.block_name AS from_block,
       tb.block_name AS to_block, m.reason, m.moved_by
FROM movements m
JOIN inmates i USING (inmate_id)
LEFT JOIN blocks fb ON fb.block_id = m.from_block
JOIN blocks tb ON tb.block_id = m.to_block;

CREATE OR REPLACE VIEW v_blacklisted_visitors AS
SELECT v.visitor_id, v.full_name, v.id_proof_type,
       '****' || right(v.id_proof_number, 4) AS id_proof_masked,
       (SELECT count(*) FROM audit_log a
        WHERE a.action_type = 'VISIT_DENIED' AND a.record_id = v.visitor_id) AS denied_attempts
FROM visitors v
WHERE v.approval_status = 'BLACKLISTED';

CREATE OR REPLACE VIEW v_frequent_visitors AS
SELECT vr.visitor_id, vr.full_name, count(*) AS visits,
       count(DISTINCT v.inmate_id) AS inmates_visited, max(v.visit_date) AS last_visit
FROM visitors vr
JOIN visits v USING (visitor_id)
WHERE v.status IN ('SCHEDULED', 'COMPLETED')
GROUP BY vr.visitor_id, vr.full_name
HAVING count(*) >= 3;

CREATE OR REPLACE VIEW v_upcoming_releases AS
SELECT i.inmate_id, i.inmate_no, i.full_name, b.block_name, i.sentence_end,
       i.sentence_end - CURRENT_DATE AS days_left
FROM inmates i
JOIN blocks b USING (block_id)
WHERE i.status = 'ACTIVE'
  AND i.sentence_end BETWEEN CURRENT_DATE AND CURRENT_DATE + 60;

CREATE OR REPLACE VIEW v_visit_stats_per_inmate AS
SELECT i.inmate_id, i.inmate_no, i.full_name,
       count(v.visit_id) AS total_visits,
       sum(CASE WHEN v.status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed,
       sum(CASE WHEN v.status = 'MISSED' THEN 1 ELSE 0 END) AS missed,
       count(DISTINCT v.visitor_id) AS distinct_visitors,
       max(v.visit_date) AS last_visit
FROM inmates i
LEFT JOIN visits v USING (inmate_id)
GROUP BY i.inmate_id, i.inmate_no, i.full_name;

CREATE OR REPLACE VIEW v_monthly_visit_stats AS
SELECT to_char(visit_date, 'YYYY-MM') AS visit_month,
       count(*) AS visits,
       sum(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed,
       sum(CASE WHEN status = 'MISSED' THEN 1 ELSE 0 END) AS missed,
       sum(CASE WHEN status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled,
       count(DISTINCT visitor_id) AS distinct_visitors
FROM visits
GROUP BY to_char(visit_date, 'YYYY-MM');

CREATE OR REPLACE VIEW v_fac_blocks AS
SELECT b.*
FROM blocks b
WHERE EXISTS (
    SELECT 1 FROM staff_access s
    WHERE s.db_username = lower(session_user)
      AND (s.facility_id IS NULL OR s.facility_id = b.facility_id)
);

CREATE OR REPLACE VIEW v_fac_inmates AS
SELECT i.inmate_id, i.inmate_no, i.full_name, i.status, i.risk_level, i.sentence_end,
       b.block_id, b.block_name, b.facility_id
FROM inmates i
JOIN v_fac_blocks b USING (block_id);

CREATE OR REPLACE VIEW v_fac_visits AS
SELECT v.visit_id, v.visit_date, v.slot, v.status,
       i.inmate_no, i.full_name AS inmate_name, vr.full_name AS visitor_name,
       b.block_name, b.facility_id
FROM visits v
JOIN inmates i USING (inmate_id)
JOIN visitors vr USING (visitor_id)
JOIN v_fac_blocks b USING (block_id);

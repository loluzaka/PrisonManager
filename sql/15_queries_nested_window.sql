-- =============================================================================
-- 15_queries_nested_window.sql
-- Features : F11 (nested queries and set operations), F12 (window functions),
--            F36 (pagination with OFFSET / FETCH)
-- Owner    : Member 1 (F11) / Member 3 (F12 stretch)
-- RUN AS   : PRISON_OWNER, after 14_queries_joins.sql                 (read-only script)
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON
SET LINESIZE 170
SET PAGESIZE 60
COLUMN full_name FORMAT A22
COLUMN block_name FORMAT A10

PROMPT ======================= F11  SUBQUERIES =======================

PROMPT N1  Scalar subquery: inmates with MORE visits than the average inmate
SELECT i.inmate_no, i.full_name, COUNT(*) AS visits
  FROM inmates i JOIN visits v ON v.inmate_id = i.inmate_id
 GROUP BY i.inmate_no, i.full_name
HAVING COUNT(*) > (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM visits GROUP BY inmate_id))
 ORDER BY visits DESC, i.inmate_no;

PROMPT N2  ALL: blocks of facility 1 whose capacity is greater than ALL blocks of facility 2
SELECT b.block_name, b.capacity FROM blocks b
 WHERE b.facility_id = 1
   AND b.capacity > ALL (SELECT capacity FROM blocks WHERE facility_id = 2);

PROMPT N3  ANY: blocks bigger than at least ONE high-security block
SELECT block_name, capacity FROM blocks
 WHERE capacity > ANY (SELECT capacity FROM blocks WHERE security_level = 'HIGH') ORDER BY capacity;

PROMPT N4  NOT EXISTS: APPROVED visitors with no conflict at all
SELECT vr.visitor_id, vr.full_name FROM visitors vr
 WHERE vr.approval_status = 'APPROVED'
   AND NOT EXISTS (SELECT 1 FROM conflicts c WHERE c.visitor_id = vr.visitor_id)
 ORDER BY vr.visitor_id FETCH FIRST 8 ROWS ONLY;

PROMPT N5  EXISTS: visitors that have at least one COMPLETED visit
SELECT vr.visitor_id, vr.full_name FROM visitors vr
 WHERE EXISTS (SELECT 1 FROM visits v WHERE v.visitor_id = vr.visitor_id AND v.status = 'COMPLETED')
 ORDER BY vr.visitor_id FETCH FIRST 8 ROWS ONLY;

PROMPT N6  CORRELATED subquery: the LATEST movement of each inmate who has been moved at least twice
SELECT m.inmate_id, m.movement_date, m.from_block, m.to_block, m.reason
  FROM movements m
 WHERE m.movement_date = (SELECT MAX(m2.movement_date) FROM movements m2 WHERE m2.inmate_id = m.inmate_id)
   AND (SELECT COUNT(*) FROM movements m3 WHERE m3.inmate_id = m.inmate_id) >= 2
 ORDER BY m.inmate_id;

PROMPT N7  IN with subquery: inmates housed in HIGH-security blocks
SELECT inmate_no, full_name, risk_level FROM inmates
 WHERE block_id IN (SELECT block_id FROM blocks WHERE security_level = 'HIGH') AND status = 'ACTIVE' ORDER BY inmate_no;

PROMPT N8  Subquery in FROM (inline view): block with the highest occupancy percentage
SELECT block_name, occupancy_pct FROM (SELECT block_name, occupancy_pct FROM v_block_occupancy ORDER BY occupancy_pct DESC)
 WHERE ROWNUM = 1;

PROMPT ======================= F11  SET OPERATIONS =======================

PROMPT S1  UNION: every person flagged somewhere - blacklisted visitors plus visitors with an active conflict
SELECT visitor_id, 'BLACKLISTED' AS flagged_because FROM visitors WHERE approval_status = 'BLACKLISTED'
UNION
SELECT visitor_id, 'ACTIVE CONFLICT' FROM conflicts WHERE resolved = 'N'
ORDER BY visitor_id;

PROMPT S2  INTERSECT: inmates who have BOTH a visit and a movement besides admission
SELECT inmate_id FROM visits
INTERSECT
SELECT inmate_id FROM movements WHERE from_block IS NOT NULL
ORDER BY inmate_id;

PROMPT S3  MINUS (= EXCEPT in other DBMS): inmates who have visits but were NEVER transferred
SELECT inmate_id FROM visits
MINUS
SELECT inmate_id FROM movements WHERE from_block IS NOT NULL
ORDER BY inmate_id FETCH FIRST 10 ROWS ONLY;

PROMPT S4  UNION ALL keeps duplicates: all people who appear in the audit log or the visit table (counts rows)
SELECT COUNT(*) AS rows_union_all FROM (SELECT visitor_id FROM visits UNION ALL SELECT record_id FROM audit_log WHERE action_type = 'VISIT_DENIED');

PROMPT ======================= F12  WINDOW FUNCTIONS =======================

PROMPT W1  RANK inmates by visit count WITHIN each block (PARTITION BY ... ORDER BY)
SELECT block_name, inmate_no, visits,
       RANK()       OVER (PARTITION BY block_name ORDER BY visits DESC) AS rank_in_block,
       ROW_NUMBER() OVER (PARTITION BY block_name ORDER BY visits DESC, inmate_no) AS row_no,
       DENSE_RANK() OVER (PARTITION BY block_name ORDER BY visits DESC) AS dense_rank
  FROM (SELECT b.block_name, i.inmate_no, COUNT(v.visit_id) AS visits
          FROM inmates i JOIN blocks b ON b.block_id = i.block_id
          LEFT JOIN visits v ON v.inmate_id = i.inmate_id
         WHERE i.status = 'ACTIVE' GROUP BY b.block_name, i.inmate_no)
 ORDER BY block_name, rank_in_block, inmate_no FETCH FIRST 15 ROWS ONLY;

PROMPT W2  RUNNING TOTAL of visits per month, plus the change versus the previous month (LAG)
SELECT visit_month, visits,
       SUM(visits) OVER (ORDER BY visit_month)                    AS running_total,
       visits - LAG(visits) OVER (ORDER BY visit_month)           AS change_vs_prev_month
  FROM v_monthly_visit_stats ORDER BY visit_month;

PROMPT W3  Most RECENT visit of each inmate (ROW_NUMBER = 1 per partition) - first 8 inmates
SELECT inmate_id, visit_date, slot, status FROM (
  SELECT v.inmate_id, v.visit_date, v.slot, v.status,
         ROW_NUMBER() OVER (PARTITION BY v.inmate_id ORDER BY v.visit_date DESC, v.slot DESC) AS rn
    FROM visits v)
 WHERE rn = 1 ORDER BY inmate_id FETCH FIRST 8 ROWS ONLY;

PROMPT W4  Share of each block in the facility total (window SUM without ORDER BY)
SELECT block_name, occupied, ROUND(100 * occupied / SUM(occupied) OVER (), 1) AS pct_of_all_inmates
  FROM v_block_occupancy ORDER BY block_name;

PROMPT ======================= F36  PAGINATION =======================

PROMPT P1  Second page of active inmates (stable sort, 5 rows per page)
SELECT inmate_no, full_name, block_id
  FROM inmates
 WHERE status = 'ACTIVE'
 ORDER BY inmate_no
 OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY;

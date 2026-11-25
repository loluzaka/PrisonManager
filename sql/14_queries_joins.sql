-- =============================================================================
-- 14_queries_joins.sql
-- Feature : F10 (joins: inner, left, right, full outer, self, multi-table)
-- Owner   : Member 1
-- RUN AS  : PRISON_OWNER, after 13_queries_select_aggregate.sql      (read-only script)
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON
SET LINESIZE 170
SET PAGESIZE 60
COLUMN inmate_name FORMAT A22
COLUMN visitor_name FORMAT A22
COLUMN full_name FORMAT A22
COLUMN from_block FORMAT A10
COLUMN to_block FORMAT A10
COLUMN reason FORMAT A28

PROMPT J1  INNER JOIN (3 tables): today's visits with inmate and visitor names
SELECT v.visit_date, v.slot, i.full_name AS inmate_name, vr.full_name AS visitor_name, v.status
  FROM visits v
  INNER JOIN inmates  i  ON i.inmate_id   = v.inmate_id
  INNER JOIN visitors vr ON vr.visitor_id = v.visitor_id
 WHERE v.visit_date = TRUNC(SYSDATE)
 ORDER BY v.slot, i.full_name;

PROMPT J2  LEFT JOIN: inmates who have NEVER had a visit of any kind (no match => NULL on the right)
SELECT i.inmate_no, i.full_name, i.status, v.visit_id
  FROM inmates i LEFT JOIN visits v ON v.inmate_id = i.inmate_id
 WHERE v.visit_id IS NULL
 ORDER BY i.inmate_no;

PROMPT J3  RIGHT JOIN: every visitor, with the number of visits (visitors without visits show 0)
SELECT vr.visitor_id, vr.full_name, vr.approval_status, COUNT(v.visit_id) AS visits
  FROM visits v RIGHT JOIN visitors vr ON vr.visitor_id = v.visitor_id
 GROUP BY vr.visitor_id, vr.full_name, vr.approval_status
 ORDER BY visits, vr.visitor_id FETCH FIRST 8 ROWS ONLY;

PROMPT J4  FULL OUTER JOIN: facilities versus blocks - a facility without blocks or a block without facility would also appear (none here)
SELECT f.facility_name, b.block_name, b.capacity
  FROM facilities f FULL OUTER JOIN blocks b ON b.facility_id = f.facility_id
 ORDER BY f.facility_name, b.block_name;

PROMPT J5  MULTI-TABLE JOIN joining BLOCKS twice: movement history with origin and destination names
SELECT m.movement_date, i.inmate_no, i.full_name AS inmate_name,
       NVL(fb.block_name, '(admission)') AS from_block, tb.block_name AS to_block, m.reason
  FROM movements m
  JOIN inmates i       ON i.inmate_id = m.inmate_id
  LEFT JOIN blocks fb  ON fb.block_id = m.from_block
  JOIN blocks tb       ON tb.block_id = m.to_block
 WHERE m.from_block IS NOT NULL
 ORDER BY m.movement_date DESC;

PROMPT J6  SELF JOIN: every pair of inmates who are rivals, with both names (INMATES joined to itself)
SELECT a.inmate_no AS inmate_1, a.full_name AS name_1, ba.block_name AS block_1,
       b.inmate_no AS inmate_2, b.full_name AS name_2, bb.block_name AS block_2, ic.reason
  FROM inmate_conflicts ic
  JOIN inmates a ON a.inmate_id = ic.inmate_a
  JOIN inmates b ON b.inmate_id = ic.inmate_b
  JOIN blocks ba ON ba.block_id = a.block_id
  JOIN blocks bb ON bb.block_id = b.block_id
 WHERE ic.resolved = 'N';

PROMPT J7  SELF JOIN: pairs of ACTIVE inmates housed in the same block (a.id < b.id avoids mirror pairs) - first 6
SELECT a.inmate_no AS inmate_1, b.inmate_no AS inmate_2, bl.block_name
  FROM inmates a JOIN inmates b ON a.block_id = b.block_id AND a.inmate_id < b.inmate_id
  JOIN blocks bl ON bl.block_id = a.block_id
 WHERE a.status = 'ACTIVE' AND b.status = 'ACTIVE' AND bl.block_name = 'E-Block'
 ORDER BY a.inmate_id, b.inmate_id FETCH FIRST 6 ROWS ONLY;

PROMPT J8  All conflicting inmate-visitor pairs with their state
SELECT i.inmate_no, i.full_name AS inmate_name, vr.full_name AS visitor_name, c.reason, c.flagged_date, c.resolved
  FROM conflicts c JOIN inmates i ON i.inmate_id = c.inmate_id JOIN visitors vr ON vr.visitor_id = c.visitor_id
 ORDER BY c.flagged_date;

PROMPT J9  Four-table join: visits with facility, block, inmate and visitor (last 5 completed)
SELECT v.visit_date, f.facility_name, b.block_name, i.inmate_no, vr.full_name AS visitor_name
  FROM visits v
  JOIN inmates i    ON i.inmate_id    = v.inmate_id
  JOIN blocks b     ON b.block_id     = i.block_id
  JOIN facilities f ON f.facility_id  = b.facility_id
  JOIN visitors vr  ON vr.visitor_id  = v.visitor_id
 WHERE v.status = 'COMPLETED'
 ORDER BY v.visit_date DESC, v.slot FETCH FIRST 5 ROWS ONLY;

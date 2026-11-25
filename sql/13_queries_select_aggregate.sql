-- =============================================================================
-- 13_queries_select_aggregate.sql
-- Features : F8 (SELECT: filters, sorting, functions), F9 (aggregation and grouping)
-- Owner    : Member 1
-- RUN AS   : PRISON_OWNER (or any user with SELECT on the tables), after 12_dml_demo.sql
-- Read-only script: it changes no data.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON
SET LINESIZE 170
SET PAGESIZE 60
COLUMN full_name FORMAT A24
COLUMN inmate_name FORMAT A24
COLUMN block_name FORMAT A10
COLUMN slot FORMAT A12

PROMPT ======================= F8  SELECT, WHERE, ORDER BY =======================

PROMPT Q8.1  Active inmates in block 2, newest sentence first (WHERE + AND + ORDER BY)
SELECT inmate_id, inmate_no, full_name, risk_level, sentence_start
  FROM inmates WHERE block_id = 2 AND status = 'ACTIVE' ORDER BY sentence_start DESC;

PROMPT Q8.2  Visitors that are NOT approved (logical operators NOT / IN / OR)
SELECT visitor_id, full_name, approval_status FROM visitors
 WHERE approval_status NOT IN ('APPROVED') ORDER BY approval_status, visitor_id;

PROMPT Q8.3  Visits in a date range (BETWEEN) for HIGH or MEDIUM-risk inmates
SELECT v.visit_id, v.visit_date, v.slot, i.risk_level
  FROM visits v JOIN inmates i ON i.inmate_id = v.inmate_id
 WHERE v.visit_date BETWEEN TRUNC(SYSDATE) - 14 AND TRUNC(SYSDATE)
   AND (i.risk_level = 'HIGH' OR i.risk_level = 'MEDIUM')
 ORDER BY v.visit_date, v.slot;

PROMPT Q8.4  Pattern search (LIKE, case-insensitive with UPPER)
SELECT inmate_no, full_name FROM inmates WHERE UPPER(full_name) LIKE '%KHAN%' OR UPPER(full_name) LIKE 'A%' ORDER BY full_name;

PROMPT ======================= F8  scalar functions =======================

PROMPT Q8.5  String functions: UPPER, TRIM, SUBSTR, LENGTH, INSTR, REPLACE, concatenation
SELECT visitor_id,
       UPPER(TRIM(full_name))                         AS name_upper,
       LENGTH(full_name)                              AS name_length,
       SUBSTR(full_name, 1, INSTR(full_name, ' ') - 1) AS first_name,
       REPLACE(phone, '-', '')                        AS phone_digits,
       '****' || SUBSTR(id_proof_number, -4)          AS masked_id
  FROM visitors WHERE visitor_id <= 5 ORDER BY visitor_id;

PROMPT Q8.6  Date arithmetic: days left, months served, weekday of release
SELECT inmate_no,
       sentence_end - TRUNC(SYSDATE)                               AS days_left,
       ROUND(MONTHS_BETWEEN(TRUNC(SYSDATE), sentence_start), 1)    AS months_served,
       TO_CHAR(sentence_end, 'DY DD-MON-YYYY')                     AS release_day,
       ADD_MONTHS(sentence_end, 6)                                 AS date_plus_6_months,
       NEXT_DAY(sentence_end, 'MONDAY')                            AS next_monday_after
  FROM inmates WHERE inmate_id IN (3, 14, 19) ORDER BY sentence_end;

PROMPT Q8.7  Numeric functions: ROUND, TRUNC, MOD, CEIL, FLOOR, ABS and a CASE expression
SELECT block_name, capacity,
       ROUND(capacity / 3, 2) AS third_rounded, CEIL(capacity / 3) AS third_ceil,
       FLOOR(capacity / 3)    AS third_floor,   MOD(capacity, 4)   AS remainder_div_4,
       CASE WHEN capacity >= 12 THEN 'LARGE' WHEN capacity >= 8 THEN 'MEDIUM' ELSE 'SMALL' END AS size_class
  FROM blocks ORDER BY capacity DESC;

PROMPT Q8.8  NULL handling: NVL / COALESCE (admissions have no origin block)
SELECT movement_id, inmate_id, NVL(TO_CHAR(from_block), 'ADMISSION') AS origin, to_block, reason
  FROM movements WHERE inmate_id IN (2, 5) ORDER BY inmate_id, movement_date;

PROMPT Q8.9  Own functions inside SELECT (F19): visit count and days remaining
SELECT inmate_id, full_name, fn_inmate_visit_count(inmate_id) AS visits, fn_days_remaining(inmate_id) AS days_left
  FROM inmates WHERE status = 'ACTIVE' AND ROWNUM <= 5 ORDER BY inmate_id;

PROMPT ======================= F9  aggregation =======================

PROMPT Q9.1  COUNT, SUM, AVG, MIN, MAX over all blocks
SELECT COUNT(*) AS blocks, SUM(capacity) AS total_beds, ROUND(AVG(capacity), 1) AS avg_capacity,
       MIN(capacity) AS smallest, MAX(capacity) AS largest
  FROM blocks;

PROMPT Q9.2  Occupancy per block (GROUP BY)
SELECT b.block_name, b.capacity, COUNT(i.inmate_id) AS occupied
  FROM blocks b LEFT JOIN inmates i ON i.block_id = b.block_id AND i.status = 'ACTIVE'
 GROUP BY b.block_name, b.capacity ORDER BY b.block_name;

PROMPT Q9.3  Visits per inmate per month, only inmates with 2+ visits in a month (HAVING)
SELECT i.inmate_no, TO_CHAR(v.visit_date, 'YYYY-MM') AS visit_month, COUNT(*) AS visits
  FROM visits v JOIN inmates i ON i.inmate_id = v.inmate_id
 GROUP BY i.inmate_no, TO_CHAR(v.visit_date, 'YYYY-MM')
HAVING COUNT(*) >= 2
 ORDER BY visit_month DESC, visits DESC, i.inmate_no;

PROMPT Q9.4  Busiest time slots
SELECT slot, COUNT(*) AS bookings FROM visits WHERE status <> 'CANCELLED' GROUP BY slot ORDER BY bookings DESC, slot;

PROMPT Q9.5  Denied attempts per visitor (from the audit trail)
SELECT record_id AS visitor_id, COUNT(*) AS denied_attempts, MIN(changed_at) AS first_attempt, MAX(changed_at) AS last_attempt
  FROM audit_log WHERE action_type = 'VISIT_DENIED' GROUP BY record_id ORDER BY denied_attempts DESC, visitor_id;

PROMPT Q9.6  Visit status mix with percentages
SELECT status, COUNT(*) AS visits, ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
  FROM visits GROUP BY status ORDER BY visits DESC;

PROMPT Q9.7  Inmates per status and risk level (two grouping columns, ROLLUP subtotals)
SELECT NVL(status, 'ALL') AS status, NVL(risk_level, 'ALL') AS risk_level, COUNT(*) AS inmates
  FROM inmates GROUP BY ROLLUP (status, risk_level) ORDER BY status, risk_level;

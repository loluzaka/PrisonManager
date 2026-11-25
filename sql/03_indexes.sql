-- =============================================================================
-- 03_indexes.sql
-- Feature : F5 (indexes for performance)
-- Owner   : Member 1
-- RUN AS  : PRISON_OWNER, after 02_alter_schema.sql
--
-- Oracle automatically indexes every PRIMARY KEY and UNIQUE constraint, but NOT foreign
-- keys. This script adds B-tree indexes on the columns used in joins and filters.
--
-- NOTE: CONFLICTS(inmate_id, visitor_id) is already indexed by constraint UQ_CONF_PAIR, so
-- creating a second identical index would raise ORA-01408; the existing one is reused.
-- NOTE: IDX_VISITS_INMATE_DATE overlaps the leading columns of UQ_VISITS_INMATE_SLOT. It is
-- kept because the specification asks for it and it is narrower (cheaper range scans).
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

CREATE INDEX idx_inmates_block        ON inmates (block_id);
CREATE INDEX idx_inmates_status       ON inmates (status);
CREATE INDEX idx_visits_date          ON visits (visit_date);
CREATE INDEX idx_visits_inmate_date   ON visits (inmate_id, visit_date);
CREATE INDEX idx_visits_visitor       ON visits (visitor_id);
CREATE INDEX idx_movements_inmate     ON movements (inmate_id);
CREATE INDEX idx_movements_to_block   ON movements (to_block);
CREATE INDEX idx_audit_table_record   ON audit_log (table_name, record_id);
CREATE INDEX idx_audit_action         ON audit_log (action_type, changed_at);
CREATE INDEX idx_blocks_facility      ON blocks (facility_id);

-- ---------------------------------------------------------------- EXPLAIN PLAN DEMO
-- The 100 seed visits are too few for the optimizer to prefer an index, so we build a
-- scratch table with 100,000 rows, compare plans without / with an index, then drop it.
SET ECHO ON
SET LINESIZE 160
SET PAGESIZE 100

CREATE TABLE visits_big AS
  SELECT LEVEL AS visit_id,
         MOD(LEVEL, 5000) + 1                   AS inmate_id,
         TRUNC(SYSDATE) - MOD(LEVEL, 1000)      AS visit_date
  FROM dual CONNECT BY LEVEL <= 100000;

EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'VISITS_BIG');

PROMPT ---- Plan WITHOUT an index (expect TABLE ACCESS FULL):
EXPLAIN PLAN FOR
  SELECT * FROM visits_big WHERE inmate_id = 43 AND visit_date = TRUNC(SYSDATE) - 42;
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST'));

CREATE INDEX idx_visits_big ON visits_big (inmate_id, visit_date);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'VISITS_BIG');

PROMPT ---- Plan WITH the composite index (expect INDEX RANGE SCAN):
EXPLAIN PLAN FOR
  SELECT * FROM visits_big WHERE inmate_id = 43 AND visit_date = TRUNC(SYSDATE) - 42;
SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST'));

DROP TABLE visits_big PURGE;
SET ECHO OFF
PROMPT 03_indexes.sql finished.


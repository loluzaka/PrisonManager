-- =============================================================================
-- connection_check.sql
-- Features : F29 (remote connection demonstration), F32 (secure access)
-- Owner    : Member 3
-- RUN AS   : PRISON_OWNER (or any project user) connected to the CLOUD database
--
-- Prints evidence that the session really is on a remote managed service:
-- database name, service, server host, protocol (TCPS = TLS encrypted), user and object counts.
-- Take a screenshot of this output for the project report.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK OFF
SET LINESIZE 150
COLUMN item  FORMAT A28
COLUMN value FORMAT A90

SELECT 'database name'      AS item, SYS_CONTEXT('USERENV', 'DB_NAME')         AS value FROM dual UNION ALL
SELECT 'service name',               SYS_CONTEXT('USERENV', 'SERVICE_NAME')    FROM dual UNION ALL
SELECT 'server host',                SYS_CONTEXT('USERENV', 'SERVER_HOST')     FROM dual UNION ALL
SELECT 'network protocol',           SYS_CONTEXT('USERENV', 'NETWORK_PROTOCOL')FROM dual UNION ALL
SELECT 'client address',             SYS_CONTEXT('USERENV', 'IP_ADDRESS')      FROM dual UNION ALL
SELECT 'session user',               SYS_CONTEXT('USERENV', 'SESSION_USER')    FROM dual UNION ALL
SELECT 'database version',           (SELECT product || ' ' || version_full FROM product_component_version FETCH FIRST 1 ROW ONLY) FROM dual;

SELECT object_type, COUNT(*) AS objects FROM user_objects GROUP BY object_type ORDER BY object_type;
SELECT 'inmates' AS tbl, COUNT(*) AS row_count FROM inmates UNION ALL
SELECT 'visitors', COUNT(*) FROM visitors UNION ALL
SELECT 'visits',   COUNT(*) FROM visits;
PROMPT connection_check.sql finished.

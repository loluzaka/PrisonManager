-- =============================================================================
-- 12_dml_demo.sql
-- Feature : F7 (data entry and changes: INSERT, UPDATE, DELETE, bulk inserts, rejected rows)
-- Owner   : Member 1
-- RUN AS  : PRISON_OWNER, after 11_views.sql
--
-- Every change is made inside this script's own transaction and finished with ROLLBACK, so the
-- seed data is left exactly as it was. (Audit rows written through the autonomous transaction
-- of a refused insert are the one intentional exception - they are meant to survive.)
-- Constraint violations are caught in PL/SQL and printed, so the script never aborts.
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET LINESIZE 160

PROMPT === 1. INSERT one row (visitor) - approval_status takes its DEFAULT 'PENDING'
INSERT INTO visitors (full_name, id_proof_type, id_proof_number, phone)
VALUES ('Demo Visitor One', 'PASSPORT', 'SYN-DEMO01', '+00-555-9001');

PROMPT === 2. BULK INSERT: several rows in ONE statement (INSERT ... SELECT ... UNION ALL)
-- (INSERT ALL ... INTO is not used: with an IDENTITY column it would give every row the same new ID.)
INSERT INTO visitors (full_name, id_proof_type, id_proof_number)
SELECT 'Demo Visitor Two',   'NATIONAL_ID', 'SYN-DEMO02' FROM dual UNION ALL
SELECT 'Demo Visitor Three', 'VOTER_ID',    'SYN-DEMO03' FROM dual UNION ALL
SELECT 'Demo Visitor Four',  'PASSPORT',    'SYN-DEMO04' FROM dual;

PROMPT === 3. BULK INSERT ... SELECT (copy rows computed by a query)
INSERT INTO visitors (full_name, id_proof_type, id_proof_number, phone)
SELECT 'Generated Visitor ' || LEVEL, 'DRIVING_LICENCE', 'SYN-GEN' || LPAD(LEVEL, 3, '0'), NULL
  FROM dual CONNECT BY LEVEL <= 5;

SELECT COUNT(*) AS demo_visitors_now FROM visitors WHERE id_proof_number LIKE 'SYN-DEMO%' OR id_proof_number LIKE 'SYN-GEN%';

PROMPT === 4. UPDATE (single row, then several rows)
UPDATE visitors SET approval_status = 'APPROVED' WHERE id_proof_number = 'SYN-DEMO01';
UPDATE visitors SET phone = '+00-555-0000' WHERE id_proof_number LIKE 'SYN-GEN%';

PROMPT === 5. DELETE (allowed here: these demo visitors have no visits, conflicts or history)
DELETE FROM visitors WHERE id_proof_number LIKE 'SYN-GEN%';

PROMPT === 6. Invalid data is REJECTED at the source (each attempt is caught and printed)
DECLARE
  PROCEDURE attempt (p_title VARCHAR2, p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('UNEXPECTEDLY ACCEPTED: ' || p_title);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('rejected  ' || RPAD(p_title, 34) || SQLERRM);
  END;
BEGIN
  attempt('negative block capacity',
    'INSERT INTO blocks (block_name, capacity, security_level, facility_id) VALUES (''X'', -5, ''LOW'', 1)');
  attempt('unknown security level',
    'INSERT INTO blocks (block_name, capacity, security_level, facility_id) VALUES (''X'', 5, ''EXTREME'', 1)');
  attempt('sentence ends before it starts',
    'INSERT INTO inmates (inmate_no, full_name, date_of_birth, sentence_start, sentence_end, block_id) ' ||
    'VALUES (''INM-X1'', ''Bad Dates'', DATE ''1990-01-01'', DATE ''2030-01-01'', DATE ''2029-01-01'', 1)');
  attempt('duplicate ID proof',
    'INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES (''Dup'', ''PASSPORT'', ''SYN-DEMO01'')');
  attempt('missing NOT NULL (full_name)',
    'INSERT INTO visitors (id_proof_type, id_proof_number) VALUES (''PASSPORT'', ''SYN-DEMO99'')');
  attempt('visit with unknown inmate (FK)',
    'INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (9999, 1, TRUNC(SYSDATE), ''09:00-10:00'')');
  attempt('visit with invalid slot name',
    'INSERT INTO visits (inmate_id, visitor_id, visit_date, slot) VALUES (1, 1, TRUNC(SYSDATE)+20, ''23:00-24:00'')');
  attempt('delete inmate that has history (FK)',
    'DELETE FROM inmates WHERE inmate_id = 1');
  attempt('delete block that has inmates (FK)',
    'DELETE FROM blocks WHERE block_id = 1');
END;
/

PROMPT === 7. Undo everything done by this script
ROLLBACK;
SELECT COUNT(*) AS demo_visitors_after_rollback FROM visitors WHERE id_proof_number LIKE 'SYN-DEMO%';
PROMPT 12_dml_demo.sql finished.

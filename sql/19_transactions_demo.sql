-- =============================================================================
-- 19_transactions_demo.sql
-- Feature : F24 (transactions: ACID, COMMIT, ROLLBACK, SAVEPOINT, isolation levels, locks)
-- Owner   : Member 2
-- RUN AS  : PRISON_OWNER, after 18_scheduled_jobs.sql (single-session part of F24;
--           the two-session part is scripts 20 and 21)
--
-- Uses throw-away rows (id proof numbers SYN-TXN%) and cleans up after itself.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 160

PROMPT === A. Atomicity: a transaction is all-or-nothing (ROLLBACK undoes it)
INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES ('Txn Demo A', 'PASSPORT', 'SYN-TXN-A');
SELECT COUNT(*) AS visible_inside_my_transaction FROM visitors WHERE id_proof_number = 'SYN-TXN-A';
ROLLBACK;
SELECT COUNT(*) AS after_rollback FROM visitors WHERE id_proof_number = 'SYN-TXN-A';

PROMPT === B. Durability: after COMMIT the change stays
INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES ('Txn Demo B', 'PASSPORT', 'SYN-TXN-B');
COMMIT;
SELECT COUNT(*) AS after_commit FROM visitors WHERE id_proof_number = 'SYN-TXN-B';

PROMPT === C. SAVEPOINT: undo only PART of a transaction
INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES ('Txn Demo C1', 'PASSPORT', 'SYN-TXN-C1');
SAVEPOINT after_first_insert;
INSERT INTO visitors (full_name, id_proof_type, id_proof_number) VALUES ('Txn Demo C2', 'PASSPORT', 'SYN-TXN-C2');
SELECT COUNT(*) AS both_rows_present FROM visitors WHERE id_proof_number IN ('SYN-TXN-C1', 'SYN-TXN-C2');
ROLLBACK TO SAVEPOINT after_first_insert;
SELECT id_proof_number AS only_first_row_left FROM visitors WHERE id_proof_number IN ('SYN-TXN-C1', 'SYN-TXN-C2');
ROLLBACK;

PROMPT === D. Consistency: a failing statement leaves no partial result; sp_transfer_inmate is all-or-nothing
DECLARE
  v_status VARCHAR2(30); v_msg VARCHAR2(400);
  v_before NUMBER; v_after NUMBER; v_mov_before NUMBER; v_mov_after NUMBER;
BEGIN
  SELECT block_id INTO v_before FROM inmates WHERE inmate_id = 27;          -- HIGH-risk inmate (27) in C-Block
  SELECT COUNT(*) INTO v_mov_before FROM movements WHERE inmate_id = 27;
  sp_transfer_inmate(27, 1, 'illegal move to LOW-security A-Block', v_status, v_msg);
  SELECT block_id INTO v_after FROM inmates WHERE inmate_id = 27;
  SELECT COUNT(*) INTO v_mov_after FROM movements WHERE inmate_id = 27;
  DBMS_OUTPUT.PUT_LINE('status=' || v_status || ' | ' || v_msg);
  DBMS_OUTPUT.PUT_LINE('block before=' || v_before || ' after=' || v_after ||
                       ' | movements before=' || v_mov_before || ' after=' || v_mov_after || '  (unchanged = rollback worked)');
END;
/

PROMPT === E. Isolation levels (transaction-level) and row locks
-- READ COMMITTED is Oracle's default: each statement sees data committed before IT started.
-- SERIALIZABLE: the whole transaction sees one snapshot; a conflicting concurrent update gives ORA-08177.
-- SET TRANSACTION must be the FIRST statement of a transaction, so end the open one first
COMMIT;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS serializable_snapshot_count FROM visitors WHERE id_proof_number LIKE 'SYN-TXN%';
-- ends the transaction, isolation level returns to default
COMMIT;
-- a consistent read-only snapshot (good for reports)
SET TRANSACTION READ ONLY;
SELECT COUNT(*) AS read_only_snapshot_count FROM inmates;
COMMIT;

PROMPT Row lock: SELECT ... FOR UPDATE locks the row until COMMIT/ROLLBACK
SELECT block_id, block_name, capacity FROM blocks WHERE block_id = 3 FOR UPDATE;
SELECT 'row lock held until we end the transaction' AS note FROM dual;
-- releases the lock
ROLLBACK;

PROMPT === Cleanup
DELETE FROM visitors WHERE id_proof_number LIKE 'SYN-TXN%';
COMMIT;
SELECT COUNT(*) AS txn_demo_rows_left FROM visitors WHERE id_proof_number LIKE 'SYN-TXN%';
PROMPT 19_transactions_demo.sql finished.

-- =============================================================================
-- 10_cursors.sql
-- Feature : F20 (explicit cursors c_daily_roster, c_block_occupancy, c_upcoming_release)
-- Owner   : Member 2
-- RUN AS  : PRISON_OWNER, after 09_procedures.sql
--
-- A CURSOR is a named pointer to the result set of a query. An EXPLICIT cursor lets PL/SQL
-- walk that result ONE ROW AT A TIME with the lifecycle
--      DECLARE (CURSOR ... IS SELECT) -> OPEN -> FETCH (loop) -> test %NOTFOUND -> CLOSE.
--   PR_DAILY_ROSTER      c_daily_roster(p_date)   PARAMETERISED cursor, manual OPEN/FETCH/CLOSE,
--                        %NOTFOUND, %ROWCOUNT and control-break (new block => new heading)
--   PR_BLOCK_OCCUPANCY   c_block_occupancy        manual OPEN/FETCH/CLOSE, %ISOPEN, flags blocks
--                        AT / OVER capacity
--   PR_UPCOMING_RELEASES c_upcoming_release(days) cursor FOR loop (PL/SQL opens, fetches and
--                        closes automatically)
--   FN_ROSTER_REFCURSOR  returns a SYS_REFCURSOR so a client (SQL*Plus, Java, Python) can fetch
-- Output goes to DBMS_OUTPUT: run  SET SERVEROUTPUT ON  first.
-- =============================================================================
SET ECHO OFF
SET FEEDBACK ON

-- ---------------------------------------------------------------- c_daily_roster
CREATE OR REPLACE PROCEDURE pr_daily_roster (p_date IN DATE DEFAULT TRUNC(SYSDATE)) IS
  -- 1. DECLARE: the cursor takes a date parameter and returns visits ordered by block, then time
  CURSOR c_daily_roster (cp_date IN DATE) IS
    SELECT b.block_id, b.block_name, v.slot, v.status AS visit_status,
           i.inmate_no, i.full_name AS inmate_name,
           vr.full_name AS visitor_name
      FROM visits v
      JOIN inmates  i  ON i.inmate_id   = v.inmate_id
      JOIN blocks   b  ON b.block_id    = i.block_id
      JOIN visitors vr ON vr.visitor_id = v.visitor_id
     WHERE v.visit_date = TRUNC(cp_date) AND v.status <> 'CANCELLED'
     ORDER BY b.block_name, v.slot, i.inmate_no;

  r_row        c_daily_roster%ROWTYPE;     -- a record shaped exactly like one row of the cursor
  v_prev_block blocks.block_id%TYPE := -1;
BEGIN
  DBMS_OUTPUT.PUT_LINE('===== DAILY VISIT ROSTER for ' || TO_CHAR(TRUNC(p_date), 'DD-MON-YYYY') || ' =====');
  OPEN c_daily_roster(p_date);                                  -- 2. OPEN: runs the query
  LOOP
    FETCH c_daily_roster INTO r_row;                            -- 3. FETCH: next row into the record
    EXIT WHEN c_daily_roster%NOTFOUND;                          -- 4. no more rows? leave the loop
    IF r_row.block_id <> v_prev_block THEN                      -- control break: new block heading
      DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ' || r_row.block_name || ' ---');
      v_prev_block := r_row.block_id;
    END IF;
    DBMS_OUTPUT.PUT_LINE(                                       -- 5. process the row
      LPAD(c_daily_roster%ROWCOUNT, 3) || '. ' || r_row.slot || '  ' ||
      RPAD(r_row.inmate_no || ' ' || r_row.inmate_name, 28) || ' <- ' ||
      RPAD(r_row.visitor_name, 20) || ' [' || r_row.visit_status || ']');
  END LOOP;
  IF c_daily_roster%ROWCOUNT = 0 THEN
    DBMS_OUTPUT.PUT_LINE('(no visits scheduled)');
  ELSE
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Total visits listed: ' || c_daily_roster%ROWCOUNT);
  END IF;
  CLOSE c_daily_roster;                                         -- 6. CLOSE: frees the memory
EXCEPTION
  WHEN OTHERS THEN
    IF c_daily_roster%ISOPEN THEN CLOSE c_daily_roster; END IF; -- never leak an open cursor
    RAISE;
END pr_daily_roster;
/

-- ---------------------------------------------------------------- c_block_occupancy
CREATE OR REPLACE PROCEDURE pr_block_occupancy IS
  CURSOR c_block_occupancy IS
    SELECT b.block_id, b.block_name, b.capacity, b.security_level, f.facility_name
      FROM blocks b JOIN facilities f ON f.facility_id = b.facility_id
     ORDER BY b.block_id;

  r_block    c_block_occupancy%ROWTYPE;
  v_occupied NUMBER;
  v_pct      NUMBER;
  v_flag     VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.PUT_LINE('===== BLOCK OCCUPANCY =====');
  OPEN c_block_occupancy;
  DBMS_OUTPUT.PUT_LINE('cursor open? ' || CASE WHEN c_block_occupancy%ISOPEN THEN 'YES' ELSE 'NO' END);
  LOOP
    FETCH c_block_occupancy INTO r_block;
    EXIT WHEN c_block_occupancy%NOTFOUND;
    v_occupied := fn_block_occupancy(r_block.block_id);
    v_pct      := ROUND(v_occupied / r_block.capacity * 100, 1);
    v_flag     := CASE WHEN v_occupied > r_block.capacity  THEN '*** OVER CAPACITY'
                       WHEN v_occupied = r_block.capacity  THEN '** AT CAPACITY'
                       ELSE 'ok' END;
    DBMS_OUTPUT.PUT_LINE(
      RPAD(r_block.block_name, 9) || RPAD(r_block.security_level, 8) ||
      LPAD(v_occupied, 3) || '/' || RPAD(r_block.capacity, 4) ||
      LPAD(TO_CHAR(v_pct, 'FM990.0'), 6) || '%  ' || RPAD(v_flag, 18) || r_block.facility_name);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('blocks processed: ' || c_block_occupancy%ROWCOUNT);
  CLOSE c_block_occupancy;
EXCEPTION
  WHEN OTHERS THEN
    IF c_block_occupancy%ISOPEN THEN CLOSE c_block_occupancy; END IF;
    RAISE;
END pr_block_occupancy;
/

-- ---------------------------------------------------------------- c_upcoming_release (cursor FOR loop)
CREATE OR REPLACE PROCEDURE pr_upcoming_releases (p_days IN NUMBER DEFAULT 30) IS
  CURSOR c_upcoming_release (cp_days IN NUMBER) IS
    SELECT inmate_id, inmate_no, full_name, sentence_end, block_id
      FROM inmates
     WHERE status = 'ACTIVE' AND sentence_end BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + cp_days
     ORDER BY sentence_end;
  v_count NUMBER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('===== RELEASES DUE WITHIN ' || p_days || ' DAYS =====');
  FOR r IN c_upcoming_release(p_days) LOOP                      -- implicit OPEN / FETCH / CLOSE
    v_count := v_count + 1;
    DBMS_OUTPUT.PUT_LINE(r.inmate_no || '  ' || RPAD(r.full_name, 22) ||
      TO_CHAR(r.sentence_end, 'DD-MON-YYYY') || '  in ' || fn_days_remaining(r.inmate_id) ||
      ' day(s)  block ' || r.block_id);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('inmates due for release: ' || v_count);
END pr_upcoming_releases;
/

-- ---------------------------------------------------------------- REF CURSOR for client programs
CREATE OR REPLACE FUNCTION fn_roster_refcursor (p_date IN DATE) RETURN SYS_REFCURSOR IS
  rc SYS_REFCURSOR;
BEGIN
  OPEN rc FOR
    SELECT b.block_name, v.slot, i.inmate_no, i.full_name AS inmate, vr.full_name AS visitor
      FROM visits v JOIN inmates i ON i.inmate_id = v.inmate_id
                    JOIN blocks b ON b.block_id = i.block_id
                    JOIN visitors vr ON vr.visitor_id = v.visitor_id
     WHERE v.visit_date = TRUNC(p_date) AND v.status <> 'CANCELLED'
     ORDER BY b.block_name, v.slot;
  RETURN rc;                          -- the CALLER fetches and closes it
END fn_roster_refcursor;
/

-- ---------------------------------------------------------------- DEMO RUN
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 160
BEGIN
  pr_daily_roster(TRUNC(SYSDATE));
  DBMS_OUTPUT.PUT_LINE(CHR(10));
  pr_block_occupancy;
  DBMS_OUTPUT.PUT_LINE(CHR(10));
  pr_upcoming_releases(30);
END;
/

PROMPT --- REF CURSOR consumed from SQL*Plus:
VARIABLE rc REFCURSOR
EXEC :rc := fn_roster_refcursor(TRUNC(SYSDATE));
PRINT rc

PROMPT 10_cursors.sql finished.

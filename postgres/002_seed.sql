INSERT INTO facilities (facility_id, facility_name, city) VALUES
    (1, 'Central Correctional Facility', 'Metropolis'),
    (2, 'Riverside Detention Centre', 'Rivertown');

INSERT INTO blocks (block_id, block_name, capacity, security_level, facility_id) VALUES
    (1, 'A-Block', 14, 'LOW', 1),
    (2, 'B-Block', 12, 'MEDIUM', 1),
    (3, 'C-Block', 8, 'HIGH', 1),
    (4, 'D-Block', 10, 'LOW', 2),
    (5, 'E-Block', 6, 'MEDIUM', 2);

INSERT INTO visit_slots (slot_code, start_time, end_time) VALUES
    ('09:00-10:00', '09:00', '10:00'),
    ('10:00-11:00', '10:00', '11:00'),
    ('11:00-12:00', '11:00', '12:00'),
    ('14:00-15:00', '14:00', '15:00'),
    ('15:00-16:00', '15:00', '16:00'),
    ('16:00-17:00', '16:00', '17:00');

WITH names AS (
    SELECT ARRAY['Arjun','Bilal','Chen','Dmitri','Ethan','Farid','Gabriel','Hassan','Ivan','Jamal',
                 'Karan','Liam','Mateo','Nikhil','Omar','Pavel','Qasim','Rohan','Samuel','Tariq',
                 'Umar','Viktor','Wen','Yusuf','Zane']::text[] AS first_names,
           ARRAY['Ahmed','Brown','Chatterjee','Dubois','Evans','Fischer','Garcia','Hussain','Ibrahim','Jensen',
                 'Khan','Lopez','Mehta','Novak','Okafor','Patel','Quinn','Rossi','Singh','Tanaka',
                 'Usman','Verma','Walker','Xu','Young']::text[] AS last_names
), mapped AS (
    SELECT g.i,
           CASE WHEN g.i <= 12 THEN 1 WHEN g.i <= 23 THEN 2 WHEN g.i <= 30 THEN 3
                WHEN g.i <= 39 THEN 4 WHEN g.i <= 45 THEN 5 WHEN g.i = 46 THEN 1
                WHEN g.i = 47 THEN 4 WHEN g.i = 48 THEN 2 WHEN g.i = 49 THEN 1 ELSE 5 END AS block_id,
           CASE WHEN g.i <= 45 THEN 'ACTIVE' WHEN g.i <= 47 THEN 'TRANSFERRED' ELSE 'RELEASED' END AS status,
           CASE WHEN g.i IN (3,14,19,27,33,41) THEN CURRENT_DATE + 5 + g.i - 1500
                WHEN g.i >= 48 THEN CURRENT_DATE - 10 * (g.i - 47) - 700
                ELSE CURRENT_DATE - 100 - ((g.i * 37) % 700) END AS sentence_start,
           CASE WHEN g.i IN (3,14,19,27,33,41) THEN CURRENT_DATE + 5 + g.i
                WHEN g.i >= 48 THEN CURRENT_DATE - 10 * (g.i - 47)
                ELSE CURRENT_DATE - 100 - ((g.i * 37) % 700) + 1000 + ((g.i * 91) % 2500) END AS sentence_end
    FROM generate_series(1, 50) AS g(i)
), generated AS (
    SELECT m.*,
           CASE WHEN m.block_id IN (1,4) THEN 'LOW'
                WHEN m.block_id = 2 THEN CASE WHEN m.i % 3 = 0 THEN 'MEDIUM' ELSE 'LOW' END
                WHEN m.block_id = 5 THEN CASE WHEN m.i % 2 = 0 THEN 'MEDIUM' ELSE 'LOW' END
                ELSE CASE m.i % 3 WHEN 0 THEN 'HIGH' WHEN 1 THEN 'MEDIUM' ELSE 'LOW' END
           END AS risk_level
    FROM mapped m
)
INSERT INTO inmates
    (inmate_id, inmate_no, full_name, date_of_birth, admission_date, sentence_start, sentence_end, status, block_id, risk_level)
SELECT g.i,
       'INM-' || lpad(g.i::text, 4, '0'),
       n.first_names[((g.i * 3) % 25) + 1] || ' ' || n.last_names[((g.i * 7) % 25) + 1],
       CURRENT_DATE - make_interval(years => 22 + ((g.i * 7) % 35), days => (g.i * 11) % 300)::interval,
       g.sentence_start,
       g.sentence_start,
       g.sentence_end,
       g.status,
       g.block_id,
       g.risk_level
FROM generated g CROSS JOIN names n;

WITH names AS (
    SELECT ARRAY['Arjun','Bilal','Chen','Dmitri','Ethan','Farid','Gabriel','Hassan','Ivan','Jamal',
                 'Karan','Liam','Mateo','Nikhil','Omar','Pavel','Qasim','Rohan','Samuel','Tariq',
                 'Umar','Viktor','Wen','Yusuf','Zane']::text[] AS first_names,
           ARRAY['Ahmed','Brown','Chatterjee','Dubois','Evans','Fischer','Garcia','Hussain','Ibrahim','Jensen',
                 'Khan','Lopez','Mehta','Novak','Okafor','Patel','Quinn','Rossi','Singh','Tanaka',
                 'Usman','Verma','Walker','Xu','Young']::text[] AS last_names,
           ARRAY['PASSPORT','NATIONAL_ID','DRIVING_LICENCE','VOTER_ID']::text[] AS id_types
)
INSERT INTO visitors
    (visitor_id, full_name, id_proof_type, id_proof_number, phone, approval_status, registered_on)
SELECT g.i,
       n.first_names[((g.i * 5 + 2) % 25) + 1] || ' ' || n.last_names[((g.i * 11 + 3) % 25) + 1],
       n.id_types[(g.i % 4) + 1],
       'SYN-' || lpad(((g.i * 7919) % 1000000)::text, 6, '0'),
       '+00-555-' || lpad(g.i::text, 4, '0'),
       CASE WHEN g.i <= 30 THEN 'APPROVED' WHEN g.i <= 35 THEN 'PENDING'
            WHEN g.i <= 38 THEN 'BLACKLISTED' ELSE 'REJECTED' END,
       CURRENT_DATE - 200 + g.i
FROM generate_series(1, 40) AS g(i) CROSS JOIN names n;

INSERT INTO conflicts (conflict_id, inmate_id, visitor_id, reason, flagged_date, resolved, resolved_on, expiry_date) VALUES
    (1, 3, 5, 'VICTIM_RELATIVE', CURRENT_DATE - 300, 'N', NULL, NULL),
    (2, 8, 12, 'RIVAL', CURRENT_DATE - 250, 'N', NULL, NULL),
    (3, 15, 7, 'GANG_AFFILIATION', CURRENT_DATE - 200, 'N', NULL, NULL),
    (4, 24, 9, 'RIVAL', CURRENT_DATE - 150, 'N', NULL, CURRENT_DATE + 365),
    (5, 30, 20, 'VICTIM_RELATIVE', CURRENT_DATE - 120, 'N', NULL, NULL),
    (6, 40, 3, 'GANG_AFFILIATION', CURRENT_DATE - 90, 'N', NULL, NULL),
    (7, 1, 2, 'RIVAL', CURRENT_DATE - 180, 'Y', CURRENT_DATE - 30, NULL),
    (8, 10, 4, 'OTHER', CURRENT_DATE - 100, 'N', NULL, CURRENT_DATE - 5);

INSERT INTO inmate_conflicts (rivalry_id, inmate_a, inmate_b, reason) VALUES
    (1, 4, 14, 'RIVAL'),
    (2, 6, 25, 'GANG_AFFILIATION'),
    (3, 18, 26, 'RIVAL');

INSERT INTO movements (inmate_id, from_block, to_block, movement_date, reason, moved_by)
SELECT i.inmate_id, NULL, i.block_id, i.sentence_start::timestamp, 'ADMISSION', 'SEED'
FROM inmates i;

INSERT INTO movements (inmate_id, from_block, to_block, movement_date, reason, moved_by)
SELECT i.inmate_id, ((i.block_id % 5) + 1), i.block_id,
       CURRENT_TIMESTAMP - make_interval(days => 10 + row_number() OVER (ORDER BY i.inmate_id)::integer * 7),
       'Behaviour review transfer', 'SEED'
FROM inmates i
WHERE i.inmate_id IN (2, 9, 16, 21, 33, 36, 44, 46);

INSERT INTO audit_log (table_name, action_type, record_id, details, changed_by, changed_at)
SELECT 'INMATES', 'TRANSFER', i.inmate_id,
       'Seeded transfer into block ' || i.block_id || '; reason=Behaviour review transfer',
       'SEED',
       CURRENT_TIMESTAMP - make_interval(days => 10 + row_number() OVER (ORDER BY i.inmate_id)::integer * 7)
FROM inmates i
WHERE i.inmate_id IN (2, 9, 16, 21, 33, 36, 44, 46);

DO $seed_visits$
DECLARE
    i integer;
    candidate integer := 0;
    inmate_key bigint;
    visitor_key bigint;
    visit_day date;
    visit_slot text;
    visit_status text;
    slot_names text[] := ARRAY['09:00-10:00','10:00-11:00','11:00-12:00',
                               '14:00-15:00','15:00-16:00','16:00-17:00'];
BEGIN
    FOR i IN 0..99 LOOP
        LOOP
            candidate := candidate + 1;
            inmate_key := ((candidate * 7 + candidate / 45) % 45) + 1;
            visitor_key := ((candidate * 11 + candidate / 30 * 3) % 30) + 1;
            visit_slot := slot_names[((candidate * 3 + candidate / 6) % 6) + 1];
            IF i < 8 THEN
                visit_day := CURRENT_DATE;
                visit_status := 'SCHEDULED';
            ELSIF i < 14 THEN
                visit_day := CURRENT_DATE + 1 + (i % 3);
                visit_status := 'SCHEDULED';
            ELSE
                visit_day := CURRENT_DATE - 1 - ((candidate * 5 + candidate / 16 * 3) % 80);
                visit_status := CASE candidate % 25 WHEN 0 THEN 'MISSED' WHEN 1 THEN 'CANCELLED' ELSE 'COMPLETED' END;
            END IF;

            IF EXISTS (
                SELECT 1 FROM conflicts c
                WHERE c.inmate_id = inmate_key AND c.visitor_id = visitor_key
                  AND c.resolved = 'N' AND (c.expiry_date IS NULL OR c.expiry_date >= CURRENT_DATE)
            ) OR NOT EXISTS (
                SELECT 1 FROM inmates i0
                WHERE i0.inmate_id = inmate_key AND visit_day BETWEEN i0.sentence_start AND i0.sentence_end
            ) OR EXISTS (
                SELECT 1 FROM visits v
                WHERE v.inmate_id = inmate_key AND v.visit_date = visit_day AND v.slot = visit_slot
            ) OR (
                visit_status <> 'CANCELLED' AND (
                    SELECT count(*) FROM visits v
                    WHERE v.inmate_id = inmate_key AND v.status <> 'CANCELLED'
                      AND date_trunc('week', v.visit_date)::date = date_trunc('week', visit_day)::date
                ) >= 3
            ) OR (
                visit_status <> 'CANCELLED' AND (
                    SELECT count(*) FROM visits v
                    WHERE v.visit_date = visit_day AND v.slot = visit_slot AND v.status <> 'CANCELLED'
                ) >= 5
            ) THEN
                CONTINUE;
            END IF;

            INSERT INTO visits (inmate_id, visitor_id, visit_date, slot, status, booked_on)
            VALUES (inmate_key, visitor_key, visit_day, visit_slot, visit_status, visit_day::timestamptz - interval '3 days');
            EXIT;
        END LOOP;
    END LOOP;
END
$seed_visits$;

INSERT INTO audit_log (table_name, action_type, record_id, details, changed_by, changed_at) VALUES
    ('VISITORS', 'VISIT_DENIED', 36, 'seed: inmate_id=5; slot=09:00-10:00; reason=BLACKLISTED', 'SEED', CURRENT_TIMESTAMP - interval '20 days'),
    ('VISITORS', 'VISIT_DENIED', 36, 'seed: inmate_id=9; slot=10:00-11:00; reason=BLACKLISTED', 'SEED', CURRENT_TIMESTAMP - interval '14 days'),
    ('VISITORS', 'VISIT_DENIED', 37, 'seed: inmate_id=12; slot=14:00-15:00; reason=BLACKLISTED', 'SEED', CURRENT_TIMESTAMP - interval '9 days'),
    ('VISITORS', 'VISIT_DENIED', 31, 'seed: inmate_id=7; slot=11:00-12:00; reason=UNAPPROVED', 'SEED', CURRENT_TIMESTAMP - interval '8 days'),
    ('VISITORS', 'VISIT_DENIED', 32, 'seed: inmate_id=20; slot=15:00-16:00; reason=UNAPPROVED', 'SEED', CURRENT_TIMESTAMP - interval '6 days'),
    ('VISITORS', 'VISIT_DENIED', 5, 'seed: inmate_id=3; slot=16:00-17:00; reason=CONFLICT', 'SEED', CURRENT_TIMESTAMP - interval '4 days'),
    ('VISITORS', 'VISIT_DENIED', 12, 'seed: inmate_id=8; slot=09:00-10:00; reason=CONFLICT', 'SEED', CURRENT_TIMESTAMP - interval '3 days'),
    ('VISITORS', 'VISIT_DENIED', 38, 'seed: inmate_id=30; slot=10:00-11:00; reason=BLACKLISTED', 'SEED', CURRENT_TIMESTAMP - interval '1 day');

SELECT setval(pg_get_serial_sequence('facilities', 'facility_id'), (SELECT max(facility_id) FROM facilities));
SELECT setval(pg_get_serial_sequence('blocks', 'block_id'), (SELECT max(block_id) FROM blocks));
SELECT setval(pg_get_serial_sequence('inmates', 'inmate_id'), (SELECT max(inmate_id) FROM inmates));
SELECT setval(pg_get_serial_sequence('visitors', 'visitor_id'), (SELECT max(visitor_id) FROM visitors));
SELECT setval(pg_get_serial_sequence('conflicts', 'conflict_id'), (SELECT max(conflict_id) FROM conflicts));
SELECT setval(pg_get_serial_sequence('inmate_conflicts', 'rivalry_id'), (SELECT max(rivalry_id) FROM inmate_conflicts));
SELECT setval(pg_get_serial_sequence('movements', 'movement_id'), (SELECT max(movement_id) FROM movements));
SELECT setval(pg_get_serial_sequence('visits', 'visit_id'), (SELECT max(visit_id) FROM visits));
SELECT setval(pg_get_serial_sequence('audit_log', 'audit_id'), (SELECT max(audit_id) FROM audit_log));

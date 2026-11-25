# PostgreSQL Data Dictionary

This dictionary follows the active schema in `postgres/001_schema.sql`; it is not generated from a live cloud database. Seed records are synthetic.

## facilities

| Column | Type | Constraints / meaning |
|---|---|---|
| facility_id | bigint identity | Primary key |
| facility_name | varchar(100) | Required, unique |
| city | varchar(60) | Required |

## blocks

| Column | Type | Constraints / meaning |
|---|---|---|
| block_id | bigint identity | Primary key |
| block_name | varchar(50) | Required, unique |
| capacity | integer | Required, greater than zero |
| security_level | varchar(10) | LOW, MEDIUM or HIGH |
| facility_id | bigint | Required foreign key to facilities |

## inmates

| Column | Type | Constraints / meaning |
|---|---|---|
| inmate_id | bigint identity | Primary key |
| inmate_no | varchar(20) | Required, unique synthetic roster number |
| full_name | varchar(100) | Required synthetic name |
| date_of_birth | date | Required |
| admission_date | date | Required, defaults to current date |
| sentence_start, sentence_end | date | Required; end must be later than start |
| status | varchar(12) | ACTIVE, TRANSFERRED or RELEASED; defaults to ACTIVE |
| block_id | bigint | Required foreign key to blocks |
| risk_level | varchar(10) | LOW, MEDIUM or HIGH; defaults to LOW |

## visitors

| Column | Type | Constraints / meaning |
|---|---|---|
| visitor_id | bigint identity | Primary key |
| full_name | varchar(100) | Required synthetic name |
| id_proof_type | varchar(20) | PASSPORT, NATIONAL_ID, DRIVING_LICENCE or VOTER_ID |
| id_proof_number | varchar(30) | Synthetic proof number; unique with type and masked in authorized views |
| phone | varchar(20) | Optional synthetic phone |
| approval_status | varchar(12) | PENDING, APPROVED, REJECTED or BLACKLISTED |
| registered_on | date | Required, defaults to current date |

## visits

| Column | Type | Constraints / meaning |
|---|---|---|
| visit_id | bigint identity | Primary key |
| inmate_id, visitor_id | bigint | Required foreign keys to inmates and visitors |
| visit_date | date | Required |
| slot | varchar(11) | One of six configured one-hour time slots |
| status | varchar(10) | SCHEDULED, COMPLETED, MISSED or CANCELLED |
| booked_on | timestamptz | Required, defaults to current timestamp |
| — | — | One booking per inmate/date/slot |

## movements

| Column | Type | Constraints / meaning |
|---|---|---|
| movement_id | bigint identity | Primary key |
| inmate_id | bigint | Required foreign key to inmates |
| from_block | bigint | Optional foreign key to blocks; NULL for admission |
| to_block | bigint | Required foreign key to blocks |
| movement_date | timestamptz | Required, defaults to current timestamp |
| reason | varchar(200) | Optional movement reason |
| moved_by | varchar(60) | Required; defaults to PostgreSQL session_user |

## conflicts

| Column | Type | Constraints / meaning |
|---|---|---|
| conflict_id | bigint identity | Primary key |
| inmate_id, visitor_id | bigint | Required foreign keys |
| reason | varchar(20) | RIVAL, VICTIM_RELATIVE, GANG_AFFILIATION or OTHER |
| flagged_date | date | Required, defaults to current date |
| resolved | char(1) | Y or N; defaults to N |
| resolved_on, expiry_date | date | Optional resolution and expiry dates |
| — | — | Unique inmate/visitor pair; expiry cannot precede flag date |

## audit_log

| Column | Type | Constraints / meaning |
|---|---|---|
| audit_id | bigint identity | Primary key |
| table_name | varchar(30) | Required affected table |
| action_type | varchar(20) | INSERT, UPDATE, DELETE, TRANSFER, VISIT_BOOKED, VISIT_DENIED or JOB |
| record_id | bigint | Optional affected record |
| details | varchar(4000) | Optional event details |
| changed_by | varchar(60) | Required; defaults to PostgreSQL session_user |
| changed_at | timestamptz | Required, defaults to current timestamp |

## inmate_conflicts

| Column | Type | Constraints / meaning |
|---|---|---|
| rivalry_id | bigint identity | Primary key |
| inmate_a, inmate_b | bigint | Required foreign keys; inmate_a must be less than inmate_b |
| reason | varchar(20) | RIVAL, GANG_AFFILIATION or OTHER |
| flagged_date | date | Required, defaults to current date |
| resolved | char(1) | Y or N; defaults to N |

## visit_slots

| Column | Type | Constraints / meaning |
|---|---|---|
| slot_code | varchar(11) | Primary key, e.g. 09:00-10:00 |
| start_time, end_time | time | Required; end must be later than start |
| max_visitors | integer | Required, greater than zero; defaults to 5 |

## staff_access

| Column | Type | Constraints / meaning |
|---|---|---|
| db_username | varchar(63) | Primary key; PostgreSQL login role name |
| facility_id | bigint | Optional foreign key; NULL means all facilities |

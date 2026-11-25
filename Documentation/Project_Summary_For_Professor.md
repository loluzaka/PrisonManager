# Prison Visitor and Inmate Management System

## Project in brief

This is a database-first system for managing inmate placements, visitor approvals, visit bookings, and facility activity. Its key idea is that important rules live in PostgreSQL—not only in the user interface—so invalid data is rejected even when a user or another program writes directly to the database.

All sample records are synthetic.

## How a typical operation works

1. Staff sign in to the Flask application using an assigned database role.
2. They view the inmates, blocks, visitor information, and visits allowed for their role and facility.
3. When a visit is booked, the app calls the PostgreSQL function `fn_schedule_visit`.
4. Database functions and triggers check eligibility, dates, capacity, conflicts, role/facility access, and duplicate bookings.
5. Accepted changes are stored; important actions and rejected attempts are recorded in the audit log.
6. Views and reports present the resulting visit schedule, occupancy, movement history, and release information.

## SQL and database features

### Relational design and integrity

The schema has 11 related tables: `facilities`, `blocks`, `inmates`, `visitors`, `visits`, `movements`, `conflicts`, `inmate_conflicts`, `visit_slots`, `staff_access`, and `audit_log`.

- Primary and foreign keys connect records and prevent references to missing facilities, inmates, visitors, or blocks.
- `NOT NULL`, `UNIQUE`, and `CHECK` constraints enforce required values, valid statuses and risk levels, valid visit slots, positive block capacity, and sensible dates.
- A unique constraint prevents an inmate from being booked into two visits in the same slot.
- Ten indexes support common lookups such as visits by date, inmate, and visitor.
- Separate tables for facilities, blocks, people, bookings, conflicts, and movements reduce duplicated data and support consistent updates.

### SQL queries and reporting

The database uses joins to combine related records, aggregates to calculate counts and occupancy, and conditional expressions to label report results. Date arithmetic supports weekly visit limits and upcoming-release reports.

There are 17 views for application screens and reports, including:

- Daily visits and visitor eligibility.
- Block occupancy and capacity.
- Upcoming releases and visit statistics.
- Movement history and denied booking attempts.
- Masked visitor identity numbers.
- Facility-scoped blocks, inmates, and visits.

### Functions, triggers, procedures, and cursors

The PostgreSQL scripts define 26 functions, seven triggers, and three procedures.

- **Functions** provide reusable operations and checks, including `fn_is_visitor_eligible`, `fn_schedule_visit`, and `fn_transfer_inmate`.
- **Triggers** automatically validate visit bookings and inmate placements, log inmate movements, and record audited changes. The audit log is protected against updates and deletes.
- **Procedures** produce daily-roster, block-occupancy, and upcoming-release reports. The roster and occupancy routines use explicit `OPEN`, `FETCH`, and `CLOSE` cursor steps; the roster can also be returned through a `refcursor`.
- **Transactions and locking:** booking and placement logic locks relevant inmate, block, or slot rows with `FOR UPDATE`. This reduces race conditions when concurrent requests compete for a limited visit slot or bed.
- **Error handling:** functions return clear outcome statuses for expected denials and use PostgreSQL exceptions/SQLSTATEs for invalid operations.

### Roles and data protection

Five login roles are grouped into four permission roles: administrator, warden, front desk, and auditor. Grants limit which tables, views, and functions each group may access. `staff_access` and facility-filtered views scope operational data; visitor identity numbers are masked in user-facing views. The UI connects through the selected database role and does not connect to PostgreSQL directly from browser code.

## Application and hosting

The Flask UI provides role-based sign-in, a dashboard, inmate and visit rosters, a masked visitor directory, and visit booking through the database function.

The project is configured for Neon-hosted PostgreSQL. Neon Functions provides a database health endpoint and a server-side endpoint for preparing scoped Realtime queries. Private Object Storage is used for files; an administrator-only check verifies upload, download, and cleanup. These services support the SQL application but are not the main project contribution.

## Testing and current status

- The local PostgreSQL test suite previously passed 23 database assertions and tests for all five login roles.
- The current Flask unit suite passes 8 tests, including Realtime role scoping, CSRF checks, and restrictions on the storage check.
- `npm.cmd run build` passes and generates the browser Realtime client.
- Neon Function health and the Flask-driven private-storage round trip have been verified.
- **Cloud database limitation:** the Neon production branch currently has no project tables or demo roles. The schema install could not be completed because the public PostgreSQL endpoint refused connections on port 5432 from the current environment. Therefore, live Neon dashboard, booking, and Realtime data flows are not yet verified.

## Suggested balanced division for three members

Each member owns their feature tests and reviews one other member's work. Adjust the assignment below to match the team's actual contributions.

| Member | Main responsibility | Deliverables |
|---|---|---|
| Huzayfa Yousuf (2501030340) | Relational model and data | ER/data model; 11 tables, keys, constraints, and indexes; synthetic seed data; core joins and reporting views; schema/data tests. |
| Saksham Dixit (2501030342) | Database business rules | PL/pgSQL functions and triggers; visit eligibility and booking; inmate placement and transfers; transaction locks; audit behavior; cursor procedures and business-rule tests. |
| Saksham Azad (2501030367) | Access, application, and integration | Database roles and grants; facility scoping and privacy views; Flask UI integration; Neon Function, Realtime, and private-storage wiring; integration tests and setup documentation. |

## Short explanation for a presentation

> “Our project manages inmate placement and visitor bookings. We designed a relational PostgreSQL schema and use constraints, functions, triggers, procedures, and cursors to enforce rules and produce reports in the database itself. Role-specific views protect facility data, and an audit log records important actions. A Flask interface lets staff use these database features. Neon hosts the PostgreSQL service, with Functions, Realtime, and private Object Storage configured; the production schema still needs to be installed before the cloud application flows can be demonstrated.”

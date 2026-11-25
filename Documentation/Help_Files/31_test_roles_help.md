# Help: `31_test_roles.sql`

## 1. File overview

* **Exact filename:** `31_test_roles.sql`
* **Location:** `tests/`
* **Purpose:** Role and privilege tests run once per demo user: allowed and forbidden actions, audit-log protection, masking and facility isolation (52 checks planned over five users; R-FD-11 awaits execution).
* **Feature(s):** F25 (roles), F26 (masking), F31 (facility access), F22 (least privilege)
* **Member responsibility:** Member 3
* **Role in the system:** Proves least privilege from the point of view of each login.
* **Execution order:** Run as each of PRISON_U_FRONTDESK, _AUDITOR, _WARDEN, _WARDEN2, _ADMIN (the PowerShell runner does it).

## 2. Required database objects and dependencies

* **Needs:** roles and grants (17), views (11), demo users (00).
* **Connects as the demo user**, not as the owner; `ALTER SESSION SET CURRENT_SCHEMA = prison_owner` only lets unqualified names resolve - **privileges are not inherited**.
* **Side effect:** front desk books one visit on day +250 (the runner re-seeds afterwards).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CREATE ROLE / GRANT / REVOKE** | A role is a named bundle of privileges; GRANT gives a privilege (or role) to a user or role, REVOKE takes it back. Least privilege: give only what is needed. | `GRANT SELECT ON t TO r; GRANT r TO user; REVOKE SELECT ON t FROM r;` | The tested behaviour. |
| **EXECUTE IMMEDIATE** | Runs a SQL string built at run time (needed for DDL inside PL/SQL). | `EXECUTE IMMEDIATE 'ALTER TABLE ...';` | `attempt(sql)` runs a statement dynamically and returns ALLOWED / DENIED / ERRnnn. |
| **SQLCODE / SQLERRM** | Error number and message of the exception being handled. | `WHEN OTHERS THEN v := SQLCODE; m := SQLERRM;` | DENIED = ORA-00942, -01031, -06550, -00904 or -41900 (Oracle 23ai wording for a missing privilege). |
| **Definer's rights** | A stored procedure runs with the privileges of its OWNER, so a user with only EXECUTE can change tables he cannot touch directly. | `default for CREATE PROCEDURE (AUTHID DEFINER)` | R-FD-9: front desk books through the procedure without table rights. |
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | One block with local `chk`, `attempt`, `cnt`, `str`. |
| **CREATE VIEW** | A stored query with a name; behaves like a read-only table and can hide columns and rows. | `CREATE OR REPLACE VIEW v AS SELECT ...;` | Masked and facility views are read through. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | SERVEROUTPUT, LINESIZE. |

**Common mistakes with these keywords**

* *CREATE ROLE / GRANT / REVOKE*: One GRANT can name only ONE object in Oracle. Roles are disabled inside definer-rights PL/SQL.
* *EXECUTE IMMEDIATE*: SQL injection risk if the string contains user input; DDL commits implicitly.
* *SQLCODE / SQLERRM*: Calling them outside an exception handler gives 0 / "normal".
* *Definer's rights*: Assuming the caller's privileges apply inside the procedure.
* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.
* *CREATE VIEW*: Granting users the base table as well defeats the purpose.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.

## 4. Tables and columns involved

Objects accessed via `prison_owner.`: INMATES, VISITORS, VISITS, AUDIT_LOG, `v_visitors_masked`, `v_fac_inmates`, `v_fac_blocks`, `v_denied_attempts`, `v_movement_history`, procedures `sp_schedule_visit`, `sp_transfer_inmate`, `sp_register_visitor`.

## 5. Walkthrough

Common to all: UPDATE, DELETE and TRUNCATE on AUDIT_LOG are DENIED (R-AUDIT-1..3).
* **FRONT_DESK (13):** cannot read INMATES, raw VISITORS, AUDIT_LOG; cannot DELETE/INSERT VISITS; cannot call `sp_transfer_inmate`; CAN read masked visitors (`****7919`), CAN book a visit through the procedure (BOOKED), blacklisted visitor still refused.
* **AUDITOR (10):** CAN read audit log and report views; cannot INSERT into the audit log, change inmates, book visits, read raw visitors; sees all 50 inmates.
* **WARDEN / WARDEN2 (10 each):** CAN update inmates, cannot delete them, cannot touch visitors or book visits; sees **33** (facility 1) / **17** (facility 2) inmates and **3** / **2** blocks.
* **ADMIN (8):** CAN change visitors and register visitors, sees all 50 inmates, cannot UPDATE the audit log and cannot DROP a table.

## 6. Actual execution example

Real output (excerpt):

```
TEST|R-FD-1|PRISON_U_FRONTDESK: cannot read the INMATES table|DENIED|DENIED|PASS
TEST|R-FD-9|PRISON_U_FRONTDESK: CAN book a visit through sp_schedule_visit (definer rights)|BOOKED|BOOKED|PASS
TEST|R-AU-2|PRISON_U_AUDITOR: cannot INSERT into the audit log|DENIED|DENIED|PASS
TEST|R-WA-6|PRISON_U_WARDEN: facility-scoped view shows only the warden's own facility|33|33|PASS
TEST|R-WA-6|PRISON_U_WARDEN2: facility-scoped view shows only the warden's own facility|17|17|PASS
SUMMARY|PRISON_U_FRONTDESK|passed=13|failed=0
SUMMARY|PRISON_U_AUDITOR|passed=10|failed=0   (warden 10, warden2 10, admin 8)
```

## 7. Data flow and integration

```
 demo user login ─► roles ─► views / procedures ─► (definer rights) ─► tables
 tests: attempt() → ALLOWED | DENIED → TEST| line
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Everything DENIED for a user | Role not granted or user logged in before the grant | Reconnect after `17_roles_security.sql`. |
| `ERR-41900` shown instead of DENIED | Older script version | The mapping includes -41900 for Oracle 23ai. |
| Facility counts differ | Data changed by other tests (e.g. an inmate transferred between facilities) | Re-seed first. |
| `ORA-01017` | Wrong demo password | Use PRISON_DEMO_PASSWORD from `.env`. |

## 9. Viva questions and answers

**Q1. Why test as the real users?**  
Privileges are per login; testing as the owner would prove nothing.

**Q2. Does CURRENT_SCHEMA give privileges?**  
No, it only changes name resolution.

**Q3. Why is the front desk able to book but not insert?**  
EXECUTE on a definer-rights procedure; no privilege on the table.

**Q4. How is facility isolation tested?**  
Two wardens count rows of the same view and get different numbers (33 vs 17).

## 10. Important practical commands

```
-- one user by hand
docker exec -i prison-oracle bash -c "cd /prison/tests && sqlplus -S PRISON_U_FRONTDESK/<DEMO_PWD>@//localhost:1521/FREEPDB1 @31_test_roles.sql"
SELECT * FROM session_roles;
```

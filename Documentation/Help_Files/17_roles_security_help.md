# Help: `17_roles_security.sql`

## 1. File overview

* **Exact filename:** `17_roles_security.sql`
* **Location:** `sql/`
* **Purpose:** Creates four roles, grants privileges to the roles, assigns roles to the demo users, binds staff to facilities and demonstrates GRANT / REVOKE.
* **Feature(s):** F25 (roles and privileges), F26 (sensitive data), F31 (facility access), F22 (least privilege on AUDIT_LOG)
* **Member responsibility:** Member 3
* **Role in the system:** Enforces "front desk books visits through the procedure only", "auditor is read-only", "nobody can change the audit log".
* **Execution order:** After views (11), procedures (09) and the job script is independent; run before the tests.

## 2. Required database objects and dependencies

* **Needs:** users from `00_admin_setup.sql`; tables, views, procedures.
* **Creates:** roles PRISON_ADMIN, PRISON_WARDEN, PRISON_FRONT_DESK, PRISON_AUDITOR; rows in STAFF_ACCESS.
* **Tested by:** `tests/31_test_roles.sql` (51 checks in the last recorded run; one facility-scope regression was added afterward).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **CREATE ROLE / GRANT / REVOKE** | A role is a named bundle of privileges; GRANT gives a privilege (or role) to a user or role, REVOKE takes it back. Least privilege: give only what is needed. | `GRANT SELECT ON t TO r; GRANT r TO user; REVOKE SELECT ON t FROM r;` | Object privileges are granted to roles, roles to users; REVOKE demonstrated on SELECT ON visitors. |
| **Definer's rights** | A stored procedure runs with the privileges of its OWNER, so a user with only EXECUTE can change tables he cannot touch directly. | `default for CREATE PROCEDURE (AUTHID DEFINER)` | Procedures run with the owner's rights, so GRANT EXECUTE alone lets FRONT_DESK change data it cannot touch directly. |
| **CREATE VIEW** | A stored query with a name; behaves like a read-only table and can hide columns and rows. | `CREATE OR REPLACE VIEW v AS SELECT ...;` | Roles receive views (masked, facility-scoped). |
| **MERGE** | "Upsert": updates the row if it exists, inserts it if not, in one statement. | `MERGE INTO t USING (src) s ON (cond) WHEN MATCHED THEN UPDATE ... WHEN NOT MATCHED THEN INSERT ...` | Repeatable binding of logins to facilities. |
| **EXECUTE IMMEDIATE** | Runs a SQL string built at run time (needed for DDL inside PL/SQL). | `EXECUTE IMMEDIATE 'ALTER TABLE ...';` | Create role ignoring ORA-01921 (exists). |
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | Block with `make_role`. |
| **COMMIT / ROLLBACK** | COMMIT makes the transaction permanent and releases locks; ROLLBACK undoes everything since the last COMMIT. | `COMMIT; ROLLBACK;` | COMMIT after the MERGE. |

**Common mistakes with these keywords**

* *CREATE ROLE / GRANT / REVOKE*: One GRANT can name only ONE object in Oracle. Roles are disabled inside definer-rights PL/SQL.
* *Definer's rights*: Assuming the caller's privileges apply inside the procedure.
* *CREATE VIEW*: Granting users the base table as well defeats the purpose.
* *MERGE*: ON-clause columns cannot be updated in the MATCHED branch.
* *EXECUTE IMMEDIATE*: SQL injection risk if the string contains user input; DDL commits implicitly.
* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.
* *COMMIT / ROLLBACK*: DDL (CREATE/ALTER/TRUNCATE) commits implicitly.

**Why one object per GRANT?** Oracle syntax allows `GRANT SELECT ON a, b` only in some other DBMS; here each object has its own statement (the first version of this script failed on a multi-object grant). **Why comments are on their own line:** SQL*Plus does not ignore text after a `;` - a trailing comment broke the next statement during the first install.

## 4. Tables and columns involved

| Role | Table privileges | Procedures | Views |
|---|---|---|---|
| PRISON_ADMIN | S/I/U/D on all tables except MOVEMENTS (S/I) and AUDIT_LOG (S/I) | all business procedures + cursors | report and facility views |
| PRISON_WARDEN | S/I/U INMATES, BLOCKS; S on MOVEMENTS, CONFLICTS, INMATE_CONFLICTS, VISITS, FACILITIES | transfer, conflicts, rivalry, occupancy, releases | facility + report views |
| PRISON_FRONT_DESK | **none** | `sp_register_visitor`, `sp_schedule_visit`, `pr_daily_roster` | masked visitors, today's visits, eligibility |
| PRISON_AUDITOR | S on AUDIT_LOG | `pr_daily_roster`, `pr_block_occupancy` | all report views |

Demo users: `PRISON_U_ADMIN`, `PRISON_U_WARDEN` (facility 1), `PRISON_U_WARDEN2` (facility 2), `PRISON_U_FRONTDESK`, `PRISON_U_AUDITOR`. STAFF_ACCESS: owner/admin/auditor = NULL (all), wardens and front desk bound to facilities.

## 5. Walkthrough

1. Create the four roles (ignore "already exists").
2. Grant to each role exactly what its duties need (table above). `AUDIT_LOG` is SELECT/INSERT only for admin and SELECT for auditor; **no role has UPDATE/DELETE/TRUNCATE on it**, and the trigger refuses UPDATE/DELETE even for the owner.
3. `GRANT role TO user` for the five demo users.
4. MERGE the login -> facility rows into STAFF_ACCESS (F31).
5. GRANT then REVOKE `SELECT ON visitors` to the auditor, printing the privilege before and after.

## 6. Actual execution example

Real output of the REVOKE demo:

```
PRIVILEGE  TABLE_NAME
SELECT     VISITORS
Revoke succeeded.
AUDITOR_PRIVILEGES_ON_VISITORS_AFTER_REVOKE
                                          0
```

Real results of the role tests (`tests/31_test_roles.sql`, all PASS):

```
PRISON_U_FRONTDESK: cannot read the INMATES table                 DENIED
PRISON_U_FRONTDESK: CAN book a visit through sp_schedule_visit    BOOKED
PRISON_U_FRONTDESK: procedure still refuses a blacklisted visitor DENIED_BLACKLISTED
PRISON_U_AUDITOR:   CAN read the audit log / cannot INSERT        ALLOWED / DENIED
PRISON_U_WARDEN:    facility-scoped view shows 33 inmates         PRISON_U_WARDEN2: 17
PRISON_U_ADMIN:     cannot UPDATE audit_log, cannot DROP a table  DENIED
```

## 7. Data flow and integration

```
 roles ◄─ grants ─ tables / views / procedures      users ◄─ roles      STAFF_ACCESS ◄─ facility binding ─► v_fac_* views
 front desk ──EXECUTE──► sp_schedule_visit (definer rights) ──► VISITS (no direct privilege needed)
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-01919: role does not exist` | Role script not run | Run 17 before granting. |
| `ORA-01921` creating a role | Role exists | Handled in the script. |
| `ORA-00942` for a user although granted through a role | Roles are disabled inside definer-rights PL/SQL or the user has not re-connected | Reconnect; use views/procedures instead of direct table access in stored code. |
| `ORA-01720: grant option does not exist` | Granting a view over tables you do not own | Grant as the owner of the underlying objects. |
| `ORA-41900: missing privilege` (23ai) | The Oracle 23ai wording of insufficient privilege | Same meaning as ORA-01031. |

## 9. Viva questions and answers

**Q1. Why roles instead of granting to users directly?**  
Manage privileges once per job type; add a user by granting one role.

**Q2. What is least privilege?**  
Give only the rights needed: the auditor can read but not write, front desk can only call two procedures.

**Q3. How can FRONT_DESK book visits without table privileges?**  
Definer's-rights procedure: it runs with the owner's privileges.

**Q4. Difference between GRANT and REVOKE?**  
Give vs take back a privilege.

**Q5. How is the audit log protected from the admin?**  
Admin has no UPDATE/DELETE privilege and the BEFORE trigger refuses it anyway.

**Q6. How is facility isolation done?**  
Facility-scoped views filter by the logged-in user via STAFF_ACCESS.

## 10. Important practical commands

```
SELECT * FROM user_role_privs;                       -- as a demo user
SELECT grantee, privilege, table_name FROM user_tab_privs_made WHERE grantee = 'PRISON_FRONT_DESK';
SELECT * FROM staff_access;
-- as PRISON_U_FRONTDESK:
SELECT * FROM prison_owner.inmates;                   -- ORA-00942

```

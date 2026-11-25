# Help: `00_admin_setup.sql`

## 1. File overview

* **Exact filename:** `00_admin_setup.sql`
* **Location:** `sql/`
* **Purpose:** Creates the schema owner PRISON_OWNER and five demo login accounts (one per role) and gives them the minimum rights.
* **Feature(s):** F25 (demo users), F29 / F32 (separate administrative and application accounts)
* **Member responsibility:** Member 3 (security & cloud)
* **Role in the system:** The only script run by a DBA account (SYSTEM locally, ADMIN in Autonomous Database). Everything else runs as PRISON_OWNER, so the project never needs DBA rights after this step.
* **Execution order:** FIRST. Run before every other script.

## 2. Required database objects and dependencies

* **Tables / views read:** `dba_users` (to see whether a user already exists).
* **Runs as:** a DBA account. **Depends on nothing** in the project.
* **Needed by:** every other script (they connect as `PRISON_OWNER`); `17_roles_security.sql` grants roles to the five `PRISON_U_*` users created here.
* **Arguments:** `&1` owner password, `&2` demo-user password - passed on the command line, never stored in the file (F32).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **Substitution variables (&1, DEFINE)** | SQL*Plus replaces &name with text BEFORE sending the statement to the database. Script arguments are &1, &2, ... | `DEFINE pwd = &1` | `DEFINE owner_pwd = &1` copies the first command-line argument into a variable that is spliced into the CREATE USER text. |
| **WHENEVER SQLERROR** | Tells SQL*Plus to stop (EXIT) or continue when a statement fails. | `WHENEVER SQLERROR EXIT FAILURE` | Stops the script with a failure code at the first error, so a half-finished setup is noticed. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | `SET VERIFY OFF` stops SQL*Plus from echoing the old/new text of each substituted line (which would print the password!); `SET SERVEROUTPUT ON` shows the created/reset messages. |
| **DECLARE / BEGIN / END** | The three parts of a PL/SQL block: declarations, executable code, end. An anonymous block has no name and is not stored. | `DECLARE v NUMBER; BEGIN ...; EXCEPTION WHEN ... THEN ...; END;` | A local procedure `ensure_user` inside the anonymous block creates the user or just resets the password - making the script safe to re-run. |
| **EXECUTE IMMEDIATE** | Runs a SQL string built at run time (needed for DDL inside PL/SQL). | `EXECUTE IMMEDIATE 'ALTER TABLE ...';` | CREATE USER / ALTER USER are DDL, which PL/SQL can only run as dynamic SQL. |
| **CREATE ROLE / GRANT / REVOKE** | A role is a named bundle of privileges; GRANT gives a privilege (or role) to a user or role, REVOKE takes it back. Least privilege: give only what is needed. | `GRANT SELECT ON t TO r; GRANT r TO user; REVOKE SELECT ON t FROM r;` | `GRANT CREATE SESSION, CREATE TABLE, ... TO prison_owner` gives the owner exactly the object-creation rights the project needs; demo users get only CREATE SESSION (log in). |

**Common mistakes with these keywords**

* *Substitution variables (&1, DEFINE)*: A literal & in text triggers a prompt: use SET DEFINE OFF.
* *WHENEVER SQLERROR*: Without it SQL*Plus keeps going after an error and still returns exit code 0.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.
* *DECLARE / BEGIN / END*: In SQL*Plus a PL/SQL block must be terminated with a line containing only /.
* *EXECUTE IMMEDIATE*: SQL injection risk if the string contains user input; DDL commits implicitly.
* *CREATE ROLE / GRANT / REVOKE*: One GRANT can name only ONE object in Oracle. Roles are disabled inside definer-rights PL/SQL.

## 4. Tables and columns involved

No project table is touched. The data-dictionary view `dba_users` is read to test whether each user exists.

Privileges granted to `PRISON_OWNER`: CREATE SESSION, TABLE, VIEW, SEQUENCE, PROCEDURE, TRIGGER, TYPE, ROLE, JOB, SYNONYM and UNLIMITED TABLESPACE. Each is needed by a later script: TABLE (01), VIEW (11), PROCEDURE/TRIGGER (05-10), ROLE (17), JOB (18), UNLIMITED TABLESPACE (storage on any tablespace, portable to Autonomous Database).

## 5. Walkthrough

1. The two arguments are stored in substitution variables.
2. The block defines `ensure_user(name, pwd)`: it counts matching rows in `dba_users`; if none it runs `CREATE USER name IDENTIFIED BY "pwd"`, otherwise `ALTER USER ... IDENTIFIED BY` (password reset). A message is printed either way.
3. Six users are ensured: `PRISON_OWNER`, `PRISON_U_ADMIN`, `PRISON_U_WARDEN` (facility 1), `PRISON_U_WARDEN2` (facility 2), `PRISON_U_FRONTDESK`, `PRISON_U_AUDITOR`.
4. Two GRANT statements give the owner its build rights and the demo users the right to log in.
5. No role is granted here: roles do not exist yet; script 17 creates them and grants them.

## 6. Actual execution example

Real output of the first install (fresh container):

```
created user PRISON_OWNER
created user PRISON_U_ADMIN
created user PRISON_U_WARDEN
created user PRISON_U_WARDEN2
created user PRISON_U_FRONTDESK
created user PRISON_U_AUDITOR
Grant succeeded.
Grant succeeded.
00_admin_setup.sql finished: PRISON_OWNER and 5 demo users are ready.
```

Second run (idempotent): `user PRISON_OWNER already exists - password reset`.

## 7. Data flow and integration

```
 DBA login ──► 00_admin_setup.sql ──► users PRISON_OWNER, PRISON_U_*  (data dictionary only)
                                       │
                                       ▼ PRISON_OWNER builds everything (01..18)
                                       ▼ 17_roles_security.sql attaches roles to PRISON_U_*
```
No project tables are read or modified; no triggers fire.

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-01031: insufficient privileges` | Run as an ordinary user instead of a DBA | Connect as SYSTEM (local) or ADMIN (cloud). |
| `ORA-65096: invalid common user or role name` | Connected to the container root (CDB$ROOT) instead of the pluggable DB | Use service `FREEPDB1`: `//localhost:1521/FREEPDB1`. |
| `ORA-28003: password verification failed` | Password too weak for the profile | Use 12+ mixed letters and digits. |
| Script prompts "Enter value for 1" | Arguments missing | `@00_admin_setup.sql ownerPwd demoPwd` |

## 9. Viva questions and answers

**Q1. Why not create all objects as SYSTEM?**  
Least privilege and clean ownership: the schema owner has only the rights to build the project; a DBA account is used once.

**Q2. Why are passwords passed as arguments?**  
So no password is ever stored in a file that is committed to Git (F32).

**Q3. Why is `SET VERIFY OFF` important here?**  
Without it SQL*Plus prints the lines containing &1/&2 with the real values substituted.

**Q4. What does UNLIMITED TABLESPACE do?**  
Allows the user to store data in any tablespace; avoids ORA-01950 on managed cloud databases where the tablespace name differs.

## 10. Important practical commands

```
-- local container (passwords are in .env)
docker exec -i prison-oracle bash -c "cd /prison/sql && sqlplus -L -S 'system/<SYS_PWD>@//localhost:1521/FREEPDB1' @00_admin_setup.sql <owner_pwd> <demo_pwd>"
-- verify
SELECT username, account_status FROM dba_users WHERE username LIKE 'PRISON%';
SELECT * FROM dba_sys_privs WHERE grantee = 'PRISON_OWNER';
```

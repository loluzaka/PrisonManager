# Help: `connection_check.sql`

## 1. File overview

* **Exact filename:** `connection_check.sql`
* **Location:** `cloud/`
* **Purpose:** Prints evidence that the session is on a remote managed database: database name, service, server host, network protocol (tcps = TLS), client IP, user, version, object counts.
* **Feature(s):** F29 (remote connection demonstration), F32 (secure access)
* **Member responsibility:** Member 3
* **Role in the system:** Take a screenshot of its output for the cloud deliverable. Runs at the end of `install_cloud.ps1`.
* **Execution order:** After a cloud install (works locally too).

## 2. Required database objects and dependencies

* **Reads:** `SYS_CONTEXT` (no special privileges), `product_component_version`, `user_objects`, INMATES, VISITORS, VISITS.
* **STATUS:** never executed against a real cloud database (only against the local container).

## 3. Keyword and syntax explanation

| Keyword / concept | What it means | Syntax | Why it is used in THIS file |
|---|---|---|---|
| **SELECT** | Reads rows. | `SELECT cols FROM t [JOIN ...] [WHERE] [GROUP BY] [HAVING] [ORDER BY];` | One UNION ALL query turns several context values into rows. |
| **Scalar functions** | Row-level functions: UPPER, TRIM, SUBSTR, INSTR, REPLACE, LENGTH, ROUND, MOD, TO_CHAR, ADD_MONTHS, TRUNC(date) ... | `UPPER(TRIM(name))` | `SYS_CONTEXT('USERENV', 'NETWORK_PROTOCOL')` etc. |
| **Aggregate functions** | COUNT, SUM, AVG, MIN, MAX compute one value from many rows. | `COUNT(*), SUM(x), AVG(x), MIN(x), MAX(x)` | COUNT per object type. |
| **GROUP BY / HAVING** | GROUP BY collapses rows into groups for aggregate functions; HAVING filters the groups (WHERE cannot, because it runs earlier). | `SELECT col, COUNT(*) FROM t GROUP BY col HAVING COUNT(*) > 1` | Objects per type. |
| **UNION / INTERSECT / MINUS** | Set operations on two queries with matching columns: UNION (all distinct rows), INTERSECT (common rows), MINUS (rows only in the first; EXCEPT elsewhere). | `SELECT a FROM x MINUS SELECT a FROM y` | UNION ALL stacks item/value rows. |
| **SET (SQL*Plus)** | Session settings of the SQL*Plus client: SERVEROUTPUT, LINESIZE, PAGESIZE, FEEDBACK, VERIFY, ECHO. | `SET LINESIZE 160` | COLUMN formats and LINESIZE. |

**Common mistakes with these keywords**

* *SELECT*: Mixing aggregated and non-aggregated columns without GROUP BY -> ORA-00937.
* *Scalar functions*: Dates: SYSDATE includes the time; use TRUNC(SYSDATE) for "today".
* *Aggregate functions*: COUNT(col) skips NULLs, COUNT(*) does not.
* *GROUP BY / HAVING*: Putting an aggregate in WHERE -> ORA-00934.
* *UNION / INTERSECT / MINUS*: Column count/type mismatch -> ORA-01789.
* *SET (SQL*Plus)*: These are client commands, not SQL: no semicolon rules apply and they are ignored by other tools.

## 4. Tables and columns involved

INMATES, VISITORS, VISITS (row counts only); `user_objects` (counts per type).

## 5. Walkthrough

1. Build item/value rows from `SYS_CONTEXT`: `DB_NAME`, `SERVICE_NAME`, `SERVER_HOST`, `NETWORK_PROTOCOL` (on the cloud this is **tcps**, i.e. TLS), `IP_ADDRESS`, `SESSION_USER`, version.
2. Print counts of objects per type.
3. Print row counts of the three busiest tables (expected 50 / 40 / 100 right after a fresh install).

Privilege-free by design: the first draft used `V$` views, which `PRISON_OWNER` cannot read.

## 6. Actual execution example

Locally (protocol `tcp`, host = container id) the first rows look like `database name FREE`, `service name freepdb1`, `network protocol tcp`, `session user PRISON_OWNER`. **On the cloud the expected evidence is `network protocol tcps` and a remote `server host`; that output has not been captured yet - it is the pending manual step.**

## 7. Data flow and integration

```
 SYS_CONTEXT + data dictionary ──► connection_check.sql ──► screenshot for the report
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| `ORA-00942` on a V$ view | No privilege | Not used any more. |
| `ORA-12170` / `ORA-28759` | ACL / wallet problems | See `Cloud_Setup.md` section 8. |

## 9. Viva questions and answers

**Q1. How do you prove the connection is encrypted?**  
NETWORK_PROTOCOL = tcps (TLS) with the wallet connection.

**Q2. Why use SYS_CONTEXT?**  
It needs no extra privileges and works in every Oracle service.

## 10. Important practical commands

```
sqlplus PRISON_OWNER/<pwd>@prisondb_medium @cloud/connection_check.sql
SELECT SYS_CONTEXT('USERENV','NETWORK_PROTOCOL') FROM dual;
```

# Help: `.env.example`

## 1. File overview

* **Exact filename:** `.env.example`
* **Location:** `(project root)`
* **Purpose:** Template for the git-ignored `.env`: container name, port, service, local passwords, wallet location and cloud passwords.
* **Feature(s):** F32 (no passwords in the repository)
* **Member responsibility:** Member 3
* **Role in the system:** Project configuration.
* **Execution order:** Used by the scripts / Git.

## 2. Required database objects and dependencies

* **Copy to `.env`** and edit; `common.ps1` creates `.env` itself with random passwords if you do not.
* **Read by:** all PowerShell scripts.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

Plain configuration text; no SQL.

## 4. Tables and columns involved

No tables.

## 5. Walkthrough

| Key | Meaning |
|---|---|
| `PRISON_CONTAINER` | Docker container name (`prison-oracle`) |
| `PRISON_DB_PORT` | host port mapped to 1521 |
| `PRISON_DB_SERVICE` | pluggable database service (`FREEPDB1`) |
| `PRISON_SYS_PASSWORD` | SYS/SYSTEM password of the container |
| `PRISON_OWNER_PASSWORD` | password of schema owner PRISON_OWNER |
| `PRISON_DEMO_PASSWORD` | shared password of the five demo users |
| `TNS_ADMIN` | folder of the unzipped cloud wallet |
| `PRISON_CLOUD_TNS` | service alias from the wallet's tnsnames.ora (e.g. `prisondb_medium`) |
| `PRISON_CLOUD_ADMIN_PASSWORD`, `_OWNER_PASSWORD`, `_DEMO_PASSWORD` | cloud equivalents |

All values in the example are placeholders (`change_me_...`).

## 6. Actual execution example

```
PRISON_CONTAINER=prison-oracle
PRISON_DB_PORT=1521
PRISON_DB_SERVICE=FREEPDB1
PRISON_SYS_PASSWORD=change_me_sys_password
```

## 7. Data flow and integration

```
 .env.example ──► read by the scripts / Git
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| Script says "Set X in .env first" | Value missing or placeholder | Replace `change_me...`. |
| Spaces around `=` | Parser expects KEY=VALUE | Allowed, but avoid quotes. |

## 9. Viva questions and answers

**Q1. Why a template file?**  
Documents the required settings without revealing real secrets.

**Q2. How do you make sure `.env` is never committed?**  
`.gitignore` lists it; check `git status`.

## 10. Important practical commands

```
Copy-Item .env.example .env
notepad .env
```

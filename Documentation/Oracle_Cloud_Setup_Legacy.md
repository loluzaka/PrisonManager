# Legacy Oracle Cloud Setup (reference only)

## Status (read this first)

| Item | Status |
|---|---|
| Scripts for cloud deployment (`scripts/install_cloud.ps1`, `sql/00_admin_setup.sql`, `cloud/connection_check.sql`) | **Written, not yet run** against a real cloud database |
| Role-based web UI (`ui/`) | **Implemented; cloud connection pending valid wallet and account configuration** |
| Cloud database created | **PENDING – manual step** (needs the team's Oracle Cloud account; no credentials were available while this project was built) |
| Remote connection demonstrated from two computers | **PENDING – manual step** |
| Automated backup configured / restore demonstrated in the cloud | **PENDING – manual step** (the equivalent *Flashback Table* recovery IS tested locally, test `J01/J02`) |
| Previously recorded database checks | 191 / 191 passed against local Oracle Database Free; new SQL regressions and UI-to-Oracle integration have not yet been run |

Nothing below has been claimed as done unless it appears in the Testing Guide with a real result.
When you finish the manual steps, change the PENDING rows to the real result and attach your screenshots.

The project uses only features that exist in **Autonomous Database (Always Free)**: IDENTITY columns, compound triggers,
autonomous transactions, `DBMS_SCHEDULER`, `FLASHBACK TABLE`. The seed script and scripts avoid `SYS`/`SYSTEM`-only commands.

---

## 1. Create the database (manual, about 10 minutes)

1. Sign up at <https://www.oracle.com/cloud/free/> (a card is requested for identity checking; **Always Free** resources are not charged).
2. Console → **Oracle Database → Autonomous Database → Create Autonomous Database**.
3. Choose: Workload **Transaction Processing**, Deployment **Serverless**, tick **Always Free**, Database version 19c or 23ai,
   Database name `PRISONDB`, set an **ADMIN password** (store it in your password manager – not in Git).
4. Network access: choose **Secure access from allowed IPs and VCNs only** and add the public IP address of each team member (see 4.2),
   *or* keep the default mutual-TLS (wallet) which already requires the wallet file.
5. Wait for the state **Available**.

## 2. Download the wallet (credentials file)

1. Database details → **Database connection → Download wallet**, give it a wallet password, save `Wallet_PRISONDB.zip`.
2. Unzip it into a folder **outside the repository** (e.g. `C:\secrets\Wallet_PRISONDB`). `.gitignore` also blocks `wallet/`, `*.zip`, `cwallet.sso`, `ewallet.p12`, `tnsnames.ora`, `sqlnet.ora`.
3. Service names inside `tnsnames.ora`: `prisondb_high`, `_medium`, `_low`, `_tp`, `_tpurgent`. Use `prisondb_low` or `_medium` for this project.

## 3. Configure the project (no secrets in Git)

Copy `.env.example` to `.env` (git-ignored) and fill in:

```
TNS_ADMIN=C:\secrets\Wallet_PRISONDB
PRISON_CLOUD_TNS=prisondb_medium
PRISON_CLOUD_ADMIN_PASSWORD=<ADMIN password>
PRISON_CLOUD_OWNER_PASSWORD=<new strong password for PRISON_OWNER>
PRISON_CLOUD_DEMO_PASSWORD=<password for the five demo users>
PRISON_CLOUD_WALLET_PASSWORD=<wallet password, if the wallet requires it>
```

Run from the project folder (Docker Desktop must be running – the local Oracle container is only used as a SQL*Plus client):

```powershell
.\scripts\start_local_db.ps1          # one-time: gives us the sqlplus client container
.\scripts\install_cloud.ps1           # creates users, builds the schema, seeds data, prints the connection check
```

`install_cloud.ps1` connects as `ADMIN` only to create `PRISON_OWNER` and the demo users (`00_admin_setup.sql`);
all project objects are then created by `PRISON_OWNER`. That is the **separate administrative and application accounts** requirement of F32.

### Optional web UI

The UI connects from its Python backend to Oracle using the wallet and the selected project role account. The browser never connects directly to Oracle or receives a database password after sign-in.

```powershell
python -m venv ui\.venv
ui\.venv\Scripts\python.exe -m pip install -r ui\requirements.txt
ui\.venv\Scripts\python.exe ui\app.py
```

Open `http://127.0.0.1:5000`. The wallet directory, `PRISON_CLOUD_TNS`, and role account passwords must be configured in `.env`.
Use only on localhost for this classroom demonstration; public hosting additionally requires HTTPS, a production WSGI server, secret management, and operational session storage. The UI follows existing grants and facility-scoped views, and routes visit requests through `SP_SCHEDULE_VISIT`. `v_fac_visits` includes visitor names but remains scoped by `STAFF_ACCESS`.

### Alternative: SQL Developer / DBeaver / VS Code

* **SQL Developer**: New connection → type *Cloud Wallet* → pick the wallet zip → service `prisondb_medium` → user `PRISON_OWNER`.
  Open and run the scripts in the order of `sql/run_all.sql` (or use *Run Script*, F5).
* **DBeaver**: New connection → Oracle → *Connection type: Cloud Wallet / TNS* with `TNS_ADMIN` pointing to the wallet folder.
* Every team member downloads the same wallet (share it through a private channel, never Git) and uses the same service name from their own computer: this is the "access from different computers" demonstration.

## 4. Security configuration (F32)

### 4.1 Credentials
* Passwords live only in `.env` / a password manager. The SQL scripts take passwords as **arguments** (`@00_admin_setup.sql <owner_pwd> <demo_pwd>`).
* `.gitignore` excludes `.env`, wallets and key material. Check with `git status` before every commit; enable GitHub *secret scanning* on the repository.
* The five demo users (`PRISON_U_*`) are for demonstrations only – in a real deployment lock or drop them: `ALTER USER prison_u_admin ACCOUNT LOCK;`

### 4.2 Network: IP allowlist
Console → Database details → **Network → Edit access control list** → add each member's public IP (look it up at <https://ifconfig.me>).
Only listed addresses can open a connection. Remove the entries after the demonstration.

### 4.3 TLS (encryption in transit)
The wallet connection is **mutual TLS (TCPS)** – traffic is encrypted and the server is authenticated by the wallet.
`cloud/connection_check.sql` prints `NETWORK_PROTOCOL`; the value `tcps` is the evidence. Data at rest is encrypted
by default in Autonomous Database (Transparent Data Encryption, always on).

### 4.4 Cost control
* Always Free resources have a hard limit, so no charge arises as long as the instance is the Always Free kind.
* Still create a safety net: Console → **Billing & Cost Management → Budgets → Create budget** (e.g. 1 USD per month, alert at 50 %/100 % by e-mail).
* Console → Database details → **Metrics** (CPU, storage, sessions) is the monitoring dashboard to screenshot. Note: an Always Free database that is
  *idle for 7 days is stopped* and is deleted after 90 days stopped – start it again from the console before a demonstration.

## 5. Remote connection demonstration (F29) – checklist

1. Run `cloud/connection_check.sql` as `PRISON_OWNER` (done automatically at the end of `install_cloud.ps1`). Screenshot: database name, `tcps`, server host, user.
2. From a second computer with its IP on the allowlist, connect with SQL Developer and run `SELECT COUNT(*) FROM inmates;` – expect `50`.
3. Show a failed attempt from a computer whose IP is **not** allowlisted (connection times out) – that proves the firewall rule.
4. Run the test suite pieces against the cloud: open `tests/30_test_suite.sql` in SQL Developer as `PRISON_OWNER` and run as script (F5).

## 6. Automatic backup and restore (F30)

**Autonomous Database makes automatic daily backups** with 60-day retention (Always Free: 60 days of backups; point-in-time restore within that window). No setting needs switching on – the evidence is the list of backups.

### 6.1 Show the backup configuration
Console → Database details → **Backups** (Backups / Resources tab) → list of automatic backups with dates. Screenshot it.
Optionally click **Create manual backup** (needs an Object Storage bucket for Always Free; the automatic backups are enough for the demonstration).

### 6.2 Safe restore demonstration (never touch the real tables)
1. Create a copy to destroy:
   ```sql
   CREATE TABLE visits_backup_demo AS SELECT * FROM visits;     -- 100 synthetic rows
   SELECT COUNT(*) FROM visits_backup_demo;                      -- 100
   ```
2. Note the time: `SELECT SYSTIMESTAMP FROM dual;`
3. Simulate the accident: `DELETE FROM visits_backup_demo; COMMIT;` → count is 0.
4. **Fast recovery with Flashback Table** (works in the cloud and locally, no console needed):
   ```sql
   ALTER TABLE visits_backup_demo ENABLE ROW MOVEMENT;
   FLASHBACK TABLE visits_backup_demo TO TIMESTAMP TO_TIMESTAMP('2026-11-03 14:05:00','YYYY-MM-DD HH24:MI:SS');
   SELECT COUNT(*) FROM visits_backup_demo;                      -- 100 again
   ```
   This exact technique is automated in test `J01/J02` (`tests/30_test_suite.sql`).
5. **Whole-database restore from the backups** (disaster recovery): Console → **More actions → Restore** → pick *Restore to a timestamp* or a specific backup.
   This overwrites the *entire* database with the chosen point in time, so do it only in a lab instance, after exporting anything you need, and expect a few minutes of downtime.
6. Clean up: `DROP TABLE visits_backup_demo PURGE;`

## 7. Multi-facility access (F31) in the cloud
Facility isolation is implemented with views (`v_fac_inmates`, `v_fac_blocks`, `v_fac_visits`) and the `STAFF_ACCESS` table, so it works identically in the cloud.
Log in as `PRISON_U_WARDEN` (facility 1) and `PRISON_U_WARDEN2` (facility 2) and run `SELECT COUNT(*) FROM prison_owner.v_fac_inmates;` – expect 33 and 17.
(Oracle Virtual Private Database could enforce the same rule on the base tables; the view approach was chosen because it needs no extra licence option.)

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ORA-12170: TNS connect timeout` | Your IP is not on the ACL, or a firewall blocks port 1522. Add the IP / try another network. |
| `ORA-28759: failure to open file` | `sqlnet.ora` still contains `?/network/admin`; `install_cloud.ps1` rewrites it inside the container. For SQL Developer set the wallet path in the connection dialog. |
| `ORA-01017: invalid username/password` | The password contains characters needing quotes; use letters and digits, or quote it. |
| `ORA-01950: no privileges on tablespace` | `00_admin_setup.sql` grants `UNLIMITED TABLESPACE`; re-run it as ADMIN. |
| `ORA-01031` when running a script | Run `00_admin_setup.sql` as ADMIN first; project objects must be created as PRISON_OWNER. |
| Database "Stopped" | Always Free instances stop after 7 idle days – press **Start** in the console. |

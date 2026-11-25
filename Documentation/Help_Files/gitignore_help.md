# Help: `.gitignore`

## 1. File overview

* **Exact filename:** `.gitignore`
* **Location:** `(project root)`
* **Purpose:** Keeps secrets and generated files out of Git: `.env`, wallets, keys, zips, TNS files, logs.
* **Feature(s):** F32 (secure cloud access, no secrets committed)
* **Member responsibility:** Member 3
* **Role in the system:** Project configuration.
* **Execution order:** Used by the scripts / Git.

## 2. Required database objects and dependencies

* **Read by:** Git.

## 3. Keyword and syntax explanation

This file contains no SQL; see the explanations in section 5.

Plain configuration text; no SQL.

## 4. Tables and columns involved

No tables.

## 5. Walkthrough

| Pattern | Why |
|---|---|
| `.env` | local passwords |
| `*.pem`, `*.key`, `ewallet.p12`, `cwallet.sso` | certificates / wallet files |
| `wallet/`, `Wallet_*/`, `cloud/wallet/`, `*.zip` | the downloaded cloud wallet and its archive |
| `tnsnames.ora`, `sqlnet.ora` | connection descriptors |
| `*.log`, `*.lst` | generated output |
| `Documentation/Test_Results/*.tmp` | temp results |

(The test logs `latest_test_run.log` and `demo_output.log` are *not* ignored on purpose: they are evidence for the report and contain no secrets.)

## 6. Actual execution example

```
$ git status      # .env must never appear in the list
```

## 7. Data flow and integration

```
 .gitignore ──► read by the scripts / Git
```

## 8. Common errors and debugging

| Symptom / error | Cause | How to diagnose and fix |
|---|---|---|
| A secret was already committed | Added before the ignore rule | Rotate the password; removing the file from history is not enough. |

## 9. Viva questions and answers

**Q1. What do you do if a password reaches Git?**  
Change it immediately; treat it as compromised.

**Q2. Why ignore the wallet?**  
It is a credential for the cloud database.

## 10. Important practical commands

```
git check-ignore -v .env
git status --ignored
```

# PostgreSQL backup and restore runbook

Status (2026-10-01): Day 73 complete. Local backup and restore were verified.
The authorized `noahs-ark-staging / staging` synthetic-data cloud exercise also
passed: both staging archives were restored into isolated local databases. The
source fixture was removed, and source row hashes were preserved. Temporary SSH
keys were revoked and the CLI was logged out. The user confirmed revoking its
browser-side OAuth grant; the script did not independently query this UI action.

## Scope and cost

This covers the experimental PostgreSQL backend. Flutter SQLite, local JSON
exports and Flash Thought audio are separate. Railway staging must hold only
disposable accounts and synthetic Thoughts.

The Railway Postgres Backups page inspected on 2026-09-28 showed `No Backups`.
Creating a Volume Backup or enabling PITR required Pro on this account. No paid
upgrade or public database proxy was approved. Custom-format `pg_dump` files
are the selected portable recovery copy. Railway's Trial/Free volume cannot be
treated as permanent; export before trial-credit expiry and before risky schema
or data operations.

Official references: [Railway backup guide](https://docs.railway.com/guides/postgres-backups-restores),
[Railway SSH](https://docs.railway.com/cli/ssh),
[Railway Free Trial](https://docs.railway.com/pricing/free-trial),
[PostgreSQL pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html), and
[PostgreSQL pg_restore](https://www.postgresql.org/docs/18/app-pgrestore.html).

## Requirements and storage

Run from `backend` with its installed Node dependencies. Local connection values
come from ignored `backend/.env`. PostgreSQL client binaries must support the
source major version; Windows defaults to `C:\Program Files\PostgreSQL\18\bin`.
Set `PG_BIN` if installed elsewhere. For Railway, use a logged-in Railway CLI and
native `ssh`/`ssh-keygen`; set `RAILWAY_BIN` if needed. The script explicitly
targets `noahs-ark-staging / staging / Postgres`; `railway link` is not required.

Artifacts are in ignored `.backups/postgres/`:

- `*.dump`: compressed, custom-format database archive.
- `*.dump.json`: archive SHA-256, source/tool versions, migration checksums,
  table row counts and hashes, columns, constraints, indexes and sequences.
- `*.dump.restore-*.json`: successful restore checks and target cleanup result.

Passwords are passed to PostgreSQL subprocesses through their environment, never
in command arguments or output. On Windows the backup directory grants access to
the current user, SYSTEM and Administrators; on Unix it uses owner-only directory
permissions. Archives are compressed but not encrypted. They may contain account,
password and token hashes plus test content. Keep them private, and keep each
archive with its manifest. Restore only backups from this trusted project.

For disposable staging, take a backup before every migration or cleanup, before
trial-credit expiry and at least weekly while staging is used. Retain the seven
latest successful archive/manifest pairs and the latest verified restore report.
Prune older copies manually only after verifying the newer pair. This script does
not schedule runs or delete old backups. An encrypted copy on independent storage
and automated scheduling remain required before production use.

## Backup commands

```powershell
Set-Location 'C:\Users\alesi\StudioProjects\noahs_ark_app\backend'
npm.cmd run db:backup -- local
```

The Railway drill command below passed on 2026-10-01. Standalone Railway backup
uses the same connection and dump path, but was not separately invoked:

```powershell
railway login --browserless
npm.cmd run db:backup -- railway
npm.cmd run db:backup:railway-drill
```

The Railway code creates a temporary Ed25519 key under `.backups/postgres/`,
registers its public key using Railway's GraphQL API, obtains the database SSH
target using `railway ssh config --dry-run`, and forwards a loopback port to the
private Postgres service. Railway CLI 5.62.1 failed to discover a temporary key
outside `~/.ssh` even with `ssh keys add --key`; the API path avoids adding it to
the user's permanent SSH directory. After a normal run, the exact key ID is
revoked, then the private key, known-hosts file and tunnel are removed. Forced
termination or connection loss can interrupt cleanup: inspect Account Settings
-> SSH Keys and revoke only the temporary `day73-backup-ssh-*` entry if needed.

The archive and table hashes use one exported repeatable-read snapshot. Sequence
counters are outside PostgreSQL MVCC snapshots; run this staging exercise while
other writes are idle. A `backup_created` event proves dump completion, archive
readability and manifest creation; a restore drill is still required.

## Isolated restore exercise

Use the exact path printed by `backup_created`, relative to `backend` if desired:

```powershell
npm.cmd run db:restore:drill -- '..\.backups\postgres\<archive-name>.dump'
```

The command first checks the archive SHA-256. It creates a fresh database named
`noahs_ark_restore_drill_<UTC timestamp>_<random suffix>` from `template0` on
localhost. It calls `pg_restore` with `--no-owner --no-acl --exit-on-error
--single-transaction`; it never uses `--clean` or `--create`. Remote hosts and
existing application databases are rejected as restore targets.

Verification compares every application table's row count and ordered-row hash,
all columns, constraints and indexes, five BIGSERIAL sequence states and the
checksum-protected migration history against repository SQL files. Windows
CRLF and Railway/Linux LF copies are accepted only when their SQL bytes differ
solely by line endings. For the restored database, a temporary copy with the
source-matching line endings confirms that the migration runner applies nothing
new; neither applied SQL files nor migration records are rewritten. Rolled-back
probes test sequence inserts, unique email, foreign keys, token CHECK constraints
and account-delete cascades. The script removes only its own newly created drill
database. The archive stays available. Database roles, service secrets and
provider settings are outside this dump and must be separately restored for an
actual cutover.

## Railway synthetic-data drill: verified

`npm.cmd run db:backup:railway-drill` first takes a clean staging baseline. It
then inserts one uniquely identified `@example.invalid` account and synthetic
Thought, takes a second backup and verifies that the restored copy contains the
marker. In `finally`, it deletes only that account by exact ID plus email and
compares the remaining source table hashes with the baseline. Source sequences
may advance. It also restores and verifies the clean baseline.

Completion requires two verified local restores, original source rows preserved,
fixture deletion, temporary SSH-key revocation, tunnel and drill-database cleanup.
After the cloud work, log out of the CLI and revoke its OAuth grant under Railway
Account Settings -> Apps.

## Evidence: 2026-09-29 and 2026-10-01 (Asia/Hong_Kong)

- Local PostgreSQL 18.3 database `noahs_ark` backed up to
  `local-20260928T163848Z-7ddd3028.dump` (21,557 bytes).
- Repeated with the current script on 2026-10-01:
  `local-20261001T115311Z-d05d7fae.dump` (21,557 bytes) was restored and
  verified in 1,437 ms; its separate drill database was also removed.
- Source/restored rows: users 3, Thoughts 6, email-verification tokens 3,
  refresh tokens 6, password-reset tokens 0, schema migrations 6.
- All row hashes, schema definitions, sequences and migration checksums matched;
  behavioral probes passed. Restore/verification took 1,224 ms.
- The temporary drill database was removed. The original local database remains
  and the archive, manifest and successful restore report are ignored by Git.
- Backend unit tests passed 54/54, including unsafe-target, corrupted-archive
  rejection and LF/CRLF-only migration matching. The current local archive was
  restored again with the updated script in 1,450 ms; its drill database was
  removed. Flutter and PostgreSQL API integration suites were not run for this
  backend operations-only work.
- Railway status showed only `staging`, with API commit `fc16bf7` and pre-deploy
  command `npm run db:migrate`. The initial SSH banner timeouts were avoided
  after disabling the user's VPN TUN mode for the exercise; OpenSSH then
  completed protocol exchange. All six staging migration checksums matched the
  repository SQL after LF normalization, not after comparing Windows CRLF bytes.
- Clean staging baseline: `railway-baseline-20261001T125405Z-e434ab88.dump`
  (20,174 bytes), with 0 users, Thoughts and tokens, plus 6 migrations. Its
  archive SHA-256, rows, schema, sequences, migration history and behavioral
  probes passed a 611 ms isolated local restore; the drill database was removed.
- Synthetic marker: `railway-drill-20261001T125450Z-90221016.dump` (20,407
  bytes), with 1 disposable user and 1 Thought. Its isolated restore recovered
  the marker and passed the same checks in 627 ms; the drill database was removed.
  The exact source fixture was deleted and original staging row hashes matched
  the clean baseline. Source sequences may have advanced.
- Independent `railway ssh keys list` showed no registered keys. No temporary
  SSH or migration-copy directories remained. Both staging archives, manifests
  and restore reports are ignored by Git and retained locally; they are not an
  encrypted or offsite copy.
- `railway logout` succeeded; a subsequent `railway whoami` returned
  `Unauthorized`. The user confirmed revoking the Railway CLI OAuth grant in
  Account Settings -> Apps; this browser-side action was not independently
  queried by the script.
- Git commit/push and remote CI are unverified.

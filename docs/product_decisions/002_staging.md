# Staging environment decision

Status: Implemented and verified on 2026-09-25.

## Purpose

The staging environment exists only to verify the experimental Express and
PostgreSQL backend outside the local Docker environment.

It must not contain production user data, private journal content, exported
backups or Flash Thought audio.

## Provider decision

Render Free was abandoned before resource creation because the account required
credit-card verification. No Render service, database or charge was created.

Railway Free was selected because its trial does not require a credit card.

## Approved topology

- Platform: Railway Free
- Region: Southeast Asia Metal (Singapore)
- API: one GitHub service rooted at `/backend` and built from
  `backend/Dockerfile`
- Database: one Railway PostgreSQL service in the same project and region
- Migrations: Railway pre-deploy command `node src/migrate.js`
- Health check: `/health`
- Email delivery: disabled
- Data: disposable test accounts and test Thoughts only
- Flutter synchronization: not enabled

## Cost and lifetime boundary

- Initial target cost: USD 0
- The new-account trial provides USD 5 of one-time resource credit for 30 days.
- After the trial, the Free plan provides USD 1 of monthly resource credit.
- Do not add a payment method or upgrade a plan without explicit approval.
- The staging services may stop when their available credit is exhausted.
- Day 72 requires a separate backup and long-term database decision.

## Verified deployment

Verified on 2026-09-25.

- Railway project: `noahs-ark-staging`
- Environment: `staging`
- GitHub source: `ASAXAE/noahs_ark`, branch `master`
- API service: `noahs_ark`
- Database service: `Postgres`
- Region and scale: Southeast Asia (Singapore), one replica per service
- Root directory: `/backend`
- Dockerfile path: `/backend/Dockerfile`
- Watch path: `/backend/**`
- GitHub deployment gate: Wait for CI enabled
- Public API: `https://noahsark-staging.up.railway.app`
- PostgreSQL networking: Railway private network only; no public TCP proxy
- Estimated staging footprint: one API replica plus one PostgreSQL replica,
  within the displayed 2 vCPU and 1 GB per-replica trial limits
- Trial boundary at setup: 30 days or USD 5 remaining; no payment method or
  paid upgrade
- Verification: migrations `001` through `006`, `/health`,
  `/database-health`, registration, login, refresh rotation, logout and
  account deletion all succeeded using disposable test data
- Cleanup: the disposable staging account was deleted after verification

## Day 69 acceptance criteria

- [x] Staging configuration contains no committed secrets.
- [x] Migrations `001` through `006` are applied to a fresh database.
- [x] `/health` and `/database-health` return successful responses.
- [x] Registration, login, refresh, logout and account deletion use test data only.
- [x] Local SQLite records and Flash Thought audio remain local.
- [x] Resource names, region and estimated usage are recorded.

## Day 70 acceptance criteria

Verified on 2026-09-25.

- [x] The public `/health` endpoint returns 200 over verified HTTPS.
- [x] Staging responses include
  `Strict-Transport-Security: max-age=31536000` without subdomain or preload
  directives.
- [x] `DB_SSL_MODE=require` enforces an encrypted PostgreSQL connection, and
  `/database-health` reports `tlsEnabled: true` from `pg_stat_ssl`.
- [x] PostgreSQL remains reachable only through Railway private networking;
  no public TCP proxy is enabled.
- [x] The Railway project contains only the `staging` environment. No
  production environment, production service, production variables or
  production data exist.
- [x] The staging JWT signing secret was replaced with a newly generated random
  value without being committed or exposed in logs.
- [x] The PostgreSQL password was regenerated through Railway's database
  configuration, and the API was redeployed to resolve the updated password
  reference.
- [x] Registration, login, authenticated `/auth/me`, account deletion and
  deleted-account rejection succeeded after both credential rotations.
- [x] The disposable verification account was deleted; the staging `users`
  table is empty.
- [x] GitHub Actions run 26 passed backend unit tests, PostgreSQL integration,
  backend Docker build and Flutter checks for commit `b4b399d`.

## Day 70 security decisions and limits

- HSTS is controlled by `ENABLE_HSTS` so local HTTP development remains
  available while verified staging HTTPS opts in explicitly.
- Railway PostgreSQL uses a self-signed certificate. The staging client
  requires encryption with `rejectUnauthorized: false`; server-certificate
  identity is therefore not independently verified. The database remains
  behind Railway's isolated, encrypted private network with no public TCP
  exposure.
- Express `trust proxy` remains disabled. Railway documents `X-Real-IP` for the
  client address, while Express proxy trust is based on a topology-specific
  trust contract. The current process-local rate limiters remain staging
  controls and are not production-grade distributed limits.
- Rotating `JWT_SECRET` invalidates previously issued access tokens, whose
  configured maximum lifetime is 15 minutes. Refresh tokens can obtain access
  tokens signed with the replacement secret.
- Database-password rotation can briefly interrupt staging until the dependent
  API service is redeployed.

# Staging environment decision

Status: Approved for Railway Free staging on 2026-09-24.

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

## Day 69 acceptance criteria

- Staging configuration contains no committed secrets.
- Migrations `001` through `006` are applied to a fresh database.
- `/health` and `/database-health` return successful responses.
- Registration, login, refresh, logout and account deletion use test data only.
- Local SQLite records and Flash Thought audio remain local.
- Resource names, region and estimated usage are recorded.

## Deferred to Day 70

- HTTPS verification
- PostgreSQL TLS enforcement
- environment isolation
- secret rotation
- HSTS and proxy-trust decisions
# Staging environment decision

Status: Approved for Render Free staging on 2026-09-24.

## Purpose

The staging environment exists only to verify the experimental Express and
PostgreSQL backend outside the local Docker environment.

It must not contain production user data, private journal content, exported
backups or Flash Thought audio.

## Proposed topology

- Platform: Render Free
- Region: Singapore
- API: one Docker web service built from `backend/Dockerfile`
- Database: one PostgreSQL 17 staging database in the same region
- Email delivery: disabled
- Data: disposable test accounts and test Thoughts only
- Flutter synchronization: not enabled

## Cost and lifetime boundary

- Initial target cost: USD 0
- Do not add a payment method or upgrade a resource without explicit approval.
- The free web service can sleep while idle.
- The free PostgreSQL database expires after 30 days and has no backups.
- Day 72 therefore requires a separate database-cost decision.

## Day 69 acceptance criteria

- Staging configuration contains no committed secrets.
- Migrations `001` through `006` are applied to a fresh database.
- `/health` and `/database-health` return successful responses.
- Registration, login, refresh, logout and account deletion use test data only.
- Local SQLite records and Flash Thought audio remain local.
- Resource names, region, expiry date and cleanup responsibility are recorded.

## Deferred to Day 70

- HTTPS verification
- PostgreSQL TLS enforcement
- environment isolation
- secret rotation
- HSTS and proxy-trust decisions
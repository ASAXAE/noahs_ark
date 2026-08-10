# Local-first product decision

## Decision

1. Users can use the core journal without an account.
2. Local thoughts remain in SQLite unless the user explicitly enables sync.
3. Login, cloud sync, AI processing, and community publishing are separate choices.

## Reason

Noah's Ark contains private reflections. Users should be able to record their
thoughts without creating an account or uploading personal data.

## V1 scope

- No account is required.
- Core records are stored locally with SQLite.
- The Express and PostgreSQL backend remains experimental.
- Cloud synchronization, AI, and community features are not part of V1.
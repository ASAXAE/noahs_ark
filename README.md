# Noah's Ark（诺亚方舟）

An offline-first reflection journal built with Flutter, with an experimental
Express and PostgreSQL backend.

一款使用 Flutter 开发的本地优先思考记录 App。核心记录默认保存在设备的
SQLite 中；Express + PostgreSQL 功能目前用于学习全栈开发和验证客户端与服务器
之间的完整 CRUD 数据链路。

<p align="center">
  <img src="assets/branding/noahs_ark_app_icon.png" alt="Noah's Ark app icon" width="160" />
</p>

> Status: V1 release candidate. The offline app is functional and the signed
> Android APK has passed local smoke testing. The experimental backend now
> supports authenticated, per-user Thought CRUD, but it is not a
> production-ready sync service.

## Features / 已完成功能

### Flutter app

- Create, edit and delete reflections
- Offline persistence with SQLite
- Titles, tags and favorites
- Search and tag filtering
- Expandable long-text previews
- Reusable `ThoughtCard` widget
- Rounded card action menu for editing, favoriting and deleting records
- Empty states for an empty ark and filtered search results
- Local JSON backup export through the system share sheet
- Validated JSON backup restore into SQLite
- Merge-style restore that preserves existing data and skips duplicate records
- Settings and in-app local-first privacy information
- Optional backend account registration and login without blocking local-only use
- Registration form with password confirmation and client-side validation
- Refined authentication UX with clear login/register switching, disabled form
  controls while submitting and localized Chinese error feedback
- JWT access tokens stored with Flutter secure storage
- Login restoration after an app restart and explicit logout
- Saved JWT bearer tokens automatically attached to every experimental Thought
  API request (`GET`, `POST`, `PATCH` and `DELETE`)
- Account status card, top-of-page login confirmation and logout confirmation
  that explains local records remain on the device
- Branded Android adaptive launcher icon
- JSON serialization, backup parsing and model tests

### Experimental backend

- Flutter communicates with Express through HTTP and JSON
- PostgreSQL persistence for server-side test records
- Complete server-side CRUD:
  - `GET /thoughts`
  - `POST /thoughts`
  - `PATCH /thoughts/:id`
  - `DELETE /thoughts/:id`
- Request validation with automated Node.js tests
- `users` and `thoughts` tables connected by a foreign key
- SQL migration files for reproducible database setup
- Experimental `POST /auth/register` and `POST /auth/login` endpoints
- Registration password policy enforced by both Flutter and Express: 8–72
  characters with at least one English letter and one number
- Password hashing with `bcryptjs`; plain-text passwords are never stored
- Signed JWT access tokens protect `GET /auth/me` and every Thought CRUD route
- PostgreSQL Thought queries are scoped to the authenticated user, with
  two-account isolation coverage
- Duplicate-email protection, credential verification and authentication tests
- Database health endpoint
- Debug-only backend connection entry in the Flutter app

## Architecture / 架构

```text
Local records

Flutter UI
    ↓
ArkDatabase
    ↓
SQLite

SQLite
    ↓ export
BackupService
    ↓
JSON backup file

JSON backup file
    ↓ validate
BackupService
    ↓ transaction + duplicate check
ArkDatabase
    ↓
SQLite


Experimental server records

Flutter UI
    ↓
ApiService (HTTP + JSON + saved Bearer token)
    ↓
Express API
    ↓
JWT authentication + parameterized, user-scoped SQL
    ↓
PostgreSQL
```

Flutter never connects directly to PostgreSQL. All server data passes through
the Express API.

## Tech stack

- Flutter / Dart
- SQLite (`sqflite`)
- Node.js
- Express
- PostgreSQL (`pg`)
- Password hashing (`bcryptjs`)
- Token authentication (`jsonwebtoken`)
- Secure client token storage (`flutter_secure_storage`)
- HTTP / JSON
- Flutter Test
- Node.js Test Runner

## Android app identity

| Field | Value |
|---|---|
| App name | Noah's Ark（诺亚方舟） |
| Application ID | `io.github.asaxae.noahsark` |
| Current version | `1.0.0+1` |

The Android launcher icon uses separate background and foreground layers so it
can adapt to the device's circular or rounded-square icon mask. Editable brand
assets are kept in `assets/branding/`.

Changing the application ID makes Android treat the build as a different app.
Local SQLite data from builds using the previous ID is therefore not moved
automatically; export a JSON backup before uninstalling an older build.

## Project structure

```text
lib/
├── database/       SQLite access
├── models/         Domain models, auth session and serialization
├── screens/        App pages
├── services/       HTTP, backup and secure session storage
└── widgets/        Reusable UI components

test/
├── models/         Flutter model tests
├── services/       Backup parsing tests
└── utils/          Authentication error-message tests

backend/
├── integration/
│   ├── auth_api.integration.test.js
│   └── thought_api.integration.test.js
├── sql/
│   ├── 001_create_users.sql
│   ├── 002_create_thoughts.sql
│   └── 003_add_password_hash.sql
├── src/
│   ├── auth_middleware.js
│   ├── auth_token.js
│   ├── auth_validation.js
│   ├── database.js
│   ├── server.js
│   └── thought_validation.js
└── test/
    ├── auth_validation.test.js
    └── thought_validation.test.js

scripts/
└── start_android_dev.ps1   Android development environment helper

assets/
└── branding/               App icon source and transparent foreground
```

## API

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Check whether Express is running |
| `GET` | `/database-health` | Check the PostgreSQL connection |
| `POST` | `/auth/register` | Validate and register a backend test user |
| `POST` | `/auth/login` | Verify credentials and issue a JWT access token |
| `GET` | `/auth/me` | Return the authenticated user for a valid bearer token |
| `GET` | `/thoughts` | Fetch the authenticated user's server records |
| `POST` | `/thoughts` | Create a record for the authenticated user |
| `PATCH` | `/thoughts/:id` | Update a record owned by the authenticated user |
| `DELETE` | `/thoughts/:id` | Delete a record owned by the authenticated user |

Example request body:

```json
{
  "title": "Day 21",
  "content": "Completed the Flutter to PostgreSQL update flow.",
  "tag": "Learning",
  "isFavorite": false
}
```

Successful deletion returns:

```text
204 No Content
```

Example registration request body:

```json
{
  "displayName": "Day 30 User",
  "email": "day30@example.com",
  "password": "NoahsArk2026"
}
```

Registration passwords must contain 8–72 characters, including at least one
English letter and one number. Symbols are allowed but not required. The same
policy is checked in Flutter for immediate feedback and again by Express as the
authoritative security boundary.

The registration response contains only the new user's safe public fields. It
does not return the password or password hash.

Example login request body:

```json
{
  "email": "day30@example.com",
  "password": "NoahsArk2026"
}
```

The login endpoint returns a signed JWT access token plus safe user fields. The
Flutter app verifies the token through `/auth/me`, stores it with secure
platform storage and restores the optional account session after an app
restart. Logging out deletes the stored token. Local SQLite records remain
available whether or not the user is logged in. Authentication forms disable
their controls while a request is running, translate known API and network
errors into Chinese user-facing messages, and require confirmation before
logout.

For the experimental server-record interface, `ApiService` reads the saved
access token before each Thought request and sends it as
`Authorization: Bearer <token>`. Logged-out requests are rejected locally, and
Express uses the verified JWT user ID to isolate PostgreSQL records between
accounts. This path remains separate from the default SQLite journal: local
records are never uploaded automatically.

## Local setup

### Prerequisites

- Flutter SDK
- Android Studio or another Flutter-compatible IDE
- Node.js
- PostgreSQL

### 1. Run the Flutter app

```bash
flutter pub get
flutter run
```

The offline V1 works without starting Express or PostgreSQL. The backend steps
below are only required for the experimental server-record workflow.

### 2. Configure the optional backend

Create `backend/.env` from `backend/.env.example`:

```env
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=noahs_ark
DB_USER=postgres
DB_PASSWORD=your_postgresql_password
JWT_SECRET=replace_with_a_long_random_secret
JWT_EXPIRES_IN=1h
```

Secrets in `backend/.env` are ignored by Git.

### 3. Create the PostgreSQL tables

Run these commands from the `backend` directory:

```bash
psql -U postgres -h localhost -d noahs_ark -f sql/001_create_users.sql
psql -U postgres -h localhost -d noahs_ark -f sql/002_create_thoughts.sql
psql -U postgres -h localhost -d noahs_ark -f sql/003_add_password_hash.sql
```

The migration files create the schema only. Current Thought routes derive the
user ID from the verified JWT instead of using a fixed database user.

### 4. Start Express

```bash
cd backend
npm install
node src/server.js
```

The API runs at:

```text
http://localhost:3000
```

### Android emulator connection

The Android emulator normally reaches the host computer through
`http://10.0.2.2:3000`. If that route is unavailable, use ADB reverse:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:3000 tcp:3000
```

With ADB reverse enabled, use this development base URL in Flutter:

```text
http://127.0.0.1:3000
```

ADB reverse may need to be run again after restarting the emulator.

The included development helper checks the emulator, configures ADB reverse,
checks the Express health endpoint and starts Express in a separate terminal
when required:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_android_dev.ps1
```

The Flutter API URL can be overridden at build time:

```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

## Verification / 验证

Flutter:

```bash
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Android release artifacts:

```bash
flutter build apk --release
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

Release builds use a private upload key configured through
`android/key.properties`. That file and Android keystore files are excluded
from Git and must be created locally. Never commit signing passwords or private
keys. The current signed universal APK is produced at
`build/app/outputs/flutter-apk/app-release.apk`.

### Release smoke test

The signed universal APK was installed and tested on a clean Pixel 9 Pro
Android 17 / API 37 emulator using a 16 KB page-size system image. The verified
flow includes first launch, SQLite creation, create/edit/favorite/search/filter,
app restart persistence, APK update persistence, JSON backup export, backup
validation and merge-style restore. Re-importing the same backup correctly
skips duplicate records. External delivery from the Android share sheet, such
as Gmail delivery, depends on the selected app, account and network and is not
part of backup-file validation.

Backend:

```bash
cd backend
node --check src/server.js
node --check src/database.js
node --check src/auth_token.js
node --check src/auth_middleware.js
npm test
npm run test:integration
```

On Windows PowerShell, use `npm.cmd test` if execution policy blocks `npm.ps1`.
The integration tests require the Express server and PostgreSQL database to be
running. They verify the Thought API CRUD flow plus registration, login, JWT
issuance, authenticated `/auth/me` access and rejection of missing or invalid
tokens. They also prove that one authenticated user cannot read, update or
delete another user's thoughts. Input rejection, password hashing,
duplicate-email protection and generic rejection of invalid credentials are
covered as well. Temporary records and users created by the tests are removed
afterward.

Latest Day 41 client verification: `flutter analyze` and `flutter test` pass.
Manual emulator testing also confirms logged-out rejection and authenticated
server-record create, read, update and delete operations.

## Privacy and security

- Offline records are stored locally in SQLite by default.
- Records are not automatically uploaded to the experimental backend.
- Backup files are created only when the user explicitly exports them.
- Restore validates backup format version and record count before writing.
- Restore merges data without deleting existing records and skips matching
  duplicates.
- Exported JSON can contain private journal content and should be stored safely.
- The current backend contains test data only.
- The Flutter backend-test button is visible only in debug builds.
- `.env` and database passwords are excluded from Git.
- The API uses parameterized SQL queries.
- Registration passwords are validated and stored only as `bcrypt` hashes.
- Authentication responses never include a password or password hash.
- Incorrect passwords and unknown emails receive the same generic login error.
- JWT signing secrets stay in the ignored backend `.env` file.
- Flutter stores the access token with secure platform storage rather than
  SQLite or plain-text preferences.
- Logging out deletes the locally stored access token without deleting journal
  records.
- Production cloud sync will still require HTTPS, account deletion, secure
  secret management, deployment hardening and a privacy policy.
- An administration interface must not expose private journal content by
  default.

## Current limitations

- Registration, login, JWT verification, current-user lookup and per-user
  Thought authorization are implemented for local learning and testing.
- Account deletion, refresh tokens and email verification are not implemented.
- Server records are shown in an experimental test interface.
- The backend is intended for local development and is not deployed.
- Local SQLite records and PostgreSQL test records are not synchronized.
- V1 uses a fixed set of tags; custom tag management is not implemented yet.

## Roadmap

### Daily development sequence

- [x] Day 35–41: registration, JWT/401 handling, protected Thought routes,
  removal of the fixed `user_id = 1`, two-account isolation and automatic
  Flutter bearer-token headers
- [ ] Day 42: containerize the experimental Express and PostgreSQL development
  environment with Docker
- [ ] Day 43: add a separate local `CaptureDraft` model and SQLite table without
  changing the meaning of a formal `Thought`
- [ ] Day 44: add recording permission plus start/stop recording
- [ ] Day 45: save, play and delete original audio locally
- [ ] Day 46: add speech-to-text and retry handling while always retaining the
  original audio
- [ ] Day 47: build a Flash Thought inbox for recordings and transcripts waiting
  to be organized
- [ ] Day 48: convert a draft into a formal `Thought` only after user confirmation,
  with basic tests and a privacy review
- [ ] Day 49+: resume email verification, CI, cloud deployment, HTTPS and privacy
  hardening

The Flash Thought MVP remains local-first. It will not upload recordings to the
experimental backend, require a title or tag during capture, overwrite original
audio with generated content, or create a formal `Thought` without explicit user
confirmation.

### Product backlog

- Test the release candidate on a physical Android device
- Publish the first internally tested Android release artifact
- Add custom tag management in V1.1
- Design an opt-in, privacy-preserving sync model

## Author

ASAXAE

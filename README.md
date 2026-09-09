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
- Local Flash Thought inbox with original-audio playback and offline transcription
- Explicit transactional conversion from `CaptureDraft` to a linked `Thought`

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
- Ordered, transactional PostgreSQL migrations tracked in
  `schema_migrations` with SHA-256 checksums
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

### 3. Run PostgreSQL migrations

Run the migration command from the `backend` directory:

```bash
npm run db:migrate
```

The runner loads numbered files from `backend/sql` in version order and records
each successful migration in `schema_migrations`. Every migration runs inside a
transaction. Repeated runs skip migrations that have already been applied, while
the stored SHA-256 checksum detects later changes to migration history.

Do not edit a migration after it has been applied. Add a new file using the next
three-digit version instead. The existing migrations use `IF NOT EXISTS`, so the
runner can safely take ownership of a database whose initial tables were created
manually.

Current Thought routes derive the user ID from the verified JWT instead of using
a fixed database user.

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

### Docker development environment

Day 42 adds a reproducible local Docker Compose environment containing the
Express API and PostgreSQL 17. The API is published on port `3000`; PostgreSQL
is published on host port `5433` to avoid conflicting with a PostgreSQL service
already using the default host port `5432`.

Create a private `.env.docker` file in the project root with the Compose
variables referenced by `compose.yaml`. The file is ignored by Git and must not
be committed. With Docker Desktop running, validate and start the environment:

```powershell
docker compose --env-file .env.docker config
docker compose --env-file .env.docker up --build
```

In a second terminal, verify both services:

```powershell
docker compose --env-file .env.docker ps
Invoke-RestMethod http://localhost:3000/health
Invoke-RestMethod http://localhost:3000/database-health
```

Host-side integration tests must use the same Docker database credentials and
JWT secret as the running Compose environment. The verified Day 42 run passes
all seven authentication, authorization, isolation and Thought API integration
tests. Stop and remove the containers and Compose network without deleting the
named PostgreSQL data volume:

```powershell
docker compose --env-file .env.docker down
```

Do not add `-v` unless the PostgreSQL development data is intentionally being
discarded.

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
- [x] Day 42: containerize the experimental Express and PostgreSQL development
  environment with Docker
- [x] Day 43: add a separate local `CaptureDraft` model and SQLite table without
  changing the meaning of a formal `Thought`
- [x] Day 44: add recording permission plus start/stop recording
- [x] Day 45: save, play and delete original audio locally
- [x] Day 46: add on-device offline speech-to-text and failure retry handling
  while always retaining the original audio
- [x] Day 47: build a Flash Thought inbox for recordings and transcripts waiting
  to be organized
- [x] Day 48: convert a draft into a formal `Thought` only after user confirmation,
  with basic tests and a privacy review
- [x] Day 49: build a Material 3 `AppShell` with Ark, Flash Thought and My
  destinations while preserving all three page states. My owns account, backup,
  privacy and about. Keep AI inside the existing capture and Thought flows.
  Refresh the persistent inbox after capture or transcription changes, extract
  reusable home UI and move test-server Thought CRUD to a dedicated debug page
- [x] Day 50: continue reducing `HomePage` by moving backup management under
  Settings, extracting `HomeThoughtList` and introducing a plain
  `CaptureController` for recording, local draft persistence, model management
  and transcription state updates. Add two-state play/pause controls and
  per-draft transcription feedback to the Flash Thought inbox without introducing
  Provider or Bloc. Keep Sherpa decoding on the current isolate for now; a
  dedicated background-isolate worker remains a separate performance follow-up
- [x] Day 51: move Sherpa transcription into a long-lived `TranscriptionWorker`.
  Initialize bindings and create, reuse and dispose the recognizer inside its
  worker isolate; exchange audio paths, request IDs, text and errors with the
  main isolate. Keep SQLite and draft state in the main isolate. Verify UI
  responsiveness, sequential requests, error/retry delivery and worker shutdown.
  Run regression across the Flash Thought MVP, `HomePage` split and
  navigation. Verify permission denial, recording interruption, restart recovery,
  transcription failure, audio deletion, confirmed conversion and navigation
  state, including at least one Android physical-device microphone test. Create
  `v0.2.0-flash-mvp` only after every check passes
- [x] Day 52: establish basic CI in `.github/workflows/ci.yml`.
  Run independent Flutter and backend jobs on pushes, pull requests and manual
  dispatches, using Flutter 3.41.2 stable and Node.js 24.19.0.
  Check Dart formatting, run Flutter static analysis and tests, and install
  backend dependencies with `npm ci` before running Node unit tests.
  Keep checks independent of PostgreSQL and production secrets.
  Local verification passed: 39 Dart files required no formatting changes,
  Flutter analysis reported no issues, all 16 Flutter tests passed, and all
  15 backend unit tests passed. GitHub Actions run #1 for commit `26c7f85`
  passed both jobs: Backend unit tests in 14 seconds and Flutter checks in
  2 minutes 5 seconds. This completes basic CI; automated deployment and
  release delivery remain future work
- [x] Day 53: add a user-visible transcription queue. Allow additional drafts to
  be submitted while one is running, but execute recognition serially through
  one reusable worker/model. Show waiting, queued, transcribing, failed and
  completed states per draft, prevent duplicate submissions and continue after
  individual failures. Support cancelling queued work and safely removing queued
  drafts without later processing deleted audio; define active-task deletion
  behavior explicitly. Preserve queue state across tab navigation. For this
  first version, keep the queue in memory and return interrupted jobs to a
  retryable state after app restart rather than silently resuming them. Verify
  queue order, failure continuation, cancellation, deletion and restart recovery;
  do not equate a Dart worker isolate with Android background execution support.
  Introduce `CaptureViewModel` as the owner of transcription-queue state and
  commands, and migrate capture UI state into it incrementally instead of adding
  more page-local flags. `CaptureViewModel` now owns the in-memory FIFO queue,
  active draft ID, duplicate prevention, serial drain loop and queue-drained
  notification. `CaptureInboxPage` observes that state to show the active task
  and numbered waiting positions, cancel queued drafts and block deletion of the
  audio file currently being transcribed. Deleting a queued draft removes it
  from the queue before deleting its local file. On startup, unfinished
  `transcribing` rows are restored to an explicit retryable failure state rather
  than resumed silently. The full Flutter test suite and `flutter analyze`
  passed. Android physical-device verification passed for serial queue order,
  visible positions, duplicate prevention, queued cancellation, active-task
  deletion protection, result-to-audio matching and the single queue-completion
  dialog
- [x] Day 54: establish a formal PostgreSQL database migration mechanism.
  Discover and order numbered SQL files, track applied versions and SHA-256
  checksums in `schema_migrations`, execute each pending migration in a
  transaction and roll back failures. Add `npm run db:migrate` and automated
  coverage for ordering, filename validation, duplicate versions, idempotence,
  history changes and rollback. All 22 backend tests passed. PostgreSQL 18
  verification applied migrations `001` through `003` on the first run and
  reported the database up to date on the second run
- [ ] Day 55: extend CI with PostgreSQL, migrations, two-account integration tests
  and a Docker build
- [ ] Day 56: define recording-session ownership independently of page widgets,
  including permission checks, lifecycle transitions, interruption handling and
  recovery. Introduce `CaptureRepository` as the source of truth for capture
  drafts and recording/transcription operations. It coordinates `ArkDatabase`,
  audio services, model management and `TranscriptionWorker`; migrate callers
  from the transitional `CaptureController` before removing that class. Select
  an Android microphone foreground-service integration and establish one
  authoritative recording state shared by the UI and service
- [ ] Day 57: implement user-initiated microphone foreground-service recording
  with a required recording notification. Verify continuous audio while switching
  apps or locking the screen; stopping must finalize local audio, save one draft
  and end the service
- [ ] Day 58: add elapsed recording time and a Stop and Save action to the
  notification. Keep notification and in-app state consistent, including stopping
  from the notification and returning to the app without duplicate draft saves
- [ ] Day 59: verify background recording on physical Android devices, covering
  lock screen, long recordings, microphone contention, permission changes and
  process termination. Recover usable saved audio where possible and surface
  interruptions honestly; never imply that force-stopped recording continues
- [ ] Day 60: move the recording entry from the Ark home page into the Flash
  Thought destination. Add an in-app recording panel with elapsed time, real
  audio-level feedback and Stop and Save. Preserve an active recording when
  navigating between destinations and restore its visible state on return.
  Complete the capture UI boundary so `CaptureInboxPage` renders ViewModel state
  and forwards user actions, while `HomePage` no longer owns capture behavior
- [ ] Day 61: add playback progress and seeking to inbox audio, showing current
  position and total duration. Verify seeking, pause/resume, completion, switching
  clips and deletion during playback. Regress the new capture entry together
  with background recording, notification controls and confirmed conversion.
  Keep playback state and commands outside the page, then review the completed
  `View → ViewModel → Repository → Database/Service` boundary
- [ ] Day 62: add email-verification database structures with expiring,
  single-use tokens stored only as hashes
- [ ] Day 63: add a mail-sending adapter, development fake sender, resend flow and
  rate limits. External services require explicit approval
- [ ] Day 64: show email-verification state, resend and results in Flutter without
  restricting local-only use
- [ ] Day 65: add short-lived access tokens plus refresh-token hashing, rotation,
  reuse detection, revocation and secure storage
- [ ] Day 66: add password recovery and reset without revealing whether an email
  exists, and revoke old sessions after a successful reset
- [ ] Day 67: add account deletion for cloud accounts, server data and sessions
  without deleting local SQLite, backups or original audio by default
- [ ] Day 68: harden the API
- [ ] Day 69: prepare staging; cloud platform, resources and costs require explicit
  approval
- [ ] Day 70: verify HTTPS, database TLS, environment isolation and secret rotation
- [ ] Day 71: productionize health checks, request IDs, error monitoring and
  privacy-safe logging
- [ ] Day 72: configure PostgreSQL backups and complete a real restore exercise
- [ ] Day 73: finish the privacy policy, retention periods, third-party-service
  disclosures and recording/transcription consent rules
- [ ] Day 74: complete full Android physical-device regression
- [ ] Day 75: prepare versioning, changelog, signed APK/AAB and internal-test notes
- [ ] Day 76: pass the release gate before creating
  `v0.3.0-cloud-foundation`
- [ ] Day 77: write an optional synchronization design document without
  implementing uploads
- [ ] Day 78–84: sequentially add UUID and sync metadata, an explicit sync switch,
  idempotent synchronization, cursor-based upload/download, an offline queue,
  conflict and deletion propagation, then dual-device and staged-rollout testing.
  Create `v0.4.0-sync-beta` only after every check passes

The Flash Thought MVP remains local-first. It will not upload recordings to the
experimental backend, require a title or tag during capture, overwrite original
audio with generated content, or create a formal `Thought` without explicit user
confirmation. Local Thoughts, backups and original audio must never upload
automatically. AI organization remains deferred until its privacy and
third-party-service rules are explicitly defined.

Day 48 privacy review confirms that conversion stays inside local SQLite,
requires both confirmation and an explicit save action, retains the original
audio, and makes no HTTP request. Deleting the converted `Thought` clears only
the local relationship so its `CaptureDraft` and audio remain available for
reorganization. Manual emulator checks covered cancellation, leaving without
saving, conversion, linked record opening, original-audio retention and
unlink-on-delete. The focused `CaptureDraft` model test also passes.

### Flash Thought capture direction / 闪念记录规划

The Flash Thought destination will own both capture entry points and the inbox.
The Ark home page will focus on formal Thoughts, search and filtering; its
recording button moves to Flash Thought on Day 60. Recording-session ownership
must remain independent of the currently visible page.

- Recording feedback: show elapsed time and a live audio-level indicator or
  waveform derived from microphone input. An open-ended recording has no known
  completion percentage, so do not display a fabricated percentage progress bar.
  If a maximum duration is introduced later, show the limit explicitly. Silence
  alone must not be treated as proof of a recording failure.
- Playback feedback: show a seekable progress bar with current position and total
  duration on Day 61. Keep its position synchronized with the actual player.
- Transcription submission: Day 53 replaced the single-submission guard with an
  in-memory, user-visible FIFO queue. It keeps one active recognizer, shows each
  waiting position, prevents duplicate submissions and emits one completion
  dialog only after the queue drains. Successful drafts proceed to organization;
  successful-result retranscription remains a separate future action requiring
  a clear policy for replacing existing text.
- Future input direction: the user envisions two Flash Thought capture methods:
  audio recording and brain-computer interface (BCI / 脑机接口) device input.
  After Day 84, schedule a separate feasibility milestone before implementation:
  identify a candidate device and available SDK/protocol, verify its actual
  output (such as signals, events or commands), mobile compatibility, access
  requirements and privacy constraints, and demonstrate a minimal input flow.
  Do not assume that a device can decode free-form thoughts into journal text.
  Hardware purchases, external services and transmission of neural data require
  explicit user approval. Set implementation days only after feasibility is
  established; do not add a nonfunctional button or speculative data schema now.
  Any adopted input method must preserve local-first storage and explicit
  confirmation before creating a formal Thought.
- Platform status surfaces: Android recording notifications are part of
  Day 57–58. Apple Live Activities / Dynamic Island and Android vendor-specific
  capsule displays are separate future enhancements requiring supported devices
  and platform research; they are not prerequisites for continuous recording.

### Gradual MVVM direction / 渐进式 MVVM 调整

The capture feature will move toward Flutter's recommended separation of Views,
ViewModels, Repositories and Services as its next features are built. This is a
responsibility-based migration, not a rewrite, and it does not change the meaning
of the `v0.2.0-flash-mvp` product milestone. Flutter's architecture guidance is
available in the [official app architecture guide](https://docs.flutter.dev/app-architecture/guide).

```text
CaptureInboxPage (View)
        ↓ user actions / observes UI state
CaptureViewModel
        ↓ capture operations / observes source-of-truth state
CaptureRepository
        ↓
ArkDatabase + audio services + model manager + TranscriptionWorker
```

- `CaptureViewModel` owns recording, playback and transcription-queue UI state,
  exposes commands for user actions, and converts repository data into state the
  View can render. It must not perform SQLite, file, plugin or Sherpa calls
  directly.
- `CaptureRepository` is the source of truth for `CaptureDraft` data and capture
  session state. It coordinates database and platform services, centralizes
  retry/error rules and exposes stable operations and observable state to the
  ViewModel.
- `CaptureInboxPage` becomes a View: it renders ViewModel state, handles layout,
  dialogs and navigation, and forwards recording, playback, transcription,
  organization and deletion actions as commands. It must not call
  `ArkDatabase` or audio services directly after the migration is complete.
- `ArkDatabase` and the audio, model and Sherpa worker classes remain the lowest
  data/platform layer. They perform SQLite, local-file, plugin and inference work
  without depending on widgets or BuildContext.

The current `CaptureController` is a transition point rather than the final
architecture. Day 53 moved queue state and commands into `CaptureViewModel`;
Day 56 introduces `CaptureRepository` while recording
ownership is redesigned; Day 60–61 completes the View boundary as capture and
playback UI move under Flash Thought. Keep constructor-based dependencies and
well-defined interfaces so each responsibility can be tested independently.
Adding Provider, Riverpod, Bloc or another state-management package is a separate
decision and is not required merely to call the structure MVVM.

During migration, preserve one working path at a time: move responsibility,
update its callers, verify behavior, and only then remove the old path. Do not
maintain two writable sources of truth for the same recording, queue or draft
state, and do not combine this refactor with cloud sync or BCI integration.

Day 51 physical-device findings (OPPO A52 / PDAM10, Android 11): the user verified
permission denial feedback, recording after restoring permission, clear
approximately 30-second audio, playback and saved-draft playback after restart.
Profile-mode cold launch took approximately two seconds, compared with more than
ten seconds in debug mode; the user also verified the updated native launch logo.
The original recording implementation lost the background segment while the UI
continued to indicate recording. An interim lifecycle handler now stops and
saves on `paused`, with feedback on return. The user verified Home-key and
lock-screen auto-save, one playable draft per recording, uninterrupted capture
across in-app tabs, and recovery after immediately backgrounding a new recording.
After this change, a focused microphone-permission denial regression also showed
the correct message, no background-save message, no empty draft and no stuck
recording control. Deleting a disposable draft removed it immediately and it
remained absent after restart, with no error shown.
Day 56–59 will replace this fallback with supported background recording.

Offline model files were imported over USB because phone Wi-Fi was unavailable.
Before the worker change, the user verified accurate local transcription in
approximately three seconds and an injected controller failure followed by
successful retry with original audio retained; that injection was removed.
After the worker change, the user verified successful transcription with smooth
scrolling, tab switching and an animated loading indicator, followed by another
successful draft in the same app session. An injected worker-isolate failure was
returned to the main isolate, left the original audio playable and then retried
successfully through the same worker; the injection was removed afterward.
These results verify sequential reuse, not measured model-load counts. Graceful
shutdown is implemented through an explicit dispose message and worker `finally`,
but no dedicated runtime observation was performed. Returning to the Android
home screen pauses background computation, so the isolate must not be described
as background-execution support. Remaining Day 51 regression checks still apply;
do not create `v0.2.0-flash-mvp` until all required checks pass.

Day 51 also found that converting a draft wrote the new `Thought` to SQLite but
left the Ark page's cached list stale until manual refresh. `CaptureInboxPage`
now reports a successful conversion through `onThoughtsChanged`, and `HomePage`
reloads its owned Thought list. Physical-device verification confirmed that the
draft changes to organized and the new formal record appears in Ark immediately
without pull-to-refresh. The reverse direction is synchronized as well:
successful Thought changes reload Ark and increment the inbox refresh version,
while changes opened from a converted draft refresh both pages. Physical-device
verification confirmed that deleting the linked formal record immediately
restores the draft to an organizable state, retains playable original audio and
requires no pull-to-refresh.

Day 51 automated verification completed after the final changes: `dart format`
reported all four changed Dart files already formatted, all 16 Flutter tests
passed, `flutter build apk --debug` produced `app-debug.apk`, and
`git diff --check` reported no whitespace errors. `flutter analyze` was not run
for this learning task. The Android 11 launch screen, physical-device recording,
interruption fallback, offline transcription, conversion and navigation checks
above provide the manual acceptance evidence for `v0.2.0-flash-mvp`.

Days are learning work units rather than guaranteed calendar-day estimates.
Day 52 completed basic CI, Day 53 completed the transcription queue and
`CaptureViewModel` ownership step, and Day 54 completed the formal PostgreSQL
migration runner with automated and local-database verification. Day 55 next
extends CI with PostgreSQL, migrations, integration tests and a Docker build.
Day 56–59 adds background recording and Day 60–61 adds capture-entry and playback
UX work. Account work starts on Day 62, the cloud-foundation release gate is Day
76, and optional sync is Day 77–84. Future unchecked tasks remain plans.

### Product backlog

- Test the release candidate on a physical Android device
- Publish the first internally tested Android release artifact
- Add custom tag management in V1.1
- Design an opt-in, privacy-preserving sync model
- Research BCI device input after Day 84; select hardware and validate actual
  output and privacy boundaries before scheduling a Flash Thought integration
- Evaluate Live Activities / Dynamic Island and Android vendor status capsules
  after the core recording lifecycle and notification controls are reliable

## Author

ASAXAE

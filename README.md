# Noah's Ark（诺亚方舟）

An offline-first reflection journal built with Flutter, with an experimental
Express and PostgreSQL backend.

一款使用 Flutter 开发的本地优先思考记录 App。核心记录默认保存在设备的
SQLite 中；Express + PostgreSQL 功能目前用于学习全栈开发和验证客户端与服务器
之间的完整 CRUD 数据链路。

> Status: actively developed. The backend currently uses a fixed test user and
> is not a production-ready sync service.

## Features / 已完成功能

### Flutter app

- Create, edit and delete reflections
- Offline persistence with SQLite
- Titles, tags and favorites
- Search and tag filtering
- Expandable long-text previews
- Reusable `ThoughtCard` widget
- JSON serialization and model tests

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
- Database health endpoint

## Architecture / 架构

```text
Local records

Flutter UI
    ↓
ArkDatabase
    ↓
SQLite


Experimental server records

Flutter UI
    ↓
ApiService (HTTP + JSON)
    ↓
Express API
    ↓
Parameterized SQL
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
- HTTP / JSON
- Flutter Test
- Node.js Test Runner

## Project structure

```text
lib/
├── database/       SQLite access
├── models/         Domain models and serialization
├── screens/        App pages
├── services/       HTTP services
└── widgets/        Reusable UI components

test/
└── models/         Flutter model tests

backend/
├── sql/
│   ├── 001_create_users.sql
│   └── 002_create_thoughts.sql
├── src/
│   ├── database.js
│   ├── server.js
│   └── thought_validation.js
└── test/
    └── thought_validation.test.js
```

## API

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Check whether Express is running |
| `GET` | `/database-health` | Check the PostgreSQL connection |
| `GET` | `/thoughts` | Fetch server-side test records |
| `POST` | `/thoughts` | Create a server-side test record |
| `PATCH` | `/thoughts/:id` | Update a server-side test record |
| `DELETE` | `/thoughts/:id` | Delete a server-side test record |

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

### 2. Configure the backend

Create `backend/.env` from `backend/.env.example`:

```env
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=noahs_ark
DB_USER=postgres
DB_PASSWORD=your_postgresql_password
```

Secrets in `backend/.env` are ignored by Git.

### 3. Create the PostgreSQL tables

Run these commands from the `backend` directory:

```bash
psql -U postgres -h localhost -d noahs_ark -f sql/001_create_users.sql
psql -U postgres -h localhost -d noahs_ark -f sql/002_create_thoughts.sql
```

The current learning version expects a test user with `id = 1`.

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

## Verification / 验证

Flutter:

```bash
dart format lib test
flutter analyze
flutter test
```

Backend:

```bash
cd backend
node --check src/server.js
node --check src/database.js
npm test
```

On Windows PowerShell, use `npm.cmd test` if execution policy blocks `npm.ps1`.

## Privacy and security

- Offline records are stored locally in SQLite by default.
- The current backend contains test data only.
- `.env` and database passwords are excluded from Git.
- The API uses parameterized SQL queries.
- Production cloud sync will require authentication, HTTPS, per-user
  authorization, account deletion, secure secret management and a privacy
  policy.
- An administration interface must not expose private journal content by
  default.

## Current limitations

- Server requests currently operate as a fixed test user (`user_id = 1`).
- Authentication and account management are not implemented.
- Server records are shown in an experimental test interface.
- The backend is intended for local development and is not deployed.
- Local SQLite records and PostgreSQL test records are not synchronized.

## Roadmap

- Replace the fixed test user with authentication and authorization
- Separate server test UI from the home page
- Add API integration tests
- Add local export and restore for the offline V1
- Design an opt-in, privacy-preserving sync model
- Add CI checks for Flutter and backend tests

## Author

ASAXAE

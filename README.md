# Noah's Ark（诺亚方舟）

一款使用 Flutter 开发的个人思考记录 App。

Noah's Ark is an offline-first reflection journal built with Flutter.

> 项目仍在开发中。公开版计划默认只在本机保存数据；服务器功能目前用于学习、作品展示和封闭测试。

## 已完成功能

### Flutter App

- 新建、编辑和删除记录
- 使用 SQLite 在手机本地保存记录
- 标题与标签
- 搜索与标签筛选
- 收藏记录
- 展开和收起长文本
- JSON 序列化与模型测试

### 实验性后端

- Flutter 通过 HTTP 调用 Express API
- `GET /thoughts` 获取服务器记录
- `POST /thoughts` 创建服务器测试记录
- Express 使用 PostgreSQL 永久保存记录
- `users` 与 `thoughts` 数据表
- 使用外键让记录属于指定用户
- 数据库迁移 SQL 文件
- Express 重启后服务器记录仍然存在

## 技术栈

- Flutter / Dart
- SQLite
- Node.js
- Express
- PostgreSQL

## 当前架构

```text
本地记录：

Flutter
   ↓
SQLite

实验性服务器记录：

Flutter
   ↓ HTTP + JSON
Express
   ↓ 参数化 SQL
PostgreSQL
```

Flutter 不会直接连接 PostgreSQL。所有服务器数据都必须经过 Express API。

## 项目结构

```text
lib/
├── database/       SQLite 数据操作
├── models/         数据模型
├── screens/        App 页面
├── services/       HTTP 服务
└── widgets/        可复用组件

backend/
├── sql/
│   ├── 001_create_users.sql
│   └── 002_create_thoughts.sql
└── src/
    ├── database.js
    └── server.js
```

## 本地运行

### Flutter

```bash
flutter pub get
flutter run
```

### Express

```bash
cd backend
npm install
node src/server.js
```

环境变量保存在 `backend/.env` 中。该文件包含本地数据库密码，不会提交到 Git。

配置示例参见：

```text
backend/.env.example
```

### PostgreSQL

按顺序执行数据库迁移：

```bash
psql -U postgres -h localhost -d noahs_ark -f sql/001_create_users.sql
psql -U postgres -h localhost -d noahs_ark -f sql/002_create_thoughts.sql
```

以上命令需要在 `backend` 目录中运行。

## 验证

```bash
dart format lib test
flutter analyze
flutter test
node --check backend/src/server.js
node --check backend/src/database.js
```

## 隐私原则

- 本地记录默认保存在用户设备的 SQLite 中
- 当前服务器功能只使用虚构测试数据
- `.env` 和数据库密码不会上传到 GitHub
- 未来公开云同步前，需要完成身份认证、HTTPS、用户数据隔离、账户删除和隐私政策
- 管理后台不应默认展示用户的私人记录正文

## 下一步

- 为 Express API 添加输入校验
- 完成服务器记录的编辑与删除接口
- 添加后端自动测试
- 为离线 V1 增加数据导出与恢复
- 云同步保留为后续可选功能

## 作者

ASAXAE

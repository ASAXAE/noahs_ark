import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/capture_draft.dart';

import '../models/thought.dart';

class BackupImportResult {
  const BackupImportResult({
    required this.importedCount,
    required this.skippedCount,
  });

  final int importedCount;
  final int skippedCount;
}

class ArkDatabase {
  ArkDatabase._();

  static final instance = ArkDatabase._();
  static const _databaseVersion = 4;
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'noahs_ark_v1.db');
    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, _) async {
        await _createThoughtsTable(db);
        await _createCaptureDraftsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE thoughts ADD COLUMN title TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          await _createCaptureDraftsTable(db);
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE capture_drafts ADD COLUMN converted_thought_id INTEGER',
          );
        }
      },
    );
  }

  Future<void> _createThoughtsTable(Database db) => db.execute('''
    CREATE TABLE thoughts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL,
      tag TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      is_favorite INTEGER NOT NULL DEFAULT 0
    )
  ''');

  Future<void> _createCaptureDraftsTable(Database db) => db.execute('''
    CREATE TABLE capture_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      audio_path TEXT NOT NULL,
      transcript TEXT,
      transcription_status TEXT NOT NULL DEFAULT 'pending',
      transcription_error TEXT,
      converted_thought_id INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  Future<int> insertCaptureDraft(CaptureDraft draft) async {
    final db = await database;
    final values = draft.toMap()..remove('id');

    return db.insert('capture_drafts', values);
  }

  Future<CaptureDraft?> getCaptureDraft(int id) async {
    final db = await database;
    final rows = await db.query(
      'capture_drafts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CaptureDraft.fromMap(rows.first);
  }

  Future<List<CaptureDraft>> getCaptureDrafts() async {
    final db = await database;

    final rows = await db.query('capture_drafts', orderBy: 'created_at DESC');

    return rows.map(CaptureDraft.fromMap).toList();
  }

  Future<void> updateCaptureDraft(CaptureDraft draft) async {
    final id = draft.id;

    if (id == null) {
      throw ArgumentError('Cannot update a CaptureDraft without an id');
    }

    final db = await database;
    final values = draft.toMap()..remove('id');

    await db.update('capture_drafts', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> convertCaptureDraftToThought({
    required int draftId,
    required Thought thought,
  }) async {
    if (thought.id != null) {
      throw ArgumentError('A converted Thought must not already have an id');
    }

    final db = await database;

    await db.transaction((transaction) async {
      final eligibleDrafts = await transaction.query(
        'capture_drafts',
        columns: ['id'],
        where:
            'id = ? AND transcription_status = ? '
            'AND converted_thought_id IS NULL',
        whereArgs: [draftId, CaptureTranscriptionStatus.completed.name],
        limit: 1,
      );

      if (eligibleDrafts.isEmpty) {
        throw StateError(
          'CaptureDraft is missing, unfinished, or already converted',
        );
      }

      final thoughtValues = thought.toMap()..remove('id');
      final thoughtId = await transaction.insert('thoughts', thoughtValues);

      final updatedCount = await transaction.update(
        'capture_drafts',
        {
          'converted_thought_id': thoughtId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND converted_thought_id IS NULL',
        whereArgs: [draftId],
      );

      if (updatedCount != 1) {
        throw StateError('Failed to link CaptureDraft to Thought');
      }
    });
  }

  Future<void> deleteCaptureDraftByAudioPath(String audioPath) async {
    final db = await database;

    await db.delete(
      'capture_drafts',
      where: 'audio_path = ?',
      whereArgs: [audioPath],
    );
  }

  Future<Thought?> getThought(int id) async {
    final db = await database;

    final rows = await db.query(
      'thoughts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Thought.fromMap(rows.first);
  }

  Future<List<Thought>> getThoughts({
    String query = '',
    String? tag,
    bool favoritesOnly = false,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      final keyword = '%${query.trim()}%';

      where.add('(title LIKE ? OR content LIKE ?)');
      args.add(keyword);
      args.add(keyword);
    }
    if (tag != null) {
      where.add('tag = ?');
      args.add(tag);
    }
    if (favoritesOnly) where.add('is_favorite = 1');
    final rows = await db.query(
      'thoughts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Thought.fromMap).toList();
  }

  Future<void> saveThought(Thought thought) async {
    final db = await database;
    final values = thought.toMap()..remove('id');
    if (thought.id == null) {
      await db.insert('thoughts', values);
    } else {
      await db.update(
        'thoughts',
        values,
        where: 'id = ?',
        whereArgs: [thought.id],
      );
    }
  }

  Future<void> deleteThought(int id) async {
    final db = await database;

    await db.transaction((transaction) async {
      await transaction.update(
        'capture_drafts',
        {
          'converted_thought_id': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'converted_thought_id = ?',
        whereArgs: [id],
      );

      await transaction.delete('thoughts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<BackupImportResult> importThoughts(List<Thought> thoughts) async {
    final db = await database;

    return db.transaction((transaction) async {
      final existingRows = await transaction.query('thoughts');

      final existingFingerprints = existingRows
          .map(Thought.fromMap)
          .map(_thoughtFingerprint)
          .toSet();

      var importedCount = 0;
      var skippedCount = 0;

      for (final thought in thoughts) {
        final fingerprint = _thoughtFingerprint(thought);

        if (existingFingerprints.contains(fingerprint)) {
          skippedCount++;
          continue;
        }

        final values = thought.toMap()..remove('id');

        await transaction.insert('thoughts', values);

        existingFingerprints.add(fingerprint);
        importedCount++;
      }

      return BackupImportResult(
        importedCount: importedCount,
        skippedCount: skippedCount,
      );
    });
  }

  String _thoughtFingerprint(Thought thought) {
    return jsonEncode([
      thought.title,
      thought.content,
      thought.tag,
      thought.createdAt.toIso8601String(),
    ]);
  }
}

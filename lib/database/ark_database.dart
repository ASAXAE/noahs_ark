import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/thought.dart';

class ArkDatabase {
  ArkDatabase._();

  static final instance = ArkDatabase._();
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'noahs_ark_v1.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE thoughts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL,
          tag TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_favorite INTEGER NOT NULL DEFAULT 0
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE thoughts ADD COLUMN title TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
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
    await db.delete('thoughts', where: 'id = ?', whereArgs: [id]);
  }
}

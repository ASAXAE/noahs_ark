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
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE thoughts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          tag TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_favorite INTEGER NOT NULL DEFAULT 0
        )
      '''),
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
      where.add('content LIKE ?');
      args.add('%${query.trim()}%');
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

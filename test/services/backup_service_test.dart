import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/services/backup_service.dart';

void main() {
  group('BackupService.parseBackup', () {
    final service = BackupService();

    test('reads a valid version 1 backup', () {
      final jsonText = jsonEncode({
        'formatVersion': 1,
        'exportedAt': '2026-08-10T06:40:18.000Z',
        'thoughtCount': 1,
        'thoughts': [
          {
            'id': 7,
            'title': '测试备份',
            'content': '这是一条备份记录',
            'tag': '学习',
            'createdAt': '2026-08-10T06:30:00.000Z',
            'updatedAt': '2026-08-10T06:35:00.000Z',
            'isFavorite': true,
          },
        ],
      });

      final backup = service.parseBackup(jsonText);

      expect(backup.thoughts.length, 1);
      expect(backup.thoughts.first.title, '测试备份');
      expect(backup.thoughts.first.content, '这是一条备份记录');
      expect(backup.thoughts.first.tag, '学习');
      expect(backup.thoughts.first.isFavorite, true);
      expect(backup.exportedAt, DateTime.parse('2026-08-10T06:40:18.000Z'));
    });

    test('rejects an unsupported backup version', () {
      final jsonText = jsonEncode({
        'formatVersion': 99,
        'exportedAt': '2026-08-10T06:40:18.000Z',
        'thoughtCount': 0,
        'thoughts': [],
      });

      expect(
        () => service.parseBackup(jsonText),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a mismatched thought count', () {
      final jsonText = jsonEncode({
        'formatVersion': 1,
        'exportedAt': '2026-08-10T06:40:18.000Z',
        'thoughtCount': 2,
        'thoughts': [],
      });

      expect(
        () => service.parseBackup(jsonText),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

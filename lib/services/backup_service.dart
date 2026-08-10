import 'dart:convert';

import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../models/thought.dart';

class BackupPreview {
  const BackupPreview({required this.exportedAt, required this.thoughts});

  final DateTime exportedAt;
  final List<Thought> thoughts;
}

class BackupService {
  Future<void> exportThoughts(List<Thought> thoughts) async {
    final now = DateTime.now();

    final backup = {
      'formatVersion': 1,
      'exportedAt': now.toUtc().toIso8601String(),
      'thoughtCount': thoughts.length,
      'thoughts': thoughts.map((thought) => thought.toJson()).toList(),
    };

    const encoder = JsonEncoder.withIndent('  ');
    final jsonText = encoder.convert(backup);

    final fileName = _buildFileName(now);

    await SharePlus.instance.share(
      ShareParams(
        title: '导出诺亚方舟数据',
        text: '诺亚方舟本地记录备份',
        files: [
          XFile.fromData(utf8.encode(jsonText), mimeType: 'application/json'),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }

  Future<BackupPreview?> pickAndReadBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null) {
      return null;
    }

    final bytes = result.files.single.bytes;

    if (bytes == null) {
      throw const FormatException('无法读取所选文件');
    }

    final jsonText = utf8.decode(bytes, allowMalformed: false);

    return parseBackup(jsonText);
  }

  BackupPreview parseBackup(String jsonText) {
    final dynamic decoded;

    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const FormatException('所选文件不是有效的 JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份文件的最外层格式不正确');
    }

    if (decoded['formatVersion'] != 1) {
      throw const FormatException('不支持这个版本的备份文件');
    }

    final exportedAtValue = decoded['exportedAt'];

    if (exportedAtValue is! String) {
      throw const FormatException('备份文件缺少导出时间');
    }

    final exportedAt = DateTime.tryParse(exportedAtValue);

    if (exportedAt == null) {
      throw const FormatException('备份文件中的导出时间无效');
    }

    final rawThoughts = decoded['thoughts'];

    if (rawThoughts is! List) {
      throw const FormatException('备份文件缺少记录列表');
    }

    final thoughts = <Thought>[];

    for (final rawThought in rawThoughts) {
      if (rawThought is! Map<String, dynamic>) {
        throw const FormatException('备份文件中存在格式错误的记录');
      }

      try {
        thoughts.add(Thought.fromJson(rawThought));
      } catch (_) {
        throw const FormatException('备份文件中存在无法读取的记录');
      }
    }

    final declaredCount = decoded['thoughtCount'];

    if (declaredCount is! int || declaredCount != thoughts.length) {
      throw const FormatException('备份中的记录数量不一致');
    }

    return BackupPreview(exportedAt: exportedAt, thoughts: thoughts);
  }

  String _buildFileName(DateTime time) {
    String twoDigits(int value) {
      return value.toString().padLeft(2, '0');
    }

    return 'noahs_ark_backup_'
        '${time.year}'
        '${twoDigits(time.month)}'
        '${twoDigits(time.day)}_'
        '${twoDigits(time.hour)}'
        '${twoDigits(time.minute)}'
        '${twoDigits(time.second)}'
        '.json';
  }
}

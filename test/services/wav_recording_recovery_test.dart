import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/services/wav_recording_recovery.dart';

void main() {
  group('WavRecordingRecovery inspect', () {
    late Directory temporaryDirectory;
    const recovery = WavRecordingRecovery();

    File testFile(String name) {
      return File('${temporaryDirectory.path}${Platform.pathSeparator}$name');
    }

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'wav_recording_recovery_test_',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('reports a missing file', () async {
      final result = await recovery.inspect(testFile('missing.wav').path);

      expect(result, WavRecoveryStatus.missing);
    });

    test('reports an empty file', () async {
      final file = await testFile('empty.wav').create();

      final result = await recovery.inspect(file.path);

      expect(result, WavRecoveryStatus.empty);
    });

    test('recognizes an expected WAV header', () async {
      final bytes = List<int>.filled(45, 0)
        ..setRange(0, 4, 'RIFF'.codeUnits)
        ..setRange(8, 12, 'WAVE'.codeUnits)
        ..setRange(12, 16, 'fmt '.codeUnits)
        ..setRange(36, 40, 'data'.codeUnits)
        ..[44] = 1;

      final file = await testFile('valid.wav').writeAsBytes(bytes);

      final result = await recovery.inspect(file.path);

      expect(result, WavRecoveryStatus.valid);
    });

    test('recognizes zero-header PCM as recoverable', () async {
      final bytes = List<int>.filled(45, 0)..[44] = 1;
      final file = await testFile('recoverable.wav').writeAsBytes(bytes);

      final result = await recovery.inspect(file.path);

      expect(result, WavRecoveryStatus.recoverable);
    });

    test('refuses an unknown non-zero header', () async {
      final bytes = List<int>.filled(45, 0)..[0] = 1;
      final file = await testFile('unsupported.wav').writeAsBytes(bytes);

      final result = await recovery.inspect(file.path);

      expect(result, WavRecoveryStatus.unsupported);
    });

    test(
      'creates a valid recovery copy without changing the original',
      () async {
        final originalBytes = List<int>.filled(48, 0)
          ..[44] = 1
          ..[45] = 2
          ..[46] = 3
          ..[47] = 4;

        final originalFile = await testFile(
          'interrupted.wav',
        ).writeAsBytes(originalBytes);

        final recoveredPath = await recovery.recover(originalFile.path);

        expect(recoveredPath, isNotNull);
        expect(recoveredPath, isNot(originalFile.path));
        expect(await originalFile.readAsBytes(), originalBytes);

        final recoveredFile = File(recoveredPath!);
        final recoveredBytes = await recoveredFile.readAsBytes();

        expect(await recovery.inspect(recoveredPath), WavRecoveryStatus.valid);
        expect(recoveredBytes.length, originalBytes.length);
        expect(recoveredBytes.sublist(44), originalBytes.sublist(44));
      },
    );

    test('finds an unfinished WAV without reimporting it', () async {
      final validBytes = List<int>.filled(45, 0)
        ..setRange(0, 4, 'RIFF'.codeUnits)
        ..setRange(8, 12, 'WAVE'.codeUnits)
        ..setRange(12, 16, 'fmt '.codeUnits)
        ..setRange(36, 40, 'data'.codeUnits)
        ..[44] = 1;
      await testFile('finished.wav').writeAsBytes(validBytes);

      final unfinishedBytes = List<int>.filled(46, 0)
        ..[44] = 1
        ..[45] = 2;
      await testFile('unfinished.wav').writeAsBytes(unfinishedBytes);

      final recoveredPath = await recovery.recoverNewestUnfinishedIn(
        temporaryDirectory,
      );

      expect(recoveredPath, endsWith('unfinished_recovered.wav'));
      expect(await recovery.inspect(recoveredPath!), WavRecoveryStatus.valid);
      expect(
        await recovery.recoverNewestUnfinishedIn(temporaryDirectory),
        isNull,
      );
    });
  });
}

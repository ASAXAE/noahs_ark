import 'dart:io';
import 'dart:typed_data';

enum WavRecoveryStatus { missing, empty, valid, recoverable, unsupported }

class WavRecordingRecovery {
  const WavRecordingRecovery();

  static const int _headerLength = 44;
  static const int _sampleRate = 48000;
  static const int _channelCount = 1;
  static const int _bitsPerSample = 16;
  static const int _maximumUint32 = 0xFFFFFFFF;

  static const List<int> _riff = [0x52, 0x49, 0x46, 0x46];
  static const List<int> _wave = [0x57, 0x41, 0x56, 0x45];
  static const List<int> _format = [0x66, 0x6D, 0x74, 0x20];
  static const List<int> _data = [0x64, 0x61, 0x74, 0x61];

  Future<WavRecoveryStatus> inspect(String audioPath) async {
    final file = File(audioPath);

    if (!await file.exists()) {
      return WavRecoveryStatus.missing;
    }

    final fileLength = await file.length();

    if (fileLength <= _headerLength) {
      return WavRecoveryStatus.empty;
    }

    final input = await file.open(mode: FileMode.read);

    try {
      final header = await input.read(_headerLength);

      if (_hasExpectedHeader(header)) {
        return WavRecoveryStatus.valid;
      }

      if (header.length == _headerLength && header.every((byte) => byte == 0)) {
        return WavRecoveryStatus.recoverable;
      }

      return WavRecoveryStatus.unsupported;
    } finally {
      await input.close();
    }
  }

  Future<String?> recover(String audioPath) async {
    final status = await inspect(audioPath);

    if (status == WavRecoveryStatus.valid) {
      return audioPath;
    }

    if (status != WavRecoveryStatus.recoverable) {
      return null;
    }

    final sourceFile = File(audioPath);
    final fileLength = await sourceFile.length();
    final dataLength = fileLength - _headerLength;
    final blockAlign = _channelCount * _bitsPerSample ~/ 8;

    if (dataLength <= 0 ||
        dataLength % blockAlign != 0 ||
        fileLength - 8 > _maximumUint32 ||
        dataLength > _maximumUint32) {
      return null;
    }

    final recoveredPath = _recoveredPath(audioPath);
    final recoveredFile = File(recoveredPath);

    if (await recoveredFile.exists()) {
      final recoveredStatus = await inspect(recoveredPath);

      return recoveredStatus == WavRecoveryStatus.valid ? recoveredPath : null;
    }

    final partialFile = File('$recoveredPath.part');
    final output = partialFile.openWrite(mode: FileMode.write);

    try {
      output.add(_buildHeader(fileLength));
      await output.addStream(sourceFile.openRead(_headerLength));
      await output.flush();
    } finally {
      await output.close();
    }

    if (await partialFile.length() != fileLength ||
        await inspect(partialFile.path) != WavRecoveryStatus.valid) {
      return null;
    }

    await partialFile.rename(recoveredPath);
    return recoveredPath;
  }

  Future<String?> recoverNewestUnfinishedIn(Directory audioDirectory) async {
    if (!await audioDirectory.exists()) {
      return null;
    }

    final candidates = <({File file, DateTime modified})>[];

    await for (final entity in audioDirectory.list()) {
      if (entity is! File) {
        continue;
      }

      final lowerCasePath = entity.path.toLowerCase();

      if (!lowerCasePath.endsWith('.wav') ||
          lowerCasePath.endsWith('_recovered.wav')) {
        continue;
      }

      final stat = await entity.stat();
      candidates.add((file: entity, modified: stat.modified));
    }

    candidates.sort((left, right) => right.modified.compareTo(left.modified));

    for (final candidate in candidates) {
      if (await inspect(candidate.file.path) != WavRecoveryStatus.recoverable) {
        continue;
      }

      final recoveredPath = _recoveredPath(candidate.file.path);

      if (await File(recoveredPath).exists() &&
          await inspect(recoveredPath) == WavRecoveryStatus.valid) {
        continue;
      }

      final result = await recover(candidate.file.path);

      if (result != null) {
        return result;
      }
    }

    return null;
  }

  String _recoveredPath(String audioPath) {
    if (audioPath.toLowerCase().endsWith('.wav')) {
      return '${audioPath.substring(0, audioPath.length - 4)}_recovered.wav';
    }

    return '$audioPath.recovered.wav';
  }

  Uint8List _buildHeader(int fileLength) {
    final header = Uint8List(_headerLength);
    final values = ByteData.sublistView(header);
    final blockAlign = _channelCount * _bitsPerSample ~/ 8;
    final byteRate = _sampleRate * blockAlign;
    final dataLength = fileLength - _headerLength;

    header.setRange(0, 4, _riff);
    values.setUint32(4, fileLength - 8, Endian.little);
    header.setRange(8, 12, _wave);
    header.setRange(12, 16, _format);
    values.setUint32(16, 16, Endian.little);
    values.setUint16(20, 1, Endian.little);
    values.setUint16(22, _channelCount, Endian.little);
    values.setUint32(24, _sampleRate, Endian.little);
    values.setUint32(28, byteRate, Endian.little);
    values.setUint16(32, blockAlign, Endian.little);
    values.setUint16(34, _bitsPerSample, Endian.little);
    header.setRange(36, 40, _data);
    values.setUint32(40, dataLength, Endian.little);

    return header;
  }

  bool _hasExpectedHeader(List<int> header) {
    return header.length == _headerLength &&
        _matches(header, 0, _riff) &&
        _matches(header, 8, _wave) &&
        _matches(header, 12, _format) &&
        _matches(header, 36, _data);
  }

  bool _matches(List<int> bytes, int offset, List<int> expected) {
    for (var index = 0; index < expected.length; index++) {
      if (bytes[offset + index] != expected[index]) {
        return false;
      }
    }

    return true;
  }
}

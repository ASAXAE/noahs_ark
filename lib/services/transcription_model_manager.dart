import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TranscriptionModelFiles {
  const TranscriptionModelFiles({
    required this.modelPath,
    required this.tokensPath,
  });

  final String modelPath;
  final String tokensPath;
}

class TranscriptionModelManager {
  static const _modelUrl =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/'
      'resolve/main/model.int8.onnx?download=true';

  static const _tokensUrl =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/'
      'resolve/main/tokens.txt?download=true';

  static const _minimumModelBytes = 200 * 1024 * 1024;
  static const _minimumTokensBytes = 100 * 1024;

  TranscriptionModelManager({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _modelDirectoryName = 'sense_voice';

  Future<TranscriptionModelFiles> getLocalFiles() async {
    final documentDirectory = await getApplicationDocumentsDirectory();
    final modelDirectory = path.join(
      documentDirectory.path,
      'transcription_models',
      _modelDirectoryName,
    );

    return TranscriptionModelFiles(
      modelPath: path.join(modelDirectory, 'model.int8.onnx'),
      tokensPath: path.join(modelDirectory, 'tokens.txt'),
    );
  }

  Future<bool> isInstalled() async {
    final files = await getLocalFiles();
    final modelFile = File(files.modelPath);
    final tokensFile = File(files.tokensPath);

    if (!await modelFile.exists() || !await tokensFile.exists()) {
      return false;
    }

    return await modelFile.length() >= _minimumModelBytes &&
        await tokensFile.length() >= _minimumTokensBytes;
  }

  Future<TranscriptionModelFiles> download({
    void Function(double progress)? onProgress,
  }) async {
    final files = await getLocalFiles();
    final modelDirectory = Directory(path.dirname(files.modelPath));

    await modelDirectory.create(recursive: true);

    await _downloadFile(
      url: _modelUrl,
      destinationPath: files.modelPath,
      minimumBytes: _minimumModelBytes,
      onProgress: onProgress,
    );

    await _downloadFile(
      url: _tokensUrl,
      destinationPath: files.tokensPath,
      minimumBytes: _minimumTokensBytes,
    );

    onProgress?.call(1);
    return files;
  }

  Future<void> _downloadFile({
    required String url,
    required String destinationPath,
    required int minimumBytes,
    void Function(double progress)? onProgress,
  }) async {
    final destinationFile = File(destinationPath);

    if (await destinationFile.exists() &&
        await destinationFile.length() >= minimumBytes) {
      return;
    }

    final partialFile = File('$destinationPath.part');

    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '模型下载失败：HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final sink = partialFile.openWrite();
    final totalBytes = response.contentLength;
    var receivedBytes = 0;
    var completed = false;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes != null && totalBytes > 0) {
          onProgress?.call(receivedBytes / totalBytes);
        }
      }

      await sink.flush();
      completed = true;
    } finally {
      await sink.close();

      if (!completed && await partialFile.exists()) {
        await partialFile.delete();
      }
    }

    if (await partialFile.length() < minimumBytes) {
      await partialFile.delete();
      throw const FileSystemException('下载的模型文件不完整');
    }

    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }

    await partialFile.rename(destinationPath);
  }

  void dispose() {
    _client.close();
  }
}

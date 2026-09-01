import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'transcription_service.dart';

class SherpaTranscriptionService implements TranscriptionService {
  SherpaTranscriptionService({
    required this.modelPath,
    required this.tokensPath,
  });

  final String modelPath;
  final String tokensPath;

  sherpa.OfflineRecognizer? _recognizer;

  Future<void> _initialize() async {
    if (_recognizer != null) {
      return;
    }

    if (!await File(modelPath).exists()) {
      throw const TranscriptionException('找不到本地转写模型');
    }

    if (!await File(tokensPath).exists()) {
      throw const TranscriptionException('找不到本地转写词表');
    }

    await sherpa.initBindingsAsync();

    final model = sherpa.OfflineModelConfig(
      senseVoice: sherpa.OfflineSenseVoiceModelConfig(
        model: modelPath,
        language: 'auto',
        useInverseTextNormalization: true,
      ),
      tokens: tokensPath,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );

    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(model: model),
    );
  }

  @override
  Future<String> transcribeFile(String audioPath) async {
    final audioFile = File(audioPath);

    if (!await audioFile.exists()) {
      throw const TranscriptionException('找不到原始录音');
    }

    await _initialize();

    final wave = sherpa.readWave(audioPath);
    final stream = _recognizer!.createStream();

    try {
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);

      _recognizer!.decode(stream);

      final transcript = _recognizer!.getResult(stream).text.trim();

      if (transcript.isEmpty) {
        throw const TranscriptionException('没有识别到可用的语音内容');
      }

      return transcript;
    } finally {
      stream.free();
    }
  }

  void dispose() {
    _recognizer?.free();
    _recognizer = null;
  }
}

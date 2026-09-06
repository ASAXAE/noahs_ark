import 'dart:isolate';
import 'dart:async';

import 'sherpa_transcription_service.dart';
import 'transcription_service.dart';

class TranscriptionWorker implements TranscriptionService {
  TranscriptionWorker({required this.modelPath, required this.tokensPath});

  final String modelPath;
  final String tokensPath;

  final _ready = Completer<void>();
  final _exited = Completer<void>();

  ReceivePort? _events;
  SendPort? _commands;
  bool _started = false;
  bool _closed = false;
  Object? _failure;
  Future<void>? _disposeFuture;
  int _nextRequestId = 0;
  final Map<int, Completer<String>> _pending = {};

  @override
  Future<String> transcribeFile(String audioPath) async {
    await start();

    // 等待启动期间，Worker 可能已经被关闭或发生错误。
    if (_closed) {
      throw StateError('转写 Worker 已关闭');
    }

    if (_failure != null) {
      throw _failure!;
    }

    final id = _nextRequestId++;
    final result = Completer<String>();
    _pending[id] = result;

    try {
      _commands!.send({'type': 'transcribe', 'id': id, 'audioPath': audioPath});
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }

    return result.future;
  }

  Future<void> start() {
    if (_closed) {
      return Future.error(StateError('转写 Worker 已关闭'));
    }

    if (_failure != null) {
      return Future.error(_failure!);
    }

    if (!_started) {
      _started = true;
      _events = ReceivePort();
      _events!.listen(_handleMessage);
      unawaited(_launch());
    }

    return _ready.future;
  }

  Future<void> _launch() async {
    try {
      await Isolate.spawn(
        _transcriptionWorkerMain,
        _WorkerConfiguration(
          replyPort: _events!.sendPort,
          modelPath: modelPath,
          tokensPath: tokensPath,
        ),
        onError: _events!.sendPort,
        onExit: _events!.sendPort,
        errorsAreFatal: true,
        debugName: 'transcription_worker',
      );
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
      _markExited();
    }
  }

  void _handleMessage(dynamic message) {
    if (message == null) {
      _markExited();
      return;
    }

    if (message is List) {
      final error = RemoteError(message[0].toString(), message[1].toString());
      _fail(error, StackTrace.fromString(message[1].toString()));
      return;
    }

    final event = message as Map<String, Object?>;
    final type = event['type'];

    if (type == 'ready') {
      _commands = event['port'] as SendPort;

      if (!_ready.isCompleted) {
        _ready.complete();
      }
      return;
    }

    if (type != 'result' && type != 'error') return;

    final id = event['id'] as int;
    final result = _pending.remove(id);
    if (result == null) return;

    if (type == 'result') {
      result.complete(event['text'] as String);
    } else {
      result.completeError(
        TranscriptionException(event['message'] as String),
        StackTrace.fromString(event['stackTrace'] as String),
      );
    }
  }

  void _fail(Object error, StackTrace stackTrace) {
    _failure = error;

    if (!_ready.isCompleted) {
      _ready.completeError(error, stackTrace);
    }

    for (final result in _pending.values) {
      result.completeError(error, stackTrace);
    }
    _pending.clear();
  }

  void _markExited() {
    if (!_ready.isCompleted || !_closed || _pending.isNotEmpty) {
      _fail(_failure ?? StateError('转写 Worker 意外退出'), StackTrace.current);
    }

    if (!_exited.isCompleted) {
      _exited.complete();
    }

    _events?.close();
  }

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    _closed = true;

    if (!_started) return;

    try {
      await _ready.future;
    } catch (_) {
      await _exited.future;
      return;
    }

    if (!_exited.isCompleted) {
      _commands!.send({'type': 'dispose'});
    }

    await _exited.future;
  }
}

class _WorkerConfiguration {
  const _WorkerConfiguration({
    required this.replyPort,
    required this.modelPath,
    required this.tokensPath,
  });

  final SendPort replyPort;
  final String modelPath;
  final String tokensPath;
}

void _transcriptionWorkerMain(_WorkerConfiguration config) async {
  final commands = ReceivePort();

  //在工作Isolate 内创建， 识别器也将在这里初始化和缓存。
  final service = SherpaTranscriptionService(
    modelPath: config.modelPath,
    tokensPath: config.tokensPath,
  );

  config.replyPort.send({'type': 'ready', 'port': commands.sendPort});

  try {
    //按顺序处理，避免多个任务同时使用同一个识别器
    await for (final message in commands) {
      final command = message as Map<String, Object?>;

      if (command['type'] == 'dispose') {
        break;
      }

      final id = command['id'] as int;

      try {
        final audioPath = command['audioPath'] as String;

        final text = await service.transcribeFile(audioPath);

        config.replyPort.send({'type': 'result', 'id': id, 'text': text});
      } catch (error, stackTrace) {
        config.replyPort.send({
          'type': 'error',
          'id': id,
          'message': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
      }
    }
  } finally {
    service.dispose();
    commands.close();
  }
}

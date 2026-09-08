import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/view_models/capture_view_model.dart';

void main() {
  group('CaptureViewModel queue', () {
    test('runs drafts serially in FIFO order', () async {
      final firstCanFinish = Completer<void>();
      final startedDraftIds = <int>[];

      final viewModel = CaptureViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
      );
      addTearDown(viewModel.dispose);

      expect(viewModel.submitDraft(11), isTrue);
      expect(viewModel.activeDraftId, 11);

      expect(viewModel.submitDraft(22), isTrue);
      expect(viewModel.submitDraft(11), isFalse);
      expect(viewModel.submitDraft(0), isFalse);

      expect(viewModel.activeDraftId, 11);
      expect(viewModel.queuedDraftIds, [22]);
      expect(viewModel.queuePositionFor(22), 1);
      expect(() => viewModel.queuedDraftIds.add(33), throwsUnsupportedError);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11, 22]);
      expect(viewModel.activeDraftId, isNull);
      expect(viewModel.queuedDraftIds, isEmpty);
    });

    test('cancels a queued draft before it starts', () async {
      final firstCanFinish = Completer<void>();
      final startedDraftIds = <int>[];

      final viewModel = CaptureViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
      );
      addTearDown(viewModel.dispose);

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);

      expect(viewModel.cancelQueuedDraft(22), isTrue);
      expect(viewModel.cancelQueuedDraft(22), isFalse);
      expect(viewModel.queuedDraftIds, isEmpty);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11]);
    });

    test('continues with the next draft after a failure', () async {
      final startedDraftIds = <int>[];

      final viewModel = CaptureViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            throw StateError('simulated failure');
          }
        },
      );
      addTearDown(viewModel.dispose);

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);

      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11, 22]);
      expect(viewModel.activeDraftId, isNull);
      expect(viewModel.queuedDraftIds, isEmpty);
    });
    test('notifies listeners for every visible queue change', () async {
      final firstCanFinish = Completer<void>();
      final snapshots = <String>[];

      final viewModel = CaptureViewModel(
        runTranscription: (draftId) async {
          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
      );
      addTearDown(viewModel.dispose);

      viewModel.addListener(() {
        snapshots.add(
          '${viewModel.activeDraftId}:'
          '${viewModel.queuedDraftIds.join(',')}',
        );
      });

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);
      viewModel.cancelQueuedDraft(22);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(snapshots, ['null:11', '11:', '11:22', '11:', 'null:']);
    });

    test('notifies once after the whole queue drains', () async {
      final firstCanFinish = Completer<void>();
      final startedDraftIds = <int>[];
      var queueDrainedCount = 0;

      final viewModel = CaptureViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
        onQueueDrained: () {
          queueDrainedCount++;
        },
      );
      addTearDown(viewModel.dispose);

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);

      expect(queueDrainedCount, 0);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11, 22]);
      expect(queueDrainedCount, 1);
    });
  });
}

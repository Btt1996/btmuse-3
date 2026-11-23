import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/download_task.dart';
import '../../data/models/x2_result.dart';
import '../../data/repositories/history_repository.dart';
import '../x2/x2_acquisition_engine.dart';

class DownloadManagerNotifier extends StateNotifier<List<DownloadTask>> {
  final HistoryRepository _historyRepo;
  final X2AcquisitionEngine _acquisitionEngine;
  final void Function() _onLibraryChanged;

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, X2Result> _queuedPayloads = {};
  static const _uuid = Uuid();

  DownloadManagerNotifier(
    this._historyRepo,
    this._acquisitionEngine,
    this._onLibraryChanged,
  ) : super([]) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    state = await _historyRepo.getDownloadHistory();
    // F10 (Phase 4): rehydrate the in-memory payloads from the
    // persisted rows, so a failed task restored after a restart is
    // retryable in this session too. Rows predating payload
    // persistence (schema v5) have no payload and stay non-retryable
    // — the UI keeps their Retry button disabled with an honest
    // tooltip. Corrupt stored JSON decodes to null and is skipped.
    for (final task in state) {
      final payload = task.payload;
      if (payload != null) _queuedPayloads[task.id] = payload;
    }
  }

  Future<void> enqueueX2Download(X2Result result) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final taskId = _uuid.v4();
    final initialTask = DownloadTask(
      id: taskId,
      title: result.title,
      artist: result.artist,
      providerId: result.providerId,
      sourceUrl: result.audioUrl ?? result.externalPageUrl ?? '',
      artworkUrl: result.artworkUrl,
      stage: DownloadStage.waiting,
      progress: 0.0,
      // F10: persist the payload with the task row so retry survives
      // a restart. _updateTask(persist: true) re-writes this row on
      // every stage change via copyWith, which carries payloadJson.
      payloadJson: jsonEncode(result.toJson()),
      createdAtMs: now,
      updatedAtMs: now,
    );

    _queuedPayloads[taskId] = result;
    state = [initialTask, ...state];
    await _historyRepo.upsertTask(initialTask);

    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      final track = await _acquisitionEngine.acquireTrack(
        result: result,
        cancelToken: cancelToken,
        onStageUpdate: (stage, progress, received, total) {
          _updateTask(
            taskId,
            (t) => t.copyWith(
              stage: stage,
              progress: progress,
              receivedBytes: received,
              totalBytes: total,
              updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        },
      );

      _updateTask(
        taskId,
        (t) => t.copyWith(
          stage: DownloadStage.completed,
          progress: 1.0,
          importedTrackId: track.id,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persist: true,
      );
      _onLibraryChanged();
    } on DioException catch (e) {
      final isCancelled = CancelToken.isCancel(e);
      _updateTask(
        taskId,
        (t) => t.copyWith(
          stage: isCancelled ? DownloadStage.cancelled : DownloadStage.failed,
          errorMessage: isCancelled ? 'Download cancelled.' : (e.message ?? 'Download failed.'),
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persist: true,
      );
    } catch (e) {
      _updateTask(
        taskId,
        (t) => t.copyWith(
          stage: DownloadStage.failed,
          errorMessage: e.toString(),
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persist: true,
      );
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  /// Records a download that ran OUTSIDE the manager as a finished row
  /// in Downloads history, so it appears alongside queued downloads.
  ///
  /// The only such caller is the self-hosted YouTube bridge import in
  /// ImportCenter (`_importViaBridge`): it drives its own stage/progress
  /// UI and CancelToken and must pass `allowPrivateHost: true` to the
  /// acquisition engine (the bridge URL is the user's own host, often a
  /// LAN address), so it cannot go through [enqueueX2Download], which
  /// owns its token, swallows errors into the task row, and has no
  /// `allowPrivateHost` parameter. Routing the bridge through the
  /// manager would also orphan the sheet's Cancel button (which drives
  /// `_bridgeCancelToken`) and its `_bridgeError` handling.
  ///
  /// No payload is persisted: a bridge result points at the user's own
  /// bridge host, which [enqueueX2Download] must not re-fetch without
  /// the bridge's `allowPrivateHost` verification, so the row is not
  /// retryable from history ([canRetry] stays false) — re-import from
  /// the Import Center instead. The row is prepended newest-first and
  /// persisted with [HistoryRepository.upsertTask], like every other
  /// task. Never throws: history recording must not fail the import
  /// that already succeeded (or the error path that already reported).
  /// Does not call the library-changed callback: the bridge caller
  /// already invalidates the library providers itself.
  Future<void> recordExternalDownload({
    required X2Result result,
    required String? importedTrackId,
    String? errorMessage,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final task = DownloadTask(
      id: _uuid.v4(),
      title: result.title,
      artist: result.artist,
      providerId: result.providerId,
      sourceUrl: result.audioUrl ?? result.externalPageUrl ?? '',
      artworkUrl: result.artworkUrl,
      stage:
          errorMessage == null ? DownloadStage.completed : DownloadStage.failed,
      progress: errorMessage == null ? 1.0 : 0.0,
      importedTrackId: importedTrackId,
      errorMessage: errorMessage,
      createdAtMs: now,
      updatedAtMs: now,
    );
    state = [task, ...state];
    try {
      await _historyRepo.upsertTask(task);
    } catch (_) {
      // History is best-effort: the import already happened (or its
      // error is already shown); never fail the caller over storage.
    }
  }

  void cancelTask(String taskId) {
    final token = _cancelTokens[taskId];
    if (token != null && !token.isCancelled) {
      token.cancel('Cancelled by user');
    }
  }

  /// Retries [taskId] from its payload — the in-memory copy when this
  /// session queued it, otherwise the payload persisted on the task
  /// row (schema v5, rehydrated by [loadHistory]). Throws [StateError]
  /// when no payload exists at all: Retry is only enabled when
  /// [canRetry] is true, so reaching this without a payload is a
  /// programming error, and failing loudly beats the old silent no-op.
  /// (A retry enqueues a fresh task, as before; the failed row stays
  /// in history until the user clears it.)
  Future<void> retryTask(String taskId) async {
    var payload = _queuedPayloads[taskId];
    if (payload == null) {
      for (final task in state) {
        if (task.id == taskId) {
          payload = task.payload;
          break;
        }
      }
    }
    if (payload == null) {
      throw StateError(
        'Cannot retry download $taskId: its original request was not '
        'saved (queued before payload persistence). Re-queue it from '
        'its source instead.',
      );
    }
    await enqueueX2Download(payload);
  }

  /// True when this task's download payload is still held in memory
  /// (i.e. the download was queued in this app session) or was
  /// restored from its persisted task row by [loadHistory] (schema v5
  /// `payload_json`). Tasks queued before payload persistence, or
  /// whose stored JSON is corrupt, have no payload, so their Retry
  /// button must be disabled — retrying them would silently do
  /// nothing. The UI gates on this; [retryTask] throws instead of
  /// silently doing nothing if it is ever called without a payload.
  bool canRetry(String taskId) => _queuedPayloads.containsKey(taskId);

  Future<void> clearFinished() async {
    await _historyRepo.clearFinishedHistory();
    state = state.where((t) => t.isActive).toList();
  }

  void _updateTask(
    String taskId,
    DownloadTask Function(DownloadTask current) transform, {
    bool persist = false,
  }) {
    final idx = state.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final updated = transform(state[idx]);
    final nextList = [...state];
    nextList[idx] = updated;
    state = nextList;
    if (persist) {
      _historyRepo.upsertTask(updated);
    }
  }
}

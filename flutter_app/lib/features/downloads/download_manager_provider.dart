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

  void cancelTask(String taskId) {
    final token = _cancelTokens[taskId];
    if (token != null && !token.isCancelled) {
      token.cancel('Cancelled by user');
    }
  }

  Future<void> retryTask(String taskId) async {
    final payload = _queuedPayloads[taskId];
    if (payload != null) {
      await enqueueX2Download(payload);
    }
  }

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

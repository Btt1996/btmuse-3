import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/models/download_task.dart';

class DownloadHistoryScreen extends ConsumerWidget {
  const DownloadHistoryScreen({super.key});

  String _stageText(DownloadTask task) => switch (task.stage) {
        DownloadStage.waiting => 'Waiting in queue',
        DownloadStage.searching => 'Searching sources',
        DownloadStage.resolving => 'Verifying stream',
        DownloadStage.downloading =>
          'Downloading ${(task.progress * 100).round()}%',
        DownloadStage.processing => 'Validating audio header & SHA-256',
        DownloadStage.importing => 'Importing into offline vault',
        DownloadStage.completed => 'Completed',
        DownloadStage.failed => 'Failed',
        DownloadStage.cancelled => 'Cancelled',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadManagerProvider);
    final notifier = ref.read(downloadManagerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads & History'),
        actions: [
          if (tasks.any((t) => !t.isActive))
            TextButton(
              onPressed: () => notifier.clearFinished(),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: tasks.isEmpty
          ? Center(
              child: Text(
                'No acquisition jobs recorded yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final task = tasks[idx];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: BttColors.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BttColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${task.artist} · ${task.providerId} · ${_stageText(task)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          if (task.isActive)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: BttColors.warning),
                              onPressed: () => notifier.cancelTask(task.id),
                            )
                          else if (task.stage == DownloadStage.failed ||
                              task.stage == DownloadStage.cancelled)
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, color: BttColors.cyanAccent),
                              onPressed: () => notifier.retryTask(task.id),
                            )
                          else
                            const Icon(Icons.check_circle_rounded, color: BttColors.greenAccent),
                        ],
                      ),
                      if (task.isActive) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: task.progress),
                      ],
                      if (task.errorMessage != null && task.stage == DownloadStage.failed) ...[
                        const SizedBox(height: 6),
                        Text(
                          task.errorMessage!,
                          style: const TextStyle(color: BttColors.danger, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

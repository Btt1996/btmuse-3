import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/library_repository.dart';

/// Storage dashboard: per-source usage, duplicate scan grouped by
/// SHA-256, and confirmed-only cleanup.
///
/// Design notes (borrowed from the Swift LibraryStore, adapted to the
/// stronger guarantee here):
/// * Swift groups duplicates by title+artist+duration and its
///   `removeDuplicates` picks losers itself. Here groups are by SHA-256
///   content hash only, and deletion never happens without the user
///   confirming — the repository only deletes ids the user explicitly
///   chose, keeping exactly one copy per group.
/// * Deletion always removes the file + DB row together
///   ([LibraryRepository.deleteTrack]); there is no file-only or
///   row-only delete path in this screen.
/// * Free space is reported as unavailable rather than guessed: no
///   disk-space plugin is currently a dependency. iOS Settings >
///   General > iPhone Storage shows device free space.
class StorageDashboardScreen extends ConsumerStatefulWidget {
  const StorageDashboardScreen({super.key});

  @override
  ConsumerState<StorageDashboardScreen> createState() => _StorageDashboardScreenState();
}

class _StorageDashboardScreenState extends ConsumerState<StorageDashboardScreen> {
  bool _scanning = false;
  List<DuplicateGroup>? _groups;
  String? _scanError;

  /// Keeper choice per group (sha256 -> track id). Defaults to each
  /// group's suggested keeper (most-played, then newest) once scanned.
  final Map<String, String> _keepers = {};

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Future<void> _runScan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final groups = await ref.read(libraryRepositoryProvider).findDuplicates();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _keepers
          ..clear()
          ..addEntries(
            groups.map((g) => MapEntry(g.sha256, g.suggestedKeeper.id)),
          );
      });
    } catch (e) {
      if (mounted) setState(() => _scanError = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _confirmAndDeleteGroup(DuplicateGroup group) async {
    final keeperId = _keepers[group.sha256] ?? group.suggestedKeeper.id;
    final keeper = group.tracks.firstWhere(
      (t) => t.id == keeperId,
      orElse: () => group.suggestedKeeper,
    );
    final losers = group.tracks.where((t) => t.id != keeper.id).toList();
    if (losers.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete duplicate copies?'),
        content: Text(
          'This keeps "${keeper.title}" by ${keeper.artist} and permanently '
          'deletes ${losers.length} duplicate cop${losers.length == 1 ? 'y' : 'ies'} '
          '(${formatBytes(group.reclaimableBytes)} freed). '
          'The audio files and their library entries are removed together. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BttColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete duplicates'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removed = await ref
        .read(libraryRepositoryProvider)
        .deleteDuplicateCopies(group, keepTrackId: keeper.id);
    ref.invalidate(libraryTracksProvider);
    ref.invalidate(storageStatsProvider);
    await _runScan();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $removed duplicate cop${removed == 1 ? 'y' : 'ies'}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(storageStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage & Duplicates'),
        actions: [
          IconButton(
            tooltip: 'Rescan for duplicates',
            onPressed: _scanning ? null : _runScan,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          statsAsync.when(
            data: (stats) => _StorageSummaryCard(stats: stats),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => _ErrorCard(message: 'Could not load storage stats: $err'),
          ),
          const SizedBox(height: 18),
          Text(
            'DUPLICATES BY CONTENT HASH',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: BttColors.textSecondary,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 8),
          if (_scanning && _groups == null)
            const Center(child: CircularProgressIndicator())
          else if (_scanError != null)
            _ErrorCard(message: 'Duplicate scan failed: $_scanError')
          else if (_groups != null && _groups!.isEmpty)
            const _EmptyDuplicatesCard()
          else if (_groups != null)
            ..._groups!.map(
              (g) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DuplicateGroupCard(
                  group: g,
                  keeperId: _keepers[g.sha256] ?? g.suggestedKeeper.id,
                  onKeeperChanged: (id) => setState(() => _keepers[g.sha256] = id),
                  onDelete: () => _confirmAndDeleteGroup(g),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StorageSummaryCard extends StatelessWidget {
  final LibraryStorageStats stats;
  const _StorageSummaryCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final localBytes = stats.bytesBySource['local_file'] ?? 0;
    final localCount = stats.trackCountBySource['local_file'] ?? 0;
    final telegramBytes = stats.bytesBySource['telegram'] ?? 0;
    final telegramCount = stats.trackCountBySource['telegram'] ?? 0;
    // Every other source_provider value is an X2 acquisition provider
    // (audius, deezer, direct_url, ...): group them as X2 downloads.
    var x2Bytes = 0;
    var x2Count = 0;
    stats.bytesBySource.forEach((source, bytes) {
      if (source != 'local_file' && source != 'telegram') {
        x2Bytes += bytes;
        x2Count += stats.trackCountBySource[source] ?? 0;
      }
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BttColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${stats.trackCount} tracks',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                formatBytes(stats.totalBytes),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: BttColors.accentPink,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SourceRow(
            label: 'Local files',
            count: localCount,
            bytes: localBytes,
            totalBytes: stats.totalBytes,
            color: BttColors.accentPink,
          ),
          const SizedBox(height: 8),
          _SourceRow(
            label: 'Telegram',
            count: telegramCount,
            bytes: telegramBytes,
            totalBytes: stats.totalBytes,
            color: BttColors.accentMagenta,
          ),
          const SizedBox(height: 8),
          _SourceRow(
            label: 'X2 downloads',
            count: x2Count,
            bytes: x2Bytes,
            totalBytes: stats.totalBytes,
            color: BttColors.accentViolet,
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Icon(Icons.sd_storage_rounded, size: 16, color: BttColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free space: not available in-app (no disk-space plugin). '
                  'Check iOS Settings > General > iPhone Storage.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
          if (stats.missingFilesCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: BttColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${stats.missingFilesCount} library entr${stats.missingFilesCount == 1 ? 'y' : 'ies'} '
                    'point${stats.missingFilesCount == 1 ? 's' : ''} to a file that is no longer on disk.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: BttColors.warning,
                        ),
                  ),
                ),
              ],
            ),
          ],
          if (stats.duplicateGroupsCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${stats.duplicateGroupsCount} duplicate group${stats.duplicateGroupsCount == 1 ? '' : 's'} · '
              '${formatBytes(stats.duplicateBytesReclaimable)} reclaimable',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: BttColors.warning,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final String label;
  final int count;
  final int bytes;
  final int totalBytes;
  final Color color;

  const _SourceRow({
    required this.label,
    required this.count,
    required this.bytes,
    required this.totalBytes,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = totalBytes > 0 ? bytes / totalBytes : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              '$count track${count == 1 ? '' : 's'} · ${formatBytes(bytes)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: fraction,
          backgroundColor: BttColors.borderSubtle,
          color: color,
        ),
      ],
    );
  }
}

class _EmptyDuplicatesCard extends StatelessWidget {
  const _EmptyDuplicatesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BttColors.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: BttColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No duplicates found. Every track has a unique content hash.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BttColors.borderSubtle),
      ),
      child: Text(message, style: const TextStyle(color: BttColors.danger, fontSize: 13)),
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  final DuplicateGroup group;
  final String keeperId;
  final ValueChanged<String> onKeeperChanged;
  final VoidCallback onDelete;

  const _DuplicateGroupCard({
    required this.group,
    required this.keeperId,
    required this.onKeeperChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final shortHash = group.sha256.length > 12 ? group.sha256.substring(0, 12) : group.sha256;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BttColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${group.count} copies · ${formatBytes(group.totalBytes)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'SHA-256 $shortHash…',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Deleting the extras frees ${formatBytes(group.reclaimableBytes)}. '
            'Pick the copy to keep — the rest are deleted only after you confirm.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...group.tracks.map((t) => _GroupMemberTile(
                track: t,
                isKeeper: t.id == keeperId,
                onSelectKeeper: () => onKeeperChanged(t.id),
              )),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: BttColors.danger),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text('Delete ${group.count - 1} duplicate${group.count - 1 == 1 ? '' : 's'}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupMemberTile extends StatelessWidget {
  final Track track;
  final bool isKeeper;
  final VoidCallback onSelectKeeper;

  const _GroupMemberTile({
    required this.track,
    required this.isKeeper,
    required this.onSelectKeeper,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelectKeeper,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: isKeeper,
              onChanged: (_) => onSelectKeeper(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${track.title} — ${track.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
                  ),
                  Text(
                    '${track.sourceProvider} · ${formatBytes(track.fileSizeBytes)}'
                    ' · played ${track.playCount}x'
                    '${isKeeper ? ' · KEEP' : ''}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isKeeper ? BttColors.success : null,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

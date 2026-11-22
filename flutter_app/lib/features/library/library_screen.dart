import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/track_tile.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/features/library/metadata_editor_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _searchQuery = '';
  String _segment = 'Tracks'; // Tracks, Favorites, Artists, Albums
  bool _importing = false;

  Future<void> _importLocalFiles() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      final repo = ref.read(libraryRepositoryProvider);
      var importedCount = 0;
      final skipped = <String>[];
      for (final file in result.files) {
        final path = file.path;
        if (path == null) continue;
        final rawTitle = p.basenameWithoutExtension(file.name);
        // Per-file catch: since b690ae1 a duplicate throws
        // DuplicateTrackFailure instead of silently "succeeding", so one
        // duplicate must not abort the rest of the batch (same pattern as
        // the Import Center). Skips are reported in the summary snackbar.
        try {
          await repo.importFileIntoLibrary(
            sourceFile: File(path),
            rawTitle: rawTitle,
            sourceProvider: 'local_file',
          );
          importedCount++;
        } catch (e) {
          skipped.add('${file.name}: $e');
        }
      }

      ref.invalidate(libraryTracksProvider);
      ref.invalidate(storageStatsProvider);

      if (mounted) {
        final summary = skipped.isEmpty
            ? 'Imported $importedCount audio file(s) into library.'
            : 'Imported $importedCount of ${result.files.length} audio file(s) · ${skipped.length} skipped — ${skipped.first}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(summary)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showTrackOptions(Track track) {
    final playlistsAsync = ref.read(playlistsProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BttColors.bgElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: BttColors.cyanAccent),
              title: const Text('Edit Metadata'),
              onTap: () {
                Navigator.of(ctx).pop();
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: BttColors.bgElevated,
                  builder: (_) => MetadataEditorSheet(
                    track: track,
                    onSave: (updated) async {
                      await ref.read(libraryRepositoryProvider).updateTrackMetadata(updated);
                      ref.invalidate(libraryTracksProvider);
                    },
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: BttColors.goldAccent),
              title: const Text('Add to Playlist'),
              onTap: () {
                Navigator.of(ctx).pop();
                final playlists = playlistsAsync.valueOrNull ?? [];
                if (playlists.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Create a playlist in the Playlists tab first.')),
                  );
                  return;
                }
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: BttColors.bgElevated,
                  builder: (pCtx) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: playlists
                          .map(
                            (pl) => ListTile(
                              title: Text(pl.name),
                              subtitle: Text('${pl.trackIds.length} tracks'),
                              onTap: () async {
                                await ref
                                    .read(playlistRepositoryProvider)
                                    .addTrackToPlaylist(pl.id, track.id);
                                ref.invalidate(playlistsProvider);
                                if (pCtx.mounted) Navigator.of(pCtx).pop();
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: BttColors.danger),
              title: const Text('Delete Offline File', style: TextStyle(color: BttColors.danger)),
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref.read(libraryRepositoryProvider).deleteTrack(track);
                ref.invalidate(libraryTracksProvider);
                ref.invalidate(storageStatsProvider);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    final statsAsync = ref.watch(storageStatsProvider);
    final handler = ref.watch(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Library'),
        actions: [
          IconButton(
            tooltip: 'Import Local Audio',
            onPressed: _importing ? null : _importLocalFiles,
            icon: _importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_upload_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(
                hintText: 'Filter local tracks, artists, or albums',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: ['Tracks', 'Favorites', 'Artists', 'Albums'].map((label) {
                final selected = _segment == label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() => _segment = label),
                    selectedColor: BttColors.cyanAccent.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: selected ? BttColors.cyanAccent : BttColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          statsAsync.when(
            data: (stats) {
              final mb = (stats.totalBytes / (1024 * 1024)).toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${stats.trackCount} tracks · $mb MB on disk',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (stats.duplicateGroupsCount > 0)
                      Text(
                        '${stats.duplicateGroupsCount} duplicate alert(s)',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: BttColors.goldAccent,
                            ),
                      ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Expanded(
            child: tracksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load library: $err')),
              data: (allTracks) {
                final filtered = allTracks.where((t) {
                  if (_segment == 'Favorites' && !t.isFavorite) return false;
                  if (_searchQuery.trim().isEmpty) return true;
                  final q = _searchQuery.toLowerCase();
                  return t.title.toLowerCase().contains(q) ||
                      t.artist.toLowerCase().contains(q) ||
                      t.album.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.music_off_rounded, size: 48, color: BttColors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            allTracks.isEmpty ? 'No offline tracks yet' : 'No matching tracks',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _importLocalFiles,
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Import From iOS Files'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (_segment == 'Artists' || _segment == 'Albums') {
                  final grouped = <String, List<Track>>{};
                  for (final t in filtered) {
                    final key = _segment == 'Artists' ? t.artist : t.album;
                    grouped.putIfAbsent(key, () => []).add(t);
                  }
                  final keys = grouped.keys.toList()..sort();
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    itemCount: keys.length,
                    itemBuilder: (context, idx) {
                      final name = keys[idx];
                      final groupTracks = grouped[name]!;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: BttColors.bgCard,
                          child: Icon(
                            _segment == 'Artists' ? Icons.person_rounded : Icons.album_rounded,
                            color: BttColors.cyanAccent,
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text('${groupTracks.length} track(s)'),
                        trailing: const Icon(Icons.play_arrow_rounded),
                        onTap: () => handler.setTrackQueueAndPlay(groupTracks),
                      );
                    },
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final t = filtered[idx];
                    return TrackTile(
                      track: t,
                      isCurrent: handler.currentTrack?.id == t.id,
                      onTap: () => handler.setTrackQueueAndPlay(filtered, initialIndex: idx),
                      onFavoriteToggle: () async {
                        await ref
                            .read(libraryRepositoryProvider)
                            .toggleFavorite(t.id, !t.isFavorite);
                        ref.invalidate(libraryTracksProvider);
                      },
                      onMorePressed: () => _showTrackOptions(t),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

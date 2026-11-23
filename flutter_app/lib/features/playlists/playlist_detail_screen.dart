import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/track_tile.dart';
import 'package:btmu/data/models/playlist.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/playlist_repository.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  /// Exports this playlist through the system save dialog — the same
  /// `FilePicker.saveFile` pattern `BackupScreen` uses (`share_plus`
  /// is not a dependency). Only tracks still in the library are
  /// exported: playlist entries whose rows are gone are left out and
  /// the snackbar says so instead of silently writing a shorter list.
  /// JSON is the faithful format (SHA-256 included); M3U is the lossy
  /// interchange format (artist/title only).
  Future<void> _export(
    BuildContext context,
    Playlist playlist,
    List<Track> tracks,
    String format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final isJson = format == 'json';
      final content = isJson
          ? PlaylistRepository.exportPlaylistJson(
              playlist: playlist,
              tracks: tracks,
            )
          : PlaylistRepository.exportPlaylistM3u(
              playlist: playlist,
              tracks: tracks,
            );
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save playlist export',
        fileName: isJson
            ? PlaylistRepository.exportFileNameJson(playlist)
            : PlaylistRepository.exportFileNameM3u(playlist),
        type: FileType.custom,
        allowedExtensions: [if (isJson) 'json' else 'm3u'],
        bytes: utf8.encode(content),
      );
      if (!context.mounted) return;
      final skipped = playlist.trackIds.length - tracks.length;
      if (savedPath == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Export cancelled — nothing was saved.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Playlist exported (${tracks.length} track${tracks.length == 1 ? '' : 's'})'
              '${skipped > 0 ? ' — $skipped ${skipped == 1 ? 'entry is' : 'entries are'} no longer in the library and ${skipped == 1 ? 'was' : 'were'} left out' : ''}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTracks = ref.watch(libraryTracksProvider).valueOrNull ?? [];
    final playlists = ref.watch(playlistsProvider).valueOrNull ?? [];
    final livePlaylist = playlists.firstWhere(
      (p) => p.id == playlist.id,
      orElse: () => playlist,
    );

    final trackMap = {for (final t in allTracks) t.id: t};
    final tracks = livePlaylist.trackIds
        .map((id) => trackMap[id])
        .whereType<Track>()
        .toList();
    final handler = ref.watch(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(livePlaylist.name),
        actions: [
          if (tracks.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Export playlist',
              icon: const Icon(Icons.ios_share_rounded, color: BttColors.accentViolet),
              onSelected: (format) =>
                  _export(context, livePlaylist, tracks, format),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'json',
                  child: Text('Export as JSON'),
                ),
                PopupMenuItem(
                  value: 'm3u',
                  child: Text('Export as M3U'),
                ),
              ],
            ),
          if (tracks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded, color: BttColors.accentPink),
              onPressed: () => handler.setTrackQueueAndPlay(tracks),
            ),
        ],
      ),
      body: tracks.isEmpty
          ? Center(
              child: Text(
                'No tracks in this playlist yet.\nAdd tracks from the Music Library menu.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
              itemCount: tracks.length,
              itemBuilder: (context, idx) {
                final t = tracks[idx];
                return TrackTile(
                  track: t,
                  isCurrent: handler.currentTrack?.id == t.id,
                  onTap: () => handler.setTrackQueueAndPlay(tracks, initialIndex: idx),
                  onMorePressed: () async {
                    await ref
                        .read(playlistRepositoryProvider)
                        .removeTrackFromPlaylist(livePlaylist.id, t.id);
                    ref.invalidate(playlistsProvider);
                  },
                );
              },
            ),
    );
  }
}

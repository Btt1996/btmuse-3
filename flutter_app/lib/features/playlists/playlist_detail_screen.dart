import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/track_tile.dart';
import 'package:btmu/data/models/playlist.dart';
import 'package:btmu/data/models/track.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

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
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded, color: BttColors.cyanAccent),
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

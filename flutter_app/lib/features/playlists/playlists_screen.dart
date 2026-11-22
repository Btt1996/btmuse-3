import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/btt_page_route.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/features/playlists/playlist_detail_screen.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BttColors.bgElevated,
        title: const Text('New Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Playlist Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await ref.read(playlistRepositoryProvider).createPlaylist(
                    name: name,
                    description: descCtrl.text.trim(),
                  );
              ref.invalidate(playlistsProvider);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: BttColors.cyanAccent),
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (playlists) {
          if (playlists.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.queue_music_rounded, size: 52, color: BttColors.textMuted),
                  const SizedBox(height: 12),
                  Text('No playlists yet', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _showCreateDialog(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create Playlist'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final pl = playlists[idx];
              return ListTile(
                tileColor: BttColors.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: BttColors.borderSubtle),
                ),
                leading: const CircleAvatar(
                  backgroundColor: BttColors.bgCardHighlight,
                  child: Icon(Icons.queue_music_rounded, color: BttColors.goldAccent),
                ),
                title: Text(pl.name),
                subtitle: Text('${pl.trackIds.length} track(s)'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: BttColors.textMuted),
                  onPressed: () async {
                    await ref.read(playlistRepositoryProvider).deletePlaylist(pl.id);
                    ref.invalidate(playlistsProvider);
                  },
                ),
                onTap: () {
                  Navigator.of(context).push(
                    BttPageRoute<void>(
                      builder: (_) => PlaylistDetailScreen(playlist: pl),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

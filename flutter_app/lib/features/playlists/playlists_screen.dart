import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/btt_page_route.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/repositories/playlist_repository.dart';
import 'package:btmu/features/playlists/playlist_detail_screen.dart';

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  bool _busy = false;

  Future<void> _showCreateDialog() async {
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

  /// Imports a playlist export file (`.json` or `.m3u`/`.m3u8`) picked
  /// through the system picker — same `FilePicker.pickFiles` pattern
  /// `BackupScreen` uses for backup import. The result summary is
  /// always shown: added / duplicates / not-in-library / skipped, so no
  /// entry is ever silently dropped. A name that already exists is kept
  /// as a new playlist with an " (imported)" suffix — existing
  /// playlists are never overwritten.
  Future<void> _importPlaylist() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'm3u', 'm3u8'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null) {
        throw const PlaylistFormatException(
          'Could not read the selected playlist file.',
        );
      }
      final content = utf8.decode(bytes);
      final extension = (picked.extension ?? '').toLowerCase();
      final libraryTracks =
          await ref.read(libraryRepositoryProvider).getAllTracks();
      final repo = ref.read(playlistRepositoryProvider);
      final importResult = extension == 'json'
          ? await repo.importPlaylistJson(
              content,
              libraryTracks: libraryTracks,
            )
          : await repo.importPlaylistM3u(
              content,
              libraryTracks: libraryTracks,
              fallbackName: picked.name.replaceAll(
                RegExp(r'\.(json|m3u8?)$', caseSensitive: false),
                '',
              ),
            );
      ref.invalidate(playlistsProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: BttColors.bgElevated,
          title: const Text('Playlist imported'),
          content: SingleChildScrollView(
            child: Text(importResult.summary),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on PlaylistFormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import playlist: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import playlist: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            tooltip: 'Import playlist (.json or .m3u)',
            icon: const Icon(Icons.file_download_rounded, color: BttColors.accentViolet),
            onPressed: _busy ? null : _importPlaylist,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, color: BttColors.accentPink),
            onPressed: _busy ? null : _showCreateDialog,
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
                    onPressed: _busy ? null : _showCreateDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create Playlist'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importPlaylist,
                    icon: const Icon(Icons.file_download_rounded),
                    label: const Text('Import Playlist'),
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
                  child: Icon(Icons.queue_music_rounded, color: BttColors.accentViolet),
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

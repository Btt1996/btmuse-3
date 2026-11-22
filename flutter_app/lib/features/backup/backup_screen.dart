import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/features/backup/backup_service.dart';

/// Backup & Restore screen.
///
/// Flow (mirrors the Swift reference):
/// * Export — one JSON file with the whole library (metadata + playlist
///   structure, no audio). Saved through the system save dialog
///   (`FilePicker.saveFile` — `share_plus` is not a dependency).
/// * Import — pick a `.json` backup, see a preview (counts, playlist names,
///   missing-audio warnings) and only then tap an explicit confirm button;
///   nothing is written before that tap.
/// * After restore, a report shows what was added, what already existed
///   (untouched) and what came back metadata-only.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _error;
  String? _status;
  BackupPreview? _preview;
  String? _pendingJson;
  RestoreReport? _report;

  /// Export needs no audio directory and never inserts tracks.
  BackupService _service() {
    return BackupService(
      library: ref.read(libraryRepositoryProvider),
      playlists: ref.read(playlistRepositoryProvider),
    );
  }

  /// Preview/restore resolve missing-audio flags against the audio directory.
  /// New tracks are inserted through LibraryRepository.insertTrack (plain
  /// row insert, no file copy), so restore of tracks not already in the
  /// library works end to end.
  Future<BackupService> _serviceWithAudioDir() async {
    final audioDir = await ref.read(localDatabaseProvider).audioDirectory;
    final library = ref.read(libraryRepositoryProvider);
    return BackupService(
      library: library,
      playlists: ref.read(playlistRepositoryProvider),
      audioDirectory: audioDir,
      insertTrack: (track) => library.insertTrack(track),
    );
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final json = await _service().exportLibrary();
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save library backup',
        fileName: BackupService.exportFileName(),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: utf8.encode(json),
      );
      if (!mounted) return;
      if (savedPath == null) {
        setState(() => _status = 'Export cancelled — nothing was saved.');
      } else {
        setState(() => _status = 'Backup saved.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickBackupFile() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
      _preview = null;
      _pendingJson = null;
      _report = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const BackupError('Could not read the selected backup file.');
      }
      final json = utf8.decode(bytes);
      final service = await _serviceWithAudioDir();
      final preview = await service.importPreview(json);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _pendingJson = json;
      });
    } on BackupFormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRestore() async {
    final json = _pendingJson;
    if (json == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = await _serviceWithAudioDir();
      final report = await service.restore(json, confirm: true);
      ref.invalidate(libraryTracksProvider);
      ref.invalidate(playlistsProvider);
      ref.invalidate(storageStatsProvider);
      if (!mounted) return;
      setState(() {
        _report = report;
        _preview = null;
        _pendingJson = null;
        _status = 'Restore complete.';
      });
    } on BackupError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _discardPreview() {
    setState(() {
      _preview = null;
      _pendingJson = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your library, as one file',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'A backup holds track metadata and playlist structure as JSON. '
                  'Audio files are never included — tracks whose audio is not on '
                  'this device come back as metadata-only entries.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader('EXPORT'),
          const SizedBox(height: 8),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.file_upload_rounded, color: BttColors.cyanAccent),
            title: const Text('Export Library Backup'),
            subtitle: const Text('Save the whole library as one .json file'),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : _export,
          ),
          const SizedBox(height: 16),
          _SectionHeader('IMPORT'),
          const SizedBox(height: 8),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.file_download_rounded, color: BttColors.goldAccent),
            title: const Text('Import Backup File'),
            subtitle: const Text('Pick a .json backup to preview before restoring'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : _pickBackupFile,
          ),
          if (_preview != null) ...[
            const SizedBox(height: 16),
            _PreviewCard(
              preview: _preview!,
              onConfirm: _busy ? null : _confirmRestore,
              onCancel: _busy ? null : _discardPreview,
              busy: _busy,
            ),
          ],
          if (_report != null) ...[
            const SizedBox(height: 16),
            _ReportCard(report: _report!),
          ],
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(
              _status!,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: BttColors.greenAccent),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BttColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BttColors.danger.withValues(alpha: 0.5)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: BttColors.danger, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Restore never overwrites anything: tracks already in your library '
            'are left untouched, and playlists with an existing name are skipped.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: BttColors.textSecondary,
            letterSpacing: 1.1,
          ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final BackupPreview preview;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool busy;

  const _PreviewCard({
    required this.preview,
    required this.onConfirm,
    required this.onCancel,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final shownMissing = preview.missingAudioTrackLabels.take(5).toList();
    final extraMissing =
        preview.missingAudioTrackLabels.length - shownMissing.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BttColors.cyanAccent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Backup Preview', style: Theme.of(context).textTheme.titleMedium),
          if (preview.exportedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Exported ${preview.exportedAt!.toLocal()}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          const SizedBox(height: 10),
          _previewRow(
            context,
            '${preview.trackCount} tracks in backup',
            '${preview.newTrackCount} new · ${preview.alreadyInLibraryCount} already in library',
          ),
          const SizedBox(height: 6),
          _previewRow(
            context,
            '${preview.playlists.length} playlists in backup',
            '${preview.newPlaylistCount} new · ${preview.existingPlaylistCount} already exist',
          ),
          if (preview.skippedEntryCount > 0) ...[
            const SizedBox(height: 6),
            _previewRow(
              context,
              '${preview.skippedEntryCount} malformed entries',
              'will be skipped',
              warning: true,
            ),
          ],
          if (preview.playlists.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Playlists', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            ...preview.playlists.map(
              (pl) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      pl.alreadyExists
                          ? Icons.check_circle_rounded
                          : Icons.add_circle_outline_rounded,
                      size: 16,
                      color: pl.alreadyExists
                          ? BttColors.textMuted
                          : BttColors.greenAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${pl.name} (${pl.trackCount} tracks)'
                        '${pl.alreadyExists ? ' — already exists, will be skipped' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (preview.missingAudioFileCount > 0) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: BttColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${preview.missingAudioFileCount} track'
                    '${preview.missingAudioFileCount == 1 ? '' : 's'} '
                    'have no audio file on this device and will be restored '
                    'as metadata-only:',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: BttColors.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...shownMissing.map(
              (label) => Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            if (extraMissing > 0)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Text(
                  'and $extraMissing more…',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: BttColors.cyanAccent,
                    foregroundColor: BttColors.bgObsidian,
                  ),
                  child: Text(busy ? 'Restoring…' : 'Restore Backup'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewRow(BuildContext context, String title, String detail,
      {bool warning = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(width: 8),
        Text(
          detail,
          style: TextStyle(
            fontSize: 12.5,
            color: warning ? BttColors.warning : BttColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final RestoreReport report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BttColors.greenAccent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: BttColors.greenAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Restore Report',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            report.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: BttColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

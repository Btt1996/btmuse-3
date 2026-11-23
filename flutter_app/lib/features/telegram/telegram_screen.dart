import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/player/mini_player.dart';
import 'package:btmu/features/telegram/telegram_service.dart';

class TelegramScreen extends ConsumerStatefulWidget {
  const TelegramScreen({super.key});

  @override
  ConsumerState<TelegramScreen> createState() => _TelegramScreenState();
}

class _TelegramScreenState extends ConsumerState<TelegramScreen> {
  final TextEditingController _tokenCtrl = TextEditingController();
  TelegramBotIdentity? _identity;
  List<TelegramAudioEntry> _entries = [];
  bool _loading = false;
  String? _error;
  // v3.0.5, item 11: import feedback is an inline line, never a
  // SnackBar overlaying the player.
  String? _status;
  final Map<String, double> _progressByFileId = {};
  final Map<String, CancelToken> _tokens = {};
  // v3.0.5, batch 2, item 1: a "Download All" run in progress.
  bool _downloadingAll = false;

  int get _downloadableCount =>
      _entries.where(isDownloadableTelegramEntry).length;

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
  }

  Future<void> _loadSavedToken() async {
    final saved = await ref.read(credentialsStoreProvider).getTelegramToken();
    if (saved != null && saved.isNotEmpty && mounted) {
      _tokenCtrl.text = saved;
    }
  }

  Future<void> _verifyAndScan() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tg = ref.read(telegramServiceProvider);
      final identity = await tg.validateBotToken(token);
      await ref.read(credentialsStoreProvider).setTelegramToken(token);
      final messages = await tg.fetchAccessibleAudioMessages(token);
      if (mounted) {
        setState(() {
          _identity = identity;
          _entries = messages;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _identity = null;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Downloads one entry and reports its outcome plus the status line
  /// for a single download. Shared by the per-file button and the
  /// "Download All" batch loop (which only uses the outcome).
  Future<({TelegramBatchOutcome outcome, String status})> _downloadOne(
    TelegramAudioEntry entry,
  ) async {
    final token = _tokenCtrl.text.trim();
    final cancelToken = CancelToken();
    _tokens[entry.fileId] = cancelToken;
    setState(() => _progressByFileId[entry.fileId] = 0.02);

    void markImported() {
      if (!mounted) return;
      setState(() {
        _progressByFileId.remove(entry.fileId);
        _entries = _entries
            .map((e) => e.fileId == entry.fileId ? e.copyWith(alreadyInLibrary: true) : e)
            .toList();
      });
    }

    try {
      final track = await ref.read(telegramServiceProvider).downloadAndImportAudio(
            botToken: token,
            entry: entry,
            cancelToken: cancelToken,
            onProgress: (pct, _, __) {
              if (mounted) {
                setState(() => _progressByFileId[entry.fileId] = pct);
              }
            },
          );
      ref.invalidate(libraryTracksProvider);
      ref.invalidate(storageStatsProvider);
      markImported();
      return (
        outcome: TelegramBatchOutcome.imported,
        status: 'Imported "${track.title}" from Telegram.',
      );
    } on DuplicateTrackFailure catch (e) {
      // Pre-download (or post-download hash) duplicate: report it as
      // "already in library", never as a download failure, and mark the
      // entry so the list stops offering a re-download.
      markImported();
      return (outcome: TelegramBatchOutcome.alreadyInLibrary, status: e.message);
    } catch (e) {
      if (mounted) setState(() => _progressByFileId.remove(entry.fileId));
      return (
        outcome: TelegramBatchOutcome.failed,
        status: 'Telegram download failed: $e',
      );
    } finally {
      _tokens.remove(entry.fileId);
    }
  }

  Future<void> _downloadEntry(TelegramAudioEntry entry) async {
    final result = await _downloadOne(entry);
    if (mounted) setState(() => _status = result.status);
  }

  /// "Download All" (batch 2, item 1): downloads every downloadable
  /// entry — not already in the library, within the 20 MB Bot API limit —
  /// one after another, then reports one summary line. A file that turns
  /// out to be a duplicate mid-batch counts as "already in library",
  /// never as a failure. Cancelling (the button toggles to Cancel) stops
  /// the loop after the current file; the summary says so.
  Future<void> _downloadAll() async {
    if (_downloadingAll) {
      // Cancel: stop after the current file and cancel its download.
      setState(() => _downloadingAll = false);
      for (final c in _tokens.values) {
        c.cancel();
      }
      return;
    }
    final targets = _entries.where(isDownloadableTelegramEntry).toList();
    if (targets.isEmpty) return;
    setState(() {
      _downloadingAll = true;
      _status = 'Downloading all ${targets.length} file(s)...';
    });
    final outcomes = <TelegramBatchOutcome>[];
    var cancelled = false;
    for (final entry in targets) {
      if (!mounted || !_downloadingAll) {
        cancelled = true;
        break;
      }
      final result = await _downloadOne(entry);
      if (!mounted || !_downloadingAll) {
        // Cancelled during this file: do not count it, just stop.
        cancelled = true;
        break;
      }
      outcomes.add(result.outcome);
      if (mounted) {
        final s = summarizeTelegramBatch(outcomes);
        setState(() => _status =
            'Download All: ${s.imported} imported, ${s.alreadyInLibrary} already in library, ${s.failed} failed (${outcomes.length}/${targets.length}).');
      }
    }
    if (mounted) {
      final s = summarizeTelegramBatch(outcomes);
      setState(() {
        _downloadingAll = false;
        _status = cancelled
            ? 'Download All stopped: ${s.imported} imported, ${s.alreadyInLibrary} already in library, ${s.failed} failed.'
            : 'Download All finished: ${s.imported} imported, ${s.alreadyInLibrary} already in library, ${s.failed} failed.';
      });
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    for (final c in _tokens.values) {
      c.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Telegram Bot Sync')),
      // v3.0.5, item 11: the player stays visible during import flows.
      bottomNavigationBar: const MiniPlayer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Bot Token (Stored in iOS Keychain)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: '123456:ABC-DEF...',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _verifyAndScan,
                  style: FilledButton.styleFrom(
                    backgroundColor: BttColors.accentPink,
                    foregroundColor: BttColors.bgObsidian,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(_loading ? 'Scanning Bot Updates...' : 'Verify Bot & Scan Audio'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Token verification checks bot identity via getMe only. Downloading requires accessible audio messages ≤ 20 MB per Telegram Bot API limits.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: BttColors.accentViolet),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What the bot can see',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The bot only sees audio sent directly to it, or posted in channels where it is an admin. It cannot read arbitrary public channels. To import from your own channel, add the bot as an admin there — or forward the audio to the bot.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: BttColors.danger)),
          ],
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: BttColors.accentPink,
                  ),
            ),
          ],
          if (_identity != null) ...[
            const SizedBox(height: 14),
            ListTile(
              tileColor: BttColors.bgCardHighlight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: Icon(Icons.verified_user_rounded, color: BttColors.success),
              title: Text('@${_identity!.username}'),
              subtitle: Text('${_identity!.firstName} · ${_entries.length} audio file(s) found'),
            ),
          ],
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _downloadingAll
                  ? _downloadAll
                  : (_downloadableCount == 0 ? null : _downloadAll),
              style: FilledButton.styleFrom(
                backgroundColor: BttColors.accentPink,
                foregroundColor: BttColors.bgObsidian,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: Icon(
                _downloadingAll ? Icons.close_rounded : Icons.download_for_offline_rounded,
              ),
              label: Text(
                _downloadingAll
                    ? 'Cancel Download All'
                    : 'Download All ($_downloadableCount)',
              ),
            ),
          ],
          const SizedBox(height: 16),
          TelegramAudioEntryList(
            entries: _entries,
            progressByFileId: _progressByFileId,
            onDownload: _downloadEntry,
            onCancel: (entry) => _tokens[entry.fileId]?.cancel(),
          ),
        ],
      ),
    );
  }
}

/// One audio entry row, shared by the Telegram sync screen and the
/// bot-link import screen: title / performer / chat / size, an
/// already-in-library or over-limit badge, a per-file download button,
/// or a cancel button + progress bar while downloading.
class TelegramAudioEntryList extends StatelessWidget {
  final List<TelegramAudioEntry> entries;
  final Map<String, double> progressByFileId;
  final void Function(TelegramAudioEntry entry) onDownload;
  final void Function(TelegramAudioEntry entry) onCancel;

  const TelegramAudioEntryList({
    super.key,
    required this.entries,
    required this.progressByFileId,
    required this.onDownload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: entries.map((entry) {
        final mb = (entry.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
        final progress = progressByFileId[entry.fileId];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            '${entry.performer} · ${entry.chatTitle} · $mb MB'
                            '${entry.alreadyInLibrary ? ' · Already in library' : ''}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (entry.alreadyInLibrary)
                      Icon(Icons.check_circle_rounded, color: BttColors.success)
                    else if (entry.exceedsBotApiLimit)
                      Icon(Icons.block_rounded, color: BttColors.danger)
                    else if (progress == null)
                      IconButton(
                        icon: Icon(Icons.download_rounded, color: BttColors.accentPink),
                        onPressed: () => onDownload(entry),
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: BttColors.warning),
                        onPressed: () => onCancel(entry),
                      ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

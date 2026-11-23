import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/player/mini_player.dart';
import 'package:btmu/features/telegram/telegram_screen.dart';
import 'package:btmu/features/telegram/telegram_service.dart';

/// Bot-link import (v3.0.5, batch 2, item 4): a SEPARATE screen from the
/// Telegram sync screen. The user stores their download bot's token once,
/// pastes any media link, the app hands the link to the bot, and this
/// screen picks up the file(s) the bot returns.
///
/// The app never fetches the media from the original link itself and
/// never interferes with what the bot does — the bot is built separately,
/// in Telegram, later. What the app does: verify the token, hand the
/// link over, poll the bot's updates for returned audio, and import it
/// (same validation + SHA-256 dedup as every other import).
class BotLinkImportScreen extends ConsumerStatefulWidget {
  const BotLinkImportScreen({super.key});

  @override
  ConsumerState<BotLinkImportScreen> createState() => _BotLinkImportScreenState();
}

class _BotLinkImportScreenState extends ConsumerState<BotLinkImportScreen> {
  final TextEditingController _tokenCtrl = TextEditingController();
  final TextEditingController _linkCtrl = TextEditingController();
  String? _botUsername;
  List<TelegramAudioEntry> _entries = [];
  bool _verifying = false;
  bool _sending = false;
  bool _polling = false;
  bool _downloadingAll = false;
  String? _error;
  // v3.0.5, item 11: import feedback is an inline line, never a
  // SnackBar overlaying the player.
  String? _status;
  final Map<String, double> _progressByFileId = {};
  final Map<String, CancelToken> _tokens = {};
  // Update id captured right before a link is sent: polling only watches
  // files that arrive AFTER the link was sent.
  int? _waitingSince;

  int get _downloadableCount =>
      _entries.where(isDownloadableTelegramEntry).length;

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
  }

  Future<void> _loadSavedToken() async {
    final saved = await ref.read(credentialsStoreProvider).getBotLinkToken();
    if (saved != null && saved.isNotEmpty && mounted) {
      _tokenCtrl.text = saved;
    }
  }

  Future<void> _verifyBot() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final username =
          await ref.read(botLinkServiceProvider).resolveBotUsername(token);
      await ref.read(credentialsStoreProvider).setBotLinkToken(token);
      if (mounted) {
        setState(() {
          _botUsername = username;
          _status = 'Download bot verified: @$username. Paste a link below.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _botUsername = null;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _sendLink() async {
    final token = _tokenCtrl.text.trim();
    final link = _linkCtrl.text.trim();
    if (token.isEmpty || link.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final svc = ref.read(botLinkServiceProvider);
      // Verify (and persist the token) first if the bot is not verified
      // yet — the username is needed to address the Telegram message.
      final username = _botUsername ?? await svc.resolveBotUsername(token);
      await ref.read(credentialsStoreProvider).setBotLinkToken(token);
      // Baseline BEFORE sending: only files arriving after this moment
      // belong to this link.
      final baseline = await svc.currentMaxUpdateId(token);
      await svc.sendLinkToBot(botUsername: username, link: link);
      if (mounted) {
        setState(() {
          _botUsername = username;
          _waitingSince = baseline;
          _status =
              'Link sent to @$username. Send it in Telegram, then tap "Check for returned files" once the bot replies.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pollReturnedFiles() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty || _waitingSince == null) return;
    setState(() {
      _polling = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(botLinkServiceProvider)
          .pollForReturnedFiles(token, sinceUpdateId: _waitingSince!);
      if (!mounted) return;
      setState(() {
        _waitingSince = result.maxUpdateId;
        if (result.entries.isEmpty) {
          _status = 'The bot has not returned any file yet — try again in a moment.';
        } else {
          final known = _entries.map((e) => e.fileId).toSet();
          final fresh =
              result.entries.where((e) => !known.contains(e.fileId)).toList();
          _entries = [...fresh, ..._entries];
          _status = fresh.isEmpty
              ? 'No new files from the bot.'
              : 'The bot returned ${fresh.length} file(s).';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  /// Same per-file download as the sync screen (shared service call),
  /// reporting its outcome plus the single-download status line.
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
        status: 'Imported "${track.title}" from your bot.',
      );
    } on DuplicateTrackFailure catch (e) {
      markImported();
      return (outcome: TelegramBatchOutcome.alreadyInLibrary, status: e.message);
    } catch (e) {
      if (mounted) setState(() => _progressByFileId.remove(entry.fileId));
      return (
        outcome: TelegramBatchOutcome.failed,
        status: 'Download failed: $e',
      );
    } finally {
      _tokens.remove(entry.fileId);
    }
  }

  Future<void> _downloadEntry(TelegramAudioEntry entry) async {
    final result = await _downloadOne(entry);
    if (mounted) setState(() => _status = result.status);
  }

  /// "Download All" (batch 2, item 5): same batch semantics as the sync
  /// screen — every downloadable returned file, one after another, one
  /// summary line. Cancelling stops the loop after the current file.
  Future<void> _downloadAll() async {
    if (_downloadingAll) {
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
    _linkCtrl.dispose();
    for (final c in _tokens.values) {
      c.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import via Download Bot')),
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
                  'Download Bot Token (Stored in iOS Keychain)',
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
                  onPressed: _verifying ? null : _verifyBot,
                  style: FilledButton.styleFrom(
                    backgroundColor: BttColors.accentPink,
                    foregroundColor: BttColors.bgObsidian,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _verifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_rounded),
                  label: Text(_verifying ? 'Verifying...' : 'Verify Download Bot'),
                ),
                if (_botUsername != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Verified: @$_botUsername',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: BttColors.success,
                        ),
                  ),
                ],
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
                        'How this works',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Paste any media link. The app opens Telegram with the link ready to send to your download bot — send it there. The bot downloads the media and replies with the file; this screen picks it up. The bot itself is built separately in Telegram — the app only sends the link and receives the file, and never downloads from the original link itself.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Media Link',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _linkCtrl,
                  decoration: const InputDecoration(
                    hintText: 'https://...',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sending ? null : _sendLink,
                  style: FilledButton.styleFrom(
                    backgroundColor: BttColors.accentMagenta,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_sending ? 'Sending...' : 'Send Link to Bot'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed:
                      (_polling || _waitingSince == null) ? null : _pollReturnedFiles,
                  icon: _polling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(
                    _polling
                        ? 'Checking...'
                        : 'Check for Returned Files',
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

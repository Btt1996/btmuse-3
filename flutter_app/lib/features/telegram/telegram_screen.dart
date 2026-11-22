import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
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
  final Map<String, double> _progressByFileId = {};
  final Map<String, CancelToken> _tokens = {};

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

  Future<void> _downloadEntry(TelegramAudioEntry entry) async {
    final token = _tokenCtrl.text.trim();
    final cancelToken = CancelToken();
    _tokens[entry.fileId] = cancelToken;
    setState(() => _progressByFileId[entry.fileId] = 0.02);

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
      if (mounted) {
        setState(() => _progressByFileId.remove(entry.fileId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "${track.title}" from Telegram.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _progressByFileId.remove(entry.fileId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Telegram download failed: $e')),
        );
      }
    } finally {
      _tokens.remove(entry.fileId);
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
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: BttColors.danger)),
          ],
          if (_identity != null) ...[
            const SizedBox(height: 14),
            ListTile(
              tileColor: BttColors.bgCardHighlight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.verified_user_rounded, color: BttColors.success),
              title: Text('@${_identity!.username}'),
              subtitle: Text('${_identity!.firstName} · ${_entries.length} audio file(s) found'),
            ),
          ],
          const SizedBox(height: 16),
          ..._entries.map((entry) {
            final mb = (entry.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
            final progress = _progressByFileId[entry.fileId];
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
                                '${entry.performer} · ${entry.chatTitle} · $mb MB',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (entry.exceedsBotApiLimit)
                          const Icon(Icons.block_rounded, color: BttColors.danger)
                        else if (progress == null)
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: BttColors.accentPink),
                            onPressed: () => _downloadEntry(entry),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: BttColors.warning),
                            onPressed: () => _tokens[entry.fileId]?.cancel(),
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
          }),
        ],
      ),
    );
  }
}

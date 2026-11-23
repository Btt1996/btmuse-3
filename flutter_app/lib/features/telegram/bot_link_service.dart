import 'package:btmu/core/deep_link.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/telegram/telegram_service.dart';

/// Bot-link import (v3.0.5, batch 2, item 4): a SEPARATE import path from
/// the Telegram sync screen, for a download bot the user builds later.
///
/// The contract, exactly as specified:
///   1. The user stores the download bot's token ONCE (iOS Keychain, via
///      [SecureCredentialsStore] — a separate key from the sync bot's
///      token, because this is a different bot doing a different job).
///   2. The user pastes any media link in the app; the app hands the
///      link to the bot.
///   3. The app waits for the bot to return the file(s) and imports
///      them — the app never fetches the media from the original link
///      itself and never interferes with what the bot does. The bot
///      itself is built later, by the user, in Telegram.
///
/// How step 2 actually works (honest mechanism): with only a bot token,
/// no app can inject a message into a bot's inbox — the Bot API only
/// lets a bot SEND messages, never receive one from a third party. So
/// the app opens Telegram with a message to the bot prefilled with the
/// link (`https://t.me/<bot>?text=<link>`); the user taps Send once.
/// The bot then sees a normal user message — exactly what any standard
/// Bot API bot expects — replies with the audio file, and this service
/// picks it up by polling `getUpdates`.
///
/// Polling note: `getUpdates` with an `offset` marks those updates as
/// read for that bot token, so the poller only advances the queue AFTER
/// a link was sent in this session (from the baseline captured at send
/// time). Use a different bot for link-downloads than for sync — that is
/// the intended setup — so the poller never eats the sync bot's queue.
class BotLinkImportService {
  final ApiClient _apiClient;
  final TelegramService _telegramService;
  final Future<void> Function(String url) _openExternalUrl;

  BotLinkImportService(
    this._apiClient,
    this._telegramService, {
    Future<void> Function(String url)? openExternalUrl,
  }) : _openExternalUrl = openExternalUrl ??
            ((url) => BttNativeBridge().openExternalUrl(url));

  /// Validates the download-bot token (`getMe` only) and returns the
  /// bot's username, needed to address the prefilled Telegram message.
  Future<String> resolveBotUsername(String botToken) async {
    final identity = await _telegramService.validateBotToken(botToken);
    return identity.username;
  }

  /// Hands [link] to the bot: opens Telegram with the link prefilled as
  /// a message to [botUsername]. The user taps Send once in Telegram.
  /// Throws [ValidationFailure] on an empty link.
  Future<void> sendLinkToBot({
    required String botUsername,
    required String link,
  }) async {
    final trimmed = link.trim();
    if (trimmed.isEmpty) {
      throw const ValidationFailure('Paste a media link first.');
    }
    final encoded = Uri.encodeComponent(trimmed);
    await _openExternalUrl('https://t.me/$botUsername?text=$encoded');
  }

  /// Highest `update_id` currently in the bot's queue (read-only — no
  /// offset, so nothing is consumed). The bot-link screen captures this
  /// right before sending a link, so polling only watches files that
  /// arrive after the link was sent.
  Future<int> currentMaxUpdateId(String botToken) async {
    final updates = await _fetchUpdates(botToken, offset: null);
    var maxId = 0;
    for (final raw in updates) {
      if (raw is Map) {
        final id = raw['update_id'] as int?;
        if (id != null && id > maxId) maxId = id;
      }
    }
    return maxId;
  }

  /// Polls for audio the bot returned after [sinceUpdateId]. Returns the
  /// new entries (newest-first, same parsing as the sync screen) plus
  /// the highest update id seen, which the caller stores as the next
  /// poll's baseline. An empty entry list means "the bot has not replied
  /// yet" — never an error, never a fake file.
  Future<({List<TelegramAudioEntry> entries, int maxUpdateId})>
      pollForReturnedFiles(
    String botToken, {
    required int sinceUpdateId,
  }) async {
    final updates = await _fetchUpdates(botToken, offset: sinceUpdateId + 1);
    var maxId = sinceUpdateId;
    for (final raw in updates) {
      if (raw is Map) {
        final id = raw['update_id'] as int?;
        if (id != null && id > maxId) maxId = id;
      }
    }
    return (
      entries: parseTelegramAudioEntries(updates),
      maxUpdateId: maxId,
    );
  }

  Future<List<dynamic>> _fetchUpdates(
    String botToken, {
    int? offset,
  }) async {
    final clean = botToken.trim();
    final query = <String, dynamic>{
      'allowed_updates': '["message","channel_post"]',
      'limit': 100,
    };
    if (offset != null) query['offset'] = offset;
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://api.telegram.org/bot$clean/getUpdates',
      queryParameters: query,
    );
    final data = res.data ?? {};
    if (data['ok'] != true) {
      throw AuthorizationFailure(
        (data['description'] as String?) ??
            'Unable to fetch Telegram bot updates.',
      );
    }
    return (data['result'] as List<dynamic>?) ?? [];
  }
}

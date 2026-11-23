import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/errors/app_failure.dart';
import '../../core/networking/api_client.dart';
import '../../core/utilities/audio_validator.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';

class TelegramBotIdentity {
  final String username;
  final String firstName;
  final int botId;

  const TelegramBotIdentity({
    required this.username,
    required this.firstName,
    required this.botId,
  });
}

class TelegramAudioEntry {
  final String fileId;

  /// Telegram Bot API `file_unique_id`: stable for the same file across
  /// bots and re-sends (unlike `file_id`). Null when the update payload
  /// did not carry one; dedup then falls back to the post-download
  /// SHA-256 check.
  final String? fileUniqueId;

  final String title;
  final String performer;
  final String fileName;
  final int durationSeconds;
  final int fileSizeBytes;
  final String chatTitle;
  final int messageDateEpoch;

  /// True when a track imported from this exact Telegram file is
  /// already in the library (matched by `fileUniqueId` at scan time).
  final bool alreadyInLibrary;

  const TelegramAudioEntry({
    required this.fileId,
    this.fileUniqueId,
    required this.title,
    required this.performer,
    required this.fileName,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.chatTitle,
    required this.messageDateEpoch,
    this.alreadyInLibrary = false,
  });

  TelegramAudioEntry copyWith({bool? alreadyInLibrary}) {
    return TelegramAudioEntry(
      fileId: fileId,
      fileUniqueId: fileUniqueId,
      title: title,
      performer: performer,
      fileName: fileName,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes,
      chatTitle: chatTitle,
      messageDateEpoch: messageDateEpoch,
      alreadyInLibrary: alreadyInLibrary ?? this.alreadyInLibrary,
    );
  }

  bool get exceedsBotApiLimit => fileSizeBytes > 20 * 1024 * 1024;
}

class TelegramService {
  final ApiClient _apiClient;
  final LibraryRepository _libraryRepo;

  TelegramService(this._apiClient, this._libraryRepo);

  Future<TelegramBotIdentity> validateBotToken(String botToken) async {
    final clean = botToken.trim();
    if (clean.isEmpty) {
      throw const ValidationFailure('Enter a valid Telegram Bot Token first.');
    }
    try {
      final res = await _apiClient.dio.get<Map<String, dynamic>>(
        'https://api.telegram.org/bot$clean/getMe',
      );
      final data = res.data ?? {};
      if (data['ok'] != true || data['result'] == null) {
        throw AuthorizationFailure(
          (data['description'] as String?) ?? 'Telegram rejected the bot token.',
        );
      }
      final bot = Map<String, dynamic>.from(data['result'] as Map);
      return TelegramBotIdentity(
        username: (bot['username'] as String?) ?? 'bot',
        firstName: (bot['first_name'] as String?) ?? 'Telegram Bot',
        botId: (bot['id'] as int?) ?? 0,
      );
    } on DioException catch (e) {
      throw NetworkFailure(
        'Telegram token verification failed (${e.response?.statusCode ?? 'network error'}).',
        cause: e,
      );
    }
  }

  Future<List<TelegramAudioEntry>> fetchAccessibleAudioMessages(String botToken) async {
    final clean = botToken.trim();
    final res = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://api.telegram.org/bot$clean/getUpdates',
      queryParameters: {
        'allowed_updates': '["message","channel_post"]',
        'limit': 100,
      },
    );

    final data = res.data ?? {};
    if (data['ok'] != true) {
      throw AuthorizationFailure(
        (data['description'] as String?) ?? 'Unable to fetch Telegram bot updates.',
      );
    }

    final updates = (data['result'] as List<dynamic>?) ?? [];
    final entries = <TelegramAudioEntry>[];
    final seenFileIds = <String>{};

    // Iterate in Telegram's chronological order, so a file posted twice
    // is represented by its FIRST occurrence (its original post). The
    // collected list is reversed below so the screen shows newest first.
    for (final raw in updates) {
      if (raw is! Map) continue;
      final msg = (raw['message'] ?? raw['channel_post']) as Map?;
      if (msg == null) continue;

      final chat = msg['chat'] as Map?;
      final chatTitle = (chat?['title'] as String?) ??
          (chat?['username'] as String?) ??
          'Direct Bot Chat';
      final date = (msg['date'] as int?) ?? 0;

      final audio = msg['audio'] as Map?;
      final document = msg['document'] as Map?;
      final voice = msg['voice'] as Map?;

      if (audio != null) {
        final fileId = audio['file_id'] as String?;
        if (fileId == null || !seenFileIds.add(fileId)) continue;
        final fileName = (audio['file_name'] as String?) ?? '${audio['title'] ?? 'track'}.mp3';
        entries.add(
          TelegramAudioEntry(
            fileId: fileId,
            fileUniqueId: audio['file_unique_id'] as String?,
            title: (audio['title'] as String?) ??
                fileName.replaceAll(RegExp(r'\.[a-z0-9]+$', caseSensitive: false), ''),
            performer: (audio['performer'] as String?) ?? 'Telegram Audio',
            fileName: fileName,
            durationSeconds: (audio['duration'] as int?) ?? 0,
            fileSizeBytes: (audio['file_size'] as int?) ?? 0,
            chatTitle: chatTitle,
            messageDateEpoch: date,
          ),
        );
      } else if (document != null) {
        final fileName = (document['file_name'] as String?) ?? '';
        final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
        final mime = ((document['mime_type'] as String?) ?? '').toLowerCase();
        final isAudio = AudioValidator.supportedExtensions.contains(ext) || mime.startsWith('audio/');
        if (!isAudio) continue;

        final fileId = document['file_id'] as String?;
        if (fileId == null || !seenFileIds.add(fileId)) continue;

        entries.add(
          TelegramAudioEntry(
            fileId: fileId,
            fileUniqueId: document['file_unique_id'] as String?,
            title: fileName.replaceAll(RegExp(r'\.[a-z0-9]+$', caseSensitive: false), ''),
            performer: 'Telegram Document',
            fileName: fileName,
            durationSeconds: 0,
            fileSizeBytes: (document['file_size'] as int?) ?? 0,
            chatTitle: chatTitle,
            messageDateEpoch: date,
          ),
        );
      } else if (voice != null) {
        final fileId = voice['file_id'] as String?;
        if (fileId == null || !seenFileIds.add(fileId)) continue;
        entries.add(
          TelegramAudioEntry(
            fileId: fileId,
            fileUniqueId: voice['file_unique_id'] as String?,
            title: 'Voice Note $date',
            performer: 'Telegram Voice',
            fileName: 'voice_$date.ogg',
            durationSeconds: (voice['duration'] as int?) ?? 0,
            fileSizeBytes: (voice['file_size'] as int?) ?? 0,
            chatTitle: chatTitle,
            messageDateEpoch: date,
          ),
        );
      }
    }

    // Newest first: entries were collected chronologically above, so
    // reverse them for display. Each entry keeps the date of the
    // message it represents, so the list is newest-first by that date.
    final ordered = entries.reversed.toList();

    // Pre-download dedup annotation: flag entries whose exact Telegram
    // file is already in the library, so the screen can show
    // "already in library" instead of offering a re-download. One
    // indexed lookup per entry; entries without a `file_unique_id`
    // stay unflagged and rely on the post-download SHA-256 check.
    for (var i = 0; i < ordered.length; i++) {
      final uniqueId = ordered[i].fileUniqueId;
      if (uniqueId == null || uniqueId.isEmpty) continue;
      final existing = await _libraryRepo.findByTelegramFileUniqueId(uniqueId);
      if (existing != null) {
        ordered[i] = ordered[i].copyWith(alreadyInLibrary: true);
      }
    }

    return ordered;
  }

  Future<Track> downloadAndImportAudio({
    required String botToken,
    required TelegramAudioEntry entry,
    required void Function(double progress, int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    // Pre-download duplicate check: the same Telegram file re-sent (or
    // still sitting in `getUpdates`) is skipped WITHOUT downloading.
    // Throws [DuplicateTrackFailure] carrying the existing track, the
    // same failure the post-download SHA-256 check throws — the screen
    // reports it as "already in library", not as a download failure.
    final uniqueId = entry.fileUniqueId;
    if (uniqueId != null && uniqueId.isNotEmpty) {
      final existing = await _libraryRepo.findByTelegramFileUniqueId(uniqueId);
      if (existing != null) {
        throw DuplicateTrackFailure(existing, existing.sha256);
      }
    }

    if (entry.exceedsBotApiLimit) {
      throw const ValidationFailure(
        'File exceeds Telegram Bot API 20 MB download limit for direct bots.',
      );
    }

    final clean = botToken.trim();
    final infoRes = await _apiClient.dio.get<Map<String, dynamic>>(
      'https://api.telegram.org/bot$clean/getFile',
      queryParameters: {'file_id': entry.fileId},
      cancelToken: cancelToken,
    );
    final infoData = infoRes.data ?? {};
    final filePath = infoData['result']?['file_path'] as String?;
    if (infoData['ok'] != true || filePath == null || filePath.isEmpty) {
      throw AuthorizationFailure(
        (infoData['description'] as String?) ??
            'Telegram could not resolve file path (possible Bot API size limit).',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(entry.fileName).replaceFirst('.', '');
    final tempFile = File(
      p.join(tempDir.path, 'tg_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'mp3' : ext}'),
    );

    try {
      await _apiClient.dio.download(
        'https://api.telegram.org/file/bot$clean/$filePath',
        tempFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final effectiveTotal = total > 0 ? total : entry.fileSizeBytes;
          final pct = effectiveTotal > 0 ? (received / effectiveTotal).clamp(0.0, 1.0) : 0.0;
          onProgress(pct, received, effectiveTotal);
        },
      );

      final actualSize = await tempFile.exists() ? await tempFile.length() : 0;
      if (actualSize < 1024) {
        throw ValidationFailure(
          'Telegram returned an incomplete or empty audio file ($actualSize bytes).',
        );
      }
      if (entry.fileSizeBytes > 4096 && actualSize < (entry.fileSizeBytes * 0.90)) {
        throw ValidationFailure(
          'Telegram download interrupted: received $actualSize of ${entry.fileSizeBytes} bytes.',
        );
      }

      return await _libraryRepo.importFileIntoLibrary(
        sourceFile: tempFile,
        rawTitle: entry.title,
        rawArtist: entry.performer,
        rawAlbum: entry.chatTitle,
        durationSeconds: entry.durationSeconds,
        sourceProvider: 'telegram',
        deleteSourceAfterCopy: true,
        telegramFileUniqueId: entry.fileUniqueId,
      );
    } catch (e) {
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }
  }
}

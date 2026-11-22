import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:btmu/core/config/x2_config.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';

/// Result of asking a self-hosted yt-dlp bridge to extract one YouTube URL.
class YoutubeBridgeExtraction {
  final String title;
  final String downloadUrl;

  const YoutubeBridgeExtraction({
    required this.title,
    required this.downloadUrl,
  });
}

/// Result of probing a bridge's `/health` endpoint.
class YoutubeBridgeHealth {
  final bool ok;
  final String detail;

  const YoutubeBridgeHealth({
    required this.ok,
    required this.detail,
  });
}

/// Client for the OPTIONAL self-hosted YouTube bridge (plan item 21,
/// the BttMusic pattern; reference server: `tools/ytdlp_server.py`).
///
/// What this is: the app never downloads YouTube audio itself. When the
/// user has configured a bridge URL (their OWN server running yt-dlp),
/// this service POSTs a YouTube URL to that server and receives a
/// `download_url` for the extracted audio. The caller then imports that
/// audio through the same X2 acquisition validation pipeline as any X2
/// download (content-type, magic bytes, size, duration plausibility,
/// SHA-256 dedup).
///
/// What this is not: a built-in YouTube download. With no bridge
/// configured every method throws [NetworkFailure] with code
/// `youtube_bridge_not_configured` and the app does nothing. No bridge
/// URL is ever invented — the user types their own.
///
/// Trust model: the bridge base URL is explicitly configured by the
/// user, so its own host is trusted for the `download_url` it returns —
/// a self-hosted bridge typically serves files from itself, often on a
/// LAN address that the SSRF guard would otherwise reject. Any other
/// host must pass [ApiClient.isSafeExternalUrl]. The bridge is never
/// sent credentials.
class YoutubeBridgeService {
  final Dio _dio;

  YoutubeBridgeService(ApiClient apiClient) : _dio = apiClient.dio;

  static const String extractPath = '/extract';
  static const String healthPath = '/health';

  /// Whether a `download_url` returned by the bridge at [bridgeBaseUrl]
  /// may be fetched: same host as the bridge itself (any port — the
  /// bridge serving its own file), or a safe public URL.
  static bool isAllowedBridgeDownloadUrl(String downloadUrl, String bridgeBaseUrl) {
    final parsed = Uri.tryParse(downloadUrl.trim());
    if (parsed == null) return false;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return false;
    if (parsed.host.isEmpty) return false;
    final bridge = Uri.tryParse(X2Config.normalizeSingleUrl(bridgeBaseUrl));
    if (bridge != null &&
        bridge.host.isNotEmpty &&
        parsed.host.toLowerCase() == bridge.host.toLowerCase()) {
      return true;
    }
    return ApiClient.isSafeExternalUrl(downloadUrl);
  }

  /// Probes `{bridge}/health`. Returns `ok: true` only when the server
  /// answers with `{"ok": true}` (the contract in
  /// `tools/ytdlp_server.py`). A server that answers HTTP but without
  /// that body returns `ok: false` — reachable, but not a btmu bridge.
  /// Throws only when nothing answers at all.
  Future<YoutubeBridgeHealth> testConnection(String bridgeBaseUrl) async {
    final base = _requireBridgeBaseUrl(bridgeBaseUrl);
    try {
      final res = await _dio.get<String>(
        '$base$healthPath',
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final data = _decodeJsonObject(res.data);
      if (data != null && data['ok'] == true) {
        final service = data['service'] as String?;
        return YoutubeBridgeHealth(
          ok: true,
          detail: service != null && service.isNotEmpty
              ? 'Bridge reachable ($service).'
              : 'Bridge reachable.',
        );
      }
      return const YoutubeBridgeHealth(
        ok: false,
        detail:
            'Server answered but did not confirm the bridge contract (expected {"ok": true} from /health).',
      );
    } on DioException catch (e) {
      final res = e.response;
      if (res != null) {
        return YoutubeBridgeHealth(
          ok: false,
          detail:
              'Bridge answered HTTP ${res.statusCode} at /health — this server does not expose the btmu bridge contract (older reference server?).',
        );
      }
      throw NetworkFailure(
        'Bridge unreachable: ${_dioErrorDetail(e)}',
        code: 'youtube_bridge_unreachable',
      );
    }
  }

  /// Asks the user's bridge to extract [youtubeUrl] and returns the
  /// title + audio `download_url`. The URL is validated with
  /// [isAllowedBridgeDownloadUrl] before it is returned; anything else
  /// throws [ValidationFailure] and is never fetched.
  Future<YoutubeBridgeExtraction> extract({
    required String bridgeBaseUrl,
    required Uri youtubeUrl,
  }) async {
    final base = _requireBridgeBaseUrl(bridgeBaseUrl);
    final host = youtubeUrl.host.toLowerCase();
    if (!host.contains('youtube.com') && host != 'youtu.be') {
      throw ValidationFailure(
        'Not a YouTube URL: ${youtubeUrl.toString()}',
        code: 'youtube_bridge_not_youtube_url',
      );
    }

    late final Response<String> res;
    try {
      res = await _dio.post<String>(
        '$base$extractPath',
        data: {'url': youtubeUrl.toString()},
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.jsonContentType,
          // yt-dlp extraction on the user's server can take a while;
          // the app's default 20 s receive timeout is too short here.
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
    } on DioException catch (e) {
      throw _bridgeFailure(e, 'Bridge extraction failed');
    }

    final data = _decodeJsonObject(res.data);
    final downloadUrl = data?['download_url'] as String?;
    if (data == null || downloadUrl == null || downloadUrl.trim().isEmpty) {
      throw const NetworkFailure(
        'Bridge answered but returned no download URL.',
        code: 'youtube_bridge_bad_response',
      );
    }
    if (!isAllowedBridgeDownloadUrl(downloadUrl, base)) {
      throw ValidationFailure(
        'Bridge returned a download URL the app will not fetch ($downloadUrl). '
        'The bridge must serve the file from its own host or a public URL.',
        code: 'youtube_bridge_unsafe_download_url',
      );
    }
    final rawTitle = data['title'] as String?;
    return YoutubeBridgeExtraction(
      title: rawTitle != null && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : 'YouTube audio',
      downloadUrl: downloadUrl.trim(),
    );
  }

  String _requireBridgeBaseUrl(String bridgeBaseUrl) {
    final base = X2Config.normalizeSingleUrl(bridgeBaseUrl);
    if (base.isEmpty) {
      throw const NetworkFailure(
        'No YouTube bridge is configured. Btt Music never downloads '
        'YouTube audio itself — configure your own yt-dlp server to '
        'enable this.',
        code: 'youtube_bridge_not_configured',
      );
    }
    if (!X2Config.isValidBackendUrl(base)) {
      throw const ValidationFailure(
        'Bridge URL is not a valid http(s) URL.',
        code: 'youtube_bridge_invalid_url',
      );
    }
    return base;
  }

  Map<String, dynamic>? _decodeJsonObject(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _dioErrorDetail(DioException e) {
    return e.message ?? e.error?.toString() ?? 'network error';
  }

  NetworkFailure _bridgeFailure(DioException e, String prefix) {
    final res = e.response;
    if (res != null) {
      final raw = res.data is String ? res.data as String : null;
      final detail = _decodeJsonObject(raw)?['detail'] as String?;
      if (detail != null && detail.isNotEmpty) {
        return NetworkFailure(
          '$prefix (HTTP ${res.statusCode}): $detail',
          code: 'youtube_bridge_error',
        );
      }
      return NetworkFailure(
        '$prefix (HTTP ${res.statusCode}).',
        code: 'youtube_bridge_error',
      );
    }
    return NetworkFailure(
      '$prefix: ${_dioErrorDetail(e)}',
      code: 'youtube_bridge_unreachable',
    );
  }
}

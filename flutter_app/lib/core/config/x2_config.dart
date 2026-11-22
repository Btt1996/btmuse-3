import '../networking/api_client.dart';

/// Environment and runtime configuration for Btt Music X2 multi-provider routing.
///
/// Honors compile-time `--dart-define` variables while allowing runtime overrides
/// persisted in local preferences / iOS Keychain:
///   - `X2_BACKEND_URL`
///   - `PIPED_API_URL` (single URL or comma-separated failover list)
///   - `INVIDIOUS_API_URL` (single URL or comma-separated failover list)
///
/// IMPORTANT: This class NEVER invents or falls back to a hardcoded backend URL.
/// When `X2_BACKEND_URL` is omitted, it remains empty and reports as not configured.
class X2Config {
  static const String buildTimeBackendUrl = String.fromEnvironment('X2_BACKEND_URL');
  static const String buildTimePipedUrls = String.fromEnvironment('PIPED_API_URL');
  static const String buildTimeInvidiousUrls = String.fromEnvironment('INVIDIOUS_API_URL');

  final String backendUrl;
  final List<String> pipedInstances;
  final List<String> invidiousInstances;

  const X2Config({
    required this.backendUrl,
    this.pipedInstances = const [],
    this.invidiousInstances = const [],
  });

  factory X2Config.fromEnvironment() {
    return X2Config(
      backendUrl: normalizeSingleUrl(buildTimeBackendUrl),
      pipedInstances: parseUrlList(buildTimePipedUrls),
      invidiousInstances: parseUrlList(buildTimeInvidiousUrls),
    );
  }

  bool get isBackendConfigured => isValidBackendUrl(backendUrl);
  bool get hasPipedInstances => pipedInstances.isNotEmpty;
  bool get hasInvidiousInstances => invidiousInstances.isNotEmpty;

  String get backendStatusLabel =>
      isBackendConfigured ? backendUrl.trim() : 'Not configured (X2_BACKEND_URL missing)';

  static String normalizeSingleUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static bool isValidBackendUrl(String raw) {
    final cleaned = normalizeSingleUrl(raw);
    if (cleaned.isEmpty) return false;
    final parsed = Uri.tryParse(cleaned);
    return parsed != null &&
        (parsed.scheme == 'https' || parsed.scheme == 'http') &&
        parsed.host.isNotEmpty;
  }

  static List<String> parseUrlList(
    String raw, {
    bool allowPrivateForTesting = false,
  }) {
    if (raw.trim().isEmpty) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final part in raw.split(',')) {
      final candidate = normalizeSingleUrl(part);
      if (candidate.isEmpty) continue;
      final isAllowed = allowPrivateForTesting
          ? isValidBackendUrl(candidate)
          : ApiClient.isSafeExternalUrl(candidate);
      if (isAllowed && seen.add(candidate)) {
        result.add(candidate);
      }
    }
    return List.unmodifiable(result);
  }
}

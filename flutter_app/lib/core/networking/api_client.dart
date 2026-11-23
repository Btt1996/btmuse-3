import 'package:dio/dio.dart';
import '../config/x2_config.dart';
import '../errors/app_failure.dart';

class ApiClient {
  final Dio dio;
  String backendBaseUrl;
  String? backendAuthToken;
  List<String> pipedInstances;
  List<String> invidiousInstances;
  final bool allowPrivateForTesting;

  ApiClient({
    this.backendBaseUrl = '',
    this.backendAuthToken,
    List<String>? pipedInstances,
    List<String>? invidiousInstances,
    this.allowPrivateForTesting = false,
    Dio? customDio,
  })  : pipedInstances = List.unmodifiable(pipedInstances ?? const []),
        invidiousInstances = List.unmodifiable(invidiousInstances ?? const []),
        dio = customDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 12),
                headers: const {
                  'User-Agent': 'BttMusic/3.0.5 (iOS; Flutter)',
                  'Accept': 'application/json',
                },
              ),
            );

  bool get isBackendConfigured => X2Config.isValidBackendUrl(backendBaseUrl);

  X2Config get currentConfig => X2Config(
        backendUrl: X2Config.normalizeSingleUrl(backendBaseUrl),
        pipedInstances: pipedInstances,
        invidiousInstances: invidiousInstances,
      );

  void applyConfig(X2Config config) {
    backendBaseUrl = config.backendUrl;
    pipedInstances = config.pipedInstances;
    invidiousInstances = config.invidiousInstances;
  }

  Map<String, String> backendHeaders() {
    final headers = <String, String>{};
    if (backendAuthToken != null && backendAuthToken!.trim().isNotEmpty) {
      headers['x-btt-auth'] = backendAuthToken!.trim();
    }
    return headers;
  }

  Uri buildBackendUri(String path) {
    if (!isBackendConfigured) {
      throw const NetworkFailure(
        'X2_BACKEND_URL is not configured. Set your deployed Btt Music backend URL in Settings or build with --dart-define=X2_BACKEND_URL=...',
        code: 'backend_not_configured',
      );
    }
    final cleaned = X2Config.normalizeSingleUrl(backendBaseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$cleaned$normalizedPath');
  }

  static bool isSafeExternalUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) return false;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return false;
    final host = parsed.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.startsWith('169.254.') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return false;
    }
    final parts = host.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? -1;
      if (second >= 16 && second <= 31) return false;
    }
    return true;
  }
}

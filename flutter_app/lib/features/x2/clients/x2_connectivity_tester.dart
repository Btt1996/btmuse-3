import 'package:dio/dio.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/clients/invidious_client.dart';
import 'package:btmu/features/x2/clients/piped_client.dart';
import 'package:btmu/features/x2/clients/provider_diagnostics.dart';

class X2ConnectivityReport {
  final bool backendConfigured;
  final bool backendReachable;
  final String backendMessage;
  final int? backendLatencyMs;
  final List<InstanceProbeResult> pipedProbes;
  final List<InstanceProbeResult> invidiousProbes;
  final bool audiusReachable;
  final String audiusMessage;
  final bool archiveOrgReachable;
  final String archiveOrgMessage;
  final bool jamendoReachable;
  final String jamendoMessage;

  const X2ConnectivityReport({
    required this.backendConfigured,
    required this.backendReachable,
    required this.backendMessage,
    this.backendLatencyMs,
    required this.pipedProbes,
    required this.invidiousProbes,
    required this.audiusReachable,
    required this.audiusMessage,
    required this.archiveOrgReachable,
    required this.archiveOrgMessage,
    required this.jamendoReachable,
    required this.jamendoMessage,
  });
}

/// Executes live availability checks against X2_BACKEND_URL, configured Piped/Invidious
/// instances, and direct zero-key open providers (never fabricating success).
class X2ConnectivityTester {
  final ApiClient _apiClient;
  final PipedClient _pipedClient;
  final InvidiousClient _invidiousClient;

  /// Jamendo client ID from X2Config (wired in app_providers.dart).
  /// Null/empty means "not configured": the Jamendo probe reports that
  /// instead of failing.
  final String? jamendoClientId;

  X2ConnectivityTester(this._apiClient, {this.jamendoClientId})
      : _pipedClient = PipedClient(_apiClient),
        _invidiousClient = InvidiousClient(_apiClient);

  Future<X2ConnectivityReport> runDiagnostics() async {
    bool backendConfigured = _apiClient.isBackendConfigured;
    bool backendReachable = false;
    int? backendLatencyMs;
    String backendMessage;

    if (!backendConfigured) {
      backendMessage = 'X2_BACKEND_URL is not configured. Optional companion features are offline.';
    } else {
      final sw = Stopwatch()..start();
      try {
        final uri = _apiClient.buildBackendUri('/api/x2/health');
        final res = await _apiClient.dio.get<Map<String, dynamic>>(
          uri.toString(),
          options: Options(
            headers: _apiClient.backendHeaders(),
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        sw.stop();
        backendLatencyMs = sw.elapsedMilliseconds;
        if (res.statusCode == 200 && res.data?['ok'] == true) {
          backendReachable = true;
          backendMessage = 'Connected (${sw.elapsedMilliseconds}ms)';
        } else {
          backendMessage = 'Backend responded with HTTP ${res.statusCode}';
        }
      } catch (e) {
        sw.stop();
        backendMessage = 'Backend unreachable: $e';
      }
    }

    final pipedProbes = await Future.wait(
      _apiClient.pipedInstances.map(_pipedClient.probeInstance),
    );
    final invidiousProbes = await Future.wait(
      _apiClient.invidiousInstances.map(_invidiousClient.probeInstance),
    );

    bool audiusReachable = false;
    String audiusMessage;
    try {
      final res = await _apiClient.dio.get<Map<String, dynamic>>(
        'https://discoveryprovider.audius.co/v1/tracks/search',
        queryParameters: const {'query': 'ambient', 'app_name': 'BttMusic'},
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final list = res.data?['data'] as List<dynamic>?;
      if (res.statusCode == 200 && list != null && list.isNotEmpty) {
        audiusReachable = true;
        audiusMessage = 'Reachable (${list.length} open tracks checked, zero keys)';
      } else {
        audiusMessage = 'Audius returned HTTP ${res.statusCode}';
      }
    } catch (e) {
      audiusMessage = 'Audius probe failed: $e';
    }

    // Internet Archive: lightweight keyless advancedsearch (one audio row).
    bool archiveOrgReachable = false;
    String archiveOrgMessage;
    try {
      final res = await _apiClient.dio.get<Map<String, dynamic>>(
        'https://archive.org/advancedsearch.php',
        queryParameters: const {
          'q': 'mediatype:(audio)',
          'fl[]': ['identifier'],
          'rows': 1,
          'output': 'json',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (res.statusCode == 200 && res.data?['response'] != null) {
        archiveOrgReachable = true;
        archiveOrgMessage = 'Reachable (public library search responded, zero keys)';
      } else {
        archiveOrgMessage = 'Internet Archive returned HTTP ${res.statusCode}';
      }
    } catch (e) {
      archiveOrgMessage = 'Internet Archive probe failed: $e';
    }

    // Jamendo: cheap tracks ping (limit=1). With no client ID configured
    // this is reported as "not configured", never as a failure.
    bool jamendoReachable = false;
    String jamendoMessage;
    final jamendoId = jamendoClientId?.trim() ?? '';
    if (jamendoId.isEmpty) {
      jamendoMessage =
          'Jamendo client ID not configured — set the Jamendo client ID in Settings to enable Jamendo search.';
    } else {
      try {
        final res = await _apiClient.dio.get<Map<String, dynamic>>(
          'https://api.jamendo.com/v3.0/tracks/',
          queryParameters: {'client_id': jamendoId, 'format': 'json', 'limit': 1},
          options: Options(
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final status = res.data?['headers']?['status'] as String?;
        if (res.statusCode == 200 && status == 'success') {
          jamendoReachable = true;
          jamendoMessage = 'Reachable (Jamendo API responded with client ID)';
        } else {
          jamendoMessage =
              'Jamendo returned HTTP ${res.statusCode}${status != null ? ' ($status)' : ''}';
        }
      } catch (e) {
        jamendoMessage = 'Jamendo probe failed: $e';
      }
    }

    return X2ConnectivityReport(
      backendConfigured: backendConfigured,
      backendReachable: backendReachable,
      backendMessage: backendMessage,
      backendLatencyMs: backendLatencyMs,
      pipedProbes: pipedProbes,
      invidiousProbes: invidiousProbes,
      audiusReachable: audiusReachable,
      audiusMessage: audiusMessage,
      archiveOrgReachable: archiveOrgReachable,
      archiveOrgMessage: archiveOrgMessage,
      jamendoReachable: jamendoReachable,
      jamendoMessage: jamendoMessage,
    );
  }
}

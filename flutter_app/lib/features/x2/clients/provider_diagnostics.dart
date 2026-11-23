import 'package:btmu/data/models/x2_result.dart';

class InstanceProbeResult {
  final String provider;
  final String instanceUrl;
  final bool available;
  final int latencyMs;
  final int? statusCode;
  final String? error;

  const InstanceProbeResult({
    required this.provider,
    required this.instanceUrl,
    required this.available,
    required this.latencyMs,
    this.statusCode,
    this.error,
  });
}

class ProviderAttempt {
  final String provider;
  final String instanceUrl;
  final String stage; // probe | search | resolve
  final bool ok;
  final String? error;

  const ProviderAttempt({
    required this.provider,
    required this.instanceUrl,
    required this.stage,
    required this.ok,
    this.error,
  });

  String formatSummary() {
    final host = Uri.tryParse(instanceUrl)?.host ?? instanceUrl;
    return ok
        ? '$provider ($host) $stage succeeded'
        : '$provider ($host) $stage failed: ${error ?? 'unknown error'}';
  }
}

class FailoverClientResult {
  final bool ok;
  final String? providerUsed;
  final String? instanceUsed;
  final List<X2Result> items;
  final List<ProviderAttempt> attempts;
  final String message;

  const FailoverClientResult({
    required this.ok,
    this.providerUsed,
    this.instanceUsed,
    required this.items,
    required this.attempts,
    required this.message,
  });
}

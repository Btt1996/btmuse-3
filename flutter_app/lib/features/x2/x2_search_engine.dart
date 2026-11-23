import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/provider_manager.dart';

class X2SearchResponse {
  final List<X2Result> results;
  final Map<String, String> providerErrors;
  final bool isUrlLookup;

  const X2SearchResponse({
    required this.results,
    required this.providerErrors,
    this.isUrlLookup = false,
  });
}

class X2SearchEngine {
  final ProviderManager _providerManager;
  final Duration providerTimeout;

  X2SearchEngine(
    this._providerManager, {
    this.providerTimeout = const Duration(seconds: 9),
  });

  Future<X2SearchResponse> search(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const X2SearchResponse(results: [], providerErrors: {});
    }

    final maybeUri = Uri.tryParse(trimmed);
    if (maybeUri != null && (maybeUri.scheme == 'http' || maybeUri.scheme == 'https')) {
      return _handleUrlInput(maybeUri);
    }

    final errors = <String, String>{};
    final collected = <X2Result>[];

    await Future.wait(
      _providerManager.searchProviders.map((provider) async {
        try {
          final items = await provider
              .searchTracks(trimmed, limit: 12)
              .timeout(providerTimeout);
          collected.addAll(items);
        } catch (e) {
          errors[provider.displayName] = e.toString();
        }
      }),
    );

    final scored = collected
        .map((r) => r.copyWith(matchScore: _scoreRelevance(trimmed, r)))
        .toList();

    final deduped = _deduplicateAndRank(scored);
    return X2SearchResponse(
      results: deduped,
      providerErrors: errors,
      isUrlLookup: false,
    );
  }

  Future<X2SearchResponse> _handleUrlInput(Uri uri) async {
    final provider = _providerManager.findProviderForUrl(uri);
    final errors = <String, String>{};
    if (provider == null) {
      return X2SearchResponse(
        results: const [],
        providerErrors: {
          'URL Resolver': 'Unsupported or unsafe URL host (${uri.host}).',
        },
        isUrlLookup: true,
      );
    }

    try {
      final resolved = await provider.resolveUrl(uri).timeout(providerTimeout);
      if (resolved == null) {
        return X2SearchResponse(
          results: const [],
          providerErrors: {provider.displayName: 'No resolvable audio or metadata at that URL.'},
          isUrlLookup: true,
        );
      }

      final all = <X2Result>[resolved.copyWith(matchScore: 1.0)];

      // If resolved URL is metadata-only (e.g. YouTube/Spotify/SoundCloud), automatically search authorized X2 providers
      if (!resolved.downloadAuthorized) {
        final handoffQuery = '${resolved.artist} ${resolved.title}'.trim();
        final alt = await search(handoffQuery);
        all.addAll(alt.results.where((r) => r.downloadAuthorized));
      }

      return X2SearchResponse(
        results: all,
        providerErrors: errors,
        isUrlLookup: true,
      );
    } catch (e) {
      return X2SearchResponse(
        results: const [],
        providerErrors: {provider.displayName: e.toString()},
        isUrlLookup: true,
      );
    }
  }

  static double _scoreRelevance(String query, X2Result result) {
    final qTokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();
    final haystack = '${result.title} ${result.artist} ${result.album}'.toLowerCase();
    var hits = 0;
    for (final token in qTokens) {
      if (haystack.contains(token)) hits++;
    }
    final textScore = qTokens.isEmpty ? 0.0 : hits / qTokens.length;
    final authBonus = result.downloadAuthorized ? 0.35 : 0.0;
    final audioBonus = result.audioAvailable ? 0.15 : 0.0;
    return (textScore * 0.6 + authBonus + audioBonus).clamp(0.0, 1.2);
  }

  static List<X2Result> _deduplicateAndRank(List<X2Result> items) {
    final byKey = <String, X2Result>{};
    for (final item in items) {
      final key =
          '${item.providerId}::${MetadataNormalizer.deduplicationKey(item.title, item.artist)}';
      final existing = byKey[key];
      if (existing == null || item.matchScore > existing.matchScore) {
        byKey[key] = item;
      }
    }
    final sorted = byKey.values.toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return sorted;
  }
}

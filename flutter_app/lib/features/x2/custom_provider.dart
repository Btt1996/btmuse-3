import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/direct_url_provider.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';

/// A user-added X2 source (v3.0.5, batch 2, item 2): a name plus a base
/// URL / source link. Built-in providers stay untouched; customs run
/// FIRST in the provider order, so a URL from a custom host resolves
/// through the custom provider instead of the generic direct-URL one.
///
/// What a custom provider IS: a named source whose URLs resolve through
/// the existing direct-audio / RSS validation (the same
/// [DirectUrlProvider] logic, the same SSRF guard, the same
/// acquisition-engine validation as every other authorized download).
/// It is NOT a search engine for an arbitrary site — no generic site
/// exposes a search API the app could guess — so keyword search stays
/// off and the UI says so. The source itself is never policed: any
/// http(s) host the user types is accepted as a source; the existing
/// URL-safety and audio-validation checks still apply at fetch time,
/// exactly as they do for every built-in provider.
class CustomX2ProviderConfig {
  final String id;
  final String name;
  final String baseUrl;

  const CustomX2ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'baseUrl': baseUrl};

  factory CustomX2ProviderConfig.fromJson(Map<String, dynamic> json) {
    return CustomX2ProviderConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
    );
  }

  Uri? get baseUri => Uri.tryParse(baseUrl.trim());

  String get host => baseUri?.host.toLowerCase() ?? '';

  /// A config is storable when it has an id, a non-empty name, and a
  /// parseable http(s) URL with a host. (The SSRF guard still applies
  /// at fetch time; this check only rejects unusable input.)
  bool get isValid {
    final uri = baseUri;
    return id.isNotEmpty &&
        name.trim().isNotEmpty &&
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

/// An [X2Provider] backed by a user-configured source. URL resolution
/// delegates to [DirectUrlProvider] (direct audio files + RSS feeds);
/// keyword search returns nothing by design (see above).
class CustomX2Provider implements X2Provider {
  final CustomX2ProviderConfig config;
  final DirectUrlProvider _direct;

  CustomX2Provider(this.config, ApiClient api) : _direct = DirectUrlProvider(api);

  @override
  String get id => 'custom_${config.id}';

  @override
  String get displayName => config.name;

  @override
  bool get supportsKeywordSearch => false;

  @override
  bool get supportsUrlResolution => true;

  @override
  bool get isMetadataOnly => false;

  @override
  bool canHandleUrl(Uri uri) {
    final host = config.host;
    if (host.isEmpty) return false;
    final h = uri.host.toLowerCase();
    return h == host || h.endsWith('.$host');
  }

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 15}) async =>
      const [];

  @override
  Future<X2Result?> resolveUrl(Uri uri) async {
    final resolved = await _direct.resolveUrl(uri);
    // The direct-URL resolver stamps its own provider id; a result
    // resolved for THIS custom source is attributed to the custom
    // provider, so Downloads history names the user's source.
    return resolved?.copyWith(providerId: id, providerLabel: displayName);
  }
}

/// Persistence for custom providers: a JSON list in SharedPreferences.
/// Names + URLs are not secrets, so plain prefs (like the backend URL)
/// — never the Keychain, never code.
class CustomProviderStore {
  static const _key = 'btmu_custom_x2_providers';

  Future<List<CustomX2ProviderConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => CustomX2ProviderConfig.fromJson(Map<String, dynamic>.from(m)))
          .where((c) => c.isValid)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<CustomX2ProviderConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }
}

/// Owns the live custom-provider list: loads it from [CustomProviderStore]
/// at startup and rebuilds the [X2Provider] instances on every change.
/// `providerManagerProvider` watches this and prepends the list, so
/// adding a provider takes effect without a restart.
class CustomProvidersNotifier extends StateNotifier<List<X2Provider>> {
  final CustomProviderStore _store;
  final ApiClient _api;
  List<CustomX2ProviderConfig> _configs = const [];

  static const _uuid = Uuid();

  CustomProvidersNotifier(this._store, this._api) : super(const []) {
    _load();
  }

  Future<void> _load() async {
    _configs = await _store.load();
    state = _configs.map((c) => CustomX2Provider(c, _api)).toList();
  }

  /// Adds a provider. Returns false (and stores nothing) when the name
  /// is empty or the URL is not a usable http(s) URL with a host.
  Future<bool> addProvider({
    required String name,
    required String baseUrl,
  }) async {
    final config = CustomX2ProviderConfig(
      id: _uuid.v4(),
      name: name.trim(),
      baseUrl: baseUrl.trim(),
    );
    if (!config.isValid) return false;
    _configs = [..._configs, config];
    await _store.save(_configs);
    state = _configs.map((c) => CustomX2Provider(c, _api)).toList();
    return true;
  }

  Future<void> removeProvider(String configId) async {
    _configs = _configs.where((c) => c.id != configId).toList();
    await _store.save(_configs);
    state = _configs.map((c) => CustomX2Provider(c, _api)).toList();
  }
}

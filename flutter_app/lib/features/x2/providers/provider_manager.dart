import 'x2_provider.dart';

class ProviderManager {
  final List<X2Provider> providers;

  ProviderManager(this.providers);

  List<X2Provider> get searchProviders =>
      providers.where((p) => p.supportsKeywordSearch).toList();

  List<X2Provider> get urlProviders =>
      providers.where((p) => p.supportsUrlResolution).toList();

  X2Provider? findProviderForUrl(Uri uri) {
    for (final p in urlProviders) {
      if (p.canHandleUrl(uri)) return p;
    }
    return null;
  }

  X2Provider? getById(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/data/models/x2_result.dart';
import 'package:btmu/features/x2/providers/provider_manager.dart';
import 'package:btmu/features/x2/providers/x2_provider.dart';
import 'package:btmu/features/x2/x2_search_engine.dart';

class _HealthyMockProvider implements X2Provider {
  @override
  String get id => 'mock_healthy';
  @override
  String get displayName => 'Healthy CC';
  @override
  bool get supportsKeywordSearch => true;
  @override
  bool get supportsUrlResolution => false;
  @override
  bool get isMetadataOnly => false;
  @override
  bool canHandleUrl(Uri uri) => false;

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 15}) async {
    return [
      const X2Result(
        id: '1',
        providerId: 'mock_healthy',
        providerLabel: 'Healthy CC',
        title: 'Midnight Echoes',
        artist: 'Solaris',
        album: 'Ambient Vol 1',
        audioUrl: 'https://example.com/echoes.mp3',
        audioAvailable: true,
        downloadAuthorized: true,
        authorizationNote: 'Creative Commons BY',
      ),
    ];
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async => null;
}

class _FailingProvider implements X2Provider {
  @override
  String get id => 'mock_broken';
  @override
  String get displayName => 'Broken Provider';
  @override
  bool get supportsKeywordSearch => true;
  @override
  bool get supportsUrlResolution => false;
  @override
  bool get isMetadataOnly => false;
  @override
  bool canHandleUrl(Uri uri) => false;

  @override
  Future<List<X2Result>> searchTracks(String query, {int limit = 15}) async {
    throw Exception('Upstream 503');
  }

  @override
  Future<X2Result?> resolveUrl(Uri uri) async => null;
}

void main() {
  test('X2SearchEngine isolates provider failures while returning authorized matches', () async {
    final manager = ProviderManager([_HealthyMockProvider(), _FailingProvider()]);
    final engine = X2SearchEngine(manager);

    final response = await engine.search('Midnight Echoes');

    expect(response.results.length, 1);
    expect(response.results.first.title, 'Midnight Echoes');
    expect(response.results.first.downloadAuthorized, isTrue);
    expect(response.providerErrors.containsKey('Broken Provider'), isTrue);
  });
}

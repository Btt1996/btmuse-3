import 'package:btmu/data/models/x2_result.dart';

abstract class X2Provider {
  String get id;
  String get displayName;
  bool get supportsKeywordSearch;
  bool get supportsUrlResolution;
  bool get isMetadataOnly;

  bool canHandleUrl(Uri uri);

  Future<List<X2Result>> searchTracks(String query, {int limit = 15});

  Future<X2Result?> resolveUrl(Uri uri);
}

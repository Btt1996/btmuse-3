import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/utilities/metadata_normalizer.dart';

void main() {
  test('MetadataNormalizer splits Artist - Title and strips noisy tags', () {
    final norm = MetadataNormalizer.normalize(
      rawTitle: 'Daft Punk - Voyager (Official Audio) [4K]',
    );

    expect(norm.artist, 'Daft Punk');
    expect(norm.title, 'Voyager');
    expect(norm.album, 'Single');
  });

  test('Deduplication key ignores punctuation and casing', () {
    final k1 = MetadataNormalizer.deduplicationKey('Midnight City!', 'M83');
    final k2 = MetadataNormalizer.deduplicationKey('midnight city', 'm83');
    expect(k1, k2);
  });
}

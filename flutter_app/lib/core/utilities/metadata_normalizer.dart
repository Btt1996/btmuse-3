class NormalizedMetadata {
  final String title;
  final String artist;
  final String album;

  const NormalizedMetadata({
    required this.title,
    required this.artist,
    required this.album,
  });
}

class MetadataNormalizer {
  static final RegExp _noiseTags = RegExp(
    r'\s*[\(\[](?:official\s*(?:music\s*)?video|official\s*audio|lyric(?:s)?\s*video|hd|4k|hq|Visualizer|explicit)[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _multiSpaces = RegExp(r'\s{2,}');

  static NormalizedMetadata normalize({
    required String rawTitle,
    String? rawArtist,
    String? rawAlbum,
  }) {
    var title = rawTitle.replaceAll(_noiseTags, '').trim();
    var artist = (rawArtist ?? '').trim();
    final album = (rawAlbum ?? '').trim().isEmpty ? 'Single' : rawAlbum!.trim();

    if ((artist.isEmpty || artist.toLowerCase() == 'unknown artist') &&
        title.contains(' - ')) {
      final parts = title.split(' - ');
      if (parts.length >= 2) {
        artist = parts.first.trim();
        title = parts.sublist(1).join(' - ').trim();
      }
    }

    title = title.replaceAll(_multiSpaces, ' ').trim();
    artist = artist.replaceAll(_multiSpaces, ' ').trim();

    if (title.isEmpty) title = 'Untitled Track';
    if (artist.isEmpty) artist = 'Unknown Artist';

    return NormalizedMetadata(
      title: title,
      artist: artist,
      album: album,
    );
  }

  static String deduplicationKey(String title, String artist) {
    final cleanTitle = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanArtist = artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$cleanArtist::$cleanTitle';
  }
}

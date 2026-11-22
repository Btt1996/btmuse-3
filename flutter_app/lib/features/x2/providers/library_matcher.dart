import 'package:btmu/core/utilities/metadata_normalizer.dart';
import 'package:btmu/data/models/track.dart';

/// Pure library-matching helper shared by metadata-only import paths
/// (Spotify playlists, SoundCloud / X2 results).
///
/// A candidate counts as "already in library" when either:
///
/// * its content hash matches a stored track's SHA-256 — the same audio
///   bytes, even when the tags differ; or
/// * its normalized title + artist key matches
///   ([MetadataNormalizer.deduplicationKey] — case- and
///   punctuation-insensitive, so "Midnight City!" by "M83" matches
///   "midnight city" by "m83").
///
/// Hash wins over metadata. Metadata-only sources (Spotify, SoundCloud)
/// have no audio, so they match by title + artist only — pass [sha256]
/// only when audio actually exists for the candidate.
class LibraryMatcher {
  LibraryMatcher._();

  static Track? findInLibrary(
    List<Track> libraryTracks, {
    required String title,
    required String artist,
    String? sha256,
  }) {
    if (sha256 != null && sha256.isNotEmpty) {
      for (final track in libraryTracks) {
        if (track.sha256.isNotEmpty && track.sha256 == sha256) {
          return track;
        }
      }
    }
    final key = MetadataNormalizer.deduplicationKey(title, artist);
    for (final track in libraryTracks) {
      if (MetadataNormalizer.deduplicationKey(track.title, track.artist) == key) {
        return track;
      }
    }
    return null;
  }
}

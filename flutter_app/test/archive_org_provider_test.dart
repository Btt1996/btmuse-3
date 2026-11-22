import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/features/x2/providers/archive_org_provider.dart';

typedef _StubHandler = ResponseBody Function(RequestOptions options);

class _StubAdapter implements HttpClientAdapter {
  final _StubHandler handler;
  _StubAdapter(this.handler);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }
}

ResponseBody _jsonBody(Object body, [int statusCode = 200]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

Map<String, dynamic> _searchJson() {
  return {
    'responseHeader': {'status': 0, 'QTime': 12},
    'response': {
      'numFound': 3,
      'docs': [
        {
          'identifier': 'test-item-1',
          'title': 'Test Item One',
          'creator': 'Test Artist',
        },
        {'identifier': 'test-item-2', 'title': 'No Audio Here'},
        {'identifier': 'restricted-item', 'title': 'Restricted Item'},
      ],
    },
  };
}

Map<String, dynamic> _metadataJson(String identifier) {
  switch (identifier) {
    case 'test-item-1':
      return {
        'metadata': {
          'identifier': 'test-item-1',
          'title': 'Test Item One',
          'creator': 'Test Artist',
          'mediatype': 'audio',
        },
        'files': [
          {'name': 'cover.jpg', 'format': 'JPEG', 'size': '1234'},
          {
            'name': 'test-item-1_vbr.mp3',
            'format': 'VBR MP3',
            'source': 'derivative',
            'size': '1234567',
            'length': '245.5',
          },
          {
            'name': 'test-item-1.flac',
            'format': 'FLAC',
            'source': 'original',
            'size': '9999999',
            'length': '245.5',
          },
        ],
      };
    case 'test-item-2':
      return {
        'metadata': {
          'identifier': 'test-item-2',
          'title': 'No Audio Here',
          'mediatype': 'audio',
        },
        'files': [
          {'name': 'notes.pdf', 'format': 'Text PDF', 'size': '555'},
        ],
      };
    case 'restricted-item':
      return {
        'metadata': {
          'identifier': 'restricted-item',
          'title': 'Restricted Item',
          'mediatype': 'audio',
          'access-restricted-item': 'true',
        },
        'files': [
          {
            'name': 'restricted.mp3',
            'format': 'MP3',
            'source': 'original',
            'size': '1000',
            'length': '60',
          },
        ],
      };
    default:
      return {
        'metadata': {'identifier': identifier},
        'files': [],
      };
  }
}

Dio _archiveDio() {
  final dio = Dio();
  dio.httpClientAdapter = _StubAdapter((options) {
    final path = options.uri.path;
    if (path.contains('advancedsearch.php')) return _jsonBody(_searchJson());
    if (path.contains('/metadata/')) {
      final identifier = options.uri.pathSegments.last;
      return _jsonBody(_metadataJson(identifier));
    }
    return _jsonBody({'error': 'Unexpected URL: $path'}, 404);
  });
  return dio;
}

void main() {
  group('ArchiveOrgProvider', () {
    test('search picks the MP3 file and skips non-MP3 and restricted items', () async {
      final provider = ArchiveOrgProvider(
        ApiClient(customDio: _archiveDio()),
      );

      final results = await provider.searchTracks('test song');

      expect(results.length, 1);
      final first = results.first;
      expect(first.providerId, 'archive_org');
      expect(first.title, 'Test Item One');
      expect(first.artist, 'Test Artist');
      expect(first.audioUrl,
          'https://archive.org/download/test-item-1/test-item-1_vbr.mp3');
      expect(first.durationSeconds, 245);
      expect(first.fileSizeBytes, 1234567);
      expect(first.format, 'MP3');
      expect(first.audioAvailable, isTrue);
      // Only public library items are downloadable; the restricted item
      // and the PDF-only item never produce a result.
      expect(first.downloadAuthorized, isTrue);
      expect(first.authorizationNote, contains('Internet Archive'));
      expect(first.authorizationNote, contains('public library'));
      expect(first.externalPageUrl, 'https://archive.org/details/test-item-1');
    });

    test('resolveUrl handles details and download URLs', () async {
      final provider = ArchiveOrgProvider(
        ApiClient(customDio: _archiveDio()),
      );

      final fromDetails = await provider.resolveUrl(
        Uri.parse('https://archive.org/details/test-item-1'),
      );
      expect(fromDetails, isNotNull);
      expect(fromDetails!.audioUrl,
          'https://archive.org/download/test-item-1/test-item-1_vbr.mp3');
      expect(fromDetails.downloadAuthorized, isTrue);

      final fromDownload = await provider.resolveUrl(
        Uri.parse(
            'https://archive.org/download/test-item-1/test-item-1_vbr.mp3'),
      );
      expect(fromDownload, isNotNull);
      expect(fromDownload!.audioUrl, fromDetails.audioUrl);

      // An item with no MP3 file resolves to null, not a fake result.
      final noAudio = await provider.resolveUrl(
        Uri.parse('https://archive.org/details/test-item-2'),
      );
      expect(noAudio, isNull);

      // A restricted item resolves to null even with a direct MP3 link.
      final restricted = await provider.resolveUrl(
        Uri.parse('https://archive.org/details/restricted-item'),
      );
      expect(restricted, isNull);

      expect(await provider.resolveUrl(Uri.parse('https://example.org/x')), isNull);
    });

    test('provider flags and URL routing', () {
      final provider = ArchiveOrgProvider(ApiClient());
      expect(provider.id, 'archive_org');
      expect(provider.supportsKeywordSearch, isTrue);
      expect(provider.supportsUrlResolution, isTrue);
      expect(provider.isMetadataOnly, isFalse);
      expect(provider.canHandleUrl(Uri.parse('https://archive.org/details/x')), isTrue);
      expect(
          provider.canHandleUrl(Uri.parse('https://www.archive.org/details/x')), isTrue);
      expect(provider.canHandleUrl(Uri.parse('https://example.org/details/x')), isFalse);
    });
  });
}

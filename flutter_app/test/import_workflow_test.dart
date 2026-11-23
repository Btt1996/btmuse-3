import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/utilities/audio_validator.dart';
import 'package:btmu/features/x2/providers/direct_url_provider.dart';
import 'package:btmu/features/x2/providers/soundcloud_provider.dart';
import 'package:btmu/features/x2/providers/vk_provider.dart';

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

void main() {
  group('AudioValidator container checks', () {
    test('Accepts valid ID3 MP3, FLAC, WAV, OGG, and M4A magic headers', () {
      expect(
        AudioValidator.inspectMagicBytes(Uint8List.fromList([0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0]))
            .format,
        AudioFormatType.mp3,
      );
      expect(
        AudioValidator.inspectMagicBytes(Uint8List.fromList([0x66, 0x4C, 0x61, 0x43, 0, 0, 0, 0]))
            .format,
        AudioFormatType.flac,
      );
      expect(
        AudioValidator.inspectMagicBytes(
          Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]),
        ).format,
        AudioFormatType.wav,
      );
      expect(
        AudioValidator.inspectMagicBytes(Uint8List.fromList([0x4F, 0x67, 0x67, 0x53, 0, 0, 0, 0]))
            .format,
        AudioFormatType.ogg,
      );
      expect(
        AudioValidator.inspectMagicBytes(Uint8List.fromList([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]))
            .format,
        AudioFormatType.m4a,
      );
    });

    test('Rejects HTML/XML/JSON payloads disguised with .mp3 extension', () {
      final html = Uint8List.fromList(utf8.encode('<!DOCTYPE html><html>Error 403</html>'));
      final res = AudioValidator.inspectMagicBytes(html, fileName: 'fake.mp3');
      expect(res.isValid, isFalse);
      expect(res.reason, contains('HTML'));
    });
  });

  group('DirectUrlProvider HTTP Range fallback & RSS enclosure parsing', () {
    test('Falls back from 405 HEAD to Range GET on extensionless stream URLs', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((options) {
        if (options.method == 'HEAD') {
          return ResponseBody.fromBytes(Uint8List(0), 405);
        }
        return ResponseBody.fromBytes(
          Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0, 0, 0, 0]),
          206,
          headers: {
            Headers.contentTypeHeader: ['audio/mpeg'],
            'content-range': ['bytes 0-1023/4259840'],
          },
        );
      });

      final provider = DirectUrlProvider(ApiClient(customDio: dio));
      final item = await provider.resolveUrl(Uri.parse('https://cdn.example.org/stream/88412'));
      expect(item, isNotNull);
      expect(item!.downloadAuthorized, isTrue);
      expect(item.fileSizeBytes, 4259840);
      expect(item.format, 'MP3');
    });

    test('Parses multiple audio enclosures from a Podcast RSS XML feed', () {
      const sampleXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Btt Synth Cast</title>
    <item>
      <title>Episode 01 — Skyline</title>
      <enclosure url="https://cdn.example.org/ep01.mp3" length="5120000" type="audio/mpeg"/>
    </item>
    <item>
      <title>Episode 02 — Midnight</title>
      <enclosure url="https://cdn.example.org/ep02.m4a" length="4120000" type="audio/mp4"/>
    </item>
  </channel>
</rss>''';

      final parsed = DirectUrlProvider.parseRssAudioEnclosures(
        sampleXml,
        sourceHost: 'cdn.example.org',
        feedUrl: 'https://cdn.example.org/feed.xml',
      );
      expect(parsed.length, 2);
      expect(parsed.first.title, 'Episode 01 — Skyline');
      expect(parsed.first.downloadAuthorized, isTrue);
      expect(parsed.last.audioUrl, 'https://cdn.example.org/ep02.m4a');
    });
  });

  group('VK & SoundCloud transparent failure contracts', () {
    test('VkProvider searchTracks never silently returns empty list without token', () async {
      final vk = VkProvider(ApiClient());
      expect(
        () => vk.searchTracks('daft punk'),
        throwsA(isA<AuthorizationFailure>()),
      );
    });

    test('SoundCloudProvider searchTracks reports API restriction transparently', () async {
      final sc = SoundCloudProvider(ApiClient());
      expect(
        () => sc.searchTracks('lofi beats'),
        throwsA(isA<AuthorizationFailure>()),
      );
    });
  });
}

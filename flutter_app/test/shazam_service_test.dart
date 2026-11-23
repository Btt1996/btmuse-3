import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/storage/secure_credentials_store.dart';
import 'package:btmu/features/x1/shazam_service.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseShazamDetectResponse', () {
    test('parses a full track payload', () {
      final id = ShazamIdentificationService.parseShazamDetectResponse({
        'track': {
          'key': '12345',
          'title': 'Dreams',
          'subtitle': 'Fleetwood Mac',
          'url': 'https://www.shazam.com/track/12345',
          'images': {'coverart': 'https://cdn.example.com/cover.jpg'},
          'share': {'href': 'https://www.shazam.com/track/12345'},
        },
      });
      expect(id, isNotNull);
      expect(id!.provider, 'Shazam');
      expect(id.title, 'Dreams');
      expect(id.artist, 'Fleetwood Mac');
      expect(id.artworkUrl, 'https://cdn.example.com/cover.jpg');
      expect(id.externalId, '12345');
      expect(id.confidence, 0.95);
    });

    test('no track means no match, never a guess', () {
      expect(
        ShazamIdentificationService.parseShazamDetectResponse({}),
        isNull,
      );
      expect(
        ShazamIdentificationService.parseShazamDetectResponse({
          'track': null,
        }),
        isNull,
      );
      expect(
        ShazamIdentificationService.parseShazamDetectResponse({
          'track': {'subtitle': 'Someone'},
        }),
        isNull,
      );
    });

    test('missing artist/artwork fall back, never throw', () {
      final id = ShazamIdentificationService.parseShazamDetectResponse({
        'track': {'title': 'Untitled'},
      });
      expect(id, isNotNull);
      expect(id!.artist, 'Unknown Artist');
      expect(id.artworkUrl, isNull);
    });
  });

  group('identifyClip', () {
    const channelName = 'plugins.it_nomads.com/flutter_secure_storage';
    const keyChannel = MethodChannel(channelName);
    var storedKey = '';
    late File sampleFile;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('shazam_test');
      sampleFile = File('${dir.path}/sample.wav');
      await sampleFile.writeAsBytes([0, 1, 2, 3, 4, 5]);
    });

    setUp(() {
      storedKey = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keyChannel, (call) async {
        if (call.method == 'read') {
          final args = call.arguments as Map?;
          if (args?['key'] == 'btmu_shazam_api_key') return storedKey;
          return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keyChannel, null);
    });

    ShazamIdentificationService serviceWithStub(_StubHandler handler) {
      final dio = Dio()..httpClientAdapter = _StubAdapter(handler);
      return ShazamIdentificationService(
        ApiClient(customDio: dio),
        SecureCredentialsStore(),
      );
    }

    test('no key configured throws a clear ValidationFailure', () async {
      final service = serviceWithStub((_) {
        fail('must not call the API without a key');
      });
      expect(
        () => service.identifyClip(sampleFile),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });

    test('a match parses into an X1Identification', () async {
      storedKey = 'test-key-123';
      var seenKey = '';
      var seenHost = '';
      var seenBody = '';
      final service = serviceWithStub((options) {
        seenKey = options.headers['X-RapidAPI-Key'] as String? ?? '';
        seenHost = options.headers['X-RapidAPI-Host'] as String? ?? '';
        seenBody = options.data as String? ?? '';
        return ResponseBody.fromString(
          jsonEncode({
            'track': {
              'key': '999',
              'title': 'Blinding Lights',
              'subtitle': 'The Weeknd',
              'images': {'coverart': 'https://cdn.example.com/c.jpg'},
            },
          }),
          200,
          headers: {'content-type': ['application/json']},
        );
      });
      final id = await service.identifyClip(sampleFile);
      expect(seenKey, 'test-key-123');
      expect(seenHost, 'shazam.p.rapidapi.com');
      expect(seenBody, base64Encode([0, 1, 2, 3, 4, 5]));
      expect(id, isNotNull);
      expect(id!.title, 'Blinding Lights');
      expect(id.artist, 'The Weeknd');
      expect(id.provider, 'Shazam');
    });

    test('a response without a track returns null (no match)', () async {
      storedKey = 'test-key-123';
      final service = serviceWithStub((_) {
        return ResponseBody.fromString(
          jsonEncode({'matches': []}),
          200,
          headers: {'content-type': ['application/json']},
        );
      });
      expect(await service.identifyClip(sampleFile), isNull);
    });

    test('a rejected key surfaces as AuthorizationFailure', () async {
      storedKey = 'bad-key';
      final service = serviceWithStub((_) {
        return ResponseBody.fromString(
          jsonEncode({'message': 'Invalid API key'}),
          401,
          headers: {'content-type': ['application/json']},
        );
      });
      expect(
        () => service.identifyClip(sampleFile),
        throwsA(isA<AuthorizationFailure>()),
      );
    });
  });
}

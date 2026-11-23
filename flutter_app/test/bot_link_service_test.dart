import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/core/errors/app_failure.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/telegram/bot_link_service.dart';
import 'package:btmu/features/telegram/telegram_service.dart';

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

class _FakeLibraryRepository extends LibraryRepository {
  _FakeLibraryRepository() : super(LocalDatabase.instance);
}

/// getUpdates payloads the stub serves, keyed by update id. The stub
/// mimics the real API: with an `offset` it only returns updates whose
/// id is >= the offset.
List<Map<String, dynamic>> _updates() => [
      {
        'update_id': 9,
        'message': {
          'date': 100,
          'chat': {'title': 'DL Bot'},
          'audio': {
            'file_id': 'f-old',
            'file_unique_id': 'vu-old',
            'title': 'Old Song',
            'duration': 180,
            'file_size': 1000,
          },
        },
      },
      {
        'update_id': 11,
        'message': {
          'date': 200,
          'chat': {'title': 'DL Bot'},
          'audio': {
            'file_id': 'f-new-1',
            'file_unique_id': 'vu-new-1',
            'title': 'New Song 1',
            'performer': 'Singer',
            'duration': 200,
            'file_size': 3000000,
          },
        },
      },
      {
        'update_id': 12,
        'message': {
          'date': 201,
          'chat': {'title': 'DL Bot'},
          'document': {
            'file_id': 'f-new-2',
            'file_unique_id': 'vu-new-2',
            'file_name': 'new-song-2.mp3',
            'mime_type': 'audio/mpeg',
            'file_size': 4000000,
          },
        },
      },
    ];

void main() {
  BotLinkImportService serviceWithStub({List<String>? openedUrls}) {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter((options) {
        final path = options.uri.path;
        if (path.endsWith('/getMe')) {
          return ResponseBody.fromString(
            jsonEncode({
              'ok': true,
              'result': {'username': 'dlbot', 'first_name': 'DL Bot', 'id': 123},
            }),
            200,
            headers: {'content-type': ['application/json']},
          );
        }
        if (path.endsWith('/getUpdates')) {
          final offset = options.queryParameters['offset'] as int?;
          final all = _updates();
          final visible = offset == null
              ? all
              : all.where((u) => (u['update_id'] as int) >= offset).toList();
          return ResponseBody.fromString(
            jsonEncode({'ok': true, 'result': visible}),
            200,
            headers: {'content-type': ['application/json']},
          );
        }
        throw StateError('unexpected request: $path');
      });
    return BotLinkImportService(
      ApiClient(customDio: dio),
      TelegramService(ApiClient(customDio: dio), _FakeLibraryRepository()),
      openExternalUrl: (url) async {
        openedUrls?.add(url);
      },
    );
  }

  group('BotLinkImportService', () {
    test('resolveBotUsername returns the bot username from getMe', () async {
      final service = serviceWithStub();
      expect(
        await service.resolveBotUsername('123:abc'),
        'dlbot',
      );
    });

    test('sendLinkToBot opens Telegram with the link prefilled', () async {
      final opened = <String>[];
      final service = serviceWithStub(openedUrls: opened);
      await service.sendLinkToBot(
        botUsername: 'dlbot',
        link: 'https://www.youtube.com/watch?v=abc&list=xyz',
      );
      expect(opened.length, 1);
      expect(
        opened.first,
        'https://t.me/dlbot?text=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3Dabc%26list%3Dxyz',
      );
    });

    test('sendLinkToBot rejects an empty link without opening anything', () async {
      final opened = <String>[];
      final service = serviceWithStub(openedUrls: opened);
      expect(
        () => service.sendLinkToBot(botUsername: 'dlbot', link: '   '),
        throwsA(isA<ValidationFailure>()),
      );
      expect(opened, isEmpty);
    });

    test('currentMaxUpdateId reads the queue without consuming it', () async {
      final service = serviceWithStub();
      expect(await service.currentMaxUpdateId('123:abc'), 12);
      // A second read sees the same max: nothing was consumed.
      expect(await service.currentMaxUpdateId('123:abc'), 12);
    });

    test('pollForReturnedFiles only returns files after the baseline', () async {
      final service = serviceWithStub();
      final result = await service.pollForReturnedFiles(
        '123:abc',
        sinceUpdateId: 10,
      );
      expect(result.maxUpdateId, 12);
      expect(result.entries.map((e) => e.fileId).toList(), [
        'f-new-2',
        'f-new-1',
      ]);
      expect(result.entries.first.title, 'new-song-2');
    });

    test('poll with nothing new returns empty entries, same baseline', () async {
      final service = serviceWithStub();
      final result = await service.pollForReturnedFiles(
        '123:abc',
        sinceUpdateId: 12,
      );
      expect(result.entries, isEmpty);
      expect(result.maxUpdateId, 12);
    });
  });
}

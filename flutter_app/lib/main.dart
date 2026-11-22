import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/app.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/core/services/btt_audio_handler.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/core/storage/secure_credentials_store.dart';
import 'package:btmu/data/repositories/library_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = LocalDatabase.instance;
  await db.database;

  final store = SecureCredentialsStore();
  final libraryRepo = LibraryRepository(db);

  final audioHandler = await AudioService.init(
    builder: () => BttAudioHandler(libraryRepo, store),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ahmed.btmu.playback',
      androidNotificationChannelName: 'Btt Music Playback',
      androidNotificationOngoing: true,
    ),
  );
  await audioHandler.initialize();

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const BttMusicApp(),
    ),
  );
}

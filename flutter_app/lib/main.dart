import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/app.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/core/services/btt_audio_handler.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/core/storage/secure_credentials_store.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/features/settings/custom_font_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = LocalDatabase.instance;
  await db.database;

  final store = SecureCredentialsStore();
  final libraryRepo = LibraryRepository(db);

  // v3.0.5, item 12: apply the saved theme before the first frame so
  // the app never flashes the default palette.
  final savedVariant = await store.getThemeVariant();
  BttColors.applyVariant(savedVariant);

  // v3.0.5, item 9: load a user-imported font before the first frame.
  // A missing or unloadable file just means the built-in fonts are used.
  String? loadedFontFamily;
  final savedFontFile = await store.getCustomFontFileName();
  if (savedFontFile != null) {
    loadedFontFamily = await CustomFontService.loadInstalledFont(savedFontFile);
  }

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
        themeVariantProvider.overrideWith((ref) => savedVariant),
        customFontFamilyProvider.overrideWith((ref) => loadedFontFamily),
      ],
      child: const BttMusicApp(),
    ),
  );
}

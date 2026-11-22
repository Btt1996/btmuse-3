import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/core/config/x2_config.dart';
import 'package:btmu/core/networking/api_client.dart';
import 'package:btmu/core/services/btt_audio_handler.dart';
import 'package:btmu/core/storage/local_database.dart';
import 'package:btmu/core/storage/secure_credentials_store.dart';
import 'package:btmu/data/models/audio_settings.dart';
import 'package:btmu/data/models/download_task.dart';
import 'package:btmu/data/models/playlist.dart';
import 'package:btmu/data/models/smart_remix_config.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/data/repositories/history_repository.dart';
import 'package:btmu/data/repositories/library_repository.dart';
import 'package:btmu/data/repositories/playlist_repository.dart';
import 'package:btmu/features/downloads/download_manager_provider.dart';
import 'package:btmu/features/telegram/telegram_service.dart';
import 'package:btmu/features/x1/x1_service.dart';
import 'package:btmu/features/x2/clients/x2_connectivity_tester.dart';
import 'package:btmu/features/x2/providers/audius_provider.dart';
import 'package:btmu/features/x2/providers/deezer_provider.dart';
import 'package:btmu/features/x2/providers/direct_url_provider.dart';
import 'package:btmu/features/x2/providers/itunes_metadata_provider.dart';
import 'package:btmu/features/x2/providers/provider_manager.dart';
import 'package:btmu/features/x2/providers/soundcloud_provider.dart';
import 'package:btmu/features/x2/providers/spotify_metadata_provider.dart';
import 'package:btmu/features/x2/providers/vk_provider.dart';
import 'package:btmu/features/x2/providers/youtube_provider.dart';
import 'package:btmu/features/x2/x2_acquisition_engine.dart';
import 'package:btmu/features/x2/x2_search_engine.dart';

final localDatabaseProvider = Provider<LocalDatabase>((ref) => LocalDatabase.instance);

final credentialsStoreProvider = Provider<SecureCredentialsStore>((ref) => SecureCredentialsStore());

final x2ConfigProvider = StateProvider<X2Config>((ref) => X2Config.fromEnvironment());

final apiClientProvider = Provider<ApiClient>((ref) {
  final initial = ref.read(x2ConfigProvider);
  final client = ApiClient(
    backendBaseUrl: initial.backendUrl,
    pipedInstances: initial.pipedInstances,
    invidiousInstances: initial.invidiousInstances,
  );
  ref.listen<X2Config>(x2ConfigProvider, (_, next) {
    client.applyConfig(next);
  });
  final store = ref.read(credentialsStoreProvider);
  store.loadX2Config().then((loaded) {
    client.applyConfig(loaded);
    ref.read(x2ConfigProvider.notifier).state = loaded;
  });
  store.getBackendAuthToken().then((token) => client.backendAuthToken = token);
  return client;
});

final x2ConnectivityTesterProvider = Provider<X2ConnectivityTester>(
  (ref) => X2ConnectivityTester(ref.watch(apiClientProvider)),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(localDatabaseProvider)),
);

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepository(ref.watch(localDatabaseProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(localDatabaseProvider)),
);

final audioHandlerProvider = Provider<BttAudioHandler>((ref) {
  throw UnimplementedError('BttAudioHandler must be overridden in ProviderScope at startup.');
});

final libraryTracksProvider = FutureProvider<List<Track>>((ref) async {
  return ref.watch(libraryRepositoryProvider).getAllTracks();
});

final storageStatsProvider = FutureProvider<LibraryStorageStats>((ref) async {
  ref.watch(libraryTracksProvider);
  return ref.watch(libraryRepositoryProvider).getStorageStats();
});

final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  return ref.watch(playlistRepositoryProvider).getAllPlaylists();
});

final providerManagerProvider = Provider<ProviderManager>((ref) {
  final api = ref.watch(apiClientProvider);
  return ProviderManager([
    VkProvider(api),
    YoutubeProvider(api),
    SoundCloudProvider(api),
    SpotifyMetadataProvider(api),
    AudiusProvider(api),
    DeezerProvider(api),
    ItunesMetadataProvider(api),
    DirectUrlProvider(api),
  ]);
});

final x2SearchEngineProvider = Provider<X2SearchEngine>(
  (ref) => X2SearchEngine(ref.watch(providerManagerProvider)),
);

final x2AcquisitionEngineProvider = Provider<X2AcquisitionEngine>(
  (ref) => X2AcquisitionEngine(
    ref.watch(apiClientProvider),
    ref.watch(libraryRepositoryProvider),
  ),
);

final x1ServiceProvider = Provider<X1Service>(
  (ref) => X1Service(
    ref.watch(apiClientProvider),
    ref.watch(libraryRepositoryProvider),
  ),
);

final telegramServiceProvider = Provider<TelegramService>(
  (ref) => TelegramService(
    ref.watch(apiClientProvider),
    ref.watch(libraryRepositoryProvider),
  ),
);

final downloadManagerProvider =
    StateNotifierProvider<DownloadManagerNotifier, List<DownloadTask>>((ref) {
  return DownloadManagerNotifier(
    ref.watch(historyRepositoryProvider),
    ref.watch(x2AcquisitionEngineProvider),
    () {
      ref.invalidate(libraryTracksProvider);
      ref.invalidate(storageStatsProvider);
    },
  );
});

final audioSettingsProvider = StateProvider<AudioSettings>((ref) {
  return ref.watch(audioHandlerProvider).audioSettings;
});

final smartRemixConfigProvider = StateProvider<SmartRemixConfig>((ref) {
  return const SmartRemixConfig();
});

/// Handoff query from X1 Recognition or YouTube Metadata Card directly into X2 Search tab.
final pendingX2SearchQueryProvider = StateProvider<String?>((ref) => null);

/// Global bottom-tab indices inside AppShell.
abstract final class BttTab {
  static const int home = 0;
  static const int library = 1;
  static const int importCenter = 2;
  static const int x2 = 3;
  static const int x1 = 4;
  static const int playlists = 5;
}

/// Global bottom-tab navigation index inside AppShell.
final currentTabIndexProvider = StateProvider<int>((ref) => BttTab.home);

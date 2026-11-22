import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/x2_config.dart';
import '../../data/models/audio_settings.dart';
import '../../data/models/smart_remix_config.dart';

class SecureCredentialsStore {
  static const _telegramTokenKey = 'btmu_telegram_bot_token';
  static const _vkTokenKey = 'btmu_vk_user_token';
  static const _backendTokenKey = 'btmu_backend_auth_token';
  static const _jamendoClientIdKey = 'btmu_jamendo_client_id';
  static const _backendUrlKey = 'btmu_backend_url';
  static const _youtubeBridgeUrlKey = 'btmu_youtube_bridge_url';
  static const _pipedUrlsKey = 'btmu_piped_api_urls';
  static const _invidiousUrlsKey = 'btmu_invidious_api_urls';
  static const _volumeMultKey = 'btmu_audio_volume_mult';
  static const _limiterKey = 'btmu_audio_limiter';
  static const _normalizeKey = 'btmu_audio_normalize';
  static const _eqPresetKey = 'btmu_audio_eq_preset';
  static const _playbackSpeedKey = 'btmu_audio_playback_speed';
  static const _crossfadeEnabledKey = 'btmu_audio_crossfade_enabled';
  static const _crossfadeSecondsKey = 'btmu_audio_crossfade_seconds';
  // Legacy (Phase 3, S-3): read only by the crossfade migration in
  // loadAudioSettings; `SmartRemixConfig.enabled` was dropped as vestigial.
  static const _remixEnabledKey = 'btmu_remix_enabled';
  static const _remixModeKey = 'btmu_remix_mode';
  // Legacy (Phase 3, S-3): crossfade used to live on SmartRemixConfig.
  // The key is kept only so loadAudioSettings can migrate existing users
  // once (see below); nothing writes it anymore.
  static const _remixCrossfadeKey = 'btmu_remix_crossfade';
  static const _lastTrackIdKey = 'btmu_last_track_id';
  static const _lastPositionMsKey = 'btmu_last_position_ms';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<String?> getTelegramToken() => _secureStorage.read(key: _telegramTokenKey);

  Future<void> setTelegramToken(String? token) async {
    if (token == null || token.trim().isEmpty) {
      await _secureStorage.delete(key: _telegramTokenKey);
    } else {
      await _secureStorage.write(key: _telegramTokenKey, value: token.trim());
    }
  }

  Future<String?> getVkToken() => _secureStorage.read(key: _vkTokenKey);

  Future<void> setVkToken(String? token) async {
    if (token == null || token.trim().isEmpty) {
      await _secureStorage.delete(key: _vkTokenKey);
    } else {
      await _secureStorage.write(key: _vkTokenKey, value: token.trim());
    }
  }

  Future<String?> getBackendAuthToken() => _secureStorage.read(key: _backendTokenKey);

  Future<void> setBackendAuthToken(String? token) async {
    if (token == null || token.trim().isEmpty) {
      await _secureStorage.delete(key: _backendTokenKey);
    } else {
      await _secureStorage.write(key: _backendTokenKey, value: token.trim());
    }
  }

  // Jamendo API client ID (Phase 5, item 24). A user credential, so it
  // lives in the Keychain like the backend auth token / VK token — never
  // in SharedPreferences, never in code. Empty (or only a build-time
  // --dart-define=JAMENDO_CLIENT_ID) means "not configured" and Jamendo
  // keyword search stays disabled; deleting the stored value falls back
  // to the build-time define, exactly like getBackendUrl().
  Future<String> getJamendoClientId() async {
    final stored = await _secureStorage.read(key: _jamendoClientIdKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    return X2Config.buildTimeJamendoClientId.trim();
  }

  Future<void> setJamendoClientId(String? clientId) async {
    if (clientId == null || clientId.trim().isEmpty) {
      await _secureStorage.delete(key: _jamendoClientIdKey);
    } else {
      await _secureStorage.write(key: _jamendoClientIdKey, value: clientId.trim());
    }
  }

  Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_backendUrlKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return X2Config.normalizeSingleUrl(saved);
    }
    return X2Config.normalizeSingleUrl(X2Config.buildTimeBackendUrl);
  }

  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = X2Config.normalizeSingleUrl(url);
    if (cleaned.isEmpty) {
      await prefs.remove(_backendUrlKey);
    } else {
      await prefs.setString(_backendUrlKey, cleaned);
    }
  }

  // Self-hosted YouTube bridge base URL (Phase 4, item 21). Stored in
  // SharedPreferences like the X2 backend URL: it is a server address
  // the user typed, not a secret. Empty means "no bridge configured"
  // and the app does nothing — the bridge URL is never invented.
  // NOTE: this store has no generic get/set methods; each key gets a
  // typed pair following getBackendUrl/setBackendUrl.
  Future<String> getYoutubeBridgeUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_youtubeBridgeUrlKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return X2Config.normalizeSingleUrl(saved);
    }
    return '';
  }

  Future<void> setYoutubeBridgeUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = X2Config.normalizeSingleUrl(url);
    if (cleaned.isEmpty) {
      await prefs.remove(_youtubeBridgeUrlKey);
    } else {
      await prefs.setString(_youtubeBridgeUrlKey, cleaned);
    }
  }

  Future<String> getPipedUrlsCsv() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pipedUrlsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    return X2Config.buildTimePipedUrls.trim();
  }

  Future<void> setPipedUrlsCsv(String csv) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = csv.trim();
    if (cleaned.isEmpty) {
      await prefs.remove(_pipedUrlsKey);
    } else {
      await prefs.setString(_pipedUrlsKey, cleaned);
    }
  }

  Future<String> getInvidiousUrlsCsv() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_invidiousUrlsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    return X2Config.buildTimeInvidiousUrls.trim();
  }

  Future<void> setInvidiousUrlsCsv(String csv) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = csv.trim();
    if (cleaned.isEmpty) {
      await prefs.remove(_invidiousUrlsKey);
    } else {
      await prefs.setString(_invidiousUrlsKey, cleaned);
    }
  }

  Future<X2Config> loadX2Config() async {
    final backend = await getBackendUrl();
    final pipedCsv = await getPipedUrlsCsv();
    final invidiousCsv = await getInvidiousUrlsCsv();
    final jamendoClientId = await getJamendoClientId();
    return X2Config(
      backendUrl: backend,
      pipedInstances: X2Config.parseUrlList(pipedCsv),
      invidiousInstances: X2Config.parseUrlList(invidiousCsv),
      jamendoClientId: jamendoClientId,
    );
  }

  Future<AudioSettings> loadAudioSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // One-time migration (Phase 3, S-3): crossfade used to be gated behind
    // Smart Remix (`btmu_remix_enabled` + `btmu_remix_crossfade`). If the
    // new keys have never been written, seed them from the legacy values
    // so an existing user who had crossfade via Smart Remix keeps it, then
    // persist the migrated values so this runs exactly once.
    final hasNewCrossfadeKeys = prefs.containsKey(_crossfadeEnabledKey) ||
        prefs.containsKey(_crossfadeSecondsKey);
    final migratedCrossfadeEnabled = hasNewCrossfadeKeys
        ? prefs.getBool(_crossfadeEnabledKey) ?? false
        : prefs.getBool(_remixEnabledKey) ?? false;
    final migratedCrossfadeSeconds = hasNewCrossfadeKeys
        ? prefs.getDouble(_crossfadeSecondsKey) ?? 6.0
        : (prefs.getInt(_remixCrossfadeKey) ?? 6).toDouble();
    final settings = AudioSettings(
      volumeMultiplier: prefs.getDouble(_volumeMultKey) ?? 1.0,
      limiterEnabled: prefs.getBool(_limiterKey) ?? true,
      normalizeVolume: prefs.getBool(_normalizeKey) ?? true,
      // Phase 3, C-3: playbackSpeed is persisted now; the native engine
      // clamps it to 0.5–2.0, so clamp on load too. Previously it always
      // reloaded as 1.0.
      playbackSpeed:
          (prefs.getDouble(_playbackSpeedKey) ?? 1.0).clamp(0.5, 2.0).toDouble(),
      eqPreset: prefs.getString(_eqPresetKey) ?? 'Balanced',
      crossfadeEnabled: migratedCrossfadeEnabled,
      crossfadeSeconds: migratedCrossfadeSeconds.clamp(1.0, 15.0).toDouble(),
    );
    if (!hasNewCrossfadeKeys) {
      await saveAudioSettings(settings);
    }
    return settings;
  }

  Future<void> saveAudioSettings(AudioSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeMultKey, settings.volumeMultiplier);
    await prefs.setBool(_limiterKey, settings.limiterEnabled);
    await prefs.setBool(_normalizeKey, settings.normalizeVolume);
    await prefs.setDouble(
        _playbackSpeedKey, settings.playbackSpeed.clamp(0.5, 2.0).toDouble());
    await prefs.setString(_eqPresetKey, settings.eqPreset);
    await prefs.setBool(_crossfadeEnabledKey, settings.crossfadeEnabled);
    await prefs.setDouble(_crossfadeSecondsKey,
        settings.crossfadeSeconds.clamp(1.0, 15.0).toDouble());
  }

  Future<SmartRemixConfig> loadSmartRemixConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_remixModeKey) ?? SmartRemixMode.smoothMix.name;
    return SmartRemixConfig(
      mode: SmartRemixMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => SmartRemixMode.smoothMix,
      ),
    );
  }

  Future<void> saveSmartRemixConfig(SmartRemixConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remixModeKey, config.mode.name);
  }

  Future<({String? trackId, int positionMs})> loadPlaybackCheckpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      trackId: prefs.getString(_lastTrackIdKey),
      positionMs: prefs.getInt(_lastPositionMsKey) ?? 0,
    );
  }

  Future<void> savePlaybackCheckpoint(String trackId, int positionMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastTrackIdKey, trackId);
    await prefs.setInt(_lastPositionMsKey, positionMs);
  }
}

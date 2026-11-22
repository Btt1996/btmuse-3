import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/x2_config.dart';
import '../../data/models/audio_settings.dart';
import '../../data/models/smart_remix_config.dart';

class SecureCredentialsStore {
  static const _telegramTokenKey = 'btmu_telegram_bot_token';
  static const _vkTokenKey = 'btmu_vk_user_token';
  static const _backendTokenKey = 'btmu_backend_auth_token';
  static const _backendUrlKey = 'btmu_backend_url';
  static const _pipedUrlsKey = 'btmu_piped_api_urls';
  static const _invidiousUrlsKey = 'btmu_invidious_api_urls';
  static const _volumeMultKey = 'btmu_audio_volume_mult';
  static const _limiterKey = 'btmu_audio_limiter';
  static const _normalizeKey = 'btmu_audio_normalize';
  static const _eqPresetKey = 'btmu_audio_eq_preset';
  static const _remixEnabledKey = 'btmu_remix_enabled';
  static const _remixModeKey = 'btmu_remix_mode';
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
    return X2Config(
      backendUrl: backend,
      pipedInstances: X2Config.parseUrlList(pipedCsv),
      invidiousInstances: X2Config.parseUrlList(invidiousCsv),
    );
  }

  Future<AudioSettings> loadAudioSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AudioSettings(
      volumeMultiplier: prefs.getDouble(_volumeMultKey) ?? 1.0,
      limiterEnabled: prefs.getBool(_limiterKey) ?? true,
      normalizeVolume: prefs.getBool(_normalizeKey) ?? true,
      eqPreset: prefs.getString(_eqPresetKey) ?? 'Balanced',
    );
  }

  Future<void> saveAudioSettings(AudioSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeMultKey, settings.volumeMultiplier);
    await prefs.setBool(_limiterKey, settings.limiterEnabled);
    await prefs.setBool(_normalizeKey, settings.normalizeVolume);
    await prefs.setString(_eqPresetKey, settings.eqPreset);
  }

  Future<SmartRemixConfig> loadSmartRemixConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_remixModeKey) ?? SmartRemixMode.smoothMix.name;
    return SmartRemixConfig(
      enabled: prefs.getBool(_remixEnabledKey) ?? false,
      mode: SmartRemixMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => SmartRemixMode.smoothMix,
      ),
      crossfadeSeconds: prefs.getInt(_remixCrossfadeKey) ?? 6,
    );
  }

  Future<void> saveSmartRemixConfig(SmartRemixConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_remixEnabledKey, config.enabled);
    await prefs.setString(_remixModeKey, config.mode.name);
    await prefs.setInt(_remixCrossfadeKey, config.crossfadeSeconds);
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

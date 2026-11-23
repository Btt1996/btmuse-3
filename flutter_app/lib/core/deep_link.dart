import 'package:flutter/services.dart';
import 'package:btmu/core/utilities/audio_validator.dart';

/// Actions the app can take from a `bttmu://` deep link (Share Extension,
/// Siri intents) or a `file://` URL handed over by iOS "Open In".
///
/// Pure Dart: parsing is unit-tested in `test/deep_link_test.dart`. The
/// side effects (navigation, playback, import) live in
/// `DeepLinkBootstrap` (`lib/app/app.dart`), never here.
sealed class BttDeepLinkAction {
  const BttDeepLinkAction();
}

/// Open X2 with [query] — a shared link (YouTube, Spotify, SoundCloud,
/// direct audio URL) or a search string. X2's engine handles URL vs
/// keyword itself.
class X2SearchDeepLink extends BttDeepLinkAction {
  final String query;
  const X2SearchDeepLink(this.query);
}

/// Import one audio file already on disk (iOS "Open In" drops it in the
/// app's Documents/Inbox; the Share Extension hands files over the same way).
class ImportFileDeepLink extends BttDeepLinkAction {
  final String filePath;
  const ImportFileDeepLink(this.filePath);
}

/// Siri: start playback. [shuffle] shuffles the library queue first.
class SiriPlayDeepLink extends BttDeepLinkAction {
  final bool shuffle;
  const SiriPlayDeepLink({this.shuffle = false});
}

/// Siri: play the playlist named [playlistName] (matched case-insensitively
/// against the library; no match is reported, never faked).
class SiriPlaylistDeepLink extends BttDeepLinkAction {
  final String playlistName;
  const SiriPlaylistDeepLink(this.playlistName);
}

/// Unparseable, or a link this build does not handle. Callers ignore it.
class UnknownDeepLink extends BttDeepLinkAction {
  const UnknownDeepLink();
}

/// Parses a raw link string into the action the app should take.
///
/// Accepted shapes:
///   - `bttmu://share?url=<encoded>` — Share Extension URL handoff.
///   - `bttmu://youtube-import?url=<encoded>` — legacy shape from the
///     BttMusic Share Extension; same handling as `share`.
///   - `bttmu://siri/play` / `bttmu://siri/shuffle` — Siri intents.
///   - `bttmu://siri/playlist?name=<name>` — Siri playlist intent.
///   - `file:///.../song.mp3` — iOS "Open In" (audio extension required).
/// Anything else is [UnknownDeepLink].
BttDeepLinkAction parseBttDeepLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const UnknownDeepLink();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return const UnknownDeepLink();

  if (uri.scheme == 'file') {
    final path = uri.toFilePath();
    return isImportableShareFile(path)
        ? ImportFileDeepLink(path)
        : const UnknownDeepLink();
  }

  if (uri.scheme != 'bttmu') return const UnknownDeepLink();

  switch (uri.host) {
    case 'share':
    case 'youtube-import':
      final url = uri.queryParameters['url'];
      if (url == null || url.trim().isEmpty) return const UnknownDeepLink();
      return X2SearchDeepLink(url.trim());
    case 'siri':
      switch (uri.path) {
        case '/play':
          return const SiriPlayDeepLink(shuffle: false);
        case '/shuffle':
          return const SiriPlayDeepLink(shuffle: true);
        case '/playlist':
          final name = uri.queryParameters['name'];
          if (name == null || name.trim().isEmpty) {
            return const UnknownDeepLink();
          }
          return SiriPlaylistDeepLink(name.trim());
        default:
          return const UnknownDeepLink();
      }
    default:
      return const UnknownDeepLink();
  }
}

/// True when [path] points at an audio file the library can import.
/// The Share Extension and "Open In" hand over arbitrary files; only
/// supported audio extensions reach the importer — everything else is
/// ignored, never force-imported.
bool isImportableShareFile(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0 || dot == lower.length - 1) return false;
  return AudioValidator.supportedExtensions.contains(lower.substring(dot + 1));
}

/// Method-channel bridge to the iOS Runner (`AppDelegate.swift`).
///
/// Channel `btmu/native_bridge`:
///   - Dart → native `getInitialLink`: the link that cold-launched the
///     app, if any (captured from launch options).
///   - Dart → native `openExternalUrl {url}`: opens an http(s) URL in the
///     system browser / Telegram (used by the bot-link import to hand a
///     prefilled message to the bot).
///   - Dart → native `drainShareInbox`: moves files the Share Extension
///     left in the App Group inbox into the app's Documents and returns
///     their paths (empty when the group container is unavailable — the
///     unsigned build has no App Group entitlement).
///   - Native → Dart `onLink <raw>`: a link that arrived while the app
///     was running (Share Extension / Siri / Open In).
class BttNativeBridge {
  static const MethodChannel _channel = MethodChannel('btmu/native_bridge');

  final void Function(String rawLink)? onLink;

  BttNativeBridge({this.onLink}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final raw = call.arguments as String?;
        if (raw != null && raw.isNotEmpty) onLink?.call(raw);
      }
      return null;
    });
  }

  Future<String?> getInitialLink() async {
    try {
      return await _channel.invokeMethod<String>('getInitialLink');
    } on PlatformException {
      return null;
    }
  }

  Future<void> openExternalUrl(String url) async {
    await _channel.invokeMethod<void>('openExternalUrl', {'url': url});
  }

  Future<List<String>> drainShareInbox() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('drainShareInbox');
      return result?.whereType<String>().toList() ?? const [];
    } on PlatformException {
      return const [];
    }
  }
}

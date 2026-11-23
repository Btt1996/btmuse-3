import 'package:flutter/services.dart';

/// Actions the app can take from a `bttmu://` deep link (Siri intents).
///
/// Pure Dart: parsing is unit-tested in `test/deep_link_test.dart`. The
/// side effects (navigation, playback, import) live in
/// `DeepLinkBootstrap` (`lib/app/app.dart`), never here.
sealed class BttDeepLinkAction {
  const BttDeepLinkAction();
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
///   - `bttmu://siri/play` / `bttmu://siri/shuffle` — Siri intents.
///   - `bttmu://siri/playlist?name=<name>` — Siri playlist intent.
/// Anything else is [UnknownDeepLink].
BttDeepLinkAction parseBttDeepLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const UnknownDeepLink();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return const UnknownDeepLink();

  if (uri.scheme != 'bttmu') return const UnknownDeepLink();

  switch (uri.host) {
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

/// Method-channel bridge to the iOS Runner (`AppDelegate.swift`).
///
/// Channel `btmu/native_bridge`:
///   - Dart → native `getInitialLink`: the link that cold-launched the
///     app, if any (captured from launch options).
///   - Dart → native `openExternalUrl {url}`: opens an http(s) URL in the
///     system browser / Telegram (used by the bot-link import to hand a
///     prefilled message to the bot).
///   - Native → Dart `onLink <raw>`: a link that arrived while the app
///     was running (Siri intent URL).
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
}

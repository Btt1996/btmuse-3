import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Method channel to Dart (`btmu/native_bridge`, see `lib/core/deep_link.dart`):
  ///   - Dart → native `getInitialLink`: the link that cold-launched the app.
  ///   - Dart → native `openExternalUrl {url}`: opens an http(s) URL
  ///     (bot-link import hands a prefilled Telegram message to the bot).
  ///   - Native → Dart `onLink <raw>`: a link that arrived while running
  ///     (Siri intent URL). Forwarded to Dart via the bridge channel.
  private var bridgeChannel: FlutterMethodChannel?
  private var launchLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "AudioEnginePlugin") {
      AudioEnginePlugin.register(with: registrar)
    }
    if let url = launchOptions?[.url] as? URL {
      launchLink = url.absoluteString
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "btmu/native_bridge",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { result(nil); return }
        switch call.method {
        case "getInitialLink":
          result(self.launchLink)
        case "openExternalUrl":
          guard
            let args = call.arguments as? [String: Any],
            let raw = args["url"] as? String,
            let url = URL(string: raw),
            url.scheme == "http" || url.scheme == "https"
          else {
            result(FlutterError(code: "bad_url", message: "Not an http(s) URL", details: nil))
            return
          }
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      bridgeChannel = channel
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// A link that arrives while the app runs (Siri intent URL). Forwarded
  /// to Dart via the bridge channel; super is NOT called, so the URL is
  /// handled exactly once, by `DeepLinkBootstrap`.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    bridgeChannel?.invokeMethod("onLink", arguments: url.absoluteString)
    return true
  }
}

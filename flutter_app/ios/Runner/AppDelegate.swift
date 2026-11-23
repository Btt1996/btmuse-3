import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Method channel to Dart (`btmu/native_bridge`, see `lib/core/deep_link.dart`):
  ///   - Dart → native `getInitialLink`: the link that cold-launched the app.
  ///   - Dart → native `openExternalUrl {url}`: opens an http(s) URL
  ///     (bot-link import hands a prefilled Telegram message to the bot).
  ///   - Dart → native `drainShareInbox`: moves files the Share Extension
  ///     left in the App Group inbox into the app's Documents.
  ///   - Native → Dart `onLink <raw>`: a link that arrived while running
  ///     (Share Extension / Siri / Open In).
  private var bridgeChannel: FlutterMethodChannel?
  private var launchLink: String?
  private static let appGroupId = "group.com.ahmed.btmu"

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
        case "drainShareInbox":
          result(self.drainShareInbox())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      bridgeChannel = channel
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// A link that arrives while the app runs (Share Extension `bttmu://`
  /// handoff, Siri intent URL, Open In file URL). Forwarded to Dart via
  /// the bridge channel; super is NOT called, so the URL is handled
  /// exactly once, by `DeepLinkBootstrap`.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    bridgeChannel?.invokeMethod("onLink", arguments: url.absoluteString)
    return true
  }

  /// Moves files the Share Extension left in the App Group inbox
  /// (`<group>/ShareInbox/`) into the app's Documents `share_inbox/`
  /// and returns their paths. Returns [] when the group container is
  /// unavailable — the unsigned build has no App Group entitlement, so
  /// the extension degrades to its URL handoff there (see
  /// `docs/share-extension-siri.md`).
  private func drainShareInbox() -> [String] {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroupId
    ) else { return [] }
    let inbox = container.appendingPathComponent("ShareInbox", isDirectory: true)
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: inbox, includingPropertiesForKeys: nil
    ) else { return [] }
    guard let docs = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask
    ).first else { return [] }
    let destDir = docs.appendingPathComponent("share_inbox", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: destDir, withIntermediateDirectories: true
    )
    var moved: [String] = []
    for file in files {
      let dest = destDir.appendingPathComponent(file.lastPathComponent)
      do {
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: file, to: dest)
        moved.append(dest.path)
      } catch {
        // Cross-volume move fallback: copy, then remove the original.
        do {
          try FileManager.default.copyItem(at: file, to: dest)
          try FileManager.default.removeItem(at: file)
          moved.append(dest.path)
        } catch {
          continue
        }
      }
    }
    return moved
  }
}

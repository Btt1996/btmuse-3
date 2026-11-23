import AppIntents
import Foundation

/// Siri integration (v3.0.5, batch 2, item 13): App Shortcuts for
/// "play some Btmus" / "Btmus me" / "shuffle Btmus" / "play <playlist>
/// on Btmus".
///
/// The intents open the app through its `bttmu://` deep links
/// (`bttmu://siri/play`, `bttmu://siri/shuffle`,
/// `bttmu://siri/playlist?name=...`); the Dart side
/// (`DeepLinkBootstrap`) starts playback. Opening the app is how indie
/// players do this: an intent cannot reach the Flutter audio engine
/// directly, so the deep link is the honest bridge — Siri opens Btmus
/// and playback starts there.
struct PlayBtmusIntent: AppIntent {
    static var title: LocalizedStringResource = "Play some Btmus"
    static var description = IntentDescription("Start playing your Btmus library.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "bttmu://siri/play")!))
    }
}

struct ShuffleBtmusIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle Btmus"
    static var description = IntentDescription("Shuffle-play your Btmus library.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "bttmu://siri/shuffle")!))
    }
}

struct PlayBtmusPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play a Btmus playlist"
    static var description = IntentDescription("Play one of your Btmus playlists.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Playlist", requestValueDialog: "Which playlist?")
    var playlistName: String

    func perform() async throws -> some IntentResult & OpensIntent {
        var components = URLComponents(string: "bttmu://siri/playlist")!
        components.queryItems = [URLQueryItem(name: "name", value: playlistName)]
        return .result(opensIntent: OpenURLIntent(components.url!))
    }
}

struct BtmusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayBtmusIntent(),
            phrases: [
                "Play some \(.applicationName)",
                "\(.applicationName) me",
                "Play \(.applicationName)",
            ],
            shortTitle: "Play some Btmus",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: ShuffleBtmusIntent(),
            phrases: [
                "Shuffle \(.applicationName)",
                "Shuffle my \(.applicationName)",
            ],
            shortTitle: "Shuffle Btmus",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: PlayBtmusPlaylistIntent(),
            phrases: [
                "Play a playlist on \(.applicationName)",
                "Play my playlist on \(.applicationName)",
            ],
            shortTitle: "Play a Btmus playlist",
            systemImageName: "music.note.list"
        )
    }
}

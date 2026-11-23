import SwiftUI
import UniformTypeIdentifiers

// Local stand-in for the app's BT design system (the extension is a separate
// module and cannot import it): the BT gradient, purple → magenta → red.
private struct ShareGradient: ShapeStyle {
    var body: some ShapeStyle {
        LinearGradient(
            colors: [Color(red: 0.478, green: 0.169, blue: 0.961),
                     Color(red: 0.902, green: 0.169, blue: 0.851),
                     Color(red: 1.0, green: 0.122, blue: 0.294)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Share Extension UI (v3.0.5, batch 2, item 7). Two handoffs, one screen:
///
///   - URLs / link text → forwarded to Btt Music via the `bttmu://share`
///     deep link (same pattern as the BttMusic SwiftUI app's extension).
///     If iOS denies the open from an extension (common), the link is
///     copied to the pasteboard as a fallback.
///   - Audio files → copied into the App Group inbox
///     (`group.com.ahmed.btmu/ShareInbox/`). Btt Music drains that inbox
///     on launch and on resume and imports the files. When the group
///     container is unavailable — the unsigned build has no App Group
///     entitlement — the screen says so plainly instead of pretending
///     the file was handed over (see `docs/share-extension-siri.md`).
struct ShareView: View {
    let extensionContext: NSExtensionContext?
    @State private var done = false
    @State private var message = "Working out what you shared…"
    @State private var sharedDetail: String?

    private static let appGroupId = "group.com.ahmed.btmu"
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "aiff", "aif",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(ShareGradient())
                Text(done ? "Handed to Btt Music" : "Share to Btt Music")
                    .font(.system(size: 17, weight: .bold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                if let detail = sharedDetail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                }
                Button("Done") {
                    extensionContext?.completeRequest(returningItems: nil)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(ShareGradient(), in: Capsule())
            }
            .padding()
            .navigationTitle("Btt Music")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .task { await handleSharedItems() }
    }

    private func handleSharedItems() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if await forwardURL(provider) { return }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                    if await handOverAudioFile(provider) { return }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if await forwardFileURL(provider) { return }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if await forwardPlainText(provider) { return }
                }
            }
        }
        if !done {
            message = "Btt Music couldn't use what was shared. It takes audio files and links."
        }
    }

    // MARK: - URLs

    private func forwardURL(_ provider: NSItemProvider) async -> Bool {
        guard let url = try? await provider.loadObject(ofClass: URL.self) as? URL else {
            return false
        }
        sharedDetail = url.absoluteString
        copyAndOpen(url.absoluteString)
        return true
    }

    private func forwardPlainText(_ provider: NSItemProvider) async -> Bool {
        guard let text = try? await provider.loadObject(ofClass: NSString.self) as? String else {
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme == "http" || url.scheme == "https" else {
            return false
        }
        sharedDetail = trimmed
        copyAndOpen(trimmed)
        return true
    }

    private func copyAndOpen(_ urlString: String) {
        UIPasteboard.general.string = urlString
        let trimmed = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ":/?&=.-_~"))) ?? urlString
        if let appURL = URL(string: "bttmu://share?url=\(trimmed)") {
            extensionContext?.open(appURL) { opened in
                Task { @MainActor in
                    done = true
                    message = opened
                        ? "Link handed to Btt Music — switch to the app to finish the import."
                        : "Link copied to your clipboard — open Btt Music and paste it into X2."
                }
            }
        } else {
            done = true
            message = "Link copied to your clipboard — open Btt Music and paste it into X2."
        }
    }

    // MARK: - Audio files

    private func forwardFileURL(_ provider: NSItemProvider) async -> Bool {
        guard let url = try? await provider.loadObject(ofClass: URL.self) as? URL else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        guard Self.audioExtensions.contains(ext) else { return false }
        return await handOverFile(at: url, fileName: url.lastPathComponent)
    }

    private func handOverAudioFile(_ provider: NSItemProvider) async -> Bool {
        guard let url = try? await provider.loadFileRepresentation(
            forTypeIdentifier: UTType.audio.identifier
        ) else {
            return false
        }
        return await handOverFile(at: url, fileName: url.lastPathComponent)
    }

    private func handOverFile(at url: URL, fileName: String) async -> Bool {
        sharedDetail = fileName
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupId
        ) else {
            done = true
            message = "Audio sharing needs the Btt Music App Group, which this unsigned build doesn't have. Save the file to Files and use Import from iPhone Files in Btt Music instead."
            return true
        }
        let inbox = container.appendingPathComponent("ShareInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let dest = inbox.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            // The extension only has a security-scoped read on the file.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: url, to: dest)
            done = true
            message = "Audio file saved to Btt Music — open the app and it will import automatically."
            return true
        } catch {
            done = true
            message = "Couldn't hand the file to Btt Music (\(error.localizedDescription)). Save it to Files and use Import from iPhone Files instead."
            return true
        }
    }
}

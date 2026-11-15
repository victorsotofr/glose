import AppKit

/// Test-only: `--snapshot <path.png>` writes the window to a PNG once the translation
/// has arrived, and logs the lookup to stderr. No screen-recording permission needed.
@MainActor
enum DebugHooks {
    static var snapshotPath: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--screen …` runs: snapshot once the screen has settled.
    static func snapshotSoon() {
        guard let path = snapshotPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { snapshot(to: path) }
    }

    static func log(_ line: String) {
        guard snapshotPath != nil else { return }
        FileHandle.standardError.write(Data((line + "\n").utf8))
        if line.hasPrefix("SELECTED"), let path = snapshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                snapshot(to: path.replacingOccurrences(of: ".png", with: "-pending.png"))
            }
        }
    }

    static func lookupFinished(_ lookup: Lookup) {
        guard let path = snapshotPath else { return }
        FileHandle.standardError.write(Data("""
        LOOKUP word=\(lookup.text) | fr=\(lookup.translation ?? "-") | page=\(lookup.pageIndex + 1)
        SENTENCE \(lookup.sentence ?? "-")
        SENTENCE_FR \(lookup.sentenceTranslation ?? "-")
        ERROR \(lookup.error ?? "-")
        DEFINITION \(lookup.definition.map { String($0.prefix(120)) } ?? "-")

        """.utf8))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { snapshot(to: path) }
    }

    static func snapshot(to path: String) {
        guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("SNAPSHOT \(path)\n".utf8))
    }
}

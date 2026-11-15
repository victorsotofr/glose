import Foundation

/// Glose keeps its own copy of every book so the library survives a cleaned-up Downloads folder.
public struct BookFiles {
    public let directory: URL
    /// How a copy is discarded: the Trash in the app, a plain delete in tests.
    public var discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    public init(directory: URL) { self.directory = directory }

    public static var `default`: BookFiles {
        BookFiles(directory: LibraryStore.default.url.deletingLastPathComponent()
            .appendingPathComponent("Books", isDirectory: true))
    }

    public static func fileName(for id: String) -> String { "\(id).pdf" }

    public func url(for book: BookRecord) -> URL? {
        book.fileName.map { directory.appendingPathComponent($0) }
    }

    public func hasCopy(_ book: BookRecord) -> Bool {
        url(for: book).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Copies `source` in as `<id>.pdf` unless that copy already exists. Returns the file name.
    @discardableResult
    public func importCopy(from source: URL, id: String) throws -> String {
        let name = Self.fileName(for: id)
        let dest = directory.appendingPathComponent(name)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: dest.path) {
            try fm.copyItem(at: source, to: dest)
        }
        return name
    }

    /// Moves Glose's copy (never the original) to the Trash.
    public func trashCopy(of book: BookRecord) throws {
        guard let url = url(for: book), FileManager.default.fileExists(atPath: url.path) else { return }
        try discard(url)
    }
}

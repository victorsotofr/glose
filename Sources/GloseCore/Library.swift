import CoreGraphics
import CryptoKit
import Foundation

public struct BookRecord: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// Where the PDF was added from. Informational only: Glose reads its own copy.
    public var sourcePath: String
    /// Glose's copy inside `BookFiles.directory`; nil until copied (v1 records).
    public var fileName: String?
    public var pageCount: Int
    public var lastPage: Int
    public var added: Date
    public var opened: Date

    public init(id: String, title: String, sourcePath: String, fileName: String? = nil,
                pageCount: Int = 0, lastPage: Int = 0, added: Date = .now, opened: Date = .now) {
        self.id = id; self.title = title; self.sourcePath = sourcePath; self.fileName = fileName
        self.pageCount = pageCount; self.lastPage = lastPage; self.added = added; self.opened = opened
    }

    /// 0…1 reading progress (last page seen / page count).
    public var progress: Double {
        pageCount > 1 ? min(1, Double(lastPage) / Double(pageCount - 1)) : 0
    }

    enum CodingKeys: String, CodingKey { case id, title, sourcePath, path, fileName, pageCount, lastPage, added, opened }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        // v1 stored the original location as "path".
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath)
            ?? c.decodeIfPresent(String.self, forKey: .path) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount) ?? 0
        lastPage = try c.decodeIfPresent(Int.self, forKey: .lastPage) ?? 0
        opened = try c.decodeIfPresent(Date.self, forKey: .opened) ?? .now
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? opened
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
        try c.encode(sourcePath, forKey: .sourcePath); try c.encodeIfPresent(fileName, forKey: .fileName)
        try c.encode(pageCount, forKey: .pageCount); try c.encode(lastPage, forKey: .lastPage)
        try c.encode(added, forKey: .added); try c.encode(opened, forKey: .opened)
    }
}

public struct Entry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var bookID: String
    public var word: String
    public var translation: String
    public var sentence: String?
    public var sentenceTranslation: String?
    public var pageIndex: Int
    /// Selection rectangles in page space, one per line, used for the highlight.
    public var rects: [CGRect]
    public var created: Date

    public init(id: UUID = UUID(), bookID: String, word: String, translation: String,
                sentence: String?, sentenceTranslation: String?, pageIndex: Int,
                rects: [CGRect], created: Date = .now) {
        self.id = id; self.bookID = bookID; self.word = word; self.translation = translation
        self.sentence = sentence; self.sentenceTranslation = sentenceTranslation
        self.pageIndex = pageIndex; self.rects = rects; self.created = created
    }
}

public enum WordSort: String, CaseIterable {
    case byBook = "By book", alphabetical = "A–Z", recent = "Recent"
}

public struct WordGroup: Equatable, Identifiable {
    /// Book id, or "" when the list is not grouped.
    public var id: String
    public var title: String?
    public var entries: [Entry]
}

public struct Library: Codable, Equatable {
    public var version = 2
    public var books: [String: BookRecord] = [:]
    public var entries: [Entry] = []
    public init() {}

    public func entries(for bookID: String) -> [Entry] {
        entries.filter { $0.bookID == bookID }.sorted { $0.created > $1.created }
    }

    /// Books, most recently opened first.
    public var booksByRecent: [BookRecord] {
        books.values.sorted { $0.opened > $1.opened }
    }

    public func wordCount(for bookID: String) -> Int {
        entries.reduce(0) { $0 + ($1.bookID == bookID ? 1 : 0) }
    }

    /// Entries whose word, translation or sentence contains `query` (case and accent insensitive).
    public func entries(matching query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entries.filter { e in
            [e.word, e.translation, e.sentence ?? "", e.sentenceTranslation ?? ""]
                .contains { $0.range(of: q, options: options) != nil }
        }
    }

    /// The Words tab: one section per book (most recently read book first, newest word first),
    /// or a single flat section sorted A–Z or newest first.
    public func wordGroups(sort: WordSort, query: String = "") -> [WordGroup] {
        let matches = entries(matching: query)
        switch sort {
        case .alphabetical:
            let sorted = matches.sorted {
                $0.word.compare($1.word, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending
            }
            return sorted.isEmpty ? [] : [WordGroup(id: "", title: nil, entries: sorted)]
        case .recent:
            let sorted = matches.sorted { $0.created > $1.created }
            return sorted.isEmpty ? [] : [WordGroup(id: "", title: nil, entries: sorted)]
        case .byBook:
            let byBook = Dictionary(grouping: matches, by: \.bookID)
            let order = booksByRecent.map(\.id) + byBook.keys.filter { books[$0] == nil }.sorted()
            return order.compactMap { id in
                guard let list = byBook[id], !list.isEmpty else { return nil }
                return WordGroup(id: id, title: books[id]?.title ?? "Removed book",
                                 entries: list.sorted { $0.created > $1.created })
            }
        }
    }

    public func isSaved(word: String, bookID: String, pageIndex: Int) -> Bool {
        entries.contains {
            $0.bookID == bookID && $0.pageIndex == pageIndex
                && $0.word.caseInsensitiveCompare(word) == .orderedSame
        }
    }
}

/// JSON file holding every book and saved word.
public struct LibraryStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static var `default`: LibraryStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glose", isDirectory: true)
        return LibraryStore(url: dir.appendingPathComponent("library.json"))
    }

    public func load() -> Library {
        guard let data = try? Data(contentsOf: url) else { return Library() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Library.self, from: data)) ?? Library()
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(library).write(to: url, options: .atomic)
    }
}

public enum BookID {
    /// SHA-256 of the first megabyte plus the file size: stable across renames and moves.
    public static func compute(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 1 << 20) ?? Data()
        let size = try handle.seekToEnd()
        var hasher = SHA256()
        hasher.update(data: head)
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum BookTitle {
    /// "Author - 2015 - Title" (a common file-naming scheme) → ("Title", "Author · 2015").
    /// Anything else → (name, nil).
    public static func split(_ name: String) -> (title: String, byline: String?) {
        let parts = name.components(separatedBy: " - ")
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        if trimmed.count >= 3, let year = Int(trimmed[1]), (1000...2999).contains(year), !trimmed[0].isEmpty {
            return (trimmed[2...].joined(separator: " - "), "\(trimmed[0]) · \(year)")
        }
        return (name, nil)
    }
}

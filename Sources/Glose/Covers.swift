import AppKit
import GloseCore
import PDFKit

/// Page-1 thumbnails, rendered once and cached on disk (`Covers/<id>.png`) and in memory.
@MainActor
enum Covers {
    private static var cache: [String: NSImage] = [:]
    private static let directory = LibraryStore.default.url.deletingLastPathComponent()
        .appendingPathComponent("Covers", isDirectory: true)

    static func image(for book: BookRecord, files: BookFiles) -> NSImage? {
        if let cached = cache[book.id] { return cached }
        let file = directory.appendingPathComponent("\(book.id).png")
        if let image = NSImage(contentsOf: file) {
            cache[book.id] = image
            return image
        }
        guard let url = files.url(for: book), let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let image = page.thumbnail(of: NSSize(width: 360, height: 520), for: .cropBox)
        cache[book.id] = image
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: file)
        }
        return image
    }

    static func remove(_ id: String) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).png"))
    }
}

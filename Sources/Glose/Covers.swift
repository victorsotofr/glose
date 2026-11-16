import AppKit
import GloseCore
import PDFKit

/// Thumbnail of the first page with something on it (skips blank leading pages), rendered once and cached on disk (`Covers/<id>.png`) and in memory.
@MainActor
enum Covers {
    private static var cache: [String: NSImage] = [:]
    private static let directory = LibraryStore.default.url.deletingLastPathComponent()
        .appendingPathComponent("Covers", isDirectory: true)

    static func image(for book: BookRecord, files: BookFiles) -> NSImage? {
        if let cached = cache[book.id] { return cached }
        let file = directory.appendingPathComponent("\(book.id).png")
        // Covers cached before blank pages were skipped are re-rendered once.
        if let image = NSImage(contentsOf: file), !isBlank(image) {
            cache[book.id] = image
            return image
        }
        guard let url = files.url(for: book), let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        // Prefer the first page that is a picture (cover or title graphic: ink but no text layer),
        // else the first non-blank page, else page 1.
        var firstNonBlank: NSImage?
        var picture: NSImage?
        for index in 0..<min(document.pageCount, 8) {
            guard let page = document.page(at: index) else { continue }
            let thumb = page.thumbnail(of: NSSize(width: 360, height: 520), for: .cropBox)
            if isBlank(thumb) { continue }
            if firstNonBlank == nil { firstNonBlank = thumb }
            let text = (page.string ?? "").filter { !$0.isWhitespace }
            if text.count < 3 { picture = thumb; break }
        }
        guard let image = picture ?? firstNonBlank
            ?? document.page(at: 0)?.thumbnail(of: NSSize(width: 360, height: 520), for: .cropBox) else { return nil }
        cache[book.id] = image
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: file)
        }
        return image
    }

    /// True when the page is a single flat colour (a blank leaf before the real cover).
    static func isBlank(_ image: NSImage) -> Bool {
        let width = 24, height = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        var low = 255, high = 0
        for x in 0..<width {
            for y in 0..<height {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let l = Int((0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent) * 255)
                low = min(low, l); high = max(high, l)
            }
        }
        return high - low < 8
    }

    static func remove(_ id: String) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).png"))
    }
}

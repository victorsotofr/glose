import Foundation

public enum CSV {
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func export(_ entries: [Entry], books: [String: BookRecord]) -> String {
        let iso = ISO8601DateFormatter()
        var rows = [["word", "translation", "sentence", "sentence_fr", "book", "page", "saved"]]
        for e in entries.sorted(by: { $0.created < $1.created }) {
            rows.append([
                e.word, e.translation, e.sentence ?? "", e.sentenceTranslation ?? "",
                books[e.bookID]?.title ?? "", String(e.pageIndex + 1), iso.string(from: e.created),
            ])
        }
        return encode(rows)
    }
}

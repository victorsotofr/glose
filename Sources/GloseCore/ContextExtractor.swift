import Foundation
import NaturalLanguage

/// Turns raw PDF text into the word and sentence shown in the panel.
public enum ContextExtractor {
    /// Rejoins words split across a line ("surf-\ning" → "surfing"), drops soft
    /// hyphens and folds all whitespace into single spaces.
    public static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\u{00AD}", with: "")
        // Compounds that already contain a hyphen keep it: "out-of-\nseason" → "out-of-season".
        s = s.replacingOccurrences(
            of: #"([-\x{2010}]\p{L}+[-\x{2010}])\s*[\r\n]+\s*(\p{L})"#,
            with: "$1$2",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"(\p{L})[-\x{2010}]\s*[\r\n]+\s*(\p{Ll})"#,
            with: "$1$2",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"(\p{L})([-\x{2010}])\s*[\r\n]+\s*(\p{Lu})"#,
            with: "$1$2$3",
            options: .regularExpression
        )
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The selection as a lookup term: normalized, with punctuation and quotes
    /// trimmed from both ends (inner apostrophes and hyphens are kept).
    public static func cleanSelection(_ raw: String) -> String {
        let edges = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        return normalize(raw).trimmingCharacters(in: edges)
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// The sentence of `text` containing the UTF-16 offset `offset`, normalized.
    /// Line breaks inside the page text are treated as spaces so a sentence that
    /// wraps over several lines is returned whole.
    public static func sentence(in text: String, aroundUTF16 offset: Int, maxLength: Int = 500) -> String? {
        let units = Array(text.utf16)
        guard offset >= 0, offset < units.count else { return nil }
        // Same UTF-16 length as `text`, so offsets and ranges stay valid in both.
        let flat = String(decoding: units.map { $0 == 10 || $0 == 13 ? 32 : $0 }, as: UTF16.self)
        guard let index = Range(NSRange(location: offset, length: 0), in: flat)?.lowerBound else { return nil }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = flat
        let range = tokenizer.tokenRange(at: index)
        guard !range.isEmpty,
              let original = Range(NSRange(range, in: flat), in: text) else { return nil }

        let sentence = normalize(String(text[original]))
        guard !sentence.isEmpty else { return nil }
        if sentence.count <= maxLength { return sentence }
        return String(sentence.prefix(maxLength)) + "…"
    }
}

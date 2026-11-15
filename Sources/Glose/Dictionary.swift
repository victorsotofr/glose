import CoreServices
import Foundation

/// English definition from the macOS built-in dictionary (offline).
enum SystemDictionary {
    static func definition(of term: String) -> String? {
        let length = (term as NSString).length
        guard length > 0,
              let raw = DCSCopyTextDefinition(nil, term as CFString, CFRangeMake(0, length))
        else { return nil }
        let text = raw.takeRetainedValue() as String
        // Put each numbered sense and part of speech on its own line.
        return text
            .replacingOccurrences(of: #" (\d{1,2}) (?=[a-z(\[])"#, with: "\n$1 ", options: .regularExpression)
            .replacingOccurrences(of: #" (noun|verb|adjective|adverb|preposition|exclamation|phrasal verb)\b"#,
                                  with: "\n\n$1", options: .regularExpression)
    }
}

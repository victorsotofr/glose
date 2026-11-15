// Plain assertion runner: swift-testing / XCTest need SwiftPM or Xcode, which this machine lacks.
import Foundation
import GloseCore

var failures = 0
func check(_ name: String, _ got: String?, _ want: String?) {
    if got == want { print("ok   \(name)") } else {
        failures += 1
        print("FAIL \(name)\n     got:  \(got.map { "\"\($0)\"" } ?? "nil")\n     want: \(want.map { "\"\($0)\"" } ?? "nil")")
    }
}
func offset(of needle: String, in text: String) -> Int {
    (text as NSString).range(of: needle).location
}

// cleanSelection
check("trims punctuation and quotes", ContextExtractor.cleanSelection("“swell,”"), "swell")
check("keeps inner apostrophe", ContextExtractor.cleanSelection(" don’t. "), "don’t")
check("keeps inner hyphen", ContextExtractor.cleanSelection("long-board;"), "long-board")
check("rejoins line-break hyphen", ContextExtractor.cleanSelection("surf-\ning"), "surfing")
check("keeps hyphen before capital", ContextExtractor.normalize("Anglo-\nSaxon"), "Anglo-Saxon")
check("keeps compound hyphen", ContextExtractor.normalize("an out-of-\nseason swell"), "an out-of-season swell")
check("drops soft hyphen", ContextExtractor.cleanSelection("re\u{00AD}ef"), "reef")
check("folds whitespace", ContextExtractor.cleanSelection("reef\n  break"), "reef break")
check("word count", String(ContextExtractor.wordCount("reef break here")), "3")

// sentence
let page = """
The waves came in sets. We paddled out past the
reef, where the swell stood up and broke in long, clean
walls. Nobody spoke.
"""
check("sentence across lines", ContextExtractor.sentence(in: page, aroundUTF16: offset(of: "swell", in: page)),
      "We paddled out past the reef, where the swell stood up and broke in long, clean walls.")
check("first sentence", ContextExtractor.sentence(in: page, aroundUTF16: offset(of: "sets", in: page)),
      "The waves came in sets.")
check("last sentence", ContextExtractor.sentence(in: page, aroundUTF16: offset(of: "Nobody", in: page)),
      "Nobody spoke.")
let crlf = "One line.\r\nThe barrel-\r\nling wave was hollow."
check("CRLF + hyphen", ContextExtractor.sentence(in: crlf, aroundUTF16: offset(of: "wave", in: crlf)),
      "The barrelling wave was hollow.")
let emoji = "A 🌊 sentence. Then the lineup."
check("UTF-16 offsets after emoji", ContextExtractor.sentence(in: emoji, aroundUTF16: offset(of: "lineup", in: emoji)),
      "Then the lineup.")
check("out of range", ContextExtractor.sentence(in: "abc", aroundUTF16: 10), nil)
check("truncates long sentences",
      ContextExtractor.sentence(in: String(repeating: "word ", count: 200) + "end.", aroundUTF16: 3, maxLength: 20),
      "word word word word …")

// CSV
check("csv escaping", CSV.encode([["a", "b,c", "say \"hi\"", "x\ny"]]), "a,\"b,c\",\"say \"\"hi\"\"\",\"x\ny\"\n")
let book = BookRecord(id: "b1", title: "Test Book", sourcePath: "/tmp/t.pdf")
let e1 = Entry(bookID: "b1", word: "swell", translation: "houle", sentence: "The swell, big.",
               sentenceTranslation: "La houle, grosse.", pageIndex: 4, rects: [], created: Date(timeIntervalSince1970: 0))
let export = CSV.export([e1], books: ["b1": book]).split(separator: "\n").map(String.init)
check("csv header", export.first, "word,translation,sentence,sentence_fr,book,page,saved")
check("csv row (1-based page)", export.last, "swell,houle,\"The swell, big.\",\"La houle, grosse.\",Test Book,5,1970-01-01T00:00:00Z")

// Library round trip
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glose-test-\(UUID().uuidString)")
let store = LibraryStore(url: dir.appendingPathComponent("library.json"))
var lib = Library()
lib.books["b1"] = book
lib.entries.append(Entry(bookID: "b1", word: "Swell", translation: "houle", sentence: nil, sentenceTranslation: nil,
                         pageIndex: 2, rects: [CGRect(x: 1, y: 2, width: 3, height: 4)]))
try! store.save(lib)
let loaded = store.load()
check("library round trip", String(loaded.entries.count), "1")
check("rects survive", loaded.entries.first.map { "\($0.rects)" }, "[(1.0, 2.0, 3.0, 4.0)]")
check("isSaved is case-insensitive", String(loaded.isSaved(word: "swell", bookID: "b1", pageIndex: 2)), "true")
check("isSaved checks page", String(loaded.isSaved(word: "swell", bookID: "b1", pageIndex: 3)), "false")

// BookID: stable across renames
let a = dir.appendingPathComponent("a.bin"), b = dir.appendingPathComponent("b.bin")
try! Data("same bytes".utf8).write(to: a); try! Data("same bytes".utf8).write(to: b)
check("book id ignores filename", try! BookID.compute(for: a), try! BookID.compute(for: b))
// v1 library.json (no sourcePath / fileName / pageCount) still loads
let v1 = """
{"version":1,"books":{"b1":{"id":"b1","title":"Old","path":"/Users/x/Downloads/Old.pdf","lastPage":20,"opened":"2026-11-15T10:00:00Z"}},"entries":[]}
"""
let v1URL = dir.appendingPathComponent("v1.json")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
try! Data(v1.utf8).write(to: v1URL)
let migrated = LibraryStore(url: v1URL).load().books["b1"]
check("v1: path becomes sourcePath", migrated?.sourcePath, "/Users/x/Downloads/Old.pdf")
check("v1: keeps last page", migrated.map { String($0.lastPage) }, "20")
check("v1: no copy yet", migrated?.fileName, nil)
check("v1: added falls back to opened", migrated.map { String($0.added == $0.opened) }, "true")

// Words tab
var words = Library()
words.books["a"] = BookRecord(id: "a", title: "Alpha", sourcePath: "", opened: Date(timeIntervalSince1970: 100))
words.books["b"] = BookRecord(id: "b", title: "Beta", sourcePath: "", opened: Date(timeIntervalSince1970: 200))
func entry(_ w: String, _ t: String, _ book: String, _ at: Double, _ s: String? = nil) -> Entry {
    Entry(bookID: book, word: w, translation: t, sentence: s, sentenceTranslation: nil, pageIndex: 0, rects: [],
          created: Date(timeIntervalSince1970: at))
}
words.entries = [entry("swell", "houle", "a", 1, "A big south swell."), entry("Reef", "récif", "a", 3),
                 entry("barrel", "tube", "b", 2), entry("éclat", "shine", "gone", 4)]
func names(_ g: [WordGroup]) -> String { g.map { "\($0.title ?? "-"):" + $0.entries.map(\.word).joined(separator: ",") }.joined(separator: " | ") }
check("by book: recent book first, newest word first, orphan last",
      names(words.wordGroups(sort: .byBook)), "Beta:barrel | Alpha:Reef,swell | Removed book:éclat")
check("A–Z ignores case and accents", names(words.wordGroups(sort: .alphabetical)), "-:barrel,éclat,Reef,swell")
check("recent", names(words.wordGroups(sort: .recent)), "-:éclat,Reef,barrel,swell")
check("search translation, accent-insensitive", names(words.wordGroups(sort: .recent, query: "RECIF")), "-:Reef")
check("search sentence", names(words.wordGroups(sort: .recent, query: "south")), "-:swell")
check("search no match", String(words.wordGroups(sort: .byBook, query: "zzz").count), "0")
check("word count per book", String(words.wordCount(for: "a")), "2")
check("progress", String(BookRecord(id: "p", title: "", sourcePath: "", pageCount: 101, lastPage: 50).progress), "0.5")

// Title parsing
let t = BookTitle.split("Jane Doe - 2019 - Waves and Reefs")
check("title split", t.title, "Waves and Reefs")
check("byline", t.byline, "Jane Doe · 2019")
check("plain name", BookTitle.split("notes - draft").byline, nil)

// Book copies
var files = BookFiles(directory: dir.appendingPathComponent("Books"))
files.discard = { try FileManager.default.removeItem(at: $0) }
let original = dir.appendingPathComponent("original.pdf")
try! Data("pdf bytes".utf8).write(to: original)
let name1 = try! files.importCopy(from: original, id: "x1")
try! Data("changed".utf8).write(to: original)  // a second import must not overwrite the copy
let name2 = try! files.importCopy(from: original, id: "x1")
check("copy name", name1, "x1.pdf")
check("same id twice → one copy", String(name1 == name2), "true")
check("copy not overwritten", try! String(contentsOf: files.directory.appendingPathComponent(name1), encoding: .utf8), "pdf bytes")
let copied = BookRecord(id: "x1", title: "X", sourcePath: original.path, fileName: name1)
check("hasCopy", String(files.hasCopy(copied)), "true")
try! files.trashCopy(of: copied)
check("trash removes the copy", String(files.hasCopy(copied)), "false")
check("trash keeps the original", String(FileManager.default.fileExists(atPath: original.path)), "true")
try? FileManager.default.removeItem(at: dir)

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)

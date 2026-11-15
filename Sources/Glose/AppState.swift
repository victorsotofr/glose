import AppKit
import GloseCore
import Observation
import PDFKit
import SwiftUI
import Translation
import UniformTypeIdentifiers

/// What the side panel shows for the current selection.
struct Lookup: Equatable {
    let id = UUID()
    var text: String
    var isPhrase: Bool
    var sentence: String?
    var pageIndex: Int
    var rects: [CGRect]
    var translation: String?
    var sentenceTranslation: String?
    var definition: String?
    var error: String?
}

enum LibraryTab: Equatable { case books, words }

enum SidebarTab: Equatable { case pages, contents, found }

enum TopBar: Equatable { case find, goToPage }

struct OutlineItem: Identifiable {
    let id: Int
    let label: String
    let depth: Int
    let pageIndex: Int
    let destination: PDFDestination?
}

struct FindResult: Identifiable {
    let id: Int
    let pageIndex: Int
    let snippet: String
}

enum Screen: Equatable {
    case library(LibraryTab)
    case reader
}

@MainActor @Observable
final class AppState {
    static let shared = AppState()

    let pdfView = PDFView()
    var screen: Screen = .library(.books)
    private(set) var book: BookRecord?
    private(set) var library: Library
    /// Books whose copy is gone and whose original can't be found.
    private(set) var missing: Set<String> = []
    private(set) var lookup: Lookup?
    var panelVisible = true

    // Navigation (left sidebar, find, go to page)
    var sidebarPinned = UserDefaults.standard.bool(forKey: "sidebarPinned") {
        didSet { UserDefaults.standard.set(sidebarPinned, forKey: "sidebarPinned") }
    }
    var sidebarPeek = false
    var sidebarTab: SidebarTab = .pages
    var topBar: TopBar?
    private(set) var outline: [OutlineItem] = []
    private(set) var currentPageIndex = 0
    var findQuery = ""
    private(set) var findResults: [FindResult] = []
    private(set) var findCount = 0
    private(set) var findCurrent = -1
    /// Bumped to ask the visible search field to take focus.
    private(set) var focusTick = 0
    @ObservationIgnored private var findMatches: [PDFSelection] = []
    @ObservationIgnored private var findTask: Task<Void, Never>?
    var translationConfig: TranslationSession.Configuration?
    var alert: String?
    /// nil until checked; false means the en→fr pack still has to be downloaded.
    private(set) var languagePackInstalled: Bool?

    @ObservationIgnored let files = BookFiles.default
    @ObservationIgnored private let store = LibraryStore.default
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var pageSaveTask: Task<Void, Never>?
    @ObservationIgnored private var highlights: [UUID: [(PDFPage, PDFAnnotation)]] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var launched = false

    private init() {
        library = store.load()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = Theme.canvas

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewSelectionChanged, object: pdfView, queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.selectionChanged() }
        })
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.pageChanged() }
        })
        migrateCopies()
    }

    /// v1 read books in place. Copy each one in from where it was added; mark the rest missing.
    private func migrateCopies() {
        var changed = false
        for (id, var record) in library.books where !files.hasCopy(record) {
            let source = URL(fileURLWithPath: record.sourcePath)
            if let doc = PDFDocument(url: source), let name = try? files.importCopy(from: source, id: id) {
                record.fileName = name
                record.pageCount = doc.pageCount
                library.books[id] = record
                changed = true
            } else {
                missing.insert(id)
            }
        }
        if changed { save() }
    }

    // MARK: Library

    /// Saved words of the book being read (side panel).
    var entries: [Entry] {
        guard let book else { return [] }
        return library.entries(for: book.id)
    }

    var libraryTab: LibraryTab {
        if case .library(let tab) = screen { return tab }
        return .books
    }

    func launch() {
        guard !launched else { return }
        launched = true
        let args = CommandLine.arguments
        if args.contains("--select"), let recent = library.booksByRecent.first {
            read(recent.id)
        } else if let i = args.firstIndex(of: "--screen"), i + 1 < args.count {
            switch args[i + 1] {
            case "words": screen = .library(.words)
            case "reader": if let recent = library.booksByRecent.first { read(recent.id) }
            default: screen = .library(.books)
            }
            DebugHooks.snapshotSoon()
        }
    }

    func showLibrary(_ tab: LibraryTab? = nil) {
        persistNow()
        screen = .library(tab ?? libraryTab)
    }

    /// ⌘L: library ⇄ the book being read.
    func toggleLibrary() {
        if screen == .reader { showLibrary() } else if book != nil { screen = .reader }
    }

    func showAddPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK { addBooks(panel.urls) }
    }

    /// Copies each PDF into Glose's library. A single new book opens straight away.
    func addBooks(_ urls: [URL]) {
        var added: [String] = []
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                alert = "Could not open \(url.lastPathComponent) as a PDF."
                continue
            }
            do {
                let id = try BookID.compute(for: url)
                let name = try files.importCopy(from: url, id: id)
                var record = library.books[id] ?? BookRecord(
                    id: id, title: url.deletingPathExtension().lastPathComponent, sourcePath: url.path)
                record.sourcePath = url.path
                record.fileName = name
                record.pageCount = doc.pageCount
                library.books[id] = record
                missing.remove(id)
                added.append(id)
            } catch {
                alert = "Could not add \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        save()
        if added.count == 1 { read(added[0]) } else if !added.isEmpty { showLibrary(.books) }
    }

    /// Opens a book in the reader, optionally at a saved word.
    func read(_ id: String, at entry: Entry? = nil) {
        guard var record = library.books[id] else { return }
        guard !missing.contains(id), files.hasCopy(record) else {
            locate(id)
            return
        }
        if book?.id != id {
            guard let url = files.url(for: record), let document = PDFDocument(url: url) else {
                alert = "Could not open \(record.title)."
                return
            }
            persistNow()
            removeAllHighlights()
            lookup = nil
            record.pageCount = document.pageCount
            closeFind()
            pdfView.document = document
            outline = Self.flatten(document)
            currentPageIndex = record.lastPage
            if outline.isEmpty, sidebarTab == .contents { sidebarTab = .pages }
            for saved in library.entries(for: id) { addHighlightOn(document, saved) }
        }
        record.opened = .now
        library.books[id] = record
        book = record
        screen = .reader
        save()

        let lastPage = record.lastPage
        // Let PDFView lay out before jumping.
        DispatchQueue.main.async { [pdfView] in
            if let entry {
                AppState.shared.show(entry)
            } else if let page = pdfView.document?.page(at: lastPage), pdfView.currentPage != page {
                pdfView.go(to: page)
            }
            AppState.shared.applyLaunchSelection()
        }
    }

    /// For a missing book: ask for the file again; only the same book (same id) is accepted.
    private func locate(_ id: String) {
        guard let record = library.books[id] else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = "“\(record.title)” can't be found. Locate the PDF to restore it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard (try? BookID.compute(for: url)) == id else {
            alert = "That PDF is a different file from “\(record.title)”."
            return
        }
        addBooks([url])
    }

    func removeBook(_ id: String, keepWords: Bool) {
        guard let record = library.books[id] else { return }
        if book?.id == id {
            removeAllHighlights()
            closeFind()
            outline = []
            pdfView.document = nil
            book = nil
            lookup = nil
            screen = .library(.books)
        }
        do { try files.trashCopy(of: record) } catch {
            alert = "Could not move Glose's copy to the Trash: \(error.localizedDescription)"
        }
        library.books[id] = nil
        missing.remove(id)
        if !keepWords { library.entries.removeAll { $0.bookID == id } }
        Covers.remove(id)
        save()
    }

    func revealCopy(_ id: String) {
        guard let record = library.books[id], let url = files.url(for: record) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func pageChanged() {
        guard let doc = pdfView.document, let page = pdfView.currentPage else { return }
        let index = doc.index(for: page)
        currentPageIndex = index
        guard screen == .reader, var current = book else { return }
        guard index != current.lastPage else { return }
        current.lastPage = index
        book = current
        library.books[current.id] = current
        pageSaveTask?.cancel()
        pageSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func persistNow() {
        pageSaveTask?.cancel()
        save()
    }

    private func save() {
        do { try store.save(library) } catch { alert = "Could not save your words: \(error.localizedDescription)" }
    }

    // MARK: Navigation

    private static func flatten(_ document: PDFDocument) -> [OutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        var items: [OutlineItem] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let destination = child.destination
                let pageIndex = destination?.page.map { document.index(for: $0) } ?? -1
                if let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    items.append(OutlineItem(id: items.count, label: label, depth: depth,
                                             pageIndex: pageIndex, destination: destination))
                }
                if depth < 3 { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return items
    }

    var pageCount: Int { pdfView.document?.pageCount ?? 0 }

    /// The last chapter that starts at or before the current page.
    var currentChapter: OutlineItem? {
        outline.last { $0.pageIndex >= 0 && $0.pageIndex <= currentPageIndex }
    }

    func go(to item: OutlineItem) {
        if let destination = item.destination {
            pdfView.go(to: destination)
        } else if let page = pdfView.document?.page(at: item.pageIndex) {
            pdfView.go(to: page)
        }
    }

    func goToPage(_ text: String) {
        let input = text.trimmingCharacters(in: .whitespaces)
        guard let doc = pdfView.document, !input.isEmpty else { return }
        if let n = Int(input), let page = doc.page(at: min(max(n, 1), doc.pageCount) - 1) {
            pdfView.go(to: page)
            topBar = nil
        } else if let index = (0..<doc.pageCount).first(where: { doc.page(at: $0)?.label == input }),
                  let page = doc.page(at: index) {
            pdfView.go(to: page)  // printed labels like "xii"
            topBar = nil
        }
    }

    func showGoToPage() {
        guard screen == .reader, book != nil else { return }
        topBar = .goToPage
        focusTick += 1
    }

    func toggleSidebarPinned() {
        sidebarPinned.toggle()
        sidebarPeek = false
    }

    func showSidebar(_ tab: SidebarTab) {
        sidebarTab = tab
        if !sidebarPinned { sidebarPinned = true }
    }

    func step(page delta: Int) {
        if delta > 0 { pdfView.goToNextPage(nil) } else { pdfView.goToPreviousPage(nil) }
    }

    func zoom(_ delta: Int) {
        switch delta {
        case 0: pdfView.autoScales = true
        case 1: pdfView.zoomIn(nil)
        default: pdfView.zoomOut(nil)
        }
    }

    // MARK: Find (⌘F)

    func showFind() {
        if screen != .reader || book == nil {
            screen = .library(.words)
        } else {
            topBar = .find
        }
        focusTick += 1
    }

    /// Debounced search as you type.
    func findQueryChanged() {
        findTask?.cancel()
        findTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.runFind()
        }
    }

    private func runFind() {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let doc = pdfView.document, query.count >= 2 else {
            clearFindResults()
            return
        }
        let matches = doc.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        findMatches = matches
        findCount = matches.count
        for match in matches { match.color = Theme.findHighlight }
        pdfView.highlightedSelections = matches.isEmpty ? nil : matches
        findResults = matches.prefix(500).enumerated().map { i, match in
            let page = match.pages.first.map { doc.index(for: $0) } ?? 0
            let context = (match.copy() as? PDFSelection) ?? match
            context.extend(atStart: 45)
            context.extend(atEnd: 60)
            return FindResult(id: i, pageIndex: page, snippet: ContextExtractor.normalize(context.string ?? ""))
        }
        // Start from the first match at or after the page being read.
        let start = findResults.firstIndex { $0.pageIndex >= currentPageIndex } ?? 0
        findCurrent = matches.isEmpty ? -1 : start
        if !matches.isEmpty {
            showMatch(start)
            if sidebarPinned || sidebarPeek { sidebarTab = .found }
        }
    }

    func findStep(_ delta: Int) {
        guard findCount > 0 else {
            if screen == .reader { showFind() }
            return
        }
        showMatch((findCurrent + delta + findCount) % findCount)
    }

    func showMatch(_ index: Int) {
        guard findMatches.indices.contains(index) else { return }
        findCurrent = index
        let match = findMatches[index]
        pdfView.setCurrentSelection(match, animate: false)
        pdfView.scrollSelectionToVisible(nil)
    }

    func closeFind() {
        findTask?.cancel()
        topBar = nil
        findQuery = ""
        clearFindResults()
        if sidebarTab == .found { sidebarTab = .pages }
    }

    private func clearFindResults() {
        findMatches = []
        findResults = []
        findCount = 0
        findCurrent = -1
        pdfView.highlightedSelections = nil
    }

    /// Test hook: `--select <text> --page <n>` selects text the way a double-click would,
    /// so the full selection → translation path can be checked from a script.
    func applyLaunchSelection() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--sidebar"), i + 1 < args.count {
            sidebarTab = args[i + 1] == "contents" ? .contents : .pages
            sidebarPeek = true  // not pinned: pinning would persist
        }
        if let i = args.firstIndex(of: "--find"), i + 1 < args.count {
            topBar = .find
            findQuery = args[i + 1]
            runFind()
            if args.contains("--sidebar") { sidebarTab = .found }
        }
        guard let i = args.firstIndex(of: "--select"), i + 1 < args.count, let doc = pdfView.document else { return }
        let term = args[i + 1]
        let pageNumber = args.firstIndex(of: "--page").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
        let match = doc.findString(term, withOptions: .caseInsensitive).first { sel in
            guard let n = pageNumber, let page = sel.pages.first else { return true }
            return doc.index(for: page) == n - 1
        }
        guard let match, let page = match.pages.first else { return }
        pdfView.go(to: page)
        pdfView.setCurrentSelection(match, animate: false)
        // setCurrentSelection does not always post PDFViewSelectionChanged.
        selectionChanged()
    }

    // MARK: Selection → lookup

    func selectionChanged() {
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.lookUpSelection()
        }
    }

    private func lookUpSelection() {
        guard let selection = pdfView.currentSelection, let raw = selection.string,
              let page = selection.pages.first, let doc = pdfView.document else { return }
        let text = ContextExtractor.cleanSelection(raw)
        guard !text.isEmpty, text.count <= 600 else { return }
        let pageIndex = doc.index(for: page)
        if let lookup, lookup.text == text, lookup.pageIndex == pageIndex { return }

        let words = ContextExtractor.wordCount(text)
        let rects = selection.selectionsByLine().map { $0.bounds(for: page) }.filter { !$0.isEmpty }
        var sentence: String?
        if words <= 8, let pageText = page.string {
            sentence = sentenceAround(rects: rects, on: page, pageText: pageText)
            if let s = sentence, ContextExtractor.cleanSelection(s) == text { sentence = nil }
        }
        lookup = Lookup(
            text: text, isPhrase: words > 1, sentence: sentence, pageIndex: pageIndex, rects: rects,
            definition: words <= 3 ? SystemDictionary.definition(of: text) : nil
        )
        if let lookup { DebugHooks.log("SELECTED \(lookup.text) p.\(lookup.pageIndex + 1) | \(lookup.sentence ?? "-")") }
        requestTranslation()
    }

    private func sentenceAround(rects: [CGRect], on page: PDFPage, pageText: String) -> String? {
        for rect in rects {
            let probes = [CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: rect.minX + 1, y: rect.midY)]
            for point in probes {
                let index = page.characterIndex(at: point)
                if index >= 0, let s = ContextExtractor.sentence(in: pageText, aroundUTF16: index) { return s }
            }
        }
        return nil
    }

    // MARK: Translation (Apple, on-device)

    func checkLanguagePack() async {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "fr"))
        languagePackInstalled = status == .installed
    }

    private func requestTranslation() {
        if translationConfig == nil {
            translationConfig = .init(source: Locale.Language(identifier: "en"),
                                      target: Locale.Language(identifier: "fr"))
        } else {
            translationConfig?.invalidate()
        }
    }

    /// Called by `.translationTask` each time the configuration is set or invalidated.
    func runTranslation(_ session: TranslationSession) async {
        guard let current = lookup, current.translation == nil else { return }
        var requests = [TranslationSession.Request(sourceText: current.text, clientIdentifier: "word")]
        if let sentence = current.sentence {
            requests.append(.init(sourceText: sentence, clientIdentifier: "sentence"))
        }
        do {
            if languagePackInstalled != true {
                try await session.prepareTranslation()  // Apple's one-time download prompt
                await checkLanguagePack()
            }
            let responses = try await session.translations(from: requests)
            guard lookup?.id == current.id else { return }
            for response in responses {
                if response.clientIdentifier == "word" {
                    lookup?.translation = response.targetText
                } else {
                    lookup?.sentenceTranslation = response.targetText
                }
            }
            if let done = lookup { DebugHooks.lookupFinished(done) }
        } catch is CancellationError {
        } catch {
            guard lookup?.id == current.id else { return }
            lookup?.error = "Translation failed: \(error.localizedDescription)"
            if let done = lookup { DebugHooks.lookupFinished(done) }
        }
    }

    // MARK: Saved words

    var currentIsSaved: Bool {
        guard let lookup, let book else { return false }
        return library.isSaved(word: lookup.text, bookID: book.id, pageIndex: lookup.pageIndex)
    }

    var canSave: Bool { lookup?.translation != nil && book != nil && !currentIsSaved }

    func saveCurrent() {
        guard canSave, let lookup, let translation = lookup.translation, let book else { return }
        let entry = Entry(bookID: book.id, word: lookup.text, translation: translation,
                          sentence: lookup.sentence, sentenceTranslation: lookup.sentenceTranslation,
                          pageIndex: lookup.pageIndex, rects: lookup.rects)
        library.entries.append(entry)
        addHighlight(entry)
        save()
    }

    func delete(_ entry: Entry) {
        library.entries.removeAll { $0.id == entry.id }
        for (page, annotation) in highlights.removeValue(forKey: entry.id) ?? [] { page.removeAnnotation(annotation) }
        save()
    }

    func show(_ entry: Entry) {
        guard let page = pdfView.document?.page(at: entry.pageIndex) else { return }
        if let rect = entry.rects.first {
            pdfView.go(to: rect.insetBy(dx: 0, dy: -120), on: page)
        } else {
            pdfView.go(to: page)
        }
        lookup = Lookup(text: entry.word, isPhrase: ContextExtractor.wordCount(entry.word) > 1,
                        sentence: entry.sentence, pageIndex: entry.pageIndex, rects: entry.rects,
                        translation: entry.translation, sentenceTranslation: entry.sentenceTranslation,
                        definition: SystemDictionary.definition(of: entry.word))
    }

    /// Highlights live only in memory; the PDF file is never written.
    private func addHighlight(_ entry: Entry) {
        guard let document = pdfView.document else { return }
        addHighlightOn(document, entry)
    }

    private func addHighlightOn(_ document: PDFDocument, _ entry: Entry) {
        guard let page = document.page(at: entry.pageIndex) else { return }
        highlights[entry.id] = entry.rects.map { rect in
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = Theme.highlight
            page.addAnnotation(annotation)
            return (page, annotation)
        }
    }

    private func removeAllHighlights() {
        for pairs in highlights.values { for (page, annotation) in pairs { page.removeAnnotation(annotation) } }
        highlights = [:]
    }

    // MARK: Export

    /// Exports the open book's words from the reader, every word from the library.
    func exportCSV() {
        let scoped = screen == .reader ? book : nil
        let rows = scoped.map { library.entries(for: $0.id) } ?? library.entries
        guard !rows.isEmpty else {
            alert = "No saved words to export yet."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(scoped.map { BookTitle.split($0.title).title } ?? "Glose") - words.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSV.export(rows, books: library.books).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            alert = "Could not export: \(error.localizedDescription)"
        }
    }
}

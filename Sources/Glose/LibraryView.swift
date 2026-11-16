import GloseCore
import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            header
            DashedRule()
            switch state.libraryTab {
            case .books: BooksGrid()
            case .words: WordsList()
            }
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(spacing: 22) {
            Text("GLOSE").font(Theme.mono(13, .semibold)).tracking(3).foregroundStyle(Theme.fg)
            TabButton(title: "Books", count: state.library.books.count, active: state.libraryTab == .books) {
                state.showLibrary(.books)
            }
            TabButton(title: "Words", count: state.library.entries.count, active: state.libraryTab == .words) {
                state.showLibrary(.words)
            }
            Spacer()
            if let book = state.book {
                Button("[ CONTINUE \(BookTitle.split(book.title).title.prefix(24).uppercased())  ⌘L ]") {
                    state.toggleLibrary()
                }
                .buttonStyle(BracketButtonStyle())
            }
            Button("[ + ADD  ⌘O ]") { state.showAddPanel() }.buttonStyle(BracketButtonStyle(prominent: true))
        }
        .padding(.horizontal, 32)
        .frame(height: 64)
    }
}

private struct TabButton: View {
    let title: String
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text("\(title.uppercased()) · \(count)")
                    .font(Theme.mono(11, active ? .semibold : .regular))
                    .tracking(1)
                    .foregroundStyle(active ? Theme.fg : Theme.muted)
                Rectangle().fill(active ? Theme.accent : .clear).frame(height: 2)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .padding(.top, 7)
    }
}

// MARK: Books

private struct BooksGrid: View {
    @Environment(AppState.self) private var state
    @State private var removing: BookRecord?

    var body: some View {
        let books = state.library.booksByRecent
        if books.isEmpty {
            VStack(spacing: 14) {
                Text("No books yet.").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                Text("Drop a PDF anywhere in this window, or").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                Button("[ ADD A PDF  ⌘O ]") { state.showAddPanel() }.buttonStyle(BracketButtonStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 32, alignment: .top)],
                          alignment: .leading, spacing: 40) {
                    ForEach(books) { book in
                        BookCard(book: book, isCurrent: book.id == state.book?.id,
                                 isMissing: state.missing.contains(book.id),
                                 words: state.library.wordCount(for: book.id))
                            .clickable()
                            .onTapGesture { state.read(book.id) }
                            .contextMenu {
                                Button("Read") { state.read(book.id) }
                                Button("Show Glose's Copy in Finder") { state.revealCopy(book.id) }
                                Divider()
                                Button("Remove from Library…", role: .destructive) { removing = book }
                            }
                    }
                }
                .padding(32)
            }
            .confirmationDialog(
                "Remove “\(removing.map { BookTitle.split($0.title).title } ?? "")” from the library?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                presenting: removing
            ) { book in
                let n = state.library.wordCount(for: book.id)
                Button(n == 0 ? "Remove Book" : "Remove Book, Keep Its \(n) Words") {
                    state.removeBook(book.id, keepWords: true)
                }
                if n > 0 {
                    Button("Remove Book and Its \(n) Words", role: .destructive) {
                        state.removeBook(book.id, keepWords: false)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Glose's copy goes to the Trash. The original PDF is not touched.")
            }
        }
    }
}

private struct BookCard: View {
    @Environment(AppState.self) private var state
    let book: BookRecord
    let isCurrent: Bool
    let isMissing: Bool
    let words: Int
    @State private var hovering = false

    var body: some View {
        let name = BookTitle.split(book.title)
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Theme.panel
                if isMissing {
                    Text("MISSING\nclick to locate").font(Theme.mono(10)).multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted)
                } else if let cover = Covers.image(for: book, files: state.files) {
                    Image(nsImage: cover).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Text("PDF").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(Rectangle().stroke(hovering ? Theme.fg : Theme.rule, lineWidth: 1))
            .padding(.bottom, 4)

            if isCurrent {
                Text("CONTINUE").font(Theme.mono(9, .semibold)).tracking(1).foregroundStyle(Theme.accent)
            }
            Text(name.title)
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(Theme.fg)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let byline = name.byline {
                Text(byline).font(Theme.mono(10)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            HStack {
                Text(book.pageCount > 0 ? "p.\(book.lastPage + 1) / \(book.pageCount)" : "p.\(book.lastPage + 1)")
                Spacer()
                Text("\(Int((book.progress * 100).rounded()))%")
            }
            .font(Theme.mono(10))
            .foregroundStyle(Theme.muted)
            .padding(.top, 2)
            SquaresBar(progress: book.progress)
            Text(words == 1 ? "1 word" : "\(words) words").font(Theme.mono(10)).foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Progress drawn as a row of squares.
struct SquaresBar: View {
    let progress: Double
    var count = 20

    var body: some View {
        let filled = progress > 0 ? max(1, Int((progress * Double(count)).rounded())) : 0
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Rectangle().fill(i < filled ? Theme.accent : Theme.rule).frame(height: 6)
            }
        }
    }
}

// MARK: Words

private struct WordsList: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var sort: WordSort = .byBook
    @FocusState private var searchFocused: Bool

    var body: some View {
        let groups = state.library.wordGroups(sort: sort, query: query)
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("/").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    TextField("search words, translations, sentences", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(12))
                        .focused($searchFocused)
                        .onExitCommand { query = ""; searchFocused = false }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .overlay(Rectangle().stroke(Theme.rule, lineWidth: 1))
                .frame(maxWidth: 360)

                HStack(spacing: 6) {
                    ForEach(WordSort.allCases, id: \.self) { option in
                        Button(option.rawValue.uppercased()) { sort = option }
                            .buttonStyle(ToggleChipStyle(active: sort == option))
                    }
                }
                Spacer()
                Button("[ EXPORT CSV ]") { state.exportCSV() }
                    .buttonStyle(BracketButtonStyle())
                    .disabled(state.library.entries.isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .onChange(of: state.focusTick) { searchFocused = true }
            .onAppear { if state.focusTick > 0 { searchFocused = true } }

            if groups.isEmpty {
                Text(state.library.entries.isEmpty
                     ? "No saved words yet. Open a book, double-click a word, press ⌘S."
                     : "Nothing matches “\(query)”.")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    WordRow(entry: entry, showBook: group.title == nil)
                                }
                            } header: {
                                if let title = group.title {
                                    GroupHeader(title: BookTitle.split(title).title, count: group.entries.count)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

private struct GroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased()).font(Theme.mono(10, .semibold)).tracking(1).foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text("· \(count)").font(Theme.mono(10)).foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 10)
            DashedRule().padding(.horizontal, 32)
        }
        .background(Theme.bg)
    }
}

private struct WordRow: View {
    @Environment(AppState.self) private var state
    let entry: Entry
    let showBook: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(entry.word).font(Theme.mono(13, .medium)).foregroundStyle(Theme.fg)
                .frame(width: 190, alignment: .leading)
            Text(entry.translation).font(Theme.mono(12, .semibold)).foregroundStyle(Theme.fg)
                .frame(width: 190, alignment: .leading)
            Text(entry.sentence ?? "").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showBook, let title = state.library.books[entry.bookID]?.title {
                Text(BookTitle.split(title).title).font(Theme.mono(10)).foregroundStyle(Theme.muted)
                    .frame(width: 160, alignment: .trailing)
            }
            Text("p.\(entry.pageIndex + 1)").font(Theme.mono(10)).foregroundStyle(Theme.muted)
                .frame(width: 48, alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.horizontal, 32)
        .padding(.vertical, 9)
        .background(hovering ? Theme.rule.opacity(0.45) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .clickable()
        .onTapGesture { if state.library.books[entry.bookID] != nil { state.read(entry.bookID, at: entry) } }
        .contextMenu {
            if state.library.books[entry.bookID] != nil {
                Button("Open in Book") { state.read(entry.bookID, at: entry) }
            }
            Button("Delete Word", role: .destructive) { state.delete(entry) }
        }
    }
}

private struct ToggleChipStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(10, active ? .semibold : .regular))
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(active ? Theme.bg : Theme.muted)
            .background(active ? Theme.fg : .clear)
            .overlay(Rectangle().stroke(active ? Theme.fg : Theme.rule, lineWidth: 1))
            .contentShape(Rectangle())
            .clickable()
    }
}

import GloseCore
import PDFKit
import SwiftUI

/// The PDF plus Preview-style navigation: left sidebar (pinned, or peeking when the
/// cursor touches the left edge), ⌘F / ⌥⌘G bar on top, page indicator at the bottom.
struct ReaderCanvas: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if state.sidebarPinned {
                    ReaderSidebar().frame(width: 230)
                    Rectangle().fill(Theme.rule).frame(width: 1)
                }
                ZStack {
                    PDFContainer(view: state.pdfView, hidden: state.screen != .reader)
                    VStack(spacing: 0) {
                        if let bar = state.topBar {
                            TopBarView(mode: bar)
                            Rectangle().fill(Theme.rule).frame(height: 1)
                        }
                        Spacer()
                        PageIndicator().padding(.bottom, 14)
                    }
                }
            }

            if !state.sidebarPinned {
                // Hot edge: touching the left edge slides the sidebar in.
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside, state.book != nil { withAnimation(.easeOut(duration: 0.15)) { state.sidebarPeek = true } }
                    }
                if state.sidebarPeek {
                    HStack(spacing: 0) {
                        ReaderSidebar().frame(width: 230)
                        Rectangle().fill(Theme.rule).frame(width: 1)
                    }
                    .transition(.move(edge: .leading))
                    .onHover { inside in
                        if !inside { withAnimation(.easeIn(duration: 0.15)) { state.sidebarPeek = false } }
                    }
                }
            }
        }
    }
}

// MARK: Sidebar

struct ReaderSidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                SidebarTabButton(title: "Pages", active: state.sidebarTab == .pages) { state.sidebarTab = .pages }
                if !state.outline.isEmpty {
                    SidebarTabButton(title: "Contents", active: state.sidebarTab == .contents) { state.sidebarTab = .contents }
                }
                if state.findCount > 0 {
                    SidebarTabButton(title: "Found · \(state.findCount)", active: state.sidebarTab == .found) {
                        state.sidebarTab = .found
                    }
                }
                Spacer(minLength: 0)
                Button { state.toggleSidebarPinned() } label: {
                    Text(state.sidebarPinned ? "⇤" : "⇥")
                        .font(Theme.mono(12))
                        .foregroundStyle(state.sidebarPinned ? Theme.accent : Theme.muted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickable()
                .help(state.sidebarPinned ? "Unpin: show on hover at the left edge (⌥⌘S)" : "Keep the sidebar open (⌥⌘S)")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            DashedRule()

            switch state.sidebarTab {
            case .pages: ThumbnailStrip(pdfView: state.pdfView)
            case .contents: ContentsList()
            case .found: FoundList()
            }
        }
        .background(Theme.panel)
    }
}

private struct SidebarTabButton: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title.uppercased())
                    .font(Theme.mono(10, active ? .semibold : .regular))
                    .tracking(0.8)
                    .foregroundStyle(active ? Theme.fg : Theme.muted)
                    .fixedSize()
                Rectangle().fill(active ? Theme.accent : .clear).frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .padding(.top, 6)
    }
}

/// Apple's own page thumbnails (the same component as Preview), wired to the reader.
struct ThumbnailStrip: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = pdfView
        view.thumbnailSize = CGSize(width: 140, height: 190)
        view.maximumNumberOfColumns = 1
        view.backgroundColor = .clear
        view.allowsDragging = false
        view.allowsMultipleSelection = false
        // PDFThumbnailView only follows page changes; on open, centre it on the current page.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak view, pdfView] in
            guard let view, let doc = pdfView.document, let page = pdfView.currentPage else { return }
            Self.scroll(view, to: doc.index(for: page))
        }
        return view
    }

    private static func scroll(_ view: NSView, to index: Int) {
        if let collection = view as? NSCollectionView {
            let path = IndexPath(item: index, section: 0)
            guard index < collection.numberOfItems(inSection: 0) else { return }
            collection.scrollToItems(at: [path], scrollPosition: .centeredVertically)
            return
        }
        for sub in view.subviews { scroll(sub, to: index) }
    }

    func updateNSView(_ view: PDFThumbnailView, context: Context) {
        if view.pdfView !== pdfView { view.pdfView = pdfView }
    }
}

private struct ContentsList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let current = state.currentChapter?.id
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.outline) { item in
                        ContentsRow(item: item, isCurrent: item.id == current).id(item.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
        }
    }
}

private struct ContentsRow: View {
    @Environment(AppState.self) private var state
    let item: OutlineItem
    let isCurrent: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.label)
                .font(Theme.mono(item.depth == 0 ? 11 : 10, isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Theme.accent : (item.depth == 0 ? Theme.fg : Theme.muted))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.pageIndex >= 0 {
                Text("\(item.pageIndex + 1)").font(Theme.mono(9)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.leading, 14 + CGFloat(item.depth) * 12)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(hovering ? Theme.rule.opacity(0.5) : .clear)
        .overlay(alignment: .leading) {
            if isCurrent { Rectangle().fill(Theme.accent).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .clickable()
        .onTapGesture { state.go(to: item) }
    }
}

private struct FoundList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.findResults) { result in
                        FoundRow(result: result, isCurrent: result.id == state.findCurrent).id(result.id)
                    }
                    if state.findCount > state.findResults.count {
                        Text("+ \(state.findCount - state.findResults.count) more")
                            .font(Theme.mono(10)).foregroundStyle(Theme.muted).padding(14)
                    }
                }
            }
            .onChange(of: state.findCurrent) { _, current in
                withAnimation { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }
}

private struct FoundRow: View {
    @Environment(AppState.self) private var state
    let result: FindResult
    let isCurrent: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("p.\(result.pageIndex + 1)").font(Theme.mono(9, .medium)).foregroundStyle(isCurrent ? Theme.accent : Theme.muted)
            Text(highlighted).font(Theme.mono(10)).foregroundStyle(Theme.muted).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isCurrent ? Theme.rule.opacity(0.7) : hovering ? Theme.rule.opacity(0.4) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .clickable()
        .onTapGesture { state.showMatch(result.id) }
    }

    private var highlighted: AttributedString {
        var text = AttributedString(result.snippet)
        let query = state.findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].foregroundColor = Theme.fg
            text[range].font = Theme.mono(10, .bold)
        }
        return text
    }
}

// MARK: Top bar (find / go to page)

private struct TopBarView: View {
    @Environment(AppState.self) private var state
    let mode: TopBar
    @State private var pageText = ""
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 12) {
            switch mode {
            case .find:
                Text("FIND").font(Theme.mono(10, .semibold)).tracking(1).foregroundStyle(Theme.muted)
                TextField("word or phrase", text: $state.findQuery)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(13))
                    .focused($focused)
                    .onChange(of: state.findQuery) { state.findQueryChanged() }
                    .onSubmit { state.findStep(1) }
                Text(findStatus).font(Theme.mono(11)).foregroundStyle(Theme.muted).fixedSize()
                Button("‹") { state.findStep(-1) }.buttonStyle(BracketButtonStyle()).disabled(state.findCount == 0)
                    .help("Previous (⇧⌘G)")
                Button("›") { state.findStep(1) }.buttonStyle(BracketButtonStyle()).disabled(state.findCount == 0)
                    .help("Next (Return, ⌘G)")
            case .goToPage:
                Text("GO TO PAGE").font(Theme.mono(10, .semibold)).tracking(1).foregroundStyle(Theme.muted)
                TextField("\(state.currentPageIndex + 1)", text: $pageText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(13))
                    .frame(width: 70)
                    .focused($focused)
                    .onSubmit { state.goToPage(pageText) }
                Text("/ \(state.pageCount)").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                Spacer()
            }
            Button("ESC") { mode == .find ? state.closeFind() : (state.topBar = nil) }
                .buttonStyle(BracketButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .onExitCommand { mode == .find ? state.closeFind() : (state.topBar = nil) }
        .onAppear { focused = true }
        .onChange(of: state.focusTick) { focused = true }
    }

    private var findStatus: String {
        let q = state.findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.count < 2 { return "" }
        if state.findCount == 0 { return "no match" }
        return "\(state.findCurrent + 1) / \(state.findCount)"
    }
}

// MARK: Bottom indicator

private struct PageIndicator: View {
    @Environment(AppState.self) private var state
    @State private var hovering = false

    var body: some View {
        if state.book != nil, state.pageCount > 0 {
            Button { state.showGoToPage() } label: {
                HStack(spacing: 8) {
                    Text("\(state.currentPageIndex + 1) / \(state.pageCount)")
                    if let chapter = state.currentChapter {
                        Text("·")
                        Text(chapter.label).lineLimit(1).frame(maxWidth: 320)
                    }
                }
                .font(Theme.mono(10))
                .foregroundStyle(hovering ? Theme.fg : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.panel.opacity(0.92))
                .overlay(Rectangle().stroke(Theme.rule, lineWidth: 1))
                .fixedSize()
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .clickable()
            .help("Go to page (⌥⌘G)")
        }
    }
}

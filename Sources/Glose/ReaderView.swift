import GloseCore
import PDFKit
import SwiftUI
import Translation

struct ReaderView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        ZStack {
            // The reader stays mounted so PDFView keeps its layout and scroll position.
            HStack(spacing: 0) {
                ReaderCanvas()
                if state.panelVisible {
                    Rectangle().fill(Theme.rule).frame(width: 1)
                    SidePanel().frame(width: 280)
                }
            }
            if state.screen != .reader || state.book == nil {
                LibraryView()
            }
        }
        .background(Theme.bg)
        .navigationTitle(state.screen == .reader ? (state.book.map { BookTitle.split($0.title).title } ?? "Glose") : "Glose")
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfs.isEmpty else { return false }
            state.addBooks(pdfs)
            return true
        }
        .translationTask(state.translationConfig) { session in
            await state.runTranslation(session)
        }
        .onAppear { state.launch() }
        .task { await state.checkLanguagePack() }
        .alert(state.alert ?? "", isPresented: Binding(get: { state.alert != nil }, set: { if !$0 { state.alert = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

struct PDFContainer: NSViewRepresentable {
    let view: PDFView
    func makeNSView(context: Context) -> PDFView { view }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

import GloseCore
import SwiftUI

struct SidePanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { state.showLibrary() } label: {
                    Text("← LIBRARY").font(Theme.mono(11, .semibold)).tracking(1).foregroundStyle(Theme.fg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to your books and words (⌘L)")
                Spacer()
                Text("EN → FR").font(Theme.mono(10)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            DashedRule()

            if state.languagePackInstalled == false {
                LanguagePackNotice()
                DashedRule()
            }
            ScrollView {
                LookupCard().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            DashedRule()
            SavedList().frame(maxHeight: .infinity)
        }
        .background(Theme.panel)
    }
}

private struct LookupCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let lookup = state.lookup {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(number: 1, title: lookup.isPhrase ? "Phrase" : "Word")
                Text(lookup.text)
                    .font(Theme.mono(lookup.isPhrase ? 15 : 20, .semibold))
                    .foregroundStyle(Theme.fg)
                    .textSelection(.enabled)
                Text("→ " + (lookup.translation ?? "…"))
                    .font(Theme.mono(lookup.isPhrase ? 14 : 17, .medium))
                    .foregroundStyle(Theme.accent)
                    .textSelection(.enabled)

                if let error = lookup.error {
                    Text(error).font(Theme.mono(11)).foregroundStyle(.red)
                }

                HStack {
                    if state.currentIsSaved {
                        Text("[ SAVED ✓ ]").font(Theme.mono(11, .medium)).foregroundStyle(Theme.accent)
                    } else {
                        Button("[ SAVE  ⌘S ]") { state.saveCurrent() }
                            .buttonStyle(BracketButtonStyle(prominent: true))
                            .disabled(!state.canSave)
                    }
                    Spacer()
                    Text("p.\(lookup.pageIndex + 1)").font(Theme.mono(10)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)

                if let sentence = lookup.sentence {
                    SectionLabel(number: 2, title: "In context").padding(.top, 6)
                    Text(emphasized(sentence, term: lookup.text))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                    if let fr = lookup.sentenceTranslation {
                        Text("→ " + fr)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.fg)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                }

                if let definition = lookup.definition {
                    DefinitionBlock(number: lookup.sentence == nil ? 2 : 3, text: definition)
                        .padding(.top, 6)
                        .id(lookup.id)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(number: 1, title: "Word")
                Text("Double-click a word in the book, or select a phrase.")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
            }
        }
    }

    private func emphasized(_ sentence: String, term: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].foregroundColor = Theme.fg
            text[range].font = Theme.mono(12, .bold)
        }
        return text
    }
}

private struct DefinitionBlock: View {
    let number: Int
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    SectionLabel(number: number, title: "Definition")
                    Text(expanded ? "−" : "+").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                Text(text)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SavedList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let entries = state.entries
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(number: 4, title: "Saved · \(entries.count)")
                Spacer()
                Button("[ CSV ]") { state.exportCSV() }
                    .buttonStyle(BracketButtonStyle())
                    .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if entries.isEmpty {
                Text("Saved words show up here, newest first.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { SavedRow(entry: $0) }
                    }
                }
            }
        }
    }
}

private struct SavedRow: View {
    @Environment(AppState.self) private var state
    let entry: Entry
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.word).font(Theme.mono(12, .medium)).foregroundStyle(Theme.fg)
                Text(entry.translation).font(Theme.mono(11)).foregroundStyle(Theme.accent)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text("p.\(entry.pageIndex + 1)").font(Theme.mono(10)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(hovering ? Theme.rule.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { state.show(entry) }
        .contextMenu {
            Button("Go to page \(entry.pageIndex + 1)") { state.show(entry) }
            Button("Delete", role: .destructive) { state.delete(entry) }
        }
    }
}

private struct LanguagePackNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FRENCH PACK NOT DOWNLOADED")
                .font(Theme.mono(10, .semibold)).tracking(1).foregroundStyle(Theme.accent)
            Text("Select a word and accept macOS's download prompt (one time, then offline). Or: System Settings › General › Language & Region › Translation Languages.")
                .font(Theme.mono(11)).foregroundStyle(Theme.muted).lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import AppKit
import SwiftUI

@main
struct GloseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        Window("Glose", id: "main") {
            ReaderView()
                .environment(state)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1470, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Books…") { state.showAddPanel() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Word") { state.saveCurrent() }
                    .keyboardShortcut("s")
                    .disabled(!state.canSave)
                Button("Export Words as CSV…") { state.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .textEditing) {
                Button("Find…") { state.showFind() }.keyboardShortcut("f")
                Button("Find Next") { state.findStep(1) }.keyboardShortcut("g")
                Button("Find Previous") { state.findStep(-1) }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                Button("Back") { state.pdfView.goBack(nil) }.keyboardShortcut("[")
                Button("Forward") { state.pdfView.goForward(nil) }.keyboardShortcut("]")
                Divider()
                Button("Previous Page") { state.step(page: -1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Next Page") { state.step(page: 1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("Go to Page…") { state.showGoToPage() }.keyboardShortcut("g", modifiers: [.command, .option])
            }
            CommandGroup(after: .sidebar) {
                Button(state.sidebarPinned ? "Hide Sidebar" : "Show Sidebar") { state.toggleSidebarPinned() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Page Thumbnails") { state.showSidebar(.pages) }.keyboardShortcut("2", modifiers: [.command, .option])
                Button("Table of Contents") { state.showSidebar(.contents) }.keyboardShortcut("3", modifiers: [.command, .option])
                Divider()
                Button("Zoom In") { state.zoom(1) }.keyboardShortcut("=")
                Button("Zoom Out") { state.zoom(-1) }.keyboardShortcut("-")
                Button("Fit Width") { state.zoom(0) }.keyboardShortcut("0")
                Divider()
                Button(state.screen == .reader ? "Library" : "Back to Book") { state.toggleLibrary() }
                    .keyboardShortcut("l")
                    .disabled(state.screen != .reader && state.book == nil)
                Button(state.panelVisible ? "Hide Translation Panel" : "Show Translation Panel") {
                    state.panelVisible.toggle()
                }
                .keyboardShortcut("\\")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }
        MainActor.assumeIsolated { AppState.shared.addBooks(pdfs) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.persistNow() }
    }
}

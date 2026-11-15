# Glose

Native macOS PDF reader with an English→French side panel. Opens on a library (Books grid with covers and progress, Words tab with every saved word); ⌘L switches between library and reader. Double-click a word (or select a phrase) and the panel shows its translation, the sentence it sits in (plus that sentence translated), and the macOS dictionary definition. Saved words are highlighted in the book and exportable as CSV.

## Rules
- **Offline only.** Translation is Apple's on-device `Translation` framework (en→fr pack, downloaded once). No network APIs, no API keys.
- **Glose reads its own copy.** Adding a book copies it to `Books/<bookID>.pdf`; removing one trashes that copy only, never the original.
- **Never write the PDF.** Highlights are in-memory `PDFAnnotation`s redrawn on open; never call `PDFDocument.write`.
- **No book content in the repo.** `.gitignore` excludes `*.pdf`; tests use synthetic text only.

## Layout
- `Sources/GloseCore/` pure logic, unit-tested: `ContextExtractor` (selection cleanup, line-break hyphen rejoin, sentence around a UTF-16 offset), `CSV`, `Library` (`BookRecord`, `Entry`, `LibraryStore` JSON v2 that still reads v1, `wordGroups` sort/search, `BookTitle` "Author - Year - Title" split, `BookID` = SHA-256 of first MB + size), `BookFiles` (the copies).
- `Sources/Glose/` SwiftUI app: `AppState` (owns the `PDFView`, selection → `Lookup` → translation → save), `ReaderView`, `SidePanel`, `LibraryView` (Books/Words tabs), `ReaderNavigation` (left sidebar with `PDFThumbnailView` / outline / find results, hot left edge, ⌘F and ⌥⌘G top bar, page indicator), `Covers` (page-1 PNG cache), `Theme`, `Dictionary` (`DCSCopyTextDefinition`), `DebugHooks`.
- On macOS 15 a `TranslationSession` only comes from `.translationTask(config)` in `ReaderView`; `AppState.requestTranslation()` sets or invalidates the config, which reruns `runTranslation`.
- `ReaderView` keeps the PDFView mounted and lays `LibraryView` over it, so the reader keeps its layout and scroll position.
- Data in `~/Library/Application Support/Glose/`: `library.json`, `Books/`, `Covers/`. On launch, v1 books without a copy are copied from `sourcePath` or marked missing.

## Build (Command Line Tools only, no Xcode or SwiftPM: `swiftc` driven by a script)
```
scripts/build.sh            # build/Glose.app
scripts/build.sh --install  # + /Applications/Glose.app
scripts/build.sh --test     # GloseCore tests (plain assertion runner in Tests/main.swift)
scripts/make-icon.sh        # regenerate Resources/AppIcon.icns (deep blue, white mono "g")
```
`scripts/toolchain-fix/` hides a stale `usr/include/swift/module.modulemap` that some CLT upgrades leave behind (it redefines `SwiftBridging`) through a VFS overlay; on a clean toolchain the overlay is harmless.

## Checking the real app from a script
`build/Glose.app/Contents/MacOS/Glose --screen books|words|reader --snapshot <out.png>` snapshots a screen after 2.5 s; add `--sidebar pages|contents` (peeks it open, does not pin) and `--find <query>`. `--select <text> --page <n> --snapshot <out.png>` opens the most recent book, selects the text like a double-click, logs `SELECTED`/`LOOKUP` lines to stderr and writes window PNGs (`out-pending.png` after 2 s, `out.png` once translated). No screen-recording permission needed.
These runs use the real library: back up `library.json` first, since reading moves `lastPage`.

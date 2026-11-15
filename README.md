<img src="docs/icon.png" width="96" alt="Glose icon">

# Glose

A lean macOS PDF reader for reading English books with French at hand. The book fills the window; double-click a word and a side panel shows its translation, the sentence it sits in, and that sentence in French. Fully offline: translation runs on-device with Apple's Translation framework.

## Features

- **Translate in place.** Double-click a word or select a phrase: French translation, sentence in context (translated too), and the English dictionary definition.
- **Save words.** ⌘S keeps the word with its sentence and page, highlights it in the book, and adds it to your list. Export everything as CSV (for Anki or a spreadsheet).
- **Library.** Your books with covers and reading progress, and every saved word across books, grouped by book, A–Z or recent, with search.
- **Navigate like Preview.** Page thumbnails and table of contents in a sidebar that appears at the left edge, ⌘F find with a results list, go to page, back/forward, zoom.

## Install

Requires macOS 15+ and the Xcode Command Line Tools (`xcode-select --install`). No Xcode needed.

```sh
git clone https://github.com/victorsotofr/glose.git
cd glose
scripts/build.sh --install   # builds Glose.app into /Applications
```

On the first translation, macOS asks to download the English–French language pack once (also in System Settings › General › Language & Region › Translation Languages).

## Shortcuts

| | |
|---|---|
| ⌘O | Add PDFs |
| ⌘L | Library ⇄ book |
| ⌘S | Save word |
| ⌘F / ⌘G / ⇧⌘G | Find, next, previous |
| ⌥⌘S · ⌥⌘2 · ⌥⌘3 | Sidebar, thumbnails, contents |
| ⌥⌘G | Go to page |
| ⌘[ / ⌘] | Back / forward |
| ⌘\ | Translation panel |
| ⇧⌘E | Export words as CSV |

## How it works

SwiftUI + PDFKit, Apple's `Translation` (on-device), `NaturalLanguage` for sentence boundaries, and the built-in macOS dictionary. Glose keeps its own copy of each book and a JSON file of your words in `~/Library/Application Support/Glose/`; PDFs are never modified. No network, no accounts, no API keys.

```sh
scripts/build.sh --test   # unit tests for the core logic
```

Development notes are in [AGENTS.md](AGENTS.md).

## License

MIT

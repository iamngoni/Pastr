# Pastr

A lightweight macOS clipboard manager that lives in your menu bar. Pastr tracks your clipboard history and surfaces it in a sleek bottom-anchored panel, so you can paste anything you've copied — instantly.

## Features

- **Clipboard history** — captures text, images, links, rich text, and files
- **Quick panel** — global hotkey (default `⌘B`) opens a full-width bottom panel
- **Pinned items** — pin frequently used snippets; they sync across your Macs via iCloud
- **Tags & collections** — organise clipboard items your way
- **Backup & restore** — export your history with optional encryption
- **Syntax highlighting** — code snippets render with highlight
- **On-device intelligence** — OCR on image clips, search-by-meaning, automatic classification/tagging, and sensitive-content detection — all processed locally
- **Apple Intelligence** — generate titles, summarise clips, and "Paste As…" transforms (clean up, rewrite, Markdown, JSON, translate) on supported hardware (macOS 26+)
- **Hotkey customisation** — change the activation shortcut in Settings
- **Hot corners** — optionally open the panel by moving the cursor to a screen corner

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (for building from source; Xcode 26 / macOS 26 SDK required to build the Apple Intelligence features)

## Building

```bash
# Open in Xcode
open Pastr.xcodeproj

# Or build a release copy to /Applications from the command line
bash Scripts/build.sh
```

The build script archives the project and copies `Pastr.app` to `/Applications`.

## Getting started

1. Launch Pastr — a menu bar icon appears.
2. Grant clipboard access when prompted (required for monitoring).
3. Press `⌘B` to open the panel.
4. Click or use arrow keys to select an item; press `Return` to paste it into the active app.
5. Open **Settings** from the menu bar icon to customise the hotkey, history limits, iCloud sync, and more.

## Project structure

```
Pastr/
├── AppDelegate.swift          # App lifecycle and background agent setup
├── ClipboardMonitor.swift     # NSPasteboard polling and change detection
├── ClipboardHistoryStore.swift# In-memory + persisted history state
├── ClipboardItem.swift        # Core data model
├── PanelWindowController.swift# Floating bottom panel window
├── PanelView.swift            # SwiftUI panel UI
├── PanelViewModel.swift       # Panel state and selection logic
├── PasteController.swift      # Writes to pasteboard and fires Cmd+V
├── PasteQueue.swift           # Queued paste sequencing
├── CollectionStore.swift      # Collections management
├── PinnedStore.swift          # Pinned items (CloudKit-backed)
├── TagStore.swift             # Tag management
├── BackupManager.swift        # Export / import with encryption
├── HotKeyManager.swift        # Global hotkey registration
├── SettingsStore.swift        # User preferences
├── SettingsView.swift         # Settings UI
├── Intelligence/              # On-device AI (OCR, embeddings, classifier, Apple Intelligence)
└── ...
```

## Data & privacy

Pastr stores clipboard history locally using Core Data. Pinned items can optionally sync to iCloud via CloudKit — everything else stays on-device. No analytics are collected beyond opt-in crash reporting (Sentry).

All intelligence features run **entirely on-device** — OCR (Vision), search-by-meaning and classification (NaturalLanguage), and Apple Intelligence (FoundationModels). Clip contents are never sent to any server, and enrichment data (`ai-enrichment.json`) is stored locally and never synced.

## License

MIT

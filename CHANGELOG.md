# Changelog

## v1.5 (2026-08-31)
- Moved clipboard search and semantic matching off the main thread.
- Moved CloudKit, on-device intelligence persistence, and image preview decoding off the main thread.
- Reduced SwiftUI invalidations by publishing clipboard and enrichment updates in batches.
- Improved responsiveness for large text, image, rich-text, and synced clipboard histories.
- Fixed startup, search-field, display-sizing, and link-preview error-reporting hangs.

## v1.3 (2026-06-20)
On-device intelligence — everything runs locally; your clipboard never leaves your Mac.

**Tier 1 — works on every supported Mac (macOS 14+):**
- Recognize text in image clips with on-device OCR, making screenshots searchable and copyable.
- Search clips by meaning, not just exact text, using on-device sentence embeddings.
- Automatic content classification (code, link, email, command, JSON, color, …) with optional auto-tagging.
- Sensitive-content detection for API keys, passwords, private keys, and card numbers, with optional blur-until-revealed in the panel.

**Tier 2 — Apple Intelligence (macOS 26+ on supported hardware, with graceful fallback):**
- Generate a short title for any clip.
- Summarize long clips.
- "Paste As…" transforms: clean up grammar, rewrite professionally/friendlier, make concise, bullet points, Markdown, JSON, extract action items, translate to English.

**Settings:**
- New Intelligence section with granular on/off controls for every feature and a live Apple Intelligence availability status.

## v1.2 (2026-01-14)
- Removed in-app update checks for Mac App Store distribution.
- Added "Maximum items" setting in History section (500, 1k, 5k, 10k, Unlimited). Default is Unlimited.
- Added performance warning when history exceeds 15,000 items.
- Fixed app hang when playing sounds by moving audio playback to background thread.
- Fixed app hang during clipboard monitoring by moving pasteboard polling to background thread.
- Fixed app hang when loading app icons by adding async icon cache.
- Fixed app hang during rich text preview by caching parsed AttributedString objects.
- Fixed app hang during search filtering by caching filtered results.
- Version number in Settings now displays dynamically from the app bundle.

## 2026-01-09
- Set minimum macOS deployment target to Sonoma (14.0).
- Sync full clipboard history to iCloud (not just pinned items).
- Added manual Sync Now with progress, success toast, and error feedback.
- Enabled drag-and-drop of clipboard items into other apps.
- Added quick preview on hover/space and a Preview context menu action.
- Added backup/export tools with optional encryption and restore support.
- Strengthened backup encryption key derivation (PBKDF2).
- Fixed export/backup dialogs to present reliably from the settings window.
- Added Sentry crash reporting.
- Registered Pastr backup file type and enabled user-selected file read/write for save panels.
- Added a custom document icon for .pastrbackup files.
- Added a Quick Preview toggle to disable hover previews.
- Updated Settings About link to the Pastr website.
- Improved selected-card highlight visibility.

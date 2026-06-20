# Changelog

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

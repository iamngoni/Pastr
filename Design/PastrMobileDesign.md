# Pastr Mobile Design

Date: 2026-06-09
Source app: Pastr macOS SwiftUI menu bar app
Target: iPhone app plus iOS custom keyboard extension

## Desktop Source Of Truth

The current Mac app is a fast clipboard surface, not a document app. It runs as a menu bar accessory, captures clipboard items, and opens a bottom floating panel with search, History, Collections, Tags, source-app metadata, previews, pinning, and direct paste back into the previous app.

Mobile Pastr should preserve that product model: copied things become reusable clips, clips can be organized, and the fastest insertion path is always one gesture away. The shell changes because iOS cannot behave like the Mac app:

- No always-on global clipboard monitor.
- No global floating panel over every app.
- No simulated systemwide Cmd+V paste action.
- A system keyboard extension can insert text into the active field through `UITextDocumentProxy`.

## Product Shape

Pastr for mobile has two surfaces:

1. Main app: library, setup, import/paste, organization, preview, sync, and privacy controls.
2. Keyboard extension: fast text and link insertion from pinned clips and collections while typing in other apps.

The first launch should make the keyboard relationship explicit: Pastr Mobile is useful as a normal clip library, but systemwide insertion requires enabling the Pastr keyboard in iOS Settings. Full Access should be optional and explained as needed only for synced/shared clip access, not for basic typing.

## Visual Direction

Carry the Mac app's dark glass clipboard strip into a native iPhone shell, but make it touch-first and less hover-dependent.

- Background: graphite black, not pure black.
- Surface: layered dark material cards with thin borders.
- Accents: Pastr blue for focus, mint for text clips, amber for files/imports, violet for links.
- Typography: San Francisco, compact hierarchy, no marketing hero.
- Touch: 44 pt minimum controls, bottom-heavy actions, swipe actions for pin/delete.

## Screen 1: Library

Purpose: daily home for searching and organizing clips.

Layout:

- Top bar with "Pastr", sync state, and settings icon.
- Search field below the title, always visible.
- Segmented filter row: History, Pinned, Links, Files.
- Vertical clip feed, grouped by recency.
- Each clip row shows type tint, source, relative time, one content preview, and pin state.
- Bottom tab bar: Library, Collections, Keyboard, Settings.

Primary actions:

- Tap a clip to open detail.
- Long press for Copy, Insert In Keyboard, Add to Collection, Delete.
- Swipe right to pin, swipe left to delete.
- Use a system paste control/import action rather than background pasteboard reads.

## Screen 2: Keyboard Extension

Purpose: insert saved clips while typing anywhere third-party keyboards are allowed.

Layout:

- Top utility strip with Pastr mark, search, collections, and compact status.
- Horizontal clip tray above the keys for recent/pinned clips.
- Standard typing keys remain available so the keyboard satisfies input functionality.
- Globe/next-keyboard key is persistent.
- Insert key writes selected text/link through `textDocumentProxy.insertText`.

Keyboard constraints:

- Must remain useful without network access and without requiring Full Access.
- Must provide a way to progress to the next keyboard.
- Should only insert plain text or URL strings. Rich text, images, and files should open the main app/share flow instead.
- Should not collect typed content beyond what is necessary for local keyboard behavior.

## Screen 3: Keyboard Setup

Purpose: reduce rejection and support risk by making permissions obvious.

Layout:

- Setup status checklist:
  - Add Pastr Keyboard.
  - Allow Full Access, optional for synced collections.
  - Choose default keyboard collection.
- Privacy explanation below the checklist.
- Buttons for Open Keyboard Settings, Test Keyboard, and Manage Synced Clips.

Copy principles:

- Do not imply Pastr can paste into every secure field. Some apps and secure inputs disable third-party keyboards.
- Do not present Full Access as required for basic typing.
- Be explicit that synced clips use iCloud/App Group storage.

## Architecture

Targets:

- `PastrMobile`: iOS SwiftUI app.
- `PastrKeyboard`: iOS Custom Keyboard extension.
- Shared package/module: clip model, collection model, serialization, filtering, privacy rules.

Shared storage:

- Use an App Group for clips available to the keyboard extension.
- Keep local keyboard cache small: pinned clips, selected collection, and recent text/link clips.
- Use CloudKit/iCloud from the containing app to sync with Mac. The keyboard reads the app-group cache written by the app.

Pasteboard policy:

- Use user-initiated paste/import flows in the main app.
- Use `UIPasteControl` where appropriate on iOS 16+ to avoid surprise pasteboard prompts.
- Use pasteboard type checks before reading content.
- Do not poll the system pasteboard in the background.

Keyboard insertion policy:

- Plain text: insert directly.
- Links: insert URL or saved label text.
- Rich text: offer plain-text insertion first.
- Images/files: show "Open in Pastr" or copy/share from the containing app.

## Mac App Store Rejection Handling

Verified local fix:

- The macOS entitlement file now enables App Sandbox, which is required for Mac App Store distribution.

Remaining review-hardening work:

- Add or verify privacy manifest coverage for crash reporting and any SDK data collection.
- Gate crash reporting behind an explicit privacy setting or first-run consent if App Review flagged data collection.
- Make App Store metadata match the app: clipboard history, iCloud sync, keyboard extension if shipped, and optional Full Access use.
- Keep the Accessibility permission copy tied to direct paste into other apps; do not request it before explaining why.
- Confirm the Mac App Store submission includes Sandbox usage notes for user-selected file read/write, iCloud, and network access.

## Apple Review Constraints Used

- Custom keyboards must provide keyboard input functionality, a next-keyboard method, work without full access, and collect user activity only for keyboard functionality: https://developer.apple.com/app-store/review/guidelines/
- Custom keyboard extensions insert text through `UITextDocumentProxy` and are separate extension processes: https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- Full Access is declared with `RequestsOpenAccess` for custom keyboard extension attributes: https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html
- iOS pasteboard reads can trigger user notifications or prompts without user intent; use user-initiated paste flows: https://developer.apple.com/documentation/uikit/uipasteboard/
- Mac App Store distribution requires App Sandbox: https://developer.apple.com/documentation/security/app-sandbox

## Implementation Slices

1. Create iOS app target and shared clip model.
2. Add App Group and a small keyboard-readable clip cache.
3. Build Library, Clip Detail, Collections, Keyboard Setup, and Settings screens.
4. Add Custom Keyboard extension with plain-text insertion, search, next-keyboard key, and fallback no-full-access state.
5. Add App Review pass: privacy manifest, consent toggles, metadata notes, and sandbox/entitlement validation.


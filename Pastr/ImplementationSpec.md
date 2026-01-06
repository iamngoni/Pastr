# Pastr Quick Pop-up Panel Spec

Date: 2026-01-06
Owner: Pastr (macOS Swift app)
Goal: Deliver a Paste-like micro-pop-up paste history panel that is fast, minimal, and out of the way, with iCloud sync for pinned items.

## 1) Product Intent
- Pastr runs quietly in the background (menu bar / background agent style), always ready without feeling like a big app.
- On global shortcut, a small sleek panel slides up from the bottom of the screen (not full overlay, not Spotlight style).
- Panel shows a horizontal strip of recent clipboard items as clean cards (text, images, links previews).
- Default action: choose an item -> panel closes -> paste into the previously active app after a short delay.
- Browsing: horizontal scroll; optional lightweight sections (History, Pinned/Useful).
- Trust: pinned items sync via iCloud across Macs (CloudKit).

## 2) Reference Visual (from provided image)
- Bottom-anchored floating panel with rounded corners and subtle translucency.
- Horizontal card strip of recent items, each with type label and time.
- Subtle control row for sections and actions.

## 3) Core Experience
### 3.1 Launch and Activation
- App runs as background accessory (no dock unless opened explicitly).
- Global hotkey toggles panel (default Cmd+B).
- Hotkey is user-customizable in settings.
- Menu bar icon present; click opens the panel (no extra actions).
- Panel appears on the display under the cursor.
- Onboarding shown on first open, with explicit clipboard monitoring copy.

### 3.2 Panel Behavior
- Panel slides up from bottom with short easing (200-280ms).
- Panel is a full-width bottom bar (like Paste), not a narrow centered strip.
- Panel can overlay above full-screen apps/spaces.
- Dismissal on:
  - Selection/paste action
  - Esc key
  - Click outside
  - Hotkey again
- Panel keeps focus for navigation but returns focus to prior app after paste.
- Paste action closes panel first, then triggers Cmd+V after a short delay (~50-120ms).

### 3.3 Clipboard Items
- Track recent clipboard items in-memory and persisted locally.
- Types: support all possible clipboard types (text, image, link/URL, file, rich text/RTF, etc.).
- Cards show:
  - Type label (Text/Image/Link)
  - Preview (snippet/image/favicon or URL title if available)
  - Timestamp / relative time
  - Source app icon/name

### 3.4 Selection and Pasting
- Keyboard navigation: left/right arrows for items, Enter to paste.
- Mouse selection: click item to paste.
- On paste:
  - copy item to pasteboard
  - close panel
  - simulate Cmd+V in previous app after a short delay

### 3.5 Sections
- History (default)
- Pinned/Useful (synced via iCloud)
- Simple toggle row; horizontal scroll remains per section.
- Pinned limit: default max 5, user-customizable in settings.

## 4) Architecture
### 4.1 App Structure
- SwiftUI app with background agent mode.
- Main components:
  - AppDelegate / app lifecycle manager
  - ClipboardMonitor
  - PanelWindowController
  - PasteActionController
  - Persistence (Core Data + CloudKit for pinned)

### 4.2 Data Model
- ClipboardItem
  - id (UUID)
  - createdAt (Date)
  - type (enum: text, image, link, file, richText, other)
  - textContent (String?)
  - imageData (Data?)
  - rtfData (Data?)
  - urlString (String?)
  - fileBookmarks (Data?) for security-scoped file URLs
  - sourceAppBundleId (String?)
  - sourceAppName (String?)
  - isPinned (Bool)
  - pinnedTitle (String?)
  - hashFingerprint (String) for dedupe
  - utiTypes ([String]) for supported pasteboard representations

- Storage Plan
  - Local Core Data store for history
  - CloudKit-backed Core Data store (NSPersistentCloudKitContainer) for pinned items

### 4.3 Clipboard Monitoring
- Use NSPasteboard.general changeCount polling (Timer) or NSPasteboard.notification if feasible.
- Dedupe by hash fingerprint.
- Clip retention policy: default 100 items / 30 days; user-customizable with an option for unlimited.
- Warn when storage becomes large (performance impact).

### 4.4 Pasting
- Capture frontmost app before opening panel (NSWorkspace / NSRunningApplication).
- Paste action writes to NSPasteboard and triggers Cmd+V using CGEvent.

### 4.5 iCloud Sync
- Pinned items sync via NSPersistentCloudKitContainer.
- Sync only for pinned items (isPinned = true).
- iCloud account availability and error states handled gracefully.
- Scope: macOS only.

## 5) UI / Interaction Details
- Panel size: full-width bottom bar; height approx 160-220px (TBD).
- Panel anchored with 16-24px margin from bottom.
- Visual style:
  - Rounded corners 14-18px
  - Glass blur / translucency
  - Subtle border or shadow
- Cards:
  - 120-160px width each
  - 3-4 lines text snippet max
  - Image cards with 1:1 or 4:3 crop
- Section switcher: left aligned icons + text, minimal emphasis.

## 6) Non-Goals (Current)
- Advanced search
- Cloud sync for full history
- Complex formatting conversions

## 7) Decisions (Resolved)
1) Hotkey: desired default shortcut and whether user can customize? (Answered: default Cmd+B; user-customizable)
2) Screen placement: always main display, or display under cursor? (Answered: display under cursor)
3) Panel width: match Paste-like full width (near bottom) or narrower centered panel? (Answered: full width bottom bar)
4) Clipboard types: include files and rich text (RTF) for MVP? (Answered: full support for all possible types)
5) History size: max count, retention duration? (Answered: default 100 items / 30 days, customizable incl. unlimited; warn on large storage)
6) Pinned behavior: pin limit? editable titles/labels? (Answered: default max 5, customizable; editable labels)
7) iCloud scope: should pinned items sync only across user Macs or also iOS (if future)? (Answered: macOS only)
8) Should panel show source app icon on cards? (Answered: yes)
9) Should paste trigger delay (e.g., 50-150ms) after closing panel? (Answered: close panel then paste with short delay)
10) Any privacy indicator or onboarding copy needed? (Answered: onboarding on first open)
11) Do we support multiple spaces / full screen apps? (panel overlay behavior) (Answered: overlay above full-screen apps)
12) Should Pastr appear in menu bar with quick actions or remain invisible? (Answered: menu bar icon; click opens panel; no extra actions)

## 8) Milestones
- M1: Clipboard monitor + local persistence + horizontal history UI.
- M2: Panel window + animation + global hotkey + paste action.
- M3: Pinned section + iCloud sync + polish.

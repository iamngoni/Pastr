# Contributing to Pastr

Thanks for taking the time to contribute. This document covers how to set up a local development environment, the conventions used in this project, and the process for submitting changes.

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- An Apple Developer account (free tier is sufficient for local builds)

## Setting up

1. Fork and clone the repository.
2. Open `Pastr.xcodeproj` in Xcode.
3. Select the **Pastr** scheme and your Mac as the run destination.
4. Press `⌘R` to build and run.

No external package managers or additional tooling are required — the project has no Swift Package Manager dependencies beyond what Xcode provides.

## Development workflow

- Work directly in the main repository directory. Do not use git worktrees.
- Keep one concern per branch. Branch names should be short and descriptive (e.g. `fix/panel-flicker`, `feat/tag-filtering`).
- Run the app manually and exercise the affected flow before opening a pull request.
- Check that the app launches, the panel opens, and clipboard capture works after any non-trivial change.

## Code style

- Follow standard Swift and SwiftUI conventions.
- Keep types and functions focused — prefer small, composable pieces.
- Use descriptive names. Avoid abbreviations unless they are universally understood.
- Add comments only when the reasoning is not obvious from the code itself.
- Remove dead code rather than commenting it out.
- Do not introduce new third-party dependencies without prior discussion.

## Architecture notes

- **Background agent** — Pastr runs as a background accessory (no Dock icon by default). App lifecycle lives in `AppDelegate`.
- **Clipboard monitoring** — `ClipboardMonitor` polls `NSPasteboard.general` on a background thread. Deduplication is fingerprint-based.
- **Panel** — `PanelWindowController` owns the floating window; `PanelViewModel` drives selection and section state.
- **Paste** — `PasteController` writes to the pasteboard and fires a `CGEvent` `Cmd+V` after closing the panel.
- **Persistence** — local history is stored in Core Data; pinned items use `NSPersistentCloudKitContainer` for iCloud sync.
- **Settings** — all user preferences flow through `SettingsStore.shared`.

Understand the relevant parts of this architecture before making changes. Avoid bypassing the established data flow.

## Submitting a pull request

1. Ensure your branch is up to date with `master`.
2. Confirm the app builds without warnings introduced by your changes.
3. Test the golden path and any edge cases your change touches.
4. Write a clear PR description covering:
   - **What changed** — a concise summary of the diff.
   - **Why** — the motivation or problem being solved.
   - **Testing performed** — what you ran or verified manually.
   - **Risks** — anything that could affect other features or behaviour.
5. Keep PRs focused. Large, multi-concern changes are harder to review and merge.

## Reporting bugs

Open a GitHub issue with:
- macOS version and Pastr version (visible in Settings → About).
- Steps to reproduce.
- Expected vs actual behaviour.
- A crash log or screenshot if relevant.

## Security issues

Do not open a public issue for security vulnerabilities. Email the maintainer directly instead.

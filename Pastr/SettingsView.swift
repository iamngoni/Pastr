import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var historyStore: ClipboardHistoryStore
    let hotKeyManager: HotKeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Hotkey")) {
                HStack(spacing: 12) {
                    Text("Show Panel")
                        .frame(width: 120, alignment: .leading)
                    HotKeyRecorderView(
                        keyCode: $settings.hotKeyKeyCode,
                        modifiers: $settings.hotKeyModifiers
                    ) {
                        hotKeyManager.register(keyCode: settings.hotKeyKeyCode, modifiers: settings.hotKeyModifiers)
                    }
                    .frame(width: 140, height: 28)
                }
                .padding(.vertical, 6)
            }

            GroupBox(label: Text("History")) {
                Toggle("Unlimited history", isOn: $settings.historyUnlimited)

                HStack {
                    Text("Max items")
                        .frame(width: 120, alignment: .leading)
                    Stepper(value: $settings.historyMaxItems, in: 10...10000, step: 10) {
                        Text("\(settings.historyMaxItems)")
                    }
                    .disabled(settings.historyUnlimited)
                }

                HStack {
                    Text("Max days")
                        .frame(width: 120, alignment: .leading)
                    Stepper(value: $settings.historyMaxDays, in: 1...365) {
                        Text("\(settings.historyMaxDays)")
                    }
                    .disabled(settings.historyUnlimited)
                }

                if settings.historyUnlimited && historyStore.items.count > 1000 {
                    Text("Large history sizes can affect performance.")
                        .foregroundColor(.orange)
                        .font(.footnote)
                }
            }

            GroupBox(label: Text("Pinned")) {
                HStack {
                    Text("Pin limit")
                        .frame(width: 120, alignment: .leading)
                    Stepper(value: $settings.pinLimit, in: 1...50) {
                        Text("\(settings.pinLimit)")
                    }
                }
            }

            GroupBox(label: Text("General")) {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                Toggle("Show in menu bar", isOn: $settings.showInMenuBar)

                Toggle("Play sound effects", isOn: $settings.playSoundEffects)

                HStack {
                    Text("Paste delay")
                        .frame(width: 120, alignment: .leading)
                    Slider(value: $settings.pasteDelay, in: 0.01...0.5, step: 0.01)
                        .frame(width: 120)
                    Text(String(format: "%.2fs", settings.pasteDelay))
                        .foregroundColor(.secondary)
                        .frame(width: 50)
                }
            }

            GroupBox(label: Text("Sync")) {
                Toggle("Enable iCloud sync", isOn: $settings.iCloudSyncEnabled)
                if settings.iCloudSyncEnabled {
                    Text("Clipboard history will sync across your devices.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            GroupBox(label: Text("Data")) {
                Button("Clear History") {
                    showClearHistoryAlert = true
                }
                .alert("Clear History", isPresented: $showClearHistoryAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear", role: .destructive) {
                        historyStore.clearUnpinnedItems()
                    }
                } message: {
                    Text("This will remove all non-pinned clipboard items. This action cannot be undone.")
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 420, height: 520)
    }

    @State private var showClearHistoryAlert = false
}

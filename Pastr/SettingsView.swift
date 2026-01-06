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

            Spacer()
        }
        .padding(24)
        .frame(width: 420)
    }
}

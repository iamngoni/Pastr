import Carbon.HIToolbox
import SwiftUI

// MARK: - Settings Section Enum

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case privacy = "Privacy"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "lock.shield"
        case .shortcuts: return "command"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var historyStore: ClipboardHistoryStore
    let hotKeyManager: HotKeyManager

    @State private var selectedSection: SettingsSection = .general
    @State private var showClearHistoryAlert = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            contentArea
        }
        .background(Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)))
        .frame(width: 600, height: 520)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarButton(
                        title: section.rawValue,
                        icon: section.icon,
                        isSelected: selectedSection == section
                    ) {
                        selectedSection = section
                    }
                }
            }
            .padding(.top, 12)

            Spacer()

            // Help Center
            Button {
                if let url = URL(string: "https://github.com/iamngoni/Pastr") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.5))

                    Text("Help Center")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .frame(width: 160)
        .background(Color(nsColor: NSColor(red: 0.09, green: 0.09, blue: 0.095, alpha: 1)))
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text(selectedSection.rawValue)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.bottom, 24)

                // Content based on selected section
                switch selectedSection {
                case .general:
                    generalSection
                case .privacy:
                    privacySection
                case .shortcuts:
                    shortcutsSection
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Basic settings toggles
            SettingsToggleRow(
                title: "Open at login",
                isOn: $settings.launchAtLogin
            )

            SettingsToggleRow(
                title: "Run in background",
                isOn: $settings.showInMenuBar
            )

            SettingsToggleRow(
                title: "iCloud sync",
                subtitle: settings.iCloudSyncEnabled ? "Synced now" : nil,
                isOn: $settings.iCloudSyncEnabled
            )

            SettingsToggleRow(
                title: "Sound effects",
                isOn: $settings.playSoundEffects
            )

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 8)

            // Paste Items section
            Text("Paste Items")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 12) {
                PasteOptionRow(
                    title: "To active app",
                    subtitle: "Paste selected items directly to the application you are currently using.",
                    isSelected: true,
                    icon: "app.badge.checkmark"
                )

                PasteOptionRow(
                    title: "To clipboard",
                    subtitle: "Copy selected items to the system clipboard to paste manually later.",
                    isSelected: false,
                    icon: "doc.on.clipboard"
                )

                HStack {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.4))
                        .frame(width: 20)

                    Text("Always paste as Plain Text")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.6))
                }
                .padding(.top, 4)
            }

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 8)

            // Keep History section
            Text("Keep History")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 8)

            HistoryDurationPicker(
                selectedDuration: Binding(
                    get: {
                        if settings.historyUnlimited { return .forever }
                        switch settings.historyMaxDays {
                        case 1: return .day
                        case 7: return .week
                        case 30: return .month
                        case 365: return .year
                        default: return .month
                        }
                    },
                    set: { newValue in
                        switch newValue {
                        case .day:
                            settings.historyUnlimited = false
                            settings.historyMaxDays = 1
                        case .week:
                            settings.historyUnlimited = false
                            settings.historyMaxDays = 7
                        case .month:
                            settings.historyUnlimited = false
                            settings.historyMaxDays = 30
                        case .year:
                            settings.historyUnlimited = false
                            settings.historyMaxDays = 365
                        case .forever:
                            settings.historyUnlimited = true
                        }
                    }
                )
            )

            // Erase History button
            HStack {
                Spacer()
                Button("Erase History...") {
                    showClearHistoryAlert = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 8)
        }
        .alert("Erase History", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) {
                historyStore.clearUnpinnedItems()
            }
        } message: {
            Text("This will remove all non-pinned clipboard items. This action cannot be undone.")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggleRow(
                title: "Show during screen sharing",
                subtitle: "Allow Pastr to appear to others when you share your screen.",
                isOn: .constant(true)
            )

            SettingsToggleRow(
                title: "Generate link previews",
                subtitle: "Download web content for previews; may activate one-time or analytics-sensitive links.",
                isOn: .constant(true)
            )

            SettingsToggleRow(
                title: "Ignore confidential content",
                subtitle: "Do not save passwords and sensitive data when detected.",
                isOn: .constant(true)
            )

            SettingsToggleRow(
                title: "Ignore transient content",
                subtitle: "Do not save temporary data generated by other apps.",
                isOn: .constant(true)
            )

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 8)

            // Ignore Applications section
            Text("Ignore Applications")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text("Do not save content copied from the applications below.")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                IgnoredAppRow(appName: "Keychain Access", bundleId: "com.apple.keychainaccess")
                Divider().background(Color.white.opacity(0.05))
                IgnoredAppRow(appName: "Passwords", bundleId: "com.apple.Passwords")
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )

            // Add/Remove buttons
            HStack(spacing: 8) {
                Button("+") {}
                    .buttonStyle(SmallIconButtonStyle())

                Button("−") {}
                    .buttonStyle(SmallIconButtonStyle())
            }
        }
    }

    // MARK: - Shortcuts Section

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShortcutRow(
                title: "Activate Pastr",
                keyCode: $settings.hotKeyKeyCode,
                modifiers: $settings.hotKeyModifiers,
                hotKeyManager: hotKeyManager
            )

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)

            // Quick Paste info
            HStack {
                Text("Quick Paste")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.7))

                Spacer()

                HStack(spacing: 4) {
                    KeyboardKey(text: "⌘")
                    Text("Command")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.5))
                    Text("+ 1...9")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.5))
                }
            }

            HStack {
                Text("Plain Text mode")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.7))

                Spacer()

                HStack(spacing: 4) {
                    KeyboardKey(text: "⇧")
                    Text("Shift")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.5))
                }
            }

            Spacer()

            // Reset button
            HStack {
                Spacer()
                Button("Reset shortcuts to default...") {
                    settings.hotKeyKeyCode = 9 // V key
                    settings.hotKeyModifiers = UInt32(cmdKey | shiftKey)
                    hotKeyManager.register(keyCode: settings.hotKeyKeyCode, modifiers: settings.hotKeyModifiers)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : Color(white: 0.5))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color(white: 0.5))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(red: 0.2, green: 0.4, blue: 0.9) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.85))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.5))
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.2, green: 0.5, blue: 1.0)))
                .labelsHidden()
        }
    }
}

// MARK: - Paste Option Row

struct PasteOptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? Color(red: 0.2, green: 0.5, blue: 1.0) : Color(white: 0.4))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.85))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

// MARK: - History Duration Picker

enum HistoryDuration: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case forever = "Forever"
}

struct HistoryDurationPicker: View {
    @Binding var selectedDuration: HistoryDuration

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HistoryDuration.allCases, id: \.self) { duration in
                Button {
                    selectedDuration = duration
                } label: {
                    Text(duration.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedDuration == duration ? .white : Color(white: 0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedDuration == duration ? Color(white: 0.25) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Ignored App Row

struct IgnoredAppRow: View {
    let appName: String
    let bundleId: String

    private var appIcon: NSImage {
        if appName == "Keychain Access" {
            return NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Keychain Access.app")
        } else if appName == "Passwords" {
            return NSWorkspace.shared.icon(forFile: "/System/Applications/Passwords.app")
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 24, height: 24)

            Text(appName)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.85))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Shortcut Row

struct ShortcutRow: View {
    let title: String
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    let hotKeyManager: HotKeyManager

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.7))

            Spacer()

            HStack(spacing: 8) {
                HotKeyRecorderView(
                    keyCode: $keyCode,
                    modifiers: $modifiers
                ) {
                    hotKeyManager.register(keyCode: keyCode, modifiers: modifiers)
                }
                .frame(width: 120, height: 28)

                Button {
                    // Clear shortcut
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                }
                .buttonStyle(SmallIconButtonStyle())
            }
        }
    }
}

// MARK: - Keyboard Key

struct KeyboardKey: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(white: 0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Button Styles

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(white: 0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SmallIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color(white: 0.6))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Glass Card (used by OnboardingView)

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    var opacity: CGFloat = 0.6
    var borderColor: Color = Color.white.opacity(0.06)
    @ViewBuilder let content: () -> Content

    init(cornerRadius: CGFloat, opacity: CGFloat = 0.6, borderColor: Color = Color.white.opacity(0.06), @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.borderColor = borderColor
        self.content = content
    }

    init(cornerRadius: CGFloat, opacity: CGFloat = 0.6, borderColor: Color = Color.white.opacity(0.06)) where Content == EmptyView {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.borderColor = borderColor
        self.content = { EmptyView() }
    }

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial.opacity(opacity))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(red: 0.118, green: 0.118, blue: 0.125).opacity(0.6))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

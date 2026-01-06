import SwiftUI

// MARK: - Settings Section Enum

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case history = "History Management"
    case pinned = "Pinned Items"
    case sync = "Sync & Cloud"
    case data = "Data Management"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .history: return "clock.fill"
        case .pinned: return "pin.fill"
        case .sync: return "icloud.fill"
        case .data: return "trash.fill"
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
        .background(
            LinearGradient(
                colors: [Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)),
                         Color(nsColor: NSColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(width: 680, height: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            // App logo and name
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                     Color(red: 0.39, green: 0.71, blue: 1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .shadow(color: Color(red: 0.04, green: 0.52, blue: 1).opacity(0.3), radius: 4, y: 2)
                    .overlay(
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )

                Text("Pastr")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Navigation items
            VStack(alignment: .leading, spacing: 4) {
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

            Spacer()
        }
        .padding(21)
        .frame(width: 180)
        .background(
            GlassCard(cornerRadius: 0, opacity: 0.7)
        )
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .tracking(-0.4)

                    Text("Customize your Pastr experience")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                }

                // Quick Access (Hotkey)
                GlassCard(cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Access")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)

                        SettingsRow(label: "Show Panel") {
                            HotKeyRecorderView(
                                keyCode: $settings.hotKeyKeyCode,
                                modifiers: $settings.hotKeyModifiers
                            ) {
                                hotKeyManager.register(keyCode: settings.hotKeyKeyCode, modifiers: settings.hotKeyModifiers)
                            }
                            .frame(width: 80, height: 36)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(21)
                }

                // Content based on selected section
                switch selectedSection {
                case .general:
                    generalSection
                case .history:
                    historySection
                case .pinned:
                    pinnedSection
                case .sync:
                    syncSection
                case .data:
                    dataSection
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - General Section

    private var generalSection: some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 19) {
                Text("General")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 13) {
                    GlassCheckbox(isOn: $settings.launchAtLogin, label: "Launch at login")
                    GlassCheckbox(isOn: $settings.showInMenuBar, label: "Show in menu bar")
                    GlassCheckbox(isOn: $settings.playSoundEffects, label: "Play sound effects")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Paste delay")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.62))

                        Spacer()

                        Text(String(format: "%.2fs", settings.pasteDelay))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                    }

                    GlassSlider(value: $settings.pasteDelay, range: 0.01...0.5)
                }
                .padding(.top, 12)
            }
            .padding(21)
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 20) {
                Text("History Management")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                SettingsRow(label: "Unlimited history") {
                    GlassToggle(isOn: $settings.historyUnlimited)
                }

                SettingsRow(label: "Max items") {
                    GlassStepper(value: $settings.historyMaxItems, range: 10...10000, step: 10)
                        .disabled(settings.historyUnlimited)
                        .opacity(settings.historyUnlimited ? 0.5 : 1)
                }

                SettingsRow(label: "Max days") {
                    GlassStepper(value: $settings.historyMaxDays, range: 1...365, step: 1)
                        .disabled(settings.historyUnlimited)
                        .opacity(settings.historyUnlimited ? 0.5 : 1)
                }

                if settings.historyUnlimited && historyStore.items.count > 1000 {
                    Text("Large history sizes can affect performance.")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(21)
        }
    }

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pinned Items")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                SettingsRow(label: "Pin limit") {
                    GlassStepper(value: $settings.pinLimit, range: 1...50, step: 1)
                }
            }
            .padding(21)
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sync & Cloud")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.04, green: 0.52, blue: 1).opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable iCloud sync")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Sync across Apple devices")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                    }

                    Spacer()

                    GlassToggle(isOn: $settings.iCloudSyncEnabled)
                }
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.04, green: 0.08, blue: 0.12).opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
            }
            .padding(21)
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        GlassCard(cornerRadius: 16, borderColor: Color.orange.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Data Management")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 12) {
                    Text("This action cannot be undone. All your clipboard history will be permanently deleted.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.58, blue: 0))

                    Button(action: { showClearHistoryAlert = true }) {
                        Text("Clear History")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.58, blue: 0),
                                             Color(red: 1, green: 0.7, blue: 0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: Color(red: 1, green: 0.58, blue: 0).opacity(0.3), radius: 3, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 1, green: 0.58, blue: 0).opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 1, green: 0.58, blue: 0).opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .padding(21)
        }
        .alert("Clear History", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                historyStore.clearUnpinnedItems()
            }
        } message: {
            Text("This will remove all non-pinned clipboard items. This action cannot be undone.")
        }
    }
}

// MARK: - Glass Card

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

// MARK: - Sidebar Button

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Color(red: 0.04, green: 0.52, blue: 1) : Color(red: 0.6, green: 0.6, blue: 0.62))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? Color(red: 0.04, green: 0.52, blue: 1) : Color(red: 0.6, green: 0.6, blue: 0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(red: 0.04, green: 0.52, blue: 1).opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color(red: 0.04, green: 0.52, blue: 1).opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Row

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.62))

            Spacer()

            content()
        }
    }
}

// MARK: - Glass Toggle

struct GlassToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn ?
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                     Color(red: 0.39, green: 0.71, blue: 1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 44, height: 26)
                    .shadow(color: isOn ? Color(red: 0.04, green: 0.52, blue: 1).opacity(0.4) : .clear, radius: 3, y: 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isOn)
    }
}

// MARK: - Glass Checkbox

struct GlassCheckbox: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            isOn ?
                            LinearGradient(
                                colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                         Color(red: 0.39, green: 0.71, blue: 1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isOn ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: isOn ? Color(red: 0.04, green: 0.52, blue: 1).opacity(0.4) : .clear, radius: 3, y: 2)

                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.62))

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Stepper

struct GlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(minWidth: 30, alignment: .trailing)

            VStack(spacing: 2) {
                StepperButton(systemName: "chevron.up") {
                    if value + step <= range.upperBound {
                        value += step
                    }
                }

                StepperButton(systemName: "chevron.down") {
                    if value - step >= range.lowerBound {
                        value -= step
                    }
                }
            }
        }
    }
}

struct StepperButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.04, green: 0.52, blue: 1).opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(red: 0.04, green: 0.52, blue: 1).opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Slider

struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                // Filled track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                     Color(red: 0.39, green: 0.71, blue: 1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, thumbPosition(in: geometry.size.width) + 7), height: 6)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.04, green: 0.52, blue: 1), lineWidth: 2)
                    )
                    .shadow(color: Color(red: 0.04, green: 0.52, blue: 1).opacity(0.4), radius: 3, y: 2)
                    .offset(x: thumbPosition(in: geometry.size.width))
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let newValue = Double(gesture.location.x / geometry.size.width)
                                let clamped = min(max(newValue, 0), 1)
                                value = range.lowerBound + (range.upperBound - range.lowerBound) * clamped
                            }
                    )
            }
        }
        .frame(height: 14)
    }

    private func thumbPosition(in width: CGFloat) -> CGFloat {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(normalized) * (width - 14)
    }
}

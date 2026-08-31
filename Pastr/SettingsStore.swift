import AppKit
import Carbon
import Combine
import Foundation
import ServiceManagement

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var historyMaxItems: Int {
        didSet { defaults.set(historyMaxItems, forKey: Keys.historyMaxItems) }
    }

    @Published var historyMaxDays: Int {
        didSet { defaults.set(historyMaxDays, forKey: Keys.historyMaxDays) }
    }

    @Published var historyUnlimited: Bool {
        didSet { defaults.set(historyUnlimited, forKey: Keys.historyUnlimited) }
    }

    @Published var pinLimit: Int {
        didSet { defaults.set(pinLimit, forKey: Keys.pinLimit) }
    }

    @Published var hotKeyKeyCode: UInt32 {
        didSet { defaults.set(Int(hotKeyKeyCode), forKey: Keys.hotKeyKeyCode) }
    }

    @Published var hotKeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotKeyModifiers), forKey: Keys.hotKeyModifiers) }
    }

    @Published var queueModeKeyCode: UInt32 {
        didSet { defaults.set(Int(queueModeKeyCode), forKey: Keys.queueModeKeyCode) }
    }

    @Published var queueModeModifiers: UInt32 {
        didSet { defaults.set(Int(queueModeModifiers), forKey: Keys.queueModeModifiers) }
    }

    @Published var hotCorner: HotCornerMonitor.Corner {
        didSet { defaults.set(hotCorner.rawValue, forKey: Keys.hotCorner) }
    }

    @Published var hotCornerDelay: TimeInterval {
        didSet { defaults.set(hotCornerDelay, forKey: Keys.hotCornerDelay) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Last app version for which the "What's New" sheet was shown. Empty until first set.
    @Published var lastSeenVersion: String {
        didSet { defaults.set(lastSeenVersion, forKey: Keys.lastSeenVersion) }
    }

    @Published var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    @Published var playSoundEffects: Bool {
        didSet { defaults.set(playSoundEffects, forKey: Keys.playSoundEffects) }
    }

    @Published var pasteDelay: Double {
        didSet { defaults.set(pasteDelay, forKey: Keys.pasteDelay) }
    }

    @Published var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }

    // Privacy settings
    @Published var showDuringScreenSharing: Bool {
        didSet { defaults.set(showDuringScreenSharing, forKey: Keys.showDuringScreenSharing) }
    }

    @Published var generateLinkPreviews: Bool {
        didSet { defaults.set(generateLinkPreviews, forKey: Keys.generateLinkPreviews) }
    }

    @Published var encryptBackups: Bool {
        didSet { defaults.set(encryptBackups, forKey: Keys.encryptBackups) }
    }

    @Published var enableQuickPreview: Bool {
        didSet { defaults.set(enableQuickPreview, forKey: Keys.enableQuickPreview) }
    }

    @Published var ignoreConfidentialContent: Bool {
        didSet { defaults.set(ignoreConfidentialContent, forKey: Keys.ignoreConfidentialContent) }
    }

    @Published var ignoreTransientContent: Bool {
        didSet { defaults.set(ignoreTransientContent, forKey: Keys.ignoreTransientContent) }
    }

    @Published var ignoredAppBundleIds: [String] {
        didSet { defaults.set(ignoredAppBundleIds, forKey: Keys.ignoredAppBundleIds) }
    }

    @Published var displaySize: DisplaySize {
        didSet { defaults.set(displaySize.rawValue, forKey: Keys.displaySize) }
    }

    /// The automatic size is refreshed by the panel controller before it presents on a screen.
    /// Keeping it as state avoids querying AppKit repeatedly during SwiftUI layout.
    @Published private(set) var detectedDisplaySize: DisplaySize = .regular

    var resolvedDisplaySize: DisplaySize {
        displaySize == .auto ? detectedDisplaySize : displaySize
    }

    // MARK: - On-device Intelligence (Tier 1)

    /// Master switch for all deterministic on-device enrichment (OCR, classification,
    /// sensitivity, embeddings).
    @Published var aiEnrichmentEnabled: Bool {
        didSet { defaults.set(aiEnrichmentEnabled, forKey: Keys.aiEnrichmentEnabled) }
    }

    @Published var ocrEnabled: Bool {
        didSet { defaults.set(ocrEnabled, forKey: Keys.ocrEnabled) }
    }

    @Published var semanticSearchEnabled: Bool {
        didSet { defaults.set(semanticSearchEnabled, forKey: Keys.semanticSearchEnabled) }
    }

    @Published var autoTaggingEnabled: Bool {
        didSet { defaults.set(autoTaggingEnabled, forKey: Keys.autoTaggingEnabled) }
    }

    @Published var sensitiveDataDetectionEnabled: Bool {
        didSet { defaults.set(sensitiveDataDetectionEnabled, forKey: Keys.sensitiveDataDetectionEnabled) }
    }

    // MARK: - Apple Intelligence (Tier 2)

    /// Master switch for Apple Intelligence features (titles, summaries, transforms).
    @Published var appleIntelligenceEnabled: Bool {
        didSet { defaults.set(appleIntelligenceEnabled, forKey: Keys.appleIntelligenceEnabled) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        // 0 means unlimited, so we need to check if key exists to distinguish "not set" from "unlimited"
        if defaults.object(forKey: Keys.historyMaxItems) != nil {
            historyMaxItems = defaults.integer(forKey: Keys.historyMaxItems)
        } else {
            historyMaxItems = 0 // Default to unlimited
        }

        let storedMaxDays = defaults.integer(forKey: Keys.historyMaxDays)
        historyMaxDays = storedMaxDays == 0 ? 30 : storedMaxDays

        historyUnlimited = defaults.bool(forKey: Keys.historyUnlimited)

        let storedPinLimit = defaults.integer(forKey: Keys.pinLimit)
        pinLimit = storedPinLimit == 0 ? 5 : storedPinLimit

        let storedKeyCode = defaults.integer(forKey: Keys.hotKeyKeyCode)
        hotKeyKeyCode = storedKeyCode == 0 ? UInt32(kVK_ANSI_B) : UInt32(storedKeyCode)

        let storedModifiers = defaults.integer(forKey: Keys.hotKeyModifiers)
        hotKeyModifiers = storedModifiers == 0 ? UInt32(cmdKey) : UInt32(storedModifiers)

        // Queue mode hotkey defaults to Cmd+Shift+B
        let storedQueueKeyCode = defaults.integer(forKey: Keys.queueModeKeyCode)
        queueModeKeyCode = storedQueueKeyCode == 0 ? UInt32(kVK_ANSI_B) : UInt32(storedQueueKeyCode)

        let storedQueueModifiers = defaults.integer(forKey: Keys.queueModeModifiers)
        queueModeModifiers = storedQueueModifiers == 0 ? UInt32(cmdKey | shiftKey) : UInt32(storedQueueModifiers)

        // Hot corner settings
        if let storedHotCorner = defaults.string(forKey: Keys.hotCorner),
           let corner = HotCornerMonitor.Corner(rawValue: storedHotCorner) {
            hotCorner = corner
        } else {
            hotCorner = .disabled
        }

        let storedHotCornerDelay = defaults.double(forKey: Keys.hotCornerDelay)
        hotCornerDelay = storedHotCornerDelay == 0 ? 0.3 : storedHotCornerDelay

        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion) ?? ""

        iCloudSyncEnabled = defaults.bool(forKey: Keys.iCloudSyncEnabled)

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        let storedPlaySoundEffects = defaults.object(forKey: Keys.playSoundEffects)
        playSoundEffects = storedPlaySoundEffects == nil ? true : defaults.bool(forKey: Keys.playSoundEffects)

        let storedPasteDelay = defaults.double(forKey: Keys.pasteDelay)
        pasteDelay = storedPasteDelay == 0 ? 0.08 : storedPasteDelay

        let storedShowInMenuBar = defaults.object(forKey: Keys.showInMenuBar)
        showInMenuBar = storedShowInMenuBar == nil ? true : defaults.bool(forKey: Keys.showInMenuBar)

        // Privacy settings - defaults
        let storedShowDuringScreenSharing = defaults.object(forKey: Keys.showDuringScreenSharing)
        showDuringScreenSharing = storedShowDuringScreenSharing == nil ? true : defaults.bool(forKey: Keys.showDuringScreenSharing)

        let storedGenerateLinkPreviews = defaults.object(forKey: Keys.generateLinkPreviews)
        generateLinkPreviews = storedGenerateLinkPreviews == nil ? true : defaults.bool(forKey: Keys.generateLinkPreviews)
        encryptBackups = defaults.bool(forKey: Keys.encryptBackups)
        let storedQuickPreview = defaults.object(forKey: Keys.enableQuickPreview)
        enableQuickPreview = storedQuickPreview == nil ? true : defaults.bool(forKey: Keys.enableQuickPreview)

        let storedIgnoreConfidential = defaults.object(forKey: Keys.ignoreConfidentialContent)
        ignoreConfidentialContent = storedIgnoreConfidential == nil ? true : defaults.bool(forKey: Keys.ignoreConfidentialContent)

        let storedIgnoreTransient = defaults.object(forKey: Keys.ignoreTransientContent)
        ignoreTransientContent = storedIgnoreTransient == nil ? true : defaults.bool(forKey: Keys.ignoreTransientContent)

        // Default ignored apps: Keychain Access, Passwords, 1Password, etc.
        let storedIgnoredApps = defaults.stringArray(forKey: Keys.ignoredAppBundleIds)
        ignoredAppBundleIds = storedIgnoredApps ?? [
            "com.apple.keychainaccess",
            "com.apple.Passwords"
        ]

        // Display size - default to auto (detects based on screen)
        if let storedDisplaySize = defaults.string(forKey: Keys.displaySize),
           let size = DisplaySize(rawValue: storedDisplaySize) {
            displaySize = size
        } else {
            displaySize = .auto
        }

        // On-device Intelligence (Tier 1) - default on (fully local, privacy-safe)
        let storedAIEnrichment = defaults.object(forKey: Keys.aiEnrichmentEnabled)
        aiEnrichmentEnabled = storedAIEnrichment == nil ? true : defaults.bool(forKey: Keys.aiEnrichmentEnabled)

        let storedOCR = defaults.object(forKey: Keys.ocrEnabled)
        ocrEnabled = storedOCR == nil ? true : defaults.bool(forKey: Keys.ocrEnabled)

        let storedSemantic = defaults.object(forKey: Keys.semanticSearchEnabled)
        semanticSearchEnabled = storedSemantic == nil ? true : defaults.bool(forKey: Keys.semanticSearchEnabled)

        // Auto-tagging off by default to avoid surprising users with new tags.
        autoTaggingEnabled = defaults.bool(forKey: Keys.autoTaggingEnabled)

        let storedSensitive = defaults.object(forKey: Keys.sensitiveDataDetectionEnabled)
        sensitiveDataDetectionEnabled = storedSensitive == nil ? true : defaults.bool(forKey: Keys.sensitiveDataDetectionEnabled)

        // Apple Intelligence (Tier 2) - default on; gated by hardware/OS availability at use.
        let storedAppleIntelligence = defaults.object(forKey: Keys.appleIntelligenceEnabled)
        appleIntelligenceEnabled = storedAppleIntelligence == nil ? true : defaults.bool(forKey: Keys.appleIntelligenceEnabled)
    }

    private enum Keys {
        static let historyMaxItems = "historyMaxItems"
        static let historyMaxDays = "historyMaxDays"
        static let historyUnlimited = "historyUnlimited"
        static let pinLimit = "pinLimit"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let queueModeKeyCode = "queueModeKeyCode"
        static let queueModeModifiers = "queueModeModifiers"
        static let hotCorner = "hotCorner"
        static let hotCornerDelay = "hotCornerDelay"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastSeenVersion = "lastSeenVersion"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let playSoundEffects = "playSoundEffects"
        static let pasteDelay = "pasteDelay"
        static let showInMenuBar = "showInMenuBar"
        // Privacy
        static let showDuringScreenSharing = "showDuringScreenSharing"
        static let generateLinkPreviews = "generateLinkPreviews"
        static let encryptBackups = "encryptBackups"
        static let enableQuickPreview = "enableQuickPreview"
        static let ignoreConfidentialContent = "ignoreConfidentialContent"
        static let ignoreTransientContent = "ignoreTransientContent"
        static let ignoredAppBundleIds = "ignoredAppBundleIds"
        static let displaySize = "displaySize"
        // Intelligence
        static let aiEnrichmentEnabled = "aiEnrichmentEnabled"
        static let ocrEnabled = "ocrEnabled"
        static let semanticSearchEnabled = "semanticSearchEnabled"
        static let autoTaggingEnabled = "autoTaggingEnabled"
        static let sensitiveDataDetectionEnabled = "sensitiveDataDetectionEnabled"
        static let appleIntelligenceEnabled = "appleIntelligenceEnabled"
    }

    // MARK: - Ignored Apps Management

    func addIgnoredApp(_ bundleId: String) {
        if !ignoredAppBundleIds.contains(bundleId) {
            ignoredAppBundleIds.append(bundleId)
        }
    }

    func removeIgnoredApp(_ bundleId: String) {
        ignoredAppBundleIds.removeAll { $0 == bundleId }
    }

    func isAppIgnored(_ bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return ignoredAppBundleIds.contains { $0.lowercased() == bundleId.lowercased() }
    }

    func updateDetectedDisplaySize(for screen: NSScreen) {
        let detectedSize = DisplaySize.detected(for: screen)
        if detectedDisplaySize != detectedSize {
            detectedDisplaySize = detectedSize
        }
    }
}

enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            let identifier = "com.iamngoni.Pastr.LaunchHelper" as CFString
            SMLoginItemSetEnabled(identifier, enabled)
        }
    }
}

enum DisplaySize: String, CaseIterable, Identifiable {
    case auto = "auto"
    case compact = "compact"
    case regular = "regular"
    case large = "large"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto (detect screen)"
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .large: return "Large"
        }
    }

    /// Scale factor for UI elements
    var scaleFactor: CGFloat {
        switch self {
        case .auto: return DisplaySize.regular.scaleFactor
        case .compact: return 0.85
        case .regular: return 1.0
        case .large: return 1.25
        }
    }

    /// Card width in points
    var cardWidth: CGFloat {
        switch self {
        case .auto: return DisplaySize.regular.cardWidth
        case .compact: return 200
        case .regular: return 240
        case .large: return 300
        }
    }

    /// Card height in points
    var cardHeight: CGFloat {
        switch self {
        case .auto: return DisplaySize.regular.cardHeight
        case .compact: return 150
        case .regular: return 180
        case .large: return 225
        }
    }

    /// Panel width in points
    var panelWidth: CGFloat {
        switch self {
        case .auto: return DisplaySize.regular.panelWidth
        case .compact: return 640
        case .regular: return 780
        case .large: return 960
        }
    }

    /// Panel height in points
    var panelHeight: CGFloat {
        switch self {
        case .auto: return DisplaySize.regular.panelHeight
        case .compact: return 420
        case .regular: return 500
        case .large: return 620
        }
    }

    /// Base font size for card content
    var baseFontSize: CGFloat {
        switch self {
        case .auto: return DisplaySize.regular.baseFontSize
        case .compact: return 10
        case .regular: return 12
        case .large: return 14
        }
    }

    static func detected(for screen: NSScreen) -> DisplaySize {
        detected(forEffectivePixelWidth: screen.frame.width * screen.backingScaleFactor)
    }

    static func detected(forEffectivePixelWidth effectiveWidth: CGFloat) -> DisplaySize {
        if effectiveWidth >= 3_840 {
            return .large
        }
        if effectiveWidth >= 2_560 {
            return .regular
        }
        return .compact
    }
}

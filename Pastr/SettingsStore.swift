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

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
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

    @Published var checkForUpdatesAutomatically: Bool {
        didSet { defaults.set(checkForUpdatesAutomatically, forKey: Keys.checkForUpdatesAutomatically) }
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

        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

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

        // Check for updates automatically - default to true
        let storedCheckUpdates = defaults.object(forKey: Keys.checkForUpdatesAutomatically)
        checkForUpdatesAutomatically = storedCheckUpdates == nil ? true : defaults.bool(forKey: Keys.checkForUpdatesAutomatically)
    }

    private enum Keys {
        static let historyMaxItems = "historyMaxItems"
        static let historyMaxDays = "historyMaxDays"
        static let historyUnlimited = "historyUnlimited"
        static let pinLimit = "pinLimit"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
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
        static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
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

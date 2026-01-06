import Carbon
import Combine
import Foundation

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

    private let defaults = UserDefaults.standard

    private init() {
        historyMaxItems = defaults.integer(forKey: Keys.historyMaxItems)
        if historyMaxItems == 0 { historyMaxItems = 100 }

        historyMaxDays = defaults.integer(forKey: Keys.historyMaxDays)
        if historyMaxDays == 0 { historyMaxDays = 30 }

        historyUnlimited = defaults.bool(forKey: Keys.historyUnlimited)

        let storedPinLimit = defaults.integer(forKey: Keys.pinLimit)
        pinLimit = storedPinLimit == 0 ? 5 : storedPinLimit

        let storedKeyCode = defaults.integer(forKey: Keys.hotKeyKeyCode)
        hotKeyKeyCode = storedKeyCode == 0 ? UInt32(kVK_ANSI_B) : UInt32(storedKeyCode)

        let storedModifiers = defaults.integer(forKey: Keys.hotKeyModifiers)
        hotKeyModifiers = storedModifiers == 0 ? UInt32(cmdKey) : UInt32(storedModifiers)

        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    private enum Keys {
        static let historyMaxItems = "historyMaxItems"
        static let historyMaxDays = "historyMaxDays"
        static let historyUnlimited = "historyUnlimited"
        static let pinLimit = "pinLimit"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
}

import AppKit

enum SoundManager {
    static func playPasteSound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Pop")?.play()
    }

    static func playCopySound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Blow")?.play()
    }

    static func playPinSound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Tink")?.play()
    }
}

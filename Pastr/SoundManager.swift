import AppKit

enum SoundManager {
    static func playCopySound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Frog")?.play()
    }

    static func playPinSound() {
        guard SettingsStore.shared.playSoundEffects else { return }
    }
}

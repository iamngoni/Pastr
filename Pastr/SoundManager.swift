import AppKit

enum SoundManager {
    // Volume: 0.0 (silent) to 1.0 (full)
    private static let soundVolume: Float = 0.4

    static func playCopySound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        playSound(named: "Frog")
    }

    static func playPinSound() {
        guard SettingsStore.shared.playSoundEffects else { return }
    }

    private static func playSound(named name: String) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = soundVolume
        sound.play()
    }
}

import AppKit
import AudioToolbox

enum SoundManager {
    static func playPasteSound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        AudioServicesPlaySystemSound(1104) // Paste sound
    }

    static func playCopySound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        AudioServicesPlaySystemSound(1103) // Copy sound
    }

    static func playPinSound() {
        guard SettingsStore.shared.playSoundEffects else { return }
        AudioServicesPlaySystemSound(1057) // Pin/click sound
    }
}

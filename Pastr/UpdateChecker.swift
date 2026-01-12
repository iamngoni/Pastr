import AppKit
import Combine
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var updateURL: URL?

    private let appStoreID = "6740686579" // Your App Store ID
    private let currentVersion: String

    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func checkForUpdates(silent: Bool = true) async {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreID)") else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)

            guard let result = response.results.first else {
                return
            }

            let storeVersion = result.version
            latestVersion = storeVersion
            updateURL = URL(string: result.trackViewUrl)

            if isNewerVersion(storeVersion, than: currentVersion) {
                updateAvailable = true

                if !silent {
                    showUpdateAlert(newVersion: storeVersion)
                }
            } else if !silent {
                showUpToDateAlert()
            }
        } catch {
            print("[Pastr] Failed to check for updates: \(error)")
            if !silent {
                showErrorAlert()
            }
        }
    }

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(newComponents.count, currentComponents.count)

        for i in 0..<maxLength {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0

            if newPart > currentPart {
                return true
            } else if newPart < currentPart {
                return false
            }
        }

        return false
    }

    private func showUpdateAlert(newVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Pastr \(newVersion) is available. You have \(currentVersion). Would you like to update now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openAppStore()
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Pastr \(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Unable to check for updates. Please try again later."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func openAppStore() {
        if let url = updateURL {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback to App Store page
            if let url = URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - App Store API Response

private struct AppStoreLookupResponse: Codable {
    let resultCount: Int
    let results: [AppStoreResult]
}

private struct AppStoreResult: Codable {
    let version: String
    let trackViewUrl: String
}

import AppKit
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var currentPage = 0
    @State private var accessibilityGranted = false
    @State private var isCheckingPermissions = false

    private let totalPages = 3

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)),
                         Color(nsColor: NSColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    permissionsPage.tag(2)
                }
                .tabViewStyle(.automatic)
                .animation(.easeInOut, value: currentPage)

                // Bottom navigation
                bottomNavigation
            }
        }
        .onAppear {
            checkAccessibilityPermission()
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                 Color(red: 0.39, green: 0.71, blue: 1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .shadow(color: Color(red: 0.04, green: 0.52, blue: 1).opacity(0.4), radius: 16, y: 8)
                .overlay(
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white)
                )

            VStack(spacing: 12) {
                Text("Welcome to Pastr")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Your clipboard history, always at hand")
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
            }

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Features Page

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("What you can do")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 16) {
                FeatureRow(
                    icon: "keyboard",
                    title: "Quick Access",
                    description: "Press ⌘B to instantly access your clipboard history"
                )

                FeatureRow(
                    icon: "pin.fill",
                    title: "Pin Important Items",
                    description: "Keep frequently used snippets always available"
                )

                FeatureRow(
                    icon: "text.magnifyingglass",
                    title: "Search & Filter",
                    description: "Quickly find what you copied earlier"
                )

                FeatureRow(
                    icon: "icloud.fill",
                    title: "Sync Across Devices",
                    description: "Enable iCloud sync to access history everywhere"
                )
            }

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Permissions Page

    private var permissionsPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Almost there!")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)

            Text("Pastr needs Accessibility permission to paste items directly into other apps.")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Permission card
            GlassCard(cornerRadius: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accessibilityGranted ?
                                  LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.78, blue: 0.35),
                                             Color(red: 0.35, green: 0.85, blue: 0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  ) :
                                  LinearGradient(
                                    colors: [Color(red: 1, green: 0.58, blue: 0),
                                             Color(red: 1, green: 0.7, blue: 0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: accessibilityGranted ?
                                    Color(red: 0.2, green: 0.78, blue: 0.35).opacity(0.4) :
                                    Color(red: 1, green: 0.58, blue: 0).opacity(0.4),
                                    radius: 8, y: 4)

                        Image(systemName: accessibilityGranted ? "checkmark" : "hand.raised.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Access")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        Text(accessibilityGranted ? "Permission granted" : "Required for pasting")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                    }

                    Spacer()

                    if !accessibilityGranted {
                        Button(action: requestAccessibilityPermission) {
                            Text("Grant")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                                 Color(red: 0.39, green: 0.71, blue: 1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(8)
                                .shadow(color: Color(red: 0.04, green: 0.52, blue: 1).opacity(0.3), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 0.2, green: 0.78, blue: 0.35))
                    }
                }
                .padding(20)
            }
            .padding(.horizontal, 20)

            if !accessibilityGranted {
                Text("You can also grant this later in System Settings → Privacy & Security → Accessibility")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        HStack {
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ?
                              Color(red: 0.04, green: 0.52, blue: 1) :
                              Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }

            Spacer()

            // Navigation buttons
            HStack(spacing: 12) {
                if currentPage > 0 {
                    Button(action: { currentPage -= 1 }) {
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.62))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    if currentPage < totalPages - 1 {
                        currentPage += 1
                    } else {
                        finishOnboarding()
                    }
                }) {
                    Text(currentPage == totalPages - 1 ? "Get Started" : "Continue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                         Color(red: 0.39, green: 0.71, blue: 1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(10)
                        .shadow(color: Color(red: 0.04, green: 0.52, blue: 1).opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .background(
            Color(red: 0.11, green: 0.11, blue: 0.118).opacity(0.8)
        )
    }

    // MARK: - Permission Handling

    private func checkAccessibilityPermission() {
        accessibilityGranted = AXIsProcessTrustedWithOptions(nil)
    }

    private func requestAccessibilityPermission() {
        // First try to prompt via AXIsProcessTrustedWithOptions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let alreadyGranted = AXIsProcessTrustedWithOptions(options)

        if alreadyGranted {
            accessibilityGranted = true
            return
        }

        // Also open System Settings directly to Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Poll for permission changes
        isCheckingPermissions = true
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let granted = AXIsProcessTrustedWithOptions(nil)
            if granted {
                DispatchQueue.main.async {
                    self.accessibilityGranted = true
                    self.isCheckingPermissions = false
                }
                timer.invalidate()
            }
        }
    }

    private func finishOnboarding() {
        // Request accessibility permissions if not already granted
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        onFinish()
        NSApp.keyWindow?.close()
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.04, green: 0.52, blue: 1).opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

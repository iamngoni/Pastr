import AppKit
import SwiftUI

/// Post-update "What's New" sheet, shown once when the app version changes. Mirrors the
/// onboarding visual language.
struct WhatsNewView: View {
    let version: String
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)),
                         Color(nsColor: NSColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        header
                        VStack(spacing: 14) {
                            ForEach(Self.highlights) { highlight in
                                WhatsNewRow(highlight: highlight)
                            }
                        }
                        privacyNote
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 16)
                }

                bottomBar
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                 Color(red: 0.39, green: 0.71, blue: 1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .shadow(color: Color(red: 0.04, green: 0.52, blue: 1).opacity(0.4), radius: 14, y: 6)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                )

            VStack(spacing: 8) {
                Text("What's New in Pastr \(version)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("On-device intelligence — all processed locally")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.2, green: 0.78, blue: 0.35))
            Text("Everything runs on-device. Your clipboard never leaves your Mac.")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
        }
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button(action: {
                onFinish()
                NSApp.keyWindow?.close()
            }) {
                Text("Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
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
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(Color(red: 0.11, green: 0.11, blue: 0.118).opacity(0.8))
    }

    // MARK: - Content

    struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }

    static let highlights: [Highlight] = [
        Highlight(icon: "text.viewfinder",
                  title: "Text in Images",
                  description: "Search and copy text from screenshots with on-device OCR"),
        Highlight(icon: "text.magnifyingglass",
                  title: "Search by Meaning",
                  description: "Find clips by what they mean, not just exact words"),
        Highlight(icon: "tag.fill",
                  title: "Smart Tagging",
                  description: "Clips are classified and tagged automatically"),
        Highlight(icon: "lock.shield",
                  title: "Sensitive Content Protection",
                  description: "Secrets like API keys and passwords are detected and blurred"),
        Highlight(icon: "sparkles",
                  title: "Apple Intelligence",
                  description: "Generate titles, summaries, and \u{201C}Paste As…\u{201D} rewrites on supported Macs"),
    ]
}

// MARK: - Row

private struct WhatsNewRow: View {
    let highlight: WhatsNewView.Highlight

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.04, green: 0.52, blue: 1).opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: highlight.icon)
                        .font(.system(size: 18))
                        .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(highlight.description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
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

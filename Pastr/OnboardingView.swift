import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pastr is ready")
                .font(.title2.weight(.semibold))

            Text("Pastr keeps your clipboard history close at hand. Use Cmd+B to bring up the quick panel and paste instantly.")
                .font(.body)
                .foregroundColor(.secondary)

            Text("You can adjust hotkeys, history limits, and pinning in Settings.")
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Get Started") {
                    onFinish()
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}

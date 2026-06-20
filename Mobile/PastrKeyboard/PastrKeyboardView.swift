import SwiftUI

enum PastrKeyboardActionResult {
    case inserted
    case copied
    case unavailable

    var message: String {
        switch self {
        case .inserted:
            return "Inserted"
        case .copied:
            return "Copied"
        case .unavailable:
            return "Unavailable"
        }
    }
}

struct PastrKeyboardView: View {
    let clips: [PastrClip]
    let onClipTap: (PastrClip) -> PastrKeyboardActionResult
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onNextKeyboard: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedClipId: PastrClip.ID?
    @State private var actionMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if clips.isEmpty {
                KeyboardEmptyState()
                    .padding(.horizontal, 12)
            } else {
                GeometryReader { proxy in
                    let cardWidth = max(104, min(126, (proxy.size.width - 34) / 3))
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(clips) { clip in
                                KeyboardClipCard(
                                    clip: clip,
                                    isSelected: selectedClipId == clip.id,
                                    width: cardWidth,
                                    onTap: {
                                        selectedClipId = clip.id
                                        let result = onClipTap(clip)
                                        actionMessage = result.message
                                        clearActionMessage()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .frame(height: 132)
            }

            Spacer(minLength: 0)

            utilityRow
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .background(keyboardBackground)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Pastr")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PastrTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let actionMessage {
                Text(actionMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            Spacer(minLength: 4)

            Button(action: onNextKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 19, weight: .medium))
            }
            .buttonStyle(KeyboardIconButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var utilityRow: some View {
        HStack(spacing: 7) {
            Button(action: onNextKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 22, weight: .medium))
            }
            .buttonStyle(KeyboardUtilityButtonStyle(width: 54))

            Button("ABC", action: onNextKeyboard)
                .font(.system(size: 18, weight: .semibold))
                .buttonStyle(KeyboardUtilityButtonStyle(width: 82))

            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(KeyboardUtilityButtonStyle(width: 68))

            Button(action: onReturn) {
                Image(systemName: "return")
                    .font(.system(size: 22, weight: .bold))
            }
            .buttonStyle(KeyboardUtilityButtonStyle(width: 104, isPrimary: true))

            Button(action: {}) {
                Image(systemName: "mic")
                    .font(.system(size: 22, weight: .medium))
            }
            .buttonStyle(KeyboardUtilityButtonStyle(width: 54))
        }
    }

    private func clearActionMessage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeOut(duration: 0.16)) {
                actionMessage = nil
            }
        }
    }

    private var keyboardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(red: 0.06, green: 0.065, blue: 0.075))
            : AnyShapeStyle(Color(red: 0.93, green: 0.94, blue: 0.96))
    }
}

private struct KeyboardEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PastrTheme.accent)
            Text("No clips")
                .font(.system(size: 15, weight: .semibold))
            Text("Open Pastr to sync.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 142)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct KeyboardClipCard: View {
    let clip: PastrClip
    let isSelected: Bool
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                cardBackground
                cardContent
            }
            .frame(width: width, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? PastrTheme.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if clip.type == .image {
            ClipThumbnail(clip: clip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.04), .black.opacity(0.58)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if clip.type == .image {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    KeyboardTypeBadge(title: "Image", symbol: "photo.fill", tint: .white.opacity(0.92))
                    Spacer()
                    Text(clip.relativeTime)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                }
                Spacer()
                Text(clip.sourceAppName ?? clip.source)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(9)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(PastrTheme.tint(clip.tintName).opacity(0.14))
                        Image(systemName: clip.isPinned ? "pin.fill" : clip.type.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PastrTheme.tint(clip.tintName))
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(clip.type.label)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                        Text(clip.relativeTime)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                ClipThumbnail(clip: clip)
                    .frame(height: 30)

                Text(clip.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(clip.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct KeyboardTypeBadge: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(.black.opacity(0.26), in: Capsule())
    }
}

private struct KeyboardIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .frame(width: 36, height: 32)
            .background(.regularMaterial, in: Circle())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct KeyboardUtilityButtonStyle: ButtonStyle {
    let width: CGFloat
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? .white : .primary)
            .frame(width: width, height: 44)
            .background(isPrimary ? PastrTheme.accent : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

#Preview {
    PastrKeyboardView(
        clips: PastrSampleClips.clips,
        onClipTap: { _ in .inserted },
        onDelete: {},
        onReturn: {},
        onNextKeyboard: {}
    )
}

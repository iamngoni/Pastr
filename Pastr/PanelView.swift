import SwiftUI

struct PanelView: View {
    @ObservedObject var historyStore: ClipboardHistoryStore
    let onSelect: (ClipboardItem) -> Void

    @State private var selectedSection: PanelSection = .history

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(spacing: 12) {
                header
                cards
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ForEach(PanelSection.allCases, id: \.self) { section in
                Button {
                    selectedSection = section
                } label: {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selectedSection == section ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedSection == section ? Color.white.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var cards: some View {
        let items = historyStore.items(for: selectedSection)

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    ClipboardCardView(item: item)
                        .onTapGesture {
                            onSelect(item)
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ClipboardCardView: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = item.sourceAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .cornerRadius(3)
                }

                Text(item.type.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text(item.relativeTime)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Group {
                switch item.type {
                case .image:
                    if let image = item.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 90)
                            .clipped()
                            .cornerRadius(8)
                    } else {
                        Text("Image")
                            .foregroundColor(.white.opacity(0.7))
                    }
                case .text, .richText, .other:
                    Text(item.previewText)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(4)
                case .link:
                    Text(item.previewText)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(3)
                case .file:
                    Text(item.previewText)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 180, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }
}

enum PanelSection: CaseIterable {
    case history
    case pinned

    var title: String {
        switch self {
        case .history: return "History"
        case .pinned: return "Pinned"
        }
    }
}

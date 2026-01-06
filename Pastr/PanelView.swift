import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    let onSelect: (ClipboardItem) -> Void
    let onTogglePin: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onPastePlainText: (ClipboardItem) -> Void
    let onOpenLink: (ClipboardItem) -> Void
    let onRevealInFinder: (ClipboardItem) -> Void
    let onUpdatePinnedTitle: (ClipboardItem, String) -> Void

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
                    viewModel.selectedSection = section
                    viewModel.resetSelection()
                } label: {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(viewModel.selectedSection == section ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(viewModel.selectedSection == section ? Color.white.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var cards: some View {
        let items = viewModel.items

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ClipboardCardView(
                        item: item,
                        isSelected: index == viewModel.selectedIndex,
                        onTogglePin: { onTogglePin(item) }
                    )
                    .onTapGesture {
                        viewModel.selectItem(item)
                        onSelect(item)
                    }
                    .contextMenu {
                        contextMenu(for: item)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        if item.isPinned {
            Button("Unpin") { onTogglePin(item) }
            Button("Edit Title…") { promptForTitle(item: item) }
        } else {
            Button("Pin") { onTogglePin(item) }
        }
        Divider()
        Button("Copy to Clipboard") { onCopy(item) }
        if item.plainText != nil {
            Button("Paste as Plain Text") { onPastePlainText(item) }
        }
        if item.type == .link, item.urlString != nil {
            Button("Open Link") { onOpenLink(item) }
        }
        if item.type == .file, !item.fileURLs.isEmpty {
            Button("Reveal in Finder") { onRevealInFinder(item) }
        }
    }

    private func promptForTitle(item: ClipboardItem) {
        let alert = NSAlert()
        alert.messageText = "Pinned Title"
        alert.informativeText = "Set a custom label for this pinned item."
        let field = NSTextField(string: item.pinnedTitle ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            onUpdatePinnedTitle(item, field.stringValue)
        }
    }
}

private struct ClipboardCardView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onTogglePin: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let icon = item.sourceAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .cornerRadius(3)
                    }

                    if let appName = item.sourceAppName {
                        Text(appName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(item.type.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))

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
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
            )

            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(item.isPinned ? 0.9 : 0.6))
                    .padding(6)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
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

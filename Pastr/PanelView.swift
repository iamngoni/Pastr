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
    let onDelete: ([ClipboardItem]) -> Void
    let onOpenSettings: () -> Void

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
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                NonCapturingTextField(
                    text: $viewModel.searchText,
                    placeholder: "Search",
                    onArrowLeft: { viewModel.selectPrevious() },
                    onArrowRight: { viewModel.selectNext() }
                )
                .frame(height: 18)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .frame(width: 180)

            // Section tabs
            ForEach(PanelSection.allCases, id: \.self) { section in
                Button {
                    viewModel.selectedSection = section
                    viewModel.selectedIndex = 0
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

            // Settings button
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(viewModel.items) { item in
                        ClipboardCardView(
                            item: item,
                            isSelected: viewModel.isSelected(item),
                            onTogglePin: { onTogglePin(item) }
                        )
                        .id(item.id)
                        .onDrag { item.itemProvider() }
                        .onHover { hovering in
                            viewModel.hoverPreview(for: item, isHovering: hovering)
                        }
                        .popover(isPresented: previewBinding(for: item)) {
                            ClipboardPreviewView(item: item)
                                .frame(width: 360, height: 260)
                        }
                        .gesture(
                            TapGesture()
                                .modifiers(.command)
                                .onEnded { _ in
                                    viewModel.toggleSelection(for: item)
                                }
                        )
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    if !NSEvent.modifierFlags.contains(.command) {
                                        viewModel.selectItem(item)
                                        onSelect(item)
                                    }
                                }
                        )
                        .contextMenu {
                            contextMenu(for: item)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) {
                if let selectedItem = viewModel.selectedItem {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedItem.id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button {
            viewModel.showPreview(item, source: .explicit)
        } label: {
            Label("Preview", systemImage: "eye")
        }
        .keyboardShortcut(.space, modifiers: [])

        // Paste action
        Button {
            onSelect(item)
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut(.return, modifiers: [])

        // Paste as Plain Text
        if item.plainText != nil {
            Button {
                onPastePlainText(item)
            } label: {
                Label("Paste as Plain Text", systemImage: "text.alignleft")
            }
            .keyboardShortcut(.return, modifiers: [.shift, .command])
        }

        // Copy
        Button {
            onCopy(item)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .keyboardShortcut("c", modifiers: .command)

        Divider()

        // Delete
        Button(role: .destructive) {
            if viewModel.hasMultipleSelection {
                onDelete(viewModel.selectedItems)
                viewModel.clearMultiSelection()
            } else {
                onDelete([item])
            }
        } label: {
            if viewModel.hasMultipleSelection {
                Label("Delete Selected (\(viewModel.selectedItems.count))", systemImage: "trash")
            } else {
                Label("Delete", systemImage: "trash")
            }
        }
        .keyboardShortcut(.delete, modifiers: [])

        Divider()

        // Pin (simple toggle, no submenu)
        Button {
            onTogglePin(item)
        } label: {
            if item.isPinned {
                Label("Unpin", systemImage: "pin.slash")
            } else {
                Label("Pin", systemImage: "pin")
            }
        }

        // Open Link (for links)
        if item.type == .link, item.urlString != nil {
            Button {
                onOpenLink(item)
            } label: {
                Label("Open Link", systemImage: "safari")
            }
        }

        // Reveal in Finder (for files)
        if item.type == .file, !item.fileURLs.isEmpty {
            Button {
                onRevealInFinder(item)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }

        // Share submenu
        Menu {
            Button {
                shareItem(item)
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func shareItem(_ item: ClipboardItem) {
        let content: Any
        if let text = item.textContent {
            content = text
        } else if let image = item.image {
            content = image
        } else if !item.fileURLs.isEmpty {
            content = item.fileURLs
        } else {
            content = item.previewText
        }

        let picker = NSSharingServicePicker(items: [content])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func previewBinding(for item: ClipboardItem) -> Binding<Bool> {
        Binding(
            get: { viewModel.previewItem?.id == item.id },
            set: { isPresented in
                if !isPresented, viewModel.previewItem?.id == item.id {
                    viewModel.clearPreview()
                }
            }
        )
    }
}

private struct ClipboardCardView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onTogglePin: () -> Void
    @ObservedObject private var linkService = LinkPreviewService.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                // First row: App info and pin button space
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
                }
                .padding(.trailing, 32) // Space for pin button

                // Second row: Type and time
                HStack(spacing: 6) {
                    Text(item.type.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))

                    Text(item.relativeTime)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()
                }

                Group {
                    switch item.type {
                    case .image:
                        if let image = item.image {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 204, height: 120)
                                .clipped()
                                .cornerRadius(8)
                        } else {
                            Text("Image")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    case .richText:
                        if let attributed = item.attributedPreview {
                            Text(attributed)
                                .font(.system(size: 10))
                                .lineLimit(10)
                        } else {
                            Text(item.previewText)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .lineLimit(10)
                        }
                    case .text, .other:
                        if SyntaxHighlighter.isLikelyCode(item.previewText) {
                            Text(SyntaxHighlighter.highlightedAttributedString(item.previewText))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .lineLimit(10)
                        } else {
                            Text(item.previewText)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .lineLimit(6)
                        }
                    case .link:
                        LinkPreviewCard(urlString: item.urlString ?? item.previewText)
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
            .frame(width: 240, height: 180)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.6 : 1)
            )
            .shadow(color: isSelected ? Color.white.opacity(0.25) : .clear, radius: 6, x: 0, y: 0)

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

// MARK: - Non-Capturing TextField

struct NonCapturingTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onArrowLeft: () -> Void
    let onArrowRight: () -> Void

    func makeNSView(context: Context) -> ArrowPassingTextField {
        let field = ArrowPassingTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        field.onArrowLeft = onArrowLeft
        field.onArrowRight = onArrowRight
        return field
    }

    func updateNSView(_ nsView: ArrowPassingTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: NonCapturingTextField

        init(_ parent: NonCapturingTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
    }
}

final class ArrowPassingTextField: NSTextField {
    var onArrowLeft: (() -> Void)?
    var onArrowRight: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: // Left arrow
            onArrowLeft?()
        case 124: // Right arrow
            onArrowRight?()
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Link Preview Card

private struct LinkPreviewCard: View {
    let urlString: String
    let domain: String // Pre-computed to avoid URL parsing in body
    @ObservedObject private var linkService = LinkPreviewService.shared

    init(urlString: String) {
        self.urlString = urlString
        // Compute domain once in init, not on every body evaluation
        if let url = URL(string: urlString), let host = url.host {
            self.domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else {
            self.domain = urlString
        }
    }

    private var preview: LinkPreview? {
        linkService.preview(for: urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Large preview image (Open Graph image)
            if let image = preview?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 90)
                    .clipped()
                    .cornerRadius(8)
            } else {
                // Gradient placeholder with link icon
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.25, blue: 0.45),
                                Color(red: 0.25, green: 0.15, blue: 0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 90)
                    .overlay(
                        Image(systemName: "link")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }

            // Bottom section with icon, title, and URL
            VStack(alignment: .leading, spacing: 4) {
                // Site info row
                HStack(spacing: 6) {
                    if let icon = preview?.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .cornerRadius(3)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(domain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                // Title
                if let title = preview?.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            linkService.fetchPreview(for: urlString)
        }
    }
}

// MARK: - Clipboard Preview

private struct ClipboardPreviewView: View {
    let item: ClipboardItem
    @ObservedObject private var linkService = LinkPreviewService.shared

    private var preview: LinkPreview? {
        guard let urlString = item.urlString else { return nil }
        return linkService.preview(for: urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon = item.sourceAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.sourceAppName ?? "Unknown App")
                        .font(.system(size: 12, weight: .semibold))
                    Text(item.relativeTime)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(item.type.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Divider()

            Group {
                switch item.type {
                case .image:
                    if let image = item.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 160)
                            .cornerRadius(8)
                    } else {
                        Text("Image")
                            .foregroundColor(.secondary)
                    }
                case .richText:
                    ScrollView {
                        if let attributed = item.attributedPreview {
                            Text(attributed)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(item.previewText)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .text, .other:
                    ScrollView {
                        if SyntaxHighlighter.isLikelyCode(item.previewText) {
                            Text(SyntaxHighlighter.highlightedAttributedString(item.previewText))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(item.previewText)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .link:
                    VStack(alignment: .leading, spacing: 8) {
                        if let image = preview?.image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 110)
                                .clipped()
                                .cornerRadius(8)
                        }
                        Text(preview?.title ?? item.previewText)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        if let urlString = item.urlString {
                            Text(urlString)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                case .file:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(item.fileURLs, id: \.self) { url in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(url.path)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .onAppear {
            if let urlString = item.urlString {
                linkService.fetchPreview(for: urlString)
            }
        }
    }
}

import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @ObservedObject private var historyStore = ClipboardHistoryStore.shared
    let onSelect: (ClipboardItem) -> Void
    let onTogglePin: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onCopyPlainText: (ClipboardItem) -> Void
    let onOpenLink: (ClipboardItem) -> Void
    let onRevealInFinder: (ClipboardItem) -> Void
    let onDelete: ([ClipboardItem]) -> Void
    let onOpenSettings: () -> Void
    let onAddToCollection: ((ClipboardItem, UUID) -> Void)?
    let onRemoveFromCollection: ((ClipboardItem, UUID) -> Void)?

    init(
        viewModel: PanelViewModel,
        onSelect: @escaping (ClipboardItem) -> Void,
        onTogglePin: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onCopyPlainText: @escaping (ClipboardItem) -> Void,
        onOpenLink: @escaping (ClipboardItem) -> Void,
        onRevealInFinder: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping ([ClipboardItem]) -> Void,
        onOpenSettings: @escaping () -> Void,
        onAddToCollection: ((ClipboardItem, UUID) -> Void)? = nil,
        onRemoveFromCollection: ((ClipboardItem, UUID) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onTogglePin = onTogglePin
        self.onCopy = onCopy
        self.onCopyPlainText = onCopyPlainText
        self.onOpenLink = onOpenLink
        self.onRevealInFinder = onRevealInFinder
        self.onDelete = onDelete
        self.onOpenSettings = onOpenSettings
        self.onAddToCollection = onAddToCollection
        self.onRemoveFromCollection = onRemoveFromCollection
    }

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
        .sheet(isPresented: $viewModel.showingCreateCollection) {
            CreateCollectionSheet(collectionStore: collectionStore) { newCollection in
                viewModel.selectedSection = .collection(newCollection.id)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer()

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

            // History tab
            Button {
                viewModel.selectedSection = .history
                viewModel.selectedIndex = 0
            } label: {
                Text("History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(viewModel.selectedSection == .history ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(viewModel.selectedSection == .history ? Color.white.opacity(0.18) : Color.clear)
                    )
            }
            .buttonStyle(.plain)

            // Collections menu
            Menu {
                // Show all collections with checkmark for currently selected
                ForEach(collectionStore.collections) { collection in
                    Button {
                        viewModel.selectedSection = .collection(collection.id)
                        viewModel.selectedIndex = 0
                    } label: {
                        HStack {
                            Image(systemName: collection.icon)
                            Text(collection.name)
                            if case .collection(let id) = viewModel.selectedSection, id == collection.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !collectionStore.collections.isEmpty {
                    Divider()
                }

                // Create new collection
                Button {
                    viewModel.showingCreateCollection = true
                } label: {
                    Label("New Collection...", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                    Text(collectionsTabTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(isCollectionSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCollectionSelected ? Color.white.opacity(0.18) : Color.clear)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Add Files button (only when viewing a collection)
            if case .collection(let collectionId) = viewModel.selectedSection {
                Button {
                    addFilesToCollection(collectionId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add Files")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }

            // Tags menu
            if !tagStore.tags.isEmpty {
                Menu {
                    ForEach(tagStore.tags) { tag in
                        Button {
                            viewModel.selectedSection = .tag(tag.id)
                            viewModel.selectedIndex = 0
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: tag.color))
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                if case .tag(let id) = viewModel.selectedSection, id == tag.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 11))
                        Text(tagsTabTitle)
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(isTagSelected ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isTagSelected ? Color.white.opacity(0.18) : Color.clear)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

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

            Spacer()
        }
    }

    private func addFilesToCollection(_ collectionId: UUID) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select files to add to collection"
        panel.prompt = "Add"

        panel.begin { response in
            if response == .OK {
                let urls = panel.urls
                _ = collectionStore.addFiles(urls, to: collectionId, historyStore: historyStore)
                SoundManager.playPinSound()
            }
        }
    }

    private var isCollectionSelected: Bool {
        if case .collection = viewModel.selectedSection {
            return true
        }
        return false
    }

    private var collectionsTabTitle: String {
        if case .collection(let id) = viewModel.selectedSection,
           let collection = collectionStore.collections.first(where: { $0.id == id }) {
            return collection.name
        }
        return "Collections"
    }

    private var isTagSelected: Bool {
        if case .tag = viewModel.selectedSection {
            return true
        }
        return false
    }

    private var tagsTabTitle: String {
        if case .tag(let id) = viewModel.selectedSection,
           let tag = tagStore.tags.first(where: { $0.id == id }) {
            return tag.name
        }
        return "Tags"
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

        // Copy action
        Button {
            onSelect(item)
        } label: {
            Label("Copy", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut(.return, modifiers: [])

        // Copy as plain text
        if item.plainText != nil {
            Button {
                onCopyPlainText(item)
            } label: {
                Label("Copy Plain Text", systemImage: "text.alignleft")
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

        // Collections submenu
        if !collectionStore.collections.isEmpty {
            Menu {
                ForEach(collectionStore.collections) { collection in
                    let isInCollection = collection.contains(fingerprint: item.fingerprint)
                    Button {
                        if isInCollection {
                            onRemoveFromCollection?(item, collection.id)
                        } else {
                            onAddToCollection?(item, collection.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: collection.icon)
                            Text(collection.name)
                            if isInCollection {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Collections", systemImage: "folder")
            }
        }

        // Tags submenu
        Menu {
            if tagStore.tags.isEmpty {
                Text("No tags yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(tagStore.tags) { tag in
                    let hasTag = tagStore.hasTag(tag.id, fingerprint: item.fingerprint)
                    Button {
                        tagStore.toggleTag(tag.id, for: item.fingerprint)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: tag.color))
                                .frame(width: 8, height: 8)
                            Text(tag.name)
                            if hasTag {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                // Open settings to tag management
                onOpenSettings()
            } label: {
                Label("Manage Tags...", systemImage: "gear")
            }
        } label: {
            Label("Tags", systemImage: "tag")
        }

        // Legacy Pin (simple toggle, for backward compatibility)
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
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    private var itemCollections: [Collection] {
        collectionStore.collections(containing: item.fingerprint)
    }

    private var itemTags: [Tag] {
        tagStore.tags(for: item.fingerprint)
    }

    private var displaySize: DisplaySize {
        settings.displaySize
    }

    /// Color tint based on clipboard item type
    private var typeColor: Color {
        switch item.type {
        case .text:
            return Color.blue
        case .richText:
            return Color.cyan
        case .image:
            return Color.green
        case .link:
            return Color.purple
        case .file:
            return Color.orange
        case .other:
            return Color.gray
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                // First row: App info and pin button space
                HStack(spacing: 6) {
                    if let icon = item.sourceAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14 * displaySize.scaleFactor, height: 14 * displaySize.scaleFactor)
                            .cornerRadius(3)
                    }

                    if let appName = item.sourceAppName {
                        Text(appName)
                            .font(.system(size: 11 * displaySize.scaleFactor, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.trailing, 32) // Space for pin button

                // Second row: Type and time
                HStack(spacing: 6) {
                    Text(item.type.label)
                        .font(.system(size: 10 * displaySize.scaleFactor, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))

                    Text(item.relativeTime)
                        .font(.system(size: 10 * displaySize.scaleFactor))
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
                                .frame(width: displaySize.cardWidth - 36, height: displaySize.cardHeight * 0.67)
                                .clipped()
                                .cornerRadius(8)
                        } else {
                            Text("Image")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    case .richText:
                        if let attributed = item.attributedPreview {
                            Text(attributed)
                                .font(.system(size: displaySize.baseFontSize - 2))
                                .lineLimit(10)
                        } else {
                            Text(item.previewText)
                                .font(.system(size: displaySize.baseFontSize - 2))
                                .foregroundColor(.white)
                                .lineLimit(10)
                        }
                    case .text, .other:
                        if SyntaxHighlighter.isLikelyCode(item.previewText) {
                            Text(SyntaxHighlighter.highlightedAttributedString(item.previewText))
                                .font(.system(size: displaySize.baseFontSize - 2, weight: .regular, design: .monospaced))
                                .lineLimit(10)
                        } else {
                            Text(item.previewText)
                                .font(.system(size: displaySize.baseFontSize))
                                .foregroundColor(.white)
                                .lineLimit(6)
                        }
                    case .link:
                        LinkPreviewCard(urlString: item.urlString ?? item.previewText)
                    case .file:
                        Text(item.previewText)
                            .font(.system(size: displaySize.baseFontSize))
                            .foregroundColor(.white)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12 * displaySize.scaleFactor)
            .frame(width: displaySize.cardWidth, height: displaySize.cardHeight)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(typeColor.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.6 : 1)
            )
            .shadow(color: isSelected ? Color.white.opacity(0.25) : .clear, radius: 6, x: 0, y: 0)

            VStack(alignment: .trailing, spacing: 4 * displaySize.scaleFactor) {
                // Pin button
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12 * displaySize.scaleFactor, weight: .semibold))
                        .foregroundColor(.white.opacity(item.isPinned ? 0.9 : 0.6))
                        .padding(6 * displaySize.scaleFactor)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .buttonStyle(.plain)

                // Collection indicators
                if !itemCollections.isEmpty {
                    HStack(spacing: 2 * displaySize.scaleFactor) {
                        ForEach(itemCollections.prefix(3)) { collection in
                            Circle()
                                .fill(Color(hex: collection.color))
                                .frame(width: 8 * displaySize.scaleFactor, height: 8 * displaySize.scaleFactor)
                        }
                        if itemCollections.count > 3 {
                            Text("+\(itemCollections.count - 3)")
                                .font(.system(size: 8 * displaySize.scaleFactor, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 6 * displaySize.scaleFactor)
                    .padding(.vertical, 3 * displaySize.scaleFactor)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                    )
                }

                // Tag indicators
                if !itemTags.isEmpty {
                    HStack(spacing: 2 * displaySize.scaleFactor) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 7 * displaySize.scaleFactor))
                            .foregroundColor(.white.opacity(0.6))
                        ForEach(itemTags.prefix(2)) { tag in
                            Text(tag.name)
                                .font(.system(size: 7 * displaySize.scaleFactor, weight: .medium))
                                .foregroundColor(Color(hex: tag.color))
                        }
                        if itemTags.count > 2 {
                            Text("+\(itemTags.count - 2)")
                                .font(.system(size: 7 * displaySize.scaleFactor, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 6 * displaySize.scaleFactor)
                    .padding(.vertical, 3 * displaySize.scaleFactor)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                    )
                }
            }
            .padding(6)
        }
    }
}

enum PanelSection: Hashable {
    case history
    case pinned
    case collection(UUID)
    case tag(UUID)

    var title: String {
        switch self {
        case .history: return "History"
        case .pinned: return "Collections"
        case .collection(let id):
            if let collection = CollectionStore.shared.collections.first(where: { $0.id == id }) {
                return collection.name
            }
            return "Collection"
        case .tag(let id):
            if let tag = TagStore.shared.tags.first(where: { $0.id == id }) {
                return tag.name
            }
            return "Tag"
        }
    }

    static var defaultSections: [PanelSection] {
        [.history, .pinned]
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

// MARK: - Create Collection Sheet

private struct CreateCollectionSheet: View {
    @ObservedObject var collectionStore: CollectionStore
    let onCreated: (Collection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedIcon: String = "folder.fill"
    @State private var selectedColor: String = "#007AFF"

    var body: some View {
        VStack(spacing: 20) {
            Text("New Collection")
                .font(.headline)

            // Name field
            TextField("Collection name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 8), spacing: 8) {
                    ForEach(Collection.availableIcons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(selectedIcon == icon ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(Collection.availableColors, id: \.hex) { colorOption in
                        Button {
                            selectedColor = colorOption.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: colorOption.hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .strokeBorder(selectedColor == colorOption.hex ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .shadow(color: selectedColor == colorOption.hex ? .black.opacity(0.3) : .clear, radius: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    let collection = collectionStore.create(
                        name: name.isEmpty ? "New Collection" : name,
                        icon: selectedIcon,
                        color: selectedColor
                    )
                    onCreated(collection)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

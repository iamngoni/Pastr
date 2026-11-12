import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    // Not observed: the panel doesn't render from these directly, and observing them made
    // the (often hidden) panel redo SwiftUI work on every copy/enrichment (Sentry PASTR-3K).
    // PanelWindowController forces a refresh each time the panel is shown.
    private let historyStore = ClipboardHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    private let enrichmentStore = AIEnrichmentStore.shared
    @StateObject private var ai = PanelAIController()
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    // Dark tint keeps the glass (and white text) consistent over bright windows.
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.32))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )

            // AnyView boundaries keep the root view's generic type shallow; resolving the
            // fully nested type at launch was a measurable hang (Sentry PASTR-3T).
            VStack(spacing: 12) {
                AnyView(header.padding(.horizontal, 16))
                AnyView(cards)
            }
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The panel is always styled as a dark glass surface (white text on material);
        // pin the color scheme so light mode doesn't produce white-on-light.
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .bottom) {
            if let banner = ai.banner {
                aiBanner(banner)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ai.banner)
        .sheet(isPresented: $viewModel.showingCreateCollection) {
            CreateCollectionSheet(collectionStore: collectionStore) { newCollection in
                viewModel.selectedSection = .collection(newCollection.id)
            }
        }
    }

    private var header: some View {
        ZStack {
            // Leading: search. Trailing: count + settings.
            HStack(spacing: 10) {
                searchField
                Spacer(minLength: 12)
                Text(itemCountLabel)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.45))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: viewModel.items.count)

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            // Centered section switcher
            sectionSwitcher
        }
    }

    private var itemCountLabel: String {
        let count = viewModel.items.count
        return count == 1 ? "1 clip" : "\(count) clips"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            TextField("Search clips", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onKeyPress(.leftArrow) {
                    viewModel.selectPrevious()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    viewModel.selectNext()
                    return .handled
                }
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
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .frame(width: 220)
        .animation(.easeOut(duration: 0.15), value: viewModel.searchText.isEmpty)
    }

    private var sectionSwitcher: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.selectedSection = .history
                viewModel.selectedIndex = 0
            } label: {
                SectionTabLabel(
                    title: "History",
                    systemImage: "clock",
                    isSelected: viewModel.selectedSection == .history,
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)

            Menu {
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

                Button {
                    viewModel.showingCreateCollection = true
                } label: {
                    Label("New Collection...", systemImage: "plus")
                }
            } label: {
                SectionTabLabel(
                    title: collectionsTabTitle,
                    systemImage: "folder",
                    isSelected: isCollectionSelected,
                    showsChevron: true
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

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
                    SectionTabLabel(
                        title: tagsTabTitle,
                        systemImage: "tag",
                        isSelected: isTagSelected,
                        showsChevron: true
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if case .collection(let collectionId) = viewModel.selectedSection {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)
                Button {
                    addFilesToCollection(collectionId)
                } label: {
                    SectionTabLabel(
                        title: "Add Files",
                        systemImage: "plus",
                        isSelected: false,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .help("Add files to this collection")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.15), value: viewModel.selectedSection)
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
        let displaySize = settings.resolvedDisplaySize
        return ZStack {
            if viewModel.items.isEmpty {
                emptyState
                    .frame(height: displaySize.cardHeight + 12)
                    .transition(.opacity)
            } else {
                cardScroller(displaySize: displaySize)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.items.isEmpty)
    }

    private func cardScroller(displaySize: DisplaySize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(viewModel.items) { item in
                        ClipboardCardView(
                            item: item,
                            isSelected: viewModel.isSelected(item),
                            collectionColors: collectionStore.collections(containing: item.fingerprint).map(\.color),
                            tags: tagStore.tags(for: item.fingerprint),
                            displaySize: displaySize,
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
                // Inset content so the first/last card (and its selection ring)
                // sits clear of the edge fade.
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .mask(edgeFade)
            .onChange(of: viewModel.selectedIndex) {
                if let selectedItem = viewModel.selectedItem {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedItem.id, anchor: .center)
                    }
                }
            }
        }
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
            Rectangle().fill(Color.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
        }
    }

    private var emptyState: some View {
        let content = emptyStateContent
        return VStack(spacing: 8) {
            Image(systemName: content.icon)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.white.opacity(0.35))
            Text(content.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Text(content.message)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateContent: (icon: String, title: String, message: String) {
        if !viewModel.searchText.isEmpty {
            return (
                "magnifyingglass",
                "No matches for “\(viewModel.searchText)”",
                "Try a different word, or search by what's in an image or what a clip means."
            )
        }
        switch viewModel.selectedSection {
        case .history, .pinned:
            return (
                "doc.on.clipboard",
                "Nothing copied yet",
                "Copy anything — text, links, images or files — and it will show up here."
            )
        case .collection:
            return (
                "folder",
                "This collection is empty",
                "Right-click a clip and choose Collections, or use Add Files."
            )
        case .tag:
            return (
                "tag",
                "No clips with this tag",
                "Right-click a clip and choose Tags to add it here."
            )
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

        // Paste into the previously focused app
        Button {
            onSelect(item)
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
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

        aiMenu(for: item)

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

    // MARK: - Intelligence menu

    @ViewBuilder
    private func aiMenu(for item: ClipboardItem) -> some View {
        let hasOCRText = enrichmentStore.searchableText(for: item.fingerprint) != nil
        let hasText = item.plainText != nil || hasOCRText
        let hasSuggestions = !enrichmentStore.tagSuggestions(for: item.fingerprint).isEmpty
        let aiOn = settings.appleIntelligenceEnabled
        let aiAvailable = ai.appleIntelligenceAvailable

        let showsAnything = (settings.aiEnrichmentEnabled && (hasOCRText || hasSuggestions))
            || (aiOn && hasText)

        if showsAnything {
            Divider()

            if settings.aiEnrichmentEnabled && hasOCRText {
                Button {
                    ai.copyRecognizedText(item)
                } label: {
                    Label("Copy Recognized Text", systemImage: "text.viewfinder")
                }
            }

            if settings.aiEnrichmentEnabled && hasSuggestions {
                Button {
                    ai.applySuggestedTags(item)
                } label: {
                    Label("Apply Suggested Tags", systemImage: "tag.fill")
                }
            }

            if aiOn && hasText {
                Menu {
                    if aiAvailable {
                        Button {
                            ai.generateTitle(for: item)
                        } label: {
                            Label("Generate Title", systemImage: "textformat")
                        }
                        Button {
                            ai.summarize(item)
                        } label: {
                            Label("Summarize", systemImage: "text.append")
                        }
                        Divider()
                        Menu {
                            ForEach(TextTransform.allCases) { transform in
                                Button {
                                    ai.transform(item, transform)
                                } label: {
                                    Label(transform.label, systemImage: transform.systemImage)
                                }
                            }
                        } label: {
                            Label("Paste As…", systemImage: "sparkles")
                        }
                    } else {
                        Text(enrichmentStore.appleIntelligenceAvailability.message)
                    }
                } label: {
                    Label("Apple Intelligence", systemImage: "sparkles")
                }
            }
        }
    }

    @ViewBuilder
    private func aiBanner(_ banner: PanelAIController.Banner) -> some View {
        HStack(spacing: 8) {
            switch banner.kind {
            case .progress:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            }
            Text(banner.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
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

private struct SectionTabLabel: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let showsChevron: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
        }
        .foregroundColor(isSelected ? .white : .white.opacity(isHovering ? 0.85 : 0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.16 : (isHovering ? 0.07 : 0)))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Clip card. Takes everything it renders as plain values so it doesn't observe
/// the shared stores itself — a change in any store would otherwise redraw every card.
private struct ClipboardCardView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let collectionColors: [String]
    let tags: [Tag]
    let displaySize: DisplaySize
    let onTogglePin: () -> Void

    @State private var isHovering = false

    private var scale: CGFloat { displaySize.scaleFactor }
    private var typeColor: Color { item.type.tint }
    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 9 * scale) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !collectionColors.isEmpty || !tags.isEmpty {
                footer
            }
        }
        .padding(12 * scale)
        .frame(width: displaySize.cardWidth, height: displaySize.cardHeight)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(
            color: isSelected ? Color.white.opacity(0.18) : Color.black.opacity(isHovering ? 0.35 : 0.2),
            radius: isSelected ? 8 : (isHovering ? 8 : 4),
            y: isSelected ? 0 : (isHovering ? 4 : 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .center, spacing: 8 * scale) {
            SourceAppIconView(item: item, size: 20 * scale)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.sourceAppName ?? "Unknown App")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 4 * scale) {
                    Image(systemName: item.type.symbolName)
                        .font(.system(size: 8 * scale, weight: .bold))
                        .foregroundColor(typeColor)
                    Text(item.type.label)
                        .foregroundColor(typeColor.opacity(0.95))
                    Text("·")
                        .foregroundColor(.white.opacity(0.35))
                    Text(item.relativeTime)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .font(.system(size: 10 * scale, weight: .medium))
            }

            Spacer(minLength: 4)

            pinButton
        }
    }

    private var pinButton: some View {
        let visible = item.isPinned || isHovering || isSelected
        return Button(action: onTogglePin) {
            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundColor(item.isPinned ? .yellow.opacity(0.9) : .white.opacity(0.7))
                .rotationEffect(.degrees(item.isPinned ? 0 : 45))
                .frame(width: 24 * scale, height: 24 * scale)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .help(item.isPinned ? "Unpin" : "Pin")
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            ClipboardImageView(item: item, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        case .richText:
            Text(item.cardPreviewText)
                .font(.system(size: displaySize.baseFontSize))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(1.5)
        case .text, .other:
            if SyntaxHighlighter.isLikelyCode(item.cardPreviewText) {
                Text(item.cardPreviewText)
                    .font(.system(size: displaySize.baseFontSize - 1.5, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.88))
                    .padding(8 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(item.cardPreviewText)
                    .font(.system(size: displaySize.baseFontSize + 1))
                    .foregroundColor(.white.opacity(0.95))
                    .lineSpacing(2)
            }
        case .link:
            LinkPreviewCard(urlString: item.urlString ?? item.previewText)
        case .file:
            fileList
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if item.fileURLs.isEmpty {
            Text(item.cardPreviewText)
                .font(.system(size: displaySize.baseFontSize))
                .foregroundColor(.white.opacity(0.92))
        } else {
            VStack(alignment: .leading, spacing: 6 * scale) {
                ForEach(item.fileURLs.prefix(3), id: \.self) { url in
                    HStack(spacing: 6 * scale) {
                        Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.fill")
                            .font(.system(size: 12 * scale))
                            .foregroundColor(typeColor)
                        Text(url.lastPathComponent)
                            .font(.system(size: displaySize.baseFontSize, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if item.fileURLs.count > 3 {
                    Text("+\(item.fileURLs.count - 3) more")
                        .font(.system(size: 10 * scale, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6 * scale) {
            if !collectionColors.isEmpty {
                HStack(spacing: -3 * scale) {
                    ForEach(Array(collectionColors.prefix(3).enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 9 * scale, height: 9 * scale)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                    }
                }
                .help("In \(collectionColors.count) collection\(collectionColors.count == 1 ? "" : "s")")
            }

            ForEach(tags.prefix(2)) { tag in
                HStack(spacing: 3 * scale) {
                    Circle()
                        .fill(Color(hex: tag.color))
                        .frame(width: 6 * scale, height: 6 * scale)
                    Text(tag.name)
                        .lineLimit(1)
                }
                .font(.system(size: 9 * scale, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 2 * scale)
                .background(Capsule().fill(Color(hex: tag.color).opacity(0.18)))
            }

            if tags.count > 2 {
                Text("+\(tags.count - 2)")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(isHovering ? 0.26 : 0.32))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [typeColor.opacity(0.2), typeColor.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var borderColor: Color {
        if isSelected { return Color.white.opacity(0.9) }
        if isHovering { return Color.white.opacity(0.22) }
        return Color.white.opacity(0.08)
    }
}

/// Source app icon with graceful fallbacks (Universal Clipboard / unknown app).
private struct SourceAppIconView: View {
    let item: ClipboardItem
    let size: CGFloat
    // Observed so the card refreshes when the icon finishes loading in the background.
    @ObservedObject private var iconCache = AppIconCache.shared

    var body: some View {
        if let bundleID = item.sourceAppBundleId, let icon = iconCache.icon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: item.sourceAppBundleId == nil ? "iphone" : "app.dashed")
                        .font(.system(size: size * 0.52, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                )
        }
    }
}

private extension ClipboardItemType {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .link: return "link"
        case .file: return "doc"
        case .other: return "square.dashed"
        }
    }

    /// Slightly lifted hues so they read well on the dark glass panel.
    var tint: Color {
        switch self {
        case .text: return Color(red: 0.45, green: 0.66, blue: 1.0)
        case .richText: return Color(red: 0.38, green: 0.84, blue: 0.92)
        case .image: return Color(red: 0.42, green: 0.86, blue: 0.55)
        case .link: return Color(red: 0.74, green: 0.56, blue: 1.0)
        case .file: return Color(red: 1.0, green: 0.68, blue: 0.35)
        case .other: return Color(white: 0.7)
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
                    ClipboardImageView(item: item, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .cornerRadius(8)
                case .richText:
                    ScrollView {
                        Text(item.detailPreviewText)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .text, .other:
                    ScrollView {
                        if SyntaxHighlighter.isLikelyCode(item.detailPreviewText) {
                            Text(item.detailPreviewText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(item.detailPreviewText)
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
                        Text(preview?.title ?? item.cardPreviewText)
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

private struct ClipboardImageView: View {
    let item: ClipboardItem
    let contentMode: ContentMode

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.white.opacity(0.04)
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear(perform: loadImage)
        .onChange(of: item.fingerprint) {
            image = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard image == nil, let data = item.imageData else { return }
        let fingerprint = item.fingerprint
        ClipboardImageCache.shared.loadImage(for: fingerprint, data: data) { loaded in
            guard item.fingerprint == fingerprint else { return }
            image = loaded
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

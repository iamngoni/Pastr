import SwiftUI

struct PastrMobileRootView: View {
    @State private var selectedTab: MobileTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PastrLibraryView()
            }
            .tabItem { Label("Library", systemImage: "square.stack.3d.up") }
            .tag(MobileTab.library)

            NavigationStack {
                PastrCollectionsView()
            }
            .tabItem { Label("Collections", systemImage: "folder") }
            .tag(MobileTab.collections)

            NavigationStack {
                PastrKeyboardSetupView()
            }
            .tabItem { Label("Keyboard", systemImage: "keyboard") }
            .tag(MobileTab.keyboard)

            NavigationStack {
                PastrMobileSettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(MobileTab.settings)
        }
        .tint(PastrTheme.accent)
    }
}

private enum MobileTab {
    case library
    case collections
    case keyboard
    case settings
}

struct PastrLibraryView: View {
    @EnvironmentObject private var clipStore: MobileClipStore
    @State private var query = ""
    @State private var selectedFilter: PastrClipType?

    private var filteredClips: [PastrClip] {
        clipStore.clips.filter { clip in
            let matchesFilter = selectedFilter.map { $0 == clip.type } ?? true
            let matchesQuery = query.isEmpty
                || clip.title.localizedCaseInsensitiveContains(query)
                || clip.detail.localizedCaseInsensitiveContains(query)
                || clip.source.localizedCaseInsensitiveContains(query)
            return matchesFilter && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                libraryHeader
                searchField
                filterStrip

                if clipStore.clips.isEmpty {
                    EmptyLibraryState()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pinned")
                            .font(.headline)
                        VStack(spacing: 0) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(clipStore.clips.filter(\.isPinned)) { clip in
                                        ShelfClipCard(clip: clip)
                                            .frame(width: 164, height: 138)
                                    }
                                }
                                .padding(12)
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent")
                            .font(.headline)
                        if filteredClips.isEmpty {
                            EmptySearchState()
                        } else {
                            ForEach(filteredClips) { clip in
                                ClipListRow(clip: clip)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            clipStore.delete(clip)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 84)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await clipStore.refreshNow()
        }
        .alert("Pastr", isPresented: Binding(
            get: { clipStore.userMessage != nil },
            set: { if !$0 { clipStore.userMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                clipStore.userMessage = nil
            }
        } message: {
            Text(clipStore.userMessage ?? "")
        }
    }

    private var libraryHeader: some View {
        HStack {
            Text("Pastr")
                .font(.system(size: 34, weight: .bold))
            Spacer()
            HStack(spacing: 4) {
                Button {
                    clipStore.captureCurrentPasteboard()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 38)
                }
                Button {
                    clipStore.refresh()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 38)
                }
            }
            .background(.regularMaterial, in: Capsule())
            .buttonStyle(.plain)
            .foregroundStyle(PastrTheme.accent)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "History", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }
                ForEach(PastrClipType.allCases) { type in
                    FilterChip(title: type.label, isSelected: selectedFilter == type) {
                        selectedFilter = type
                    }
                }
            }
        }
    }
}

private struct EmptyLibraryState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(PastrTheme.accent)
                .frame(width: 64, height: 64)
                .background(PastrTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("No clips")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct EmptySearchState: View {
    var body: some View {
        Text("No matching clips")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PastrCollectionsView: View {
    @EnvironmentObject private var clipStore: MobileClipStore

    var body: some View {
        List {
            CollectionRow(
                name: "Pinned",
                count: clipStore.clips.filter(\.isPinned).count,
                symbol: "pin.fill",
                tint: .blue
            )
            ForEach(PastrClipType.allCases) { type in
                CollectionRow(
                    name: type.label,
                    count: clipStore.clips.filter { $0.type == type }.count,
                    symbol: type.symbolName,
                    tint: PastrTheme.tint(PastrTintName.preferred(for: type))
                )
            }
        }
        .navigationTitle("Collections")
    }
}

struct PastrKeyboardSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PastrTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(PastrTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pastr Keyboard")
                            .font(.title2.bold())
                        Text("Pinned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                SetupChecklistRow(symbol: "keyboard", title: "Add Keyboard", detail: "Settings -> General -> Keyboard", status: .todo)
                SetupChecklistRow(symbol: "folder", title: "Collection", detail: "Pinned", status: .todo)
                SetupChecklistRow(symbol: "lock.open", title: "Full Access", detail: "Required", status: .todo)
                SetupChecklistRow(symbol: "shield", title: "Secure Fields", detail: "System keyboard", status: .done)

                VStack(spacing: 12) {
                    Button {
                        openKeyboardSettings()
                    } label: {
                        Label("Open Keyboard Settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                    } label: {
                        Label("Preview Pastr Keyboard", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .padding(.bottom, 84)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Keyboard")
    }

    private func openKeyboardSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct PastrMobileSettingsView: View {
    @EnvironmentObject private var clipStore: MobileClipStore

    var body: some View {
        Form {
            Section("Sync") {
                LabeledContent("iCloud") {
                    Text(syncLabel)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Keyboard cache") {
                    Text("\(clipStore.clips.count) clips")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var syncLabel: String {
        switch clipStore.syncState {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing"
        case .success:
            return "Updated"
        case .failed:
            return "Failed"
        }
    }
}

private struct ShelfClipCard: View {
    let clip: PastrClip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(clip.type.label)
                    .font(.caption.weight(.semibold))
                Text(clip.relativeTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: clip.isPinned ? "pin.fill" : "pin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ClipThumbnail(clip: clip)
                .frame(height: 52)

            Text(clip.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(clip.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PastrTheme.tint(clip.tintName).opacity(0.26), lineWidth: 1)
        )
    }
}

private struct ClipListRow: View {
    let clip: PastrClip

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: clip.type.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PastrTheme.tint(clip.tintName))
                .frame(width: 42, height: 42)
                .background(PastrTheme.tint(clip.tintName).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(clip.source)
                        .font(.subheadline.weight(.semibold))
                    Text(clip.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(clip.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(clip.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: clip.isPinned ? "pin.fill" : "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? PastrTheme.accent.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isSelected ? PastrTheme.accent : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct CollectionRow: View {
    let name: String
    let count: Int
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            HStack {
                Text(name)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}

private enum SetupStatus {
    case todo
    case done
}

private struct SetupChecklistRow: View {
    let symbol: String
    let title: String
    let detail: String
    let status: SetupStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status == .done ? "checkmark.circle.fill" : symbol)
                .font(.title3)
                .frame(width: 34, height: 34)
                .foregroundStyle(status == .done ? .green : PastrTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    PastrMobileRootView()
        .environmentObject(MobileClipStore(cloudStore: PastrCloudClipStore(inMemory: true)))
}

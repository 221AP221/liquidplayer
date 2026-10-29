import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Növbə

struct QueueSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section {
                        MediaRow(item: current) {}
                            .listRowBackground(Color.clear)
                            .allowsHitTesting(false)
                    } header: {
                        SectionHeader(title: "queue.nowPlaying")
                    }
                }

                Section {
                    ForEach(player.upcoming) { item in
                        MediaRow(item: item) { player.play(item) }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.Colors.separator)
                    }
                    .onMove { player.moveUpcoming(fromOffsets: $0, toOffset: $1) }
                    .onDelete { player.removeUpcoming(atOffsets: $0) }
                } header: {
                    SectionHeader(title: "queue.playingNext")
                } footer: {
                    if player.upcoming.isEmpty {
                        Text("queue.empty")
                            .font(Theme.Text.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.base)
            .navigationTitle("queue.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EditButton()
                        .disabled(player.upcoming.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - Sözlər

struct LyricsSheet: View {
    @Environment(PlayerController.self) private var player
    @State private var lyrics: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if isLoading {
                        ProgressView()
                            .tint(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                    } else if let lyrics {
                        Text(lyrics)
                            .font(.system(size: 20, weight: .semibold))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                    } else {
                        Text("lyrics.empty")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.base)
            .navigationTitle("lyrics.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        // Fayl dəyişəndə sözlər yenidən oxunur.
        .task(id: player.current?.id) {
            isLoading = true
            lyrics = await player.loadLyrics()
            isLoading = false
        }
    }
}

// MARK: - Qovluqlar

struct FoldersScreen: View {
    @Environment(\.libraryImportAction) private var importFolder
    @Environment(\.libraryRefreshAction) private var refreshLibrary
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Query(sort: \LibraryFolder.addedAt, order: .reverse) private var folders: [LibraryFolder]
    @State private var folderPendingRemoval: LibraryFolder?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(folders) { folder in
                        NavigationLink(value: folder) {
                            FolderRow(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("folders.remove", systemImage: "trash", role: .destructive) {
                                folderPendingRemoval = folder
                            }
                        }
                    }

                    Button { importFolder() } label: {
                        Label("empty.addFolder", systemImage: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                                    .foregroundStyle(Color.white.opacity(0.18))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.screenEdge)
                .padding(.bottom, 170)
            }
            .refreshable { await refreshLibrary() }
            .background(LibraryBackdrop())
            .safeAreaInset(edge: .top) {
                HStack { Text("tab.folders").font(Theme.Text.largeTitle); Spacer() }
                    .padding(.horizontal, Theme.Spacing.screenEdge)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryFolder.self) { folder in
                FolderDetailScreen(folder: folder)
            }
            .confirmationDialog(
                "folders.remove.title",
                isPresented: Binding(
                    get: { folderPendingRemoval != nil },
                    set: { if !$0 { folderPendingRemoval = nil } }
                ),
                titleVisibility: .visible,
                presenting: folderPendingRemoval
            ) { folder in
                Button("folders.remove", role: .destructive) { remove(folder) }
                Button("action.cancel", role: .cancel) {}
            } message: { _ in
                Text("folders.remove.body")
            }
        }
    }

    /// Diskdəki fayllara toxunulmur — yalnız kitabxana qeydləri, oxunmuş yerlər
    /// və əlfəcinlər silinir.
    private func remove(_ folder: LibraryFolder) {
        player.forget(folder.items)
        context.delete(folder)
        try? context.save()
        folderPendingRemoval = nil
    }
}

private struct FolderRow: View {
    let folder: LibraryFolder

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: folder.hasAccess ? "folder.fill" : "folder.badge.questionmark")
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.16))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(folder.hasAccess
                     ? String(format: String(localized: "folders.count"), folder.items.filter { !$0.isMissing }.count)
                     : String(localized: "folders.noAccess"))
                    .font(Theme.Text.caption)
                    .foregroundStyle(folder.hasAccess ? Theme.Colors.textSecondary : Theme.Colors.rose)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(height: 60)
        .contentShape(Rectangle())
    }

    private var tint: Color { folder.hasAccess ? Theme.Colors.teal : Theme.Colors.rose }
}

/// Qovluğun içindəkilər, qovluq daxilindəki yola görə sıralanıb.
struct FolderDetailScreen: View {
    @Environment(PlayerController.self) private var player
    let folder: LibraryFolder

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    Text(folder.hasAccess ? LocalizedStringKey("folders.emptyFolder") : LocalizedStringKey("folders.noAccess"))
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, Theme.Spacing.xl)
                }
                ForEach(items) { item in
                    MediaRow(item: item) { player.play(item, queue: items) }
                        .mediaContextMenu(item)
                    RowSeparator()
                }
            }
            .padding(.horizontal, Theme.Spacing.screenEdge)
            .padding(.bottom, 170)
        }
        .background(LibraryBackdrop())
        .navigationTitle(folder.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("folders.playAll", systemImage: "play.fill") {
                        if let first = items.first { player.play(first, queue: items) }
                    }
                }
            }
        }
    }

    private var items: [MediaItem] {
        folder.items
            .filter { !$0.isMissing }
            .sorted { $0.libraryKey.localizedStandardCompare($1.libraryKey) == .orderedAscending }
    }
}

// MARK: - Axtarış

struct SearchScreen: View {
    @Environment(PlayerController.self) private var player
    @State private var query = ""
    @Query private var allItems: [MediaItem]

    var body: some View {
        // `.searchable` axtarış sahəsini naviqasiya zolağına qoyur — onsuz iPhone-da görünmür.
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { item in
                        MediaRow(item: item) { player.play(item, queue: results) }
                            .mediaContextMenu(item)
                        RowSeparator()
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenEdge)
                .padding(.bottom, 170)
            }
            .background(LibraryBackdrop())
            .navigationTitle("tab.search")
            .searchable(text: $query, prompt: Text("search.prompt"))
            .overlay {
                if !query.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    /// 10 000 faylda da bu filtr millisaniyələr çəkir; FTS yalnız ondan çox lazım olacaq.
    private var results: [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return allItems.filter { item in
            !item.isMissing && (
                item.title.localizedStandardContains(trimmed)
                    || item.filename.localizedStandardContains(trimmed)
                    || (item.artist ?? "").localizedStandardContains(trimmed)
                    || (item.album ?? "").localizedStandardContains(trimmed)
            )
        }
    }
}

// MARK: - Tənzimləmələr

struct SettingsScreen: View {
    @Environment(PlayerController.self) private var player
    @State private var isEqualizerPresented = false

    var body: some View {
        @Bindable var player = player

        NavigationStack {
            List {
                Section("settings.playback") {
                    LabeledContent("settings.engine") {
                        Text(EngineRouter.isVLCAvailable ? "VLCKit + AVFoundation" : "AVFoundation")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Toggle("settings.suppressNotice", isOn: $player.suppressDecodingNotice)
                    Picker("settings.rate", selection: $player.rate) {
                        ForEach(PlayerController.availableRates, id: \.self) { rate in
                            Text(rate.rateLabel).tag(rate)
                        }
                    }
                    Button {
                        isEqualizerPresented = true
                    } label: {
                        LabeledContent("eq.title") {
                            Text(equalizerSummary)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                }

                Section("settings.about") {
                    Text("settings.privacyNote")
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("tab.more")
            .safeAreaPadding(.bottom, 150)
            .sheet(isPresented: $isEqualizerPresented) { EqualizerSheet() }
        }
    }

    private var equalizerSummary: String {
        guard player.equalizer.isEnabled else { return String(localized: "eq.off") }
        guard let preset = player.equalizer.preset else { return String(localized: "eq.custom") }
        return String(localized: String.LocalizationValue(preset.titleKey))
    }
}

extension Float {
    /// 1 → "1x", 1.25 → "1.25x".
    var rateLabel: String { String(format: "%gx", self) }
}

// MARK: - Xəbərdarlıq vərəqəsi

struct PlaybackNoticeSheet: View {
    @Environment(PlayerController.self) private var player
    let notice: PlaybackNotice

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint.opacity(0.16)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .bold))
                    Text(message).font(Theme.Text.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Button { player.dismissNotice() } label: {
                Text("action.gotIt")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.lg)
        .glassCard(elevated: true)
        .padding(Theme.Spacing.md)
        .padding(.bottom, 160)
    }

    private var symbol: String {
        switch notice {
        case .softwareDecoding:  "bolt.fill"
        case .fileMissing:       "folder.badge.questionmark"
        case .unsupportedFormat: "xmark.octagon"
        case .corruptedAt:       "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch notice {
        case .softwareDecoding: Theme.Colors.accent
        default: Theme.Colors.rose
        }
    }

    private var title: LocalizedStringKey {
        switch notice {
        case .softwareDecoding:  "notice.software.title"
        case .fileMissing:       "notice.missing.title"
        case .unsupportedFormat: "notice.unsupported.title"
        case .corruptedAt:       "notice.corrupt.title"
        }
    }

    private var message: LocalizedStringKey {
        switch notice {
        case .softwareDecoding:  "notice.software.body"
        case .fileMissing:       "notice.missing.body"
        case .unsupportedFormat: "notice.unsupported.body"
        case .corruptedAt:       "notice.corrupt.body"
        }
    }
}

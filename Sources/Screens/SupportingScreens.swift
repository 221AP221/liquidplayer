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
                Section {
                    ForEach(upcoming) { item in
                        MediaRow(item: item) { player.play(item) }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.Colors.separator)
                    }
                } header: {
                    SectionHeader(title: "queue.playingNext")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.base)
            .navigationTitle("queue.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private var upcoming: [MediaItem] {
        guard let current = player.current,
              let index = player.queue.firstIndex(where: { $0.id == current.id })
        else { return player.queue }
        return Array(player.queue.dropFirst(index + 1))
    }
}

// MARK: - Sözlər

struct LyricsSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    Text("lyrics.empty")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Colors.textSecondary)
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
    }
}

// MARK: - Qovluqlar

struct FoldersScreen: View {
    @Environment(\.libraryImportAction) private var importFolder
    @Query(sort: \LibraryFolder.addedAt, order: .reverse) private var folders: [LibraryFolder]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(folders) { folder in
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: folder.hasAccess ? "folder.fill" : "folder.badge.questionmark")
                            .font(.system(size: 17))
                            .foregroundStyle(folder.hasAccess ? Theme.Colors.teal : Theme.Colors.rose)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill((folder.hasAccess ? Theme.Colors.teal : Theme.Colors.rose).opacity(0.16))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayName)
                                .font(.system(size: 16, weight: .medium))
                            Text(folder.hasAccess
                                 ? String(format: String(localized: "folders.count"), folder.items.count)
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
        .background(LibraryBackdrop())
        .safeAreaInset(edge: .top) {
            HStack { Text("tab.folders").font(Theme.Text.largeTitle); Spacer() }
                .padding(.horizontal, Theme.Spacing.screenEdge)
                .padding(.bottom, Theme.Spacing.sm)
        }
    }
}

// MARK: - Axtarış

struct SearchScreen: View {
    @Environment(PlayerController.self) private var player
    @State private var query = ""
    @Query private var allItems: [MediaItem]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results) { item in
                    MediaRow(item: item) { player.play(item, queue: results) }
                    RowSeparator()
                }
            }
            .padding(.horizontal, Theme.Spacing.screenEdge)
            .padding(.bottom, 170)
        }
        .background(LibraryBackdrop())
        .searchable(text: $query, prompt: Text("search.prompt"))
    }

    private var results: [MediaItem] {
        guard !query.isEmpty else { return [] }
        return allItems.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.filename.localizedCaseInsensitiveContains(query)
                || ($0.artist ?? "").localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Tənzimləmələr

struct SettingsScreen: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        NavigationStack {
            List {
                Section("settings.playback") {
                    LabeledContent("settings.engine") {
                        Text(EngineRouter.isVLCAvailable ? "VLCKit + AVFoundation" : "AVFoundation")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Toggle("settings.suppressNotice", isOn: Bindable(player).suppressDecodingNotice)
                    LabeledContent("settings.rate") {
                        Text(String(format: "%.2gx", player.rate))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
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
        }
    }
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

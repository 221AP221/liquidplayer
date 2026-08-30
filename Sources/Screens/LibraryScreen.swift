import SwiftData
import SwiftUI

struct LibraryScreen: View {
    @Environment(PlayerController.self) private var player
    @Query(sort: \MediaItem.addedAt, order: .reverse) private var allItems: [MediaItem]
    @State private var filter: MediaKind?

    private let filters: [MediaKind?] = [nil, .audio, .video]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                GlassSegmentedControl(
                    items: filters,
                    label: { kind in
                        switch kind {
                        case .none:   String(localized: "filter.all")
                        case .audio?: String(localized: "filter.audio")
                        case .video?: String(localized: "filter.video")
                        default:      ""
                        }
                    },
                    selection: $filter
                )

                if visibleItems.isEmpty {
                    EmptyLibraryState()
                        .padding(.top, Theme.Spacing.xxl)
                } else {
                    if !resumable.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionHeader(title: "section.continue")
                            ForEach(resumable) { item in
                                MediaRow(item: item) { play(item) }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: "section.recent")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                                            GridItem(.flexible())],
                                  spacing: Theme.Spacing.md) {
                            ForEach(gridItems) { item in
                                MediaCard(item: item) { play(item) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenEdge)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .background(LibraryBackdrop())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("tab.library").font(Theme.Text.largeTitle)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.screenEdge)
            .padding(.bottom, Theme.Spacing.sm)
            .background(.clear)
        }
    }

    private var visibleItems: [MediaItem] {
        guard let filter else { return allItems.filter { !$0.isMissing } }
        return allItems.filter { $0.kind == filter && !$0.isMissing }
    }

    private var resumable: [MediaItem] {
        Array(visibleItems.filter(\.isResumable).prefix(4))
    }

    private var gridItems: [MediaItem] {
        Array(visibleItems.prefix(12))
    }

    private func play(_ item: MediaItem) {
        player.play(item, queue: visibleItems)
    }
}

struct LibraryBackdrop: View {
    var body: some View {
        ZStack {
            Theme.Colors.base
            Ellipse()
                .fill(Theme.Colors.accent.opacity(0.16))
                .frame(width: 520, height: 380)
                .blur(radius: 90)
                .offset(x: 140, y: -320)
            Ellipse()
                .fill(Theme.Colors.violet.opacity(0.16))
                .frame(width: 480, height: 400)
                .blur(radius: 90)
                .offset(x: -160, y: 120)
        }
        .ignoresSafeArea()
    }
}

struct MediaRow: View {
    let item: MediaItem
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ArtworkView(
                    image: item.artworkData.flatMap(UIImage.init(data:)),
                    seed: item.filename,
                    isVideo: item.isVideo
                )
                .frame(width: Theme.Size.artThumb, height: Theme.Size.artThumb)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Theme.Text.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Spacing.sm)

                if item.engine == .vlc {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.accent.opacity(0.7))
                }
            }
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if item.isResumable {
            return String(
                format: String(localized: "row.remaining"),
                item.remainingSeconds.timeLabel
            )
        }
        if let artist = item.artist, !artist.isEmpty {
            return "\(artist) · \(item.duration.timeLabel)"
        }
        return "\(item.fileExtension.uppercased()) · \(item.duration.timeLabel)"
    }
}

struct MediaCard: View {
    let item: MediaItem
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ArtworkView(
                    image: item.artworkData.flatMap(UIImage.init(data:)),
                    seed: item.filename,
                    cornerRadius: Theme.Radius.control,
                    isVideo: item.isVideo
                )
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    Text(item.fileExtension.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(item.artist ?? item.filename)
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct EmptyLibraryState: View {
    @Environment(\.libraryImportAction) private var importFolder

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 120, height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                        .foregroundStyle(Color.white.opacity(0.18))
                )

            VStack(spacing: Theme.Spacing.xs) {
                Text("empty.title")
                    .font(Theme.Text.title)
                Text("empty.body")
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                importFolder()
            } label: {
                Label("empty.addFolder", systemImage: "folder.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.Colors.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

struct NowPlayingScreen: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: NowPlayingSheet?
    @State private var scrubFraction: Double?

    enum NowPlayingSheet: String, Identifiable {
        case queue, lyrics, tracks
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            if let item = player.current {
                ArtworkGlow(colors: ArtworkPalette.glowColors(for: item.filename))

                VStack(spacing: 0) {
                    header(item)

                    if item.isVideo {
                        VideoSurface()
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .padding(.top, Theme.Spacing.lg)
                    } else {
                        ArtworkView(
                            image: item.artworkData.flatMap(UIImage.init(data:)),
                            seed: item.filename,
                            cornerRadius: 26
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .scaleEffect(player.isPlaying ? 1 : 0.9)
                        .shadow(color: .black.opacity(0.6), radius: 34, y: 18)
                        .animation(Theme.Motion.snap, value: player.isPlaying)
                        .padding(.top, Theme.Spacing.md)
                    }

                    titleBlock(item)
                    scrubber
                    transport
                    Spacer(minLength: Theme.Spacing.md)
                    bottomBar
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .queue:  QueueSheet()
            case .lyrics: LyricsSheet()
            case .tracks: TrackSelectorSheet()
            }
        }
    }

    // MARK: - Hissələr

    private func header(_ item: MediaItem) -> some View {
        HStack {
            Button { player.isExpanded = false; dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85))
                    .hitTarget()
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("nowplaying.fromAlbum")
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(item.album ?? item.folder?.displayName ?? item.fileExtension.uppercased())
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            Menu {
                Button("menu.showInFolder", systemImage: "folder") {}
                Button("menu.fileInfo", systemImage: "info.circle") {}
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85))
                    .hitTarget()
            }
        }
        .frame(height: Theme.Size.hitTarget)
    }

    private func titleBlock(_ item: MediaItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(Theme.Text.title)
                    .lineLimit(1)
                Text(item.artist ?? item.filename)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                item.isFavorite.toggle()
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.isFavorite ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    .glassCircle(diameter: Theme.Size.hitTarget)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private var scrubber: some View {
        let fraction = scrubFraction ?? player.snapshot.fraction
        return VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .frame(width: geometry.size.width * fraction)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: geometry.size.width * fraction - 7)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubFraction = min(1, max(0, value.location.x / geometry.size.width))
                        }
                        .onEnded { value in
                            let target = min(1, max(0, value.location.x / geometry.size.width))
                            player.seek(toFraction: target)
                            scrubFraction = nil
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text((player.snapshot.duration * fraction).timeLabel)
                Spacer()
                Text("-" + (player.snapshot.duration * (1 - fraction)).timeLabel)
            }
            .font(Theme.Text.numeric)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var transport: some View {
        HStack {
            Button { player.shuffle.toggle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffle ? Theme.Colors.accent : Theme.Colors.textPrimary.opacity(0.62))
                    .hitTarget(46)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 26)).hitTarget(52)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .glassCircle(diameter: Theme.Size.transportMain)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 26)).hitTarget(52)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                let all = RepeatMode.allCases
                let index = all.firstIndex(of: player.repeatMode) ?? 0
                player.repeatMode = all[(index + 1) % all.count]
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? Theme.Colors.textPrimary.opacity(0.62) : Theme.Colors.accent)
                    .hitTarget(46)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.top, Theme.Spacing.sm)
    }

    /// Video və audio üçün alt sətir fərqlidir: videoda söz yerinə treklər,
    /// AirPlay yerinə PiP daha çox işə yarayır.
    private var bottomBar: some View {
        let isVideo = player.current?.isVideo ?? false

        return HStack(spacing: 0) {
            if isVideo {
                Button { sheet = .tracks } label: {
                    Image(systemName: "captions.bubble")
                        .foregroundStyle(player.canChooseTracks
                                         ? Theme.Colors.textPrimary.opacity(0.8)
                                         : Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .hitTarget()
                }
                .buttonStyle(.plain)
                .disabled(!player.canChooseTracks)
            } else {
                Button { sheet = .lyrics } label: {
                    Image(systemName: "quote.bubble").frame(maxWidth: .infinity).hitTarget()
                }
                .buttonStyle(.plain)
            }

            if isVideo && player.supportsPictureInPicture {
                Button { player.togglePictureInPicture() } label: {
                    Image(systemName: player.isPictureInPictureActive
                          ? "pip.exit" : "pip.enter")
                        .foregroundStyle(player.isPictureInPictureActive
                                         ? Theme.Colors.accent
                                         : Theme.Colors.textPrimary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .hitTarget()
                }
                .buttonStyle(.plain)
            } else {
                Button {} label: {
                    Image(systemName: "airplayaudio").frame(maxWidth: .infinity).hitTarget()
                }
                .buttonStyle(.plain)
            }

            Button { sheet = .queue } label: {
                Image(systemName: "list.bullet").frame(maxWidth: .infinity).hitTarget()
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.8))
        .frame(height: 52)
        .glassCard(cornerRadius: 26)
    }
}

/// VLC və AVFoundation render səthini SwiftUI-ya gətirir.
struct VideoSurface: UIViewRepresentable {
    @Environment(PlayerController.self) private var player

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        if let videoView = player.makeVideoView() {
            videoView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(videoView)
            NSLayoutConstraint.activate([
                videoView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                videoView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                videoView.topAnchor.constraint(equalTo: container.topAnchor),
                videoView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

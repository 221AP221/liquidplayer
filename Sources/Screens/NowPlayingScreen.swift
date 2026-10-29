import AVKit
import SwiftUI

struct NowPlayingScreen: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: NowPlayingSheet?
    @State private var scrubFraction: Double?
    @State private var isVideoFullscreen = false

    enum NowPlayingSheet: String, Identifiable {
        case queue, lyrics, tracks, chapters, equalizer, folder, fileInfo
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            if let item = player.current {
                ArtworkGlow(colors: ArtworkPalette.glowColors(for: item.filename))

                VStack(spacing: 0) {
                    header(item)

                    if item.isVideo {
                        Group {
                            // Tam ekran açıqdırsa səth orada yaşayır: VLC-nin render
                            // görüntüsü eyni anda iki yerdə ola bilmir.
                            if isVideoFullscreen {
                                Color.black
                            } else {
                                VideoSurface()
                                    // Yeni fayl — yeni mühərrik — yeni səth.
                                    .id(player.engineGeneration)
                            }
                        }
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Button { isVideoFullscreen = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .hitTarget()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("video.fullscreen"))
                            .padding(Theme.Spacing.xs)
                        }
                        .onTapGesture(count: 2) { isVideoFullscreen = true }
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
                    if !player.chapters.isEmpty { chapterBar }
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
            case .chapters: ChaptersSheet()
            case .equalizer: EqualizerSheet()
            case .folder:
                if let folder = player.current?.folder {
                    NavigationStack { FolderDetailScreen(folder: folder) }
                        .presentationDetents([.medium, .large])
                        .presentationBackground(.ultraThinMaterial)
                }
            case .fileInfo:
                if let item = player.current { FileInfoSheet(item: item) }
            }
        }
        .fullScreenCover(isPresented: $isVideoFullscreen) {
            FullscreenVideoView()
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
                Button("bookmarks.addHere", systemImage: "bookmark") {
                    _ = player.addBookmark()
                }
                rateMenu
                sleepTimerMenu
                Button("eq.title", systemImage: "slider.vertical.3") {
                    sheet = .equalizer
                }
                Divider()
                Button("menu.showInFolder", systemImage: "folder") {
                    sheet = .folder
                }
                .disabled(item.folder == nil)
                Button("menu.fileInfo", systemImage: "info.circle") {
                    sheet = .fileInfo
                }
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
                if player.rate != 1 || player.sleepTimer != nil {
                    statusBadges
                }
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
                    chapterTicks(width: geometry.size.width)
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

    // MARK: - Sürət və yuxu taymeri

    private var rateMenu: some View {
        Menu {
            Picker("settings.rate", selection: Bindable(player).rate) {
                ForEach(PlayerController.availableRates, id: \.self) { rate in
                    Text(rate.rateLabel).tag(rate)
                }
            }
        } label: {
            Label {
                Text("settings.rate") + Text(verbatim: " · \(player.rate.rateLabel)")
            } icon: {
                Image(systemName: "gauge.with.dots.needle.67percent")
            }
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            ForEach(SleepTimerOption.all) { option in
                Button(sleepTimerTitle(option)) { player.setSleepTimer(option) }
                    .disabled(option == .endOfChapter && player.chapters.isEmpty)
            }
            if player.sleepTimer != nil {
                Divider()
                Button("sleep.off", role: .destructive) { player.setSleepTimer(nil) }
            }
        } label: {
            Label("sleep.title", systemImage: player.sleepTimer == nil ? "moon" : "moon.fill")
        }
    }

    private func sleepTimerTitle(_ option: SleepTimerOption) -> String {
        switch option {
        case .minutes(let minutes):
            String(format: String(localized: "sleep.minutes"), minutes)
        case .endOfChapter:
            String(localized: "sleep.endOfChapter")
        case .endOfItem:
            String(localized: "sleep.endOfItem")
        }
    }

    /// Başlığın altında: sürət 1x deyilsə və yuxu taymeri işləyirsə.
    private var statusBadges: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if player.rate != 1 {
                StatusBadge(systemImage: "gauge.with.dots.needle.67percent", text: player.rate.rateLabel)
            }
            if let timer = player.sleepTimer {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    StatusBadge(systemImage: "moon.fill", text: sleepTimerLabel(timer, now: context.date))
                }
            }
        }
        .padding(.top, 4)
    }

    private func sleepTimerLabel(_ timer: SleepTimer, now: Date) -> String {
        switch timer {
        case .at(let date):
            max(0, date.timeIntervalSince(now)).timeLabel
        case .endOfChapter:
            String(localized: "sleep.endOfChapter")
        case .endOfItem:
            String(localized: "sleep.endOfItem")
        }
    }

    /// Fəsilli fayllarda: hazırkı fəslin adı və fəsillər arası keçid.
    private var chapterBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button { player.previousChapter() } label: {
                Image(systemName: "backward.end.fill").hitTarget(38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("chapters.previous"))

            Button { sheet = .chapters } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 12, weight: .semibold))
                    Text(currentChapterTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { player.nextChapter() } label: {
                Image(systemName: "forward.end.fill").hitTarget(38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("chapters.next"))
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.8))
        .padding(.horizontal, Theme.Spacing.xs)
        .glassCard(cornerRadius: 19)
        .padding(.top, Theme.Spacing.md)
    }

    private var currentChapterTitle: String {
        guard let chapter = player.currentChapter else { return String(localized: "chapters.title") }
        let number = chapter.id + 1
        let title = chapter.title.isEmpty
            ? String(format: String(localized: "chapters.numbered"), number)
            : chapter.title
        return "\(number)/\(player.chapters.count) · \(title)"
    }

    /// Scrubber üzərində fəsil sərhədləri.
    @ViewBuilder
    private func chapterTicks(width: CGFloat) -> some View {
        let duration = player.snapshot.duration
        if duration > 0 {
            ForEach(player.chapters.dropFirst()) { chapter in
                Rectangle()
                    .fill(Theme.Colors.base.opacity(0.8))
                    .frame(width: 2, height: 6)
                    .offset(x: width * min(1, chapter.start / duration) - 1)
            }
        }
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
                // Sistem marşrut seçicisi: AirPlay, Bluetooth, dinamik.
                RoutePickerButton(prioritizesVideoDevices: isVideo)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Size.hitTarget)
                    .accessibilityLabel(Text("airplay.title"))
            }

            Button { sheet = .chapters } label: {
                Image(systemName: player.chapters.isEmpty ? "bookmark" : "list.bullet.indent")
                    .frame(maxWidth: .infinity)
                    .hitTarget()
            }
            .buttonStyle(.plain)

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

private struct StatusBadge: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.Colors.accent.opacity(0.14), in: Capsule())
    }
}

/// `AVRoutePickerView` — AirPlay və Bluetooth seçimi üçün sistemin öz düyməsi.
struct RoutePickerButton: UIViewRepresentable {
    var prioritizesVideoDevices = false

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        view.tintColor = UIColor(Theme.Colors.textPrimary.opacity(0.8))
        view.activeTintColor = UIColor(Theme.Colors.accent)
        view.prioritizesVideoDevices = prioritizesVideoDevices
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.prioritizesVideoDevices = prioritizesVideoDevices
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

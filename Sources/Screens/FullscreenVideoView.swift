import SwiftUI

/// Video tam ekranda. Toxunuş idarəetməni göstərir/gizlədir, sol və ya sağ
/// yarıya iki dəfə toxunmaq 10 saniyə geri/irəli çəkir — video applarındakı kimi.
struct FullscreenVideoView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubFraction: Double?
    @State private var skipFlash: SkipDirection?

    private enum SkipDirection: Equatable {
        case backward, forward
    }

    private static let skipSeconds: Double = 10

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface()
                .id(player.engineGeneration)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                gestureZone(.backward)
                gestureZone(.forward)
            }
            .ignoresSafeArea()

            if let skipFlash {
                skipIndicator(skipFlash)
                    .transition(.opacity)
            }

            if controlsVisible {
                controls
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.ease, value: controlsVisible)
        .animation(Theme.Motion.ease, value: skipFlash)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .preferredColorScheme(.dark)
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
        // Növbədə audio fayl gəlsə tam ekranın mənası qalmır.
        .onChange(of: player.current?.isVideo ?? false) { _, isVideo in
            if !isVideo { dismiss() }
        }
    }

    // MARK: - Jestlər

    private func gestureZone(_ direction: SkipDirection) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                player.skip(bySeconds: direction == .forward ? Self.skipSeconds : -Self.skipSeconds)
                flash(direction)
            }
            .onTapGesture {
                controlsVisible.toggle()
                if controlsVisible { scheduleHide() }
            }
    }

    private func flash(_ direction: SkipDirection) {
        skipFlash = direction
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if skipFlash == direction { skipFlash = nil }
        }
    }

    private func skipIndicator(_ direction: SkipDirection) -> some View {
        HStack {
            if direction == .forward { Spacer() }
            Label(
                direction == .forward ? "+10" : "-10",
                systemImage: direction == .forward ? "goforward.10" : "gobackward.10"
            )
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.ultraThinMaterial, in: Capsule())
            if direction == .backward { Spacer() }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .allowsHitTesting(false)
    }

    /// Avtomatik gizlənmə: 3 saniyə toxunulmasa idarəetmə yox olur, video pauzadadırsa qalır.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, player.isPlaying else { return }
            controlsVisible = false
        }
    }

    // MARK: - İdarəetmə

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 16, weight: .semibold))
                        .glassCircle(diameter: Theme.Size.hitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("video.exitFullscreen"))

                Text(player.current?.title ?? "")
                    .font(Theme.Text.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if player.supportsPictureInPicture {
                    Button { player.togglePictureInPicture() } label: {
                        Image(systemName: player.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 16, weight: .semibold))
                            .glassCircle(diameter: Theme.Size.hitTarget)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: Theme.Spacing.xxl) {
                Button { player.skip(bySeconds: -Self.skipSeconds); scheduleHide() } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 26)).hitTarget(56)
                }
                Button { player.togglePlayPause(); scheduleHide() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .glassCircle(diameter: Theme.Size.transportMain)
                }
                Button { player.skip(bySeconds: Self.skipSeconds); scheduleHide() } label: {
                    Image(systemName: "goforward.10").font(.system(size: 26)).hitTarget(56)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: Theme.Spacing.xs) {
                Slider(
                    value: Binding(
                        get: { scrubFraction ?? player.snapshot.fraction },
                        set: { scrubFraction = $0 }
                    ),
                    onEditingChanged: { isEditing in
                        if isEditing {
                            hideTask?.cancel()
                        } else {
                            if let scrubFraction { player.seek(toFraction: scrubFraction) }
                            scrubFraction = nil
                            scheduleHide()
                        }
                    }
                )
                .tint(Theme.Colors.accent)

                HStack {
                    let fraction = scrubFraction ?? player.snapshot.fraction
                    Text((player.snapshot.duration * fraction).timeLabel)
                    Spacer()
                    Text("-" + (player.snapshot.duration * (1 - fraction)).timeLabel)
                }
                .font(Theme.Text.numeric)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

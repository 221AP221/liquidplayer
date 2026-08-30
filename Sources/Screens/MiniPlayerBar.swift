import SwiftUI

struct MiniPlayerBar: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let item = player.current {
            HStack(spacing: Theme.Spacing.sm) {
                ArtworkView(
                    image: item.artworkData.flatMap(UIImage.init(data:)),
                    seed: item.filename,
                    isVideo: item.isVideo
                )
                .frame(
                    width: item.isVideo ? 62 : Theme.Size.artThumb,
                    height: item.isVideo ? 40 : Theme.Size.artThumb
                )
                .scaleEffect(player.isPlaying ? 1 : 0.94)
                .animation(Theme.Motion.snap, value: player.isPlaying)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(item.artist ?? item.fileExtension.uppercased())
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .hitTarget()
                }
                .buttonStyle(.plain)

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .hitTarget()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(height: Theme.Size.miniPlayer)
            .glassCard(cornerRadius: 20, elevated: true)
            .overlay(alignment: .bottom) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .frame(width: geometry.size.width * player.snapshot.fraction, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture { player.isExpanded = true }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.height < -30 { player.isExpanded = true }
                    }
            )
        }
    }
}

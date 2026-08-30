import SwiftUI
import UniformTypeIdentifiers

/// Altyazı, səs treki və sinxron. Video oxunanda Now Playing-dən açılır.
struct TrackSelectorSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var isSubtitleImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                subtitleSection
                if player.supportsSubtitleDelay { delaySection }
                audioSection
                if !player.supportsPictureInPicture { limitationsSection }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.base)
            .navigationTitle("tracks.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isSubtitleImporterPresented,
                allowedContentTypes: Self.subtitleTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    player.loadExternalSubtitle(url: url)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Bölmələr

    private var subtitleSection: some View {
        Section {
            if player.subtitleTracks.isEmpty {
                Text("tracks.noSubtitles")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(player.subtitleTracks) { track in
                    TrackRow(
                        name: track.name,
                        languageCode: track.languageCode,
                        isSelected: player.currentSubtitleTrackID == track.id
                    ) {
                        player.selectSubtitle(id: track.id)
                    }
                }
                TrackRow(
                    name: String(localized: "tracks.subtitlesOff"),
                    languageCode: nil,
                    isSelected: player.currentSubtitleTrackID == nil
                ) {
                    player.selectSubtitle(id: nil)
                }
            }

            if player.supportsExternalSubtitles {
                Button {
                    isSubtitleImporterPresented = true
                } label: {
                    Label("tracks.loadFile", systemImage: "plus")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        } header: {
            Text("tracks.subtitles")
        }
    }

    private var delaySection: some View {
        Section {
            HStack {
                Button {
                    player.setSubtitleDelay(player.subtitleDelay - 0.1)
                } label: {
                    Image(systemName: "minus").hitTarget(38)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(delayLabel)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())

                Spacer()

                Button {
                    player.setSubtitleDelay(player.subtitleDelay + 0.1)
                } label: {
                    Image(systemName: "plus").hitTarget(38)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("tracks.sync")
        } footer: {
            Text("tracks.syncHint")
        }
    }

    private var audioSection: some View {
        Section {
            if player.audioTracks.isEmpty {
                Text("tracks.noAudio")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(player.audioTracks) { track in
                    TrackRow(
                        name: track.name,
                        languageCode: track.languageCode,
                        isSelected: player.currentAudioTrackID == track.id
                    ) {
                        player.selectAudioTrack(id: track.id)
                    }
                }
            }
        } header: {
            Text("tracks.audio")
        }
    }

    /// VLC mühərriki işləyəndə nəyin itdiyini gizlətmirik.
    private var limitationsSection: some View {
        Section {
            Label("tracks.noPiP", systemImage: "pip.exit")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Label("tracks.mirrorOnly", systemImage: "airplayvideo")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        } header: {
            Text("tracks.limitations")
        }
    }

    private var delayLabel: String {
        let value = player.subtitleDelay
        let sign = value >= 0 ? "+" : ""
        return String(format: "%@%.1f s", sign, value)
    }

    private static var subtitleTypes: [UTType] {
        ["srt", "ass", "ssa", "vtt", "sub"]
            .compactMap { UTType(filenameExtension: $0) }
            .appending(.plainText)
    }
}

private extension Array {
    func appending(_ element: Element) -> [Element] {
        var copy = self
        copy.append(element)
        return copy
    }
}

private struct TrackRow: View {
    let name: String
    let languageCode: String?
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(name)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if let languageCode, !languageCode.isEmpty {
                    Text(languageCode.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

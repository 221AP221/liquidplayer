#if canImport(MobileVLCKit)
import Foundation
import MobileVLCKit
import UIKit

/// VLCKit mühərriki — MKV, FLAC, ekzotik kodeklər.
///
/// Ödənişi budur: proqram dekodlaşdırma, yəni PiP yoxdur, AirPlay yalnız ekran
/// güzgüsü kimi işləyir və batareya təxminən iki dəfə sürətli boşalır.
/// `PlayerController` bunu görüb istifadəçiyə bir dəfə xəbərdarlıq göstərir.
@MainActor
final class VLCPlaybackEngine: NSObject, PlaybackEngine {

    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((PlaybackError) -> Void)?
    var onTracksChanged: (() -> Void)?

    let supportsPictureInPicture = false
    let supportsAirPlayVideo = false
    let supportsExternalSubtitles = true
    let supportsSubtitleDelay = true

    private let player = VLCMediaPlayer()
    private lazy var renderView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }()

    private var pendingStartSeconds: Double = 0

    override init() {
        super.init()
        player.delegate = self
        player.drawable = renderView
    }

    func load(url: URL, startAtSeconds: Double) throws {
        let media = VLCMedia(url: url)
        player.media = media
        pendingStartSeconds = startAtSeconds
    }

    func play() {
        player.play()
        if pendingStartSeconds > 1 {
            // VLC media açılana qədər seek qəbul etmir.
            let target = pendingStartSeconds
            pendingStartSeconds = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self.seek(toSeconds: target)
            }
        }
    }

    func pause() { player.pause() }

    func seek(toSeconds seconds: Double) {
        player.time = VLCTime(int: Int32(seconds * 1000))
        emitSnapshot()
    }

    func setRate(_ rate: Float) { player.rate = rate }

    func teardown() {
        player.stop()
        player.drawable = nil
    }

    func makeVideoView() -> UIView? { renderView }

    // MARK: - Altyazı və səs trekləri (VLC-nin əsas üstünlüyü)

    var subtitleTracks: [MediaTrack] {
        Self.tracks(indexes: player.videoSubTitlesIndexes, names: player.videoSubTitlesNames)
    }

    var audioTracks: [MediaTrack] {
        Self.tracks(indexes: player.audioTrackIndexes, names: player.audioTrackNames)
    }

    /// VLCKit bu siyahıları `[Any]!` kimi verir — media hələ açılmayıbsa `nil` gəlir,
    /// yəni boş siyahı çökmə yox, sadəcə boş seçici deməkdir.
    private static func tracks(indexes: [Any]?, names: [Any]?) -> [MediaTrack] {
        // Parametrlər optional elan olunub — VLCKit-in `[Any]!` dəyəri
        // çağırış yerində avtomatik optional-a çevrilir və `nil` təhlükəsiz keçir.
        guard let indexes, let names else { return [] }

        return zip(indexes, names).compactMap { index, name in
            // VLC indeksləri NSNumber kimi qaytarır; birbaşa Int32-yə cast həmişə tutmur.
            guard let id = (index as? NSNumber)?.int32Value else { return nil }
            let title = (name as? String) ?? "Track \(id)"
            return MediaTrack(id: id, name: title)
        }
    }

    var currentSubtitleTrackID: Int32? {
        // VLC söndürülmüş altyazını -1 ilə göstərir.
        player.currentVideoSubTitleIndex >= 0 ? player.currentVideoSubTitleIndex : nil
    }

    var currentAudioTrackID: Int32? {
        player.currentAudioTrackIndex >= 0 ? player.currentAudioTrackIndex : nil
    }

    func selectSubtitle(id: Int32?) {
        player.currentVideoSubTitleIndex = id ?? -1
        onTracksChanged?()
    }

    func selectAudioTrack(id: Int32) {
        player.currentAudioTrackIndex = id
        onTracksChanged?()
    }

    /// Yanındakı .srt faylını yükləyir və dərhal aktiv edir.
    func loadExternalSubtitle(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        onTracksChanged?()
    }

    /// Altyazını irəli/geri sürüşdürür. VLC mikrosaniyə ilə işləyir.
    var subtitleDelay: Double {
        get { Double(player.currentVideoSubTitleDelay) / 1_000_000 }
        set { player.currentVideoSubTitleDelay = Int(newValue * 1_000_000) }
    }

    // MARK: - Detallar

    private func emitSnapshot() {
        let position = Double(player.time.intValue) / 1000
        let remaining = abs(Double(player.remainingTime?.intValue ?? 0)) / 1000
        onSnapshot?(
            PlaybackSnapshot(
                isPlaying: player.isPlaying,
                position: position,
                duration: position + remaining,
                isBuffering: player.state == .buffering,
                engine: .vlc
            )
        )
    }
}

extension VLCPlaybackEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor in self.emitSnapshot() }
    }

    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor in
            switch self.player.state {
            case .ended:
                self.onFinished?()
            case .error:
                self.onFailure?(.engineFailed("VLC playback error"))
            case .playing:
                // Treklər yalnız media açılandan sonra sadalanır.
                self.onTracksChanged?()
                self.emitSnapshot()
            default:
                self.emitSnapshot()
            }
        }
    }
}
#endif

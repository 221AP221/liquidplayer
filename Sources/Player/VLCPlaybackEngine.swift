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

    let supportsPictureInPicture = false
    let supportsAirPlayVideo = false

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

    var subtitleTracks: [(index: Int32, name: String)] {
        zip(
            player.videoSubTitlesIndexes.compactMap { $0 as? Int32 },
            player.videoSubTitlesNames.compactMap { $0 as? String }
        ).map { ($0, $1) }
    }

    func selectSubtitle(index: Int32) { player.currentVideoSubTitleIndex = index }

    /// Xarici .srt faylı yükləyir.
    func addSubtitle(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    /// Altyazını irəli/geri sürüşdürür (mikrosaniyə).
    func setSubtitleDelay(seconds: Double) {
        player.currentVideoSubTitleDelay = Int(seconds * 1_000_000)
    }

    var audioTracks: [(index: Int32, name: String)] {
        zip(
            player.audioTrackIndexes.compactMap { $0 as? Int32 },
            player.audioTrackNames.compactMap { $0 as? String }
        ).map { ($0, $1) }
    }

    func selectAudioTrack(index: Int32) { player.currentAudioTrackIndex = index }

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
            default:
                self.emitSnapshot()
            }
        }
    }
}
#endif

import AVFoundation
import Combine
import UIKit

/// AVFoundation mühərriki. Aparat dekoderi, PiP və AirPlay video burada işləyir.
@MainActor
final class SystemPlaybackEngine: NSObject, PlaybackEngine {

    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((PlaybackError) -> Void)?

    let supportsPictureInPicture = true
    let supportsAirPlayVideo = true

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        installTimeObserver()
    }

    func load(url: URL, startAtSeconds: Double) throws {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "AVPlayerItem failed"
            Task { @MainActor in self?.onFailure?(.engineFailed(message)) }
        }

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFinished?() }
        }

        player.replaceCurrentItem(with: item)

        if startAtSeconds > 1 {
            player.seek(to: CMTime(seconds: startAtSeconds, preferredTimescale: 600))
        }
    }

    func play() { player.play(); emitSnapshot() }
    func pause() { player.pause(); emitSnapshot() }

    func seek(toSeconds seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        emitSnapshot()
    }

    func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.timeControlStatus == .playing { player.rate = rate }
    }

    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    func makeVideoView() -> UIView? {
        PlayerLayerView(player: player)
    }

    // MARK: - Detallar

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.emitSnapshot() }
        }
    }

    private func emitSnapshot() {
        let duration = player.currentItem?.duration.seconds ?? 0
        onSnapshot?(
            PlaybackSnapshot(
                isPlaying: player.timeControlStatus == .playing,
                position: player.currentTime().seconds,
                duration: duration.isFinite ? duration : 0,
                isBuffering: player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                engine: .system
            )
        )
    }
}

/// AVPlayerLayer-i UIView içində saxlayan nazik qab.
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

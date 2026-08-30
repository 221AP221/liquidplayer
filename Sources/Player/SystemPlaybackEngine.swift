import AVFoundation
import AVKit
import UIKit

/// AVFoundation mühərriki. Aparat dekoderi, PiP və AirPlay video burada işləyir.
@MainActor
final class SystemPlaybackEngine: NSObject, PlaybackEngine {

    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((PlaybackError) -> Void)?
    var onTracksChanged: (() -> Void)?

    let supportsPictureInPicture = true
    let supportsAirPlayVideo = true

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    /// Trek qrupları asinxron yüklənir və nəticə burada saxlanılır ki,
    /// UI onları sinxron oxuya bilsin.
    private var legibleGroup: AVMediaSelectionGroup?
    private var audibleGroup: AVMediaSelectionGroup?

    private var pipController: AVPictureInPictureController?
    private var playerLayerView: PlayerLayerView?

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        installTimeObserver()
    }

    func load(url: URL, startAtSeconds: Double) throws {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        legibleGroup = nil
        audibleGroup = nil

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

        loadSelectionGroups(from: asset)
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
        pipController = nil
        playerLayerView = nil
        player.replaceCurrentItem(with: nil)
    }

    func makeVideoView() -> UIView? {
        let view = PlayerLayerView(player: player)
        playerLayerView = view
        setUpPictureInPicture(with: view.playerLayer)
        return view
    }

    // MARK: - Treklər

    var subtitleTracks: [MediaTrack] {
        tracks(in: legibleGroup)
    }

    var audioTracks: [MediaTrack] {
        tracks(in: audibleGroup)
    }

    var currentSubtitleTrackID: Int32? {
        selectedIndex(in: legibleGroup)
    }

    var currentAudioTrackID: Int32? {
        selectedIndex(in: audibleGroup)
    }

    func selectSubtitle(id: Int32?) {
        guard let group = legibleGroup, let item = player.currentItem else { return }
        guard let id, Int(id) < group.options.count else {
            item.select(nil, in: group)   // altyazını söndürür
            onTracksChanged?()
            return
        }
        item.select(group.options[Int(id)], in: group)
        onTracksChanged?()
    }

    func selectAudioTrack(id: Int32) {
        guard let group = audibleGroup, let item = player.currentItem,
              Int(id) < group.options.count else { return }
        item.select(group.options[Int(id)], in: group)
        onTracksChanged?()
    }

    /// Trek qrupları asset açılandan sonra gəlir, ona görə fon tapşırığında yüklənir.
    private func loadSelectionGroups(from asset: AVURLAsset) {
        Task { @MainActor [weak self] in
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
            guard let self else { return }
            self.legibleGroup = legible
            self.audibleGroup = audible
            self.onTracksChanged?()
        }
    }

    private func tracks(in group: AVMediaSelectionGroup?) -> [MediaTrack] {
        guard let group else { return [] }
        return group.options.enumerated().map { index, option in
            MediaTrack(
                id: Int32(index),
                name: option.displayName,
                languageCode: option.extendedLanguageTag
            )
        }
    }

    private func selectedIndex(in group: AVMediaSelectionGroup?) -> Int32? {
        guard let group,
              let selection = player.currentItem?.currentMediaSelection,
              let option = selection.selectedMediaOption(in: group),
              let index = group.options.firstIndex(of: option)
        else { return nil }
        return Int32(index)
    }

    // MARK: - Picture-in-Picture

    var isPictureInPictureActive: Bool {
        pipController?.isPictureInPictureActive ?? false
    }

    func startPictureInPicture() {
        guard let pipController, pipController.isPictureInPicturePossible else { return }
        pipController.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }

    private func setUpPictureInPicture(with layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // Tip açıq yazılıb: `init(playerLayer:)` SDK versiyasından asılı olaraq
        // failable ola bilər, belə yazılışda hər iki halda kompilyasiya olunur.
        let controller: AVPictureInPictureController? = AVPictureInPictureController(playerLayer: layer)
        // İstifadəçi appdan çıxanda video özü kiçik pəncərəyə keçsin.
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller
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

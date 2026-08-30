import AVFoundation
import Foundation
import MediaPlayer
import Observation
import SwiftData
import UIKit

/// Appdakı yeganə player. Növbəni, mühərriyi və oxunmuş yeri idarə edir.
///
/// Ekranlar burada nə AVFoundation, nə VLC görür — yalnız `snapshot` və əmrlər.
@MainActor
@Observable
final class PlayerController {

    // MARK: - Oxunan vəziyyət

    private(set) var current: MediaItem?
    private(set) var snapshot = PlaybackSnapshot()
    private(set) var queue: [MediaItem] = []
    private(set) var notice: PlaybackNotice?

    var isExpanded = false
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var rate: Float = 1.0 {
        didSet { engine?.setRate(rate) }
    }

    /// İstifadəçi "bir daha soruşma" seçibsə VLC xəbərdarlığı təkrarlanmır.
    var suppressDecodingNotice = false

    var isPlaying: Bool { snapshot.isPlaying }

    // MARK: - Treklər və PiP
    //
    // Bunlar hesablanan xassə deyil, saxlanan dəyərdir: `@Observable` yalnız
    // saxlanan dəyər dəyişəndə UI-ı yeniləyir, mühərriyi hər dəfə sorğulamaq isə
    // yenilənməni işə salmır.

    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var currentSubtitleTrackID: Int32?
    private(set) var currentAudioTrackID: Int32?

    var supportsPictureInPicture: Bool { engine?.supportsPictureInPicture ?? false }
    var supportsExternalSubtitles: Bool { engine?.supportsExternalSubtitles ?? false }
    var supportsSubtitleDelay: Bool { engine?.supportsSubtitleDelay ?? false }
    private(set) var isPictureInPictureActive = false
    private(set) var subtitleDelay: Double = 0

    /// Video oynayırsa və mühərrik dəstəkləyirsə trek seçicisi açıla bilər.
    var canChooseTracks: Bool { !subtitleTracks.isEmpty || !audioTracks.isEmpty }

    // MARK: - Daxili

    private var engine: PlaybackEngine?
    private var accessedURL: URL?
    private var context: ModelContext?
    private var progressSaveCounter = 0

    init() {
        configureAudioSession()
        installRemoteCommands()
    }

    func attach(context: ModelContext) {
        self.context = context
    }

    // MARK: - Oxutma

    func play(_ item: MediaItem, queue newQueue: [MediaItem] = []) {
        stopCurrent()

        guard let url = resolveURL(for: item) else {
            item.isMissing = true
            notice = .fileMissing(filename: item.filename)
            return
        }
        guard EngineRouter.isSupported(fileExtension: item.fileExtension) else {
            notice = .unsupportedFormat(fileExtension: item.fileExtension)
            return
        }

        item.isMissing = false
        current = item
        queue = newQueue.isEmpty ? queue : newQueue

        let kind = EngineRouter.engine(forFileExtension: item.fileExtension)
        if kind == .vlc && !EngineRouter.isVLCAvailable {
            notice = .unsupportedFormat(fileExtension: item.fileExtension)
            return
        }
        item.engine = kind

        let newEngine = EngineRouter.makeEngine(kind)
        wire(newEngine)
        engine = newEngine

        do {
            try newEngine.load(url: url, startAtSeconds: item.progress * item.duration)
            newEngine.setRate(rate)
            newEngine.play()
            isExpanded = true
            item.lastPlayedAt = .now

            if kind == .vlc && !suppressDecodingNotice {
                notice = .softwareDecoding(codec: item.videoCodec)
            }
            updateNowPlayingInfo()
        } catch {
            notice = .fileMissing(filename: item.filename)
        }
    }

    func togglePlayPause() {
        guard let engine else { return }
        snapshot.isPlaying ? engine.pause() : engine.play()
    }

    func seek(toFraction fraction: Double) {
        guard snapshot.duration > 0 else { return }
        engine?.seek(toSeconds: snapshot.duration * min(1, max(0, fraction)))
    }

    func skip(bySeconds delta: Double) {
        engine?.seek(toSeconds: max(0, snapshot.position + delta))
    }

    func next() {
        guard let currentItem = current else { return }
        if repeatMode == .one {
            engine?.seek(toSeconds: 0)
            return
        }
        guard let index = queue.firstIndex(where: { $0.id == currentItem.id }) else {
            if let first = queue.first { play(first) }
            return
        }
        let nextIndex = index + 1
        if nextIndex < queue.count {
            play(queue[nextIndex])
        } else if repeatMode == .all, let first = queue.first {
            play(first)
        } else {
            engine?.pause()
        }
    }

    func previous() {
        // İlk 3 saniyədə "əvvəlki" trek, sonra treyin əvvəli — iOS adəti.
        if snapshot.position > 3 {
            engine?.seek(toSeconds: 0)
            return
        }
        guard let currentItem = current,
              let index = queue.firstIndex(where: { $0.id == currentItem.id }),
              index > 0
        else {
            engine?.seek(toSeconds: 0)
            return
        }
        play(queue[index - 1])
    }

    func dismissNotice() { notice = nil }

    // MARK: - Trek seçimi

    func selectSubtitle(id: Int32?) {
        engine?.selectSubtitle(id: id)
        refreshTracks()
    }

    func selectAudioTrack(id: Int32) {
        engine?.selectAudioTrack(id: id)
        refreshTracks()
    }

    func loadExternalSubtitle(url: URL) {
        guard let engine, engine.supportsExternalSubtitles else { return }
        // Xarici fayl da security-scoped-dur; oxunub bitənə qədər açıq qalmalıdır.
        let opened = url.startAccessingSecurityScopedResource()
        engine.loadExternalSubtitle(url: url)
        if opened { url.stopAccessingSecurityScopedResource() }
        refreshTracks()
    }

    func setSubtitleDelay(_ seconds: Double) {
        guard let engine, engine.supportsSubtitleDelay else { return }
        engine.subtitleDelay = seconds
        subtitleDelay = seconds
    }

    private func refreshTracks() {
        subtitleTracks = engine?.subtitleTracks ?? []
        audioTracks = engine?.audioTracks ?? []
        currentSubtitleTrackID = engine?.currentSubtitleTrackID
        currentAudioTrackID = engine?.currentAudioTrackID
        subtitleDelay = engine?.subtitleDelay ?? 0
    }

    // MARK: - Picture-in-Picture

    func togglePictureInPicture() {
        guard let engine, engine.supportsPictureInPicture else { return }
        if engine.isPictureInPictureActive {
            engine.stopPictureInPicture()
        } else {
            engine.startPictureInPicture()
        }
        isPictureInPictureActive = engine.isPictureInPictureActive
    }

    func makeVideoView() -> UIView? { engine?.makeVideoView() }

    // MARK: - Fayla giriş

    /// Bookmark-ı həll edir və security-scoped girişi açır.
    /// Qovluq yerini dəyişibsə `nil` qayıdır — UI "fayl tapılmadı" göstərir.
    private func resolveURL(for item: MediaItem) -> URL? {
        guard let bookmark = item.bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        accessedURL = url

        if isStale, let refreshed = try? url.bookmarkData() {
            item.bookmark = refreshed
        }
        return url
    }

    private func stopCurrent() {
        saveProgress(force: true)
        subtitleTracks = []
        audioTracks = []
        currentSubtitleTrackID = nil
        currentAudioTrackID = nil
        subtitleDelay = 0
        isPictureInPictureActive = false
        engine?.teardown()
        engine = nil
        if let accessedURL {
            accessedURL.stopAccessingSecurityScopedResource()
            self.accessedURL = nil
        }
    }

    private func wire(_ engine: PlaybackEngine) {
        engine.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.snapshot = snapshot
            self.saveProgress(force: false)
            self.updateNowPlayingElapsed()
        }
        engine.onFinished = { [weak self] in
            self?.current?.progress = 1
            self?.next()
        }
        engine.onTracksChanged = { [weak self] in
            self?.refreshTracks()
        }
        engine.onFailure = { [weak self] _ in
            guard let self, let item = self.current else { return }
            self.notice = .corruptedAt(seconds: self.snapshot.position)
            item.isMissing = false
        }
    }

    /// Hər saniyədə bir dəfədən çox yazmırıq — SwiftData-nı boş yerə yormamaq üçün.
    private func saveProgress(force: Bool) {
        guard let item = current, snapshot.duration > 0 else { return }
        progressSaveCounter += 1
        guard force || progressSaveCounter % 8 == 0 else { return }
        item.progress = snapshot.fraction
        if item.duration == 0 { item.duration = snapshot.duration }
        try? context?.save()
    }

    // MARK: - Sistem inteqrasiyası

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.engine?.seek(toSeconds: event.positionTime) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(bySeconds: 30) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(bySeconds: -10) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let item = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist ?? "",
            MPMediaItemPropertyPlaybackDuration: item.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.position,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? Double(rate) : 0
        ]
        if let album = item.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let data = item.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.position
        info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.isPlaying ? Double(rate) : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

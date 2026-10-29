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
    var shuffle = false {
        didSet { shufflePlayed.removeAll() }
    }
    var repeatMode: RepeatMode = .off

    /// Oxutma sürəti. Bütün fayllar üçün birdir və saxlanılır.
    var rate: Float = 1.0 {
        didSet {
            engine?.setRate(rate)
            UserDefaults.standard.set(rate, forKey: Self.rateDefaultsKey)
            updateNowPlayingElapsed()
        }
    }

    static let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// İstifadəçi "bir daha soruşma" seçibsə VLC xəbərdarlığı təkrarlanmır.
    var suppressDecodingNotice = false {
        didSet { UserDefaults.standard.set(suppressDecodingNotice, forKey: Self.suppressNoticeDefaultsKey) }
    }

    /// Hər yeni mühərrikdə artır. Video səthi buna bağlıdır ki, fayl dəyişəndə
    /// köhnə mühərrikin görüntüsü ekranda qalmasın.
    private(set) var engineGeneration = 0

    /// Aktiv yuxu taymeri; `nil` — söndürülüb.
    private(set) var sleepTimer: SleepTimer?

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

    // MARK: - Fəsillər

    private(set) var chapters: [MediaChapter] = []

    /// `snapshot` saxlanan dəyərdir, ona görə bu hesablanan xassə də UI-ı yeniləyir.
    var currentChapter: MediaChapter? {
        chapters.last { $0.start <= snapshot.position + 0.25 }
    }

    // MARK: - Ekvalayzer

    /// Bütün fayllar üçün bir dəyər; UserDefaults-da saxlanılır.
    var equalizer: EqualizerSettings {
        didSet {
            guard equalizer != oldValue else { return }
            engine?.applyEqualizer(equalizer)
            Self.saveEqualizer(equalizer)
        }
    }

    /// Hazırkı mühərrik EQ bacarırmı. Heç nə oynamırsa tənzimləmək yenə də olar.
    var supportsEqualizer: Bool { engine?.supportsEqualizer ?? true }

    // MARK: - Daxili

    private var engine: PlaybackEngine?
    private var accessedURL: URL?
    private var context: ModelContext?
    private var progressSaveCounter = 0

    /// Shuffle rejimində bu növbədə artıq oxunanlar — təkrar düşməsin deyə.
    private var shufflePlayed: Set<UUID> = []
    private var sleepTask: Task<Void, Never>?
    private var wasPlayingBeforeInterruption = false
    private var sessionObservers: [NSObjectProtocol] = []

    private static let rateDefaultsKey = "playback.rate"
    private static let suppressNoticeDefaultsKey = "playback.suppressDecodingNotice"

    init() {
        equalizer = Self.loadEqualizer()
        let defaults = UserDefaults.standard
        let savedRate = defaults.float(forKey: Self.rateDefaultsKey)
        rate = Self.availableRates.contains(savedRate) ? savedRate : 1.0
        suppressDecodingNotice = defaults.bool(forKey: Self.suppressNoticeDefaultsKey)
        configureAudioSession()
        observeAudioSession()
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
        if !newQueue.isEmpty {
            queue = newQueue
            shufflePlayed.removeAll()
        } else if !queue.contains(where: { $0.id == item.id }) {
            queue = [item]
        }

        let kind = EngineRouter.engine(forFileExtension: item.fileExtension)
        if kind == .vlc && !EngineRouter.isVLCAvailable {
            notice = .unsupportedFormat(fileExtension: item.fileExtension)
            return
        }
        item.engine = kind

        let newEngine = EngineRouter.makeEngine(kind)
        wire(newEngine)
        engine = newEngine
        engineGeneration += 1

        do {
            try newEngine.load(url: url, startAtSeconds: item.progress * item.duration)
            newEngine.applyEqualizer(equalizer)
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

    /// Kilid ekranı «play»/«pause» ayrıca göndərir — toggle onları tərsinə çevirə bilər.
    func resume() { engine?.play() }
    func pause() { engine?.pause() }

    /// Oxutmanı tam dayandırır: mini-player gizlənir, növbə boşalır.
    func stop() {
        stopCurrent()
        current = nil
        snapshot = PlaybackSnapshot()
        queue = []
        shufflePlayed.removeAll()
        isExpanded = false
        setSleepTimer(nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Silinən elementlər üçün: oynayırsa dayandırır, növbədən çıxarır.
    /// SwiftData obyekti silinəndən sonra ona toxunmaq çökmə verir.
    func forget(_ items: [MediaItem]) {
        let ids = Set(items.map(\.id))
        if let current, ids.contains(current.id) { stop() }
        queue.removeAll { ids.contains($0.id) }
    }

    func seek(toFraction fraction: Double) {
        guard snapshot.duration > 0 else { return }
        engine?.seek(toSeconds: snapshot.duration * min(1, max(0, fraction)))
    }

    func skip(bySeconds delta: Double) {
        engine?.seek(toSeconds: max(0, snapshot.position + delta))
    }

    func seek(toSeconds seconds: Double) {
        let upperBound = snapshot.duration > 0 ? snapshot.duration : seconds
        engine?.seek(toSeconds: min(upperBound, max(0, seconds)))
    }

    func next() {
        guard let currentItem = current else { return }
        if repeatMode == .one {
            engine?.seek(toSeconds: 0)
            return
        }
        if shuffle, queue.count > 1 {
            playRandomUnplayed(after: currentItem)
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

    /// Növbədə hələ oxunmamış təsadüfi element. Hamısı oxunubsa «təkrar: hamısı»
    /// açıqdırsa dövr yenidən başlayır, yoxsa dayanır.
    private func playRandomUnplayed(after currentItem: MediaItem) {
        shufflePlayed.insert(currentItem.id)
        var candidates = queue.filter { !shufflePlayed.contains($0.id) }
        if candidates.isEmpty {
            guard repeatMode == .all else {
                engine?.pause()
                return
            }
            shufflePlayed = [currentItem.id]
            candidates = queue.filter { $0.id != currentItem.id }
        }
        if let pick = candidates.randomElement() { play(pick) }
    }

    func dismissNotice() { notice = nil }

    // MARK: - Növbə

    /// Hazırkı elementdən sonra gələnlər.
    var upcoming: [MediaItem] { Array(queue.dropFirst(upcomingStart)) }

    private var upcomingStart: Int {
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return 0 }
        return index + 1
    }

    /// Hazırkıdan dərhal sonra oxunsun. Heç nə oynamırsa dərhal başlayır.
    func playNext(_ item: MediaItem) {
        guard let current else {
            play(item, queue: [item])
            return
        }
        guard item.id != current.id else { return }
        queue.removeAll { $0.id == item.id }
        queue.insert(item, at: upcomingStart)
    }

    /// Növbənin sonuna əlavə edir. Heç nə oynamırsa dərhal başlayır.
    func enqueue(_ item: MediaItem) {
        guard let current else {
            play(item, queue: [item])
            return
        }
        guard item.id != current.id else { return }
        queue.removeAll { $0.id == item.id }
        queue.append(item)
    }

    /// `offsets` — `upcoming` siyahısındakı indekslər.
    func removeUpcoming(atOffsets offsets: IndexSet) {
        let start = upcomingStart
        for index in offsets.map({ $0 + start }).sorted(by: >) where queue.indices.contains(index) {
            queue.remove(at: index)
        }
    }

    /// `List.onMove` ilə eyni semantika, `upcoming` indeksləri ilə.
    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        let start = min(upcomingStart, queue.count)
        let newOrder = Self.reordered(Array(queue[start...]), moving: source, to: destination)
        queue.replaceSubrange(start..., with: newOrder)
    }

    /// `destination` — köçürmədən əvvəlki massivdə indeks (SwiftUI `onMove` kimi).
    nonisolated static func reordered<Element>(_ items: [Element], moving source: IndexSet, to destination: Int) -> [Element] {
        let indices = source.filter { items.indices.contains($0) }.sorted()
        guard !indices.isEmpty else { return items }
        let moving = indices.map { items[$0] }
        var result = items
        var target = min(max(destination, 0), items.count)
        for index in indices.reversed() {
            result.remove(at: index)
            if index < target { target -= 1 }
        }
        result.insert(contentsOf: moving, at: target)
        return result
    }

    // MARK: - Yuxu taymeri

    func setSleepTimer(_ option: SleepTimerOption?) {
        sleepTask?.cancel()
        sleepTask = nil

        guard let option else {
            sleepTimer = nil
            return
        }

        switch option {
        case .minutes(let minutes):
            let seconds = TimeInterval(minutes * 60)
            sleepTimer = .at(Date.now.addingTimeInterval(seconds))
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.fireSleepTimer()
            }
        case .endOfChapter:
            // Fəsil yoxdursa fayl sonu ən yaxın mənadır.
            if let chapter = currentChapter {
                sleepTimer = .endOfChapter(chapterID: chapter.id)
            } else {
                sleepTimer = .endOfItem
            }
        case .endOfItem:
            sleepTimer = .endOfItem
        }
    }

    private func fireSleepTimer() {
        engine?.pause()
        sleepTimer = nil
        sleepTask = nil
    }

    /// Fəsil sonu taymeri mövqeyə görə yoxlanır: geri çəkmək onu işə salmır.
    private func checkChapterSleepTimer() {
        guard case .endOfChapter(let chapterID)? = sleepTimer,
              let chapter = chapters.first(where: { $0.id == chapterID })
        else { return }
        if snapshot.position >= chapter.end - 0.3 { fireSleepTimer() }
    }

    // MARK: - Fəsil keçidi

    func selectChapter(_ chapter: MediaChapter) {
        seek(toSeconds: chapter.start)
        if !snapshot.isPlaying { engine?.play() }
    }

    func nextChapter() {
        guard let next = chapters.first(where: { $0.start > snapshot.position + 0.5 }) else { return }
        selectChapter(next)
    }

    /// Fəslin ilk 3 saniyəsindəyiksə əvvəlki fəslə, yoxsa hazırkının əvvəlinə — treklərdəki kimi.
    func previousChapter() {
        guard let current = currentChapter,
              let index = chapters.firstIndex(of: current)
        else { return }
        if snapshot.position - current.start > 3 || index == 0 {
            selectChapter(current)
        } else {
            selectChapter(chapters[index - 1])
        }
    }

    // MARK: - Əlfəcinlər

    /// Hazırkı mövqedə əlfəcin yaradır. Qeyd boşdursa fəsil adı yazılır.
    @discardableResult
    func addBookmark(note: String = "") -> Bookmark? {
        guard let item = current else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = Bookmark(
            position: snapshot.position,
            note: trimmed.isEmpty ? (currentChapter?.title ?? "") : trimmed
        )
        context?.insert(bookmark)
        bookmark.item = item
        try? context?.save()
        return bookmark
    }

    func jump(to bookmark: Bookmark) {
        guard bookmark.item?.id == current?.id else { return }
        seek(toSeconds: bookmark.position)
        if !snapshot.isPlaying { engine?.play() }
    }

    func renameBookmark(_ bookmark: Bookmark, note: String) {
        bookmark.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context?.save()
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        context?.delete(bookmark)
        try? context?.save()
    }

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
        chapters = (engine?.chapters ?? []).sorted { $0.start < $1.start }
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
        chapters = []
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
            self.checkChapterSleepTimer()
        }
        engine.onFinished = { [weak self] in
            guard let self else { return }
            self.current?.progress = 1
            switch self.sleepTimer {
            case .some(.endOfItem), .some(.endOfChapter):
                // Fayl bitdi — taymer məqsədinə çatdı, növbətiyə keçmirik.
                self.fireSleepTimer()
                try? self.context?.save()
            default:
                self.next()
            }
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

    // MARK: - EQ yaddaşı

    private static let equalizerDefaultsKey = "equalizer.settings"

    private static func loadEqualizer() -> EqualizerSettings {
        guard let data = UserDefaults.standard.data(forKey: equalizerDefaultsKey),
              let settings = try? JSONDecoder().decode(EqualizerSettings.self, from: data)
        else { return .flat }
        return settings.normalized()
    }

    private static func saveEqualizer(_ settings: EqualizerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: equalizerDefaultsKey)
    }

    // MARK: - Sistem inteqrasiyası

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    /// Zəng, Siri, başqa app səsi kəsəndə və qulaqlıq çıxanda.
    /// AVPlayer özü dayanır, VLC isə yox — ona görə hər iki halda əl ilə idarə olunur.
    private func observeAudioSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        })

        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonRaw: reasonRaw)
            }
        })
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = snapshot.isPlaying
            engine?.pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            guard wasPlayingBeforeInterruption, options.contains(.shouldResume) else { return }
            wasPlayingBeforeInterruption = false
            try? AVAudioSession.sharedInstance().setActive(true)
            engine?.play()
        @unknown default:
            break
        }
    }

    /// Qulaqlıq və ya Bluetooth ayrılanda səs dinamikə keçməsin — iOS adəti.
    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw,
              AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable
        else { return }
        engine?.pause()
    }

    // MARK: - Sözlər

    /// Faylın daxili sözləri (iTunes ©lyr, ID3 USLT). AVFoundation MKV/FLAC
    /// oxumadığı üçün VLC faylları üçün `nil` qayıdır.
    func loadLyrics() async -> String? {
        guard let url = accessedURL, let item = current, item.engine == .system else { return nil }
        let asset = AVURLAsset(url: url)

        if let lyrics = (try? await asset.load(.lyrics)) ?? nil,
           !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lyrics
        }

        let identifiers: Set<AVMetadataIdentifier> = [.id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics]
        let metadata = (try? await asset.load(.metadata)) ?? []
        for entry in metadata {
            guard let identifier = entry.identifier, identifiers.contains(identifier) else { continue }
            if let value = (try? await entry.load(.stringValue)) ?? nil,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        // Qulaqlıq düyməsi və CarPlay toggle göndərir.
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
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

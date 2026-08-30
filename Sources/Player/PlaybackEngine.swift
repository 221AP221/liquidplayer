import Foundation
import UIKit

/// Player nüvəsi ilə UI arasındakı yeganə müqavilə.
/// AVFoundation və VLCKit bunun iki tətbiqidir; ekranlar hansının işlədiyini bilmir.
@MainActor
protocol PlaybackEngine: AnyObject {
    /// Vəziyyət dəyişəndə (təxminən saniyədə 4 dəfə) çağırılır.
    var onSnapshot: ((PlaybackSnapshot) -> Void)? { get set }
    /// Fayl sona çatanda.
    var onFinished: (() -> Void)? { get set }
    /// Mühərrik səviyyəsində xəta.
    var onFailure: ((PlaybackError) -> Void)? { get set }
    /// Altyazı/səs trekləri gec gəlir — siyahı hazır olanda çağırılır.
    var onTracksChanged: (() -> Void)? { get set }

    func load(url: URL, startAtSeconds: Double) throws
    func play()
    func pause()
    func seek(toSeconds seconds: Double)
    func setRate(_ rate: Float)
    func teardown()

    /// Video üçün render səthi. Audio mühərrikləri `nil` qaytarır.
    func makeVideoView() -> UIView?

    /// Bu mühərrik Picture-in-Picture dəstəkləyirmi.
    var supportsPictureInPicture: Bool { get }
    /// AirPlay-ə video göndərə bilirmi (yoxsa yalnız ekran güzgüsü).
    var supportsAirPlayVideo: Bool { get }

    // MARK: - Treklər

    var subtitleTracks: [MediaTrack] { get }
    var audioTracks: [MediaTrack] { get }
    var currentSubtitleTrackID: Int32? { get }
    var currentAudioTrackID: Int32? { get }

    /// `nil` — altyazını söndürür.
    func selectSubtitle(id: Int32?)
    func selectAudioTrack(id: Int32)

    /// Xarici .srt/.ass faylı. Yalnız VLC dəstəkləyir.
    var supportsExternalSubtitles: Bool { get }
    func loadExternalSubtitle(url: URL)

    /// Altyazı sinxronu. Yalnız VLC dəstəkləyir.
    var supportsSubtitleDelay: Bool { get }
    var subtitleDelay: Double { get set }

    // MARK: - Picture-in-Picture

    var isPictureInPictureActive: Bool { get }
    func startPictureInPicture()
    func stopPictureInPicture()
}

/// Mühərriklərin çoxu bu imkanların bir hissəsini dəstəkləmir —
/// standart tətbiqlər onları səssizcə boş buraxır.
extension PlaybackEngine {
    var subtitleTracks: [MediaTrack] { [] }
    var audioTracks: [MediaTrack] { [] }
    var currentSubtitleTrackID: Int32? { nil }
    var currentAudioTrackID: Int32? { nil }
    func selectSubtitle(id: Int32?) {}
    func selectAudioTrack(id: Int32) {}

    var supportsExternalSubtitles: Bool { false }
    func loadExternalSubtitle(url: URL) {}

    var supportsSubtitleDelay: Bool { false }
    var subtitleDelay: Double {
        get { 0 }
        set {}
    }

    var isPictureInPictureActive: Bool { false }
    func startPictureInPicture() {}
    func stopPictureInPicture() {}
}

/// Faylın hansı mühərriklə açılacağını təyin edir.
///
/// Qayda sadədir: aparat dekoderi bacarırsa AVFoundation seçilir, çünki
/// batareya, PiP və AirPlay orada qazanılır. Qalan hər şey VLC-yə gedir.
enum EngineRouter {

    /// AVFoundation-ın etibarlı oxuduğu uzantılar.
    private static let systemExtensions: Set<String> = [
        "m4a", "mp3", "aac", "wav", "aiff", "aif", "caf", "m4b",
        "mp4", "m4v", "mov"
    ]

    /// Yalnız VLC-nin açdığı, geniş yayılmış uzantılar.
    private static let vlcExtensions: Set<String> = [
        "mkv", "flac", "ogg", "oga", "opus", "wma", "ape", "wv",
        "avi", "wmv", "flv", "webm", "ts", "m2ts", "vob", "mpg", "mpeg", "3gp", "ogv"
    ]

    /// Heç bir mühərriyin açmadığı formatlar — idxalda dərhal işarələnir.
    private static let unsupportedExtensions: Set<String> = [
        "rm", "rmvb", "asf", "swf"
    ]

    static func isSupported(fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased()
        return !unsupportedExtensions.contains(ext)
            && (systemExtensions.contains(ext) || vlcExtensions.contains(ext))
    }

    static func engine(forFileExtension fileExtension: String) -> EngineKind {
        systemExtensions.contains(fileExtension.lowercased()) ? .system : .vlc
    }

    static func kind(forFileExtension fileExtension: String) -> MediaKind {
        let videoExtensions: Set<String> = [
            "mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm",
            "ts", "m2ts", "vob", "mpg", "mpeg", "3gp", "ogv"
        ]
        let ext = fileExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if ext == "m4b" { return .audiobook }
        return .audio
    }

    /// Mühərriyi qurur. VLCKit layihəyə əlavə olunmayıbsa `.vlc` sorğusu
    /// AVFoundation-a düşür və çağıran tərəf `unsupported` xətası alır —
    /// bu, kompilyasiyanı VLCKit olmadan da saxlamaq üçündür.
    @MainActor
    static func makeEngine(_ kind: EngineKind) -> PlaybackEngine {
        switch kind {
        case .system:
            return SystemPlaybackEngine()
        case .vlc:
            #if canImport(MobileVLCKit)
            return VLCPlaybackEngine()
            #else
            return SystemPlaybackEngine()
            #endif
        }
    }

    /// VLCKit layihəyə qoşulubmu.
    static var isVLCAvailable: Bool {
        #if canImport(MobileVLCKit)
        return true
        #else
        return false
        #endif
    }
}

import Foundation

/// Player-in bir anlıq vəziyyəti. UI yalnız bunu oxuyur.
struct PlaybackSnapshot: Equatable, Sendable {
    var isPlaying: Bool = false
    var position: Double = 0        // saniyə
    var duration: Double = 0        // saniyə
    var isBuffering: Bool = false
    var engine: EngineKind = .system

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}

/// Altyazı və ya səs treki. Mühərrikdən asılı olmayan sadə təsvir —
/// AVFoundation-da `AVMediaSelectionOption`, VLC-də tam indeks olur.
struct MediaTrack: Identifiable, Hashable, Sendable {
    let id: Int32
    let name: String
    /// Dil kodu (`az`, `en`) — varsa UI-da rozet kimi göstərilir.
    let languageCode: String?

    init(id: Int32, name: String, languageCode: String? = nil) {
        self.id = id
        self.name = name
        self.languageCode = languageCode
    }
}

/// Fəsil. AVFoundation-da `AVTimedMetadataGroup`, VLC-də fəsil təsviri olur.
struct MediaChapter: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let start: Double       // saniyə
    let duration: Double    // saniyə

    var end: Double { start + duration }

    func contains(_ seconds: Double) -> Bool {
        seconds >= start && seconds < end
    }
}

enum RepeatMode: Int, CaseIterable, Sendable {
    case off, all, one
}

/// Yuxu taymerinin işlək vəziyyəti.
enum SleepTimer: Equatable, Sendable {
    /// Bu anda dayan.
    case at(Date)
    /// Bu fəsil bitəndə dayan.
    case endOfChapter(chapterID: Int)
    /// Fayl bitəndə dayan, növbətiyə keçmə.
    case endOfItem
}

/// UI-da təklif olunan yuxu taymeri seçimləri.
enum SleepTimerOption: Hashable, Identifiable, Sendable {
    case minutes(Int)
    case endOfChapter
    case endOfItem

    static let all: [SleepTimerOption] = [
        .minutes(5), .minutes(15), .minutes(30), .minutes(45), .minutes(60),
        .endOfChapter, .endOfItem
    ]

    var id: String {
        switch self {
        case .minutes(let value): "minutes.\(value)"
        case .endOfChapter:       "endOfChapter"
        case .endOfItem:          "endOfItem"
        }
    }
}

/// Oxutma zamanı istifadəçiyə bir dəfə göstərilən xəbərdarlıqlar.
enum PlaybackNotice: Equatable, Sendable {
    /// VLC mühərriki işə düşür: PiP və AirPlay video itir.
    case softwareDecoding(codec: String?)
    case fileMissing(filename: String)
    case unsupportedFormat(fileExtension: String)
    case corruptedAt(seconds: Double)
}

enum PlaybackError: Error, Equatable, Sendable {
    case bookmarkUnresolvable
    case accessDenied
    case unsupported(String)
    case engineFailed(String)
}

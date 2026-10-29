import XCTest
@testable import LiquidPlayer

final class EqualizerSettingsTests: XCTestCase {

    func testEveryPresetHasOneGainPerBand() {
        for preset in EqualizerPreset.allCases {
            XCTAssertEqual(preset.gains.count, EqualizerSettings.frequencies.count, preset.rawValue)
        }
    }

    func testSetGainClampsAndClearsPreset() {
        var settings = EqualizerSettings.flat
        settings.setGain(40, at: 0)
        settings.setGain(-40, at: 1)
        XCTAssertEqual(settings.gains[0], EqualizerSettings.gainRange.upperBound)
        XCTAssertEqual(settings.gains[1], EqualizerSettings.gainRange.lowerBound)
        XCTAssertNil(settings.preset)
    }

    func testSetGainIgnoresOutOfRangeBand() {
        var settings = EqualizerSettings.flat
        settings.setGain(6, at: 99)
        XCTAssertEqual(settings.gains, EqualizerPreset.flat.gains)
    }

    func testNormalizedRepairsWrongBandCount() {
        let short = EqualizerSettings(isEnabled: true, gains: [3, 3], preset: nil).normalized()
        XCTAssertEqual(short.gains.count, EqualizerSettings.frequencies.count)
        XCTAssertEqual(Array(short.gains.prefix(2)), [3, 3])

        let long = EqualizerSettings(isEnabled: true, gains: Array(repeating: 1, count: 20), preset: nil).normalized()
        XCTAssertEqual(long.gains.count, EqualizerSettings.frequencies.count)
    }

    func testCodableRoundTrip() throws {
        var settings = EqualizerSettings.flat
        settings.isEnabled = true
        settings.apply(.spokenWord)
        let decoded = try JSONDecoder().decode(EqualizerSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testFlatDetection() {
        var settings = EqualizerSettings.flat
        XCTAssertTrue(settings.isEffectivelyFlat)
        settings.isEnabled = true
        XCTAssertTrue(settings.isEffectivelyFlat)
        settings.apply(.vocal)
        XCTAssertFalse(settings.isEffectivelyFlat)
    }
}

final class MediaChapterTests: XCTestCase {

    func testContainsIsHalfOpen() {
        let chapter = MediaChapter(id: 0, title: "", start: 10, duration: 5)
        XCTAssertTrue(chapter.contains(10))
        XCTAssertTrue(chapter.contains(14.9))
        XCTAssertFalse(chapter.contains(15))
        XCTAssertEqual(chapter.end, 15)
    }
}

final class LibraryPathTests: XCTestCase {

    func testRelativePathInsideRoot() {
        let root = URL(fileURLWithPath: "/LiquidPlayerTests/Musiqi")
        let file = URL(fileURLWithPath: "/LiquidPlayerTests/Musiqi/Albom/01.mp3")
        XCTAssertEqual(LibraryImporter.relativePath(of: file, in: root), "Albom/01.mp3")
    }

    func testRelativePathWithTrailingSlashRoot() {
        let root = URL(fileURLWithPath: "/LiquidPlayerTests/Musiqi/", isDirectory: true)
        let file = URL(fileURLWithPath: "/LiquidPlayerTests/Musiqi/01.mp3")
        XCTAssertEqual(LibraryImporter.relativePath(of: file, in: root), "01.mp3")
    }

    func testSiblingFolderWithSamePrefixIsNotInside() {
        let root = URL(fileURLWithPath: "/LiquidPlayerTests/Musiqi")
        let file = URL(fileURLWithPath: "/LiquidPlayerTests/Musiqi2/01.mp3")
        XCTAssertEqual(LibraryImporter.relativePath(of: file, in: root), "01.mp3")
    }
}

final class QueueReorderTests: XCTestCase {

    private func move(_ items: [String], _ source: [Int], to destination: Int) -> [String] {
        PlayerController.reordered(items, moving: IndexSet(source), to: destination)
    }

    func testMoveDown() {
        XCTAssertEqual(move(["a", "b", "c", "d"], [0], to: 2), ["b", "a", "c", "d"])
    }

    func testMoveToEnd() {
        XCTAssertEqual(move(["a", "b", "c", "d"], [0], to: 4), ["b", "c", "d", "a"])
    }

    func testMoveUpToStart() {
        XCTAssertEqual(move(["a", "b", "c", "d"], [3], to: 0), ["d", "a", "b", "c"])
    }

    func testMoveSeveral() {
        XCTAssertEqual(move(["a", "b", "c", "d"], [1, 2], to: 4), ["a", "d", "b", "c"])
    }

    func testOutOfRangeIsIgnored() {
        XCTAssertEqual(move(["a", "b"], [5], to: 0), ["a", "b"])
    }
}

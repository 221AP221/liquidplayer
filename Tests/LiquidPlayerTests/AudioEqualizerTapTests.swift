import AVFoundation
import XCTest
@testable import LiquidPlayer

/// `AudioEqualizerTap`-in DSP hissəsini real tap olmadan yoxlayır:
/// buferi əl ilə qurub `prepare` / `process` çağırırıq — AVPlayer-in edəcəyi kimi.
final class AudioEqualizerTapTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let frameCount = 4_096

    // MARK: - Davranış

    func testDisabledEqualizerLeavesAudioUntouched() {
        let tap = AudioEqualizerTap(settings: .flat)
        let input = sine(frequency: 1_000)
        let output = run(tap, channels: [input, input])
        XCTAssertEqual(output[0], input)
        XCTAssertEqual(output[1], input)
    }

    func testEnabledButFlatIsPassThrough() {
        var settings = EqualizerSettings.flat
        settings.isEnabled = true
        let tap = AudioEqualizerTap(settings: settings)
        let input = sine(frequency: 1_000)
        XCTAssertEqual(run(tap, channels: [input])[0], input)
    }

    func testBoostRaisesLevelAtBandFrequency() {
        let tap = AudioEqualizerTap(settings: settings(gainDB: 12, atBand: 5))   // 1 kHz
        let input = sine(frequency: 1_000)
        let output = run(tap, channels: [input])[0]
        // +12 dB, ümumi səviyyə endirilməsi (-6 dB) çıxılandan sonra ≈ +6 dB ≈ 2×.
        XCTAssertGreaterThan(rms(output, skip: 1_024), rms(input) * 1.6)
    }

    func testCutLowersLevelAtBandFrequency() {
        let tap = AudioEqualizerTap(settings: settings(gainDB: -12, atBand: 5))
        let input = sine(frequency: 1_000)
        let output = run(tap, channels: [input])[0]
        XCTAssertLessThan(rms(output, skip: 1_024), rms(input) * 0.4)
    }

    func testBassBoostBarelyTouchesHighFrequencies() {
        var bass = EqualizerSettings.flat
        bass.isEnabled = true
        bass.apply(.bassBoost)
        let tap = AudioEqualizerTap(settings: bass)
        let input = sine(frequency: 10_000)
        let output = run(tap, channels: [input])[0]
        // Yalnız kəsilməyə qarşı endirmə (-3 dB) qalmalıdır.
        let ratio = rms(output, skip: 1_024) / rms(input)
        XCTAssertEqual(ratio, pow(10, -3.0 / 20), accuracy: 0.08)
    }

    func testInterleavedStereoIsProcessedPerChannel() {
        let tap = AudioEqualizerTap(settings: settings(gainDB: -12, atBand: 5))
        let left = sine(frequency: 1_000)
        let right = sine(frequency: 16)   // demək olar ki, sabit — 1 kHz kəsimi ona təsir etmir
        let output = runInterleaved(tap, left: left, right: right)
        XCTAssertLessThan(rms(output.left, skip: 1_024), rms(left) * 0.4)
        XCTAssertEqual(rms(output.right, skip: 1_024), rms(right, skip: 1_024), accuracy: rms(right) * 0.1)
    }

    func testOutputStaysFinite() {
        var loud = EqualizerSettings.flat
        loud.isEnabled = true
        loud.gains = Array(repeating: EqualizerSettings.gainRange.upperBound, count: EqualizerSettings.frequencies.count)
        let tap = AudioEqualizerTap(settings: loud)
        let output = run(tap, channels: [sine(frequency: 64)])[0]
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testUnsupportedFormatIsPassThrough() {
        let tap = AudioEqualizerTap(settings: settings(gainDB: 12, atBand: 5))
        var format = floatFormat(channels: 1, interleaved: false)
        format.mFormatFlags = kAudioFormatFlagIsSignedInteger   // 16-bit int — toxunmamalıyıq
        format.mBitsPerChannel = 16
        tap.prepare(maxFrames: frameCount, format: format)
        let input = sine(frequency: 1_000)
        XCTAssertEqual(process(tap, channels: [input]), [input])
    }

    func testUpdateAppliesNewSettingsWithoutReprepare() {
        let tap = AudioEqualizerTap(settings: .flat)
        tap.prepare(maxFrames: frameCount, format: floatFormat(channels: 1, interleaved: false))
        let input = sine(frequency: 1_000)
        XCTAssertEqual(process(tap, channels: [input])[0], input)

        tap.update(settings: settings(gainDB: -12, atBand: 5))
        let output = process(tap, channels: [input])[0]
        XCTAssertLessThan(rms(output, skip: 1_024), rms(input) * 0.4)
    }

    // MARK: - Köməkçilər

    private func settings(gainDB: Float, atBand band: Int) -> EqualizerSettings {
        var settings = EqualizerSettings.flat
        settings.isEnabled = true
        settings.setGain(gainDB, at: band)
        return settings
    }

    private func sine(frequency: Double, amplitude: Float = 0.25) -> [Float] {
        (0..<frameCount).map { index in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate))
        }
    }

    private func rms(_ samples: [Float], skip: Int = 0) -> Float {
        let slice = samples.dropFirst(skip)
        let sum = slice.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sum / Float(max(slice.count, 1)))
    }

    private func floatFormat(channels: UInt32, interleaved: Bool) -> AudioStreamBasicDescription {
        var flags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        if !interleaved { flags |= kAudioFormatFlagIsNonInterleaved }
        let bytesPerFrame = UInt32(MemoryLayout<Float>.size) * (interleaved ? channels : 1)
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    /// Non-interleaved: hər kanal öz buferində.
    private func run(_ tap: AudioEqualizerTap, channels: [[Float]]) -> [[Float]] {
        tap.prepare(maxFrames: frameCount, format: floatFormat(channels: UInt32(channels.count), interleaved: false))
        defer { tap.unprepare() }
        return process(tap, channels: channels)
    }

    private func process(_ tap: AudioEqualizerTap, channels: [[Float]]) -> [[Float]] {
        var bufferList = AudioBufferList.allocate(maximumBuffers: channels.count)
        defer { free(bufferList.unsafeMutablePointer) }

        let storage = channels.map { channel -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: channel.count)
            pointer.initialize(from: channel, count: channel.count)
            return pointer
        }
        defer { storage.forEach { $0.deallocate() } }

        for (index, pointer) in storage.enumerated() {
            bufferList[index] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(channels[index].count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(pointer)
            )
        }

        tap.process(bufferList.unsafeMutablePointer, frameCount: frameCount)
        return storage.enumerated().map { index, pointer in
            Array(UnsafeBufferPointer(start: pointer, count: channels[index].count))
        }
    }

    /// Interleaved stereo: bir buferdə L R L R …
    private func runInterleaved(_ tap: AudioEqualizerTap, left: [Float], right: [Float]) -> (left: [Float], right: [Float]) {
        tap.prepare(maxFrames: frameCount, format: floatFormat(channels: 2, interleaved: true))
        defer { tap.unprepare() }

        var samples = [Float](repeating: 0, count: frameCount * 2)
        for frame in 0..<frameCount {
            samples[frame * 2] = left[frame]
            samples[frame * 2 + 1] = right[frame]
        }

        var bufferList = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(bufferList.unsafeMutablePointer) }

        samples.withUnsafeMutableBufferPointer { buffer in
            bufferList[0] = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(buffer.baseAddress)
            )
            tap.process(bufferList.unsafeMutablePointer, frameCount: frameCount)
        }

        var outLeft: [Float] = []
        var outRight: [Float] = []
        for frame in 0..<frameCount {
            outLeft.append(samples[frame * 2])
            outRight.append(samples[frame * 2 + 1])
        }
        return (outLeft, outRight)
    }
}

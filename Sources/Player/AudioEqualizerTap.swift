import Accelerate
import AVFoundation
import MediaToolbox
import os

/// AVPlayer üçün ekvalayzer.
///
/// `AVPlayer` `AVAudioEngine` qovşaqlarını qəbul etmir, ona görə səs
/// `MTAudioProcessingTap` ilə dekoderdən sonra tutulur və vDSP biquad
/// filtrlərindən keçirilir. Bu yol aparat dekoderini, PiP-i və AirPlay-i saxlayır.
///
/// Tap callback-ləri real-time audio axınında işləyir. Orada yaddaş ayrılmır və
/// kilid gözlənilmir: parametrlər əsas axında hazırlanır, emal tərəfi isə kilidi
/// yalnız `trylock` ilə götürür — tutulubsa həmin bufer dəyişmədən keçir.
final class AudioEqualizerTap: @unchecked Sendable {

    /// Oktava aralıqlı zolaqlar üçün uyğun genişlik.
    private static let bandQ: Double = 1.41
    private static let maxChannels = 8

    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
        return pointer
    }()

    // Aşağıdakılar yalnız kilid altında dəyişir.
    private var settings: EqualizerSettings
    private var sampleRate: Double = 0
    private var channelCount = 0
    private var isSupportedFormat = false
    private var setup: vDSP_biquad_Setup?
    private var sectionCount = 0
    /// Hər kanal üçün `2 * sectionCount + 2` element — vDSP-nin filtr yaddaşı.
    private var delay: UnsafeMutablePointer<Float>?
    private var scratch: UnsafeMutablePointer<Float>?
    private var scratchCapacity = 0

    init(settings: EqualizerSettings) {
        self.settings = settings
    }

    deinit {
        if let setup { vDSP_biquad_DestroySetup(setup) }
        delay?.deallocate()
        scratch?.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Əsas axından çağırılır. Filtrlər dərhal yenidən qurulur.
    func update(settings newSettings: EqualizerSettings) {
        os_unfair_lock_lock(lock)
        settings = newSettings
        rebuildFilters()
        os_unfair_lock_unlock(lock)
    }

    /// Player item-ə qoşulacaq audio mix. Tap yaradıla bilməsə `nil`.
    func makeAudioMix(for track: AVAssetTrack) -> AVAudioMix? {
        let clientInfo = Unmanaged.passRetained(self).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                // `makeAudioMix`-dəki passRetained burada balanslaşır.
                Unmanaged<AudioEqualizerTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                let processor = Unmanaged<AudioEqualizerTap>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                processor.prepare(maxFrames: Int(maxFrames), format: format.pointee)
            },
            unprepare: { tap in
                let processor = Unmanaged<AudioEqualizerTap>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                processor.unprepare()
            },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                // Bufer göstəriciləri NULL gəlir; sistem öz buferlərini verir və
                // onları yerində dəyişmək sənədlərdə icazəlidir.
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
                )
                guard status == noErr else { return }
                let processor = Unmanaged<AudioEqualizerTap>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                let isDiscontinuity = flagsOut.pointee & kMTAudioProcessingTapFlag_StartOfStream != 0
                processor.process(
                    bufferListInOut,
                    frameCount: Int(numberFramesOut.pointee),
                    isDiscontinuity: isDiscontinuity
                )
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else {
            Unmanaged<AudioEqualizerTap>.fromOpaque(clientInfo).release()
            return nil
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    // MARK: - Tap həyat dövrü
    //
    // Bu üç metod `private` deyil ki, unit testlər onları tap olmadan, hazır
    // buferlə çağıra bilsin. App kodu onları birbaşa çağırmır.

    func prepare(maxFrames: Int, format: AudioStreamBasicDescription) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        // AVPlayer adətən 32-bit float PCM verir. Başqa format gəlsə toxunmuruq.
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        isSupportedFormat = format.mFormatID == kAudioFormatLinearPCM
            && isFloat
            && format.mBitsPerChannel == 32
            && format.mChannelsPerFrame > 0
            && Int(format.mChannelsPerFrame) <= Self.maxChannels

        sampleRate = format.mSampleRate
        channelCount = Int(format.mChannelsPerFrame)

        scratch?.deallocate()
        scratchCapacity = max(maxFrames, 0)
        scratch = scratchCapacity > 0 ? .allocate(capacity: scratchCapacity) : nil

        rebuildFilters()
    }

    func unprepare() {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        destroyFilters()
        scratch?.deallocate()
        scratch = nil
        scratchCapacity = 0
        isSupportedFormat = false
    }

    /// Real-time axın. Yaddaş ayırmır, kilidi gözləmir.
    /// `isDiscontinuity` — seek və ya axının yenidən başlaması: köhnə filtr
    /// yaddaşı yeni səsə «quyruq» kimi qarışmasın deyə sıfırlanır.
    func process(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int,
        isDiscontinuity: Bool = false
    ) {
        guard os_unfair_lock_trylock(lock) else { return }
        defer { os_unfair_lock_unlock(lock) }

        guard isSupportedFormat, let setup, let delay, let scratch,
              frameCount > 0, frameCount <= scratchCapacity
        else { return }

        let delayStride = 2 * sectionCount + 2
        if isDiscontinuity {
            delay.update(repeating: 0, count: channelCount * delayStride)
        }
        var channelIndex = 0

        for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            guard let raw = buffer.mData else { continue }
            let samples = raw.assumingMemoryBound(to: Float.self)
            // Interleaved buferdə bir neçə kanal yan-yana durur, ona görə addım
            // kanal sayına bərabərdir; non-interleaved buferdə addım 1-dir.
            let interleave = max(Int(buffer.mNumberChannels), 1)
            guard Int(buffer.mDataByteSize) >= frameCount * interleave * MemoryLayout<Float>.size else { continue }

            for offset in 0..<interleave {
                guard channelIndex < channelCount else { return }
                vDSP_biquad(
                    setup,
                    delay + channelIndex * delayStride,
                    samples + offset,
                    vDSP_Stride(interleave),
                    scratch,
                    1,
                    vDSP_Length(frameCount)
                )
                for frame in 0..<frameCount {
                    samples[offset + frame * interleave] = scratch[frame]
                }
                channelIndex += 1
            }
        }
    }

    // MARK: - Filtrlər (kilid altında çağırılır)

    private func rebuildFilters() {
        destroyFilters()
        guard isSupportedFormat, sampleRate > 0, channelCount > 0, !settings.isEffectivelyFlat else { return }

        let nyquist = sampleRate / 2
        var coefficients: [Double] = []
        var sections = 0

        // Gücləndirmə zamanı kəsilmə olmasın deyə ümumi səviyyə bir az endirilir.
        let maxBoost = Double(settings.gains.max() ?? 0)
        let preGain = maxBoost > 0 ? pow(10, -maxBoost / 2 / 20) : 1

        for (index, frequency) in EqualizerSettings.frequencies.enumerated() {
            let gain = Double(settings.gains.indices.contains(index) ? settings.gains[index] : 0)
            guard abs(gain) >= 0.05, Double(frequency) < nyquist * 0.9 else { continue }
            var section = Self.peakingCoefficients(
                frequency: Double(frequency),
                gainDB: gain,
                q: Self.bandQ,
                sampleRate: sampleRate
            )
            if sections == 0 {
                section[0] *= preGain
                section[1] *= preGain
                section[2] *= preGain
            }
            coefficients.append(contentsOf: section)
            sections += 1
        }

        guard sections > 0,
              let newSetup = coefficients.withUnsafeBufferPointer({ buffer in
                  buffer.baseAddress.flatMap { vDSP_biquad_CreateSetup($0, vDSP_Length(sections)) }
              })
        else { return }

        let delayCount = channelCount * (2 * sections + 2)
        let newDelay = UnsafeMutablePointer<Float>.allocate(capacity: delayCount)
        newDelay.initialize(repeating: 0, count: delayCount)

        setup = newSetup
        delay = newDelay
        sectionCount = sections
    }

    private func destroyFilters() {
        if let setup { vDSP_biquad_DestroySetup(setup) }
        setup = nil
        delay?.deallocate()
        delay = nil
        sectionCount = 0
    }

    /// RBJ «Audio EQ Cookbook» peaking filtri. vDSP sırası: b0, b1, b2, a1, a2 (a0-a bölünmüş).
    private static func peakingCoefficients(
        frequency: Double,
        gainDB: Double,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let amplitude = pow(10, gainDB / 40)
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosOmega = cos(omega)

        let b0 = 1 + alpha * amplitude
        let b1 = -2 * cosOmega
        let b2 = 1 - alpha * amplitude
        let a0 = 1 + alpha / amplitude
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha / amplitude

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }
}

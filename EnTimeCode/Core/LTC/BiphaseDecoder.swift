import Foundation

/// Decodes a biphase-mark (FM) bit stream from PCM samples.
///
/// Each emitted bit reports the absolute sample index at which the bit period began, so the
/// caller can align decoded LTC frames to the audio/video timeline. Feed samples sequentially
/// across blocks; internal state (DC offset, envelope, bit-clock) is retained.
final class BiphaseDecoder {
    /// Adaptive full-bit period, in samples.
    private var bitPeriod: Double
    private let minBitPeriod: Double
    private let maxBitPeriod: Double

    private var dcEstimate: Double = 0
    private var envelope: Double = 0
    private var isHigh = false
    private var primed = false

    private var globalSampleIndex = 0
    private var lastTransitionSample = 0
    private var haveLastTransition = false

    private var halfPending = false
    private var halfStartSample = 0

    /// - Parameter seedBitPeriod: expected full-bit period in samples (sampleRate / (80 * fps)).
    init(seedBitPeriod: Double) {
        self.bitPeriod = seedBitPeriod
        self.minBitPeriod = seedBitPeriod * 0.5
        self.maxBitPeriod = seedBitPeriod * 2.0
    }

    /// Process a block of samples, invoking `onBit` for each recovered bit.
    func process(_ samples: [Float], onBit: (_ bit: UInt8, _ startSample: Int) -> Void) {
        for raw in samples {
            let x = Double(raw)
            // Slow DC tracking and envelope follower.
            dcEstimate += (x - dcEstimate) * 0.0002
            let centered = x - dcEstimate
            let mag = abs(centered)
            envelope = max(envelope * 0.9997, mag)

            let hysteresis = max(envelope * 0.10, 1e-5)
            let sampleIndex = globalSampleIndex
            globalSampleIndex += 1

            if !primed {
                isHigh = centered >= 0
                primed = true
                continue
            }

            var transition = false
            if isHigh, centered < -hysteresis {
                isHigh = false
                transition = true
            } else if !isHigh, centered > hysteresis {
                isHigh = true
                transition = true
            }
            guard transition else { continue }

            guard haveLastTransition else {
                lastTransitionSample = sampleIndex
                haveLastTransition = true
                continue
            }

            let interval = Double(sampleIndex - lastTransitionSample)
            lastTransitionSample = sampleIndex

            let fullThreshold = bitPeriod * 0.75
            if interval >= fullThreshold {
                // Full-period transition => logical 0.
                if halfPending {
                    // A dangling half before a full period is a glitch; discard it.
                    halfPending = false
                }
                let start = sampleIndex - Int(interval.rounded())
                onBit(0, start)
                adaptBitPeriod(toFull: interval)
            } else {
                // Half-period transition; logical 1 is two consecutive halves.
                if halfPending {
                    halfPending = false
                    onBit(1, halfStartSample)
                    adaptBitPeriod(toFull: Double(sampleIndex - halfStartSample))
                } else {
                    halfPending = true
                    halfStartSample = sampleIndex - Int(interval.rounded())
                }
            }
        }
    }

    private func adaptBitPeriod(toFull full: Double) {
        guard full.isFinite, full > 0 else { return }
        let clamped = min(max(full, minBitPeriod), maxBitPeriod)
        bitPeriod += (clamped - bitPeriod) * 0.05
    }
}

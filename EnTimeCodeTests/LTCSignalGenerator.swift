import Foundation
@testable import EnTimeCode

/// Synthesizes a biphase-mark LTC audio signal for tests. Requires an integer number of samples
/// per bit (sampleRate must be divisible by 80 * fps), e.g. 48000 Hz at 25 or 30 fps.
enum LTCSignalGenerator {
    static func setField(_ bits: inout [UInt8], _ range: Range<Int>, _ value: Int) {
        for (offset, index) in range.enumerated() {
            bits[index] = UInt8((value >> offset) & 1)
        }
    }

    /// Build the 80 bits (64 data + 16 sync) for one frame at the given timecode.
    static func frameBits(hours: Int, minutes: Int, seconds: Int, frames: Int, dropFrame: Bool) -> [UInt8] {
        var bits = [UInt8](repeating: 0, count: 80)
        setField(&bits, 0..<4, frames % 10)
        setField(&bits, 8..<10, frames / 10)
        bits[10] = dropFrame ? 1 : 0
        setField(&bits, 16..<20, seconds % 10)
        setField(&bits, 24..<27, seconds / 10)
        setField(&bits, 32..<36, minutes % 10)
        setField(&bits, 40..<43, minutes / 10)
        setField(&bits, 48..<52, hours % 10)
        setField(&bits, 56..<58, hours / 10)
        for i in 0..<16 { bits[64 + i] = LTCDecoder.syncPattern[i] }
        return bits
    }

    /// Render `frameCount` consecutive LTC frames starting at `start`, returning mono Float samples.
    static func render(start: Timecode,
                       frameCount: Int,
                       sampleRate: Int = 48000,
                       fps: Int = 30,
                       amplitude: Float = 0.8) -> [Float] {
        precondition(sampleRate % (80 * fps) == 0, "sampleRate must divide evenly")
        let samplesPerBit = sampleRate / (80 * fps)
        let half = samplesPerBit / 2

        var out: [Float] = []
        out.reserveCapacity(frameCount * 80 * samplesPerBit)
        var level: Float = amplitude

        var frameNumber = start.frameNumber
        for _ in 0..<frameCount {
            let tc = Timecode(frameNumber: frameNumber, rate: start.rate)
            let bits = frameBits(hours: tc.hours, minutes: tc.minutes, seconds: tc.seconds,
                                 frames: tc.frames, dropFrame: start.rate.isDropFrame)
            for bit in bits {
                level = -level // transition at every bit boundary
                for _ in 0..<half { out.append(level) }
                if bit == 1 { level = -level } // mid-bit transition for a '1'
                for _ in half..<samplesPerBit { out.append(level) }
            }
            frameNumber += 1
        }
        return out
    }
}

import Foundation

struct DecodedLTCFrame: Equatable, Sendable {
    let frame: LTCFrame
    /// Absolute audio sample index where this LTC frame's bit 0 begins.
    let startSample: Int
}

/// Assembles biphase-decoded bits into LTC frames by locating the 16-bit sync word.
final class LTCDecoder {
    /// LTC sync word (bits 64...79) in transmission order: 0011 1111 1111 1101.
    static let syncPattern: [UInt8] = [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,1]

    private let biphase: BiphaseDecoder
    private let sampleRate: Double
    private let maxFrames: Int

    private var bits: [UInt8] = []
    private var starts: [Int] = []
    private(set) var frames: [DecodedLTCFrame] = []
    private(set) var stopped = false

    /// - Parameters:
    ///   - sampleRate: audio sample rate.
    ///   - seedFPS: nominal frame rate used to seed the bit clock (e.g. video's nominal rate).
    ///   - maxFrames: stop after this many frames (0 = unlimited). Used by channel detection.
    init(sampleRate: Double, seedFPS: Double, maxFrames: Int = 0) {
        self.sampleRate = sampleRate
        self.maxFrames = maxFrames
        let seedBitPeriod = sampleRate / (80.0 * max(1.0, seedFPS))
        self.biphase = BiphaseDecoder(seedBitPeriod: seedBitPeriod)
    }

    func process(channel samples: [Float]) {
        guard !stopped else { return }
        biphase.process(samples) { [self] bit, startSample in
            guard !stopped else { return }
            bits.append(bit)
            starts.append(startSample)
            // Bound memory.
            if bits.count > 4096 {
                let drop = bits.count - 2048
                bits.removeFirst(drop)
                starts.removeFirst(drop)
            }
            checkForFrame()
        }
    }

    private func checkForFrame() {
        let n = bits.count
        guard n >= 80 else { return }
        // Compare the last 16 bits against the sync pattern.
        let syncStart = n - 16
        for i in 0..<16 where bits[syncStart + i] != Self.syncPattern[i] {
            return
        }
        let dataStart = n - 80
        let dataBits = bits[dataStart..<(n - 16)]
        guard let frame = LTCFrame(dataBits: dataBits), frame.isPlausible else { return }
        frames.append(DecodedLTCFrame(frame: frame, startSample: starts[dataStart]))
        if maxFrames > 0, frames.count >= maxFrames {
            stopped = true
        }
    }

    /// Estimate the nominal frame rate from the average spacing between decoded frames.
    func estimatedFPS() -> Double? {
        guard frames.count >= 2 else { return nil }
        let first = frames.first!.startSample
        let last = frames.last!.startSample
        let span = Double(last - first)
        guard span > 0 else { return nil }
        return Double(frames.count - 1) * sampleRate / span
    }

    /// The drop-frame flag, taken as the majority across decoded frames.
    func majorityDropFrame() -> Bool {
        let dropCount = frames.reduce(0) { $0 + ($1.frame.dropFrame ? 1 : 0) }
        return dropCount * 2 > frames.count
    }
}

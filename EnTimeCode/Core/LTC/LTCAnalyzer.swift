import Foundation
import AVFoundation

struct LTCAnalysis: Sendable {
    let channelIndex: Int
    let rate: FrameRate
    /// Timecode at audio sample 0 (i.e. the start of the file / video).
    let startTimecode: Timecode
    let decodedFrameCount: Int
}

enum LTCAnalyzerError: Error, LocalizedError {
    case noLTCFound
    case audio(AudioReaderError)

    var errorDescription: String? {
        switch self {
        case .noLTCFound: return "No LTC timecode could be decoded from the audio."
        case .audio(let e): return "Audio read error: \(e)"
        }
    }
}

/// Decodes LTC from a file: auto-detects the LTC channel (or honors an override), decodes the
/// stream, and computes the start timecode aligned to the start of the file.
struct LTCAnalyzer {
    private struct StopReading: Error {}

    let url: URL
    /// Nominal frame rate of the video track, used to seed the bit clock and resolve the rate.
    let videoNominalFPS: Double?

    func analyze(channel selection: LTCChannelSelection) async throws -> LTCAnalysis {
        let reader = AudioChannelReader(url: url)
        let format = try await reader.format()
        let seedFPS = videoNominalFPS ?? 30.0
        let channelCount = max(1, format.channelCount)

        let chosenChannel: Int
        if channelCount == 1 {
            chosenChannel = 0
        } else {
            switch selection {
            case .left: chosenChannel = 0
            case .right: chosenChannel = min(1, channelCount - 1)
            case .auto: chosenChannel = try await detectChannel(reader: reader,
                                                                 sampleRate: format.sampleRate,
                                                                 seedFPS: seedFPS,
                                                                 channelCount: channelCount)
            }
        }

        let decoder = LTCDecoder(sampleRate: format.sampleRate, seedFPS: seedFPS)
        try await reader.read { block in
            if chosenChannel < block.samples.count {
                decoder.process(channel: block.samples[chosenChannel])
            }
        }

        guard let firstFrame = decoder.frames.first else {
            throw LTCAnalyzerError.noLTCFound
        }

        let dropFrame = decoder.majorityDropFrame()
        let fps = videoNominalFPS ?? decoder.estimatedFPS() ?? 30.0
        let rate = FrameRate.from(nominalFPS: fps, dropFrame: dropFrame)

        let startTimecode = startTimecode(firstFrame: firstFrame,
                                          rate: rate,
                                          sampleRate: format.sampleRate)

        return LTCAnalysis(channelIndex: chosenChannel,
                           rate: rate,
                           startTimecode: startTimecode,
                           decodedFrameCount: decoder.frames.count)
    }

    /// Extrapolate the timecode back to audio sample 0 from the first decoded frame.
    private func startTimecode(firstFrame: DecodedLTCFrame, rate: FrameRate, sampleRate: Double) -> Timecode {
        let samplesPerFrame = sampleRate / rate.nominalFPS
        let firstTC = Timecode(hours: firstFrame.frame.hours,
                               minutes: firstFrame.frame.minutes,
                               seconds: firstFrame.frame.seconds,
                               frames: firstFrame.frame.frames,
                               rate: rate)
        let frameOffset = Int((Double(firstFrame.startSample) / samplesPerFrame).rounded())
        let startFrameNumber = firstTC.frameNumber - frameOffset
        return Timecode(frameNumber: max(0, startFrameNumber), rate: rate)
    }

    /// Decode a short window on each candidate channel and pick the one yielding the most frames.
    private func detectChannel(reader: AudioChannelReader,
                               sampleRate: Double,
                               seedFPS: Double,
                               channelCount: Int) async throws -> Int {
        let candidates = min(channelCount, 2)
        let decoders = (0..<candidates).map { _ in
            LTCDecoder(sampleRate: sampleRate, seedFPS: seedFPS)
        }
        // Analyze roughly the first 6 seconds.
        let windowSamples = Int(sampleRate * 6.0)
        var consumed = 0

        do {
            try await reader.read { block in
                for ch in 0..<candidates where ch < block.samples.count {
                    decoders[ch].process(channel: block.samples[ch])
                }
                consumed += block.samples.first?.count ?? 0
                if consumed >= windowSamples { throw StopReading() }
            }
        } catch is StopReading {
            // expected early stop
        }

        let counts = decoders.map { $0.frames.count }
        let best = counts.enumerated().max { $0.element < $1.element }
        if let best, best.element > 0 {
            return best.offset
        }
        // Fall back to channel 0 if nothing decoded; caller surfaces no-LTC later.
        return 0
    }
}

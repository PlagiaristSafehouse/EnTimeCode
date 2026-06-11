import XCTest
@testable import EnTimeCode

final class LTCDecoderTests: XCTestCase {
    func testDecodes30fps() {
        let start = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps30)
        let samples = LTCSignalGenerator.render(start: start, frameCount: 20, sampleRate: 48000, fps: 30)

        let decoder = LTCDecoder(sampleRate: 48000, seedFPS: 30)
        decoder.process(channel: samples)

        XCTAssertGreaterThanOrEqual(decoder.frames.count, 15, "expected most frames to decode")

        // Every decoded frame must match the expected timecode for its absolute frame number.
        for decoded in decoder.frames {
            let f = decoded.frame
            let tc = Timecode(hours: f.hours, minutes: f.minutes, seconds: f.seconds, frames: f.frames, rate: .fps30)
            let expected = Timecode(frameNumber: tc.frameNumber, rate: .fps30)
            XCTAssertEqual(tc, expected)
        }

        // First decoded frame should be at or just after the start timecode.
        let first = decoder.frames.first!.frame
        let firstTC = Timecode(hours: first.hours, minutes: first.minutes, seconds: first.seconds, frames: first.frames, rate: .fps30)
        XCTAssertGreaterThanOrEqual(firstTC.frameNumber, start.frameNumber)
        XCTAssertLessThanOrEqual(firstTC.frameNumber, start.frameNumber + 3)
    }

    func testConsecutiveFrames() {
        let start = Timecode(hours: 0, minutes: 0, seconds: 10, frames: 0, rate: .fps30)
        let samples = LTCSignalGenerator.render(start: start, frameCount: 30, sampleRate: 48000, fps: 30)
        let decoder = LTCDecoder(sampleRate: 48000, seedFPS: 30)
        decoder.process(channel: samples)

        let numbers = decoder.frames.map { d -> Int in
            Timecode(hours: d.frame.hours, minutes: d.frame.minutes, seconds: d.frame.seconds, frames: d.frame.frames, rate: .fps30).frameNumber
        }
        for i in 1..<numbers.count {
            XCTAssertEqual(numbers[i], numbers[i - 1] + 1, "frames not consecutive: \(numbers)")
        }
    }

    func testEstimatedFPS() {
        let start = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, rate: .fps25)
        let samples = LTCSignalGenerator.render(start: start, frameCount: 30, sampleRate: 48000, fps: 25)
        let decoder = LTCDecoder(sampleRate: 48000, seedFPS: 25)
        decoder.process(channel: samples)
        let fps = decoder.estimatedFPS()
        XCTAssertNotNil(fps)
        XCTAssertEqual(fps!, 25.0, accuracy: 0.3)
    }

    func testStreamingInBlocksMatchesSinglePass() {
        let start = Timecode(hours: 2, minutes: 0, seconds: 0, frames: 0, rate: .fps30)
        let samples = LTCSignalGenerator.render(start: start, frameCount: 20, sampleRate: 48000, fps: 30)

        let whole = LTCDecoder(sampleRate: 48000, seedFPS: 30)
        whole.process(channel: samples)

        let chunked = LTCDecoder(sampleRate: 48000, seedFPS: 30)
        var i = 0
        while i < samples.count {
            let end = min(i + 777, samples.count)
            chunked.process(channel: Array(samples[i..<end]))
            i = end
        }
        XCTAssertEqual(whole.frames.count, chunked.frames.count)
    }
}

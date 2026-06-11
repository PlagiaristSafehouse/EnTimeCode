import XCTest
import AVFoundation
@testable import EnTimeCode

final class PipelineIntegrationTests: XCTestCase {
    func testEndToEndEmbedsTimecodeTrack() async throws {
        let start = Timecode(hours: 1, minutes: 0, seconds: 5, frames: 10, rate: .fps30)
        let sourceURL = try await TestMediaFactory.makeStereoLTCMovie(start: start, fps: 30, seconds: 2)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // Analyze: should detect LTC on channel 0 and recover the start timecode.
        let analyzer = LTCAnalyzer(url: sourceURL, videoNominalFPS: 30)
        let analysis = try await analyzer.analyze(channel: .auto)
        XCTAssertEqual(analysis.channelIndex, 0, "LTC should be auto-detected on channel 0")
        XCTAssertEqual(analysis.rate, .fps30)
        XCTAssertEqual(analysis.startTimecode.frameNumber, start.frameNumber,
                       "recovered start \(analysis.startTimecode.displayString) != \(start.displayString)")

        // Write the output with embedded timecode.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("out-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let writer = TimecodeConversionWriter(sourceURL: sourceURL,
                                              outputURL: outputURL,
                                              startTimecode: analysis.startTimecode,
                                              rate: analysis.rate,
                                              ltcChannel: analysis.channelIndex)
        try await writer.run()

        // Verify output structure.
        let outAsset = AVURLAsset(url: outputURL)
        let videoTracks = try await outAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await outAsset.loadTracks(withMediaType: .audio)
        let timecodeTracks = try await outAsset.loadTracks(withMediaType: .timecode)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertEqual(timecodeTracks.count, 1, "output should contain a tmcd timecode track")

        // Scratch audio should be mono.
        if let audioFormat = try await audioTracks.first?.load(.formatDescriptions).first {
            let channels = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat)?.pointee.mChannelsPerFrame
            XCTAssertEqual(channels, 1, "scratch audio should be downmixed to mono")
        }

        // The stored timecode frame number must equal the decoded start.
        let stored = try await TestMediaFactory.readTimecodeFrameNumber(url: outputURL)
        XCTAssertEqual(stored, start.frameNumber, "embedded tmcd start frame mismatch")
    }
}

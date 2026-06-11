import XCTest
import AVFoundation
@testable import EnTimeCode

/// Runs the real conversion pipeline against an actual on-disk sample file, if present.
/// The iOS Simulator can read host filesystem paths, so this exercises the exact iOS code path
/// (24-bit BE PCM audio, H.264 passthrough, existing tmcd track) that the synthesized fixtures
/// don't cover. Skipped automatically when the sample file is absent (e.g. CI).
final class RealFileConversionTests: XCTestCase {
    private let samplePath = "/Users/kmwallio/Projects/EnTimeCode/P1010703.MOV"

    func testConvertRealSampleFile() async throws {
        guard FileManager.default.fileExists(atPath: samplePath) else {
            throw XCTSkip("Sample file not present; skipping real-file conversion test.")
        }
        let url = URL(fileURLWithPath: samplePath)

        let fps = try await ConversionService.nominalFPS(forVideoAt: url)
        let analyzer = LTCAnalyzer(url: url, videoNominalFPS: fps)
        let analysis = try await analyzer.analyze(channel: .auto)
        XCTAssertGreaterThan(analysis.decodedFrameCount, 0)
        print("REALFILE analyze: ch\(analysis.channelIndex) \(analysis.rate.displayName) start \(analysis.startTimecode.displayString)")

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("realfile-out-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: out) }

        let writer = TimecodeConversionWriter(sourceURL: url, outputURL: out,
                                              startTimecode: analysis.startTimecode,
                                              rate: analysis.rate, ltcChannel: analysis.channelIndex)
        try await writer.run(progress: { _ in })

        let outAsset = AVURLAsset(url: out)
        let timecodeTracks = try await outAsset.loadTracks(withMediaType: .timecode)
        XCTAssertEqual(timecodeTracks.count, 1, "output should contain a tmcd timecode track")
        let stored = try await TestMediaFactory.readTimecodeFrameNumber(url: out)
        XCTAssertEqual(stored, analysis.startTimecode.frameNumber)
    }
}

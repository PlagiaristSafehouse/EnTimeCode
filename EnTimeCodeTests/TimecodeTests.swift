import XCTest
@testable import EnTimeCode

final class TimecodeTests: XCTestCase {
    func testNonDropRoundTrip() {
        let rate = FrameRate.fps30
        for n in stride(from: 0, to: 30 * 60 * 60, by: 137) {
            let tc = Timecode(frameNumber: n, rate: rate)
            XCTAssertEqual(tc.frameNumber, n, "round-trip failed at \(n) -> \(tc.displayString)")
            XCTAssertTrue(tc.isValid)
        }
    }

    func test25RoundTrip() {
        let rate = FrameRate.fps25
        for n in stride(from: 0, to: 25 * 60 * 10, by: 7) {
            let tc = Timecode(frameNumber: n, rate: rate)
            XCTAssertEqual(tc.frameNumber, n)
        }
    }

    func testDropFrameRoundTrip() {
        let rate = FrameRate.fps29_97_drop
        for n in stride(from: 0, to: 30 * 60 * 60, by: 101) {
            let tc = Timecode(frameNumber: n, rate: rate)
            XCTAssertEqual(tc.frameNumber, n, "DF round-trip failed at \(n) -> \(tc.displayString)")
        }
    }

    func testDropFrameSkipsFrames() {
        // At one minute (non-tenth), frames 00 and 01 are skipped: ...59:29 -> 01:00;02.
        let rate = FrameRate.fps29_97_drop
        let beforeMinute = Timecode(hours: 0, minutes: 0, seconds: 59, frames: 29, rate: rate)
        let afterMinute = Timecode(frameNumber: beforeMinute.frameNumber + 1, rate: rate)
        XCTAssertEqual(afterMinute.minutes, 1)
        XCTAssertEqual(afterMinute.seconds, 0)
        XCTAssertEqual(afterMinute.frames, 2)
    }

    func testTenthMinuteNoSkip() {
        // At the tenth minute, no frames are dropped: 09:59;29 -> 10:00;00.
        let rate = FrameRate.fps29_97_drop
        let before = Timecode(hours: 0, minutes: 9, seconds: 59, frames: 29, rate: rate)
        let after = Timecode(frameNumber: before.frameNumber + 1, rate: rate)
        XCTAssertEqual(after.minutes, 10)
        XCTAssertEqual(after.seconds, 0)
        XCTAssertEqual(after.frames, 0)
    }
}

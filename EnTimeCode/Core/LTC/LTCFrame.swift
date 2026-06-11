import Foundation

/// Decoded payload of one 80-bit LTC frame (data bits 0...63; the 16-bit sync is excluded).
struct LTCFrame: Equatable, Sendable {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var frames: Int
    var dropFrame: Bool
    var colorFrame: Bool

    /// Decode from the 64 data bits (index 0 == bit 0 == LSB-first as transmitted).
    init?(dataBits bits: ArraySlice<UInt8>) {
        guard bits.count >= 64 else { return nil }
        let b = Array(bits)

        func field(_ range: Range<Int>) -> Int {
            var value = 0
            for (offset, index) in range.enumerated() where b[index] != 0 {
                value |= (1 << offset)
            }
            return value
        }

        let frameUnits = field(0..<4)
        let frameTens = field(8..<10)
        let secUnits = field(16..<20)
        let secTens = field(24..<27)
        let minUnits = field(32..<36)
        let minTens = field(40..<43)
        let hourUnits = field(48..<52)
        let hourTens = field(56..<58)

        self.dropFrame = b[10] != 0
        self.colorFrame = b[11] != 0
        self.frames = frameTens * 10 + frameUnits
        self.seconds = secTens * 10 + secUnits
        self.minutes = minTens * 10 + minUnits
        self.hours = hourTens * 10 + hourUnits
    }

    /// Sanity bounds (frame field validated by the caller against the resolved rate).
    var isPlausible: Bool {
        hours >= 0 && hours < 24 &&
        minutes >= 0 && minutes < 60 &&
        seconds >= 0 && seconds < 60 &&
        frames >= 0 && frames < 30
    }
}

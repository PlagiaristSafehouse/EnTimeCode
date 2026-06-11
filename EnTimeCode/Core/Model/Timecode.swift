import Foundation

/// An SMPTE timecode value (HH:MM:SS:FF) tied to a frame rate.
struct Timecode: Equatable, Hashable, Sendable {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var frames: Int
    var rate: FrameRate

    init(hours: Int, minutes: Int, seconds: Int, frames: Int, rate: FrameRate) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.rate = rate
    }

    /// Total frame count from 00:00:00:00, accounting for drop-frame dropping.
    var frameNumber: Int {
        let base = rate.countingBase
        if rate.isDropFrame {
            // 29.97 DF: drop frames 0 and 1 at the start of every minute except every 10th.
            let totalMinutes = hours * 60 + minutes
            let droppedPerMinute = 2
            let dropped = droppedPerMinute * (totalMinutes - totalMinutes / 10)
            let straight = ((hours * 60 + minutes) * 60 + seconds) * base + frames
            return straight - dropped
        } else {
            return ((hours * 60 + minutes) * 60 + seconds) * base + frames
        }
    }

    /// Reconstruct a timecode from an absolute frame number at the given rate.
    init(frameNumber: Int, rate: FrameRate) {
        self.rate = rate
        let base = rate.countingBase
        var n = max(0, frameNumber)

        if rate.isDropFrame {
            // Inverse of drop-frame dropping for 29.97 DF (base 30, drop 2/min except every 10th).
            let framesPer10Min = 17982          // 10 minutes of 29.97 DF frames
            let framesPerMin = 1798             // frames in a non-tenth minute
            let tenMinChunks = n / framesPer10Min
            var rem = n % framesPer10Min
            // Add back the dropped frames.
            n += 18 * tenMinChunks
            if rem >= 2 {
                n += 2 * ((rem - 2) / framesPerMin)
            }
            _ = rem
        }

        let f = n % base
        let totalSeconds = n / base
        let s = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let m = totalMinutes % 60
        let h = (totalMinutes / 60) % 24
        self.hours = h
        self.minutes = m
        self.seconds = s
        self.frames = f
    }

    var isValid: Bool {
        hours >= 0 && hours < 24 &&
        minutes >= 0 && minutes < 60 &&
        seconds >= 0 && seconds < 60 &&
        frames >= 0 && frames < rate.countingBase
    }

    var displayString: String {
        let sep = rate.isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, sep, frames)
    }
}

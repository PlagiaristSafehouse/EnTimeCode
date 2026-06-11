import Foundation
import CoreMedia

/// SMPTE frame rates relevant to LTC.
///
/// `nominalFPS` is the real-world frame rate (e.g. 29.97). `countingBase` is the integer
/// number of frame values the timecode counter cycles through each second of *timecode*
/// (24, 25, or 30). Drop-frame is only valid for 29.97 / 59.94 family rates.
enum FrameRate: Equatable, Hashable, CaseIterable, Sendable {
    case fps23_976
    case fps24
    case fps25
    case fps29_97_nonDrop
    case fps29_97_drop
    case fps30

    /// Integer counter base used for the `:FF` field (frames roll over at this value).
    var countingBase: Int {
        switch self {
        case .fps23_976, .fps24: return 24
        case .fps25: return 25
        case .fps29_97_nonDrop, .fps29_97_drop, .fps30: return 30
        }
    }

    /// True real-world frames per second.
    var nominalFPS: Double {
        switch self {
        case .fps23_976: return 24.0 * 1000.0 / 1001.0
        case .fps24: return 24.0
        case .fps25: return 25.0
        case .fps29_97_nonDrop, .fps29_97_drop: return 30.0 * 1000.0 / 1001.0
        case .fps30: return 30.0
        }
    }

    var isDropFrame: Bool { self == .fps29_97_drop }

    /// Frame quanta for a QuickTime `tmcd` track (frame duration as a CMTime).
    var frameDuration: CMTime {
        switch self {
        case .fps23_976:
            return CMTime(value: 1001, timescale: 24000)
        case .fps24:
            return CMTime(value: 1, timescale: 24)
        case .fps25:
            return CMTime(value: 1, timescale: 25)
        case .fps29_97_nonDrop, .fps29_97_drop:
            return CMTime(value: 1001, timescale: 30000)
        case .fps30:
            return CMTime(value: 1, timescale: 30)
        }
    }

    /// Best-effort mapping from a measured nominal frame rate and a drop-frame flag
    /// (typically the flag decoded from the LTC stream).
    static func from(nominalFPS fps: Double, dropFrame: Bool) -> FrameRate {
        switch fps {
        case ..<23.99: return .fps23_976
        case 23.99..<24.5: return .fps24
        case 24.5..<27.0: return .fps25
        case 27.0..<29.985: return dropFrame ? .fps29_97_drop : .fps29_97_nonDrop
        case 29.985..<30.5: return dropFrame ? .fps29_97_drop : (fps < 29.995 ? .fps29_97_nonDrop : .fps30)
        default: return .fps30
        }
    }

    var displayName: String {
        switch self {
        case .fps23_976: return "23.976"
        case .fps24: return "24"
        case .fps25: return "25"
        case .fps29_97_nonDrop: return "29.97 NDF"
        case .fps29_97_drop: return "29.97 DF"
        case .fps30: return "30"
        }
    }
}

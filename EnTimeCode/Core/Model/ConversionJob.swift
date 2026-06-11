import Foundation

/// User-facing status of a single conversion job.
enum JobStatus: Equatable, Sendable {
    case queued
    case decoding
    case writing
    case finished(outputURL: URL, startTimecode: Timecode, rate: FrameRate)
    case failed(message: String)

    var isTerminal: Bool {
        switch self {
        case .finished, .failed: return true
        case .queued, .decoding, .writing: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .decoding, .writing: return true
        default: return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Which audio channel carries LTC.
enum LTCChannelSelection: Equatable, Sendable {
    case auto
    case left
    case right
}

/// A single video conversion request and its evolving state.
@MainActor
@Observable
final class ConversionJob: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let displayName: String

    var channelSelection: LTCChannelSelection = .auto
    var status: JobStatus = .queued
    var progress: Double = 0

    /// Channel that was actually used to decode LTC (resolved from auto-detection).
    var resolvedLTCChannel: Int?

    init(sourceURL: URL, displayName: String? = nil) {
        self.sourceURL = sourceURL
        self.displayName = displayName ?? sourceURL.lastPathComponent
    }
}

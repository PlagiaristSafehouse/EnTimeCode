import Foundation
import AVFoundation

/// Stateless helpers for the conversion pipeline. Orchestration lives in `BatchProcessor` so that
/// job state mutations stay on the main actor.
enum ConversionService {
    static func nominalFPS(forVideoAt url: URL) async throws -> Double? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let fps = try await track.load(.nominalFrameRate)
        return fps > 0 ? Double(fps) : nil
    }

    static func makeOutputURL(for source: URL, in directory: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(base)_TC.mov")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)_TC_\(counter).mov")
            counter += 1
        }
        return candidate
    }
}

import Foundation
import Observation

/// Crash-resistant breadcrumb log. Each step is written to disk immediately, so if the app is
/// killed (uncatchable crash, jetsam, etc.) the trail survives and can be shown on next launch.
/// This is the primary diagnostic when device crash reports aren't available.
@MainActor
@Observable
final class Diagnostics {
    static let shared = Diagnostics()

    private let fileURL: URL
    private(set) var entries: [String] = []

    /// Breadcrumbs captured during the previous app session (loaded at launch, before clearing).
    private(set) var previousSession: [String] = []

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("diagnostics.log")
        if let data = try? String(contentsOf: fileURL, encoding: .utf8), !data.isEmpty {
            previousSession = data.split(separator: "\n").map(String.init)
        }
        // Start a fresh log for this session.
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        log("=== session start \(Self.timestamp()) ===")
    }

    /// Record a breadcrumb and flush it to disk synchronously.
    func log(_ message: String) {
        let line = "\(Self.timestamp()) \(message)"
        entries.append(line)
        append(line)
    }

    /// Whether the previous session looks like it ended abnormally (started converting but never
    /// reached a terminal "finished"/"failed"/"session end" marker).
    var previousSessionCrashed: Bool {
        guard previousSession.contains(where: { $0.contains("CONVERT start") }) else { return false }
        return !previousSession.contains(where: {
            $0.contains("CONVERT finished") || $0.contains("CONVERT failed") || $0.contains("session end")
        })
    }

    var previousSessionText: String { previousSession.joined(separator: "\n") }

    func markCleanExit() {
        log("session end")
    }

    private func append(_ line: String) {
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            try? (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let data = (line + "\n").data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

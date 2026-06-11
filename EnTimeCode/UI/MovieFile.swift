import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Wraps a video selected from the Photos library so it can be copied to a working file URL.
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dir = MovieFile.importsDirectory
            let dest = dir.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }

    static var importsDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

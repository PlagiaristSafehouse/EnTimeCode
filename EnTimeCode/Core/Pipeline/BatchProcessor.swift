import Foundation
import Observation
import BackgroundTasks

/// Owns the batch queue and drives conversions. When the user starts a batch it is submitted as
/// a `BGContinuedProcessingTask` so it survives backgrounding (iOS 26+); if submission fails the
/// same work runs in-process so the app always functions.
@MainActor
@Observable
final class BatchProcessor {
    private(set) var jobs: [ConversionJob] = []
    private(set) var isRunning = false

    private var didRegister = false
    private var cancelRequested = false

    var outputDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Converted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Queue management

    func add(_ urls: [URL]) {
        for url in urls where !jobs.contains(where: { $0.sourceURL == url }) {
            jobs.append(ConversionJob(sourceURL: url))
        }
    }

    func remove(_ job: ConversionJob) {
        guard !job.status.isActive else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { if case .finished = $0.status { return true } else { return false } }
    }

    var pendingCount: Int {
        jobs.filter { $0.status == .queued || $0.status.isFailed }.count
    }

    /// Jobs that are not yet successfully converted (queued, in-progress, or failed).
    var pendingJobs: [ConversionJob] {
        jobs.filter { if case .finished = $0.status { return false } else { return true } }
    }

    /// Jobs that finished successfully.
    var convertedJobs: [ConversionJob] {
        jobs.filter { if case .finished = $0.status { return true } else { return false } }
    }

    /// Overall batch progress (0...1): finished jobs count as 1, others by their fraction.
    var overallProgress: Double {
        guard !jobs.isEmpty else { return 0 }
        let total = jobs.reduce(0.0) { acc, job in
            if case .finished = job.status { return acc + 1 }
            return acc + job.progress
        }
        return total / Double(jobs.count)
    }

    // MARK: Background task registration

    /// Master switch for the iOS 26 continued-processing background task. While debugging
    /// stability, leave this off so all `BGTaskScheduler` interaction is bypassed and batches
    /// run entirely in-process (proven reliable). Flip to `true` to re-enable background support.
    private let useBackgroundTask = false

    /// Register the continued-processing handler. Call once, early in app launch.
    func register() {
        guard useBackgroundTask, !didRegister else { return }
        didRegister = true
        // Registration can raise an Objective-C exception if the identifier is misconfigured or
        // unsupported on the current platform (e.g. Simulator). Don't let that crash launch.
        try? catchingObjCException {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundBatch.identifier,
                                            using: nil) { [weak self] task in
                guard let self, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    await self.run(backgroundTask: task)
                }
            }
        }
    }

    // MARK: Starting work

    /// Start processing pending jobs. Uses a background-continued task when enabled; otherwise
    /// (and on any submission failure) runs in-process so conversion always works.
    func start() {
        guard !isRunning, pendingCount > 0 else { return }

        if useBackgroundTask {
            let submitted = BackgroundBatch.submit(
                title: "Embedding Timecode",
                subtitle: "\(pendingCount) video\(pendingCount == 1 ? "" : "s")"
            )
            if submitted { return }
        }

        // Run directly in-process.
        Task { @MainActor in
            await self.run(backgroundTask: nil)
        }
    }

    func cancel() {
        cancelRequested = true
    }

    // MARK: Core runner

    private func run(backgroundTask: BGContinuedProcessingTask?) async {
        guard !isRunning else {
            backgroundTask?.setTaskCompleted(success: true)
            return
        }
        isRunning = true
        cancelRequested = false
        defer { isRunning = false }

        let pending = jobs.filter { $0.status == .queued || $0.status.isFailed }
        let progress = backgroundTask?.progress
        progress?.totalUnitCount = Int64(pending.count)
        progress?.completedUnitCount = 0

        backgroundTask?.expirationHandler = { [weak self] in
            Task { @MainActor in self?.cancel() }
        }

        for job in pending {
            if cancelRequested { break }
            job.progress = 0
            let sourceURL = job.sourceURL
            let selection = job.channelSelection
            do {
                Diagnostics.shared.log("CONVERT start \(sourceURL.lastPathComponent)")
                job.status = .decoding
                let videoFPS = try await ConversionService.nominalFPS(forVideoAt: sourceURL)
                Diagnostics.shared.log("CONVERT fps=\(videoFPS.map { String($0) } ?? "nil")")
                let analyzer = LTCAnalyzer(url: sourceURL, videoNominalFPS: videoFPS)
                let analysis = try await analyzer.analyze(channel: selection)
                Diagnostics.shared.log("CONVERT analyzed ch=\(analysis.channelIndex) rate=\(analysis.rate.displayName) start=\(analysis.startTimecode.displayString) frames=\(analysis.decodedFrameCount)")

                job.status = .writing
                let outputURL = ConversionService.makeOutputURL(for: sourceURL, in: outputDirectory)
                let writer = TimecodeConversionWriter(sourceURL: sourceURL,
                                                      outputURL: outputURL,
                                                      startTimecode: analysis.startTimecode,
                                                      rate: analysis.rate,
                                                      ltcChannel: analysis.channelIndex)
                try await writer.run(progress: { p in
                    Task { @MainActor in
                        let oldDecile = Int(job.progress * 10)
                        let newDecile = min(10, Int(p * 10))
                        job.progress = p
                        if newDecile != oldDecile {
                            Diagnostics.shared.log("CONVERT writing \(newDecile * 10)%")
                        }
                    }
                })

                job.resolvedLTCChannel = analysis.channelIndex
                job.status = .finished(outputURL: outputURL,
                                       startTimecode: analysis.startTimecode,
                                       rate: analysis.rate)
                Diagnostics.shared.log("CONVERT finished \(outputURL.lastPathComponent)")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Diagnostics.shared.log("CONVERT failed \(message)")
                job.status = .failed(message: message)
            }
            progress?.completedUnitCount += 1
        }

        backgroundTask?.setTaskCompleted(success: !cancelRequested)
    }
}

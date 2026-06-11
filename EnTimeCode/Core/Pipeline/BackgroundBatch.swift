import Foundation
import BackgroundTasks

/// Registers and submits the continued-processing background task that drives a batch so it
/// keeps running when the app is backgrounded (iOS 26+). Falls back gracefully when the task
/// cannot be submitted (e.g. on Simulator).
enum BackgroundBatch {
    static let identifier = "dev.ilish.entimecode.app.batch"

    /// Submit a continued-processing request. Returns false if submission failed for any reason
    /// (e.g. running on Simulator, missing entitlement, or an Objective-C exception from
    /// `BGTaskScheduler`), so the caller can fall back to in-process conversion.
    @discardableResult
    static func submit(title: String, subtitle: String) -> Bool {
        var succeeded = false
        // BGTaskScheduler.submit can raise an Objective-C NSException (not a Swift error) when the
        // task is misconfigured or unsupported; that would crash the app if it escaped. Catch both
        // NSExceptions and thrown Swift errors and report failure instead.
        let noException = (try? catchingObjCException {
            let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                           title: title,
                                                           subtitle: subtitle)
            request.strategy = .queue
            do {
                try BGTaskScheduler.shared.submit(request)
                succeeded = true
            } catch {
                succeeded = false
            }
        }) != nil
        return noException && succeeded
    }
}

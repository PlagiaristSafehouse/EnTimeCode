import Foundation

/// Executes `body` while catching Objective-C `NSException`s thrown by frameworks like
/// AVFoundation, rethrowing them as a Swift `Error`. Swift's `do/catch` cannot catch
/// `NSException`, so without this an AVFoundation exception crashes the whole app.
func catchingObjCException(_ body: @escaping () -> Void) throws {
    var caught: NSError?
    let ok = ETCRunCatchingExceptions(body, &caught)
    if !ok, let caught {
        throw caught
    }
}

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C @try/@catch so that AVFoundation NSExceptions
/// (which Swift cannot catch) are surfaced as NSError instead of crashing the app.
/// Returns YES on success, NO if an exception was caught (and sets `error`).
BOOL ETCRunCatchingExceptions(void (^_Nonnull block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

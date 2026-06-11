#import "ExceptionCatcher.h"

BOOL ETCRunCatchingExceptions(void (^block)(void), NSError *__autoreleasing *error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            info[@"ExceptionName"] = exception.name;
            if (exception.userInfo) {
                info[@"ExceptionUserInfo"] = exception.userInfo;
            }
            *error = [NSError errorWithDomain:@"EnTimeCode.ObjCException"
                                         code:-1
                                     userInfo:info];
        }
        return NO;
    }
}

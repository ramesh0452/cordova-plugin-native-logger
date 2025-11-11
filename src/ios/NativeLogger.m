#import <Cordova/CDV.h>
#include <signal.h>

@interface NativeLogger : CDVPlugin
@end

@implementation NativeLogger

static __weak NativeLogger *sharedInstance = nil;

// Forward declarations
static void handleException(NSException *exception);
static void handleSignal(int sig);

- (void)pluginInitialize {
    NSLog(@"[NativeLogger] Initializing native error/crash capture...");
    sharedInstance = self;

    // Prevent SIGPIPE crash when pipe breaks
    signal(SIGPIPE, SIG_IGN);

    [self startCapturingErrorLogs];

    // Catch crashes
    NSSetUncaughtExceptionHandler(&handleException);
    signal(SIGABRT, handleSignal);
    signal(SIGSEGV, handleSignal);
    signal(SIGBUS,  handleSignal);
    signal(SIGILL,  handleSignal);
    signal(SIGFPE,  handleSignal);
}


- (void)startCapturingErrorLogs {
    NSPipe *pipe = [NSPipe pipe];
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO);

    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = [handle availableData];
        if (data.length == 0) return;

        NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!line) return;

        // Only send lines containing "error" (case-insensitive)
        NSRange range = [line rangeOfString:@"error" options:NSCaseInsensitiveSearch];
        if (range.location != NSNotFound) {
            NSString *escaped = [line stringByReplacingOccurrencesOfString:@"`" withString:@"\\`"];
            escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];

            NSString *js = [NSString stringWithFormat:
                @"window.dispatchEvent(new CustomEvent('nativeLog', { detail: { type: 'error', message: `%@` } }));",
                escaped];

            if (sharedInstance && sharedInstance.commandDelegate) {
                [sharedInstance.commandDelegate evalJs:js];
            }
        }
    };
}

// === Exception handler ===
static void handleException(NSException *exception) {
    NSString *msg = [NSString stringWithFormat:@"Uncaught exception: %@\\nReason: %@",
                     exception.name, exception.reason];
    NSString *escaped = [msg stringByReplacingOccurrencesOfString:@"`" withString:@"\\`"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];

    NSString *js = [NSString stringWithFormat:
                    @"window.dispatchEvent(new CustomEvent('nativeLog', { detail: { type: 'crash', message: `%@` } }));",
                    escaped];
    if (sharedInstance && sharedInstance.commandDelegate) {
        [sharedInstance.commandDelegate evalJs:js];
    }
}

// === Signal handler ===
static void handleSignal(int sig) {
    NSString *msg = [NSString stringWithFormat:@"App received fatal signal %d", sig];
    NSString *escaped = [msg stringByReplacingOccurrencesOfString:@"`" withString:@"\\`"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];

    NSString *js = [NSString stringWithFormat:
                    @"window.dispatchEvent(new CustomEvent('nativeLog', { detail: { type: 'crash', message: `%@` } }));",
                    escaped];
    if (sharedInstance && sharedInstance.commandDelegate) {
        [sharedInstance.commandDelegate evalJs:js];
    }

    signal(sig, SIG_DFL);
    raise(sig);
}

@end

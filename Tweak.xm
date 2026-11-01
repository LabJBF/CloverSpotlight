
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString *const kLogPath =
    @"/var/mobile/Library/Logs/CloverSpotlight.log";

static void CSLog(NSString *message) {
    NSString *entry = [NSString stringWithFormat:
        @"[%@] %@\n",
        [NSDate date],
        message
    ];

    NSFileHandle *file =
        [NSFileHandle fileHandleForWritingAtPath:kLogPath];

    if (!file) {
        [[NSFileManager defaultManager]
            createFileAtPath:kLogPath
            contents:nil
            attributes:nil];

        file = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    }

    if (file) {
        [file seekToEndOfFile];
        [file writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    }

    NSLog(@"[CloverSpotlight] %@", message);
}

static void CSInspectSpotlight(void) {
    CSLog(@"Starting Spotlight diagnostics");

    void *framework = dlopen(
        "/System/Library/PrivateFrameworks/SpotlightUI.framework/SpotlightUI",
        RTLD_LAZY
    );

    CSLog(framework
        ? @"SpotlightUI framework loaded"
        : @"SpotlightUI framework could not be loaded");

    NSArray *classes = @[
        @"SPUISpotlightSceneManager",
        @"SPUISpotlightRemoteViewController",
        @"SPUISearchViewSceneSpecification"
    ];

    for (NSString *name in classes) {
        Class cls = NSClassFromString(name);

        CSLog([NSString stringWithFormat:@"%@: %@",
            name,
            cls ? @"AVAILABLE" : @"NOT FOUND"
        ]);
    }

    Class manager = NSClassFromString(@"SPUISpotlightSceneManager");

    if (manager) {
        SEL selector = @selector(sharedManager);

        CSLog([NSString stringWithFormat:
            @"sharedManager: %@",
            [manager respondsToSelector:selector]
                ? @"AVAILABLE"
                : @"NOT FOUND"
        ]);
    }

    CSLog(@"Spotlight diagnostics finished");
}

%ctor {
    @autoreleasepool {
        CSLog(@"CloverSpotlight 0.1.0 LOADED");
        CSLog([NSString stringWithFormat:
            @"Process: %@",
            [[NSProcessInfo processInfo] processName]
        ]);

        CSInspectSpotlight();
    }
}

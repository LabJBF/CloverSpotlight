
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// MARK: - Configuration

static NSString *const kLogPath =
    @"/var/mobile/Library/Logs/CloverSpotlight.log";

static NSString *const kTriggerPath =
    @"/var/mobile/Library/CloverSpotlight/launch";

// MARK: - Logging

static void CSLog(NSString *message) {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *directory =
        [kLogPath stringByDeletingLastPathComponent];

    [fm createDirectoryAtPath:directory
  withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];

    NSString *entry = [NSString stringWithFormat:
        @"[%@] %@\n",
        [NSDate date],
        message
    ];

    NSFileHandle *file =
        [NSFileHandle fileHandleForWritingAtPath:kLogPath];

    if (!file) {
        [fm createFileAtPath:kLogPath
                    contents:nil
                  attributes:nil];

        file = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    }

    if (file) {
        [file seekToEndOfFile];
        [file writeData:
            [entry dataUsingEncoding:NSUTF8StringEncoding]
        ];
        [file closeFile];
    }

    NSLog(@"[CloverSpotlight] %@", message);
}

// MARK: - Framework

static BOOL CSLoadSpotlightFramework(void) {
    static BOOL loaded = NO;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        const char *path =
            "/System/Library/PrivateFrameworks/SpotlightUI.framework/SpotlightUI";

        void *framework = dlopen(path, RTLD_NOW | RTLD_LOCAL);

        if (framework) {
            loaded = YES;
            CSLog(@"SpotlightUI framework loaded successfully");
        } else {
            const char *error = dlerror();

            CSLog([NSString stringWithFormat:
                @"Framework loading failed: %s",
                error ?: "Unknown error"
            ]);
        }
    });

    return loaded;
}

// MARK: - Native Spotlight

static BOOL CSRequestNativeSpotlight(void) {
    CSLog(@"Attempting native Spotlight launch");

    if (!CSLoadSpotlightFramework()) {
        CSLog(@"Launch aborted: framework unavailable");
        return NO;
    }

    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    if (!managerClass) {
        CSLog(@"Launch aborted: SceneManager unavailable");
        return NO;
    }

    SEL sharedSelector = @selector(sharedManager);

    if (![managerClass respondsToSelector:sharedSelector]) {
        CSLog(@"Launch aborted: sharedManager unavailable");
        return NO;
    }

    id manager =
        ((id (*)(id, SEL))objc_msgSend)(
            managerClass,
            sharedSelector
        );

    if (!manager) {
        CSLog(@"Launch aborted: manager returned nil");
        return NO;
    }

    SEL launchSelector =
        @selector(launchSpotlightIfNeededWithForegroundPriority:);

    if (![manager respondsToSelector:launchSelector]) {
        CSLog(@"Launch aborted: launch selector unavailable");
        return NO;
    }

    CSLog(@"Invoking native launch selector");

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        manager,
        launchSelector,
        YES
    );

    CSLog(@"Native launch selector returned");

    return YES;
}

// MARK: - Manual Trigger

static void CSInstallManualTrigger(void) {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *directory =
        [kTriggerPath stringByDeletingLastPathComponent];

    NSError *error = nil;

    [fm createDirectoryAtPath:directory
  withIntermediateDirectories:YES
                   attributes:nil
                        error:&error];

    if (error) {
        CSLog([NSString stringWithFormat:
            @"Trigger directory error: %@",
            error
        ]);
        return;
    }

    CSLog(@"Manual trigger installed");
    CSLog([NSString stringWithFormat:
        @"Waiting for trigger file: %@",
        kTriggerPath
    ]);

    dispatch_source_t timer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

    if (!timer) {
        CSLog(@"Could not create trigger timer");
        return;
    }

    dispatch_source_set_timer(
        timer,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
        NSEC_PER_SEC,
        100 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(timer, ^{
        if (![fm fileExistsAtPath:kTriggerPath]) {
            return;
        }

        CSLog(@"Manual launch trigger detected");

        [fm removeItemAtPath:kTriggerPath error:nil];

        dispatch_source_cancel(timer);

        BOOL result = CSRequestNativeSpotlight();

        CSLog(result
            ? @"Launch method invocation completed"
            : @"Launch method invocation failed"
        );
    });

    dispatch_resume(timer);
}

// MARK: - Diagnostics

static void CSInspectSpotlight(void) {
    CSLog(@"Starting Spotlight diagnostics");

    if (!CSLoadSpotlightFramework()) {
        CSLog(@"Diagnostics stopped");
        return;
    }

    NSArray *classes = @[
        @"SPUISpotlightSceneManager",
        @"SPUISpotlightRemoteViewController",
        @"SPUISearchViewSceneSpecification",
        @"SPUISearchViewSceneSettings",
        @"SPUISearchViewSceneTransitionContext"
    ];

    for (NSString *name in classes) {
        Class cls = NSClassFromString(name);

        CSLog([NSString stringWithFormat:
            @"%@ : %@",
            name,
            cls ? @"AVAILABLE" : @"NOT FOUND"
        ]);
    }

    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    if (managerClass) {
        SEL sharedSelector = @selector(sharedManager);

        BOOL available =
            [managerClass respondsToSelector:sharedSelector];

        CSLog([NSString stringWithFormat:
            @"sharedManager: %@",
            available ? @"AVAILABLE" : @"NOT FOUND"
        ]);

        if (available) {
            id manager =
                ((id (*)(id, SEL))objc_msgSend)(
                    managerClass,
                    sharedSelector
                );

            CSLog([NSString stringWithFormat:
                @"Manager instance: %@",
                manager ? @"AVAILABLE" : @"NIL"
            ]);

            SEL launchSelector =
                @selector(launchSpotlightIfNeededWithForegroundPriority:);

            CSLog([NSString stringWithFormat:
                @"Native launch selector: %@",
                [manager respondsToSelector:launchSelector]
                    ? @"AVAILABLE"
                    : @"NOT FOUND"
            ]);
        }
    }

    CSLog(@"Spotlight diagnostics finished");
}

// MARK: - Constructor

%ctor {
    @autoreleasepool {
        CSLog(@"CloverSpotlight 0.1.2 LOADED");

        CSLog([NSString stringWithFormat:
            @"Process: %@",
            [[NSProcessInfo processInfo] processName]
        ]);

        CSInspectSpotlight();
        CSInstallManualTrigger();
    }
}

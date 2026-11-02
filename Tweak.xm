
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
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
                @"SpotlightUI loading failed: %s",
                error ?: "Unknown error"
            ]);
        }
    });

    return loaded;
}

// MARK: - Diagnostics

static void CSInspectSpotlight(void) {
    CSLog(@"Starting Spotlight diagnostics");

    if (!CSLoadSpotlightFramework()) {
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

    if (!managerClass) {
        CSLog(@"SceneManager unavailable");
        return;
    }

    SEL sharedSelector = @selector(sharedManager);

    BOOL hasSharedManager =
        [managerClass respondsToSelector:sharedSelector];

    CSLog([NSString stringWithFormat:
        @"sharedManager: %@",
        hasSharedManager ? @"AVAILABLE" : @"NOT FOUND"
    ]);

    if (hasSharedManager) {
        id manager =
            ((id (*)(id, SEL))objc_msgSend)(
                managerClass,
                sharedSelector
            );

        SEL launchSelector =
            @selector(launchSpotlightIfNeededWithForegroundPriority:);

        CSLog([NSString stringWithFormat:
            @"Manager instance: %@",
            manager ? @"AVAILABLE" : @"NIL"
        ]);

        CSLog([NSString stringWithFormat:
            @"Native launch selector: %@",
            [manager respondsToSelector:launchSelector]
                ? @"AVAILABLE"
                : @"NOT FOUND"
        ]);
    }

    CSLog(@"Spotlight diagnostics finished");
}

// MARK: - Native Spotlight Request

static BOOL CSRequestNativeSpotlight(void) {
    CSLog(@"Native Spotlight launch requested");

    if (!CSLoadSpotlightFramework()) {
        CSLog(@"Cannot request Spotlight: framework unavailable");
        return NO;
    }

    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    if (!managerClass) {
        CSLog(@"Cannot request Spotlight: manager unavailable");
        return NO;
    }

    SEL sharedSelector = @selector(sharedManager);

    if (![managerClass respondsToSelector:sharedSelector]) {
        CSLog(@"sharedManager selector unavailable");
        return NO;
    }

    id manager =
        ((id (*)(id, SEL))objc_msgSend)(
            managerClass,
            sharedSelector
        );

    if (!manager) {
        CSLog(@"sharedManager returned nil");
        return NO;
    }

    SEL launchSelector =
        @selector(launchSpotlightIfNeededWithForegroundPriority:);

    if (![manager respondsToSelector:launchSelector]) {
        CSLog(@"Native launch selector unavailable");
        return NO;
    }

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        manager,
        launchSelector,
        YES
    );

    CSLog(@"Native Spotlight launch method invoked");

    return YES;
}

// MARK: - Constructor

%ctor {
    @autoreleasepool {
        CSLog(@"CloverSpotlight 0.1.1 LOADED");

        CSLog([NSString stringWithFormat:
            @"Process: %@",
            [[NSProcessInfo processInfo] processName]
        ]);

        CSInspectSpotlight();
    }
}

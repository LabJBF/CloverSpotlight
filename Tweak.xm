
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const kLogPath =
    @"/var/mobile/Library/Logs/CloverSpotlight.log";

static NSString *const kTriggerPath =
    @"/var/mobile/Library/CloverSpotlight/launch";

static void CSLog(NSString *message) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *directory = [kLogPath stringByDeletingLastPathComponent];

    [fm createDirectoryAtPath:directory
  withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];

    NSString *entry = [NSString stringWithFormat:@"[%@] %@\n",
                       [NSDate date], message];

    if (![fm fileExistsAtPath:kLogPath]) {
        [fm createFileAtPath:kLogPath contents:nil attributes:nil];
    }

    NSFileHandle *file =
        [NSFileHandle fileHandleForWritingAtPath:kLogPath];

    if (file) {
        [file seekToEndOfFile];
        [file writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    }

    NSLog(@"[CloverSpotlight] %@", message);
}

static BOOL CSLoadSpotlightFramework(void) {
    static BOOL loaded = NO;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        const char *path =
        "/System/Library/PrivateFrameworks/SpotlightUI.framework/SpotlightUI";

        void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);

        if (handle) {
            loaded = YES;
            CSLog(@"SpotlightUI framework loaded");
        } else {
            CSLog([NSString stringWithFormat:
                   @"Framework error: %s", dlerror() ?: "Unknown"]);
        }
    });

    return loaded;
}

static void CSInspectClass(Class cls) {
    if (!cls) return;

    CSLog([NSString stringWithFormat:
           @"===== CLASS: %@ =====", NSStringFromClass(cls)]);

    unsigned int count = 0;

    Method *methods = class_copyMethodList(cls, &count);

    for (unsigned int i = 0; i < count; i++) {
        SEL selector = method_getName(methods[i]);
        const char *encoding = method_getTypeEncoding(methods[i]);

        NSString *name = NSStringFromSelector(selector);

        if ([name localizedCaseInsensitiveContainsString:@"spotlight"] ||
            [name localizedCaseInsensitiveContainsString:@"scene"] ||
            [name localizedCaseInsensitiveContainsString:@"launch"] ||
            [name localizedCaseInsensitiveContainsString:@"present"] ||
            [name localizedCaseInsensitiveContainsString:@"foreground"] ||
            [name localizedCaseInsensitiveContainsString:@"create"]) {

            CSLog([NSString stringWithFormat:
                   @"METHOD: %@ | encoding: %s",
                   name, encoding ?: "unknown"]);
        }
    }

    free(methods);

    Ivar *ivars = class_copyIvarList(cls, &count);

    for (unsigned int i = 0; i < count; i++) {
        const char *name = ivar_getName(ivars[i]);

        if (name) {
            CSLog([NSString stringWithFormat:@"IVAR: %s", name]);
        }
    }

    free(ivars);

    objc_property_t *properties = class_copyPropertyList(cls, &count);

    for (unsigned int i = 0; i < count; i++) {
        const char *name = property_getName(properties[i]);

        if (name) {
            CSLog([NSString stringWithFormat:@"PROPERTY: %s", name]);
        }
    }

    free(properties);
}

static void CSInspectSpotlight(void) {
    CSLog(@"Starting extended Spotlight inspection");

    if (!CSLoadSpotlightFramework()) return;

    NSArray *names = @[
        @"SPUISpotlightSceneManager",
        @"SPUISpotlightRemoteViewController",
        @"SPUISearchViewSceneSpecification",
        @"SPUISearchViewSceneSettings",
        @"SPUISearchViewSceneTransitionContext"
    ];

    for (NSString *name in names) {
        Class cls = NSClassFromString(name);

        CSLog([NSString stringWithFormat:
               @"%@ : %@",
               name, cls ? @"AVAILABLE" : @"NOT FOUND"]);

        if (cls) {
            CSInspectClass(cls);
        }
    }

    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    if (managerClass &&
        [managerClass respondsToSelector:@selector(sharedManager)]) {

        id manager =
            ((id (*)(id, SEL))objc_msgSend)(
                managerClass,
                @selector(sharedManager)
            );

        CSLog([NSString stringWithFormat:
               @"Manager instance: %@",
               manager ? NSStringFromClass([manager class]) : @"NIL"]);

        if (manager) {
            CSInspectClass([manager class]);

            SEL launchSelector =
                @selector(launchSpotlightIfNeededWithForegroundPriority:);

            CSLog([NSString stringWithFormat:
                   @"Launch selector available: %@",
                   [manager respondsToSelector:launchSelector]
                       ? @"YES" : @"NO"]);
        }
    }

    CSLog(@"Extended inspection finished");
}

static BOOL CSRequestNativeSpotlight(void) {
    CSLog(@"Requesting native Spotlight");

    if (!CSLoadSpotlightFramework()) return NO;

    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    if (!managerClass) return NO;

    SEL sharedSelector = @selector(sharedManager);

    if (![managerClass respondsToSelector:sharedSelector]) return NO;

    id manager =
        ((id (*)(id, SEL))objc_msgSend)(
            managerClass,
            sharedSelector
        );

    if (!manager) return NO;

    SEL launchSelector =
        @selector(launchSpotlightIfNeededWithForegroundPriority:);

    if (![manager respondsToSelector:launchSelector]) return NO;

    CSLog(@"Calling native launch method");

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        manager,
        launchSelector,
        YES
    );

    CSLog(@"Native launch method returned");
    CSLog(@"NOTE: UI presentation has not been verified");

    return YES;
}

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
               @"Trigger directory error: %@", error]);
        return;
    }

    dispatch_source_t timer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

    if (!timer) {
        CSLog(@"Timer creation failed");
        return;
    }

    dispatch_source_set_timer(
        timer,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
        NSEC_PER_SEC,
        100 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(timer, ^{
        if (![fm fileExistsAtPath:kTriggerPath]) return;

        CSLog(@"Manual trigger detected");

        [fm removeItemAtPath:kTriggerPath error:nil];

        dispatch_source_cancel(timer);

        BOOL result = CSRequestNativeSpotlight();

        CSLog(result
            ? @"Native method invocation completed"
            : @"Native method invocation failed");
    });

    dispatch_resume(timer);

    CSLog(@"Manual trigger installed");
}

%ctor {
    @autoreleasepool {
        CSLog(@"CloverSpotlight 0.1.3 LOADED");

        CSLog([NSString stringWithFormat:
               @"Process: %@",
               [[NSProcessInfo processInfo] processName]]);

        CSInspectSpotlight();
        CSInstallManualTrigger();
    }
}


#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const kLogPath =
    @"/var/mobile/Library/Logs/CloverSpotlight.log";

static NSString *const kTriggerPath =
    @"/var/mobile/Library/CloverSpotlight/launch";

static dispatch_source_t gTriggerTimer = nil;

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

static id CSGetObjectProperty(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static void CSLogObjectProperty(id object,
                                NSString *label,
                                SEL selector) {
    id value = CSGetObjectProperty(object, selector);

    CSLog([NSString stringWithFormat:
           @"%@ = %@",
           label,
           value ? [value description] : @"NIL"]);
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

static NSArray *CSObjectsFromCollection(id collection) {
    if (!collection) return @[];

    if ([collection isKindOfClass:[NSHashTable class]]) {
        return [(NSHashTable *)collection allObjects] ?: @[];
    }

    if ([collection isKindOfClass:[NSArray class]]) {
        return (NSArray *)collection;
    }

    CSLog([NSString stringWithFormat:
           @"Unknown collection type: %@",
           NSStringFromClass([collection class])]);

    return @[];
}

static void CSInspectSceneObject(id object, NSUInteger index) {
    if (!object) return;

    CSLog([NSString stringWithFormat:
           @"--- SCENE OBJECT %lu ---",
           (unsigned long)index]);

    CSLog([NSString stringWithFormat:
           @"Object class: %@",
           NSStringFromClass([object class])]);

    CSLog([NSString stringWithFormat:
           @"Object description: %@",
           [object description]]);

    CSLogObjectProperty(object, @"sceneIdentifier",
                        @selector(sceneIdentifier));

    CSLogObjectProperty(object, @"scene",
                        @selector(scene));

    CSLogObjectProperty(object, @"presenter",
                        @selector(presenter));

    CSLogObjectProperty(object, @"hostView",
                        @selector(hostView));

    CSLogObjectProperty(object, @"foregroundScenes",
                        @selector(foregroundScenes));
}

static void CSInspectManagerState(void) {
    CSLog(@"========== SPOTLIGHT STATE BEGIN ==========");

    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    if (!managerClass) {
        CSLog(@"Manager class unavailable");
        return;
    }

    id manager =
        CSGetObjectProperty(managerClass, @selector(sharedManager));

    if (!manager) {
        CSLog(@"Shared manager is NIL");
        return;
    }

    CSLog([NSString stringWithFormat:
           @"Manager: %@",
           NSStringFromClass([manager class])]);

    id managedScenes =
        CSGetObjectProperty(manager, @selector(managedScenes));

    id foregroundScenes =
        CSGetObjectProperty(manager, @selector(foregroundScenes));

    id processHandle =
        CSGetObjectProperty(manager, @selector(spotlightProcessHandle));

    CSLog([NSString stringWithFormat:
           @"Managed scenes collection: %@",
           managedScenes ?: @"NIL"]);

    CSLog([NSString stringWithFormat:
           @"Foreground scenes collection: %@",
           foregroundScenes ?: @"NIL"]);

    CSLog([NSString stringWithFormat:
           @"Spotlight process handle: %@",
           processHandle ?: @"NIL"]);

    NSArray *managed = CSObjectsFromCollection(managedScenes);
    NSArray *foreground = CSObjectsFromCollection(foregroundScenes);

    CSLog([NSString stringWithFormat:
           @"Managed scene count: %lu",
           (unsigned long)managed.count]);

    CSLog([NSString stringWithFormat:
           @"Foreground scene count: %lu",
           (unsigned long)foreground.count]);

    for (NSUInteger i = 0; i < managed.count; i++) {
        CSInspectSceneObject(managed[i], i);
    }

    CSLog(@"========== FOREGROUND OBJECTS ==========");

    for (NSUInteger i = 0; i < foreground.count; i++) {
        CSInspectSceneObject(foreground[i], i);
    }

    CSLog(@"========== SPOTLIGHT STATE END ==========");
}

static void CSScheduleStateInspection(void) {
    NSArray *delays = @[@1, @3, @6];

    for (NSNumber *delay in delays) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                CSLog([NSString stringWithFormat:
                       @"Running state inspection after %@ seconds",
                       delay]);

                CSInspectManagerState();
            }
        );
    }
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

    if (!managerClass) {
        CSLog(@"Manager class not found");
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
        CSLog(@"Manager instance is NIL");
        return NO;
    }

    SEL launchSelector =
        @selector(launchSpotlightIfNeededWithForegroundPriority:);

    if (![manager respondsToSelector:launchSelector]) {
        CSLog(@"Launch selector unavailable");
        return NO;
    }

    CSLog(@"Calling native launch method");

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        manager,
        launchSelector,
        YES
    );

    CSLog(@"Native launch method returned");
    CSLog(@"Scheduling post-launch state inspections");

    CSScheduleStateInspection();

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

    gTriggerTimer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

    if (!gTriggerTimer) {
        CSLog(@"Timer creation failed");
        return;
    }

    dispatch_source_set_timer(
        gTriggerTimer,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
        NSEC_PER_SEC,
        100 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(gTriggerTimer, ^{
        if (![fm fileExistsAtPath:kTriggerPath]) return;

        CSLog(@"Manual trigger detected");

        [fm removeItemAtPath:kTriggerPath error:nil];

        dispatch_source_cancel(gTriggerTimer);
        gTriggerTimer = nil;

        BOOL result = CSRequestNativeSpotlight();

        CSLog(result
            ? @"Native method invocation completed"
            : @"Native method invocation failed");
    });

    dispatch_resume(gTriggerTimer);

    CSLog(@"Manual trigger installed");
}

%ctor {
    @autoreleasepool {
        CSLog(@"CloverSpotlight 0.1.4 LOADED");

        CSLog([NSString stringWithFormat:
               @"Process: %@",
               [[NSProcessInfo processInfo] processName]]);

        CSInspectSpotlight();
        CSInstallManualTrigger();
    }
}

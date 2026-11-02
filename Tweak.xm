
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const kLogPath =
    @"/var/mobile/Library/Logs/NyxianSpotlight.log";

static NSString *const kTriggerPath =
    @"/var/mobile/Library/NyxianSpotlight/launch";

static dispatch_source_t gTriggerTimer = nil;

// MARK: - Logging

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

    NSLog(@"[NyxianSpotlight] %@", message);
}

// MARK: - Framework

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

// MARK: - Runtime Helpers

static id CSGetObjectProperty(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static void CSLogObjectProperty(id object,
                                NSString *label,
                                SEL selector) {
    if (!object) {
        CSLog([NSString stringWithFormat:@"%@: owner is NIL", label]);
        return;
    }

    if (![object respondsToSelector:selector]) {
        CSLog([NSString stringWithFormat:@"%@: selector unavailable", label]);
        return;
    }

    id value = CSGetObjectProperty(object, selector);

    CSLog([NSString stringWithFormat:
           @"%@ = %@",
           label,
           value ? [value description] : @"NIL"]);

    if (value) {
        CSLog([NSString stringWithFormat:
               @"%@ class = %@",
               label,
               NSStringFromClass([value class])]);
    }
}

// Safely reads an existing object ivar without modifying it.
static id CSGetObjectIvar(id object, const char *ivarName) {
    if (!object || !ivarName) return nil;

    Ivar ivar = class_getInstanceVariable(
        object_getClass(object),
        ivarName
    );

    if (!ivar) {
        Class cls = [object class];

        while (cls && !ivar) {
            ivar = class_getInstanceVariable(cls, ivarName);
            cls = class_getSuperclass(cls);
        }
    }

    if (!ivar) {
        CSLog([NSString stringWithFormat:
               @"IVAR NOT FOUND: %s", ivarName]);
        return nil;
    }

    const char *type = ivar_getTypeEncoding(ivar);

    if (!type || type[0] != '@') {
        CSLog([NSString stringWithFormat:
               @"IVAR IS NOT AN OBJECT: %s | type: %s",
               ivarName, type ?: "unknown"]);
        return nil;
    }

    return object_getIvar(object, ivar);
}

static void CSLogIvarObject(id object,
                            NSString *label,
                            const char *ivarName) {
    if (!object) {
        CSLog([NSString stringWithFormat:@"%@: owner is NIL", label]);
        return;
    }

    id value = CSGetObjectIvar(object, ivarName);

    CSLog([NSString stringWithFormat:
           @"%@ = %@",
           label,
           value ? [value description] : @"NIL"]);

    if (value) {
        CSLog([NSString stringWithFormat:
               @"%@ class = %@",
               label,
               NSStringFromClass([value class])]);
    }
}

// MARK: - Runtime Inspection

static void CSInspectMethodList(Class cls,
                                BOOL classMethods,
                                NSString *label) {
    if (!cls) return;

    Class target = classMethods ? object_getClass(cls) : cls;

    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);

    CSLog([NSString stringWithFormat:
           @"--- %@ METHODS: %@ ---",
           label,
           classMethods ? @"CLASS" : @"INSTANCE"]);

    for (unsigned int i = 0; i < count; i++) {
        SEL selector = method_getName(methods[i]);
        const char *encoding = method_getTypeEncoding(methods[i]);

        NSString *name = NSStringFromSelector(selector);

        if ([name localizedCaseInsensitiveContainsString:@"spotlight"] ||
            [name localizedCaseInsensitiveContainsString:@"scene"] ||
            [name localizedCaseInsensitiveContainsString:@"launch"] ||
            [name localizedCaseInsensitiveContainsString:@"present"] ||
            [name localizedCaseInsensitiveContainsString:@"foreground"] ||
            [name localizedCaseInsensitiveContainsString:@"create"] ||
            [name localizedCaseInsensitiveContainsString:@"init"] ||
            [name localizedCaseInsensitiveContainsString:@"delegate"] ||
            [name localizedCaseInsensitiveContainsString:@"service"]) {

            CSLog([NSString stringWithFormat:
                   @"METHOD: %@ | encoding: %s",
                   name, encoding ?: "unknown"]);
        }
    }

    free(methods);
}

static void CSInspectClass(Class cls) {
    if (!cls) return;

    CSLog([NSString stringWithFormat:
           @"===== CLASS: %@ =====", NSStringFromClass(cls)]);

    CSInspectMethodList(cls, NO, NSStringFromClass(cls));
    CSInspectMethodList(cls, YES, NSStringFromClass(cls));

    unsigned int count = 0;

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

// MARK: - Scene Inspection

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

// MARK: - Spotlight Process Identity

static void CSInspectProcessIdentity(void) {
    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    if (!managerClass) {
        CSLog(@"Process identity: manager class unavailable");
        return;
    }

    SEL identitySelector = @selector(spotlightProcessIdentity);

    if (![managerClass respondsToSelector:identitySelector]) {
        CSLog(@"spotlightProcessIdentity selector unavailable");
        return;
    }

    CSLog(@"Calling spotlightProcessIdentity");

    id identity =
        ((id (*)(id, SEL))objc_msgSend)(
            managerClass,
            identitySelector
        );

    CSLog([NSString stringWithFormat:
           @"Spotlight process identity: %@",
           identity ? [identity description] : @"NIL"]);

    if (identity) {
        CSLog([NSString stringWithFormat:
               @"Process identity class: %@",
               NSStringFromClass([identity class])]);
    }
}

// MARK: - Manager Inspection

static void CSInspectManagerDependencies(id manager) {
    CSLog(@"========== MANAGER DEPENDENCIES ==========");

    CSLogObjectProperty(manager, @"delegate",
                        @selector(delegate));

    // The getter may not exist. Inspect the actual ivar instead.
    CSLogIvarObject(manager, @"_appService ivar", "_appService");

    CSLogObjectProperty(manager, @"appService",
                        @selector(appService));

    CSLogObjectProperty(manager, @"layoutMonitor",
                        @selector(layoutMonitor));

    CSLogObjectProperty(manager, @"watchdogTimer",
                        @selector(watchdogTimer));

    CSLogObjectProperty(manager, @"initializationAssertions",
                        @selector(initializationAssertions));

    CSLogObjectProperty(manager, @"backgroundingAssertions",
                        @selector(backgroundingAssertions));

    CSLogObjectProperty(manager, @"queue",
                        @selector(queue));

    CSLog(@"========== DEPENDENCIES END ==========");
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

    CSInspectManagerDependencies(manager);

    CSLog(@"========== SPOTLIGHT STATE END ==========");
}

// MARK: - Delayed Inspection

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

// MARK: - Initial Inspection

static void CSInspectSpotlight(void) {
    CSLog(@"Starting 0.1.6 runtime inspection");

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
            CSInspectManagerDependencies(manager);

            SEL launchSelector =
                @selector(launchSpotlightIfNeededWithForegroundPriority:);

            CSLog([NSString stringWithFormat:
                   @"Launch selector available: %@",
                   [manager respondsToSelector:launchSelector]
                       ? @"YES" : @"NO"]);
        }
    }

    CSInspectProcessIdentity();

    CSLog(@"Runtime inspection finished");
}

// MARK: - Native Spotlight Request

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

    CSLog(@"Inspecting manager before launch");
    CSInspectManagerDependencies(manager);
    CSInspectProcessIdentity();

    CSLog(@"Calling native launch method");

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        manager,
        launchSelector,
        YES
    );

    CSLog(@"Native launch method returned");

    CSScheduleStateInspection();

    CSLog(@"UI presentation remains unverified");

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

// MARK: - Constructor

%ctor {
    @autoreleasepool {
        CSLog(@"Nyxian Spotlight 0.1.6 LOADED");

        CSLog([NSString stringWithFormat:
               @"Process: %@",
               [[NSProcessInfo processInfo] processName]]);

        CSInspectSpotlight();
        CSInstallManualTrigger();
    }
}


#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// ======================================================
// CloverSpotlight 0.1.1
// Runtime Diagnostics
// Target: iOS 27.0 / SpringBoard
// ======================================================

static void CSLogMethod(Class cls, BOOL classMethod, SEL selector) {
    if (!cls || !selector) {
        return;
    }

    Method method = classMethod
        ? class_getClassMethod(cls, selector)
        : class_getInstanceMethod(cls, selector);

    if (method) {
        NSLog(@"[CloverSpotlight] FOUND %@ %@ | Encoding: %s",
              classMethod ? @"CLASS" : @"INSTANCE",
              NSStringFromSelector(selector),
              method_getTypeEncoding(method));
    } else {
        NSLog(@"[CloverSpotlight] MISSING %@ %@",
              classMethod ? @"CLASS" : @"INSTANCE",
              NSStringFromSelector(selector));
    }
}

static void CSInspectRuntime(void) {
    NSLog(@"[CloverSpotlight] ===== Runtime Diagnostics =====");

    // 1. Load SpotlightUI framework.
    const char *frameworkPath =
        "/System/Library/PrivateFrameworks/SpotlightUI.framework/SpotlightUI";

    void *framework = dlopen(frameworkPath, RTLD_LAZY);

    if (framework) {
        NSLog(@"[CloverSpotlight] SpotlightUI loaded successfully.");
    } else {
        const char *error = dlerror();

        NSLog(@"[CloverSpotlight] SpotlightUI load failed: %s",
              error ? error : "Unknown error");
    }

    // 2. Resolve native classes.
    Class managerClass =
        NSClassFromString(@"SPUISpotlightSceneManager");

    Class remoteControllerClass =
        NSClassFromString(@"SPUISpotlightRemoteViewController");

    Class sceneSpecificationClass =
        NSClassFromString(@"SPUISearchViewSceneSpecification");

    NSLog(@"[CloverSpotlight] SPUISpotlightSceneManager: %@",
          managerClass ? @"AVAILABLE" : @"NOT FOUND");

    NSLog(@"[CloverSpotlight] SPUISpotlightRemoteViewController: %@",
          remoteControllerClass ? @"AVAILABLE" : @"NOT FOUND");

    NSLog(@"[CloverSpotlight] SPUISearchViewSceneSpecification: %@",
          sceneSpecificationClass ? @"AVAILABLE" : @"NOT FOUND");

    // 3. Inspect Scene Manager.
    if (managerClass) {
        CSLogMethod(managerClass, YES, @selector(sharedManager));

        CSLogMethod(managerClass, NO,
            @selector(launchSpotlightIfNeededWithForegroundPriority:));

        CSLogMethod(managerClass, NO, @selector(addScene:));
        CSLogMethod(managerClass, NO, @selector(removeScene:));
        CSLogMethod(managerClass, NO, @selector(applyAssertionAsNeeded));
    }

    // 4. Inspect Remote View Controller.
    if (remoteControllerClass) {
        CSLogMethod(remoteControllerClass, NO,
            @selector(initWithSceneIdentifier:));

        CSLogMethod(remoteControllerClass, NO,
            @selector(createSceneIfNeededWithPriority:));

        CSLogMethod(remoteControllerClass, NO,
            @selector(createSceneWithPriority:));

        CSLogMethod(remoteControllerClass, NO,
            @selector(setForeground:));

        CSLogMethod(remoteControllerClass, NO,
            @selector(sceneSpecification));

        CSLogMethod(remoteControllerClass, NO,
            @selector(setHostView:));

        CSLogMethod(remoteControllerClass, NO,
            @selector(setPresenter:));
    }

    // 5. Inspect Scene Specification.
    if (sceneSpecificationClass) {
        CSLogMethod(sceneSpecificationClass, NO,
            @selector(settingsClass));

        CSLogMethod(sceneSpecificationClass, NO,
            @selector(clientSettingsClass));

        CSLogMethod(sceneSpecificationClass, NO,
            @selector(transitionContextClass));
    }

    NSLog(@"[CloverSpotlight] ===== Diagnostics Complete =====");
}

%ctor {
    @autoreleasepool {
        NSString *processName =
            [[NSProcessInfo processInfo] processName];

        NSLog(@"[CloverSpotlight] Loaded into process: %@",
              processName);

        // Wait until SpringBoard has finished its initial startup.
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
                CSInspectRuntime();
            }
        );
    }
}

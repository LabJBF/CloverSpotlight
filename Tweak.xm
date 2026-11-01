#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// CloverSpotlight 0.1.0
// Research scaffold only: no private Spotlight methods are hooked yet.
// We will add hooks only after verifying the exact iOS 27.0 headers
// and runtime availability on the target device.

%ctor {
    @autoreleasepool {
        NSLog(@"[CloverSpotlight] Loaded into process: %@",
              [[NSProcessInfo processInfo] processName]);
    }
}

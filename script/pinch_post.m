// pinch_post: Synthesize macOS magnify (pinch) gesture events and post them
// to the frontmost app via kCGSessionEventTap.
//
// Uses Hammerspoon's libeventtapevent.dylib which contains the private
// tl_CGEventCreateFromGesture function and kTLInfo* symbols. The dylib
// and its LuaSkin.framework dependency must be deployed alongside this
// binary (see script/pinch_deploy.sh).
//
// Usage: pinch_post <pid> <from_scale> <to_scale> [steps] [delay_ms] [lib_path]
//   pid        - target app PID (used to find window center for event location)
//   from_scale - current zoom scale (1.0 = fitted, 2.0 = zoomed 2x)
//   to_scale   - target zoom scale after the pinch
//   steps      - number of intermediate events (default 20)
//   delay_ms   - delay between steps in ms (default 16)
//   lib_path   - dir with libeventtapevent.dylib + LuaSkin.framework
//                (default: /Users/admin/teststrip-vm/gesture)
//
// Examples:
//   pinch_post 1234 1.0 2.0     # pinch out from fitted to 2x
//   pinch_post 1234 2.0 1.0     # pinch back from 2x to fitted
//
// Build: see script/pinch_deploy.sh
// Requires: Hammerspoon installed (for libeventtapevent.dylib + LuaSkin.framework)
//
// The magnification delta per NSEvent docs is cumulative: a magnification
// of 1.0 = 100% size increase. SwiftUI's MagnificationGesture value = 1 + mag.
// So newScale = baseScale * (1 + mag), meaning:
//   totalMag = to_scale / from_scale - 1.0

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <mach/mach_time.h>

typedef CGEventRef (*CreateGestureFunc)(CFDictionaryRef info, CFArrayRef touches);

static CreateGestureFunc createGesture = NULL;
static CFStringRef subtypeKey = NULL;
static CFStringRef phaseKey = NULL;
static CFStringRef magKey = NULL;

static void initGesture(const char* basePath) {
    char luaSkinPath[512], dylibPath[512];
    snprintf(luaSkinPath, sizeof(luaSkinPath), "%s/LuaSkin.framework/Versions/A/LuaSkin", basePath);
    snprintf(dylibPath, sizeof(dylibPath), "%s/libeventtapevent.dylib", basePath);

    dlopen(luaSkinPath, RTLD_NOW);
    void* handle = dlopen(dylibPath, RTLD_NOW);
    if (!handle) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); exit(1); }
    createGesture = (CreateGestureFunc)dlsym(handle, "tl_CGEventCreateFromGesture");
    subtypeKey = *(CFStringRef*)dlsym(handle, "kTLInfoKeyGestureSubtype");
    phaseKey = *(CFStringRef*)dlsym(handle, "kTLInfoKeyGesturePhase");
    magKey = *(CFStringRef*)dlsym(handle, "kTLInfoKeyMagnification");
    if (!createGesture || !subtypeKey || !phaseKey || !magKey) {
        fprintf(stderr, "Missing symbols in %s\n", dylibPath);
        exit(1);
    }
}

static CGEventRef createMagEvent(uint32_t phase, double magnification, CGPoint location) {
    uint32_t subtypeVal = 0x08; // kTLInfoSubtypeMagnify
    const void* keys[] = {subtypeKey, phaseKey, magKey};
    const void* vals[] = {
        CFNumberCreate(NULL, kCFNumberSInt32Type, &subtypeVal),
        CFNumberCreate(NULL, kCFNumberSInt32Type, &phase),
        CFNumberCreate(NULL, kCFNumberDoubleType, &magnification)
    };
    CFDictionaryRef dict = CFDictionaryCreate(NULL, keys, vals, 3,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef touches = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    CGEventRef event = createGesture(dict, touches);
    CFRelease(dict);
    CFRelease(touches);
    if (event) {
        CGEventSetLocation(event, location);
        CGEventSetTimestamp(event, mach_absolute_time());
    }
    return event;
}

static CGPoint getWindowCenter(pid_t pid) {
    CGPoint center = CGPointMake(640, 400);
    AXUIElementRef appRef = AXUIElementCreateApplication(pid);
    if (appRef) {
        CFArrayRef windows = NULL;
        AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef*)&windows);
        if (windows && CFArrayGetCount(windows) > 0) {
            AXUIElementRef win = (AXUIElementRef)CFArrayGetValueAtIndex(windows, 0);
            AXValueRef posVal = NULL, sizeVal = NULL;
            AXUIElementCopyAttributeValue(win, kAXPositionAttribute, (CFTypeRef*)&posVal);
            AXUIElementCopyAttributeValue(win, kAXSizeAttribute, (CFTypeRef*)&sizeVal);
            if (posVal && sizeVal) {
                CGPoint pos; CGSize size;
                AXValueGetValue(posVal, kAXValueCGPointType, &pos);
                AXValueGetValue(sizeVal, kAXValueCGSizeType, &size);
                center = CGPointMake(pos.x + size.width/2, pos.y + size.height/2);
                CFRelease(posVal); CFRelease(sizeVal);
            }
            CFRelease(windows);
        }
        CFRelease(appRef);
    }
    return center;
}

int main(int argc, char* argv[]) {
    @autoreleasepool {
        if (argc < 4) {
            fprintf(stderr, "Usage: %s <pid> <from_scale> <to_scale> [steps] [delay_ms] [lib_path]\n", argv[0]);
            return 1;
        }

        pid_t pid = atoi(argv[1]);
        double fromScale = atof(argv[2]);
        double toScale = atof(argv[3]);
        int steps = argc > 4 ? atoi(argv[4]) : 20;
        int delayMs = argc > 5 ? atoi(argv[5]) : 16;
        const char* libPath = argc > 6 ? argv[6] : "/Users/admin/teststrip-vm/gesture";

        if (fromScale <= 0 || toScale <= 0) {
            fprintf(stderr, "Scales must be positive\n");
            return 1;
        }

        initGesture(libPath);
        CGPoint center = getWindowCenter(pid);
        fprintf(stderr, "Window center: (%.0f, %.0f)\n", center.x, center.y);

        double totalMag = toScale / fromScale - 1.0;
        double perStep = totalMag / steps;

        fprintf(stderr, "Pinch: %.2f -> %.2f (total mag %.4f, %d steps, %dms delay)\n",
                fromScale, toScale, totalMag, steps, delayMs);

        // Begin (phase=1, mag=0)
        CGEventRef begin = createMagEvent(1, 0.0, center);
        if (begin) { CGEventPost(kCGSessionEventTap, begin); CFRelease(begin); }
        usleep(delayMs * 1000);

        // Changed (phase=2, cumulative magnification)
        for (int i = 1; i <= steps; i++) {
            double mag = perStep * i;
            CGEventRef ev = createMagEvent(2, mag, center);
            if (ev) { CGEventPost(kCGSessionEventTap, ev); CFRelease(ev); }
            usleep(delayMs * 1000);
        }

        // End (phase=4, final magnification)
        CGEventRef end = createMagEvent(4, totalMag, center);
        if (end) { CGEventPost(kCGSessionEventTap, end); CFRelease(end); }

        fprintf(stderr, "Done: %.2f -> %.2f via kCGSessionEventTap\n", fromScale, toScale);
    }
    return 0;
}

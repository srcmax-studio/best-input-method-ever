#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import "Lexicon.h"

static NSString *const EHBundleID = @"com.qian.inputmethod.englishhanzi";
static IMKServer *server;

static TISInputSourceRef CopyInputSource(void) {
    NSDictionary *filter = @{(__bridge NSString *)kTISPropertyInputSourceID: EHBundleID};
    CFArrayRef list = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true);
    if (!list || CFArrayGetCount(list) == 0) {
        if (list) CFRelease(list);
        return NULL;
    }
    TISInputSourceRef source = (TISInputSourceRef)CFRetain(CFArrayGetValueAtIndex(list, 0));
    CFRelease(list);
    return source;
}

static int RegisterInputSource(BOOL select) {
    OSStatus result = TISRegisterInputSource((__bridge CFURLRef)[[NSBundle mainBundle] bundleURL]);
    if (result != noErr) {
        fprintf(stderr, "TISRegisterInputSource failed: %d\n", (int)result);
        return 1;
    }
    TISInputSourceRef source = CopyInputSource();
    if (!source) {
        fprintf(stderr, "Registered bundle, but macOS has not listed the input source yet. Try logging out and back in.\n");
        return 2;
    }
    result = TISEnableInputSource(source);
    CFRelease(source);
    if (result != noErr) {
        fprintf(stderr, "Could not enable input source: %d\n", (int)result);
        return 3;
    }
    source = CopyInputSource();
    CFBooleanRef enabled = source ? TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) : NULL;
    if (enabled != kCFBooleanTrue) {
        if (source) CFRelease(source);
        puts("Registered, but not enabled yet. Add 英译中文 in System Settings > Keyboard > Input Sources.");
        return select ? 3 : 0;
    }
    if (select) result = TISSelectInputSource(source);
    CFRelease(source);
    if (result != noErr) {
        fprintf(stderr, "Could not select input source: %d\n", (int)result);
        return 3;
    }
    printf("EnglishHanZi input source %s.\n", select ? "enabled and selected" : "registered and enabled");
    return 0;
}

static int PrintStatus(void) {
    TISInputSourceRef source = CopyInputSource();
    if (!source) {
        puts("not registered");
        return 1;
    }
    CFBooleanRef enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled);
    CFBooleanRef canEnable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnableCapable);
    CFBooleanRef canSelect = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable);
    CFStringRef sourceType = TISGetInputSourceProperty(source, kTISPropertyInputSourceType);
    CFStringRef sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    CFBooleanRef selectedFlag = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelected);
    BOOL isSelected = selectedFlag == kCFBooleanTrue;
    printf("registered: yes\nsource id: %s\nsource type: %s\ncan enable: %s\ncan select: %s\nenabled: %s\nselected: %s\n",
           sourceID ? [(__bridge NSString *)sourceID UTF8String] : "(none)",
           sourceType ? [(__bridge NSString *)sourceType UTF8String] : "(none)",
           canEnable == kCFBooleanTrue ? "yes" : "no",
           canSelect == kCFBooleanTrue ? "yes" : "no",
           enabled == kCFBooleanTrue ? "yes" : "no", isSelected ? "yes" : "no");
    CFRelease(source);
    return 0;
}

static int Lookup(NSString *query, BOOL traditional) {
    EHLexicon *lexicon = [EHLexicon sharedLexicon];
    if (!lexicon.isReady) return 2;
    NSArray<EHEntry *> *entries = [lexicon lookup:query traditional:traditional limit:9];
    for (NSUInteger i = 0; i < entries.count; ++i) {
        EHEntry *entry = entries[i];
        printf("%lu\t%s\t%s\n", (unsigned long)(i + 1),
               [entry textForTraditional:traditional].UTF8String, entry.english.UTF8String);
    }
    return entries.count == 0 ? 1 : 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc >= 2) {
            NSString *command = [NSString stringWithUTF8String:argv[1]];
            if ([command isEqualToString:@"--register"]) return RegisterInputSource(NO);
            if ([command isEqualToString:@"--select"]) return RegisterInputSource(YES);
            if ([command isEqualToString:@"--status"]) return PrintStatus();
            if ([command isEqualToString:@"--lookup"] && argc >= 3)
                return Lookup([NSString stringWithUTF8String:argv[2]], YES);
            if ([command isEqualToString:@"--lookup-simplified"] && argc >= 3)
                return Lookup([NSString stringWithUTF8String:argv[2]], NO);
            fprintf(stderr, "Usage: EnglishHanZi [--register|--select|--status|--lookup WORD|--lookup-simplified WORD]\n");
            return 64;
        }
        [NSApplication sharedApplication];
        NSString *connection = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"InputMethodConnectionName"];
        server = [[IMKServer alloc] initWithName:connection bundleIdentifier:EHBundleID];
        if (!server) {
            NSLog(@"EnglishHanZi: failed to start IMKServer");
            return 1;
        }
        if (![EHLexicon sharedLexicon].isReady) {
            NSLog(@"EnglishHanZi: dictionary unavailable");
            return 2;
        }
        [NSApp run];
    }
    return 0;
}

#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 64;
        NSSize size = NSMakeSize(128, 128);
        NSImage *image = [[NSImage alloc] initWithSize:size];
        [image lockFocus];
        [[NSColor colorWithCalibratedRed:0.11 green:0.29 blue:0.60 alpha:1] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(4, 4, 120, 120) xRadius:27 yRadius:27] fill];
        NSDictionary *large = @{
            NSFontAttributeName: [NSFont systemFontOfSize:75 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: NSColor.whiteColor,
        };
        [@"中" drawAtPoint:NSMakePoint(27, 26) withAttributes:large];
        NSDictionary *small = @{
            NSFontAttributeName: [NSFont systemFontOfSize:22 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.82 green:0.93 blue:1 alpha:1],
        };
        [@"En" drawAtPoint:NSMakePoint(10, 89) withAttributes:small];
        [image unlockFocus];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}

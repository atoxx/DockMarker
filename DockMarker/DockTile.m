//
//  DockTile.m
//  DockMarker
//
//  Created by Serge Sander on 23.07.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import "DockTile.h"
#import "hacks.h"
#import "spaces.h"
#import "WindowInfoModel.h"
#import "UIElementUtilities.h"
#import "NSImage+Trim.h"
#import "AppDelegate.h"
#import <Foundation/Foundation.h>

extern NSWindow *openPicker;

@implementation DockTile
@synthesize img;
@synthesize indicator;
@synthesize myChildren;
@synthesize floater;

- (id) initWithFrame:(NSRect)frameRect{
    if(self = [super initWithFrame:frameRect]){
        self.wantsLayer = YES;
        [self setFrame:frameRect];
        self.wantsLayer = YES;
        indicator = [[NSView alloc] initWithFrame:NSMakeRect((frameRect.size.width - 30) / 2, 0, 30, 15)];
        indicator.wantsLayer = YES;
        [indicator.layer setBackgroundColor:[[NSColor redColor] CGColor]];
        [indicator.layer setCornerRadius:7];
        
        //NSRect frame = NSMakeRect(0, 0, 200, 200);
        NSRect frame = NSMakeRect((self.frame.origin.x) - 225, 250, 450, 200);
        NSRect frame2 = NSMakeRect(0, 0, 450, 200);
        floater = [[NSWindow alloc] initWithContentRect:frame styleMask:NSBorderlessWindowMask backing:0 defer:NO];
        [floater setBackgroundColor:[NSColor clearColor]];
        [floater setOpaque:NO];
        
        content = [[NSView alloc] initWithFrame:frame2];
        content.wantsLayer = YES;
        [content.layer setBackgroundColor:[[NSColor colorWithCalibratedRed:27/255 green:27/255 blue:27/255 alpha:1.0] CGColor]];
        [content.layer setCornerRadius:10];
        [floater setContentView:content];
        
        [floater setLevel:NSMainMenuWindowLevel +2];
        [floater setReleasedWhenClosed:NO];
        
        deleg = (AppDelegate*) [[NSApplication sharedApplication] delegate];
        [self addSubview:indicator];
    }
    return self;
}

- (void) viewDidMoveToWindow{
    track = [[NSTrackingArea alloc] initWithRect:[self bounds] options: (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:nil];
    [self addTrackingArea:track];
}
- (void) updateTA:(NSSize)size{
    NSRect rect;
    rect.origin = NSMakePoint(0, 0);
    rect.size = size;
    
    [self removeTrackingArea:track];
    track = [[NSTrackingArea alloc] initWithRect:rect options: (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:nil];
    [self addTrackingArea:track];


    [content removeTrackingArea:track2];
    NSMutableDictionary *info2 = [[NSMutableDictionary alloc] init];
    [info2 setValue:@"floater" forKey:@"owner"];
    rect.size = floater.frame.size;
    track2 = [[NSTrackingArea alloc] initWithRect:content.bounds options: (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:info2];
    [content addTrackingArea:track2];
}
-(void) mouseEntered:(NSEvent *)theEvent{
    myChildren = [deleg.WindowPreviews valueForKey:[self.values valueForKey:@"name"]];
    if (![openPicker isEqual:floater]){
        [openPicker close];
        openPicker = floater;
    }
    NSString *owner = [[[theEvent trackingArea] userInfo] valueForKey:@"owner"];
    if (!owner){
        NSRect frame = NSMakeRect(((self.frame.origin.x + 225) - ([myChildren count] * 455) / 2) - 100, 250, [myChildren count] * 455, 300);
        if (frame.origin.x < 0 ){
            frame.origin.x = 0;
        }
        [floater setFrame:frame display:YES];
        
        for (int x = 0; x < (int)[myChildren count]; x++){
            NSButton *shot = [[NSButton alloc] initWithFrame:NSMakeRect(10 + (x * 430), 10, 430, 280)];
            NSImage *preview = [self resizeImage:[[myChildren objectAtIndex:x] valueForKey:@"shot"] size:shot.frame.size];
            NSImage *new = [preview imageByTrimmingTransparentPixels];
            [shot setTag:[[[myChildren objectAtIndex:x] valueForKey:@"wid"] intValue]];
            [shot setImage:new];
            [shot setTarget:self];
            [shot setAction:@selector(raise:)];
            [shot setBordered:NO];
            [[shot cell] setImageScaling:NSImageScaleProportionallyUpOrDown];
            [content addSubview:shot];
            [shot acceptsFirstResponder];
            [floater makeFirstResponder:shot];
        }
        openPicker = floater;
        [floater makeKeyAndOrderFront:NSApp];
        
    } else {
        self.isactive = YES;
    }
}
-(void) raise : (id)sender{
    [self resetWindowInfo];
    NSButton *btn = sender;
    int wid = (int)btn.tag;
    [self switchWindow:wid];
    [floater close];
    
}
- (void) mouseExited:(NSEvent *)theEvent{
    NSString *owner = [[[theEvent trackingArea] userInfo] valueForKey:@"owner"];
    if (!owner){
        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
        dispatch_after(delay, dispatch_get_main_queue(), ^(void){
            if (self.isactive == NO){
                [floater close];
            }
        });
    } else {
        self.isactive = NO;
        [floater close];
    }
}
- (void) switchWindow : (int) pid{
    [[NSApplication sharedApplication] deactivate];
    //[self.window setLevel:NSNormalWindowLevel];
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        WindowInfoModel *model;
        for (WindowInfoModel *win in self.windowInfoArray){
            if(win.winId == pid){
                model = win;
                break;
            }
        }
        
        ProcessSerialNumber process;
        GetProcessForPID(pid, &process);
        SetFrontProcessWithOptions(&process, kSetFrontProcessFrontWindowOnly);
        AXUIElementRef uiEle = model.uiEle;
        AXUIElementPerformAction(uiEle, kAXRaiseAction);
        
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)model.pid];
        [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    });
    
}
- (NSImage*) resizeImage:(NSImage*)sourceImage size:(NSSize)size{
    
    NSRect targetFrame = NSMakeRect(0, 0, size.width, size.height);
    NSImage*  targetImage = [[NSImage alloc] initWithSize:size];
    
    NSSize sourceSize = [sourceImage size];
    
    float ratioH = size.height/ sourceSize.height;
    float ratioW = size.width / sourceSize.width;
    
    NSRect cropRect = NSZeroRect;
    if (ratioH >= ratioW) {
        cropRect.size.width = floor (size.width / ratioH);
        cropRect.size.height = sourceSize.height;
    } else {
        cropRect.size.width = sourceSize.width;
        cropRect.size.height = floor(size.height / ratioW);
    }
    
    cropRect.origin.x = floor( (sourceSize.width - cropRect.size.width)/2 );
    cropRect.origin.y = floor( (sourceSize.height - cropRect.size.height)/2 );
    
    
    
    [targetImage lockFocus];
    
    [sourceImage drawInRect:targetFrame
                   fromRect:cropRect       //portion of source image to draw
                  operation:NSCompositeCopy  //compositing operation
                   fraction:1.0              //alpha (transparency) value
             respectFlipped:YES              //coordinate system
                      hints:@{NSImageHintInterpolation:
                                  [NSNumber numberWithInt:NSImageInterpolationLow]}];
    
    [targetImage unlockFocus];
    
    return targetImage;
}
- (void)resetWindowInfo{
    
    NSMutableArray* newWindowInfoArray = [[NSMutableArray alloc] init];
    
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    
    CGWindowListOption option = kCGWindowListOptionAll;
    //    option |= kCGWindowListOptionOnScreenOnly;
    //    option |= kCGWindowListOptionOnScreenAboveWindow;
    //    option |= kCGWindowListOptionOnScreenBelowWindow;
    //    option |= kCGWindowListOptionIncludingWindow;
    option |= kCGWindowListExcludeDesktopElements;
    
    CFArrayRef windowList = CGWindowListCopyWindowInfo(option, kCGNullWindowID);
    
    for (int i = 0; i < CFArrayGetCount(windowList); i++) {
        BOOL flg = NO;
        CFDictionaryRef dict = CFArrayGetValueAtIndex(windowList, i);
        
        if ((int)CFDictionaryGetValue(dict, kCGWindowLayer) > 1000) {
            continue;
        }
        
        // pid
        CFNumberRef ownerPidRef = CFDictionaryGetValue(dict, kCGWindowOwnerPID);
        NSInteger ownerPid = [(__bridge_transfer NSNumber *)ownerPidRef integerValue];
        
        // winId
        NSNumber *winId = CFDictionaryGetValue(dict, kCGWindowNumber);
        
        // originalWinName
        CFStringRef n = CFDictionaryGetValue(dict, kCGWindowName);
        NSString *originalWinName = (__bridge_transfer NSString *) n;
        
        // alpha, layer
        NSNumber *alpha = CFDictionaryGetValue(dict, kCGWindowAlpha);
        NSNumber *layer = CFDictionaryGetValue(dict, kCGWindowLayer);
        if (!([layer integerValue] == 0 && [alpha integerValue] > 0)) continue;
        
        // owner
        //        CFStringRef ownerRef = CFDictionaryGetValue(dict, kCGWindowOwnerName);
        //        NSString *owner = (__bridge_transfer NSString *)ownerRef;
        
        // TODO: Check necessity of uiEleChildren
        // If the pid and the winID has same value as last model, the value of icon and appName, uiEle, uiEleChildren are copied from the last model.
        NSImage *icon = nil;
        NSString *appName = nil;
        AXUIElementRef uiEle = nil;
        NSDictionary* uiEleAttributes = nil;
        //        NSArray* uiEleChildren = nil;
        
        WindowInfoModel* sameWindowInfoAsLast = [self sameWindowInfoAsLastByPid:ownerPid winId:winId.integerValue];
        if (sameWindowInfoAsLast == nil) {
            icon = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
            
            for (NSRunningApplication* app in apps) {
                if (ownerPid == app.processIdentifier) {
                    // appName
                    appName = app.localizedName;
                    
                    // icon
                    [icon lockFocus];
                    [app.icon drawInRect:NSMakeRect(0, 0, icon.size.width, icon.size.height)
                                fromRect:NSMakeRect(0, 0, app.icon.size.width, app.icon.size.height)
                               operation:NSCompositeCopy
                                fraction:1.0f];
                    [icon unlockFocus];
                    flg = YES;
                    break;
                }
            }
            if (!flg) continue;
            
            // uiEle
            uiEle = [self AXUIElementRefByWinId:winId pid:ownerPid];
            
            // uiEleAttributes
            uiEleAttributes = [UIElementUtilities attributeDictionaryOfUIElement:uiEle];
            
            // subUiEle
            //            uiEleChildren = subElementsFromElement(uiEle);
        } else {
            icon = sameWindowInfoAsLast.icon;
            appName = sameWindowInfoAsLast.appName;
            uiEle = sameWindowInfoAsLast.uiEle;
            uiEleAttributes = sameWindowInfoAsLast.uiEleAttributes;
            //            uiEleChildren = sameWindowInfoAsLast.uiEleChildren;
        }
        
        // winName
        NSString *winName = (originalWinName == nil || [originalWinName isEqualToString:@""]) ? appName : originalWinName;
        
        // x, y, width, height
        CFDictionaryRef winBoundsRef = CFDictionaryGetValue(dict, kCGWindowBounds);
        NSDictionary *winBounds = (__bridge NSDictionary*)winBoundsRef;
        NSInteger x = [[winBounds objectForKey:@"X"] integerValue];
        NSInteger y = [[winBounds objectForKey:@"Y"] integerValue];
        NSInteger width = [[winBounds objectForKey:@"Width"] integerValue];
        NSInteger height = [[winBounds objectForKey:@"Height"] integerValue];
        
        // Set a model
        WindowInfoModel *model = [[WindowInfoModel alloc] init];
        model.key = @"";
        
        model.icon = icon;
        
        model.originalWinName = originalWinName;
        model.winName = winName;
        model.appName = appName;
        model.winId = winId.integerValue;
        model.pid = ownerPid;
        
        model.uiEle = uiEle;
        model.uiEleAttributes = uiEleAttributes;
        //        model.uiEleChildren = uiEleChildren;
        
        model.x = x;
        model.y = y;
        model.width = width;
        model.height = height;
        
        [newWindowInfoArray addObject:model];
    }
    
    self.lastAllWindowInfoArray = [newWindowInfoArray mutableCopy];
    
    self.windowInfoArray = [newWindowInfoArray mutableCopy];
}
- (WindowInfoModel*)sameWindowInfoAsLastByPid:(NSInteger)pid winId:(NSInteger)winId{
    for (WindowInfoModel *lastModel in self.windowInfoArray) {
        if (lastModel.pid == pid && lastModel.winId == winId) {
            return lastModel;
        }
    }
    return nil;
}
- (AXUIElementRef)AXUIElementRefByWinId:(NSNumber*)modelWinId pid:(NSInteger)modelPid{
    CGWindowID win_id = (int)[modelWinId integerValue];
    
    int pid = (int)modelPid;
    
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFArrayRef appwindows;
    AXUIElementCopyAttributeValues(app, kAXWindowsAttribute, 0, 1000, &appwindows);
    if (appwindows) {
        for (id w in (__bridge NSArray*)appwindows) {
            AXUIElementRef win = (__bridge AXUIElementRef)w;
            CGWindowID tmp;
            _AXUIElementGetWindow(win, &tmp);
            if (tmp == win_id) {
                return win;
            }
        }
        CFRelease(appwindows);
    }
    CFRelease(app);
    return nil;
}

@end

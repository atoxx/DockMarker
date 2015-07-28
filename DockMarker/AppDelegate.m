//
//  AppDelegate.m
//  DockMarker
//
//  Created by Serge Sander on 16.06.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import "AppDelegate.h"
#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>
#import "DockTile.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import "MainView.h"
#import "hacks.h"
#import "spaces.h"
#import "WindowInfoModel.h"
#import "UIElementUtilities.h"
#import <ApplicationServices/ApplicationServices.h>

#pragma mark Basic Profiling Tools
// Set to 1 to enable basic profiling. Profiling information is logged to console.
#ifndef PROFILE_WINDOW_GRAB
#define PROFILE_WINDOW_GRAB 0
#endif

#if PROFILE_WINDOW_GRAB
#define StopwatchStart() AbsoluteTime start = UpTime()
#define Profile(img) CFRelease(CGDataProviderCopyData(CGImageGetDataProvider(img)))
#define StopwatchEnd(caption) do { Duration time = AbsoluteDeltaToDuration(UpTime(), start); double timef = time < 0 ? time / -1000000.0 : time / 1000.0; NSLog(@"%s Time Taken: %f seconds", caption, timef); } while(0)
#else
#define StopwatchStart()
#define Profile(img)
#define StopwatchEnd(caption)
#endif


CFMachPortRef eventPort;
extern NSWindow *openPicker;
extern BOOL ignoreThisWindow;

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
- (IBAction)saveAction:(id)sender;

@end

static void receivedNotification(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void *refcon) {
    pid_t pid = 0;
    AXUIElementGetPid(element, &pid);
    ProcessSerialNumber process;
    GetProcessForPID(pid, &process);
    [(__bridge AppDelegate *)refcon receivedNotification:(__bridge NSString *)notification process:&process element:element];
}

@implementation AppDelegate
@synthesize AltDockTile;
@synthesize timer;
@synthesize eventTap;
@synthesize RunningTiles;
@synthesize TotalWindowsCount;
@synthesize WindowPreviews;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    TotalWindowsCount = 0;
    WindowPreviews = [[NSMutableDictionary alloc] init];
    BackupDict = [[NSMutableDictionary alloc] init];
    RunningTiles = [[NSMutableArray alloc] init];
    
    [self.window setFrame:NSMakeRect(0, -15, [[NSScreen mainScreen] frame].size.width, 200) display:YES];
    view = [[MainView alloc] initWithFrame:self.window.frame];
    view.wantsLayer = NO;
    
    [self.window setLevel:NSMainMenuWindowLevel + 1];
    [self.window setContentView:view];
    [self.window setOpaque:NO];
    [self.window setBackgroundColor:[NSColor clearColor]];
    [self.window makeKeyAndOrderFront:self];
    
    [self buildTiles];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(newApp:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(appDidActivate:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
   [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(reFocus:) name:NSWorkspaceDidActivateApplicationNotification object:nil];
    NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
    [nc addObserver:self selector:@selector(reFocus:) name:NSWorkspaceActiveSpaceDidChangeNotification object:[NSWorkspace sharedWorkspace]];

    isNotFS = [self getFrontMostWindow];
    
    // Event Tap
    @synchronized(self)
    {
        CGEventMask theEventMask = CGEventMaskBit(kCGEventMouseMoved) |
        CGEventMaskBit(kCGEventKeyDown);
        
        theEventTap = CGEventTapCreate( kCGSessionEventTap,
                                       kCGHeadInsertEventTap,
                                       0,
                                       theEventMask,
                                       MouseTapCallback,
                                       (__bridge void *)self) ;
        
        
        if( !theEventTap )
        {
            NSLog( @"Failed to create event tap!" );
        }
        
        CFRunLoopSourceRef theRunLoopSource =
        CFMachPortCreateRunLoopSource( kCFAllocatorDefault, theEventTap, 0);
        
        CFRunLoopAddSource( CFRunLoopGetCurrent(),
                           theRunLoopSource,
                           kCFRunLoopCommonModes);
        CGEventTapEnable(theEventTap, true);
        self.eventTap = eventTap;
    }
    eventPort = theEventTap;
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        [self looper];
    });
    for (NSMutableDictionary *tile in RunningTiles){
        NSString *name = [[tile valueForKey:@"vals"] valueForKey:@"name"];
        [self getAllWindow:name];
        
        // Simulate Mouse Click
          
    }
    [self registerForAXEvents];
}

CGEventRef MouseTapCallback( CGEventTapProxy aProxy, CGEventType aType, CGEventRef aEvent, void* aRefcon ){
    AppDelegate *self = (__bridge AppDelegate *)(aRefcon);
    if(aType == kCGEventTapDisabledByTimeout || aType == kCGEventTapDisabledByUserInput) {
        NSLog(@"got kCGEventTapDisabledByTimeout, reenabling tap");
        CGEventTapEnable(eventPort, TRUE);
        return aEvent; // NULL also works
    }
    CGPoint point = CGEventGetLocation(aEvent);
    
    NSRect Screen = [NSScreen mainScreen].frame;
    
    CGRect area = CGRectMake(0, Screen.size.height - 200, Screen.size.width, 200);
    
    if (CGRectContainsPoint(area, point )) {
        if (!self.timer){
            self.timer = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(looper) userInfo:nil repeats:YES];
        }
    } else {
        if (self.timer){
            dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 1);
            dispatch_after(delay, dispatch_get_main_queue(), ^(void){
                [self.timer invalidate];
                self.timer = nil;
            });
        }
    }
    return aEvent;
}
- (void)appDidActivate:(NSNotification *)notification {
    [timer invalidate];
    [RunningTiles removeAllObjects];
    [view.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    
    [self buildTiles];
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        timer = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(looper) userInfo:nil repeats:YES];
    });
}
- (void)newApp:(NSNotification *)notification {
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        [self buildTiles];
        [self registerForAXEvents];
        [self receivedNotification:@"AXWindowCreated" process:nil element:nil];
    });
}
- (void)reFocus:(NSNotification *)notification {
    isNotFS = [self getFrontMostWindow];
    if (isNotFS == YES){
        [self.window orderOut:self];
    } else {
        if (self.window.isVisible == NO){
            [self.window orderFront:self];
        }
    }
    
}
-(void) looper{
    for (NSMutableDictionary *tile in RunningTiles){
        NSRect frame = [self appDockIconByName:[[tile valueForKey:@"vals"] valueForKey:@"name"]];
        if ([[tile valueForKey:@"vals"] valueForKey:@"name"]){
            NSRect TAR = frame;
            TAR.size.height += 0;
            frame.origin.y = 15;
            //frame.size.height = 15;
            DockTile *SubView = [tile valueForKey:@"tile"];
            if (SubView){
                [[SubView animator] setFrame:frame];
                [SubView updateTA:TAR.size];
                [SubView.indicator setFrame:NSMakeRect((frame.size.width - 30) / 2, 0, 30, 15)];
            }
        }
    }
}
- (void)applicationDidTerminate:(NSNotification *)theNotification {
    NSNumber *pidNumber = [[theNotification userInfo] objectForKey:@"NSApplicationProcessIdentifier"];
    AXObserverRef observer = (AXObserverRef)CFBridgingRetain([observers objectForKey:pidNumber]);
    if (observer!=NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);
        [observers removeObjectForKey:pidNumber];
    }
}
- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    NSArray *keys = [observers allKeys];
    for (int i=0; i<[keys count]; i++) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource((AXObserverRef)CFBridgingRetain([observers objectForKey:[keys objectAtIndex:i]])), kCFRunLoopDefaultMode);
    }
}
- (NSMutableArray*) getList{
    NSMutableArray *idedApps = [[NSMutableArray alloc] init];
    NSWorkspace * ws = [NSWorkspace sharedWorkspace];
    NSArray * apps = [ws runningApplications];
    NSMutableArray *names = [[NSMutableArray alloc] init];
    
    NSUInteger count = [apps count];
    for (NSUInteger i = 0; i < count; i++) {
        NSRunningApplication *app = [apps objectAtIndex: i];
        
        if(app.activationPolicy == NSApplicationActivationPolicyRegular) {
            [idedApps addObject:app];
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            [dict setValue:app.localizedName forKey:@"name"];
            [dict setValue:app.bundleIdentifier forKey:@"id"];
            [dict setValue:[self imageResize:[NSImage imageNamed:@"run"] newSize:NSMakeSize(50, 50)] forKey:@"icon"];
            [names addObject:dict];
        }
    }
    return names;
}

- (NSArray *)subelementsFromElement:(AXUIElementRef)element forAttribute:(NSString *)attribute{
    CFArrayRef *subElements = nil;
    CFIndex count = 0;
    AXError result;
    
    result = AXUIElementGetAttributeValueCount(element, (__bridge CFStringRef)attribute, &count);
    if (result != kAXErrorSuccess) return nil;
    result = AXUIElementCopyAttributeValues(element, (__bridge CFStringRef)attribute, 0, count, (CFArrayRef *)&subElements);
    if (result != kAXErrorSuccess) return nil;
    
    CFArrayRef someArrayRef = subElements;
    NSArray *array = (__bridge NSArray*)someArrayRef;
    return array;
}
- (NSRect)appDockIconByName:(NSString *)appName{
    AXUIElementRef appElement = NULL;
    AXUIElementRef axElement;
    NSRect rect;
    CFTypeRef value;
    
    appElement = AXUIElementCreateApplication([[[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"] lastObject] processIdentifier]);
    
    if (appElement != NULL)
    {
        
        AXUIElementRef firstChild = (__bridge AXUIElementRef)[[self subelementsFromElement:appElement forAttribute:@"AXChildren"] objectAtIndex:0];
        NSArray *children = [self subelementsFromElement:firstChild forAttribute:@"AXChildren"];
        NSEnumerator *e = [children objectEnumerator];
        
        while (axElement = (__bridge AXUIElementRef)[e nextObject])
        {
            CFTypeRef value;
            id titleValue;
            AXError result = AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute, &value);
            if (result == kAXErrorSuccess)
            {
                if (AXValueGetType(value) != kAXValueIllegalType)
                    titleValue = [NSValue valueWithPointer:value];
                else
                    titleValue = (__bridge id)value; // assume toll-free bridging
                if ([titleValue isEqual:appName]) {
                    CFRelease(firstChild);
                    
                    break;
                }
            }
        }
        // get size
        AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute, (CFTypeRef *) &value);
        AXValueGetValue(value, kAXValueCGSizeType, (void *) &rect.size);
        CFRelease(value);
        
        // get position
        AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute, (CFTypeRef*) &value);
        AXValueGetValue(value, kAXValueCGPointType, (void *) &rect.origin);
        CFRelease(value);
        
        CFRelease(axElement);
        CFRelease(appElement);
        
    }
    return rect;
}

-(bool) getFrontMostWindow{
    NSWorkspace * ws = [NSWorkspace sharedWorkspace];
    NSArray * apps = [ws runningApplications];
    BOOL isFinder = NO;
    NSArray *exits = [self excludedApps];
    for (NSRunningApplication *app in apps){
        if (app.isActive == YES){
            NSString *name = app.localizedName;
            BOOL isEx = [exits containsObject:name];
            if ([name isEqualToString:@"Finder"]){
                isFinder = YES;
                return NO;
            } else if (isEx == YES){
                return YES;
            }
            break;
        }
    }
    system = nil;
    system = AXUIElementCreateSystemWide();
    CFTypeRef application = nil;
    AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute, &application);
    CFTypeRef focusedWindow = nil;
    AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute, &focusedWindow);
    AXValueRef value;
    
    NSRect rect; // dock rect
    AXUIElementCopyAttributeValue(focusedWindow, kAXSizeAttribute, (CFTypeRef *) &value);
    if (focusedWindow){
        AXValueGetValue(value, kAXValueCGSizeType, (void *) &rect.size);
        // get position
        AXUIElementCopyAttributeValue(focusedWindow, kAXPositionAttribute, (CFTypeRef*) &value);
        AXValueGetValue(value, kAXValueCGPointType, (void *) &rect.origin);
        
        CFRelease(application);
        
        if (NSEqualRects(rect, [[NSScreen mainScreen] frame]) == YES){
            CFRelease(focusedWindow);
            CFRelease(value);
            if (isFinder == YES){
                return NO;
            } else {
                return YES;
            }
        } else {
            CFRelease(focusedWindow);
            CFRelease(value);
            return NO;
        }
    }
    
    return NO;
}
- (void) buildTiles{
    NSMutableArray *names = [self getList];
    
    for (NSDictionary *name in names){
        NSRect rect = [self appDockIconByName:[name valueForKey:@"name"]]; // dock rect
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                [dict setValue:[NSValue valueWithRect:rect] forKey:@"rect"];
        [dict setValue:[name valueForKey:@"icon"] forKey:@"icon"];
        [dict setValue:[name valueForKey:@"name"] forKey:@"name"];
        
        DockTile *tile = [[DockTile alloc] initWithFrame:rect];
        tile.values = dict;
        NSMutableDictionary *final = [[NSMutableDictionary alloc] init];
        [final setObject:tile forKey:@"tile"];
        [final setValue:name forKey:@"vals"];
        [RunningTiles addObject:final];
    }
    
    for (NSMutableDictionary *sub in RunningTiles){
        DockTile *ele = [sub valueForKey:@"tile"];
        [view addSubview:ele];
    }
}
- (void) getAllWindow : (NSString*) ownerName {
    listOfWindows = CGWindowListCopyWindowInfo(kCGWindowListExcludeDesktopElements | kCGWindowListOptionAll,kCGNullWindowID );
    array = (__bridge NSArray*)listOfWindows;
    
    id CGSCopyManagedDisplaySpaces(int conn);
    int _CGSDefaultConnection();
    
    id CGSCopyManagedDisplaySpaces(int conn);
    int _CGSDefaultConnection();
    id CGSCopyWindowsWithOptionsAndTags(int conn, unsigned owner, NSArray *spids, unsigned options, unsigned long long *setTags, unsigned long long *clearTags);
    
    int conn = _CGSDefaultConnection();
    
    NSMutableArray *allWindow = [[NSMutableArray alloc] init];
    for (int x = 0; x < total_spaces(); x++){
        NSArray *info = CGSCopyManagedDisplaySpaces(conn);
        unsigned long long setTags = 0, clearTags = 0x4000000000;
        int displayNumber = 0;
        NSNumber *spaceID = info[displayNumber][@"Spaces"][x][@"id64"];
        NSArray *windows = CGSCopyWindowsWithOptionsAndTags(conn, 0, @[spaceID], 2, &setTags, &clearTags);
        [allWindow addObjectsFromArray:windows];
    }
    
    NSMutableArray *cleaned = [[NSMutableArray alloc] init];
    for (NSNumber *nr in allWindow){
        CGWindowLevel level;
        CGSGetWindowLevel(conn, [nr intValue], &level);
        if (level == 0){
            [cleaned addObject:nr];
        }
    }
    
    NSMutableArray *dataArray = [[NSMutableArray alloc] init];
    NSMutableArray *infos = [[NSMutableArray alloc] init];
    
    for (NSNumber *nr in cleaned){
        for (NSDictionary *dict in array){
            int wid = [dict[(id)kCGWindowNumber] intValue];
            
            if (wid == [nr intValue]){
                int wid = [dict[(id)kCGWindowNumber] intValue];
                NSString *name = dict[(id) kCGWindowOwnerName];
                BOOL gotten = [cleaned containsObject:[[NSNumber alloc] initWithInt:wid]];
                NSNumber *check = [[NSNumber alloc] initWithInt:wid];
                if ([cleaned containsObject:check] == YES && [name isEqualToString:ownerName] && gotten == YES){
                    [infos addObject:dict];
                }
            }
        }
    }
    if ([infos count] == 0){
        //NSLog(@"Breaking on %@",ownerName);
        return;
    }
    BOOL isNew = YES;
    for (NSMutableDictionary *dict in infos){
        NSNumber *wid = [[NSNumber alloc] initWithInt:[dict[(id)kCGWindowNumber] intValue]];
        id contained = [BackupDict objectForKey:[NSString stringWithFormat:@"%@",wid]];
        if (!contained){
            isNew = YES;
            break;
        } else {
            isNew = NO;
            break;
        }
    }
    //NSLog(isNew ? @"Yes" : @"No");
    for (NSDictionary *dict in infos){
        if (isNew == YES){
            //NSLog(@"added");
            // Create New Tile
            CGRect bounds;
            CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)dict[(id)kCGWindowBounds], &bounds);
            NSString *owner = dict[(id)kCGWindowOwnerName];
            
            if ([owner isEqualToString:ownerName]){
                NSMutableDictionary *vals = [[NSMutableDictionary alloc] init];
                CGWindowID windowID = [dict[(id)kCGWindowNumber] unsignedIntValue];
                pid_t ProcessID = [dict[(id)kCGWindowOwnerPID] unsignedIntValue];
                NSNumber *pidNr = [[NSNumber alloc] initWithInt:ProcessID];
                
                NSArray *wins = [[NSArray alloc] initWithObjects:[[NSNumber alloc] initWithInt:windowID], nil];
                NSImage *image = [self resizeImage:[self createMultiWindowShot:wins] size:NSMakeSize(400, 300)];
                if (image){
                    [vals setValue:[[NSNumber alloc] initWithInt:windowID] forKey:@"wid"];
                    [vals setValue:image forKey:@"shot"];
                    [vals setValue:pidNr forKey:@"pid"];
                    BOOL isNew = YES;
                    for (NSDictionary *ele in dataArray){
                        if ([[ele valueForKey:@"wid"] intValue] == windowID){
                            isNew = NO;
                            break;
                        }
                    }
                    if (isNew == YES){
                        [dataArray addObject:vals];
                    }
                }
                
            }
        } else {
            // Add existing one
            //NSLog(@"old added");
            NSNumber *wid = [[NSNumber alloc] initWithInt:[dict[(id)kCGWindowNumber] intValue]];
            NSMutableDictionary *old = [BackupDict valueForKey:[NSString stringWithFormat:@"%i",[wid intValue]]];
            [dataArray addObject:old];
        }
    }
    NSLog(@"%lu Windows for %@",(unsigned long)[dataArray count],ownerName);
    for (NSMutableDictionary *dict in dataArray){
        NSNumber *tmp = [dict valueForKey:@"wid"];
        id contained = [BackupDict valueForKey:[NSString stringWithFormat:@"%@",tmp]];
        if (!contained){
            [BackupDict setObject:dict forKey:[NSString stringWithFormat:@"%@",tmp]];
        }
    }
    if ([dataArray count] != 0){
        [WindowPreviews setValue:dataArray forKey:ownerName];
    }
}
-(int) getWindowsCount{
    listOfWindows = CGWindowListCopyWindowInfo(kCGWindowListExcludeDesktopElements | kCGWindowListOptionAll,kCGNullWindowID );
    array = (__bridge NSArray*)listOfWindows;
    id CGSCopyManagedDisplaySpaces(int conn);
    int _CGSDefaultConnection();
    
    id CGSCopyManagedDisplaySpaces(int conn);
    int _CGSDefaultConnection();
    id CGSCopyWindowsWithOptionsAndTags(int conn, unsigned owner, NSArray *spids, unsigned options, unsigned long long *setTags, unsigned long long *clearTags);
    
    int conn = _CGSDefaultConnection();
    
    NSMutableArray *allWindow = [[NSMutableArray alloc] init];
    for (int x = 0; x < total_spaces(); x++){
        NSArray *info = CGSCopyManagedDisplaySpaces(conn);
        unsigned long long setTags = 0, clearTags = 0x4000000000;
        int displayNumber = 0;
        NSNumber *spaceID = info[displayNumber][@"Spaces"][x][@"id64"];
        NSArray *windows = CGSCopyWindowsWithOptionsAndTags(conn, 0, @[spaceID], 2, &setTags, &clearTags);
        [allWindow addObjectsFromArray:windows];
    }
    NSMutableArray *cleaned = [[NSMutableArray alloc] init];
    for (NSNumber *nr in allWindow){
        CGWindowLevel level;
        CGSGetWindowLevel(conn, [nr intValue], &level);
        if (level == 0){
            [cleaned addObject:nr];
        }
    }
    CFRelease(listOfWindows);
    
    return (int)[cleaned count];
}
- (void) registerForAXEvents{
    observers = [NSMutableDictionary new];
    NSArray *applications = [[NSWorkspace sharedWorkspace] launchedApplications];
    for (int i=0; i<[applications count]; i++) {
        NSNumber *pidNumber = [[applications objectAtIndex:i] objectForKey:@"NSApplicationProcessIdentifier"];
        if ([pidNumber intValue]!=getpid()) {
            pid_t pid = (pid_t)[pidNumber intValue];
            AXObserverRef observer;
            
            if (AXObserverCreate(pid, receivedNotification, &observer)==kAXErrorSuccess) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);
                AXUIElementRef element = AXUIElementCreateApplication(pid);
                [self observe:kAXFocusedWindowChangedNotification element:element observer:observer application:[applications objectAtIndex:i]];
                [observers setObject:(__bridge id)observer forKey:pidNumber];
                
                [self observe:kAXWindowCreatedNotification element:element observer:observer application:[applications objectAtIndex:i]];
                [observers setObject:(__bridge id)observer forKey:pidNumber];
                
                [self observe:kAXUIElementDestroyedNotification element:element observer:observer application:[applications objectAtIndex:i]];
                [observers setObject:(__bridge id)observer forKey:pidNumber];
                
                [self observe:kAXWindowMiniaturizedNotification element:element observer:observer application:[applications objectAtIndex:i]];
                [observers setObject:(__bridge id)observer forKey:pidNumber];
                
                [self observe:kAXWindowDeminiaturizedNotification element:element observer:observer application:[applications objectAtIndex:i]];
                [observers setObject:(__bridge id)observer forKey:pidNumber];
                
                CFRelease(observer);
                CFRelease(element);
                
        }
    }
    //AXObserverAddNotification( observer, frontWindow, kAXFocusedWindowChangedNotification, (__bridge void *)(self) );
    }
}
- (void)observe:(CFStringRef)theNotification element:(AXUIElementRef)theElement observer:(AXObserverRef)theObserver application:(NSDictionary *)theApplication {
    if (AXObserverAddNotification(theObserver, theElement, theNotification, (__bridge void *)(self))!=kAXErrorSuccess)
        NSLog(@"error");
}
- (void)receivedNotification:(NSString *)theName process:(ProcessSerialNumber *)theProcess element:(AXUIElementRef)theElement {
    NSLog(@"%@",theName);
    int cnt = [self getWindowsCount];;
    if ((cnt != TotalWindowsCount && ignoreThisWindow == NO) || [theName isEqualToString:@"AXWindowCreated"] || [theName isEqualToString:@"AXUIElementDestroyed"]  || [theName isEqualToString:@"AXWindowMiniaturized"]){
        //NSLog(@"UPDATING ...");
        TotalWindowsCount = cnt;
        [WindowPreviews removeAllObjects];
        for (NSMutableDictionary *tile in RunningTiles){
            NSString *name = [[tile valueForKey:@"vals"] valueForKey:@"name"];
            [self getAllWindow:name];
        }
    }
}
- (NSArray*) excludedApps{
    NSArray *excl = [[NSArray alloc] initWithObjects:
                     @"VLC",
                     @"Plex",
                     
                      nil];
    return excl;
}






#pragma mark - ######### Image Tools ###########
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
- (NSImage *)imageResize:(NSImage*)anImage newSize:(NSSize)newSize{
    NSImage *sourceImage = anImage;
    [sourceImage setScalesWhenResized:YES];
    
    // Report an error if the source isn't a valid image
    if (![sourceImage isValid])
    {
        NSLog(@"Invalid Image");
    } else
    {
        NSImage *smallImage = [[NSImage alloc] initWithSize: newSize];
        [smallImage lockFocus];
        [sourceImage setSize: newSize];
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
        //[sourceImage compositeToPoint:NSZeroPoint operation:NSCompositeCopy];
        [sourceImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeCopy fraction:1];
        [smallImage unlockFocus];
        return smallImage;
    }
    return nil;
}

# pragma mark - ######### Shot Helpers #############
enum{
    // Constants that correspond to the rows in the
    // Single Window Option matrix.
    kSingleWindowAboveOnly = 0,
    kSingleWindowAboveIncluded = 1,
    kSingleWindowOnly = 2,
    kSingleWindowBelowIncluded = 3,
    kSingleWindowBelowOnly = 4,
};
// to the appropriate CGWindowListOption.
-(CGWindowListOption)singleWindowOption : (int) mode{
    CGWindowListOption option = 0;
    switch(mode)
    {
        case kSingleWindowAboveOnly:
            option = kCGWindowListOptionOnScreenAboveWindow;
            break;
            
        case kSingleWindowAboveIncluded:
            option = kCGWindowListOptionOnScreenAboveWindow | kCGWindowListOptionIncludingWindow;
            break;
            
        case kSingleWindowOnly:
            option = kCGWindowListOptionIncludingWindow;
            break;
            
        case kSingleWindowBelowIncluded:
            option = kCGWindowListOptionOnScreenBelowWindow | kCGWindowListOptionIncludingWindow;
            break;
            
        case kSingleWindowBelowOnly:
            option = kCGWindowListOptionOnScreenBelowWindow;
            break;
            
        default:
            break;
    }
    return option;
}
-(NSImage*)createSingleWindowShot:(CGWindowID)windowID : (CGRect) imageBounds{
    StopwatchStart();
    CGImageRef windowImage = CGWindowListCreateImage(imageBounds, singleWindowListOptions, windowID, imageOptions);
    Profile(windowImage);
    StopwatchEnd("Single Window");
    
    // Create a bitmap rep from the image...
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:windowImage];
    // Create an NSImage and add the bitmap rep to it...
    NSImage *image = [[NSImage alloc] init];
    [image addRepresentation:bitmapRep];
    CGImageRelease(windowImage);
    
    return image;
}
-(NSImage*)createMultiWindowShot:(NSArray*)selection{
    CFArrayRef windowIDs = [self newWindowListFromSelection:selection];
    
    StopwatchStart();
    CGRect imageBounds = CGRectMake(0, 0, [[NSScreen mainScreen] frame].size.width, [[NSScreen mainScreen] frame].size.height);
    CGImageRef windowImage = CGWindowListCreateImageFromArray(imageBounds, windowIDs, imageOptions);
    Profile(windowImage);
    StopwatchEnd("Multiple Window");
    
    // Create a bitmap rep from the image...
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:windowImage];
    // Create an NSImage and add the bitmap rep to it...
    NSImage *image = [[NSImage alloc] init];
    [image addRepresentation:bitmapRep];
    CFRelease(windowIDs);
    CGImageRelease(windowImage);
    
    return image;
}

#pragma mark Window List & Window Image Methods
NSString *kAppNameKey = @"applicationName";	// Application Name & PID
NSString *kWindowOriginKey = @"windowOrigin";	// Window Origin as a string
NSString *kWindowSizeKey = @"windowSize";		// Window Size as a string
NSString *kWindowIDKey = @"windowID";			// Window ID
NSString *kWindowLevelKey = @"windowLevel";	// Window Level
NSString *kWindowOrderKey = @"windowOrder";	// The overall front-to-back ordering of the windows as returned by the window
-(CFArrayRef)newWindowListFromSelection:(NSArray*)selection{
    // Now we Collect the CGWindowIDs from the sorted selection
    int count = (int)[selection count];
    const void *windowIDs[count];
    int i = 0;
    for(NSNumber *entry in selection)
    {
        windowIDs[i++] = [entry intValue];
    }
    CFArrayRef windowIDsArray = CFArrayCreate(kCFAllocatorDefault, (const void**)windowIDs, [selection count], NULL);
    
    // And send our new array on it's merry way
    return windowIDsArray;
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




















#pragma mark - Core Data stack

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

- (NSURL *)applicationDocumentsDirectory {
    // The directory the application uses to store the Core Data store file. This code uses a directory named "dockmarker.DockMarker" in the user's Application Support directory.
    NSURL *appSupportURL = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    return [appSupportURL URLByAppendingPathComponent:@"dockmarker.DockMarker"];
}

- (NSManagedObjectModel *)managedObjectModel {
    // The managed object model for the application. It is a fatal error for the application not to be able to find and load its model.
    if (_managedObjectModel) {
        return _managedObjectModel;
    }
	
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"DockMarker" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    // The persistent store coordinator for the application. This implementation creates and return a coordinator, having added the store for the application to it. (The directory for the store is created, if necessary.)
    if (_persistentStoreCoordinator) {
        return _persistentStoreCoordinator;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *applicationDocumentsDirectory = [self applicationDocumentsDirectory];
    BOOL shouldFail = NO;
    NSError *error = nil;
    NSString *failureReason = @"There was an error creating or loading the application's saved data.";
    
    // Make sure the application files directory is there
    NSDictionary *properties = [applicationDocumentsDirectory resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&error];
    if (properties) {
        if (![properties[NSURLIsDirectoryKey] boolValue]) {
            failureReason = [NSString stringWithFormat:@"Expected a folder to store application data, found a file (%@).", [applicationDocumentsDirectory path]];
            shouldFail = YES;
        }
    } else if ([error code] == NSFileReadNoSuchFileError) {
        error = nil;
        [fileManager createDirectoryAtPath:[applicationDocumentsDirectory path] withIntermediateDirectories:YES attributes:nil error:&error];
    }
    
    if (!shouldFail && !error) {
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
        NSURL *url = [applicationDocumentsDirectory URLByAppendingPathComponent:@"OSXCoreDataObjC.storedata"];
        if (![coordinator addPersistentStoreWithType:NSXMLStoreType configuration:nil URL:url options:nil error:&error]) {
            coordinator = nil;
        }
        _persistentStoreCoordinator = coordinator;
    }
    
    if (shouldFail || error) {
        // Report any error we got.
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[NSLocalizedDescriptionKey] = @"Failed to initialize the application's saved data";
        dict[NSLocalizedFailureReasonErrorKey] = failureReason;
        if (error) {
            dict[NSUnderlyingErrorKey] = error;
        }
        error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:9999 userInfo:dict];
        [[NSApplication sharedApplication] presentError:error];
    }
    return _persistentStoreCoordinator;
}

- (NSManagedObjectContext *)managedObjectContext {
    // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.)
    if (_managedObjectContext) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (!coordinator) {
        return nil;
    }
    _managedObjectContext = [[NSManagedObjectContext alloc] init];
    [_managedObjectContext setPersistentStoreCoordinator:coordinator];

    return _managedObjectContext;
}

#pragma mark - Core Data Saving and Undo support

- (IBAction)saveAction:(id)sender {
    // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
    if (![[self managedObjectContext] commitEditing]) {
        NSLog(@"%@:%@ unable to commit editing before saving", [self class], NSStringFromSelector(_cmd));
    }
    
    NSError *error = nil;
    if ([[self managedObjectContext] hasChanges] && ![[self managedObjectContext] save:&error]) {
        [[NSApplication sharedApplication] presentError:error];
    }
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
    return [[self managedObjectContext] undoManager];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    // Save changes in the application's managed object context before the application terminates.
    
    if (!_managedObjectContext) {
        return NSTerminateNow;
    }
    
    if (![[self managedObjectContext] commitEditing]) {
        NSLog(@"%@:%@ unable to commit editing to terminate", [self class], NSStringFromSelector(_cmd));
        return NSTerminateCancel;
    }
    
    if (![[self managedObjectContext] hasChanges]) {
        return NSTerminateNow;
    }
    
    NSError *error = nil;
    if (![[self managedObjectContext] save:&error]) {

        // Customize this code block to include application-specific recovery steps.              
        BOOL result = [sender presentError:error];
        if (result) {
            return NSTerminateCancel;
        }

        NSString *question = NSLocalizedString(@"Could not save changes while quitting. Quit anyway?", @"Quit without saves error question message");
        NSString *info = NSLocalizedString(@"Quitting now will lose any changes you have made since the last successful save", @"Quit without saves error question info");
        NSString *quitButton = NSLocalizedString(@"Quit anyway", @"Quit anyway button title");
        NSString *cancelButton = NSLocalizedString(@"Cancel", @"Cancel button title");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:question];
        [alert setInformativeText:info];
        [alert addButtonWithTitle:quitButton];
        [alert addButtonWithTitle:cancelButton];

        NSInteger answer = [alert runModal];
        
        if (answer == NSAlertFirstButtonReturn) {
            return NSTerminateCancel;
        }
    }

    return NSTerminateNow;
}

@end

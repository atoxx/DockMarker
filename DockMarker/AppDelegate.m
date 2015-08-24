//
//  AppDelegate.m
//  DockMarker
//
//  Created by Serge Sander on 16.06.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import "AppDelegate.h"
#import <AppKit/AppKit.h>
#import "DockTile.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import "MainView.h"
#import "WindowInfoModel.h"
#import "UIElementUtilities.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

CFMachPortRef eventPort;

@interface AppDelegate ()

@property (retain) IBOutlet NSWindow *window;
- (IBAction)saveAction:(id)sender;

@end

@implementation AppDelegate
@synthesize timer;
@synthesize eventTap;
@synthesize RunningTiles;
@synthesize TotalWindowsCount;
@synthesize WindowPreviews;
@synthesize DockSettings;
@synthesize LoopCounter;
@synthesize indicatorColor;
@synthesize IndicatorSize;
@synthesize indicatorSize2;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults valueForKey:@"indicatorSize"]){
        IndicatorSize = [[defaults valueForKey:@"indicatorSize"] intValue];
    } else {
        IndicatorSize = 15;
    }
    if ([defaults valueForKey:@"indicatorSize2"]){
        indicatorSize2 = [[defaults valueForKey:@"indicatorSize2"] intValue];
    } else {
        indicatorSize2 = 10;
    }

    if ([defaults valueForKey:@"indicatorColor"]){
        NSData *theData=[defaults dataForKey:@"indicatorColor"];
        if (theData != nil){
            indicatorColor =(NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
        }
    } else {
        indicatorColor = [NSColor redColor];
    }
    [colorPicker setColor:indicatorColor];
    [sizePicker setDoubleValue:IndicatorSize];
    
    // Verify Accessibility first
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    if (accessibilityEnabled == NO){
        
    }

    RunningTiles = [[NSMutableArray alloc] init];
    tileRects = [[NSMutableDictionary alloc] init];
    CollectionTiles = [[NSMutableDictionary alloc] init];
    
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
   [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(resetAfterQuit:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
   [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(reFocus:) name:NSWorkspaceDidActivateApplicationNotification object:nil];
   NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
   [nc addObserver:self selector:@selector(reFocus:) name:NSWorkspaceActiveSpaceDidChangeNotification object:[NSWorkspace sharedWorkspace]];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(restart) name:NSWorkspaceDidWakeNotification object:nil];
    
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

    //Status Menu
    self.myStatusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] self];
    
    NSImage *statusImage;
    statusImage = [NSImage imageNamed:@"statusIcon"];
    [self.myStatusItem setImage:statusImage];
    [self.myStatusItem setHighlightMode:YES];
    self.myStatusItem.target = self;
    self.myStatusItem.action = @selector(mouseDown:);
    
    [self.myStatusItem setMenu:self.statusMenu];
    
    [self CreateDockPrefs];
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(reFocus:) userInfo:nil repeats:YES];
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
        if (self.timerStarted == NO){
            [self CreateDockPrefs];
            self.timerStarted = YES;
            for (NSMutableDictionary *tileDict in self.RunningTiles){
                DockTile *tileView = [tileDict valueForKey:@"tile"];
                [tileView startTimer];
            }
        }
    } else {
        if (self.timerStarted == YES){
            self.timerStarted = NO;
            for (NSMutableDictionary *tileDict in self.RunningTiles){
                DockTile *tileView = [tileDict valueForKey:@"tile"];
                [tileView stopTimer];
            }
        }
    }
    return aEvent;
}

- (void)newApp:(NSNotification *)notification {
    //[RunningTiles removeAllObjects];
    [view.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    [tileRects removeAllObjects];
    tileRects = [[NSMutableDictionary alloc] init];
    
        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * .5);
        dispatch_after(delay, dispatch_get_main_queue(), ^(void){
            [self buildTiles];
        });
}
- (void) resetAfterQuit : (NSNotification*)notification{
    NSRunningApplication *runApp = [[notification userInfo] valueForKey:@"NSWorkspaceApplicationKey"];
    NSString *name = [[runApp localizedName] stringByRemovingPercentEncoding];
    int index = -1;
    for (NSMutableDictionary *tmp in RunningTiles){
        NSString *otherName = [tmp valueForKey:@"id"];
        index += 1;
        if ([otherName isEqualToString:name]){
            break;
        }
    }
    [RunningTiles removeObjectAtIndex:index];
    
    DockTile *del;
    for (DockTile *sub in [view subviews]){
        if ([[sub.values valueForKey:@"name"] isEqualTo:name]){
            del = sub;
            break;
        }
    }
    [del removeFromSuperview];
    [CollectionTiles removeObjectForKey:name];
}
- (void) restart{
    [self relaunchAfterDelay:.5];
}

- (void)relaunchAfterDelay:(float)seconds{
    NSTask *task = [[NSTask alloc] init];
    NSMutableArray *args = [NSMutableArray array];
    [args addObject:@"-c"];
    [args addObject:[NSString stringWithFormat:@"sleep %f; open \"%@\"", seconds, [[NSBundle mainBundle] bundlePath]]];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:args];
    [task launch];
    
    NSLog(@"Relaunch");
    
    [[NSApplication sharedApplication] terminate:self];
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
            [dict setValue:[[app localizedName] stringByRemovingPercentEncoding] forKey:@"name"];
            [dict setValue:app.bundleIdentifier forKey:@"id"];
            [dict setValue:[self imageResize:[NSImage imageNamed:@"run"] newSize:NSMakeSize(50, 50)] forKey:@"icon"];
            [names addObject:dict];
        }
    }
    return names;
}
- (NSArray *)subelementsFromElement:(AXUIElementRef)element forAttribute:(NSString *)attribute{
    CFArrayRef subElements = nil;
    CFIndex count = 0;
    AXError result;
    
    result = AXUIElementGetAttributeValueCount(element, (__bridge CFStringRef)attribute, &count);
    if (result != kAXErrorSuccess) return nil;
    result = AXUIElementCopyAttributeValues(element, (__bridge CFStringRef)attribute, 0, count, (CFArrayRef *)&subElements);
    if (result != kAXErrorSuccess){
        return nil;
    }
    NSArray *ElesArray = (__bridge NSArray*)subElements;
    return ElesArray;
}

-(bool) getFrontMostWindow{
    for (NSRunningApplication *currApp in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([currApp isActive] && [currApp.localizedName isEqualToString:@"Finder"]) {
            return NO;
        }    }
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
                
                if (application){
                    CFRelease(application);
                }
                NSRect visibleFrame = [[NSScreen mainScreen] frame];
                visibleFrame.origin.y = 62;
                visibleFrame.size.height -= 62;
                
                if (NSEqualRects(rect, [[NSScreen mainScreen] frame]) == YES || NSEqualRects(rect, visibleFrame) == YES){
                    if (focusedWindow){
                        CFRelease(focusedWindow);
                    }
                    if (value){
                        CFRelease(value);
                    }
                        return YES;
                } else {
                    if (focusedWindow){
                        CFRelease(focusedWindow);
                    }
                    if (value){
                        CFRelease(value);
                    }
                    return NO;
                }
            }
    return NO;
}
- (void) buildTiles{
    [self collectTiles];
    
    NSMutableArray *names = [self getList];
    
    for (NSDictionary *name in names){
        NSRect rect = NSMakeRect(10, 10, 10, 10);
        
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
        [dict setValue:[NSValue valueWithRect:rect] forKey:@"rect"];
        [dict setValue:[name valueForKey:@"icon"] forKey:@"icon"];
        [dict setValue:[name valueForKey:@"name"] forKey:@"name"];
        [dict setValue:[tileRects valueForKey:[name valueForKey:@"name"]] forKey:@"ref"];
        
        if (![CollectionTiles valueForKey:[name valueForKey:@"name"]]){
            DockTile *tile = [[DockTile alloc] initWithFrame:rect];
            tile.DockTileRef = (__bridge AXUIElementRef)[tileRects valueForKey:[name valueForKey:@"name"]];
            tile.values = dict;
            NSMutableDictionary *final = [[NSMutableDictionary alloc] init];
            [final setObject:tile forKey:@"tile"];
            [final setValue:name forKey:@"vals"];
            [final setValue:[name valueForKey:@"name"] forKey:@"id"];
            [RunningTiles addObject:final];
            [CollectionTiles setValue:final forKey:[name valueForKey:@"name"]];
        }
        
        for (NSMutableDictionary *sub in RunningTiles){
            DockTile *ele = [sub valueForKey:@"tile"];
            [view addSubview:ele];
        }
    }
}

- (IBAction)openPrefs:(id)sender {
    [self setupSettings];
    [SettingsWindow setLevel:NSFloatingWindowLevel];
    [SettingsWindow makeKeyAndOrderFront:self];
}
- (IBAction)quitApp:(id)sender {
    [[NSApplication sharedApplication] terminate:self];
}

- (NSArray*) excludedApps{
    NSArray *excl = [[NSArray alloc] initWithObjects:
                     @"VLC",
                     @"Plex",
                     
                      nil];
    return excl;
}

-(void) CreateDockPrefs{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* dockDict = [[userDefaults persistentDomainForName:@"com.apple.dock"] mutableCopy];
    
    NSMutableArray* apps = [[dockDict valueForKey:@"persistent-apps"] mutableCopy];
    int maxSize = [[dockDict valueForKey:@"largesize"] intValue];
    int tileSize = [[dockDict valueForKey:@"tilesize"] intValue];
    BOOL isMaginficationEnabled = [[dockDict valueForKey:@"magnification"] boolValue];
    
    
    DockSettings = [[NSMutableDictionary alloc] init];
    [DockSettings setValue:[[NSNumber alloc] initWithLong:[apps count]] forKey:@"NumberOfApps"];
    if (isMaginficationEnabled == YES){
        [DockSettings setValue:[[NSNumber alloc] initWithInt:maxSize] forKey:@"maxSize"];
    } else {
        [DockSettings setValue:[[NSNumber alloc] initWithInt:tileSize] forKey:@"maxSize"];
    }
    
}

#pragma mark - ####### Experimental ##########
- (void) collectTiles{
    NSLog(@"Collecting");
    AXUIElementRef appElement;
    AXUIElementRef firstChild;
    
    appElement = AXUIElementCreateApplication([[[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"] lastObject] processIdentifier]);
    if (appElement != NULL){
        firstChild = (__bridge AXUIElementRef)[[self subelementsFromElement:appElement forAttribute:@"AXChildren"] objectAtIndex:0];
        CFArrayRef subElements = nil;
        CFIndex count = 0;
        AXError result;
        
        result = AXUIElementGetAttributeValueCount(firstChild, (CFStringRef)@"AXChildren", &count);
        result = AXUIElementCopyAttributeValues(firstChild, (CFStringRef)@"AXChildren", 0, count, (CFArrayRef *)&subElements);
        NSArray *ElesArray = (__bridge NSArray*)subElements;
        
        for (id tile in ElesArray){
            CFTypeRef value_title ;
            AXUIElementCopyAttributeValue((__bridge AXUIElementRef)(tile), kAXTitleAttribute, &value_title);
            if ([tileRects valueForKey:(__bridge NSString *)(value_title)]){
                CFRelease((__bridge CFTypeRef)([tileRects valueForKey:(__bridge NSString *)(value_title)]));
            }
            [tileRects setValue:tile forKey:(__bridge NSString *)(value_title)];
            
            CFRelease(CFBridgingRetain(tile));
            CFRelease(value_title);
        }
    }
    CFRelease(appElement);
}



#pragma mark - ########### Settings Methods ###########
- (void) setupSettings{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *login = [defaults objectForKey:@"LaunchatLogin"];
    if ([defaults valueForKey:@"indicatorSize"]){
        IndicatorSize = [[defaults valueForKey:@"indicatorSize"] intValue];
    }
    if ([defaults valueForKey:@"indicatorSize2"]){
        indicatorSize2 = [[defaults valueForKey:@"indicatorSize2"] intValue];
    }
    if ([defaults valueForKey:@"indicatorColor"]){
        NSData *theData=[defaults dataForKey:@"indicatorColor"];
        if (theData != nil){
            indicatorColor =(NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
        }
    }
    [colorPicker setColor:indicatorColor];
    [sizePicker setDoubleValue:IndicatorSize];
    [sizePicker2 setDoubleValue:indicatorSize2];
    
    if (login && [login isEqualToString:@"yes"]){
        lALogin.state = NSOnState;
    } else {
        lALogin.state = NSOffState;
    }
    
}
-(void) addToLoginItems{
    NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
    // This will retrieve the path for the application
    // For example, /Applications/test.app
    CFURLRef url = (CFURLRef)CFBridgingRetain([NSURL fileURLWithPath:appPath]);
    
    // Create a reference to the shared file list.
    // We are adding it to the current user only.
    // If we want to add it all users, use
    // kLSSharedFileListGlobalLoginItems instead of
    //kLSSharedFileListSessionLoginItems
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems, NULL);
    if (loginItems) {
        //Insert an item to the list.
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
                                                                     kLSSharedFileListItemLast, NULL, NULL,
                                                                     url, NULL, NULL);
        if (item){
            CFRelease(item);
        }
    }
    
    CFRelease(loginItems);
}
-(void) deleteAppFromLoginItem{
    NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
    // This will retrieve the path for the application
    // For example, /Applications/test.app
    CFURLRef url = (CFURLRef)CFBridgingRetain([NSURL fileURLWithPath:appPath]);
    
    // Create a reference to the shared file list.
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems, NULL);
    
    if (loginItems) {
        UInt32 seedValue;
        //Retrieve the list of Login Items and cast them to
        // a NSArray so that it will be easier to iterate.
        NSArray  *loginItemsArray = (NSArray *)CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seedValue));
        int i = 0;
        for(i ; i< [loginItemsArray count]; i++){
            LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)CFBridgingRetain([loginItemsArray
                                                                                         objectAtIndex:i]);
            //Resolve the item with URL
            if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr) {
                NSString * urlPath = [(NSURL*)CFBridgingRelease(url) path];
                if ([urlPath compare:appPath] == NSOrderedSame){
                    LSSharedFileListItemRemove(loginItems,itemRef);
                }
            }
        }
    }
}
- (IBAction)toggleLoginItem:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (lALogin.state != NSOffState){
        [defaults setObject:@"yes" forKey:@"LaunchatLogin"];
        [self addToLoginItems];
    } else {
        [defaults setObject:@"no" forKey:@"LaunchatLogin"];
        [self deleteAppFromLoginItem];
    }

}

- (IBAction)chooseColor:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *theData=[NSArchiver archivedDataWithRootObject:[sender color]];
    [defaults setObject:theData forKey:@"indicatorColor"];
    indicatorColor = [sender color];
    [self newApp:nil];
}

- (IBAction)chooseSize:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setValue:[[NSNumber alloc] initWithInt:[sender doubleValue]] forKey:@"indicatorSize"];
    IndicatorSize = [sender doubleValue];
    [self newApp:nil];
}
- (IBAction)chooseSize2:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setValue:[[NSNumber alloc] initWithInt:[sender doubleValue]] forKey:@"indicatorSize2"];
    indicatorSize2 = [sender doubleValue];
    [self newApp:nil];
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

//
//  AppDelegate.m
//  Helper
//
//  Created by Serge Sander on 01.08.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import "AppDelegate.h"
#import "UIElementUtilities.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self start];
}
-(void) start{
    NSMutableArray *names = [self getList];
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    
    for (NSString *name in names){
        NSRect frame = [self appDockIconByName:name];
        [data setValue:[NSValue valueWithRect:frame] forKey:name];
    }
    
    // Send Data
    [[NSNotificationCenter defaultCenter] postNotificationName: @"DockMarkerPositions" object: data];
    [[NSApplication sharedApplication] terminate:self];
}
- (NSMutableArray*) getList{
    NSMutableArray *idedApps = [[NSMutableArray alloc] init];
    NSWorkspace * ws = [NSWorkspace sharedWorkspace];
    NSArray * apps = [ws runningApplications];
    
    NSUInteger count = [apps count];
    for (NSUInteger i = 0; i < count; i++) {
        NSRunningApplication *app = [apps objectAtIndex: i];
        
        if(app.activationPolicy == NSApplicationActivationPolicyRegular) {
            [idedApps addObject:app.localizedName];
        }
    }
    return idedApps;
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
                    if (value){
                        CFRelease(value);
                    }
                    if (firstChild){
                        CFRelease(firstChild);
                    }
                    break;
                }
            }
        }
        rect = [UIElementUtilities frameOfUIElement:axElement];
        if (axElement){
            CFRelease(axElement);
        }
        if (appElement){
            CFRelease(appElement);
        }
    }
    return rect;
}
@end

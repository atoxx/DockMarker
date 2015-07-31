//
//  AppDelegate.h
//  DockMarker
//
//  Created by Serge Sander on 16.06.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>{
    NSWindow *bar;
    NSView *view;
    NSMutableArray *RunningTiles;
    CFTypeRef system ;
    BOOL isNotFS;
    NSMutableDictionary *BackupDict;
    NSMutableDictionary *observers;
    // Event Taps
    CFMachPortRef theEventTap;
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;
    
    // Window Lists
    NSMutableArray *BackupIDs;
    NSMutableArray *BackupTiles;
    CFArrayRef listOfWindows;
    NSArray *array;
    CGWindowImageOption imageOptions;
    CGWindowListOption singleWindowListOptions;
}

@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

@property IBOutlet NSView *AltDockTile;
@property CFMachPortRef eventTap;
@property NSTimer *timer;
@property NSMutableArray *RunningTiles;
@property int TotalWindowsCount;
@property NSMutableDictionary *WindowPreviews;
@property BOOL needsRestart;

@property (nonatomic) NSMutableArray *windowInfoArray;
@property (nonatomic) NSMutableArray *lastAllWindowInfoArray;
@property (nonatomic) NSMutableArray *allShowingWinKey;


- (void)receivedNotification:(NSString *)theName process:(ProcessSerialNumber *)theProcess element:(AXUIElementRef)theElement;


@end


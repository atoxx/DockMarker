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
    NSMutableDictionary *CollectionTiles;
    
    // Event Taps
    CFMachPortRef theEventTap;
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;


    // Settings Window
    IBOutlet NSWindow *SettingsWindow;
    IBOutlet NSButton *lALogin;
    IBOutlet NSColorWell *colorPicker;
    IBOutlet NSSlider *sizePicker;
    
    // Status Menu
    NSMenuItem *clipsCont;
    
    // Experimental
    NSPoint _lastMousePoint;
    AXUIElementRef _currentUIElement;
    AXUIElementRef _systemWideElement;
    NSMutableDictionary *tileRects;
    
}

@property (readonly,  nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, nonatomic) NSManagedObjectContext *managedObjectContext;

@property CFMachPortRef eventTap;
@property NSTimer *timer;
@property NSMutableArray *RunningTiles;
@property int TotalWindowsCount;
@property NSMutableDictionary *WindowPreviews;
@property BOOL needsRestart;
@property NSMutableDictionary *DockSettings;

@property (strong) IBOutlet NSMenu *statusMenu;
@property (strong) NSStatusItem *myStatusItem;

@property (nonatomic) NSMutableArray *windowInfoArray;
@property (nonatomic) NSMutableArray *lastAllWindowInfoArray;
@property (nonatomic) NSMutableArray *allShowingWinKey;
@property int LoopCounter;
@property BOOL isPaused;

@property int IndicatorSize;
@property NSColor *indicatorColor;

- (IBAction)openPrefs:(id)sender;
- (IBAction)quitApp:(id)sender;
- (IBAction)toggleLoginItem:(id)sender;
- (IBAction)chooseColor:(id)sender;
- (IBAction)chooseSize:(id)sender;

@end


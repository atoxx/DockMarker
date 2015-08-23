//
//  DockTile.h
//  DockMarker
//
//  Created by Serge Sander on 23.07.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

@interface DockTile : NSView{
    NSTimer *looper;
    NSTimer *dummyTimer;
    AppDelegate *deleg;
}
@property NSMutableDictionary* values;
@property NSImageView *img;
@property NSView *indicator;

@property AXUIElementRef DockTileRef;

- (void) startTimer;
- (void) stopTimer;

@end

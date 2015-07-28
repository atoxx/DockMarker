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
    CGWindowImageOption imageOptions;
    CGWindowListOption singleWindowListOptions;
    NSTrackingArea *track;
    NSTrackingArea *track2;
    NSView *content;
    AppDelegate *deleg;
    
}
@property NSMutableDictionary* values;
@property NSImageView *img;
@property NSView *indicator;
@property (nonatomic) NSMutableArray *windowInfoArray;
@property (nonatomic) NSMutableArray *lastAllWindowInfoArray;
@property (nonatomic) NSMutableArray *allShowingWinKey;
@property NSMutableArray *myChildren;
@property NSWindow *floater;;
@property BOOL isactive;


-(void) updateTA : (NSSize) size;

@end

//
//  DockTile.m
//  DockMarker
//
//  Created by Serge Sander on 23.07.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import "DockTile.h"
#import "UIElementUtilities.h"
#import "AppDelegate.h"
#import <Foundation/Foundation.h>

extern NSWindow *openPicker;

@implementation DockTile
@synthesize img;
@synthesize indicator;

- (id) initWithFrame:(NSRect)frameRect{
    if(self = [super initWithFrame:frameRect]){
        [self setFrame:frameRect];
        self.wantsLayer = YES;
        deleg = (AppDelegate*) [[NSApplication sharedApplication] delegate];
        
        NSRect box = NSMakeRect((frameRect.size.width - (deleg.IndicatorSize * 2)) / 2, 0, deleg.IndicatorSize * 2, deleg.IndicatorSize);
        indicator = [[NSView alloc] initWithFrame:box];
        indicator.wantsLayer = YES;
        [indicator.layer setBackgroundColor:[deleg.indicatorColor CGColor]];
        int radius = round(deleg.IndicatorSize);
        if (deleg.IndicatorSize > 5){
            [indicator.layer setCornerRadius:radius];
        }
        [self addSubview:indicator];
        
    }
    dummyTimer = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(initLooper) userInfo:nil repeats:YES];
    return self;
}
-(void) initLooper{
    if (self.DockTileRef){
        CGRect rect = [UIElementUtilities frameOfUIElement:self.DockTileRef];
        rect.origin.y = 15;
        
        [self setFrame:rect];
        NSRect box = NSMakeRect((rect.size.width - (deleg.IndicatorSize * 2)) / 2, 0, deleg.IndicatorSize * 2, deleg.IndicatorSize);
        [self.indicator setFrame:box];
        [dummyTimer invalidate];
        dummyTimer = nil;
    }
}
-(void) looper{
    if (self.DockTileRef){
        CGRect rect = [UIElementUtilities frameOfUIElement:self.DockTileRef];
        rect.origin.y = 15;

        [[self animator] setFrame:rect];
        NSRect box = NSMakeRect((rect.size.width - (deleg.IndicatorSize * 2)) / 2, 0, deleg.IndicatorSize * 2, deleg.IndicatorSize);
        [self.indicator setFrame:box];
    }
}
- (void) startTimer{
    if (!looper){
        looper = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(looper) userInfo:nil repeats:YES];
    }
}
- (void) stopTimer{
    [looper invalidate];
    looper = nil;
}
@end

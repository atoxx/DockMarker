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
        
        int perc = (deleg.indicatorSize2 * 100) / frameRect.size.width;
        NSRect box = NSMakeRect((frameRect.size.width - (deleg.IndicatorSize * 2)) / 2, 0, perc, deleg.IndicatorSize);
        indicator = [[NSView alloc] initWithFrame:box];
        indicator.wantsLayer = YES;
        [indicator.layer setBackgroundColor:[deleg.indicatorColor CGColor]];
        int radius = 3; // round(deleg.IndicatorSize);
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
        int perc = (deleg.indicatorSize2 * [self bounds].size.width) / 100;
        NSRect box = NSMakeRect(([self bounds].size.width - perc) / 2, 0, perc, deleg.IndicatorSize);
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
        int perc = (deleg.indicatorSize2 * [self bounds].size.width) / 100;
        NSRect box = NSMakeRect(([self bounds].size.width - perc) / 2, 0, perc, deleg.IndicatorSize);
        [self.indicator setFrame:box];
    }
}
- (void) startTimer{
    if (!looper){
        looper = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(looper) userInfo:nil repeats:YES];
    }
}
- (void) stopTimer{
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        [looper invalidate];
        looper = nil;
    });
}
@end

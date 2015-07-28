//
//  MainView.m
//  DockMarker
//
//  Created by Serge Sander on 24.07.15.
//  Copyright (c) 2015 Serge Sander. All rights reserved.
//

#import "MainView.h"

extern BOOL ignoreThisWindow;

@implementation MainView
- (id) initWithFrame:(NSRect)frameRect{
    if(self = [super initWithFrame:frameRect]){
        [self setFrame:frameRect];
    }
    return self;
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}
- (NSView*)hitTest:(NSPoint)point
{
    NSView *hitView = [super hitTest:point];
    // if the view clieck was self then ignore the click by returning nil
    return (hitView == self) ? nil : hitView;
}
- (void) viewDidMoveToWindow{
    NSTrackingArea *track = [[NSTrackingArea alloc] initWithRect:[self bounds] options: (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:nil];
    [self addTrackingArea:track];
}
- (void) mouseEntered:(NSEvent *)theEvent{
    ignoreThisWindow = YES;
}
- (void) mouseExited:(NSEvent *)theEvent{
    ignoreThisWindow = NO;
}

@end

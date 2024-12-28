//
//  AppDelegate.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/14.
//

#import <Cocoa/Cocoa.h>
#import "Statistics.h"

typedef struct { CGFloat red, green, blue; } MyRGB;

@interface PanelController : NSWindowController
<NSWindowDelegate, NSMenuItemValidation>
- (NSApplicationTerminateReply)appTerminate;
- (void)resetCamera;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (readonly) PanelController *pnlCntl;
@end

extern NSString *FullScreenName;
extern void in_main_thread(void (^block)(void));
extern void err_msg(NSObject *object, BOOL fatal);
extern void load_defaults(void);

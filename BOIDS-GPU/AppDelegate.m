//
//  AppDelegate.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/14.
//

#import "AppDelegate.h"
#import "AgentGPU.h"
#import "MetalView.h"

void in_main_thread(void (^block)(void)) {
	if ([NSThread isMainThread]) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}
static void show_alert(NSObject *object, short err, BOOL fatal) {
	in_main_thread( ^{
		NSAlert *alt;
		if ([object isKindOfClass:NSError.class])
			alt = [NSAlert alertWithError:(NSError *)object];
		else {
			NSString *str = [object isKindOfClass:NSString.class]?
				(NSString *)object : object.description;
			if (err != noErr)
				str = [NSString stringWithFormat:@"%@\nerror code = %d", str, err];
			alt = NSAlert.new;
			alt.alertStyle = fatal? NSAlertStyleCritical : NSAlertStyleWarning;
			alt.messageText = [NSString stringWithFormat:@"%@ in %@",
				fatal? @"Error" : @"Warning",
				[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];
			alt.informativeText = str;
		}
		[alt runModal];
		if (fatal) [NSApp terminate:nil];
	} );
}
void err_msg(NSObject *object, BOOL fatal) {
	show_alert(object, 0, fatal);
}
void error_msg(NSString *msg, short err) {
	show_alert(msg, err, NO);
}

@interface AppDelegate ()
@property (strong) IBOutlet NSWindow *window;
@property IBOutlet MetalView *metalView;
@end

@implementation AppDelegate
//- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
//}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	[_pnlCntl appTerminate];
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return YES;
}
- (IBAction)openPanel:(id)sender {
	if (_pnlCntl == nil) _pnlCntl = [PanelController.alloc initWithWindow:nil];
	[_pnlCntl showWindow:nil];
}
@end

static NSString *keyPopSize = @"PopSize", *acNmPopSize = @"Population Size";
static NSInteger PopSizeDefault;
enum { ColorBg, ColorBird, NColors };
static MyRGB ColorDefault[NColors] = {{0,0,0}, {1,1,1}};
static MyRGB Colors[NColors];
static NSString *ColorNames[NColors] = {@"Background", @"BirdColor"};
static NSString *keyFullScreenName = @"FullScreenName";
NSString *FullScreenName = nil;

@implementation PanelController {
	IBOutlet NSTextField *popSizeDgt;
	IBOutlet NSButton *ppSzApplyBtn;
	IBOutlet NSTextField *avdLbl, *cohLbl, *aliLbl,
		*masLbl, *mxsLbl, *mnsLbl, *frcLbl;
	IBOutlet NSSlider *avdSld, *cohSld, *aliSld,
		*masSld, *mxsSld, *mnsSld, *frcSld;
	IBOutlet NSTextField *avdDgt, *cohDgt, *aliDgt,
		*masDgt, *mxsDgt, *mnsDgt, *frcDgt;
	IBOutlet NSColorWell *bgColWel, *bdColWel;
	IBOutlet NSPopUpButton *fullScrPopUp;
	IBOutlet NSButton *revertBtn, *saveBtn, *resetBtn;
	NSArray<NSTextField *> *digits;
	NSArray<NSSlider *> *sliders;
	NSArray<NSColorWell *> *colWels;
	NSUndoManager *undoMngr;
}
- (NSString *)windowNibName { return @"Panel"; }
- (instancetype)initWithWindow:(NSWindow *)win {
	if ((self = [super initWithWindow:win]) == nil) return nil;
	undoMngr = NSUndoManager.new;
	return self;
}
static NSInteger default_popSize(void) {
	NSNumber *num = [NSUserDefaults.standardUserDefaults objectForKey:keyPopSize];
	return num? num.integerValue : PopSizeDefault;
}
static CGFloat default_value(NSInteger idx) {
	NSNumber *num = [NSUserDefaults.standardUserDefaults objectForKey:PrmLabels[idx]];
	return num? num.doubleValue : 0.;
}
static MyRGB myRGB_from_array(NSArray<NSNumber *> *arr) {
	return (MyRGB){arr[0].doubleValue, arr[1].doubleValue, arr[2].doubleValue};
}
static NSArray<NSNumber *> *myRGB_to_array(MyRGB rgb) {
	return @[@(rgb.red), @(rgb.green), @(rgb.blue)];
}
static MyRGB default_color(NSInteger idx) {
	NSArray<NSNumber *> *arr =
		[NSUserDefaults.standardUserDefaults objectForKey:ColorNames[idx]];
	return (arr == nil)? ColorDefault[idx] : myRGB_from_array(arr);
}
static NSColor *myRGB_to_color(MyRGB rgb) {
	return [NSColor colorWithRed:rgb.red green:rgb.green blue:rgb.blue alpha:1.];
}
static NSString *default_screen(void) {
	return [NSUserDefaults.standardUserDefaults objectForKey:keyFullScreenName];
}
static BOOL equal_screen_names(NSObject *a, NSObject *b) {
	if (a == nil) a = @NO;
	if (b == nil) b = @NO;
	return [a isEqualTo:b];
}
- (void)checkButtonEnabled {
	BOOL reset = NewPopSize != PopSizeDefault, save = NewPopSize != default_popSize();
	for (NSInteger i = 0; i < sliders.count && !(reset && save); i ++) {
		CGFloat val = sliders[i].doubleValue;
		CGFloat dfl = default_value(i);
		if (val != 0.) reset = YES;
		if (val != dfl) save = YES;
	}
	for (NSInteger i = 0; i < NColors && !(reset && save); i ++) {
		MyRGB dfl = default_color(i);
		if (memcmp(&Colors[i], &dfl, sizeof(MyRGB)) != 0) save = YES;
		if (memcmp(&Colors[i], &ColorDefault[i], sizeof(MyRGB)) != 0) reset = YES;
	}
	if (!save) save = !equal_screen_names(FullScreenName, default_screen());
	resetBtn.enabled = reset;
	revertBtn.enabled = saveBtn.enabled = save;
}
void load_defaults(void) {
	NSNumber *num;
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	PopSizeDefault = NewPopSize = PopSize;
	if ((num = [ud objectForKey:keyPopSize]) != nil)
		NewPopSize = PopSize = num.integerValue;
	for (NSInteger i = 0; i < N_PAAMS; i ++)
		if ((num = [ud objectForKey:PrmLabels[i]]) != nil)
			set_param_value(i, num.doubleValue);
	memcpy(Colors, ColorDefault, sizeof(Colors));
	NSArray<NSNumber *> *arr;
	if ((arr = [ud objectForKey:ColorNames[ColorBg]]) != nil) {
		MyRGB rgb = Colors[ColorBg] = myRGB_from_array(arr);
		((AppDelegate *)NSApp.delegate).metalView.view.clearColor
			= (MTLClearColor){rgb.red, rgb.green, rgb.blue, 1.};
	}
	if ((arr = [ud objectForKey:ColorNames[ColorBird]]) != nil) {
		MyRGB rgb = Colors[ColorBird] = myRGB_from_array(arr);
		BirdRGB = (simd_float3){rgb.red, rgb.green, rgb.blue};
	}
	FullScreenName = default_screen();
}
- (void)adjustFullScrItemSelection:(NSString *)title {
	if (title == nil) title = fullScrPopUp.lastItem.title;
	NSMenuItem *item = [fullScrPopUp itemWithTitle:title];
	[fullScrPopUp selectItem:(item != nil)? item : fullScrPopUp.lastItem];
}
- (void)configureScreenMenu {
	[fullScrPopUp removeAllItems];
	for (NSScreen *scr in NSScreen.screens)
		[fullScrPopUp addItemWithTitle:scr.localizedName];
	[fullScrPopUp addItemWithTitle:@"Last Screen"];
	[self adjustFullScrItemSelection:FullScreenName];
	fullScrPopUp.enabled = (NSScreen.screens.count > 1);
}
static void displayReconfigCB(CGDirectDisplayID display,
	CGDisplayChangeSummaryFlags flags, void *userInfo) {
	if ((flags & kCGDisplayBeginConfigurationFlag) != 0 ||
		(flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag |
		kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) == 0) return;
	in_main_thread(^{ [(__bridge PanelController *)userInfo configureScreenMenu]; });
}
#define PRM_BASE 5.
- (void)windowDidLoad {
	popSizeDgt.integerValue = PopSize;
	sliders = @[avdSld, cohSld, aliSld, masSld, mxsSld, mnsSld, frcSld];
	digits = @[avdDgt, cohDgt, aliDgt, masDgt, mxsDgt, mnsDgt, frcDgt];
	for (NSInteger i = 0; i < sliders.count; i ++) {
		sliders[i].doubleValue = digits[i].doubleValue = default_value(i);
		sliders[i].tag = digits[i].tag = i;
		sliders[i].target = digits[i].target = self;
		sliders[i].action = digits[i].action = @selector(changeValue:);
	}
	colWels = @[bgColWel, bdColWel];
	for (NSInteger i = 0; i < NColors; i ++)
		colWels[i].color = myRGB_to_color(Colors[i]);
	[self configureScreenMenu];
	CGError error = CGDisplayRegisterReconfigurationCallback(displayReconfigCB, (void *)self);
	if (error != kCGErrorSuccess)
		error_msg(@"Could not register a callback for display reconfiguration,", error);
	[self checkButtonEnabled];
}
- (void)appTerminate {
	if (!saveBtn.enabled) return;
	NSAlert *alert = NSAlert.new;
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Do you want to save the settings?";
	alert.informativeText = @"Parameter values have changed but not saved as defaults.";
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Don't save"];
	if ([alert runModal] == NSAlertFirstButtonReturn)
		[self saveAsDefault:saveBtn];
}
static void set_popSize(NSInteger newSize) {
	[((AppDelegate *)NSApp.delegate).metalView revisePopSize:newSize];
}
- (IBAction)changePopSizeDgt:(id)sender {
	ppSzApplyBtn.enabled = NewPopSize != popSizeDgt.integerValue;
}
- (IBAction)applyNewPopSize:(id)sender {
	NSInteger newSize = popSizeDgt.integerValue;
	if (NewPopSize != newSize) {
		NSInteger orgSize = NewPopSize;
		set_popSize(newSize);
		[undoMngr registerUndoWithTarget:popSizeDgt handler:^(NSTextField *dgt) {
			dgt.integerValue = orgSize;
			[self applyNewPopSize:nil];
		}];
		if (!(undoMngr.undoing || undoMngr.redoing))
			undoMngr.actionName = acNmPopSize;
	}
	ppSzApplyBtn.enabled = NO;
	[self checkButtonEnabled];
}
static void set_param_value(NSInteger idx, CGFloat exp) {
	float *prm = (float *)(&Prms), *prmDf = (float *)(&PrmsDefault);
	prm[idx] = prmDf[idx] * pow(PRM_BASE, exp);
}
- (IBAction)changeValue:(NSControl *)sender {
	NSInteger tag = sender.tag;
	CGFloat value = sender.doubleValue;
	NSArray<NSControl *> *cntrParts = [sender isKindOfClass:NSSlider.class]?
		(NSArray<NSControl *> *)digits : (NSArray<NSControl *> *)sliders;
	CGFloat orgVal = cntrParts[tag].doubleValue;
	cntrParts[tag].doubleValue = value;
	set_param_value(tag, value);
	[undoMngr registerUndoWithTarget:sender handler:^(NSControl *target) {
		target.doubleValue = orgVal;
		[target sendAction:target.action to:target.target]; 
	}];
	if (!undoMngr.isUndoing && !undoMngr.isRedoing)
		undoMngr.actionName = PrmLabels[tag];
	[self checkButtonEnabled];
}
static void set_color_value(NSInteger idx, MyRGB rgb) {
	MTKView *view = ((AppDelegate *)NSApp.delegate).metalView.view;
	switch (idx) {
		case ColorBg:
		view.clearColor = (MTLClearColor){rgb.red, rgb.green, rgb.blue, 1.};
		break;
		case ColorBird: BirdRGB = (simd_float3){rgb.red, rgb.green, rgb.blue};
	}
	if (view.paused) view.needsDisplay = YES;
}
- (void)changeColourOf:(NSInteger)idx rgb:(MyRGB)rgb {
	MyRGB orgRGB = Colors[idx];
	Colors[idx] = rgb;
	set_color_value(idx, rgb);
	[self checkButtonEnabled];
	[undoMngr registerUndoWithTarget:colWels[idx] handler:^(NSColorWell *target) {
		target.color = myRGB_to_color(orgRGB);
		[self changeColourOf:idx rgb:orgRGB];
	}];
}
- (IBAction)changeColour:(NSColorWell *)sender {
	CGFloat red, green, blue;
	[[sender.color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getRed:&red green:&green blue:&blue alpha:NULL];
	MyRGB newCol = {red, green, blue};
	if (memcmp(&newCol, &Colors[sender.tag], sizeof(MyRGB)) == 0) return;
	[self changeColourOf:sender.tag rgb:newCol];
	undoMngr.actionName = ColorNames[sender.tag];
}
- (IBAction)chooseScreen:(id)sender {
	FullScreenName =
		(fullScrPopUp.indexOfSelectedItem == fullScrPopUp.numberOfItems - 1)?
		nil : fullScrPopUp.titleOfSelectedItem;
	[self checkButtonEnabled];
}
- (void)setValuesFromDict:(NSDictionary *)dict {
	NSNumber *num;
	NSArray<NSNumber *> *arr;
	NSMutableDictionary *md = NSMutableDictionary.new;
	if ((num = dict[keyPopSize]) != nil) {
		NSInteger newSize = num.integerValue;
		if (newSize != NewPopSize) {
			md[keyPopSize] = @(NewPopSize);
			set_popSize(popSizeDgt.integerValue = newSize);
		}
	}
	for (NSInteger i = 0; i < sliders.count; i ++)
	if ((num = dict[PrmLabels[i]]) != nil) {
		CGFloat newValue = num.doubleValue, orgValue = sliders[i].doubleValue;
		if (newValue != orgValue) {
			md[PrmLabels[i]] = @(orgValue);
			sliders[i].doubleValue = digits[i].doubleValue = newValue;
			set_param_value(i, newValue);
		}
	}
	for (NSInteger i = 0; i < NColors; i ++)
	if ((arr = dict[ColorNames[i]]) != nil) {
		MyRGB newValue = myRGB_from_array(arr);
		if (memcmp(&newValue, &Colors[i], sizeof(MyRGB)) != 0) {
			md[ColorNames[i]] = myRGB_to_array(Colors[i]);
			Colors[i] = newValue;
			colWels[i].color = myRGB_to_color(newValue);
			set_color_value(i, newValue);
		} 
	}
	if (md.count == 0) return;
	[self checkButtonEnabled];
	[undoMngr registerUndoWithTarget:self handler:^(PanelController *target) {
		[target setValuesFromDict:md];
	}];
}
- (void)setDefaultFromDict:(NSDictionary *)dict {
	NSNumber *numNew, *numOrg;
	NSArray<NSNumber *> *arrNew, *arrOrg;
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if ((numNew = dict[keyPopSize]) != nil) {
		numOrg = [ud objectForKey:keyPopSize];
		NSInteger newSize = numNew.integerValue,
			orgSize = numOrg? numOrg.integerValue : PopSizeDefault;
		if (newSize != orgSize) {
			md[keyPopSize] = numOrg? numOrg : @(orgSize);
			if (newSize == PopSizeDefault) [ud removeObjectForKey:keyPopSize];
			else [ud setObject:numNew forKey:keyPopSize];
		}
	}
	for (NSInteger i = 0; i < sliders.count; i ++)
	if ((numNew = dict[PrmLabels[i]]) != nil) {
		numOrg = [ud objectForKey:PrmLabels[i]];
		CGFloat newValue = numNew.doubleValue, orgValue = numOrg? numOrg.doubleValue : 0.;
		if (newValue != orgValue) {
			md[PrmLabels[i]] = numOrg? numOrg : @(0.);
			if (newValue == 0.) [ud removeObjectForKey:PrmLabels[i]];
			else [ud setObject:numNew forKey:PrmLabels[i]];
		}
	}
	for (NSInteger i = 0; i < NColors; i ++)
	if ((arrNew = dict[ColorNames[i]]) != nil) {
		arrOrg = [ud objectForKey:ColorNames[i]];
		MyRGB newRGB = myRGB_from_array(arrNew),
			orgRGB = arrOrg? myRGB_from_array(arrOrg) : ColorDefault[i];
		if (memcmp(&newRGB, &orgRGB, sizeof(MyRGB)) != 0) {
			md[ColorNames[i]] = arrOrg;
			if (memcmp(&newRGB, &ColorDefault[i], sizeof(MyRGB)) == 0)
				[ud removeObjectForKey:ColorNames[i]];
			else [ud setObject:arrNew forKey:ColorNames[i]];
		} 
	}
	NSObject *orgScr = default_screen(), *newScr = dict[keyFullScreenName];
	if (newScr != nil && !equal_screen_names(orgScr, newScr)) {
		md[keyFullScreenName] = orgScr? orgScr : @NO;
		if ([newScr isEqualTo:@NO])
			[ud removeObjectForKey:keyFullScreenName];
		else [ud setObject:newScr forKey:keyFullScreenName];
	}
	if (md.count == 0) return;
	[self checkButtonEnabled];
	[undoMngr registerUndoWithTarget:self handler:^(PanelController *target) {
		[target setDefaultFromDict:md];
	}];
}
- (void)setActionNameFromSender:(id)sender {
	if ([sender respondsToSelector:@selector(title)])
		undoMngr.actionName = [sender title];
}
- (IBAction)saveAsDefault:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	if (default_popSize() != NewPopSize) md[keyPopSize] = @(NewPopSize);
	for (NSInteger i = 0; i < sliders.count; i ++) {
		CGFloat orgValue = default_value(i), newValue = sliders[i].doubleValue;
		if (orgValue != newValue) md[PrmLabels[i]] = @(newValue);
	}
	for (NSInteger i = 0; i < NColors; i ++) {
		MyRGB orgRGB = default_color(i);
		if (memcmp(&orgRGB, &Colors[i], sizeof(MyRGB)) != 0)
			md[ColorNames[i]] = myRGB_to_array(Colors[i]);
	}
	if (!equal_screen_names(FullScreenName, default_screen()))
		md[keyFullScreenName] = FullScreenName? FullScreenName : @NO;
	if (md.count > 0) {
		[self setDefaultFromDict:md];
		[self setActionNameFromSender:sender];
	}
}
- (IBAction)revertToDefault:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSInteger newSize = default_popSize();
	if (newSize != NewPopSize) md[keyPopSize] = @(newSize);
	for (NSInteger i = 0; i < sliders.count; i ++) {
		CGFloat newVal = default_value(i);
		if (newVal != sliders[i].doubleValue) md[PrmLabels[i]] = @(newVal);
	}
	for (NSInteger i = 0; i < NColors; i ++) {
		MyRGB newRGB = default_color(i);
		if (memcmp(&newRGB, &Colors[i], sizeof(MyRGB)) != 0)
			md[ColorNames[i]] = myRGB_to_array(newRGB);
	}
	NSString *newScr = default_screen();
	if (!equal_screen_names(newScr, FullScreenName))
		md[keyFullScreenName] = newScr? newScr : @NO;
	if (md.count > 0) {
		[self setValuesFromDict:md];
		[self setActionNameFromSender:sender];
	}
}
- (IBAction)resetValues:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	if (NewPopSize != PopSizeDefault) md[keyPopSize] = @(PopSizeDefault);
	for (NSInteger i = 0; i < sliders.count; i ++)
		if (sliders[i].doubleValue != 0.) md[PrmLabels[i]] = @(0.);
	for (NSInteger i = 0; i < NColors; i ++) {
		if (memcmp(&Colors[i], &ColorDefault[i], sizeof(MyRGB)) != 0)
			md[ColorNames[i]] = myRGB_to_array(ColorDefault[i]);
	}
	if (md.count > 0) {
		[self setValuesFromDict:md];
		[self setActionNameFromSender:sender];
	}
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoMngr;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(saveAsDefault:)) return saveBtn.enabled;
	if (action == @selector(revertToDefault:)) return revertBtn.enabled;
	if (action == @selector(resetValues:)) return resetBtn.enabled;
	return YES;
}
@end

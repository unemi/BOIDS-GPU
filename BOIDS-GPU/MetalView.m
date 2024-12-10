//
//  MetalView.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

#import "MetalView.h"
#import "AgentCPU.h"
#import "AgentGPU.h"
#import "AppDelegate.h"
#define LOG_STEPS 200
//#define MEASURE_TIME
#ifdef MEASURE_TIME
#import <sys/sysctl.h>
#define REC_TIME(v) unsigned long v = current_time_us();
#else
#define REC_TIME(v)
#endif

CGFloat FPS = 10.;
simd_float3 WallRGB = {0,0,0}, BirdRGB = {1,1,1};
ViewParams ViewPrms = {.depth = 0., .scale = 0., .contrast = 0.};
NSString * _Nonnull ViewPrmLbls[] = { @"Depth", @"Scale", @"Contrast" };
typedef id<MTLComputeCommandEncoder> CCE;
typedef id<MTLRenderCommandEncoder> RCE;
typedef enum { StopNone = 0,
	StopCompute = 1, StopView = 2, StopAndRestart = 4 } StopState;

@interface MetalView () {
	IBOutlet NSMenu *menu;
}
@end

@implementation MetalView {
	IBOutlet NSToolbarItem *playItem, *fullScrItem;
	IBOutlet NSTextField *fpsDgt;
	NSRect viewportRect;
	NSConditionLock *drawLock;
	NSLock *memLock;
	NSTimer *fpsTimer;
	NSToolbar *toolbar;
#ifdef MEASURE_TIME
	CGFloat TM1, TM2, TM3, TM4, TMI, TMG;
#endif
	unsigned long PrevTime;
	StopState stopState;
	BOOL shouldRestart, sightDistChanged;
}
- (void)switchFpsTimer:(BOOL)on {
	if (on) {
		if (fpsTimer == nil) fpsTimer =
			[NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:
			^(NSTimer * _Nonnull timer) { self->fpsDgt.doubleValue = FPS; }];
	} else if (fpsTimer != nil) {
		[fpsTimer invalidate];
		fpsTimer = nil;
	}
}
- (void)allocPopMem {
	[memLock lock];
	alloc_pop_mem(_view.device);
	[memLock unlock];
}
- (void)allocCellMem {
	[memLock lock];
	if (check_cell_unit(PopSize))
		alloc_cell_mem(_view.device);
	[memLock unlock];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	[self switchFpsTimer:[change[NSKeyValueChangeNewKey] boolValue] && !_view.paused];
}
- (void)awakeFromNib {
	[(toolbar = _view.window.toolbar) addObserver:self forKeyPath:@"visible"
		options:NSKeyValueObservingOptionNew context:NULL];
	@try {
		load_defaults();
		NSError *error;
		id<MTLDevice> device = _view.device = setup_GPU();
		NSUInteger smplCnt = 1;
		while ([device supportsTextureSampleCount:smplCnt << 1]) smplCnt <<= 1;
		_view.sampleCount = smplCnt;
		[self mtkView:_view drawableSizeWillChange:_view.drawableSize];
		_view.menu = menu;
		_view.delegate = self;
		id<MTLLibrary> dfltLib = device.newDefaultLibrary;
		shapePSO = [device newComputePipelineStateWithFunction:
			[dfltLib newFunctionWithName:@"makeSpape"] error:&error];
		if (shapePSO == nil) @throw error;
		MTLRenderPipelineDescriptor *pplnStDesc = MTLRenderPipelineDescriptor.new;
		pplnStDesc.label = @"Simple Pipeline";
		pplnStDesc.rasterSampleCount = _view.sampleCount;
		MTLRenderPipelineColorAttachmentDescriptor *colAttDesc = pplnStDesc.colorAttachments[0];
		colAttDesc.pixelFormat = _view.colorPixelFormat;
		pplnStDesc.vertexFunction = [dfltLib newFunctionWithName:@"vertexShaderBG"];
		pplnStDesc.fragmentFunction = [dfltLib newFunctionWithName:@"fragmentShader"];
		bgPSO = [device newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];
		if (bgPSO == nil) @throw error;
		pplnStDesc.vertexFunction = [dfltLib newFunctionWithName:@"vertexShader"];
		drawPSO = [device newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];
		if (drawPSO == nil) @throw error;
		drawLock = [NSConditionLock.alloc initWithCondition:0];
		memLock = NSLock.new;
		[self allocPopMem];
		_view.paused = YES;
		_view.enableSetNeedsDisplay = YES;
	} @catch (NSObject *obj) { err_msg(obj, YES); }
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
	viewportRect.origin = NSZeroPoint;
	viewportRect.size = size;
	CGSize cSz = {size.width * 9, size.height * 16};
	if (cSz.width > cSz.height) {
		CGFloat newWidth = viewportRect.size.width = cSz.height / 9.;
		viewportRect.origin.x = (size.width - newWidth) / 2.;
	} else if (cSz.width < cSz.height) {
		CGFloat newHeight = viewportRect.size.height = cSz.width / 16.;
		viewportRect.origin.y = (size.height - newHeight) / 2.;
	}
	view.needsDisplay = YES;
}
- (void)detachComputeThread {
	[NSThread detachNewThreadSelector:@selector(compute:) toTarget:self withObject:nil];
}
- (void)compute:(id)dummy {
	static unsigned long time_us = 0;
	NSThread.currentThread.name = @"compute";
	while (stopState == StopNone) {
		unsigned long now = current_time_us();
		CGFloat interval = (now - time_us) / 1e6;
		time_us = now;
		float deltaTime = fmin(interval, 1./20.) * 1000.;
		Step ++;
#ifdef MEASURE_TIME
		TMI += (deltaTime - TMI) * 0.05;
		if (Step == 1) {
			static char name[128] = {0};
			if (name[0] == '\0') {
				size_t len = sizeof(name);
				sysctlbyname("hw.model", name, &len, NULL, 0);
			}
			NSString *str = NSProcessInfo.processInfo.operatingSystemVersionString;
			printf("\"%s\",\"%s\",%ld,%d\n", name, str.UTF8String, PopSize, N_CELLS);
		} else if (Step % LOG_STEPS == 0)
			printf("%ld,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n",
				Step, TM1, TM2, TM3, TM4, TMG, TMI);
#endif
		[memLock lock];
		REC_TIME(tm1)
		pop_step1();
		REC_TIME(tm2);
		pop_step2();
		REC_TIME(tm3);
		if (pop_step3()) {
			taskBfIdx = 1 - taskBfIdx;
			TaskQueue = taskBf[taskBfIdx].contents;
			TasQWork = taskBf[1 - taskBfIdx].contents;
		}
		REC_TIME(tm4);
		[drawLock lockWhenCondition:0];
		pop_step4(deltaTime);
		[drawLock unlockWithCondition:1];
		[memLock unlock];
#ifdef MEASURE_TIME
		TM1 += ((tm2 - tm1) / 1000. - TM1) * 0.05;
		TM2 += ((tm3 - tm2) / 1000. - TM2) * 0.05;
		TM3 += ((tm4 - tm3) / 1000. - TM3) * 0.05;
		TM4 += ((current_time_us() - tm4) / 1000. - TM4) * 0.05;
#endif
		if (NewPopSize != PopSize || sightDistChanged) usleep(100000/3);
	}
	stopState = ((stopState & StopAndRestart) | StopView);
}
- (void)drawInMTKView:(MTKView *)view {
	BOOL animated = !view.paused;
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	CCE cce = cmdBuf.computeCommandEncoder;
	[cce setComputePipelineState:shapePSO];
	NSInteger idx = 0;
	REC_TIME(tm1);
	simd_float2 camP = {WS.z * pow(10., ViewPrms.depth), pow(10., ViewPrms.scale)};
	[cce setBuffer:popBuf offset:0 atIndex:idx ++];
	[cce setBytes:&WS length:sizeof(WS) atIndex:idx ++];
	[cce setBytes:&camP length:sizeof(camP) atIndex:idx ++];
	[cce setBuffer:vxBuf offset:0 atIndex:idx ++];
	NSUInteger threadGrpSz = shapePSO.maxTotalThreadsPerThreadgroup;
		if (threadGrpSz > PopSize) threadGrpSz = PopSize;
	[cce dispatchThreads:MTLSizeMake(PopSize, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
	[cce endEncoding];
	REC_TIME(tm2);
	if (animated) [drawLock lockWhenCondition:1];
	REC_TIME(tm3);
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	if (animated) [drawLock unlockWithCondition:0];

	cmdBuf = commandQueue.commandBuffer;
	MTLRenderPassDescriptor *rndrPasDesc = view.currentRenderPassDescriptor;
	if(rndrPasDesc == nil) return;
	RCE rce = [cmdBuf renderCommandEncoderWithDescriptor:rndrPasDesc];
	rce.label = @"MyRenderEncoder";
	[rce setViewport:(MTLViewport){viewportRect.origin.x, viewportRect.origin.y,
		viewportRect.size.width, viewportRect.size.height, 0., 1. }];
	static uint16 cornersIdx[5][4] = // Floor, Left, Right, Cieling, and Back
		{{0, 1, 2, 3}, {0, 2, 4, 6}, {1, 3, 5, 6}, {2, 3, 6, 7}, {4, 5, 6, 7}};
	static float surfaceDim[5] = {0., .5, .5, 1., .75};
	[rce setRenderPipelineState:bgPSO];
	idx = 0;
	[rce setVertexBytes:&WS length:sizeof(WS) atIndex:idx ++];
	[rce setVertexBytes:&camP length:sizeof(camP) atIndex:idx ++];
	for (NSInteger i = 0; i < 5; i ++) {
		simd_float3 corners[4], col;
		for (NSInteger j = 0; j < 4; j ++) {
			uint16 k = cornersIdx[i][j];
			corners[j] = WS * (simd_float3){k % 2, (k / 2) % 2, k / 4};
		}
		col = WallRGB + surfaceDim[i] * (ViewPrms.contrast + 1.) / 2. * (1. - WallRGB);
		[rce setVertexBytes:corners length:sizeof(corners) atIndex:idx];
		[rce setFragmentBytes:&col length:sizeof(col) atIndex:0];
		[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip
			vertexStart:0 vertexCount:4];
	}
	[rce setRenderPipelineState:drawPSO];
	[rce setVertexBuffer:vxBuf offset:0 atIndex:0];
	[rce setFragmentBytes:&BirdRGB length:sizeof(BirdRGB) atIndex:0];
	[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
		vertexCount:PopSize * 6];
	[rce endEncoding];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	unsigned long tm = current_time_us();
#ifdef MEASURE_TIME
	TMG += ((tm - tm3 + tm2 - tm1) / 1000. - TMG) * 0.05;
#endif
	FPS += (fmax(1e6 / (tm - PrevTime), 10.) - FPS) * 0.05;
	PrevTime = tm;
	if (animated) {
		if (NewPopSize != PopSize) [self allocPopMem];
		else if (sightDistChanged) [self allocCellMem];
		sightDistChanged = NO;
	}
	if (stopState == StopView) {
		_view.paused = YES;
		playItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		playItem.label = @"Play";
		[self switchFpsTimer:NO];
	} else if (stopState == (StopView|StopAndRestart)) {
		pop_reset();
		stopState = StopNone;
		[self detachComputeThread];
	}
}
- (void)revisePopSize:(NSInteger)newSize {
	NewPopSize = newSize;
	if (_view.paused) {
		[self allocPopMem];
		_view.needsDisplay = YES;
	}
}
- (void)reviseSightDistance {
	if (_view.paused) [self allocCellMem];
	else sightDistChanged = YES;
}
- (IBAction)fullScreen:(id)sender {
	if (_view.inFullScreenMode) {
		[_view exitFullScreenModeWithOptions:nil];
		fullScrItem.image = [NSImage imageNamed:NSImageNameEnterFullScreenTemplate];
	} else {
		NSScreen *screen = NSScreen.screens.lastObject;
		if (FullScreenName != nil) for (NSScreen *scr in NSScreen.screens)
			if ([scr.localizedName isEqualToString:FullScreenName])
				{ screen = scr; break; }
		fullScrItem.image = [NSImage imageNamed:NSImageNameExitFullScreenTemplate];
		[_view enterFullScreenMode:screen withOptions:
			@{NSFullScreenModeAllScreens:@NO}];
	}
}
- (IBAction)playPause:(id)sender {
	if (_view.paused) {
		stopState = StopNone;
		playItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		playItem.label = @"Pause";
		_view.paused = NO;
		if (toolbar.visible) [self switchFpsTimer:YES];
		[self detachComputeThread];
	} else stopState = StopCompute;
}
- (IBAction)restart:(id)sender {
	if (_view.paused) {
		pop_reset();
		_view.needsDisplay = YES;
	} else stopState = (StopCompute|StopAndRestart);
}
- (IBAction)resetCamera:(id)sender {
	if (((AppDelegate *)NSApp.delegate).pnlCntl != nil)
		[((AppDelegate *)NSApp.delegate).pnlCntl resetCamera];
	else ViewPrms.depth = ViewPrms.scale = 0.;
	_view.needsDisplay = YES;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(playPause:)) {
		menuItem.title = _view.paused? @"Play" : @"Pause";
	} else if (menuItem.action == @selector(fullScreen:)) {
		menuItem.title = _view.inFullScreenMode? @"Exit Full Screen" : @"Enter Full Screen";
	} else if (menuItem.action == @selector(resetCamera:)) {
		return ViewPrms.depth != 0. || ViewPrms.scale != 0.;
	}
	return YES;
}
- (void)windowDidResize:(NSNotification *)notification {
// for recovery from the side effect of toolbar.
	static BOOL launched = NO;
	if (!launched) {
		launched = YES;
		NSRect frame = _view.window.frame;
		NSSize vSize = _view.frame.size;
		frame.size.width += 1280 - vSize.width;
		frame.size.height += 720 - vSize.height;
		[_view.window setFrame:frame display:NO];
	}
}
- (void)windowWillClose:(NSNotification *)notification {
	[NSApp terminate:nil];
}
- (void)escKeyDown {
	if (_view.inFullScreenMode) [self fullScreen:nil];
}
@end

@implementation MyMTKView
- (void)scrollWheel:(NSEvent *)event {
	CGFloat delta = (event.modifierFlags & NSEventModifierFlagShift)?
		event.deltaX * .05 : event.deltaY * .005;
	if (event.modifierFlags & NSEventModifierFlagCommand)
		ViewPrms.scale = fmax(-1., fmin(1., ViewPrms.scale - delta));
	else ViewPrms.depth =  fmax(-1., fmin(1., ViewPrms.depth + delta));
	self.needsDisplay = YES;
}
- (void)keyDown:(NSEvent *)event {
	if (event.keyCode == 53) [(MetalView *)self.delegate escKeyDown];
}
@end

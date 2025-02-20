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
simd_float3 WallRGB = {0,0,0}, AgntRGB = {1,1,1};
ViewParams ViewPrms = {
	.depth = 0., .scale = 0., .contrast = 0.,
	.agentSize = 0., .agentOpacity = 1.};
ShapeType shapeType = ShapePaperPlane;
NSString * _Nonnull ViewPrmLbls[] = {
	@"Depth", @"Scale", @"Contrast", @"AgentSize", @"AgentOpacity" };
typedef id<MTLComputeCommandEncoder> CCE;
typedef id<MTLRenderCommandEncoder> RCE;

@implementation MetalView {
	IBOutlet NSMenu *menu;
	IBOutlet NSToolbarItem *playItem, *fullScrItem;
	IBOutlet NSTextField *fpsDgt;
	id<MTLComputePipelineState> shapePSO, squarePSO;
	id<MTLRenderPipelineState> bgPSO, drawPSO, blobPSO;
	id<MTLBuffer> vxBuf, idxBuf;
	NSInteger vxBufSize, idxBufSize;
	NSRect viewportRect;
	NSLock *drawLock;
	NSTimer *fpsTimer;
	NSToolbar *toolbar;
#ifdef MEASURE_TIME
	CGFloat TM1, TM2, TM3, TM4, TMI, TMG;
#endif
	unsigned long PrevTimeSim, PrevTimeDraw;
	NSTimeInterval refreshSec;
	BOOL running, shouldRestart, sightDistChanged;
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
- (void)getScreenRefreshTime {
	refreshSec = _view.window.screen.displayUpdateGranularity;
}
- (void)allocCellMem {
	if (check_cell_unit(PopSize))
		alloc_cell_mem(_view.device);
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	[self switchFpsTimer:[change[NSKeyValueChangeNewKey] boolValue] && !_view.paused];
}
static id<MTLComputePipelineState> make_comp_func(id<MTLDevice> device,
	id<MTLLibrary> dfltLib, NSString *name) {
	NSError *error;
	id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:
		[dfltLib newFunctionWithName:name] error:&error];
	if (pso == nil) @throw error;
	return pso;
}
static id<MTLRenderPipelineState> make_render_func(id<MTLDevice> device,
	id<MTLLibrary> dfltLib, MTLRenderPipelineDescriptor *pplnStDesc, NSString *name) {
	NSError *error;
	pplnStDesc.vertexFunction = [dfltLib newFunctionWithName:name];
	id<MTLRenderPipelineState> pso =
		[device newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];
	if (pso == nil) @throw error;
	return pso;
}
- (void)awakeFromNib {
	[(toolbar = _view.window.toolbar) addObserver:self forKeyPath:@"visible"
		options:NSKeyValueObservingOptionNew context:NULL];
	[self getScreenRefreshTime];
	@try {
		load_defaults();
		id<MTLDevice> device = _view.device = setup_GPU(_view);
		NSUInteger smplCnt = 1;
		while ([device supportsTextureSampleCount:smplCnt << 1]) smplCnt <<= 1;
		_view.sampleCount = smplCnt;
		[self mtkView:_view drawableSizeWillChange:_view.drawableSize];
		_view.menu = menu;
		_view.delegate = self;
		id<MTLLibrary> dfltLib = device.newDefaultLibrary;
		shapePSO = make_comp_func(device, dfltLib, @"makeShape");
		squarePSO = make_comp_func(device, dfltLib, @"makeSquare");
		MTLRenderPipelineDescriptor *pplnStDesc = MTLRenderPipelineDescriptor.new;
		pplnStDesc.label = @"Simple Pipeline";
		pplnStDesc.rasterSampleCount = _view.sampleCount;
		MTLRenderPipelineColorAttachmentDescriptor *colAttDesc = pplnStDesc.colorAttachments[0];
		colAttDesc.pixelFormat = _view.colorPixelFormat;
		colAttDesc.blendingEnabled = YES;
		colAttDesc.rgbBlendOperation = MTLBlendOperationAdd;
		colAttDesc.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
		colAttDesc.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
		pplnStDesc.fragmentFunction = [dfltLib newFunctionWithName:@"fragmentShader"];
		bgPSO = make_render_func(device, dfltLib, pplnStDesc, @"vertexShaderBG");
		drawPSO = make_render_func(device, dfltLib, pplnStDesc, @"vertexShader");
		pplnStDesc.fragmentFunction = [dfltLib newFunctionWithName:@"fragmentBlob"];
		blobPSO = make_render_func(device, dfltLib, pplnStDesc, @"vertexBlob");
		drawLock = NSLock.new;
		alloc_pop_mem(_view.device);
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
	NSThread.currentThread.name = @"compute";
	while (running) {
		if (NewPopSize != PopSize) alloc_pop_mem(_view.device);
		else if (sightDistChanged) [self allocCellMem];
		if (shouldRestart) pop_reset();
		shouldRestart = sightDistChanged = NO;
		unsigned long now = current_time_us();
		CGFloat interval = (now - PrevTimeSim) / 1e6;
		PrevTimeSim = now;
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
			printf("\"%s\",\"%s\",\"%s\",%ld,%ld,%d\n", name,
				NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String,
				_view.device.name.UTF8String, nCores, PopSize, N_CELLS);
		} else if (Step % LOG_STEPS == 0)
			printf("%ld,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n",
				Step, TM1, TM2, TM3, TM4, TMG, TMI);
#endif
		REC_TIME(tm1)
		pop_step1();
		REC_TIME(tm2)
		pop_step2();
		REC_TIME(tm3)
		if (pop_step3()) {
			taskBfIdx = 1 - taskBfIdx;
			TaskQueue = taskBf[taskBfIdx].contents;
			TasQWork = taskBf[1 - taskBfIdx].contents;
		}
		REC_TIME(tm4)
		pop_step4(deltaTime);
		[drawLock lock];
		memcpy(PopDraw, PopSim, sizeof(Agent) * PopSize);
		[drawLock unlock];
		in_main_thread( ^{ self.view.needsDisplay = YES; });
		unsigned long tmE = current_time_us();
#ifdef MEASURE_TIME
		TM1 += ((tm2 - tm1) / 1000. - TM1) * 0.05;
		TM2 += ((tm3 - tm2) / 1000. - TM2) * 0.05;
		TM3 += ((tm4 - tm3) / 1000. - TM3) * 0.05;
		TM4 += ((tmE - tm4) / 1000. - TM4) * 0.05;
#endif
		long timeLeft = refreshSec * .95e6 - (tmE - now);
		if (timeLeft > 100) usleep((unsigned int)timeLeft);
		else usleep(100);
	}
}
- (void)drawInMTKView:(MTKView *)view {
	BOOL animated = !view.paused;
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	CCE cce = cmdBuf.computeCommandEncoder;
	NSArray<id<MTLComputePipelineState>> *psos = @[shapePSO, squarePSO];
	NSInteger vxSzs[] = {6, 4}, idxSzs[] = {0, 5};
	NSInteger vxSz = PopSize * vxSzs[shapeType], idxSz = PopSize * idxSzs[shapeType];
	if (vxBufSize != vxSz) {
		vxBuf = [view.device newBufferWithLength:sizeof(simd_float2) * vxSz
			options:MTLResourceStorageModePrivate];
		vxBufSize = vxSz;
	}
	if (idxBufSize != idxSz) {
		if (idxSz == 0) idxBuf = nil;
		else idxBuf = [view.device newBufferWithLength:sizeof(uint32) * idxSz
			options:MTLResourceStorageModeShared];
		idxBufSize = idxSz;
		if (shapeType == ShapeBlob) {
			uint32 *idxP = idxBuf.contents;
			for (uint32 i = 0; i < PopSize; i ++) {
				for (uint32 j = 0; j < 4; j ++) idxP[i * 5 + j] = i * 4 + j;
				idxP[i * 5 + 4] = (uint32)(-1);
	}}}
	[cce setComputePipelineState:psos[shapeType]];
	NSInteger idx = 0;
	REC_TIME(tm1);
	simd_float2 camP = {WS.z * pow(10., ViewPrms.depth), pow(10., ViewPrms.scale)};
	float agntSz = pow(5., ViewPrms.agentSize);
	[cce setBuffer:popDrawBuf offset:0 atIndex:idx ++];
	[cce setBytes:&WS length:sizeof(WS) atIndex:idx ++];
	[cce setBytes:&camP length:sizeof(camP) atIndex:idx ++];
	[cce setBytes:&agntSz length:sizeof(agntSz) atIndex:idx ++];
	[cce setBuffer:vxBuf offset:0 atIndex:idx ++];
	NSUInteger threadGrpSz = shapePSO.maxTotalThreadsPerThreadgroup;
	if (threadGrpSz > PopSize) threadGrpSz = PopSize;
	[cce dispatchThreads:MTLSizeMake(PopSize, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
	[cce endEncoding];
	REC_TIME(tm2);
	if (animated) [drawLock lock];
	REC_TIME(tm3);
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	if (animated) [drawLock unlock];

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
		simd_float3 corners[4];
		simd_float4 col = {0,0,0,1};
		for (NSInteger j = 0; j < 4; j ++) {
			uint16 k = cornersIdx[i][j];
			corners[j] = WS * (simd_float3){k % 2, (k / 2) % 2, k / 4};
		}
		col.rgb = WallRGB + ((ViewPrms.contrast > 0.)?
			surfaceDim[i] * ViewPrms.contrast :
			(1. - surfaceDim[i]) * - ViewPrms.contrast) * (1. - WallRGB);
		[rce setVertexBytes:corners length:sizeof(corners) atIndex:idx];
		[rce setFragmentBytes:&col length:sizeof(col) atIndex:0];
		[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip
			vertexStart:0 vertexCount:4];
	}
	[rce setVertexBuffer:vxBuf offset:0 atIndex:0];
	simd_float4 agntCol = simd_make_float4(AgntRGB, ViewPrms.agentOpacity);
	[rce setFragmentBytes:&agntCol length:sizeof(agntCol) atIndex:0];
	switch (shapeType) {
		case ShapePaperPlane:
		[rce setRenderPipelineState:drawPSO];
		[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
			vertexCount:vxBufSize];
		break;
		case ShapeBlob:
		[rce setRenderPipelineState:blobPSO];
		simd_float2 scrSize = {viewportRect.size.width, viewportRect.size.height};
		[rce setFragmentBytes:&scrSize length:sizeof(scrSize) atIndex:1];
		[rce drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip
			indexCount:idxBufSize indexType:MTLIndexTypeUInt32
			indexBuffer:idxBuf indexBufferOffset:0];
	}
	[rce endEncoding];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	unsigned long tm = current_time_us();
#ifdef MEASURE_TIME
	TMG += ((tm - tm3 + tm2 - tm1) / 1000. - TMG) * 0.05;
#endif
	FPS += (fmax(1e6 / (tm - PrevTimeDraw), 10.) - FPS) * 0.05;
	PrevTimeDraw = tm;
}
- (void)revisePopSize:(NSInteger)newSize {
	NewPopSize = newSize;
	if (!running) {
		alloc_pop_mem(_view.device);
		_view.needsDisplay = YES;
	}
}
- (void)reviseSightDistance {
	if (running) sightDistChanged = YES;
	else [self allocCellMem];
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
	[self getScreenRefreshTime];
}
- (IBAction)playPause:(id)sender {
	if ((running = !running)) {
		playItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		playItem.label = @"Pause";
		if (toolbar.visible) [self switchFpsTimer:YES];
		[self detachComputeThread];
	} else {
		playItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		playItem.label = @"Play";
		[self switchFpsTimer:NO];
	}
}
- (IBAction)restart:(id)sender {
	if (running) shouldRestart = YES;
	else {
		pop_reset();
		_view.needsDisplay = YES;
	}
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
- (void)windowDidChangeScreenProfile:(NSNotification *)notification {
	[self getScreenRefreshTime];
}
- (void)escKeyDown {
	if (_view.inFullScreenMode) [self fullScreen:nil];
}
@end

@implementation MyMTKView
- (void)scrollWheel:(NSEvent *)event {
	CGFloat delta = (event.modifierFlags & NSEventModifierFlagShift)?
		event.deltaX * .05 : event.deltaY * .005;
	if (event.modifierFlags & NSEventModifierFlagCommand) {
		ViewPrms.depth =  fmax(-1., fmin(1., ViewPrms.depth + delta));
		[((AppDelegate *)NSApp.delegate).pnlCntl camDepthModified];
	} else {
		ViewPrms.scale = fmax(-1., fmin(1., ViewPrms.scale - delta));
		[((AppDelegate *)NSApp.delegate).pnlCntl camScaleModified];
	}
	self.needsDisplay = YES;
}
- (void)keyDown:(NSEvent *)event {
	if (event.keyCode == 53) [(MetalView *)self.delegate escKeyDown];
}
@end

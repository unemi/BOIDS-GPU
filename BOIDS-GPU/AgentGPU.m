//
//  AgentGPU.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

#import "AgentGPU.h"
#import "AgentCPU.h"
#import "AppDelegate.h"

id<MTLComputePipelineState> movePSO, shapePSO;
id<MTLRenderPipelineState> bgPSO, drawPSO;
id<MTLCommandQueue> commandQueue;
id<MTLBuffer> popSimBuf, popDrawBuf, forceBuf, cellBuf, idxsBuf, vxBuf;
id<MTLBuffer> taskBf[2];	// for double buffering
NSInteger taskBfIdx, NewPopSize;

void alloc_pop_mem(id<MTLDevice> device) {
	for (NSInteger i = 0; i < 2; i ++)
		taskBf[i] = [device newBufferWithLength:sizeof(Task) * NewPopSize
			options:MTLResourceStorageModeShared];
	popSimBuf = [device newBufferWithLength:sizeof(Agent) * NewPopSize
		options:MTLResourceStorageModeShared];
	popDrawBuf = [device newBufferWithLength:sizeof(Agent) * NewPopSize
		options:MTLResourceStorageModeShared];
	forceBuf = [device newBufferWithLength:sizeof(simd_float3) * NewPopSize
		options:MTLResourceStorageModeShared];
	idxsBuf = [device newBufferWithLength:sizeof(uint32_t) * NewPopSize
		options:MTLResourceStorageModeShared];
	vxBuf = [device newBufferWithLength:sizeof(simd_float2) * NewPopSize * 6
		options:MTLResourceStorageModePrivate];
	TaskQueue = taskBf[0].contents;
	TasQWork = taskBf[1].contents;
	PopSim = popSimBuf.contents;
	PopDraw = popDrawBuf.contents;
	Forces = forceBuf.contents;
	Idxs = idxsBuf.contents;
	if (pop_mem_init(NewPopSize))
		alloc_cell_mem(device);
	PopSize = NewPopSize;
	pop_reset();
}
void alloc_cell_mem(id<MTLDevice> device) {
	cellBuf = [device newBufferWithLength:
		sizeof(Cell) * N_CELLS_X*N_CELLS_Y*N_CELLS_Z
		options:MTLResourceStorageModeShared];
	Cells = cellBuf.contents;
}
id<MTLDevice> setup_GPU(void) {
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	@try {
		NSError *error;
		id<MTLLibrary> dfltLib = device.newDefaultLibrary;
		movePSO = [device newComputePipelineStateWithFunction:
			[dfltLib newFunctionWithName:@"moveAgent"] error:&error];
		if (movePSO == nil) @throw error;
		commandQueue = device.newCommandQueue;
		pop_init();
		NewPopSize = PopSize;
	} @catch (NSObject *obj) { err_msg(obj, YES); }
	return device;
}
void pop_step4(float deltaTime) {
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"MyCommand";
	id<MTLComputeCommandEncoder> cce = cmdBuf.computeCommandEncoder;
	[cce setComputePipelineState:movePSO];
	NSInteger idx = 0;
	[cce setBuffer:popSimBuf offset:0 atIndex:idx ++];
	[cce setBuffer:forceBuf offset:0 atIndex:idx ++];
	[cce setBuffer:cellBuf offset:0 atIndex:idx ++];
	[cce setBuffer:idxsBuf offset:0 atIndex:idx ++];
	[cce setBuffer:taskBf[taskBfIdx] offset:0 atIndex:idx ++];
	[cce setBytes:&deltaTime length:sizeof(deltaTime) atIndex:idx ++];
	[cce setBytes:&WS length:sizeof(WS) atIndex:idx ++];
	[cce setBytes:&PrmsSim length:sizeof(Params) atIndex:idx ++];
	NSUInteger threadGrpSz = movePSO.maxTotalThreadsPerThreadgroup;
	if (threadGrpSz > PopSize) threadGrpSz = PopSize;
	[cce dispatchThreads:MTLSizeMake(PopSize, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
	[cce endEncoding];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
}

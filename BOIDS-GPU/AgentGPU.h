//
//  AgentGPU.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

extern id<MTLComputePipelineState> movePSO, shapePSO;
extern id<MTLRenderPipelineState> bgPSO, drawPSO;
extern id<MTLCommandQueue> commandQueue;
extern id<MTLBuffer> popSimBuf, popDrawBuf, forceBuf, cellBuf, idxsBuf, vxBuf;
extern id<MTLBuffer> _Nonnull taskBf[2];	// for double buffering
extern NSInteger taskBfIdx, NewPopSize;

extern void alloc_pop_mem(id<MTLDevice> device);
extern void alloc_cell_mem(id<MTLDevice> device);
extern id<MTLDevice> setup_GPU(void);
extern void pop_step4(float deltaTime);

NS_ASSUME_NONNULL_END

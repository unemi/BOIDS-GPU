//
//  MetalView.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

typedef id<MTLComputeCommandEncoder> CCE;
typedef id<MTLRenderCommandEncoder> RCE;

@interface MyMTKView : MTKView
@end

@interface MetalView : NSObject
<MTKViewDelegate, NSMenuItemValidation, NSWindowDelegate>
@property IBOutlet MyMTKView *view;
- (void)revisePopSize:(NSInteger)newSize;
@end

extern CGFloat FPS;
extern simd_float3 BirdRGB;
extern NSInteger NewPopSize;

NS_ASSUME_NONNULL_END

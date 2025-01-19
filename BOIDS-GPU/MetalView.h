//
//  MetalView.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

typedef struct {
	float depth, scale, contrast;
	float agentSize, agentOpacity;
} ViewParams;
typedef enum { ShapePaperPlane, ShapeBlob } ShapeType;
#define AGENT_OPACITY_IDX (N_PARAMS+4)
#define N_VPARAMS (sizeof(ViewParams)/sizeof(float))

@interface MyMTKView : MTKView
@end

@interface MetalView : NSObject
<MTKViewDelegate, NSMenuItemValidation, NSWindowDelegate>
@property IBOutlet MyMTKView *view;
- (void)revisePopSize:(NSInteger)newSize;
- (void)reviseSightDistance;
@end

extern CGFloat FPS;
extern simd_float3 WallRGB, AgntRGB;
extern ViewParams ViewPrms, DfltViewPrms;
extern ShapeType shapeType;
extern NSString * _Nonnull ViewPrmLbls[];

NS_ASSUME_NONNULL_END

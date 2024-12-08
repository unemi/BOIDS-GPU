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
} ViewParams;
#define N_VPARAMS (sizeof(ViewParams)/sizeof(float))

@interface MyMTKView : MTKView
@end

@interface MetalView : NSObject
<MTKViewDelegate, NSMenuItemValidation, NSWindowDelegate>
@property IBOutlet MyMTKView *view;
- (void)revisePopSize:(NSInteger)newSize;
@end

extern CGFloat FPS;
extern simd_float3 BirdRGB;
extern ViewParams ViewPrms, DfltViewPrms;
extern NSString * _Nonnull ViewPrmLbls[];

NS_ASSUME_NONNULL_END

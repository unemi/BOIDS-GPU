//
//  AgentGPU.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

#import <Foundation/Foundation.h>
@import simd;

NS_ASSUME_NONNULL_BEGIN

#define CELL_UNIT 1
#define N_CELLS_X CELL_UNIT*16
#define N_CELLS_Y CELL_UNIT*9
#define N_CELLS_Z CELL_UNIT*12
#define N_CELLS (N_CELLS_X*N_CELLS_Y*N_CELLS_Z)

typedef struct { simd_float3 p, v; } Agent;
typedef struct { NSInteger start, n; } Cell;
typedef struct { NSInteger idx, nc; int n, cIdxs[8]; } Task;
typedef struct {
	float avoid, cohide, align, mass, maxV, minV, fric, nd, tmMS;
} Params;

#define N_PAAMS (sizeof(Params)/sizeof(float)-2)

extern NSInteger PopSize, Step;
extern simd_float3 WS;
extern Params PrmsDefault, Prms;
extern NSString * _Nonnull PrmLabels[];
extern float CellSize, ND;
extern Agent *Pop;
extern simd_float3 *Forces;
extern Cell *Cells;
extern Task *TaskQueue, *TasQWork;
extern NSInteger *Idxs;
extern unsigned long current_time_us(void);
extern void pop_reset(void);
extern void pop_mem_init(NSInteger popSize);
extern void pop_init(void);
extern void pop_step1(void);
extern void pop_step2(void);
extern BOOL pop_step3(void);

NS_ASSUME_NONNULL_END

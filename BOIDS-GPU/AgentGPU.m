//
//  AgentGPU.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

#import <sys/time.h>
#import <sys/sysctl.h>
#import "AgentGPU.h"
#import "AppDelegate.h"

#define STD_POPSIZE 1000.
#define STD_CELSIZE 12.
NSInteger PopSize = 120000, Step;
float CellSize, ND = STD_CELSIZE*.75; // max distance to neighbor
simd_float3 WS;	// World Size
Params PrmsDefault = { .avoid = .05, .cohide = 1e-3, .align = .05,
	.mass = 2., .maxV = .05, .minV = .02, .fric = .05 }, Prms;
NSString * _Nonnull PrmLabels[] = {
	@"Avoidance", @"Cohision", @"Alignment",
	@"Mass", @"Max Speed", @"Min Speed", @"Friction" };
Agent *Pop = NULL;
simd_float3 *Forces;
Cell *Cells;
Task *TaskQueue, *TasQWork;
NSInteger *Idxs;
static NSInteger nCores = 0;
static dispatch_group_t DispatchGrp;
static dispatch_queue_t DispatchQue;
static NSInteger *CelIdxs = NULL;
#define MAX_CELL_IDX (simd_int3){N_CELLS_X-1,N_CELLS_Y-1,N_CELLS_Z-1}

unsigned long current_time_us(void) {
	static long startTime = -1;
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if (startTime < 0) startTime = tv.tv_sec;
	return (tv.tv_sec - startTime) * 1000000L + tv.tv_usec;
}
static simd_int3 cell_idx_v(simd_float3 p) {
	return simd_clamp(simd_int(p/CellSize), 0, MAX_CELL_IDX);
}
static void check_wall(NSInteger aIdx, NSInteger elm, float p, float nd, float avd) {
	float d = fabsf(Pop[aIdx].p[elm] - p);
	if (d > nd) return;
	float f = avd / d / d;
	Forces[aIdx][elm] += (p <= 0.)? f : - f;
}
void pop_reset(void) {
	for (NSInteger i = 0; i < PopSize; i ++) {
		Agent *a = &Pop[i];
		a->p = (simd_float3){drand48(), drand48(), drand48()} * (WS - ND) + ND/2.;
		float th = drand48() * M_PI*2, phi = (drand48() - .5) * M_PI/3;
		a->v = (simd_float3){cosf(th)*cosf(phi), sinf(phi), sinf(th)*cosf(phi)} * .01;
	}
	Step = 0;
}
void pop_mem_init(NSInteger popSize) {
	CelIdxs = realloc(CelIdxs, sizeof(NSInteger) * popSize);
	CellSize = pow(popSize / STD_POPSIZE, 1./3.) * STD_CELSIZE / CELL_UNIT;
	if (ND > CellSize / 2.) {
		CellSize = ND * 2.;
//		printf("Cell size was revised as PopSize %ld is too small.\n", PopSize);
	} 
	WS = (simd_float3){CellSize*N_CELLS_X, CellSize*N_CELLS_Y, CellSize*N_CELLS_Z};
	Prms.nd = ND;
}
void pop_init(void) {
	Prms = PrmsDefault;
	if (nCores == 0) { // get the number of performance cores.
		size_t len = sizeof(int32_t);
		int32_t nCpus;
		sysctlbyname("hw.perflevel0.physicalcpu", &nCpus, &len, NULL, 0);
		nCores = nCpus;
	}
	DispatchGrp = dispatch_group_create();
	DispatchQue = dispatch_queue_create("MyQueue", DISPATCH_QUEUE_CONCURRENT);
}
static BOOL merge_sort(Task *src, Task *work, NSInteger n) {
	if (n <= (PopSize + nCores - 1) / nCores) {
		qsort_b(src, n, sizeof(Task), ^(const void *a, const void *b){
			NSInteger p = ((Task *)a)->nc, q = ((Task *)b)->nc;
			return (p > q)? -1 : (p < q)? 1 : 0;
		});
		return NO;
	} else {
		BOOL m1, m2, *mp1 = &m1;
		dispatch_group_t grp = dispatch_group_create();
		dispatch_queue_t que = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
		dispatch_group_async(grp, que, ^{ *mp1 = merge_sort(src, work, n/2); });
		m2 = merge_sort(src+n/2, work+n/2, n-n/2);
		dispatch_group_wait(grp, DISPATCH_TIME_FOREVER);
		Task *tmp, *result;
		if (m1) { tmp = src; result = work; }
		else { tmp = work; result = src; }
		if (m1 != m2) memcpy(result+n/2, tmp+n/2, sizeof(Task)*(n-n/2));
		dispatch_group_async(grp, que, ^{ 
			NSInteger j = 0, k = n / 2;
			for (NSInteger i = 0; i < n / 2; i ++) {
				if (j >= n / 2) tmp[i] = result[k ++];
				else if (k >= n) tmp[i] = result[j ++];
				else if (result[j].nc >= result[k].nc) tmp[i] = result[j ++];
				else tmp[i] = result[k ++];
			}
		});
		NSInteger j = n / 2 - 1, k = n - 1;
		for (NSInteger i = n - 1; i >= n / 2; i --) {
			if (j < 0) tmp[i] = result[k --];
			else if (k < n / 2) tmp[i] = result[j --];
			else if (result[j].nc < result[k].nc) tmp[i] = result[j --];
			else tmp[i] = result[k --];
		}
		dispatch_group_wait(grp, DISPATCH_TIME_FOREVER);
		return !m1;
	}
}
void pop_step1(void) {
	memset(Cells, 0, sizeof(Cell) * N_CELLS);
	NSInteger *cn = alloca(sizeof(NSInteger) * N_CELLS * nCores), ii[N_CELLS];
	memset(cn, 0, sizeof(ii) * nCores);
	memset(ii, 0, sizeof(ii));
	NSInteger nAg = PopSize / nCores;
	void (^block)(NSInteger, NSInteger) = ^(NSInteger from, NSInteger to) {
		for (NSInteger i = from; i < to; i ++) {
			simd_int3 v = simd_clamp(simd_int(Pop[i].p/CellSize), 0, MAX_CELL_IDX);
			CelIdxs[i] = (v.x * N_CELLS_Y + v.y) * N_CELLS_Z + v.z;
			cn[CelIdxs[i] + N_CELLS * from/nAg] ++;
		}
	};
	for (NSInteger i = 0; i < nCores-1; i ++)
		dispatch_group_async(DispatchGrp, DispatchQue, ^{ block(i*nAg, (i+1)*nAg); } );
	block((nCores-1)*nAg, PopSize);
	dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	for (NSInteger i = 0; i < nCores; i ++)
	for (NSInteger j = 0; j < N_CELLS; j ++)
		Cells[j].n += cn[j + N_CELLS * i];
	NSInteger nn = 0;
	for (NSInteger i = 0; i < N_CELLS; i ++)
		{ Cells[i].start = nn; nn += Cells[i].n; }
	for (NSInteger i = 0; i < PopSize; i ++) {
		NSInteger cIdx = CelIdxs[i];
		Idxs[Cells[cIdx].start + (ii[cIdx] ++)] = i;
	}
}
void pop_step2(void) {
	memset(Forces, 0, sizeof(simd_float3) * PopSize);
	float nd = ND*2., avd = .2;
	for (NSInteger j = 0; j < N_CELLS_Y; j ++)
	dispatch_group_async(DispatchGrp, DispatchQue, ^{
	for (NSInteger i = 0; i < 2; i ++)
	for (NSInteger k = 0; k < N_CELLS_Z; k ++) {
		Cell *c = &Cells[(i * (N_CELLS_X - 1) * N_CELLS_Y + j) * N_CELLS_Z + k];
		for (int ii = 0; ii < c->n; ii ++)
			check_wall(Idxs[c->start + ii], 0, i * WS[0], nd, avd);
	}});
	dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	for (NSInteger j = 0; j < N_CELLS_X; j ++)
	dispatch_group_async(DispatchGrp, DispatchQue, ^{
	for (NSInteger i = 0; i < 2; i ++)
	for (NSInteger k = 0; k < N_CELLS_Z; k ++) {
		Cell *c = &Cells[(j * N_CELLS_Y + i * (N_CELLS_Y - 1)) * N_CELLS_Z + k];
		for (int ii = 0; ii < c->n; ii ++)
			check_wall(Idxs[c->start + ii], 1, i * WS[1], nd, avd);
	}});
	dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	for (NSInteger j = 0; j < N_CELLS_X; j ++)
	dispatch_group_async(DispatchGrp, DispatchQue, ^{
	for (NSInteger i = 0; i < 2; i ++)
	for (NSInteger k = 0; k < N_CELLS_Y; k ++) {
		Cell *c = &Cells[(j * N_CELLS_Y + k) * N_CELLS_Z + i * (N_CELLS_Z - 1)];
		for (int ii = 0; ii < c->n; ii ++)
			check_wall(Idxs[c->start + ii], 2, i * WS[2], nd, avd);
	}});
	dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
}
BOOL pop_step3(void) {
	NSInteger nAg = PopSize / nCores;
	void (^blockTQ)(NSInteger) = ^(NSInteger aIdx) {
		simd_int3 idxV = cell_idx_v(Pop[aIdx].p);
		simd_float3 rp = simd_fract(Pop[aIdx].p / CellSize);
		float rLow = ND / CellSize, rUp = 1. - rLow;
		simd_int3 from = idxV, to = idxV, upLm = {N_CELLS_X-1,N_CELLS_Y-1,N_CELLS_Z-1};
		for (NSInteger i = 0; i < 3; i ++) {
			if (rp[i] > rUp && to[i] < upLm[i]) to[i] ++;
			else if (rp[i] < rLow && from[i] > 0) from[i] --;  
		}
		Task tsk = {.idx = aIdx, .nc = 0, .n = 0};
		for (NSInteger i = from.x; i <= to.x; i ++)
		for (NSInteger j = from.y; j <= to.y; j ++)
		for (NSInteger k = from.z; k <= to.z; k ++) {
			int idx = (int)((i * N_CELLS_Y + j) * N_CELLS_Z + k);
			tsk.cIdxs[tsk.n ++] = idx;
			tsk.nc += Cells[idx].n;
		}
		TaskQueue[aIdx] = tsk;
	};
	for (NSInteger i = 0; i < nCores - 1; i ++) {
		dispatch_group_async(DispatchGrp, DispatchQue, ^{
			for (NSInteger j = 0; j < nAg; j ++) blockTQ(i * nAg + j); });
	}
	for (NSInteger j = (nCores-1)*nAg; j < PopSize; j ++) blockTQ(j);
	dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	return merge_sort(TaskQueue, TasQWork, PopSize);
}
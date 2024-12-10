//
//  AgentCPU.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

#import <sys/time.h>
#import <sys/sysctl.h>
#import "AgentCPU.h"
#import "AppDelegate.h"

#define STD_POPSIZE 1000.
#define STD_CELSIZE 12.
NSInteger PopSize = 120000, Step;
int32_t CellUnit = 0;
float CellSize;
#define NEAR_DIST (STD_CELSIZE*.75) // max distance to neighbor
simd_float3 WS;	// World Size
Params PrmsUI, PrmsSim;
static Params PrmsSTD = { .avoid = .05, .cohide = 1e-3, .align = .05,
	.sightDist = 1., .sightAngle = 1.,
	.mass = 2., .maxV = .05, .minV = .02, .fric = .05 },
	PrmsBase = { .avoid = 5., .cohide = 5., .align = 10.,
	.sightDist = 2., .sightAngle = 2.,
	.mass = 5., .maxV = 2., .minV = 2., .fric = 5. };
NSString * _Nonnull PrmLabels[] = {
	@"Avoidance", @"Cohision", @"Alignment",
	@"Sight Distance", @"Sight Angle",
	@"Mass", @"Max Speed", @"Min Speed", @"Friction" };
Agent *Pop = NULL;
simd_float3 *Forces;
Cell *Cells;
Task *TaskQueue, *TasQWork;
uint32_t *Idxs;
static int32_t *TmpCellMem = NULL;
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
static void check_wall(NSInteger aIdx, NSInteger elm, float p, float nd, float avd) {
	float d = fabsf(Pop[aIdx].p[elm] - p);
	if (d > nd) return;
	float f = avd / d / d;
	Forces[aIdx][elm] += (p <= 0.)? f : - f;
}
void pop_reset(void) {
	for (NSInteger i = 0; i < PopSize; i ++) {
		Agent *a = &Pop[i];
		a->p = (simd_float3){drand48(), drand48(), drand48()} * (WS - NEAR_DIST) + NEAR_DIST/2.;
		float th = drand48() * M_PI*2, phi = (drand48() - .5) * M_PI/3;
		a->v = (simd_float3){cosf(th)*cosf(phi), sinf(phi), sinf(th)*cosf(phi)} * .01;
	}
	Step = 0;
}
BOOL check_cell_unit(NSInteger popSize) {
	CellSize = pow(popSize / STD_POPSIZE, 1./3.) * STD_CELSIZE;
	float nd = PrmsSim.sightDist;
	int cellUnit = log2(CellSize / 2. / nd) + 1;
	if (cellUnit < 1) {
		CellSize = nd * 2.;
		cellUnit = 1;
	} else CellSize /= cellUnit;
	BOOL revised = cellUnit != CellUnit;
	if (revised) {
		CellUnit = cellUnit;
		TmpCellMem = realloc(TmpCellMem, sizeof(int32_t) * N_CELLS * (nCores + 1));
	}
	return revised;
}
BOOL pop_mem_init(NSInteger popSize) {
	CelIdxs = realloc(CelIdxs, sizeof(NSInteger) * popSize);
	BOOL cellUnitRevised = check_cell_unit(popSize);
	WS = (simd_float3){CellSize*N_CELLS_X, CellSize*N_CELLS_Y, CellSize*N_CELLS_Z};
	return cellUnitRevised;
}
void pop_init(void) {
	memset(&PrmsUI, 0, sizeof(Params));
	memcpy(&PrmsSim, &PrmsSTD, sizeof(Params));
	PrmsSim.sightDist *= NEAR_DIST;
	if (nCores == 0) { // get the number of performance cores.
		size_t len = sizeof(int32_t);
		int32_t nCpus;
		sysctlbyname("hw.perflevel0.physicalcpu", &nCpus, &len, NULL, 0);
		nCores = nCpus;
	}
	DispatchGrp = dispatch_group_create();
	DispatchQue = dispatch_queue_create("MyQueue", DISPATCH_QUEUE_CONCURRENT);
}
void set_sim_params(void) {
	float *prmsUI = (float *)(&PrmsUI), *prmsSim = (float *)(&PrmsSim),
		*std = (float *)(&PrmsSTD), *base = (float *)(&PrmsBase);
	for (NSInteger i = 0; i < N_PARAMS; i ++)
		prmsSim[i] = std[i] * pow(base[i], prmsUI[i]);
	PrmsSim.sightDist *= NEAR_DIST;
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
	int32_t *ii = TmpCellMem, *cn = ii + N_CELLS;
	memset(ii, 0, sizeof(NSInteger) * N_CELLS * (nCores + 1));
	NSInteger nAg = PopSize / nCores;
	void (^block)(NSInteger, NSInteger) = ^(NSInteger from, NSInteger to) {
		int32_t *ccn = cn + N_CELLS * from / nAg;
		for (NSInteger i = from; i < to; i ++) {
			simd_int3 v = simd_int(Pop[i].p / CellSize);
			CelIdxs[i] = (v.x * N_CELLS_Y + v.y) * N_CELLS_Z + v.z;
			ccn[CelIdxs[i]] ++;
		}
	};
	for (NSInteger i = 0; i < nCores-1; i ++)
		dispatch_group_async(DispatchGrp, DispatchQue, ^{ block(i*nAg, (i+1)*nAg); } );
	block((nCores-1)*nAg, PopSize);
	dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	for (NSInteger i = 0; i < nCores; i ++)
	for (NSInteger j = 0; j < N_CELLS; j ++)
		Cells[j].n += cn[j + N_CELLS * i];
	uint32_t nn = 0;
	for (NSInteger i = 0; i < N_CELLS; i ++)
		{ Cells[i].start = nn; nn += Cells[i].n; }
	for (NSInteger i = 0; i < PopSize; i ++) {
		NSInteger cIdx = CelIdxs[i];
		Idxs[Cells[cIdx].start + (ii[cIdx] ++)] = (uint32_t)i;
	}
}
void pop_step2(void) {
	memset(Forces, 0, sizeof(simd_float3) * PopSize);
	float nd = NEAR_DIST*2., avd = .2;
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
		simd_float3 p = Pop[aIdx].p / CellSize, rp = simd_fract(p);
		simd_int3 idxV = simd_int(p);
		float rLow = PrmsSim.sightDist / CellSize, rUp = 1. - rLow;
		simd_int3 from = idxV, to = idxV, upLm = MAX_CELL_IDX;
		for (NSInteger i = 0; i < 3; i ++) {
			if (rp[i] > rUp && to[i] < upLm[i]) to[i] ++;
			else if (rp[i] < rLow && from[i] > 0) from[i] --;  
		}
		Task tsk = {.idx = (int)aIdx, .nc = 0, .n = 0};
		for (int i = from.x; i <= to.x; i ++)
		for (int j = from.y; j <= to.y; j ++)
		for (int k = from.z; k <= to.z; k ++) {
			int idx = (i * N_CELLS_Y + j) * N_CELLS_Z + k;
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

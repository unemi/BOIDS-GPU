//
//  MyShader.metal
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

#include <metal_stdlib>
using namespace metal;
typedef struct { float3 p, v; } Agent;
typedef struct { long start, n; } Cell;
typedef struct { long idx, nc; int n, cIdxs[8]; } Task;
typedef struct {
	float avoid, cohide, align, mass, maxV, minV, fric, nd, tmMS;
} Params;

kernel void moveAgent(device Agent *pop, constant float3 *forces,
	constant Cell *cells, constant long *idxs, constant Task *tasks,
	constant float3 *size, constant Params *params,
	uint index [[thread_position_in_grid]]) {

	Task tsk = tasks[index];
	long aIdx = tsk.idx;
	Agent a = pop[aIdx];
	float3 ff = forces[aIdx], cc = 0., aa = 0.;
	float sumDI = 0.;
	for (int i = 0; i < tsk.n; i ++) {
		Cell c = cells[tsk.cIdxs[i]];
		for (int j = 0; j < c.n; j ++) {
			int bIdx = idxs[c.start + j];
			if (bIdx == aIdx) continue;
			Agent b = pop[bIdx];
			float3 dv = a.p - b.p;
			float d = length(dv);
			if (d > params->nd) continue;
			ff += dv * params->avoid / (d * d * d);
			cc += b.p / d;
			aa += b.v / d;
			sumDI += 1. / d;
		}
	}
	float3 WS = *size;
	if (sumDI > 0.) ff +=
		(cc / sumDI - a.p) * params->cohide +
		aa / sumDI * params->align;
	a.v += ff / params->mass * params->tmMS;
	a.v *= 1. - params->fric;
	float v = length(a.v);
	float pa = atan2(a.v.z, length(a.v.xy));
	if (abs(pa) > M_PI_4_F) {
		a.v.z = v / ((pa > 0.)? M_SQRT2_F : -M_SQRT2_F);
		a.v.xy *= M_SQRT1_2_F / cos(pa);
	}	
	if (v > params->maxV) a.v *= params->maxV / v;
	else if (v < params->minV) a.v *= params->minV / v;
	a.p += a.v * params->tmMS;
	for (int j = 0; j < 3; j ++) {
		if (a.p[j] < 0.) { a.p[j] = - a.p[j]; a.v[j] = - a.v[j]; }
		else if (a.p[j] > WS[j]) {
			a.p[j] = WS[j] * 2. - a.p[j]; a.v[j] = - a.v[j];
		}
	}
	pop[aIdx] = a;
}
kernel void makeSpape(constant Agent *pop, constant float3 *size,
	constant float2 *camPose,
	device float2 *shapes, uint index [[thread_position_in_grid]]) {
	Agent a = pop[index];
	float lxz = length(a.v.xz), v = length(a.v);
	float2 t = a.v.xz / lxz, p = float2(lxz, a.v.y) / v;
	float3x3 mx = {{t.x*p.x,-t.x*p.y,-t.y}, {p.y,p.x,0}, {t.y*p.x,-t.y*p.y,t.x}};
	float3 sh[] = {{2,0,0},{-1,0,-1},{-1,0,1}, {2,0,0},{-1,0,0},{-1,-1,0}};
	for (int i = 0; i < 6; i ++) {
		float3 p = a.p + sh[i] * mx;
		shapes[index * 6 + i] = (p.xy - size->xy / 2.) / size->xy * 2.
			* camPose->x / (camPose->x + p.z) * camPose->y;
	}
}
vertex float4 vertexShader(uint vertexID [[vertex_id]],
	constant float2 *vertices) {
    float4 out = {0.,0.,0.,1.};
    out.xy = vertices[vertexID];
    return out;
}
fragment float4 fragmentShader(constant float3 *col,
	float4 in [[stage_in]]) {
    return float4(*col, 1.);
}


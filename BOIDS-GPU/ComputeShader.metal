//
//  ComputeShader.metal
//  BOIDS GPU
//
//  Created by Tatsuo Unemi on 2024/12/08.
//

#include "ShaderHeader.metal"

kernel void moveAgent(device Agent *pop, constant float3 *forces,
	constant Cell *cells, constant long *idxs, constant Task *tasks,
	constant float *deltaTime, constant float3 *size, constant Params *params,
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
			if (d > params->sightD) continue;
			if (distance(normalize(a.v), normalize(dv))
				< 2. - params->sightA) continue;
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
	a.v += ff / params->mass * *deltaTime;
	a.v *= 1. - params->fric;
	float v = length(a.v);
	float tilt = atan2(a.v.z, length(a.v.xy));
	if (abs(tilt) > M_PI_4_F) {
		a.v.z = v / ((tilt > 0.)? M_SQRT2_F : -M_SQRT2_F);
		a.v.xy *= M_SQRT1_2_F / cos(tilt);
	}	
	if (v > params->maxV) a.v *= params->maxV / v;
	else if (v < params->minV) a.v *= params->minV / v;
	a.p += a.v * *deltaTime;
	for (int j = 0; j < 3; j ++) {
		if (a.p[j] < 0.) { a.p[j] = - a.p[j]; a.v[j] = - a.v[j]; }
		else if (a.p[j] > WS[j]) {
			a.p[j] = WS[j] * 2. - a.p[j]; a.v[j] = - a.v[j];
		}
	}
	pop[aIdx] = a;
}

//
//  ComputeShader.metal
//  BOIDS GPU
//
//  Created by Tatsuo Unemi on 2024/12/08.
//

#include "ShaderHeader.metal"
#define MaxElev (M_PI_4_F/2.)

kernel void moveAgent(device Agent *pop, constant float3 *forces,
	constant Cell *cells, constant uint *idxs, constant Task *tasks,
	constant float *deltaTime, constant float3 *size, constant Params *params,
	uint index [[thread_position_in_grid]]) {

	Task tsk = tasks[index];
	uint aIdx = tsk.idx;
	Agent a = pop[aIdx];
	float3 WS = *size, ff = forces[aIdx], cc = 0., aa = 0.;
	float sumDI = 0., dt = *deltaTime;
	a.p += a.v * dt;
	for (int j = 0; j < 3; j ++) {
		if (a.p[j] < 0.) { a.p[j] = - a.p[j]; a.v[j] = - a.v[j]; }
		else if (a.p[j] > WS[j]) {
			a.p[j] = WS[j] * 2. - a.p[j]; a.v[j] = - a.v[j];
		}
	}
	for (uint i = 0; i < tsk.n; i ++) {
		Cell c = cells[tsk.cIdxs[i]];
		for (uint j = 0; j < c.n; j ++) {
			uint bIdx = idxs[c.start + j];
			if (bIdx == aIdx) continue;
			Agent b = pop[bIdx];
			float3 dv = a.p - b.p;
			float d = length(dv);
			if (d > params->sightD) continue;
			if (distance(normalize(a.v), normalize(dv))
				< 2. - params->sightA) continue;
			if (d < .001) d = .001;
			ff += dv * params->avoid / (d * d * d);
			cc += b.p / d;
			aa += b.v / d;
			sumDI += 1. / d;
		}
	}
	if (sumDI > 0.) ff +=
		(cc / sumDI - a.p) * params->cohide +
		aa / sumDI * params->align;
	a.v = (a.v + ff / params->mass * dt) * pow(1. - params->fric, dt);
	float v = length(a.v);
	float tilt = atan2(a.v.z, length(a.v.xy));
	if (abs(tilt) > MaxElev) {
		a.v.z = v * ((tilt > 0.)? sin(MaxElev) : -sin(MaxElev));
		a.v.xy *= cos(MaxElev) / cos(tilt);
	}	
	if (v > params->maxV) a.v *= params->maxV / v;
	else if (v < params->minV) a.v *= params->minV / v;
	if (any(isnan(v))) a.v = float3(params->minV);
	pop[aIdx] = a;
}

//
//  MyShader.metal
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

#include "ShaderHeader.metal"

float2 map3D_to_2D(float3 p, float3 size, float2 camPose) {
	return (p.xy - size.xy / 2.) / size.xy * 2.
		* camPose.x / (camPose.x + p.z) * camPose.y;
} 
kernel void makeShape(constant Agent *pop, constant float3 *size,
	constant float2 *camPose, constant float *agntSz,
	device float2 *shapes, uint index [[thread_position_in_grid]]) {
	Agent a = pop[index];
	float lxz = length(a.v.xz), v = length(a.v);
	float2 t = a.v.xz / lxz, p = float2(lxz, a.v.y) / v;
	float3x3 mx = {{t.x*p.x,-t.x*p.y,-t.y}, {p.y,p.x,0}, {t.y*p.x,-t.y*p.y,t.x}};
	float3 sh[] = {{2,0,0},{-1,0,-1},{-1,0,1}, {2,0,0},{-1,0,0},{-1,-1,0}};
	for (int i = 0; i < 6; i ++) shapes[index * 6 + i] =
		map3D_to_2D(a.p + sh[i] * *agntSz * mx, *size, *camPose);
}
vertex float4 vertexShaderBG(uint vertexID [[vertex_id]],
	constant float3 *size, constant float2 *camPose, constant float3 *corners) {
    return float4(map3D_to_2D(corners[vertexID], *size, *camPose),0.,1.);
}
vertex float4 vertexShader(uint vertexID [[vertex_id]],
	constant float2 *vertices) {
    return float4(vertices[vertexID], 0., 1.);
}
fragment float4 fragmentShader(constant float4 *col,
	float4 in [[stage_in]]) {
    return *col;
}

kernel void makeSquare(constant Agent *pop, constant float3 *size,
	constant float2 *camPose, constant float *agntSz,
	device float2 *shapes, uint index [[thread_position_in_grid]]) {
	float3 sh[] = {{-1,-1,0},{-1,1,0},{1,-1,0},{1,1,0}};
	float3 p = pop[index].p;
	for (int i = 0; i < 4; i ++) shapes[index * 4 + i] =
		map3D_to_2D(p + sh[i] * 2. * *agntSz, *size, *camPose);
}
typedef struct {
	float4 position [[position]];
	float2 center;
	float radius;
} VertexOutBlob;
vertex VertexOutBlob vertexBlob(uint vertexID [[vertex_id]],
	constant float2 *vertices) {
	VertexOutBlob out;
	out.position = float4(vertices[vertexID], 0., 1.);
	uint ix = (vertexID / 4) * 4;
	out.center = (vertices[ix + 1] + vertices[ix + 2]) / 2.;
	out.radius = (vertices[ix + 3].x - vertices[ix].x) / 2.;
    return out;
}
fragment float4 fragmentBlob(constant float4 *col,
	constant float2 *vSize,
	VertexOutBlob in [[stage_in]]) {
	float2 vp = in.position.xy / *vSize * 2. - 1.;
	vp.y *= -1.;
	return float4(col->rgb, col->a *
		(1. - length((vp - in.center) * float2(1., 9./16.)) / in.radius));
}

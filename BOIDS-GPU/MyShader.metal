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
kernel void makeSpape(constant Agent *pop, constant float3 *size,
	constant float2 *camPose,
	device float2 *shapes, uint index [[thread_position_in_grid]]) {
	Agent a = pop[index];
	float lxz = length(a.v.xz), v = length(a.v);
	float2 t = a.v.xz / lxz, p = float2(lxz, a.v.y) / v;
	float3x3 mx = {{t.x*p.x,-t.x*p.y,-t.y}, {p.y,p.x,0}, {t.y*p.x,-t.y*p.y,t.x}};
	float3 sh[] = {{2,0,0},{-1,0,-1},{-1,0,1}, {2,0,0},{-1,0,0},{-1,-1,0}};
	for (int i = 0; i < 6; i ++)
		shapes[index * 6 + i] = map3D_to_2D(a.p + sh[i] * mx, *size, *camPose);
}
vertex float4 vertexShaderBG(uint vertexID [[vertex_id]],
	constant float3 *size, constant float2 *camPose, constant float3 *corners) {
    return float4(map3D_to_2D(corners[vertexID], *size, *camPose),0.,1.);
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

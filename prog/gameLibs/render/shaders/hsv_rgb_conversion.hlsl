#ifndef hsv_rgb_conversion
#define hsv_rgb_conversion

// pulled them straight out from "g3dmath.hlsl", cannot include it in some places due to name clashing

/** \cite http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl */
float3 rgb_to_hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = (c.g < c.b) ? float4(c.bg, K.wz) : float4(c.gb, K.xy);
    float4 q = (c.r < p.x) ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
    float d = q.x - min(q.w, q.y);
    float eps = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + eps)), d / (q.x + eps), q.x);
}
/** \cite http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl */
float3 hsv_to_rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), clamp(c.y, 0.0, 1.0));
}

#endif

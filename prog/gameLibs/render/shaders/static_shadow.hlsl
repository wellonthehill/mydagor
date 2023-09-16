#ifndef STATIC_SHADOW_HLSL
#define STATIC_SHADOW_HLSL 1

half static_shadow_sample_fxaa(float2 pos, float z, texture_ref tex, sampler_state_ref tex_samplerstate, float layer, float texel_size )
{
  float2 fxaaConsoleRcpFrameOpt = 0.5*texel_size;

  float4 fxaaConsolePosPos = float4(pos - fxaaConsoleRcpFrameOpt, pos + fxaaConsoleRcpFrameOpt);
  half4 luma = half4(
           static_shadow_sample(fxaaConsolePosPos.xy, z, tex, tex_samplerstate, layer),
           static_shadow_sample(fxaaConsolePosPos.xw, z, tex, tex_samplerstate, layer),
           static_shadow_sample(fxaaConsolePosPos.zy, z, tex, tex_samplerstate, layer),
           static_shadow_sample(fxaaConsolePosPos.zw, z, tex, tex_samplerstate, layer));

   #if STATIC_SHADOW_REFERENCE_FXAA_IMPL//+2 additional samples, i.e. 9 total
   {
     #define FXAA_REDUCE_MUL   (1.0/1.0)
     #define FXAA_SPAN_MAX     1.0
     half lumaNW = luma.x;
     half lumaNE = luma.z;
     half lumaSW = luma.y;
     half lumaSE = luma.w;
     half lumaM = static_shadow_sample(pos, z, tex, tex_samplerstate, layer);
     half lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
     half lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
     float2 dir;
     dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
     dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));
     half dirReduce = (lumaNW + lumaNE + lumaSW + lumaSE) * half(0.25 * FXAA_REDUCE_MUL);
     half rcpDirMin = half(1.0) / half(min(abs(dir.x), abs(dir.y)) + dirReduce);
     dir = min(half2( FXAA_SPAN_MAX,  FXAA_SPAN_MAX),
           max(half2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX),
           dir * rcpDirMin)) * (half2)texel_size;
     half lumaA = half(1.0/2.0) * (half)(
         static_shadow_sample(pos.xy + dir * (1.0/3.0 - 0.5), z, tex, tex_samplerstate, layer) +
         static_shadow_sample(pos.xy + dir * (2.0/3.0 - 0.5), z, tex, tex_samplerstate, layer));
     half lumaB = lumaA * half(1.0/2.0) + half(1.0/4.0) * half(
         static_shadow_sample(pos.xy + dir * (0.0/3.0 - 0.5), z, tex, tex_samplerstate, layer) +
         static_shadow_sample(pos.xy + dir * (3.0/3.0 - 0.5), z, tex, tex_samplerstate, layer));

     if ((lumaB < lumaMin) || (lumaB > lumaMax))
       return lumaA;
     return lumaB;
   }
   #endif

   half2 dir = half2(
     dot(luma, half4(-1.0h,-1.0h,1.0h,1.0h)),
     dot(luma, half4(-1.0h,1.0h,-1.0h,1.0h)));

  float2 dir2 = dir.xy * fxaaConsoleRcpFrameOpt;

   half3 grad = half3(
     static_shadow_sample(pos.xy, z, tex, tex_samplerstate, layer),
     static_shadow_sample(pos.xy - dir2, z, tex, tex_samplerstate, layer),
     static_shadow_sample(pos.xy + dir2, z, tex, tex_samplerstate, layer));

   return saturate(dot(grad, half3(0.2h, 0.4h, 0.4h) ));
}

#define NUM_STATIC_SHADOW_SAMPLES 8
static const float2 static_shadow_offsets[NUM_STATIC_SHADOW_SAMPLES] = {
  float2( -0.7071,  0.7071),
  float2( -0.0000, -0.8750),
  float2(  0.5303,  0.5303),
  float2( -0.6250, -0.0000),
  float2(  0.3536, -0.3536),
  float2( -0.0000,  0.3750),
  float2( -0.1768, -0.1768),
  float2(  0.1250,  0.0000)
};

#ifndef STATIC_SHADOW_DITHER_RADIUS
#define STATIC_SHADOW_DITHER_RADIUS 2
#endif

half static_shadow_sample_8_tap(float2 pos, float z, texture_ref tex, sampler_state_ref tex_samplerstate, float layer, float texel_size, float dither )
{
  float3 depthShadowTC = float3(pos,z);
  float2 rotation;
  sincos((2.0f*PI)*dither, rotation.x, rotation.y);
  float2x2 rotationMatrix = {rotation.x, rotation.y, -rotation.y, rotation.x};
  const int NUM_SAMPLES = NUM_STATIC_SHADOW_SAMPLES;
  float radius = texel_size*STATIC_SHADOW_DITHER_RADIUS;
  rotationMatrix *= radius;
  half shadow = half(0.0);
  UNROLL
  for (int i = 0; i < NUM_SAMPLES; ++i)
  {
    float2 sampleOffset = mul(static_shadow_offsets[i], rotationMatrix);
    shadow += static_shadow_sample(depthShadowTC.xy+sampleOffset, depthShadowTC.z, tex, tex_samplerstate, layer);
  }
  return shadow * half(1./NUM_SAMPLES);
}

#if FASTEST_STATIC_SHADOW_PCF
  #define static_shadow_sample_opt(a,b,c,d,cid, e, dth) (1.h-static_shadow_sample(a,b,c,d,cid))
#else
  #if STATIC_SHADOW_DITHERED
  #define static_shadow_sample_opt(a,b,c,d,cid, e, dth) (1.h-static_shadow_sample_8_tap(a,b,c,d,cid, e, dth))
  #else
  #define static_shadow_sample_opt(a,b,c,d,cid, e, dth) (1.h-static_shadow_sample_fxaa(a,b,c,d,cid, e))
  #endif
#endif


half getStaticShadow(float3 worldPos, float dither, out uint cascade_id)
{
  cascade_id = 2;
#if STATIC_SHADOW_USE_CASCADE_0
  bool hardVignette0 = false;
  #if (STATIC_SHADOW_USE_CASCADE_0 && STATIC_SHADOW_USE_CASCADE_1) || STATIC_SHADOW_NO_VIGNETTE
  hardVignette0 = true;
  #endif

  float3 baseTc0 = get_static_shadow_tc_base(worldPos, staticShadowWorldRenderMatrix_0);
  float4 tc = get_static_shadow_tc(baseTc0, static_shadow_cascade_0_tor, dither, hardVignette0);
  float texel_size = staticShadowWorldRenderMatrix_0[0].w;
  float layer = 0;
  #if STATIC_SHADOW_USE_CASCADE_1
    bool hardVignette1 = false;
    #if STATIC_SHADOW_NO_VIGNETTE
    hardVignette1 = true;
    #endif
    float3 baseTc1 = get_static_shadow_tc_base(worldPos, staticShadowWorldRenderMatrix_1);
    float4 tc1 = get_static_shadow_tc(baseTc1, static_shadow_cascade_1_tor.xy, dither, hardVignette1);
    FLATTEN
    if ( !(tc.w > 0 && tc.z > 0.f) || (tc.z >= 1 && tc1.z < 1))
    {
      layer = 1;
      tc = tc1;
      texel_size = staticShadowWorldRenderMatrix_1[0].w;
    }
  #endif

  BRANCH
  if ( tc.w > 0 && tc.z > 0.f )
  {
    cascade_id = layer;
    half temp = 1.h - static_shadow_sample_opt(
      tc.xy, tc.z, static_shadow_tex, static_shadow_tex_cmpSampler, layer, texel_size, dither) * half(tc.w);

    return temp;
  }
#endif

  return half(1.0);
}


half getStaticShadow(float3 worldPos, float dither = 0)
{
  uint cascadeId;
  return getStaticShadow(worldPos, dither, cascadeId);
}

#endif

include "shader_global.sh"
include "gbuffer.sh"

texture source_color_tex;
float4 fxaa_params = (0.5, 0.166, 0.0833, 0);    // fxaaQualitySubpix, fxaaQualityEdgeThreshold, fxaaQualityEdgeThresholdMin
float4 fxaa_tc_scale_offset = float4(1.0, 1.0, 0.0, 0.0);

int fxaa_quality = 29;
interval fxaa_quality : 
  fxaa_quality_none < 0,
  fxaa_quality_low < 10,
  fxaa_quality_23 < 24, fxaa_quality_25 < 26, fxaa_quality_29 < 30,
  fxaa_quality_39;

float4 resolution = (1280, 720, 1.0/1280, 1.0/720);    // wd,ht, 1/width,1/height
int in_cockpit = 0;
interval in_cockpit: off<1, on;

int sharpness_on_selfillum = 1;
interval sharpness_on_selfillum: off<1, on;

int luminance_from_alpha = 0;
interval luminance_from_alpha : luminance_from_alpha_off < 1, luminance_from_alpha_on;

float4 adaptive_sharpen_quality = (0, 0, 16, 12);
float4 fxaa_color_mul = (1, 1, 1, 1);

texture material_data;

shader antialiasing
{
  supports global_frame;

  cull_mode  = none;
  z_write = false;

  if (use_screen_mask == yes)
  {
    z_test=true;
  }
  else
  {
    z_test=false;
  }

  USE_POSTFX_VERTEX_POSITIONS()
  INIT_ZNZFAR()
  INIT_READ_DEPTH_GBUFFER()
  USE_READ_DEPTH_GBUFFER()

  (vs) {
    resolution@f4 = resolution;
    fxaa_tc_scale_offset@f4 = fxaa_tc_scale_offset;
  }
  (ps) {
    tex@smp2d = source_color_tex;
    resolution@f4 = resolution;
    fxaa_params@f4 = fxaa_params;
    fxaa_color_mul@f4 = fxaa_color_mul;
  }

  if (in_cockpit == on && compatibility_mode == compatibility_mode_off)
  {
    if (sharpness_on_selfillum == off)
    {
      (ps) { material_data@smp2d = material_data; }
      hlsl(ps) {
        float shouldSharpen(float2 texcoord)
        {
          float material = floor(0.1+3.0f*tex2Dlod(material_data, float4(texcoord,0,0)).w);
          return material != SHADING_SELFILLUM ? 1 : 0;
        }
      }
    }
    else
    {
      hlsl(ps) {
        #define shouldSharpen(texcoord) 1
      }
    }
    (ps) {
      adaptive_sharpen_quality@f4 = adaptive_sharpen_quality;
    }
    hlsl(ps) {
      float get_confidence_of_cockpit_tools(float2 tc)
      {
        if (shouldSharpen(tc) < 1)
          return 0.0f;
        float depth0 = linearize_z(readGbufferDepth(tc-resolution.zw), zn_zfar.zw);
        float depth1 = linearize_z(readGbufferDepth(tc.x+resolution.z,tc.y-resolution.w), zn_zfar.zw);
        float depth2 = linearize_z(readGbufferDepth(tc.x-resolution.z,tc.y+resolution.w), zn_zfar.zw);
        float depth3 = linearize_z(readGbufferDepth(tc+resolution.zw), zn_zfar.zw);
        float maxDepth = max(max(depth0, depth1), max(depth2, depth3));
        float minDepth = min(min(depth0, depth1), min(depth2, depth3));

        //depth differece: <= 0.002 then it is cockpit tools, >= 0.0025 it is not cockpit tools, else linear interpolated value
        const float2 depthDiffLimits = float2(0.002, 0.0025);
        const float rcpDepthDiffRange = 1.0f / (depthDiffLimits.y - depthDiffLimits.x);
        float not_cockpit_tools_confidence = clamp((maxDepth - minDepth - depthDiffLimits.x) * rcpDepthDiffRange, 0, 1);

        return maxDepth < 2 ? (1 - not_cockpit_tools_confidence): 0.0f;
      }
      half4 adaptive_sharpen(float2 tc)
      {
        half4 C   = tex2D(tex, tc);
        float4 texcoordNWNE = tc.xyxy + float4(-0.5, -0.5, 0.5, -0.5) * resolution.zwzw;
        float4 texcoordSWSE = tc.xyxy + float4(-0.5, +0.5, 0.5, +0.5) * resolution.zwzw;
        half4 tNW = tex2Dlod(tex, float4(texcoordNWNE.xy, 0,0));
        half4 tNE = tex2Dlod(tex, float4(texcoordNWNE.zw, 0,0));
        half4 tSW = tex2Dlod(tex, float4(texcoordSWSE.xy, 0,0));
        half4 tSE = tex2Dlod(tex, float4(texcoordSWSE.zw, 0,0));
        half4 B = tNW + tNE + tSW + tSE;


  ##if luminance_from_alpha == luminance_from_alpha_on
        half lNW = tNW.w;
        half lNE = tNE.w;
        half lSW = tSW.w;
        half lSE = tSE.w;
  ##else
        half3 lumaC = normalize(half3(0.299, 0.587, 0.114));
        half lNW = dot(tNW.rgb, lumaC);
        half lNE = dot(tNE.rgb, lumaC);
        half lSW = dot(tSW.rgb, lumaC);
        half lSE = dot(tSE.rgb, lumaC);
  ##endif

        half2 grad;
        grad.x = ((lNE + lSE) - (lNW + lSW)) * 0.5;
        grad.y = ((lSW + lSE) - (lNW + lNE)) * 0.5;
   
        half mag2 = clamp(grad.x * grad.x + grad.y * grad.y, 0.0, 1.0);
        half mag = sqrt(mag2);
   
        half str = adaptive_sharpen_quality.z * mag + adaptive_sharpen_quality.w * (1. - mag); 
   
        half Q1 = (17. + str) / (str + 1.); 
        half Q2 = -4. / (str + 1.);
   
        return C * Q1 + B * Q2;
      }
    }
  } else
  {
    hlsl(ps) {
      #define get_confidence_of_cockpit_tools(tc) 0
      #define adaptive_sharpen(tc) 0
    }
  }

  if (fxaa_quality == fxaa_quality_low || fxaa_quality == fxaa_quality_none)
  {
    hlsl {
      struct VsOutput
      {
        VS_OUT_POSITION(pos)
        float4 texcoord : TEXCOORD0;
      };
    }

    hlsl(vs) {
      VsOutput antialiasing_vs(uint vertex_id : SV_VertexID)
      {
        half2 pos = getPostfxVertexPositionById(vertex_id);
        VsOutput output;
  /*--------------------------------------------------------------------------*/
      #define FXAA_SUBPIX_SHIFT 0//(1.0/4.0)
  /*--------------------------------------------------------------------------*/
        output.pos = float4(pos.x, pos.y, 1, 1);
        output.texcoord.xy = screen_to_texcoords(pos);
        output.texcoord.xy = output.texcoord.xy * fxaa_tc_scale_offset.xy + fxaa_tc_scale_offset.zw;
        output.texcoord.xy += float2(0.00001, 0.00001);
        output.texcoord.zw = output.texcoord.xy - (resolution.zw * (0.5 + FXAA_SUBPIX_SHIFT));
        return output;
      }
    }

    hlsl(ps) {
      #define int2 half2
      #define FxaaInt2 half2
      #define Fxaahalf2 half2
      #define FxaaSat(a) saturate((a))
      #define FxaaTex Texture2D
      #define FxaaTexLod0(t, p) ((half4)tex2Dlod(t, float4(p, 0.0, 0.0)))
      #define FxaaTexOff(t, p, o, r) ((half4)tex2Dlod(t, float4(p + (o * r), 0, 0)))

      half4 antialiasing_ps(VsOutput IN): SV_Target
      {
        float4 posPos = IN.texcoord;
        float cockpitToolsWeight = 0;
        float4 sharpenValue = float4(0, 0, 0, 0);
        ##if (in_cockpit == on && hmd_device == hmd_device_off)
          cockpitToolsWeight = get_confidence_of_cockpit_tools(posPos.xy);
          BRANCH
          if (cockpitToolsWeight > 0.0f)
          {
            sharpenValue = adaptive_sharpen(posPos.xy);
          }
        ##endif
        ##if (fxaa_quality == fxaa_quality_none)
          return lerp(tex2Dlod(tex, float4(posPos.xy, 0, 0)), sharpenValue, cockpitToolsWeight) * fxaa_color_mul;
        ##endif

        //return 0;
    /*--------------------------------------------------------------------------*/
        #define FXAA_REDUCE_MIN   (1.0/128.0)
        #define FXAA_REDUCE_MUL   (1.0/8.0)
        #define FXAA_SPAN_MAX     8.0
    /*--------------------------------------------------------------------------*/
        half4 rgbNW = FxaaTexLod0(tex, posPos.zw);
        half4 rgbNE = FxaaTexOff(tex, posPos.zw, FxaaInt2(1,0), resolution.zw);
        half4 rgbSW = FxaaTexOff(tex, posPos.zw, FxaaInt2(0,1), resolution.zw);
        half4 rgbSE = FxaaTexOff(tex, posPos.zw, FxaaInt2(1,1), resolution.zw);
        half4 rgbM  = FxaaTexLod0(tex, posPos.xy);
    /*--------------------------------------------------------------------------*/      
##if luminance_from_alpha == luminance_from_alpha_on
        half lumaNW = rgbNW.w;
        half lumaNE = rgbNE.w;
        half lumaSW = rgbSW.w;
        half lumaSE = rgbSE.w;
        half lumaM  = rgbM.w;
##else
        half3 luma = half3(0.299, 0.587, 0.114);
        half lumaNW = dot(rgbNW.xyz, luma);
        half lumaNE = dot(rgbNE.xyz, luma);
        half lumaSW = dot(rgbSW.xyz, luma);
        half lumaSE = dot(rgbSE.xyz, luma);
        half lumaM  = dot(rgbM.xyz,  luma);
##endif
    /*--------------------------------------------------------------------------*/
        half lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
        half lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    /*--------------------------------------------------------------------------*/
        float2 dir; 
        dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
        dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));
    /*--------------------------------------------------------------------------*/
        half dirReduce = max(
            (lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL),
            FXAA_REDUCE_MIN);
        half rcpDirMin = 1.0/(min(abs(dir.x), abs(dir.y)) + dirReduce);
        dir = min(Fxaahalf2( FXAA_SPAN_MAX,  FXAA_SPAN_MAX), 
              max(Fxaahalf2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), 
              dir * rcpDirMin)) * (half2)resolution.zw;
    /*--------------------------------------------------------------------------*/
        half4 rgbA = (1.0/2.0) * (
            FxaaTexLod0(tex, posPos.xy + dir * (1.0/3.0 - 0.5)) +
            FxaaTexLod0(tex, posPos.xy + dir * (2.0/3.0 - 0.5)));
        half4 rgbB = rgbA * (1.0/2.0) + (1.0/4.0) * (
            FxaaTexLod0(tex, posPos.xy + dir * (0.0/3.0 - 0.5)) +
            FxaaTexLod0(tex, posPos.xy + dir * (3.0/3.0 - 0.5)));

##if luminance_from_alpha == luminance_from_alpha_on
        half lumaB = rgbB.w;
##else
        half lumaB = dot(rgbB.xyz, luma);
##endif

        if ((lumaB < lumaMin) || (lumaB > lumaMax)) 
          return lerp(rgbA, sharpenValue, cockpitToolsWeight) * fxaa_color_mul;
        return lerp(rgbB, sharpenValue, cockpitToolsWeight) * fxaa_color_mul;
      }
    }
  
  } else {
    hlsl {
      struct VsOutput
      {
        VS_OUT_POSITION(pos)
        float2 texcoord : TEXCOORD0;
      };
    }

    hlsl(vs) {
      VsOutput antialiasing_vs(uint vertex_id : SV_VertexID)
      {
        half2 pos = getPostfxVertexPositionById(vertex_id);
        VsOutput output;
        output.pos = float4(pos.x, pos.y, 1, 1);
        output.texcoord.xy = screen_to_texcoords(pos);
        output.texcoord.xy = output.texcoord.xy * fxaa_tc_scale_offset.xy + fxaa_tc_scale_offset.zw;
        output.texcoord.xy += float2(0.00001, 0.00001);
        return output;
      }
    }


    hlsl(ps) {
    #define FXAA_PC 1
    #define FXAA_HLSL_3 1
    #define FXAA_DISCARD 0
    #define FXAA_GATHER4_ALPHA 0

    #ifndef FXAA_PS3
        #define FXAA_PS3 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_360
        #define FXAA_360 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_360_OPT
        #define FXAA_360_OPT 0
    #endif
    /*==========================================================================*/
    #ifndef FXAA_PC
        //
        // FXAA Quality
        // The high quality PC algorithm.
        //
        #define FXAA_PC 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_PC_CONSOLE
        //
        // The console algorithm for PC is included
        // for developers targeting really low spec machines.
        // Likely better to just run FXAA_PC, and use a really low preset.
        //
        #define FXAA_PC_CONSOLE 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_GLSL_120
        #define FXAA_GLSL_120 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_GLSL_130
        #define FXAA_GLSL_130 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_HLSL_3
        #define FXAA_HLSL_3 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_HLSL_4
        #define FXAA_HLSL_4 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_HLSL_5
        #define FXAA_HLSL_5 0
    #endif
    /*==========================================================================*/
    #ifndef FXAA_GREEN_AS_LUMA
        //
        // For those using non-linear color,
        // and either not able to get luma in alpha, or not wanting to,
        // this enables FXAA to run using green as a proxy for luma.
        // So with this enabled, no need to pack luma in alpha.
        //
        // This will turn off AA on anything which lacks some amount of green.
        // Pure red and blue or combination of only R and B, will get no AA.
        //
        // Might want to lower the settings for both,
        //    fxaaConsoleEdgeThresholdMin
        //    fxaaQualityEdgeThresholdMin
        // In order to insure AA does not get turned off on colors 
        // which contain a minor amount of green.
        //
        // 1 = On.
        // 0 = Off.
        //
        #define FXAA_GREEN_AS_LUMA 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_EARLY_EXIT
        //
        // Controls algorithm's early exit path.
        // On PS3 turning this ON adds 2 cycles to the shader.
        // On 360 turning this OFF adds 10ths of a millisecond to the shader.
        // Turning this off on console will result in a more blurry image.
        // So this defaults to on.
        //
        // 1 = On.
        // 0 = Off.
        //
        #define FXAA_EARLY_EXIT 1
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_DISCARD
        //
        // Only valid for PC OpenGL currently.
        // Probably will not work when FXAA_GREEN_AS_LUMA = 1.
        //
        // 1 = Use discard on pixels which don't need AA.
        //     For APIs which enable concurrent TEX+ROP from same surface.
        // 0 = Return unchanged color on pixels which don't need AA.
        //
        #define FXAA_DISCARD 0
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_FAST_PIXEL_OFFSET
        //
        // Used for GLSL 120 only.
        //
        // 1 = GL API supports fast pixel offsets
        // 0 = do not use fast pixel offsets
        //
        #ifdef GL_EXT_gpu_shader4
            #define FXAA_FAST_PIXEL_OFFSET 1
        #endif
        #ifdef GL_NV_gpu_shader5
            #define FXAA_FAST_PIXEL_OFFSET 1
        #endif
        #ifdef GL_ARB_gpu_shader5
            #define FXAA_FAST_PIXEL_OFFSET 1
        #endif
        #ifndef FXAA_FAST_PIXEL_OFFSET
            #define FXAA_FAST_PIXEL_OFFSET 0
        #endif
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_GATHER4_ALPHA
        //
        // 1 = API supports gather4 on alpha channel.
        // 0 = API does not support gather4 on alpha channel.
        //
        #if (FXAA_HLSL_5 == 1)
            #define FXAA_GATHER4_ALPHA 1
        #endif
        #ifdef GL_ARB_gpu_shader5
            #define FXAA_GATHER4_ALPHA 1
        #endif
        #ifdef GL_NV_gpu_shader5
            #define FXAA_GATHER4_ALPHA 1
        #endif
        #ifndef FXAA_GATHER4_ALPHA
            #define FXAA_GATHER4_ALPHA 0
        #endif
    #endif
    /*============================================================================
                          FXAA CONSOLE PS3 - TUNING KNOBS
    ============================================================================*/
    #ifndef FXAA_CONSOLE__PS3_EDGE_SHARPNESS
        //
        // Consoles the sharpness of edges on PS3 only.
        // Non-PS3 tuning is done with shader input.
        //
        // Due to the PS3 being ALU bound,
        // there are only two safe values here: 4 and 8.
        // These options use the shaders ability to a free *|/ by 2|4|8.
        //
        // 8.0 is sharper
        // 4.0 is softer
        // 2.0 is really soft (good for vector graphics inputs)
        //
        #if 1
            #define FXAA_CONSOLE__PS3_EDGE_SHARPNESS 8.0
        #endif
        #if 0
            #define FXAA_CONSOLE__PS3_EDGE_SHARPNESS 4.0
        #endif
        #if 0
            #define FXAA_CONSOLE__PS3_EDGE_SHARPNESS 2.0
        #endif
    #endif
    /*--------------------------------------------------------------------------*/
    #ifndef FXAA_CONSOLE__PS3_EDGE_THRESHOLD
        //
        // Only effects PS3.
        // Non-PS3 tuning is done with shader input.
        //
        // The minimum amount of local contrast required to apply algorithm.
        // The console setting has a different mapping than the quality setting.
        //
        // This only applies when FXAA_EARLY_EXIT is 1.
        //
        // Due to the PS3 being ALU bound,
        // there are only two safe values here: 0.25 and 0.125.
        // These options use the shaders ability to a free *|/ by 2|4|8.
        //
        // 0.125 leaves less aliasing, but is softer
        // 0.25 leaves more aliasing, and is sharper
        //
        #if 1
            #define FXAA_CONSOLE__PS3_EDGE_THRESHOLD 0.125
        #else
            #define FXAA_CONSOLE__PS3_EDGE_THRESHOLD 0.25
        #endif
    #endif

    /*============================================================================
                            FXAA QUALITY - TUNING KNOBS
    ------------------------------------------------------------------------------
    NOTE the other tuning knobs are now in the shader function inputs!
    ============================================================================*/
    //##ifndef FXAA_QUALITY__PRESET
        //
        // Choose the quality preset.
        // This needs to be compiled into the shader as it effects code.
        // Best option to include multiple presets is to 
        // in each shader define the preset, then include this file.
        // 
        // OPTIONS
        // -----------------------------------------------------------------------
        // 10 to 15 - default medium dither (10=fastest, 15=highest quality)
        // 20 to 29 - less dither, more expensive (20=fastest, 29=highest quality)
        // 39       - no dither, very expensive 
        //
        // NOTES
        // -----------------------------------------------------------------------
        // 12 = slightly faster then FXAA 3.9 and higher edge quality (default)
        // 13 = about same speed as FXAA 3.9 and better than 12
        // 23 = closest to FXAA 3.9 visually and performance wise
        //  _ = the lowest digit is directly related to performance
        // _  = the highest digit is directly related to style
        // 
        //#define FXAA_QUALITY__PRESET 23
    //##endif


    /*============================================================================

                               FXAA QUALITY - PRESETS

    ============================================================================*/

    /*============================================================================
                         FXAA QUALITY - MEDIUM DITHER PRESETS
    ============================================================================*/
    //##if (fxaa_quality == fxaa_quality_10)
    //    #define FXAA_QUALITY__PS 3
    //    #define FXAA_QUALITY__P0 1.5
    //    #define FXAA_QUALITY__P1 3.0
    //    #define FXAA_QUALITY__P2 12.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_11)
    //    #define FXAA_QUALITY__PS 4
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 3.0
    //    #define FXAA_QUALITY__P3 12.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_12)
    //    #define FXAA_QUALITY__PS 5
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 4.0
    //    #define FXAA_QUALITY__P4 12.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_13)
    //    #define FXAA_QUALITY__PS 6
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 4.0
    //    #define FXAA_QUALITY__P5 12.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_14)
    //    #define FXAA_QUALITY__PS 7
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 2.0
    //    #define FXAA_QUALITY__P5 4.0
    //    #define FXAA_QUALITY__P6 12.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_15)
    //    #define FXAA_QUALITY__PS 8
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 2.0
    //    #define FXAA_QUALITY__P5 2.0
    //    #define FXAA_QUALITY__P6 4.0
    //    #define FXAA_QUALITY__P7 12.0
    //##endif

    /*============================================================================
                         FXAA QUALITY - LOW DITHER PRESETS
    ============================================================================*/
    //##if (fxaa_quality == fxaa_quality_20)
    //    #define FXAA_QUALITY__PS 3
    //    #define FXAA_QUALITY__P0 1.5
    //    #define FXAA_QUALITY__P1 2.0
    //    #define FXAA_QUALITY__P2 8.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_21)
    //    #define FXAA_QUALITY__PS 4
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 8.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_22)
    //    #define FXAA_QUALITY__PS 5
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 8.0
    //##endif
    /*--------------------------------------------------------------------------*/
    ##if (fxaa_quality == fxaa_quality_23)
        #define FXAA_QUALITY__PS 6
        #define FXAA_QUALITY__P0 1.0
        #define FXAA_QUALITY__P1 1.5
        #define FXAA_QUALITY__P2 2.0
        #define FXAA_QUALITY__P3 2.0
        #define FXAA_QUALITY__P4 2.0
        #define FXAA_QUALITY__P5 8.0
    ##endif
    /*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_24)
    //    #define FXAA_QUALITY__PS 7
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 2.0
    //    #define FXAA_QUALITY__P5 3.0
    //    #define FXAA_QUALITY__P6 8.0
    //##endif
    /*--------------------------------------------------------------------------*/
    ##if (fxaa_quality == fxaa_quality_25)
        #define FXAA_QUALITY__PS 8
        #define FXAA_QUALITY__P0 1.0
        #define FXAA_QUALITY__P1 1.5
        #define FXAA_QUALITY__P2 2.0
        #define FXAA_QUALITY__P3 2.0
        #define FXAA_QUALITY__P4 2.0
        #define FXAA_QUALITY__P5 2.0
        #define FXAA_QUALITY__P6 4.0
        #define FXAA_QUALITY__P7 8.0
    ##endif
    /*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_26)
    //    #define FXAA_QUALITY__PS 9
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 2.0
    //    #define FXAA_QUALITY__P5 2.0
    //    #define FXAA_QUALITY__P6 2.0
    //    #define FXAA_QUALITY__P7 4.0
    //    #define FXAA_QUALITY__P8 8.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_27)
    //    #define FXAA_QUALITY__PS 10
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 2.0
    //    #define FXAA_QUALITY__P5 2.0
    //    #define FXAA_QUALITY__P6 2.0
    //    #define FXAA_QUALITY__P7 2.0
    //    #define FXAA_QUALITY__P8 4.0
    //    #define FXAA_QUALITY__P9 8.0
    //##endif
    ///*--------------------------------------------------------------------------*/
    //##if (fxaa_quality == fxaa_quality_28)
    //    #define FXAA_QUALITY__PS 11
    //    #define FXAA_QUALITY__P0 1.0
    //    #define FXAA_QUALITY__P1 1.5
    //    #define FXAA_QUALITY__P2 2.0
    //    #define FXAA_QUALITY__P3 2.0
    //    #define FXAA_QUALITY__P4 2.0
    //    #define FXAA_QUALITY__P5 2.0
    //    #define FXAA_QUALITY__P6 2.0
    //    #define FXAA_QUALITY__P7 2.0
    //    #define FXAA_QUALITY__P8 2.0
    //    #define FXAA_QUALITY__P9 4.0
    //    #define FXAA_QUALITY__P10 8.0
    //##endif
    /*--------------------------------------------------------------------------*/
    ##if (fxaa_quality == fxaa_quality_29)
        #define FXAA_QUALITY__PS 12
        #define FXAA_QUALITY__P0 1.0
        #define FXAA_QUALITY__P1 1.5
        #define FXAA_QUALITY__P2 2.0
        #define FXAA_QUALITY__P3 2.0
        #define FXAA_QUALITY__P4 2.0
        #define FXAA_QUALITY__P5 2.0
        #define FXAA_QUALITY__P6 2.0
        #define FXAA_QUALITY__P7 2.0
        #define FXAA_QUALITY__P8 2.0
        #define FXAA_QUALITY__P9 2.0
        #define FXAA_QUALITY__P10 4.0
        #define FXAA_QUALITY__P11 8.0
    ##endif

    /*============================================================================
                         FXAA QUALITY - EXTREME QUALITY
    ============================================================================*/
    ##if (fxaa_quality == fxaa_quality_39)
        #define FXAA_QUALITY__PS 12
        #define FXAA_QUALITY__P0 1.0
        #define FXAA_QUALITY__P1 1.0
        #define FXAA_QUALITY__P2 1.0
        #define FXAA_QUALITY__P3 1.0
        #define FXAA_QUALITY__P4 1.0
        #define FXAA_QUALITY__P5 1.5
        #define FXAA_QUALITY__P6 2.0
        #define FXAA_QUALITY__P7 2.0
        #define FXAA_QUALITY__P8 2.0
        #define FXAA_QUALITY__P9 2.0
        #define FXAA_QUALITY__P10 4.0
        #define FXAA_QUALITY__P11 8.0
    ##endif



    /*============================================================================

                                    API PORTING

    ============================================================================*/
    #if (FXAA_GLSL_120 == 1) || (FXAA_GLSL_130 == 1)
        #define FxaaBool bool
        #define FxaaDiscard discard
        #define FxaaFloat float
        #define FxaaFloat2 vec2
        #define FxaaFloat3 vec3
        #define FxaaFloat4 vec4
        #define FxaaHalf float
        #define FxaaHalf2 vec2
        #define FxaaHalf3 vec3
        #define FxaaHalf4 vec4
        #define FxaaInt2 ivec2
        #define FxaaSat(x) clamp(x, 0.0, 1.0)
        #define FxaaTex Texture2D
    #else
        #define FxaaBool bool
        #define FxaaDiscard discard
        //#define FxaaDiscard clip(-1)
        #define FxaaFloat float
        #define FxaaFloat2 float2
        #define FxaaFloat3 float3
        #define FxaaFloat4 float4
        #define FxaaHalf half
        #define FxaaHalf2 half2
        #define FxaaHalf3 half3
        #define FxaaHalf4 half4
        #define FxaaSat(x) saturate(x)
    #endif
    /*--------------------------------------------------------------------------*/
    #if (FXAA_GLSL_120 == 1)
        // Requires,
        //  ##version 120
        // And at least,
        //  ##extension GL_EXT_gpu_shader4 : enable
        //  (or set FXAA_FAST_PIXEL_OFFSET 1 to work like DX9)
        #define FxaaTexTop(t, p) texture2DLod(t, p, 0.0)
        #if (FXAA_FAST_PIXEL_OFFSET == 1)
            #define FxaaTexOff(t, p, o, r) texture2DLodOffset(t, p, 0.0, o)
        #else
            #define FxaaTexOff(t, p, o, r) texture2DLod(t, p + (o * r), 0.0)
        #endif
        #if (FXAA_GATHER4_ALPHA == 1)
            // use ##extension GL_ARB_gpu_shader5 : enable
            #define FxaaTexAlpha4(t, p) textureGather(t, p, 3)
            #define FxaaTexOffAlpha4(t, p, o) textureGatherOffset(t, p, o, 3)
            #define FxaaTexGreen4(t, p) textureGather(t, p, 1)
            #define FxaaTexOffGreen4(t, p, o) textureGatherOffset(t, p, o, 1)
        #endif
    #endif
    /*--------------------------------------------------------------------------*/
    #if (FXAA_GLSL_130 == 1)
        // Requires "##version 130" or better
        #define FxaaTexTop(t, p) textureLod(t, p, 0.0)
        #define FxaaTexOff(t, p, o, r) textureLodOffset(t, p, 0.0, o)
        #if (FXAA_GATHER4_ALPHA == 1)
            // use ##extension GL_ARB_gpu_shader5 : enable
            #define FxaaTexAlpha4(t, p) textureGather(t, p, 3)
            #define FxaaTexOffAlpha4(t, p, o) textureGatherOffset(t, p, o, 3)
            #define FxaaTexGreen4(t, p) textureGather(t, p, 1)
            #define FxaaTexOffGreen4(t, p, o) textureGatherOffset(t, p, o, 1)
        #endif
    #endif
    /*--------------------------------------------------------------------------*/
    #if (FXAA_HLSL_3 == 1) || (FXAA_360 == 1) || (FXAA_PS3 == 1)
        #define FxaaInt2 float2
        #define FxaaTex Texture2D
        #define FxaaTexTop(t, p) tex2Dlod(t, float4(p, 0.0, 0.0))
        #define FxaaTexOff(t, p, o, r) tex2Dlod(t, float4(p + (o * r), 0, 0))
    #endif
    /*--------------------------------------------------------------------------*/
    #if (FXAA_HLSL_4 == 1)
        #define FxaaInt2 int2
        struct FxaaTex { SamplerState smpl; Texture2D tex; };
        #define FxaaTexTop(t, p) t.tex.SampleLevel(t.smpl, p, 0.0)
        #define FxaaTexOff(t, p, o, r) t.tex.SampleLevel(t.smpl, p, 0.0, o)
    #endif
    /*--------------------------------------------------------------------------*/
    #if (FXAA_HLSL_5 == 1)
        #define FxaaInt2 int2
        struct FxaaTex { SamplerState smpl; Texture2D tex; };
        #define FxaaTexTop(t, p) t.tex.SampleLevel(t.smpl, p, 0.0)
        #define FxaaTexOff(t, p, o, r) t.tex.SampleLevel(t.smpl, p, 0.0, o)
        #define FxaaTexAlpha4(t, p) t.tex.GatherAlpha(t.smpl, p)
        #define FxaaTexOffAlpha4(t, p, o) t.tex.GatherAlpha(t.smpl, p, o)
        #define FxaaTexGreen4(t, p) t.tex.GatherGreen(t.smpl, p)
        #define FxaaTexOffGreen4(t, p, o) t.tex.GatherGreen(t.smpl, p, o)
    #endif


    /*============================================================================
                       GREEN AS LUMA OPTION SUPPORT FUNCTION
    ============================================================================*/
    #if (FXAA_GREEN_AS_LUMA == 0)
##if luminance_from_alpha == luminance_from_alpha_on
        FxaaFloat FxaaLuma(FxaaFloat4 rgba) { return rgba.w; }
##else
        FxaaFloat FxaaLuma(FxaaFloat4 rgba) { return dot(rgba.rgb, half3(0.299, 0.587, 0.114)); }
##endif
    #else
        FxaaFloat FxaaLuma(FxaaFloat4 rgba) { return rgba.y; }
    #endif



      FxaaFloat4 FxaaPixelShader(
          //
          // Use noperspective interpolation here (turn off perspective interpolation).
          // {xy} = center of pixel
          FxaaFloat2 pos,
          //
          // Used only for FXAA Console, and not used on the 360 version.
          // Use noperspective interpolation here (turn off perspective interpolation).
          // {xy__} = upper left of pixel
          // {__zw} = lower right of pixel
          FxaaFloat4 fxaaConsolePosPos,
          //
          // Input color texture.
          // {rgb_} = color in linear or perceptual color space
          // if (FXAA_GREEN_AS_LUMA == 0)
          //     {___a} = luma in perceptual color space (not linear)
          FxaaTex tex,
          //
          // Only used on the optimized 360 version of FXAA Console.
          // For everything but 360, just use the same input here as for "tex".
          // For 360, same texture, just alias with a 2nd sampler.
          // This sampler needs to have an exponent bias of -1.
          FxaaTex fxaaConsole360TexExpBiasNegOne,
          // 
          // Only used on the optimized 360 version of FXAA Console.
          // For everything but 360, just use the same input here as for "tex".
          // For 360, same texture, just alias with a 3nd sampler.
          // This sampler needs to have an exponent bias of -2.
          FxaaTex fxaaConsole360TexExpBiasNegTwo,
          //
          // Only used on FXAA Quality.
          // This must be from a constant/uniform.
          // {x_} = 1.0/screenWidthInPixels
          // {_y} = 1.0/screenHeightInPixels
          FxaaFloat2 fxaaQualityRcpFrame,
          //
          // Only used on FXAA Console.
          // This must be from a constant/uniform.
          // This effects sub-pixel AA quality and inversely sharpness.
          //   Where N ranges between,
          //     N = 0.50 (default)
          //     N = 0.33 (sharper)
          // {x___} = -N/screenWidthInPixels  
          // {_y__} = -N/screenHeightInPixels
          // {__z_} =  N/screenWidthInPixels  
          // {___w} =  N/screenHeightInPixels 
          FxaaFloat4 fxaaConsoleRcpFrameOpt,
          //
          // Only used on FXAA Console.
          // Not used on 360, but used on PS3 and PC.
          // This must be from a constant/uniform.
          // {x___} = -2.0/screenWidthInPixels  
          // {_y__} = -2.0/screenHeightInPixels
          // {__z_} =  2.0/screenWidthInPixels  
          // {___w} =  2.0/screenHeightInPixels 
          FxaaFloat4 fxaaConsoleRcpFrameOpt2,
          //
          // Only used on FXAA Console.
          // Only used on 360 in place of fxaaConsoleRcpFrameOpt2.
          // This must be from a constant/uniform.
          // {x___} =  8.0/screenWidthInPixels  
          // {_y__} =  8.0/screenHeightInPixels
          // {__z_} = -4.0/screenWidthInPixels  
          // {___w} = -4.0/screenHeightInPixels 
          FxaaFloat4 fxaaConsole360RcpFrameOpt2,
          //
          // Only used on FXAA Quality.
          // This used to be the FXAA_QUALITY__SUBPIX define.
          // It is here now to allow easier tuning.
          // Choose the amount of sub-pixel aliasing removal.
          // This can effect sharpness.
          //   1.00 - upper limit (softer)
          //   0.75 - default amount of filtering
          //   0.50 - lower limit (sharper, less sub-pixel aliasing removal)
          //   0.25 - almost off
          //   0.00 - completely off
          FxaaFloat fxaaQualitySubpix,
          //
          // Only used on FXAA Quality.
          // This used to be the FXAA_QUALITY__EDGE_THRESHOLD define.
          // It is here now to allow easier tuning.
          // The minimum amount of local contrast required to apply algorithm.
          //   0.333 - too little (faster)
          //   0.250 - low quality
          //   0.166 - default
          //   0.125 - high quality 
          //   0.063 - overkill (slower)
          FxaaFloat fxaaQualityEdgeThreshold,
          //
          // Only used on FXAA Quality.
          // This used to be the FXAA_QUALITY__EDGE_THRESHOLD_MIN define.
          // It is here now to allow easier tuning.
          // Trims the algorithm from processing darks.
          //   0.0833 - upper limit (default, the start of visible unfiltered edges)
          //   0.0625 - high quality (faster)
          //   0.0312 - visible limit (slower)
          // Special notes when using FXAA_GREEN_AS_LUMA,
          //   Likely want to set this to zero.
          //   As colors that are mostly not-green
          //   will appear very dark in the green channel!
          //   Tune by looking at mostly non-green content,
          //   then start at zero and increase until aliasing is a problem.
          FxaaFloat fxaaQualityEdgeThresholdMin,
          // 
          // Only used on FXAA Console.
          // This used to be the FXAA_CONSOLE__EDGE_SHARPNESS define.
          // It is here now to allow easier tuning.
          // This does not effect PS3, as this needs to be compiled in.
          //   Use FXAA_CONSOLE__PS3_EDGE_SHARPNESS for PS3.
          //   Due to the PS3 being ALU bound,
          //   there are only three safe values here: 2 and 4 and 8.
          //   These options use the shaders ability to a free *|/ by 2|4|8.
          // For all other platforms can be a non-power of two.
          //   8.0 is sharper (default!!!)
          //   4.0 is softer
          //   2.0 is really soft (good only for vector graphics inputs)
          FxaaFloat fxaaConsoleEdgeSharpness,
          //
          // Only used on FXAA Console.
          // This used to be the FXAA_CONSOLE__EDGE_THRESHOLD define.
          // It is here now to allow easier tuning.
          // This does not effect PS3, as this needs to be compiled in.
          //   Use FXAA_CONSOLE__PS3_EDGE_THRESHOLD for PS3.
          //   Due to the PS3 being ALU bound,
          //   there are only two safe values here: 1/4 and 1/8.
          //   These options use the shaders ability to a free *|/ by 2|4|8.
          // The console setting has a different mapping than the quality setting.
          // Other platforms can use other values.
          //   0.125 leaves less aliasing, but is softer (default!!!)
          //   0.25 leaves more aliasing, and is sharper
          FxaaFloat fxaaConsoleEdgeThreshold,
          //
          // Only used on FXAA Console.
          // This used to be the FXAA_CONSOLE__EDGE_THRESHOLD_MIN define.
          // It is here now to allow easier tuning.
          // Trims the algorithm from processing darks.
          // The console setting has a different mapping than the quality setting.
          // This only applies when FXAA_EARLY_EXIT is 1.
          // This does not apply to PS3, 
          // PS3 was simplified to avoid more shader instructions.
          //   0.06 - faster but more aliasing in darks
          //   0.05 - default
          //   0.04 - slower and less aliasing in darks
          // Special notes when using FXAA_GREEN_AS_LUMA,
          //   Likely want to set this to zero.
          //   As colors that are mostly not-green
          //   will appear very dark in the green channel!
          //   Tune by looking at mostly non-green content,
          //   then start at zero and increase until aliasing is a problem.
          FxaaFloat fxaaConsoleEdgeThresholdMin,
          //    
          // Extra constants for 360 FXAA Console only.
          // Use zeros or anything else for other platforms.
          // These must be in physical constant registers and NOT immedates.
          // Immedates will result in compiler un-optimizing.
          // {xyzw} = float4(1.0, -1.0, 0.25, -0.25)
          FxaaFloat4 fxaaConsole360ConstDir
      ) {
      /*--------------------------------------------------------------------------*/
          FxaaFloat2 posM;
          posM.x = pos.x;
          posM.y = pos.y;
          #if (FXAA_GATHER4_ALPHA == 1)
              #if (FXAA_DISCARD == 0)
                  FxaaFloat4 rgbyM = FxaaTexTop(tex, posM);
                  #if (FXAA_GREEN_AS_LUMA == 0)
                      #define lumaM FxaaLuma(rgbyM)
                  #else
                      #define lumaM rgbyM.y
                  #endif
              #endif
              #if (FXAA_GREEN_AS_LUMA == 0)
                  FxaaFloat4 luma4A = FxaaTexAlpha4(tex, posM);
                  FxaaFloat4 luma4B = FxaaTexOffAlpha4(tex, posM, FxaaInt2(-1, -1));
              #else
                  FxaaFloat4 luma4A = FxaaTexGreen4(tex, posM);
                  FxaaFloat4 luma4B = FxaaTexOffGreen4(tex, posM, FxaaInt2(-1, -1));
              #endif
              #if (FXAA_DISCARD == 1)
                  #define lumaM FxaaLuma(luma4A)
              #endif
              #define lumaE luma4A.z
              #define lumaS luma4A.x
              #define lumaSE luma4A.y
              #define lumaNW luma4B.w
              #define lumaN luma4B.z
              #define lumaW luma4B.x
          #else
              FxaaFloat4 rgbyM = FxaaTexTop(tex, posM);
              #if (FXAA_GREEN_AS_LUMA == 0)
                  #define lumaM FxaaLuma(rgbyM)
              #else
                  #define lumaM rgbyM.y
              #endif
              FxaaFloat lumaS = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2( 0, 1), fxaaQualityRcpFrame.xy));
              FxaaFloat lumaE = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2( 1, 0), fxaaQualityRcpFrame.xy));
              FxaaFloat lumaN = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2( 0,-1), fxaaQualityRcpFrame.xy));
              FxaaFloat lumaW = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2(-1, 0), fxaaQualityRcpFrame.xy));
          #endif
      /*--------------------------------------------------------------------------*/
          FxaaFloat maxSM = max(lumaS, lumaM);
          FxaaFloat minSM = min(lumaS, lumaM);
          FxaaFloat maxESM = max(lumaE, maxSM);
          FxaaFloat minESM = min(lumaE, minSM);
          FxaaFloat maxWN = max(lumaN, lumaW);
          FxaaFloat minWN = min(lumaN, lumaW);
          FxaaFloat rangeMax = max(maxWN, maxESM);
          FxaaFloat rangeMin = min(minWN, minESM);
          FxaaFloat rangeMaxScaled = rangeMax * fxaaQualityEdgeThreshold;
          FxaaFloat range = rangeMax - rangeMin;
          FxaaFloat rangeMaxClamped = max(fxaaQualityEdgeThresholdMin, rangeMaxScaled);
          FxaaBool earlyExit = range < rangeMaxClamped;
      /*--------------------------------------------------------------------------*/
          if(earlyExit)
              #if (FXAA_DISCARD == 1)
                  FxaaDiscard;
              #else
                  return rgbyM;
              #endif
      /*--------------------------------------------------------------------------*/
          #if (FXAA_GATHER4_ALPHA == 0)
              FxaaFloat lumaNW = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2(-1,-1), fxaaQualityRcpFrame.xy));
              FxaaFloat lumaSE = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2( 1, 1), fxaaQualityRcpFrame.xy));
              FxaaFloat lumaNE = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2( 1,-1), fxaaQualityRcpFrame.xy));
              FxaaFloat lumaSW = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2(-1, 1), fxaaQualityRcpFrame.xy));
          #else
              FxaaFloat lumaNE = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2(1, -1), fxaaQualityRcpFrame.xy));
              FxaaFloat lumaSW = FxaaLuma(FxaaTexOff(tex, posM, FxaaInt2(-1, 1), fxaaQualityRcpFrame.xy));
          #endif
      /*--------------------------------------------------------------------------*/
          FxaaFloat lumaNS = lumaN + lumaS;
          FxaaFloat lumaWE = lumaW + lumaE;
          FxaaFloat subpixRcpRange = 1.0/range;
          FxaaFloat subpixNSWE = lumaNS + lumaWE;
          FxaaFloat edgeHorz1 = (-2.0 * lumaM) + lumaNS;
          FxaaFloat edgeVert1 = (-2.0 * lumaM) + lumaWE;
      /*--------------------------------------------------------------------------*/
          FxaaFloat lumaNESE = lumaNE + lumaSE;
          FxaaFloat lumaNWNE = lumaNW + lumaNE;
          FxaaFloat edgeHorz2 = (-2.0 * lumaE) + lumaNESE;
          FxaaFloat edgeVert2 = (-2.0 * lumaN) + lumaNWNE;
      /*--------------------------------------------------------------------------*/
          FxaaFloat lumaNWSW = lumaNW + lumaSW;
          FxaaFloat lumaSWSE = lumaSW + lumaSE;
          FxaaFloat edgeHorz4 = (abs(edgeHorz1) * 2.0) + abs(edgeHorz2);
          FxaaFloat edgeVert4 = (abs(edgeVert1) * 2.0) + abs(edgeVert2);
          FxaaFloat edgeHorz3 = (-2.0 * lumaW) + lumaNWSW;
          FxaaFloat edgeVert3 = (-2.0 * lumaS) + lumaSWSE;
          FxaaFloat edgeHorz = abs(edgeHorz3) + edgeHorz4;
          FxaaFloat edgeVert = abs(edgeVert3) + edgeVert4;
      /*--------------------------------------------------------------------------*/
          FxaaFloat subpixNWSWNESE = lumaNWSW + lumaNESE;
          FxaaFloat lengthSign = fxaaQualityRcpFrame.x;
          FxaaBool horzSpan = edgeHorz >= edgeVert;
          FxaaFloat subpixA = subpixNSWE * 2.0 + subpixNWSWNESE;
      /*--------------------------------------------------------------------------*/
          if(!horzSpan) lumaN = lumaW;
          if(!horzSpan) lumaS = lumaE;
          if(horzSpan) lengthSign = fxaaQualityRcpFrame.y;
          FxaaFloat subpixB = (subpixA * (1.0/12.0)) - lumaM;
      /*--------------------------------------------------------------------------*/
          FxaaFloat gradientN = lumaN - lumaM;
          FxaaFloat gradientS = lumaS - lumaM;
          FxaaFloat lumaNN = lumaN + lumaM;
          FxaaFloat lumaSS = lumaS + lumaM;
          FxaaBool pairN = abs(gradientN) >= abs(gradientS);
          FxaaFloat gradient = max(abs(gradientN), abs(gradientS));
          if(pairN) lengthSign = -lengthSign;
          FxaaFloat subpixC = FxaaSat(abs(subpixB) * subpixRcpRange);
      /*--------------------------------------------------------------------------*/
          FxaaFloat2 posB;
          posB.x = posM.x;
          posB.y = posM.y;
          FxaaFloat2 offNP;
          offNP.x = (!horzSpan) ? 0.0 : fxaaQualityRcpFrame.x;
          offNP.y = ( horzSpan) ? 0.0 : fxaaQualityRcpFrame.y;
          if(!horzSpan) posB.x += lengthSign * 0.5;
          if( horzSpan) posB.y += lengthSign * 0.5;
      /*--------------------------------------------------------------------------*/
          FxaaFloat2 posN;
          posN.x = posB.x - offNP.x * FXAA_QUALITY__P0;
          posN.y = posB.y - offNP.y * FXAA_QUALITY__P0;
          FxaaFloat2 posP;
          posP.x = posB.x + offNP.x * FXAA_QUALITY__P0;
          posP.y = posB.y + offNP.y * FXAA_QUALITY__P0;
          FxaaFloat subpixD = ((-2.0)*subpixC) + 3.0;
          FxaaFloat lumaEndN = FxaaLuma(FxaaTexTop(tex, posN));
          FxaaFloat subpixE = subpixC * subpixC;
          FxaaFloat lumaEndP = FxaaLuma(FxaaTexTop(tex, posP));
      /*--------------------------------------------------------------------------*/
          if(!pairN) lumaNN = lumaSS;
          FxaaFloat gradientScaled = gradient * 1.0/4.0;
          FxaaFloat lumaMM = lumaM - lumaNN * 0.5;
          FxaaFloat subpixF = subpixD * subpixE;
          FxaaBool lumaMLTZero = lumaMM < 0.0;
      /*--------------------------------------------------------------------------*/
          lumaEndN -= lumaNN * 0.5;
          lumaEndP -= lumaNN * 0.5;
          FxaaBool doneN = abs(lumaEndN) >= gradientScaled;
          FxaaBool doneP = abs(lumaEndP) >= gradientScaled;
          if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P1;
          if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P1;
          FxaaBool doneNP = (!doneN) || (!doneP);
          if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P1;
          if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P1;
      /*--------------------------------------------------------------------------*/
          if(doneNP) {
              if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
              if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
              if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
              if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
              doneN = abs(lumaEndN) >= gradientScaled;
              doneP = abs(lumaEndP) >= gradientScaled;
              if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P2;
              if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P2;
              doneNP = (!doneN) || (!doneP);
              if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P2;
              if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P2;
      /*--------------------------------------------------------------------------*/
              #if (FXAA_QUALITY__PS > 3)
              if(doneNP) {
                  if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                  if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                  if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                  if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                  doneN = abs(lumaEndN) >= gradientScaled;
                  doneP = abs(lumaEndP) >= gradientScaled;
                  if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P3;
                  if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P3;
                  doneNP = (!doneN) || (!doneP);
                  if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P3;
                  if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P3;
      /*--------------------------------------------------------------------------*/
                  #if (FXAA_QUALITY__PS > 4)
                  if(doneNP) {
                      if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                      if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                      if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                      if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                      doneN = abs(lumaEndN) >= gradientScaled;
                      doneP = abs(lumaEndP) >= gradientScaled;
                      if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P4;
                      if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P4;
                      doneNP = (!doneN) || (!doneP);
                      if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P4;
                      if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P4;
      /*--------------------------------------------------------------------------*/
                      #if (FXAA_QUALITY__PS > 5)
                      if(doneNP) {
                          if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                          if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                          if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                          if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                          doneN = abs(lumaEndN) >= gradientScaled;
                          doneP = abs(lumaEndP) >= gradientScaled;
                          if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P5;
                          if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P5;
                          doneNP = (!doneN) || (!doneP);
                          if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P5;
                          if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P5;
      /*--------------------------------------------------------------------------*/
                          #if (FXAA_QUALITY__PS > 6)
                          if(doneNP) {
                              if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                              if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                              if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                              if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                              doneN = abs(lumaEndN) >= gradientScaled;
                              doneP = abs(lumaEndP) >= gradientScaled;
                              if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P6;
                              if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P6;
                              doneNP = (!doneN) || (!doneP);
                              if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P6;
                              if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P6;
      /*--------------------------------------------------------------------------*/
                              #if (FXAA_QUALITY__PS > 7)
                              if(doneNP) {
                                  if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                                  if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                                  if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                                  if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                                  doneN = abs(lumaEndN) >= gradientScaled;
                                  doneP = abs(lumaEndP) >= gradientScaled;
                                  if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P7;
                                  if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P7;
                                  doneNP = (!doneN) || (!doneP);
                                  if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P7;
                                  if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P7;
      /*--------------------------------------------------------------------------*/
          #if (FXAA_QUALITY__PS > 8)
          if(doneNP) {
              if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
              if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
              if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
              if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
              doneN = abs(lumaEndN) >= gradientScaled;
              doneP = abs(lumaEndP) >= gradientScaled;
              if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P8;
              if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P8;
              doneNP = (!doneN) || (!doneP);
              if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P8;
              if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P8;
      /*--------------------------------------------------------------------------*/
              #if (FXAA_QUALITY__PS > 9)
              if(doneNP) {
                  if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                  if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                  if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                  if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                  doneN = abs(lumaEndN) >= gradientScaled;
                  doneP = abs(lumaEndP) >= gradientScaled;
                  if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P9;
                  if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P9;
                  doneNP = (!doneN) || (!doneP);
                  if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P9;
                  if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P9;
      /*--------------------------------------------------------------------------*/
                  #if (FXAA_QUALITY__PS > 10)
                  if(doneNP) {
                      if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                      if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                      if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                      if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                      doneN = abs(lumaEndN) >= gradientScaled;
                      doneP = abs(lumaEndP) >= gradientScaled;
                      if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P10;
                      if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P10;
                      doneNP = (!doneN) || (!doneP);
                      if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P10;
                      if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P10;
      /*--------------------------------------------------------------------------*/
                      #if (FXAA_QUALITY__PS > 11)
                      if(doneNP) {
                          if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                          if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                          if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                          if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                          doneN = abs(lumaEndN) >= gradientScaled;
                          doneP = abs(lumaEndP) >= gradientScaled;
                          if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P11;
                          if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P11;
                          doneNP = (!doneN) || (!doneP);
                          if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P11;
                          if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P11;
      /*--------------------------------------------------------------------------*/
                          #if (FXAA_QUALITY__PS > 12)
                          if(doneNP) {
                              if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
                              if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
                              if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                              if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                              doneN = abs(lumaEndN) >= gradientScaled;
                              doneP = abs(lumaEndP) >= gradientScaled;
                              if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P12;
                              if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P12;
                              doneNP = (!doneN) || (!doneP);
                              if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P12;
                              if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P12;
      /*--------------------------------------------------------------------------*/
                          }
                          #endif
      /*--------------------------------------------------------------------------*/
                      }
                      #endif
      /*--------------------------------------------------------------------------*/
                  }
                  #endif
      /*--------------------------------------------------------------------------*/
              }
              #endif
      /*--------------------------------------------------------------------------*/
          }
          #endif
      /*--------------------------------------------------------------------------*/
                              }
                              #endif
      /*--------------------------------------------------------------------------*/
                          }
                          #endif
      /*--------------------------------------------------------------------------*/
                      }
                      #endif
      /*--------------------------------------------------------------------------*/
                  }
                  #endif
      /*--------------------------------------------------------------------------*/
              }
              #endif
      /*--------------------------------------------------------------------------*/
          }
      /*--------------------------------------------------------------------------*/
          FxaaFloat dstN = posM.x - posN.x;
          FxaaFloat dstP = posP.x - posM.x;
          if(!horzSpan) dstN = posM.y - posN.y;
          if(!horzSpan) dstP = posP.y - posM.y;
      /*--------------------------------------------------------------------------*/
          FxaaBool goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
          FxaaFloat spanLength = (dstP + dstN);
          FxaaBool goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
          FxaaFloat spanLengthRcp = 1.0/spanLength;
      /*--------------------------------------------------------------------------*/
          FxaaBool directionN = dstN < dstP;
          FxaaFloat dst = min(dstN, dstP);
          FxaaBool goodSpan = directionN ? goodSpanN : goodSpanP;
          FxaaFloat subpixG = subpixF * subpixF;
          FxaaFloat pixelOffset = (dst * (-spanLengthRcp)) + 0.5;
          FxaaFloat subpixH = subpixG * fxaaQualitySubpix;
      /*--------------------------------------------------------------------------*/
          FxaaFloat pixelOffsetGood = goodSpan ? pixelOffset : 0.0;
          FxaaFloat pixelOffsetSubpix = max(pixelOffsetGood, subpixH);
          if(!horzSpan) posM.x += pixelOffsetSubpix * lengthSign;
          if( horzSpan) posM.y += pixelOffsetSubpix * lengthSign;
          #if (FXAA_DISCARD == 1)
              return FxaaTexTop(tex, posM);
          #else
              return FxaaFloat4(FxaaTexTop(tex, posM).xyz, lumaM);
          #endif
      }
      /*==========================================================================*/

      half4 antialiasing_ps(VsOutput IN): SV_Target
      {
        float2 pos = IN.texcoord;
        float cockpitToolsWeight = 0;
        float4 sharpenValue = float4(0, 0, 0, 0);
        ##if (in_cockpit == on && hmd_device == hmd_device_off)
          cockpitToolsWeight = get_confidence_of_cockpit_tools(pos);
          BRANCH
          if (cockpitToolsWeight > 0.0f)
            sharpenValue = adaptive_sharpen(pos);
            //return tex2Dlod(tex, float4(pos,0,0)) * fxaa_color_mul;
        ##endif
        return fxaa_color_mul * lerp(FxaaPixelShader(
            //
            // Use noperspective interpolation here (turn off perspective interpolation).
            // {xy} = center of pixel
            pos,
            //
            // Used only for FXAA Console, and not used on the 360 version.
            // Use noperspective interpolation here (turn off perspective interpolation).
            // {xy__} = upper left of pixel
            // {__zw} = lower right of pixel
            pos.xyxy,
            //
            // Input color texture.
            // {rgb_} = color in linear or perceptual color space
            // if (FXAA_GREEN_AS_LUMA == 0)
            //     {___a} = luma in perceptual color space (not linear)
            tex,
            //
            // Only used on the optimized 360 version of FXAA Console.
            // For everything but 360, just use the same input here as for "tex".
            // For 360, same texture, just alias with a 2nd sampler.
            // This sampler needs to have an exponent bias of -1.
            tex,
            //
            // Only used on the optimized 360 version of FXAA Console.
            // For everything but 360, just use the same input here as for "tex".
            // For 360, same texture, just alias with a 3nd sampler.
            // This sampler needs to have an exponent bias of -2.
            tex,
            //
            // Only used on FXAA Quality.
            // This must be from a constant/uniform.
            // {x_} = 1.0/screenWidthInPixels
            // {_y} = 1.0/screenHeightInPixels
            resolution.zw,
            //
            // Only used on FXAA Console.
            // This must be from a constant/uniform.
            // This effects sub-pixel AA quality and inversely sharpness.
            //   Where N ranges between,
            //     N = 0.50 (default)
            //     N = 0.33 (sharper)
            // {x___} = -N/screenWidthInPixels  
            // {_y__} = -N/screenHeightInPixels
            // {__z_} =  N/screenWidthInPixels  
            // {___w} =  N/screenHeightInPixels 
            resolution,
            //
            // Only used on FXAA Console.
            // Not used on 360, but used on PS3 and PC.
            // This must be from a constant/uniform.
            // {x___} = -2.0/screenWidthInPixels  
            // {_y__} = -2.0/screenHeightInPixels
            // {__z_} =  2.0/screenWidthInPixels  
            // {___w} =  2.0/screenHeightInPixels 
            resolution,
            //
            // Only used on FXAA Console.
            // Only used on 360 in place of fxaaConsoleRcpFrameOpt2.
            // This must be from a constant/uniform.
            // {x___} =  8.0/screenWidthInPixels  
            // {_y__} =  8.0/screenHeightInPixels
            // {__z_} = -4.0/screenWidthInPixels  
            // {___w} = -4.0/screenHeightInPixels 
            resolution,
            //
            // Only used on FXAA Quality.
            // This used to be the FXAA_QUALITY__SUBPIX define.
            // It is here now to allow easier tuning.
            // Choose the amount of sub-pixel aliasing removal.
            // This can effect sharpness.
            //   1.00 - upper limit (softer)
            //   0.75 - default amount of filtering
            //   0.50 - lower limit (sharper, less sub-pixel aliasing removal)
            //   0.25 - almost off
            //   0.00 - completely off
            fxaa_params.x,      // 0.75
            //
            // Only used on FXAA Quality.
            // This used to be the FXAA_QUALITY__EDGE_THRESHOLD define.
            // It is here now to allow easier tuning.
            // The minimum amount of local contrast required to apply algorithm.
            //   0.333 - too little (faster)
            //   0.250 - low quality
            //   0.166 - default
            //   0.125 - high quality 
            //   0.063 - overkill (slower)
            fxaa_params.y,      // 0.166
            //
            // Only used on FXAA Quality.
            // This used to be the FXAA_QUALITY__EDGE_THRESHOLD_MIN define.
            // It is here now to allow easier tuning.
            // Trims the algorithm from processing darks.
            //   0.0833 - upper limit (default, the start of visible unfiltered edges)
            //   0.0625 - high quality (faster)
            //   0.0312 - visible limit (slower)
            // Special notes when using FXAA_GREEN_AS_LUMA,
            //   Likely want to set this to zero.
            //   As colors that are mostly not-green
            //   will appear very dark in the green channel!
            //   Tune by looking at mostly non-green content,
            //   then start at zero and increase until aliasing is a problem.
            fxaa_params.z,      // 0.0833
            // 
            // Only used on FXAA Console.
            // This used to be the FXAA_CONSOLE__EDGE_SHARPNESS define.
            // It is here now to allow easier tuning.
            // This does not effect PS3, as this needs to be compiled in.
            //   Use FXAA_CONSOLE__PS3_EDGE_SHARPNESS for PS3.
            //   Due to the PS3 being ALU bound,
            //   there are only three safe values here: 2 and 4 and 8.
            //   These options use the shaders ability to a free *|/ by 2|4|8.
            // For all other platforms can be a non-power of two.
            //   8.0 is sharper (default!!!)
            //   4.0 is softer
            //   2.0 is really soft (good only for vector graphics inputs)
            8.0,
            //
            // Only used on FXAA Console.
            // This used to be the FXAA_CONSOLE__EDGE_THRESHOLD define.
            // It is here now to allow easier tuning.
            // This does not effect PS3, as this needs to be compiled in.
            //   Use FXAA_CONSOLE__PS3_EDGE_THRESHOLD for PS3.
            //   Due to the PS3 being ALU bound,
            //   there are only two safe values here: 1/4 and 1/8.
            //   These options use the shaders ability to a free *|/ by 2|4|8.
            // The console setting has a different mapping than the quality setting.
            // Other platforms can use other values.
            //   0.125 leaves less aliasing, but is softer (default!!!)
            //   0.25 leaves more aliasing, and is sharper
            0.125,
            //
            // Only used on FXAA Console.
            // This used to be the FXAA_CONSOLE__EDGE_THRESHOLD_MIN define.
            // It is here now to allow easier tuning.
            // Trims the algorithm from processing darks.
            // The console setting has a different mapping than the quality setting.
            // This only applies when FXAA_EARLY_EXIT is 1.
            // This does not apply to PS3, 
            // PS3 was simplified to avoid more shader instructions.
            //   0.06 - faster but more aliasing in darks
            //   0.05 - default
            //   0.04 - slower and less aliasing in darks
            // Special notes when using FXAA_GREEN_AS_LUMA,
            //   Likely want to set this to zero.
            //   As colors that are mostly not-green
            //   will appear very dark in the green channel!
            //   Tune by looking at mostly non-green content,
            //   then start at zero and increase until aliasing is a problem.
            0.05,
            //    
            // Extra constants for 360 FXAA Console only.
            // Use zeros or anything else for other platforms.
            // These must be in physical constant registers and NOT immedates.
            // Immedates will result in compiler un-optimizing.
            // {xyzw} = float4(1.0, -1.0, 0.25, -0.25)
            0
        ), sharpenValue, cockpitToolsWeight);
      }
    }
  }

  compile("target_ps", "antialiasing_ps");
  compile("target_vs", "antialiasing_vs");
}

include "hardware_defines.sh"
include "roughToMip.sh"
include "skyLight.sh"
include "postfx_inc.sh"
include "brunetonSky.sh"
include "mulPointTm_inc.sh"
include "global_consts.sh"

float water_level = 0;

texture downsampled_far_depth_tex;

float4 world_view_pos;
float global_transp_r;

int is_gather4_supported = 0;
interval is_gather4_supported: unsupported <1, supported;

int use_screen_mask = 0;
interval use_screen_mask : no < 1, yes;

int oculus = 0;
interval oculus : oculus_off < 1, oculus_on;

int in_editor=0;
interval in_editor : no<1, yes;

int in_editor_assume=0;
interval in_editor_assume : no<1, yes;

int use_postfx = 1;
interval use_postfx : off<1, on;

int use_extended_global_frame_block = 0;
interval use_extended_global_frame_block: no < 1, yes;

float4 screen_pos_to_texcoord = (0, 0, 0, 0);
macro USE_SCREENPOS_TO_TC()
(ps) { screen_pos_to_texcoord@f4 = screen_pos_to_texcoord; }
hlsl(ps) {
  float2 screen_pos_to_tc(float2 screen_pos) {return screen_pos * screen_pos_to_texcoord.xy + screen_pos_to_texcoord.zw; }
}
endmacro


macro NO_ATEST()
  hlsl(ps) {
    #define clip_alpha(a)
    #define clip_alpha_fast(a)
  }
endmacro

macro USE_ATEST_255()
  hlsl(ps) {
    #define atest_use 1
    #define atest_value_ref (1.00000)
  }
  hlsl(ps) {
    #define clip_alpha(a) {if (a < atest_value_ref) discard;}
    #define clip_alpha_fast(a) {clip(a - atest_value_ref);}//it is not consistent across depth-pass/color-pass. use for shadow
  }
endmacro

macro USE_ATEST_1()
  hlsl(ps) {
    #define atest_use 1
    #define atest_value_ref (1.0/255.0)
  }
  hlsl(ps) {
    #define clip_alpha(a) {if (a <= 0) discard;}
    #define clip_alpha_fast(a) {clip(a);}//it is not consistent across depth-pass/color-pass. use for shadow
  }
endmacro

macro USE_ATEST_VALUE(value)
  hlsl(ps) {
    #define atest_use 1
    #define atest_value_ref (value/255.0)
  }
  hlsl(ps) {
    #define clip_alpha(a) {if (a < atest_value_ref) discard;}
    #define clip_alpha_fast(a){clip(a - atest_value_ref);}//it is not consistent across depth-pass/color-pass. use for shadow
  }
endmacro

macro USE_ATEST_DYNAMIC_VALUE(value)
  (ps) { atest_value_ref@f1 = (value); }
  hlsl(ps) {
    #define atest_use 1
    #define clip_alpha(a) {if (a < atest_value_ref) discard;}
    #define clip_alpha_fast(a){clip(a - atest_value_ref);}//it is not consistent across depth-pass/color-pass. use for shadow
  }
endmacro

macro USE_ATEST_HALF()
  hlsl(ps) {
    #define atest_use 1
    #define atest_value_ref 0.5
  }
  hlsl(ps) {
    #define clip_alpha(a) {if (a < atest_value_ref) discard;}
    #define clip_alpha_fast(a){clip(a - atest_value_ref);}//it is not consistent across depth-pass/color-pass. use for shadow
  }
endmacro

hlsl {
#define linear_to_gamma(a) a
#define linear_to_gamma_rgba(a) a
#define gamma_to_linear(a) a
#define gamma_to_linear_rgba(a) a

#define PI 3.14159265f

float pow2(float a) {return a*a;}
float pow4(float a) {return pow2(a*a);}
float pow8(float a) {return pow4(a*a);}
float pow16(float a){return pow8(a*a);}
float2 pow2_vec2(float2 a) {return a*a;}
float3 pow2_vec3(float3 a) {return a*a;}
float4 pow2_vec4(float4 a) {return a*a;}

float2 pow2(float2 a) {return a*a;}
float3 pow2(float3 a) {return a*a;}
float4 pow2(float4 a) {return a*a;}
float4 pow4(float4 a) {return pow2(a*a);}
float4 pow8(float4 a) {return pow4(a*a);}
float4 pow16(float4 a) {return pow8(a*a);}
float pow5(float a) {float v = a*a; v*=v; return v*a;}

half pow2h(half a) {return a*a;}
half pow4h(half a) {return pow2h(a*a);}
half pow5h(half a){half a4=a*a; a4*=a4; return a4*a;}

float clampedPow(float X,float Y) { return pow(max(abs(X),0.000001f),Y); }
half luminance(half3 col)
{
  return dot(col, half3(0.299, 0.587, 0.114));
}

}

hlsl {
  float linearize_z(float rawDepth, float2 decode_depth)
  {
    return rcp(decode_depth.x + decode_depth.y * rawDepth);
  }
}

float4 zn_zfar = (1, 20000, 0, 0);
float4 rendering_res = (1280, 720, 0,0);

macro INIT_RENDERING_RESOLUTION(code)
  (code) { rendering_res@f4 = (rendering_res); }
endmacro

macro INIT_ZNZFAR_STAGE(code)
  (code) { zn_zfar@f4 = (zn_zfar.x, zn_zfar.y, zn_zfar.x/(zn_zfar.x * zn_zfar.y), (zn_zfar.y-zn_zfar.x)/(zn_zfar.x * zn_zfar.y)); }
endmacro

macro INIT_ZNZFAR()
  INIT_ZNZFAR_STAGE(ps)
endmacro

macro COMMON_LINEARIZE_SKY_DEPTH()
  INIT_ZNZFAR()
endmacro
macro INIT_LINEARIZE_LOWRES_SKY_DEPTH()
  hlsl(ps) {
    float linearizeSkyDepthLow(float rawd){return linearize_z(rawd, zn_zfar.zw);}
  }
endmacro
macro INIT_LINEARIZE_HIRES_SKY_DEPTH()
  hlsl(ps) {
    float linearizeSkyDepthHigh(float rawd){return linearize_z(rawd, zn_zfar.zw);}
  }
endmacro

macro SKY_HDR()
  hlsl(ps) {half3 pack_hdr(half3 a) {return a;}}
  hlsl(ps) {half3 unpack_hdr(half3 a) {return a;}}
endmacro

macro USE_HDR_SH()
endmacro

hlsl(ps) {
  half3 restore_normal(half2 xy)
  {
    half3 normal;
    normal.xy = xy*2-1;
    normal.z = sqrt(saturate(1-dot(normal.xy,normal.xy)));
    return normal;
  }
  half3 unpack_ag_normal(half4 normalmap)
  {
    return restore_normal(normalmap.ag);
  }
  float adjustRoughness ( float inputRoughness, float avgNormalLength )
  {
    // Based on The Order : 1886 SIGGRAPH course notes implementation
    if ( avgNormalLength < 1.0f)
    {
      float avgNormLen2 = avgNormalLength * avgNormalLength ;
      float kappa = (3 * avgNormalLength - avgNormalLength * avgNormLen2 ) / (1 - avgNormLen2 );
      float variance = 1.0f / (2.0 * kappa);
      return sqrt ( inputRoughness * inputRoughness + variance );
    }
    return inputRoughness;
  }
}

hlsl {
float pow3(float v) {return v*v*v;}
half linearSmoothnessToLinearRoughness(half linearSmoothness) {return 1-linearSmoothness;}

}

int compatibility_mode = 0;
interval compatibility_mode:compatibility_mode_off<1, compatibility_mode_on;

int mobile_render = 0;
interval mobile_render: off < 1, forward < 2, deferred;

macro USE_MSAA()
  hlsl(ps) {
    #define NUM_MSAA_SAMPLES 0
  }
endmacro

macro USE_DECODE_DEPTH_BASE(suffix, code)
endmacro

macro USE_DECODE_DEPTH_STAGE(code)
endmacro

macro USE_DECODE_DEPTH()
  USE_DECODE_DEPTH_STAGE(ps)
endmacro

int support_texture_array = 0;//should be assumed
interval support_texture_array : off<1, on;
block(frame) global_frame
{}

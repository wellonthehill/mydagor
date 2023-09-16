include "sky_shader_global.sh"
//include "land_shadow.sh"
include "psh_derivate.sh"
include "vsm.sh"
include "viewVecVS.sh"
include "underwater_fog.sh"
include "wake.sh"
include "sq_clouds_shadow.sh"
include "sun_disk_specular.sh"
include "panorama.sh"
//include "water_foam_trail_inc.sh"
//include "water_geometric_decals.sh"
include "edge_tesselation.sh"
include "waveWorks.sh"
include "compatibility/sky_ground_color.sh"
include "normaldetail.sh"

//int water_render_pass = 0;
//interval water_render_pass : normal_pass<1, depth_pass;

//int underwater_render = 0;
//interval underwater_render : no<1, yes;

hlsl {
  #define WATER_GEOMORPHING FULL_GEOMORPH_LODS
}
hlsl(ps) {
  #define NORMALIZE_FFTWATER_NORMAL 0
}

float compatibility_vertex_lerp = 0;

int water_globtm_const_no = 40;
macro USE_HARDCODED_WATER()
  hlsl(vs) {
    float3 water_ofs_pos : register(c40);
  }
endmacro

float water_reflection_hdr_multiplier = 1;
float object_reflection_distortion = 0.05;
float water_depth_hardness = 1;//should be about 2 for tanks and 0.5 for planes

float scatter_disappear_factor = 1;//we'd better use it for water_vs blend out as well
float foam_tiling = 0.1013;
float angle_to_roughness_scale = 0.1;
float sun_roughness_for_water_to_cube = 0;

float4 object_reflection_offset = (0, 0.01, 0, 0);
float water_reflection_margin_inv = 1;

texture water_reflection_tex;
texture water_refraction_tex;

float bump_dist_damp = 1500;

float4 water_mask1 = (1, 1, 1, 1);
//x - shore
//y - wake
//y - shadows
//w - deepness

float4 water_mask2 = (1, 1, 1, 1);
//x - foam
//y - env refl
//z - planar refl
//w - sun refl

float4 water_mask3 = (1, 1, 1, 1);
//x - refractions
//y - sss
//z - underwater scattering
//w - proj effects

macro USE_DEBUG_WATER()
  (ps) {
    water_mask1@f4 = water_mask1;
    water_mask2@f4 = water_mask2;
    water_mask3@f4 = water_mask3;
  }

    hlsl {
##if shader != water3d_compatibility
    #define DEBUG_WATER 1
##endif
    }
endmacro

//texture heightmap_tex;

macro GET_WATER_COLOR()
hlsl(ps) {
  #define INV_MIN_IOR 100
}
hlsl(ps) {
  #include "BRDF.hlsl"
}
USE_ROUGH_TO_MIP()

endmacro

float fake_distortion_period = 6;
hlsl (ps) {
  #define to_sun_direction (-from_sun_direction)
}

block(frame) water3d_block
{

  // Declarations pulled from shader_global.sh due to the need to get rid of shadow_buffer_tex declaration
  (ps) {
    from_sun_direction@f3 = from_sun_direction;
  }
  (ps) {
    world_view_pos@f3 = world_view_pos;

    sun_color_0__shadow_intens@f3 = (sun_color_0.r, sun_color_0.g, sun_color_0.b, cloud_shadow_intensity);
    sky_color@f3 = sky_color;
    foam_tiling_bdamp_srough@f4 = (foam_tiling/(height_tiling+1), water_depth_hardness*(2-height_tiling), 1.0 / bump_dist_damp, sun_roughness_for_water_to_cube);
    depth_tex@smp2d = depth_tex;
  }
  INIT_HDR_STCODE()
  SQ_INIT_CLOUDS_SHADOW()
  INIT_ZNZFAR()

  (vs) {
    globtm@f44 = globtm;
    inv_zfar@f1 = (1.0 / zn_zfar.y, 0.0, 0.0, 0.0);
    world_view_pos@f3 = world_view_pos;
  }

  if (compatibility_mode == compatibility_mode_off)
  {
    (ps) { water_refraction_tex@smp2d = water_refraction_tex; }

    (ps) { perlin_noise@smp2d = perlin_noise; }

    (ps) {
      water_reflection_tex@smp2d = water_reflection_tex;
      foam_tex@smp2d = foam_tex;//fixme: remove in compatibility
      lrefl_scatter_hdr_psize@f4 = (object_reflection_distortion, scatter_disappear_factor, water_reflection_hdr_multiplier, 1./(0.01+(height_tiling+1)*water_color_noise_size));
    }
  }

  FOG_PS_STCODE()
  INIT_WATER_GRADIENTS()
}


float4 water_effects_proj_tm_line_0 = (1, 0, 0, 0);
float4 water_effects_proj_tm_line_1 = (0, 1, 0, 0);
float4 water_effects_proj_tm_line_2 = (0, 0, 1, 0);
float4 water_effects_proj_tm_line_3 = (0, 0, 0, 1);

texture projected_on_water_effects_tex;
float water_projection_effects_height = 0;

macro USE_WATER_PROJECTED_EFFECTS_PS()
  (ps) {
    water_effects_proj_tm@f44 = {water_effects_proj_tm_line_0, water_effects_proj_tm_line_1, water_effects_proj_tm_line_2, water_effects_proj_tm_line_3};
    water_projection_effects_height@f1 = (water_projection_effects_height);
    projected_on_water_effects_tex@smp2d = projected_on_water_effects_tex;
  }
  hlsl(ps) {
    half4 get_water_projection_effects(in float3 worldPos, in float base_foam)
    {
      //project pixel pos on effects-water-projection plane
      float4 reprojectedCoord = float4(worldPos.xyz,1);
      reprojectedCoord.y = water_projection_effects_height;

      //reproject to 'camera'
      reprojectedCoord = mul(reprojectedCoord, water_effects_proj_tm);

      //ndc -> texture space
      reprojectedCoord.xy = reprojectedCoord.xy * float2(0.5, HALF_RT_TC_YSCALE) / reprojectedCoord.w + 0.5;
      half4 projectedEffects = h4tex2D(projected_on_water_effects_tex, reprojectedCoord.xy).a;
      projectedEffects.a = 1.0h - projectedEffects.a;
      projectedEffects = lerp(float4(0, 0, 0, 1), projectedEffects, saturate(2 * base_foam));

      return projectedEffects;
    }
  }
endmacro

texture clouds_panorama_mip;

macro USE_ENVI_PROBE()
  INIT_ENVI_SPECULAR()
  USE_SKY_SPECULAR()
endmacro

macro USE_CLOUDS_PANORAMA()
  if (compatibility_mode == compatibility_mode_off && clouds_panorama_mip != NULL)
  {
    (ps) { clouds_panorama_mip@smp2d = clouds_panorama_mip; }
    INIT_CLOUDS_ALPHA_PANORAMA()
    USE_CLOUDS_ALPHA_PANORAMA()
    hlsl(ps) {
      #define USED_CLOUDS_PANORAMA 1
    }
  }
  else
  {
    USE_ENVI_PROBE()
    hlsl(ps) {
      #define USED_CLOUDS_PANORAMA 0
    }
  }
endmacro

shader water_nv2/*, water3d_compatibility, water_3d_decal*/
{
  supports water3d_block;

  if (shader == water_3d_decal)
  {
    if (/*water_render_pass == depth_pass ||*/ compatibility_mode == compatibility_mode_on)
    {
      dont_render;
    }
    blend_src = sa; blend_dst = isa;
    cull_mode = cw;
    z_write = false;
  } else
  {
    /*if (water_render_pass == depth_pass)
    {
      blend_src = 1; blend_dst = 1;
    } else*/
    // Introduced blending to cope with Z-fighting
    if ((compatibility_mode == compatibility_mode_off) && (water_refraction_tex == NULL))
    {
      blend_src = 1; blend_dst = isa;
    }
  }

  USE_SAMPLE_BICUBIC()

  if (shader == water_nv2)
  {
    /*if (underwater_render == yes)
    {
      cull_mode = none;
    }*/
  }

  if (shader == water3d_compatibility)
  {
    channel float4 pos = pos;
    channel float4 tc[0] = tc[0];
    hlsl(vs) {
      struct VsInput
      {
        float4 disp1_x:POSITION;
        float4 disp2_z:TEXCOORD0;
      };
    }
  } else
  {
    USE_WATER_DISPLACEMENT(vs, 1)

    if (shader == water_3d_decal)
    {
      channel float3 pos = pos;
      channel short2 tc[0]=tc[0] mul_4k;
    }
    else
    {
      HEIGHTMAP_DECODE_EDGE_TESSELATION()
      INIT_WATER_WORLD_POS()
      GET_WATER_WORLD_POS()
    }
    if (compatibility_mode == compatibility_mode_on && (water_vs_cascades == four || water_vs_cascades == three))
    {

      dont_render;
    }
  }

  USE_HDR()
  USE_SUN()
  FOG_PS_NO_STCODE()
  SQ_CLOUDS_SHADOW()
  DECL_POSTFX_TC_VS_RT()//fixme: should depend on where we render
  GET_WATER_COLOR()
  INIT_SKY_UP_DIFFUSE()
  USE_SKY_UP_DIFFUSE()

  INIT_UNDERWATER_FOG()
  GET_UNDERWATER_FOG_PERLIN()
  //USE_SNOISE()

  INIT_VSM()
  USE_VSM()
  INIT_WAKE_VS(t1, s1)
  USE_WAKE_VS()

  USE_ENVI_PROBE() //USE_CLOUDS_PANORAMA()

  if (compatibility_mode == compatibility_mode_on)
  {
    GET_SKY_GROUND_COLOR_COMPATIBILITY()
  }

  if (shader != water3d_compatibility)
  {
    hlsl {

      // WaveWorks related structs
      struct VS_OUTPUT
      {
      /*##if (water_render_pass == depth_pass)
        float lin_z: TEXCOORD0;
      ##else*/
        float4 nvsf_tex_coord_cascade01: TEXCOORD0;
        ##if (water_cascades != two)
        float4 nvsf_tex_coord_cascade23: TEXCOORD1;
        ##endif
        ##if (water_cascades == five)
        float4 nvsf_tex_coord_cascade45: TEXCOORD2;
        ##endif
        float4 nvsf_eye_vec: TEXCOORD3;
        float3 pos_world_undisplaced  : TEXCOORD4;
        ##if compatibility_mode == compatibility_mode_off
        float4 screen_texcoord          : TEXCOORD5;
        ##endif

      ##if (shader == water_3d_decal)
        float3 localUV_fade : TEXCOORD6;
      ##endif

      //##endif
        VS_OUT_POSITION(pos_clip)
      };
    }

  if (shader == water_3d_decal)
  {
    //GEOMETRIC_WATER_MESH_VS()
  }

  hlsl (vs) {
    ##if shader == water_3d_decal
      struct VsInput
      {
        float3 pos                  : POSITION;
        int2 uv0                    : TEXCOORD0;
      };
      VS_OUTPUT water_nv_vs(VsInput input)
    ##else
      VS_OUTPUT water_nv_vs(INPUT_VERTEXID_POSXZ USE_INSTANCE_ID)
    ##endif
      {
        VS_OUTPUT Output;
        float3 pos_world_undisplaced;
        float4 nvsf_tex_coord_cascade01, nvsf_tex_coord_cascade23, nvsf_tex_coord_cascade45;
      ##if shader == water_3d_decal
        float3 pos_world = get_water_3d_decal_pos(input.pos, input.uv0, pos_world_undisplaced, Output.localUV_fade);
        //project on water
        pos_world.y += pos_above_water(float3(pos_world.x, water_level_max_wave_wind_dir.x, pos_world.z), nvsf_tex_coord_cascade01, nvsf_tex_coord_cascade23);
      ##else
        DECODE_VERTEXID_POSXZ
        float distFade;
        bool useHeightmap;
        float3 pos_world = float3(getWorldPosXZ(posXZ, distFade, useHeightmap USED_INSTANCE_ID), water_level_max_wave_wind_dir.x);
        pos_world_undisplaced = pos_world;
        pos_world += (getWaterDisplacement(pos_world, length(pos_world - world_view_pos.xzy), nvsf_tex_coord_cascade01, nvsf_tex_coord_cascade23, nvsf_tex_coord_cascade45) + float3(0, 0, get_wake_height(pos_world.xzy))) * distFade;
      ##endif

        Output.pos_clip = mul(float4(pos_world.xzy,1), globtm);


      /*##if (water_render_pass == depth_pass)
        Output.lin_z = Output.pos_clip.w;
      ##else*/
        Output.nvsf_eye_vec = float4(world_view_pos.xzy - pos_world, Output.pos_clip.w * inv_zfar);
        Output.nvsf_tex_coord_cascade01 = nvsf_tex_coord_cascade01;
        Output.pos_world_undisplaced  = pos_world_undisplaced;

        ##if water_cascades != two
        Output.nvsf_tex_coord_cascade23 = nvsf_tex_coord_cascade23;
        ##endif

        ##if (compatibility_mode == compatibility_mode_off)//actually, if shore is on
        Output.screen_texcoord = float4(Output.pos_clip.xy * RT_SCALE_HALF + float2(0.50001, 0.50001) * Output.pos_clip.w, Output.pos_clip.z, Output.pos_clip.w);
        ##endif
      //##endif

        return Output;
      }
    }
  } else
  {
    (vs) { compatibility_vertex_lerp@f1 = (compatibility_vertex_lerp,0,0,0); }
    hlsl {

      // WaveWorks related structs
      struct VS_OUTPUT
      {
        VS_OUT_POSITION(pos_clip)
      ##if (water_render_pass == depth_pass)
        float lin_z: TEXCOORD0;
      ##else
        float4 nvsf_tex_coord_cascade01: TEXCOORD0;
        ##if (water_cascades != two)
        float4 nvsf_tex_coord_cascade23: TEXCOORD1;
        ##endif
        ##if (water_cascades == five)
        float4 nvsf_tex_coord_cascade45: TEXCOORD5;
        ##endif
        float4 nvsf_eye_vec: TEXCOORD2;
        float3 pos_world_undisplaced  : TEXCOORD3;

        ##if compatibility_mode == compatibility_mode_off//fixme
        float4 screen_texcoord          : TEXCOORD4;
        ##endif
      ##endif
      };
    }

    hlsl(vs) {
      VS_OUTPUT water_nv_vs(VsInput input)
      {
        float4 worldPos = float4(input.disp1_x.w, water_level_max_wave_wind_dir.x, input.disp2_z.w, 1);
        float3 pos_world_undisplaced = worldPos.xzy;
        float3 nvsf_displacement = lerp(input.disp1_x.xyz, input.disp2_z.xyz, compatibility_vertex_lerp);
        float  nvsf_distance = length(world_view_pos.xzy - pos_world_undisplaced);

        ##if (compatibility_mode == compatibility_mode_on)
        float3 nvsf_pos_world = pos_world_undisplaced + nvsf_displacement * compatibility_water_displacement_scale.x;
        ##else
        float3 nvsf_pos_world = pos_world_undisplaced+nvsf_displacement;
        ##endif
        float3 nvsf_eye_vec = world_view_pos.xzy - nvsf_pos_world;

        VS_OUTPUT Output;

        Output.pos_clip = mul(float4(nvsf_pos_world.xzy,1), globtm);

      ##if (water_render_pass == depth_pass)
        Output.lin_z = Output.pos_clip.w;
      ##else
        Output.nvsf_eye_vec = float4(nvsf_eye_vec, Output.pos_clip.w * inv_zfar);
        Output.nvsf_tex_coord_cascade01 = worldPos.xzxz * UVScaleCascade0123.xxyy;
        Output.pos_world_undisplaced  = pos_world_undisplaced;

        ##if water_cascades != two
        Output.nvsf_tex_coord_cascade23 = worldPos.xzxz * UVScaleCascade0123.zzww;
        ##endif
        ##if water_cascades == five
        Output.nvsf_tex_coord_cascade45 = worldPos.xzxz * UVScaleCascade4567.xxyy;
        ##endif

        ##if (compatibility_mode == compatibility_mode_off)//actually, if shore is on
        float2 half_clip_pos = Output.pos_clip.xy * float2(0.5, -0.5);
        Output.screen_texcoord = float4(Output.pos_clip.xy * RT_SCALE_HALF + float2(0.50001, 0.50001) * Output.pos_clip.w, Output.pos_clip.z, Output.pos_clip.w);
        ##endif
      ##endif
        return Output;
      }
    }
  }


//if (water_render_pass != depth_pass)
//{
  USE_SCREENPOS_TO_TC()
  USE_DERIVATIVE_MAPS()
  //INIT_WATER_FOAM_TRAIL()
  //USE_MODULATED_FOAM()
  //USE_WATER_FOAM_TRAIL()
  INIT_WAKE()
  USE_WAKE()
  //USE_CUBE_RAIN_DROPLETS(0) there are not enough registers now, turn on when at least one sampler will be available
  USE_WATER_GRADIENTS(1)
  USE_WATER_CASCADES_ROUGHNESS()
  USE_SUN_DISK_SPECULAR()
  if (compatibility_mode == compatibility_mode_off)
  {
    (ps) {
      view_vecLT@f3=view_vecLT;
      view_vecRT@f3=view_vecRT;
      view_vecLB@f3=view_vecLB;
      view_vecRB@f3=view_vecRB;
    }
  }

  USE_DEBUG_WATER()

  if (shader != water_3d_decal)
  {
    USE_WATER_PROJECTED_EFFECTS_PS()
  }

  if (shader == water_3d_decal)
  {
    //GEOMETRIC_WATER_MESH_PS()
  }


 hlsl(ps) {
  // WaveWorks related functions

  struct GFSDK_WAVEWORKS_SURFACE_ATTRIBUTES
  {
    float3 normal;
    float foam_surface_folding;
    float foam_turbulent_energy;
    float foam_wave_hats;
  };
  GFSDK_WAVEWORKS_SURFACE_ATTRIBUTES GFSDK_WaveWorks_GetSurfaceAttributes(VS_OUTPUT In, float4 nvsf_blend_factor_cascade0123, float4 nvsf_blend_factor_cascade4567)
  {
    float nvsf_foam_turbulent_energy, nvsf_foam_surface_folding, nvsf_foam_wave_hats;
    float3 nvsf_normal;
    float fadeNormal = 1;
    get_gradients(In.nvsf_tex_coord_cascade01, In.nvsf_tex_coord_cascade23, In.nvsf_tex_coord_cascade45, nvsf_blend_factor_cascade0123, nvsf_blend_factor_cascade4567,
      fadeNormal, nvsf_foam_turbulent_energy, nvsf_foam_surface_folding, nvsf_normal, nvsf_foam_wave_hats);

    GFSDK_WAVEWORKS_SURFACE_ATTRIBUTES Output;
    Output.normal = nvsf_normal;
    Output.foam_surface_folding = nvsf_foam_surface_folding;
    Output.foam_turbulent_energy = log(1.0 + nvsf_foam_turbulent_energy);
    Output.foam_wave_hats = nvsf_foam_wave_hats;
    return Output;
  }

  //take sun size into consideration

##if compatibility_mode == compatibility_mode_off //&& water_refraction_tex != NULL
  #define has_seabed_refraction 1
##endif
##if shader != water_3d_decal //&& projected_on_water_effects_tex != NULL
  #define has_projection_effects 0
##endif

##if compatibility_mode == compatibility_mode_off
  #define has_perlin_noise 1
##else
  #define has_perlin_noise 0
##endif

  #define FOAM_COLOR half3(1, 1, 1)
  // Reflection coefficient for light incoming parallel to the normal (F0 or fresnel bias)
  #define FRESNEL_REFLECTANCE 0.02

#if DEBUG_WATER
  #define DEBUG_WATER_MASK(m_no, reg) (water_mask##m_no.reg == false)
  #define DEBUG_WATER_RET(m_no, reg) if (DEBUG_WATER_MASK(m_no, reg)) return;
#else
  #define DEBUG_WATER_RET(m_no, reg) 0;
#endif
##if shader == water3d_compatibility
  #define COMPATIBILITY_OR_DEBUG_WATER 1
##else
  #define COMPATIBILITY_OR_DEBUG_WATER DEBUG_WATER
##endif

  struct ViewData
  {
    float4 screenPos;
    float3 pos_world_undisplaced;
    float3 pointToEye;
    float3 worldPos;
    float distSq;
    float invDist;
    float dist;
    float farDetailsWeight;
    float nearDetailsWeight;

##if shader == water_3d_decal
    float3 localUV_fade;
##endif
##if compatibility_mode == compatibility_mode_off
    float4 screen_texcoord;
    float2 reflectionTC;
##endif
    float waterColorToEnvColorKoef;

    float distLog2;
    float distToZfar;
    float3 pointToEyeNormalized;
    float3 reflectDirNormalized;
    float3 reflectSampleDir;

    half3 worldNormal;
    float3 halfDir;
    float NoV;
    float3 view;
    float NoL;
    float NdotV;
    float VoH;
    float NoH;
    float2 distortionVector;
    half fresnelView;

    float roughness;

#if has_perlin_noise
    float2 perlinWind;
    float2 perlinSurf;
#endif

    half3 wakeGradient;
    GFSDK_WAVEWORKS_SURFACE_ATTRIBUTES surfaceAttributes;
    ShoreData shoreData;
  };

  struct ShadowsData
  {
    half vsmShadow;
    half cloudShadow;
    half sunReflectionShadow;
  };

  struct PlanarReflections
  {
    half4 objectReflection;
    half4 initialWaterReflection;
  };

  struct EnvReflections
  {
#if USED_CLOUDS_PANORAMA
    float2 sky_uv;
#endif
    half3 enviReflection;
  };

  struct SunReflections
  {
    half3 sunReflection;
  };

  struct DeepnessData
  {
    half3 fog_mul;
    half3 fog_add;
    float waterDepth;
    float3 underWaterPos;
    float shore_blending_coeff;
    float2 refractionTexcoord;
  };

  struct FoamData
  {
    float foamFactor;
    float scatterFoamFactor;
    half FoamLowFreq;
    float additionalTransparency;
  };

  struct SeabedRefraction
  {
    half3 seabedColor;
  };

  struct SubSurfScattering
  {
    half scatterFactor;
  };

  struct UnderWaterScattering
  {
    half3 underwater_loss;
    half3 underwater_inscatter;
  };

  struct RefractionsData
  {
    half3 finalLitRefraction;
##if compatibility_mode == compatibility_mode_off
  #if !has_seabed_refraction
    float waterOpacity;
  #endif
##endif
  };

  struct ReflectionsData
  {
    half3 reflectionColor;
    half3 envReflection;
  };

  struct ProjectionEffects
  {
    half4 waterProjEffectsColor;
  };

  void getShore(float3 worldPos, out ShoreData shoreData)
  {
#if COMPATIBILITY_OR_DEBUG_WATER
    shoreData.gerstner_normal = float3(0,1,0);
    shoreData.gerstnerFoamFactor = 0;
    shoreData.riverMultiplier = 1;
    shoreData.oceanWavesMultiplier = 1;
    shoreData.shoreWavesDisplacement = float3(0, 0, 0);
  ##if shader != water3d_compatibility
    shoreData.landHeight = 0;
  ##endif
    DEBUG_WATER_RET(1, x);
#endif

##if shader != water3d_compatibility
    getShoreAttributes(worldPos, shoreData);
##endif
  }

  void getWake(float3 worldPos, out half3 wakeGradient)
  {
#if DEBUG_WATER
    wakeGradient = float3(0, 1, 0);
    DEBUG_WATER_RET(1, y);
#endif

    wakeGradient = get_wake_gradient(worldPos).xzy;
  }

  void calcViewData(VS_OUTPUT In, float4 screenPos, out ViewData vd)
  {
    // Calc vertexData
    vd.pos_world_undisplaced = In.pos_world_undisplaced;
    vd.pointToEye = In.nvsf_eye_vec.xzy;
    vd.worldPos = world_view_pos.xyz - vd.pointToEye;
    vd.distSq = dot(vd.pointToEye, vd.pointToEye);
    vd.invDist = rsqrt(vd.distSq);
    vd.dist = vd.distSq * vd.invDist;
    vd.distLog2 = log2(vd.dist);
    vd.distToZfar = saturate(vd.dist / zn_zfar.y);//can be replaced with mul!
    vd.pointToEyeNormalized = vd.pointToEye * vd.invDist;
    vd.nearDetailsWeight = saturate(vd.dist * details_weight.x + details_weight.y);
    vd.farDetailsWeight = 1 - saturate(vd.dist * details_weight.z + details_weight.w);
    vd.waterColorToEnvColorKoef = saturate(In.nvsf_eye_vec.w * 2.0 - 1.0); //*2.0 - 1 means: fading from zFar*0.5 to zFar
#if has_perlin_noise
    float2 wind_dir = water_level_max_wave_wind_dir.zw;
    vd.perlinWind = tex2D(perlin_noise, float2(0.00011*(vd.worldPos.x*wind_dir.x-vd.worldPos.z*wind_dir.y), 0.00041*(vd.worldPos.x*wind_dir.y+vd.worldPos.z*wind_dir.x))).ga;
    vd.perlinSurf = tex2D(perlin_noise, vd.worldPos.xz * lrefl_scatter_hdr_psize.w).ga;
#endif
    // Material
    vd.roughness = get_cascades_roughness(vd.distLog2);
    vd.roughness = lerp(vd.roughness, 1.0 - (0.71 + 0.28 * 0.5), vd.waterColorToEnvColorKoef);

    // Getting Gerstner shore waves attributes
    getShore(vd.worldPos, vd.shoreData);

    // Wake
    getWake(vd.worldPos, vd.wakeGradient);

    // Getting surface attributes from WaveWorks funcs
    float4 nvsf_blendfactors0123 = float4(1, 1, 1, 1);
    float4 nvsf_blendfactors4567 = float4(1, 1, 1, 1);
#if has_perlin_noise
    float4 perlinWaves = float4(vd.perlinSurf.yyy, pow2(vd.perlinSurf.y));
    // First tow cascades create physical waves thus damp them only if they are small
    perlinWaves.xy = lerp(perlinWaves.xy, float2(1, saturate(5 * perlinWaves.w)), vd.shoreData.oceanWavesMultiplier);
    // Last two cascades do not make any contribution to physics therefore it safe to dump them
    perlinWaves.zw = lerp(float2(perlinWaves.w, saturate(1.5 * perlinWaves.w)), saturate(5 * perlinWaves.ww), vd.shoreData.oceanWavesMultiplier);
    nvsf_blendfactors0123 *= lerp(perlinWaves, float4(1, 1, 1, 1), vd.nearDetailsWeight);
#endif
    nvsf_blendfactors0123.xy *= lerp(0.1 + 0.9 * vd.shoreData.oceanWavesMultiplier, 0.5 + 0.5 * vd.shoreData.oceanWavesMultiplier, vd.nearDetailsWeight);
    nvsf_blendfactors0123 *= 1.0 - saturate(length(vd.pointToEye.xz) * foam_tiling_bdamp_srough.z - 1.0);
    nvsf_blendfactors4567 *= 1.0 - saturate(length(vd.pointToEye.xz) * foam_tiling_bdamp_srough.z - 1.0);
    vd.surfaceAttributes = GFSDK_WaveWorks_GetSurfaceAttributes(In, nvsf_blendfactors0123, nvsf_blendfactors4567);

    vd.screenPos = screenPos;
    vd.pos_world_undisplaced = vd.pos_world_undisplaced;
##if shader == water_3d_decal
    vd.localUV_fade = In.localUV_fade;
##endif
##if compatibility_mode == compatibility_mode_off
    vd.screen_texcoord = In.screen_texcoord;
    vd.reflectionTC = In.screen_texcoord.xy/ In.screen_texcoord.w ;
##endif

    // Calc world normal
    vd.worldNormal = vd.surfaceAttributes.normal.xzy;
    // Apply wake
    vd.worldNormal.xz += vd.wakeGradient.xz * (vd.worldNormal.y * rcp(max(vd.wakeGradient.y, 0.01)));
    // Normalize
    vd.worldNormal = normalize(vd.worldNormal);

    // Applying faders to normals
    vd.worldNormal = normalize(float3(vd.worldNormal.xz*vd.shoreData.gerstner_normal.y + vd.shoreData.gerstner_normal.xz*vd.worldNormal.y, vd.shoreData.gerstner_normal.y*vd.worldNormal.y).xzy);

    // Apply rain (there are not enough registers now, turn on when at least one sampler will be available)
    //apply_rain_ripples_water(vd.worldPos, vd.dist, vd.worldNormal);
    // Calc dir for reflections
    vd.reflectDirNormalized = reflect(-vd.pointToEyeNormalized, vd.worldNormal);
    //float3 reflectDir = reflect(-vd.pointToEye, vd.worldNormal);
    vd.reflectSampleDir = vd.reflectDirNormalized;
    vd.reflectSampleDir.y = abs(vd.reflectSampleDir.y);//this hack is preventing reflection belowe horizon. In real water it can happen, but will only reflect reflecting water
    vd.distortionVector = vd.worldNormal.xz;     // Dependency from camera rotation looks unrealistic.

    /*##if (underwater_render == yes)
      vd.worldNormal = -vd.worldNormal;
      vd.reflectDirNormalized = refract(-vd.pointToEyeNormalized, vd.worldNormal, 0.8);
    ##endif*/

    // Calc view params
    vd.halfDir = normalize(vd.pointToEyeNormalized.xyz + to_sun_direction.xyz);
    vd.view = vd.pointToEyeNormalized;
    vd.NoH = saturate( dot(vd.worldNormal, vd.halfDir) );
    vd.VoH = saturate( dot(vd.view, vd.halfDir) );
    vd.NdotV = dot(vd.worldNormal, vd.pointToEyeNormalized);
    vd.NoV = abs(vd.NdotV)+1e-5;
    vd.NoL = dot(to_sun_direction.xyz, vd.worldNormal);
    float Fc = pow5(1.- vd.NoV);
    vd.fresnelView = Fc+FRESNEL_REFLECTANCE*(1-Fc);
  }

  void getShadows(ViewData vd, out ShadowsData shadowsData)
  {
#if DEBUG_WATER
    shadowsData.cloudShadow = 1;
    shadowsData.vsmShadow = 1;
    shadowsData.sunReflectionShadow = 1;
    DEBUG_WATER_RET(1, z);
#endif

    // Getting shadows
    shadowsData.cloudShadow = clouds_shadow(vd.worldPos);
##if compatibility_mode == compatibility_mode_on
    shadowsData.vsmShadow = 1;
    shadowsData.sunReflectionShadow = 1;
##else
    shadowsData.vsmShadow = def_vsm_shadow_blurred(float4(vd.worldPos, 1));
    shadowsData.sunReflectionShadow = (shadowsData.cloudShadow * 0.75 + 0.25) * (shadowsData.vsmShadow * 0.25 + 0.75); // intensity of specular mask by clouds shadow, must have outer percent parameter
##endif
  }

  void getDeepness(ViewData vd, out DeepnessData deepnessData)
  {
#if DEBUG_WATER
    deepnessData.fog_mul = half3(1, 1, 1);
    deepnessData.fog_add = half3(0, 0, 0);
    deepnessData.waterDepth = 10;
    deepnessData.underWaterPos = vd.worldPos;
    deepnessData.shore_blending_coeff = 1;
    deepnessData.refractionTexcoord = screen_pos_to_tc(vd.screenPos.xy);
    DEBUG_WATER_RET(1, w);
#endif

    get_fog(vd.pointToEyeNormalized.xyz, vd.dist, deepnessData.fog_mul, deepnessData.fog_add);
    /*##if (underwater_render == yes)
      deepnessData.fog_mul = half3(1, 1, 1);
      deepnessData.fog_add = half3(0, 0, 0);
    ##endif*/

    // Getting seabed color (refracted terrain & objects)
#if has_seabed_refraction
    float roughWaterDepth = max(linearize_z(tex2D(depth_tex, vd.reflectionTC).x, zn_zfar.zw) - vd.screen_texcoord.w, 0);
    float refractionDistortion = 0.05 * min(1, 10.0 * roughWaterDepth / (roughWaterDepth + vd.dist));
    float2 refractionDisturbance = refractionDistortion * float2(-vd.distortionVector.x, vd.distortionVector.y);
    refractionDisturbance *= saturate((linearize_z(tex2D(depth_tex, vd.reflectionTC + refractionDisturbance).x, zn_zfar.zw) - vd.screen_texcoord.w) * 2 - 0.1); // Fix scene leaks from above the water.
    deepnessData.refractionTexcoord = vd.reflectionTC + refractionDisturbance;
#else
    deepnessData.refractionTexcoord = screen_pos_to_tc(vd.screenPos.xy);
#endif

##if compatibility_mode == compatibility_mode_off && depth_tex != NULL
    float floorZ = linearize_z(tex2D(depth_tex, deepnessData.refractionTexcoord).x, zn_zfar.zw);
    floorZ += max(0, vd.screen_texcoord.w - zn_zfar.y + 100);   // Artificially increase water depth at farplane to fix transparent water over the border of the world.
    float realWaterDepth = floorZ - vd.screen_texcoord.w;
    deepnessData.waterDepth = realWaterDepth>-0.5 ? abs(realWaterDepth) : 10;
    float water_depth_hardness = foam_tiling_bdamp_srough.y;
    deepnessData.shore_blending_coeff = saturate(deepnessData.waterDepth * water_depth_hardness);

    float3 viewVect = lerp(lerp(view_vecLT, view_vecRT, deepnessData.refractionTexcoord.x), lerp(view_vecLB, view_vecRB, deepnessData.refractionTexcoord.x), deepnessData.refractionTexcoord.y);
    deepnessData.underWaterPos = world_view_pos + viewVect*floorZ;
##else
    deepnessData.underWaterPos = vd.worldPos;
    deepnessData.waterDepth = 10;
    deepnessData.shore_blending_coeff = 1;
##endif
  }

  void calcFoam(ViewData vd, DeepnessData deepnessData, out FoamData foamData)
  {
    foamData.scatterFoamFactor = 0.f;
    foamData.additionalTransparency = 1.0;
#if DEBUG_WATER
    foamData.foamFactor = 0.0;
    foamData.FoamLowFreq = 1.0;
    DEBUG_WATER_RET(2, x);
#endif

    // Adding some turbulence based bubbles spread in water
##if compatibility_mode == compatibility_mode_off
    // Getting foam textures
    float2 offs = vd.wakeGradient.xz * 0.03;
    foamData.FoamLowFreq = tex2D(foam_tex, (vd.pos_world_undisplaced.xy + offs) * foam_tiling_bdamp_srough.x).r;//0.051 plane, 0.101 tank

    // Calculating shore waves foam
    float gerstnerFoam = foamData.FoamLowFreq*vd.shoreData.gerstnerFoamFactor;

    // Calculating turbulence energy based foam
    float oceanFoamFactor = 1.0*saturate(foamData.FoamLowFreq * min(1.0,2.0*vd.surfaceAttributes.foam_turbulent_energy));

    // Clumping foam on folded areas
    oceanFoamFactor *= 1.0 + 1.0*saturate(vd.surfaceAttributes.foam_surface_folding);
    gerstnerFoam *= 1.0 + 1.0*saturate(vd.surfaceAttributes.foam_surface_folding * vd.shoreData.oceanWavesMultiplier);

    // Applying foam wave hats
  ##if shader == water_3d_decal
      foamData.additionalTransparency = decal_update_ocean_foam(vd.surfaceAttributes.foam_wave_hats, vd.localUV_fade);
  ##endif

    oceanFoamFactor += 0.1*saturate(foamData.FoamLowFreq*vd.surfaceAttributes.foam_wave_hats);
    //gerstnerFoamFactor += 0.5*saturate(FoamLowFreq*gerstner_breaker*3.0*(UltraLowFreqModulator2));

    // Combining shore and ocean foam, using high power of oceanWavesMultiplier to leave leewind areas without ocean foam
    foamData.foamFactor = vd.shoreData.oceanWavesMultiplier * oceanFoamFactor * vd.farDetailsWeight + gerstnerFoam;

  ##if shader == water_3d_decal
      foamData.additionalTransparency *= apply_decal_local_foam(vd.localUV_fade, foamData.foamFactor);
  ##endif

##else   // compatibility
    foamData.foamFactor = saturate(0.1*saturate(vd.surfaceAttributes.foam_wave_hats) * (1.0 + 1.0*saturate(vd.surfaceAttributes.foam_surface_folding))) * vd.shoreData.oceanWavesMultiplier;
    foamData.FoamLowFreq = 1;
##endif

#ifdef WATER_FOAM_TRAIL
  ##if shader != water_3d_decal
    ##if compatibility_mode == compatibility_mode_off
        get_water_foam_trail( vd.worldPos, foamData.FoamLowFreq, vd.wakeGradient.xzy, foamData.scatterFoamFactor, foamData.foamFactor );
    ##else
        get_water_foam_trail_comp( vd.worldPos, foamData.foamFactor );
    ##endif
  ##endif
#endif

    foamData.foamFactor *= deepnessData.shore_blending_coeff;
  }

  void getEnvReflections(ViewData vd, out EnvReflections envReflections)
  {
#if DEBUG_WATER
    envReflections = (EnvReflections)0;
    DEBUG_WATER_RET(2, y);
#endif

    // Taking in account the possibility for the reflection vector to point at water surface again, the reflection color is to be damped to 25%
    // gradually
    //half doubleReflectionMultiplier = 0.25+0.75*saturate(1.0 + 3.0*reflectDir.y);
    //doubleReflectionMultiplier = 1;

    //reflectDir.y = max(0,reflectDir.y);
    //roughness = lerp(roughness, AddAngleToRoughness(acos(NoV), vd.roughness), saturate(dist*(1./50)));
    //float3 roughReflection = getRoughReflectionVec(vd.reflectSampleDir.xyz, worldNormal, vd.roughness*vd.roughness);
#if USED_CLOUDS_PANORAMA
    envReflections.sky_uv = get_panorama_uv(vd.worldPos, vd.reflectSampleDir);
    envReflections.enviReflection = tex2Dlod(clouds_panorama_mip, float4(envReflections.sky_uv,0,0)).rgb;
#else
    float3 roughReflection = vd.reflectSampleDir.xyz;
    float enviMip = ComputeReflectionCaptureMipFromRoughness(vd.roughness);
    envReflections.enviReflection = texCUBElod(envi_probe_specular, float4(roughReflection, enviMip)).rgb;
#endif
  }

  void getPlanarReflections(ViewData vd, EnvReflections envReflections, out PlanarReflections planarReflections)
  {
#if DEBUG_WATER
    planarReflections.objectReflection = 0;
    planarReflections.initialWaterReflection = 0;
    DEBUG_WATER_RET(2, z);
#endif

##if water_reflection_tex == NULL || compatibility_mode == compatibility_mode_on
    planarReflections.objectReflection = 0;
    planarReflections.initialWaterReflection = 0;
##else
    float2 reflectionDistortionVector = vd.distortionVector;
    reflectionDistortionVector.y = 0.5 * abs(reflectionDistortionVector.y);
    reflectionDistortionVector *= lrefl_scatter_hdr_psize.x;

    planarReflections.initialWaterReflection = h4tex2D(water_reflection_tex, vd.reflectionTC + 0.3*reflectionDistortionVector);

    planarReflections.objectReflection =
          planarReflections.initialWaterReflection* 0.5 +
          h4tex2D(water_reflection_tex,
            vd.reflectionTC + float2(0.1, 0.6) * reflectionDistortionVector) * (0.7* 0.5) +
          h4tex2D(water_reflection_tex,
            vd.reflectionTC + float2(0.2, 1.0) * reflectionDistortionVector) * (0.3* 0.5);
    planarReflections.objectReflection.rgb *= lrefl_scatter_hdr_psize.z;
    planarReflections.objectReflection = planarReflections.objectReflection;
    float3 reflectWaterPlaneDirNormalized = reflect(-vd.pointToEyeNormalized, float3(0,1,0));
    planarReflections.objectReflection *= saturate(dot(vd.reflectDirNormalized, reflectWaterPlaneDirNormalized));
  #if USED_CLOUDS_PANORAMA
      half cloudsAlpha = 1 - get_clouds_alpha_panorama_uv(envReflections.sky_uv);
      planarReflections.initialWaterReflection.a = saturate(planarReflections.initialWaterReflection.a + cloudsAlpha);
      planarReflections.objectReflection.a = saturate(planarReflections.objectReflection.a + cloudsAlpha);
  #endif
    // Fade out on far distance
    planarReflections.initialWaterReflection *= saturate(2 * (1 - vd.distToZfar));
    planarReflections.objectReflection *= 1 - vd.distToZfar;
##endif

/*##if (underwater_render == yes)
    planarReflections.initialWaterReflection = 0;
    planarReflections.objectReflection = 0;
##endif*/
  }

  void calcSun(ViewData vd, ShadowsData shadowsData, PlanarReflections planarReflections, out SunReflections sunReflections)
  {
#if DEBUG_WATER
    sunReflections.sunReflection = half3(0, 0, 0);
    DEBUG_WATER_RET(2, w);
#endif

    //half farFactor = saturate(water_bump_far_factor * distSq);

    //float smoothness = 0.75*lerp(1, 0.5+0.5*underocean.a, farFactor);  // BY TIM //: to prevent dark "holes" in specular
#if has_perlin_noise
    half smoothness_mul = lerp(vd.perlinWind.x, 0.5, vd.distToZfar);
#else
    half smoothness_mul = 0.1;
#endif
    float smoothness = (0.71+0.28*smoothness_mul);  // BY TIM //: to prevent dark "holes" in specular
    float sun_roughness = 1-smoothness;
    float sun_roughness_for_water_to_cube = foam_tiling_bdamp_srough.w;
    sun_roughness = max(sun_roughness, sun_roughness_for_water_to_cube);

    float D = 0, G = 0;
    float3 F;
    if (vd.NoV > 0)
      sunDiskSpecular( FRESNEL_REFLECTANCE, vd.NoV, sun_roughness, to_sun_direction.xyz, vd.view, vd.worldNormal, D, G, F );
    G = 1;

    //float D = BRDF_distribution( sun_roughness, vd.vd.NoH );
    //float G = BRDF_geometricVisibility( roughness, vd.NoV, vd.NoL, vd.VoH );
    //float G = 1;
    half absNoL = abs(vd.NoL);//to avoid dark lines in specular
    half sunSpec = D*G*absNoL;

    // calculating hf specular factor
    half3 hf_normal = normalize(half3(vd.worldNormal.x,0.25, vd.worldNormal.z)); // 0.25 - tweakable - "spread" of sparkles
    //float D_sparkles, G_sparkles, F_sparkles;
    //sunWaterSpecular( NoV, sun_roughness*0.5, to_sun_direction.xyz, view, hf_normal, D_sparkles, G_sparkles, F_sparkles);
    float NoH_sparkles = saturate( dot(vd.halfDir, hf_normal) );
    float D_sparkles = BRDF_distribution( pow2(sun_roughness*0.5), NoH_sparkles );
    float maxSpec = 6.0;
    sunSpec += min(D_sparkles*G*absNoL, maxSpec)*0.5;
    sunSpec = min(sunSpec*F.x, maxSpec);
    sunSpec *= shadowsData.sunReflectionShadow * shadowsData.vsmShadow;
    sunSpec *=  saturate(1.0f - planarReflections.initialWaterReflection.a); // reflected objects mask for sun specular

    /*##if (underwater_render == yes)
      sunSpec = pow3(pow3(pow3(saturate(dot(vd.reflectDirNormalized, to_sun_direction.xyz)))));
    ##endif*/

    sunReflections.sunReflection = sun_color_0 * sunSpec;
    //result.rgb = apply_fog(sunReflections.sunReflection, pointToEye.xyz);   // simul_fog on PC, none on consoles.
    //result.rgb = pack_hdr(result.rgb).rgb;
    //result.a=1;
    //return result;
  }

  void getReflections(ViewData vd, EnvReflections envReflections, PlanarReflections planarReflections, SunReflections sunReflections, FoamData foamData, DeepnessData deepnessData, out ReflectionsData reflectionsData)
  {
#if DEBUG_WATER
    if (DEBUG_WATER_MASK(2, y))
    {
      planarReflections.objectReflection.a = 1.0;
    }
#endif

    half enviBRDF = saturate(EnvBRDFApprox( FRESNEL_REFLECTANCE, vd.roughness, vd.NoV).x);//fixme: optimize for water
    reflectionsData.reflectionColor = (envReflections.enviReflection * (1 - planarReflections.objectReflection.a) + planarReflections.objectReflection.rgb)*enviBRDF;

    half3 sunReflFinal = lerp(sunReflections.sunReflection, float3(0, 0, 0), saturate(foamData.foamFactor * 10));    // Remove specular from slightly foamed water.
    reflectionsData.reflectionColor += sunReflFinal;
    reflectionsData.reflectionColor *= deepnessData.shore_blending_coeff;

    //switch to sky color if pixel close to camera far plane
##if compatibility_mode == compatibility_mode_on
    reflectionsData.envReflection = get_ground_lit_color_compatibility();
##else
    reflectionsData.envReflection = envReflections.enviReflection * enviBRDF + sunReflFinal;
##endif
  }

  void getSeabedRefraction(DeepnessData deepnessData, out SeabedRefraction seabedRefraction)
  {
#if DEBUG_WATER
    seabedRefraction.seabedColor.rgb = half3(0, 0, 0);
    DEBUG_WATER_RET(3, x);
#endif

  // Getting seabed color (refracted terrain & objects)
#if has_seabed_refraction
    seabedRefraction.seabedColor.rgb = tex2Dlod(water_refraction_tex, float4(deepnessData.refractionTexcoord, 0, 0)).rgb;
    seabedRefraction.seabedColor.rgb = max(float3(0,0,0), unpack_hdr(half4(seabedRefraction.seabedColor.rgb, 1)).rgb-deepnessData.fog_add);//currently works not precise
#else
    seabedRefraction.seabedColor = float3(0.07, 0.1, 0.07);//fixme: sample lastclip here
#endif
  }

  void getSubSurfScattering(ViewData vd, out SubSurfScattering subSurfScattering)
  {
#if DEBUG_WATER
    subSurfScattering.scatterFactor = 0;
    DEBUG_WATER_RET(3, y);
#endif

    // Adding subsurface scattering/double refraction to refraction color
    // simulating scattering/double refraction: light hits the side of wave, travels some distance in water, and leaves wave on the other side
    // it is difficult to do it physically correct without photon mapping/ray tracing, so using simple but plausible emulation below

    // scattering needs to be faded out at distance
##if compatibility_mode == compatibility_mode_off && water_vs_cascades != zero
    const half scatterIntensity = 1.0;
    half distanceFaderStartingAt1000m =  rcp(1+vd.dist*(1./1000));

    // only the crests of water waves generate double refracted light
    half displaceY = log2(max(1, vd.worldPos.y - vd.pos_world_undisplaced.z + 2.0));
    subSurfScattering.scatterFactor = scatterIntensity * displaceY * distanceFaderStartingAt1000m*lrefl_scatter_hdr_psize.y;

    // the waves that lie between camera and light projection on water plane generate maximal amount of double refracted light
    subSurfScattering.scatterFactor *= pow2(max(0.0,dot((float3(-to_sun_direction.x,0.0,-to_sun_direction.z)),vd.pointToEyeNormalized)));

    // the slopes of waves that are oriented back to light generate maximal amount of double refracted light
    subSurfScattering.scatterFactor *= pow4(1 - vd.NoL)*2;//up to 2^4

    //scatterFactor *= 1-saturate(sdf.x*heightmap_min_max.z+heightmap_min_max.w-vd.worldPos.y+2);
  ##if shader != water3d_compatibility
    subSurfScattering.scatterFactor *= 1-saturate(vd.shoreData.landHeight);
  ##endif
##else
    subSurfScattering.scatterFactor = 0;
##endif
  }

  void getUnderWaterScattering(ViewData vd, DeepnessData deepnessData, FoamData foamData, out UnderWaterScattering underWaterScattering)
  {
#if DEBUG_WATER
    underWaterScattering.underwater_inscatter = half3(0, 0, 0);
    underWaterScattering.underwater_loss = half3(1, 1, 1);
    DEBUG_WATER_RET(3, z);
#endif

    float water_deep_down = max(0, vd.worldPos.y - deepnessData.underWaterPos.y);//
    //use if there is no sdf factor
    //float ocean_part = saturate(inv_river_depth * water_deep_down);
    //ocean_part = lerp(1, ocean_part, saturate((view.y+0.1)*10));
    //else use sdf
    float ocean_part = vd.shoreData.riverMultiplier;
#if has_perlin_noise
    half perlinWaterColor = vd.perlinSurf.x;
#else
    half perlinWaterColor = 0.5;
#endif
    get_underwater_fog_perlin(vd.worldPos, deepnessData.underWaterPos, vd.pointToEyeNormalized, deepnessData.waterDepth, water_deep_down, ocean_part, perlinWaterColor, underWaterScattering.underwater_loss, underWaterScattering.underwater_inscatter);
##if compatibility_mode == compatibility_mode_off
    underWaterScattering.underwater_inscatter += foamData.scatterFoamFactor * ocean0;
    underWaterScattering.underwater_inscatter *= deepnessData.shore_blending_coeff;
##endif

/*##if underwater_render == yes
    underWaterScattering.underwater_loss = 1;
##endif*/
  }

  void getRefractions(ViewData vd, ShadowsData shadowsData, DeepnessData deepnessData, SeabedRefraction seabedRefraction, SubSurfScattering subSurfScattering, UnderWaterScattering underWaterScattering, out RefractionsData refractionsData)
  {
##if compatibility_mode == compatibility_mode_off
  #if !has_seabed_refraction
    refractionsData.waterOpacity = saturate(1-luminance(underWaterScattering.underwater_loss));//luminocity?
  #endif
##endif

    half3 lighting = sun_color_0 * (subSurfScattering.scatterFactor * (shadowsData.cloudShadow * 0.75 + 0.25) * shadowsData.vsmShadow + saturate(0.6 + 0.4 * vd.NoL));
    ##if compatibility_mode == compatibility_mode_off
    lighting *= shadowsData.sunReflectionShadow;
    ##endif
    lighting += sky_color;

    // Getting final refraction color
##if compatibility_mode == compatibility_mode_on
    refractionsData.finalLitRefraction = underWaterScattering.underwater_inscatter * lighting;//fixme
##else
  #if has_seabed_refraction
    refractionsData.finalLitRefraction = underWaterScattering.underwater_loss * seabedRefraction.seabedColor.rgb + underWaterScattering.underwater_inscatter * lighting;
  #else
    refractionsData.finalLitRefraction = underWaterScattering.underwater_inscatter * lighting;
  #endif
##endif

    // Applying fresnel factor
    half fresnel = vd.fresnelView * deepnessData.shore_blending_coeff; // making water/terrain intersections looking smooth (fresnel is faded to 0 on depths 0.33..0m)
    refractionsData.finalLitRefraction = refractionsData.finalLitRefraction * (1 - fresnel);
  }

  void getProjectionEffects(ViewData vd, FoamData foamData, out ProjectionEffects projectionEffects)
  {
#if !has_projection_effects || DEBUG_WATER
    projectionEffects.waterProjEffectsColor = half4(0, 0, 0, 1);
    DEBUG_WATER_RET(3, w);
#endif

#if has_projection_effects
    projectionEffects.waterProjEffectsColor = get_water_projection_effects(vd.worldPos, foamData.FoamLowFreq);
#endif
  }

  half4 calcFinalColor(ViewData vd, ShadowsData shadowsData, FoamData foamData, DeepnessData deepnessData, RefractionsData refractionsData, ReflectionsData reflectionsData, ProjectionEffects projectionEffects)
  {
    float4 result = float4(refractionsData.finalLitRefraction + reflectionsData.reflectionColor, 1.0);
    result.rgb = lerp(result.rgb, reflectionsData.envReflection, vd.waterColorToEnvColorKoef);

    // Applying projected on water effects
    half3 surfaceFoamColor = sun_color_0 * (saturate(0.6 + 0.4 * vd.NoL) * shadowsData.sunReflectionShadow) + sky_color;
#if has_projection_effects
    //apply lighting
    float4 effectsColor = projectionEffects.waterProjEffectsColor;
    effectsColor.rgb *= deepnessData.shore_blending_coeff;
    effectsColor.a = lerp(1, effectsColor.a, deepnessData.shore_blending_coeff);
    result.rgb = result.rgb * effectsColor.a + surfaceFoamColor * effectsColor.rgb;
#endif
    // Applying surface foam
    result.rgb = lerp(result.rgb, surfaceFoamColor, foamData.foamFactor);

    // Applying fog
##if compatibility_mode == compatibility_mode_off
  #if has_seabed_refraction
    result.a = 1.0;
  #else
    result.a = refractionsData.waterOpacity * (1 - foamData.foamFactor); //waterOpacity;////fresnelWaterOpacity + foamData.foamFactor;
  #endif
##else
    result.a = 1.0;
##endif

##if shader == water_3d_decal
    result.a = (1 - foamData.foamFactor) * foamData.additionalTransparency;
##endif

#if has_seabed_refraction
    result.rgb = result.rgb * deepnessData.fog_mul + deepnessData.fog_add;   // simul_fog on PC, none on consoles.
#else
    result.rgb = result.rgb * deepnessData.fog_mul + deepnessData.fog_add * result.a;   // simul_fog on PC, none on consoles.
#endif

    return result;
  }

  half4 water_nv_ps(VS_OUTPUT In HW_USE_SCREEN_POS) : SV_Target0
  {
    float4 screenpos = GET_SCREEN_POS(In.pos_clip);
    // Common view data
    ViewData vd;
    calcViewData(In, screenpos, vd);

    // Shadow factors
    ShadowsData shadowsData;
    getShadows(vd, shadowsData);

    // Getting water depth and opacity for blending
    DeepnessData deepnessData;
    getDeepness(vd, deepnessData);

    // Calc foam
    FoamData foamData;
    calcFoam(vd, deepnessData, foamData);

    // Caclulating reflection color
    ReflectionsData reflectionsData;
    {
      // Environment reflections
      EnvReflections envReflections;
      getEnvReflections(vd, envReflections);

      // Refleciotns from objects
      PlanarReflections planarReflections;
      getPlanarReflections(vd, envReflections, planarReflections);

      // Calculating specular
      SunReflections sunReflections;
      calcSun(vd, shadowsData, planarReflections, sunReflections);

      getReflections(vd, envReflections, planarReflections, sunReflections, foamData, deepnessData, reflectionsData);
    }

    // Getting final refraction color
    RefractionsData refractionsData;
    {
      // Underwater
      SeabedRefraction seabedRefraction;
      getSeabedRefraction(deepnessData, seabedRefraction);

      // Surface scattering
      SubSurfScattering subSurfScattering;
      getSubSurfScattering(vd, subSurfScattering);

      // Underwater scattering
      UnderWaterScattering underWaterScattering;
      getUnderWaterScattering(vd, deepnessData, foamData, underWaterScattering);

      getRefractions(vd, shadowsData, deepnessData, seabedRefraction, subSurfScattering, underWaterScattering, refractionsData);
    }

    // Get effects
    ProjectionEffects projectionEffects;
    getProjectionEffects(vd, foamData, projectionEffects);

    // Final color
    float4 result = calcFinalColor(vd, shadowsData, foamData, deepnessData, refractionsData, reflectionsData, projectionEffects);

    result.rgb = pack_hdr(result.rgb).rgb;
    return result;
  }}
  compile("target_vs", "water_nv_vs");
  compile("target_ps", "water_nv_ps");

} /*else
  if (water_render_pass == depth_pass)
  {
    PS4_DEF_TARGET_FMT_32_AR()
    hlsl(ps) {
      float4 water_nv_depth_ps(VS_OUTPUT In) : SV_Target0
      {
        return In.lin_z;
      }
    }
    compile("target_vs", "water_nv_vs");
    compile("target_ps", "water_nv_depth_ps");
  }
}*/
include "sky_shader_global.sh"
include "viewVecVS.sh"
include "distanceToClouds2.sh"
include "cloudsShadowVolume.sh"
include "clouds_density_height_lut.sh"
include "clouds_tiled_dist.sh"
include "clouds_close_layer_outside.sh"
include "cloudsDensity.sh"
include "cloudsLighting.sh"
include "clouds_sun_light.sh"
include "panorama.sh"
include "skies_special_vision.sh"
include "renderSkiesInc.sh"
include "tonemapHelpers/use_full_tonemap_lut_inc.sh"

texture clouds_field_volume_low;
float4 clouds_field_res;//.xy - xz&y of res, .zw - xz&y of target res
int clouds_field_downsample_ratio = 8;

float clouds_offset = 0;
int clouds_has_close_sequence = 1;
texture clouds_depth_gbuf;
int clouds_infinite_skies;
int clouds_panorama_frame;

float4 nuke_light_color;

//the higher the better quality is. but after 4 it doesn't really changes.
//If you fly in clouds, use pow-of-2 (i.e 1,2,4), otherwise you will get some blinking due to fp precision and rounding errors
float clouds_steps_per_sequence = 2;//2 is default, 4 is excellent
float4 clouds_trace_steps = (256, 64, 0, 0);    // x - at horizon, y - at zenith

float4 lightning_point_light_pos = (0, 0, 0, 0);
float4 lightning_point_light_color = (0.8, 0.8, 0.8, 0);
int lightning_render_additional_point_light = 0;
int lightning_additional_point_light_natural_fade = 0;
float lightning_additional_point_light_radius = 100000;
float lightning_additional_point_light_strength = 1.0;
float lightning_additional_point_light_extinction_threshold = 0.1;

int lightning_in_clouds = 0;
interval lightning_in_clouds: off<1, on;

int clouds_panorama_depth_out = 0;
interval clouds_panorama_depth_out: off < 1, on;

int clouds_panorama_split = 0;
interval clouds_panorama_split: off < 1, trace < 2, blend;


hlsl {
  #define MAX_CLOUDS_SHADOW_DIST (100*1000)
}

int clouds2_current_frame = 0;

macro RAYCAST_CLOUDS(code)
  hlsl {
    ##if shader == clouds_panorama || shader == clouds_alpha_panorama
      #define DUAL_PANORAMA 1
      #include <panorama_samples.hlsli>
    ##endif
    ##if shader == clouds2_direct || shader == clouds2_direct_cs
      #define HAS_DEPTH_TARGET 0
      #define TEMPORAL_REPROJECTION 0
      #define INFINITE_SKIES 1
    ##endif
    ##if shader == clouds2_temporal_ps || shader == clouds2_temporal_cs
      #define HAS_DEPTH_TARGET 1
      #define TEMPORAL_REPROJECTION 1
    ##endif
    ##if shader == clouds2_close_temporal_ps || shader == clouds2_close_temporal_cs
      #define HAS_DEPTH_TARGET 0
      #define TEMPORAL_REPROJECTION 0
      #define JUST_CLOSE_SEQUENCE 1
    ##endif
    ##if clouds_use_fullres == yes
      #define CLOUDS_FULLRES 1
    ##endif
  }

  hlsl {
    //settings
    #define WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE 3//For planes better use WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE.
    #define WEIGHTED_ATMOSPHERE_SCATTERING_ONCE 2//produces some artefacts when clouds visible through clouds. For planes better use WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE, for panorama/view from ground is good enough
    #define WEIGHTED_ATMOSPHERE_SCATTERING_NONE 0//No atmosphere

    //#define CAN_BE_IN_CLOUDS 0//For panorama and 'shooter' mode (tank/ship)
    //#define CLOUDS_JUST_ONE_SEQUENCE 1//if we are not flying through clouds, stability isn't a concern. But that's way faster. For panorama and 'shooter' mode (tank/ship) (CAN_BE_IN_CLOUDS  = 1) after defined

   //panorama
   #if DUAL_PANORAMA
     //#define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
     #define CLOUDS_FIXED_LOD 1
     #define CAN_BE_IN_CLOUDS 1//panorama should not be rendered FROM clouds//todo: remove me!
     //#define CLOUDS_STATE 0//below clouds
     #define CLOUDS_LIGHT_SAMPLES 6
     #define INFINITE_SKIES 1//don't sample depth
     #define DUAL_PANORAMA 1
     #define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE
     #define CLOUDS_JUST_ONE_SEQUENCE 1//?
   #elif defined(CAN_BE_IN_CLOUDS) && !CAN_BE_IN_CLOUDS
     //we don't need variance clipping for that, and can immedieately reproject
     #define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
     #define CLOUDS_FIXED_LOD 1
     //#define CLOUDS_STATE 0//below clouds
     #define CLOUDS_LIGHT_SAMPLES 6
     #define CLOUDS_JUST_ONE_SEQUENCE 1
     //#error not supported yet
   #else
     //flying through clouds - temporal + close
     #define CLOUDS_LIGHT_SAMPLES 6
     #define CAN_BE_IN_CLOUDS 1

     #if !JUST_CLOSE_SEQUENCE
       #define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE//WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
       #define CLOUDS_FIXED_LOD 0
       #define CLOUDS_CHECK_ALT_FRACTION_IS_OUT (!_HARDWARE_XBOX && !_HARDWARE_PS4 && !_HARDWARE_PS5)//on nvidia it seems to help a bit, for unknown reason
       #define RENDER_TO_TAA_SPACE TEMPORAL_REPROJECTION
       //for shooter dynamic clouds in camera:
       //#define STEPS_PER_SEQUENCE 16
       //#define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
       //no close clouds
       //and for inifinite clouds
       //no discontinuities in taa
       //#define INFINITE_SKIES 1//don't sample depth
       //simple apply (no bilateral)
     #else
       #define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
       #define CLOUDS_FIXED_LOD 1
       #define SIMPLIFIED_ALT_FRACTION 1//difference is small. we can assume it is not changing
     #endif
    #endif

    /*#undef CLOUDS_JUST_ONE_SEQUENCE
    #undef WEIGHTED_ATMOSPHERE_SCATTERING
    #define CLOUDS_JUST_ONE_SEQUENCE 1
    #define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_ONCE*/

    //#if CLOUDS_JUST_ONE_SEQUENCE ==1 && WEIGHTED_ATMOSPHERE_SCATTERING != WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
    //  #error invalid combination
    //#endif

    //if we can't use panorama, but we are definetly below clouds (i.e. looking from ground)
    /*#define CLOUDS_JUST_ONE_SEQUENCE 1
    #if CLOUDS_JUST_ONE_SEQUENCE
      #undef CLOUDS_LIGHT_SAMPLES
      #define CLOUDS_LIGHT_SAMPLES 6

      #undef WEIGHTED_ATMOSPHERE_SCATTERING
      #define WEIGHTED_ATMOSPHERE_SCATTERING WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
    #endif*/

    //end of settings
  }
  if (shader == clouds2_close_temporal_ps || shader == clouds2_close_temporal_cs)
  {
    CLOSE_LAYER_EARLY_EXIT(code)
  } else if (shader == clouds2_temporal_ps || shader == clouds2_temporal_cs)
  {
    USE_CLOUDS_DISTANCE(code)
    (code) {clouds_has_close_sequence@f1 = (clouds_has_close_sequence*(1-clouds_infinite_skies),0,0,0);}
  } else if (shader == clouds2_direct)
  {
    hlsl(code){static const bool clouds_has_close_sequence = false;}
  }


  DISTANCE_TO_CLOUDS2(code)
  local float4 offseted_view_pos = (skies_world_view_pos.x+clouds_origin_offset.x, max(skies_world_view_pos.y, 10.-min_ground_offset), skies_world_view_pos.z+clouds_origin_offset.y,0);
  if ((shader == clouds_panorama || shader == clouds_alpha_panorama) && clouds_field_volume==NULL)
  {
    SAMPLE_CLOUDS_DENSITY_MATH_ONLY(code, offseted_view_pos)
  } else
  {
    SAMPLE_CLOUDS_DENSITY_TEXTURE(code, offseted_view_pos)
  }

  //CLOUDS_MULTIPLE_SCATTERING(code)
  INIT_ZNZFAR_STAGE(code)
  (code) {
    skies_world_view_pos@f3 = (skies_world_view_pos.x, max(skies_world_view_pos.y, 10.-min_ground_offset), skies_world_view_pos.z, 0);
    clouds_start_trace_base@f3 = (offseted_view_pos);
  }
  if (shader != clouds_panorama && shader != clouds_alpha_panorama)
  {
    (code) { clouds_offset@f1 = (clouds_offset); }
    (code) {
      clouds_infinite_skies@f1 = (clouds_infinite_skies);
      steps_per_sequence@f1 = (16*max(1, clouds_steps_per_sequence),0,0,0);//can be independent parameter. but better be pow2
    }
    hlsl(code) {
      #define USE_FROXELS_FOG 1
    }
  } else
  {
    hlsl(code) { static const float clouds_offset = 0; }
  }
  INIT_CLOUDS_SHADOWS_VOLUME(code)
  USE_CLOUDS_SHADOWS_VOLUME(code)
  CLOUDS_LIGHTING_COMMON(code)
  USE_CLOUDS_DISTANCE_STUB(code)
  CLOSE_LAYER_EARLY_EXIT_STUB(code)

  INIT_BRUNETON_FOG(code)
  BASE_USE_BRUNETON_FOG(code)
  //BRUNETON_IRRADIANCE(code)
  CLOUDS_SUN_SKY_LIGHT_COLOR(code)
  (code) {
    clouds_altitudes@f2 = (clouds_start_altitude2+skies_planet_radius, clouds_start_altitude2+skies_planet_radius+clouds_thickness2,0,0);
    skies_primary_sun_light_dir@f3 = skies_primary_sun_light_dir;
  }
  hlsl(code) {
    //#define SunLightingPixelHelper half_octaves
    struct SunLightingPixelHelper {half_octaves phase;};
    SunLightingPixelHelper getSunHelper(float3 view)
    {
      float cos0 = dot(skies_primary_sun_light_dir.xyz, view.xzy);
      half_octaves phase = henyey_greenstein_optimized_multiple_scattering(cos0);
      //return SunLightingPixelHelper(phase);
      SunLightingPixelHelper ret;
      ret.phase = phase;
      return ret;
    }

    half2 sunAmbientLuminance(float3 worldPos, float heightFraction, float base_mip, float erosion_level, SunLightingPixelHelper sunHelper)
    {
      //todo: for high quality add additional toroidally updated volume shadows around camera. We can singificanly increase quality
      float ambientV = 1;
      #if CLOUDS_PREBAKED_FIELD
        float3 volTc = getCloudsShadows3dTC(worldPos, heightFraction);
        float2 shadow_ambient = getCloudsShadows3d(volTc);
        ambientV = shadow_ambient.y;
        //that is not entirely correct on earlier octaves due to filtering. because (0.5(a+b))^c != 0.5(a^c+b^c). But this is way faster and less memory...
        //we can probably consider storing also FIRST octave separately (i.e 11,11,10 32 bit format), and incorrectly filter only less important octaves (i.e. 2th or 2th/3rd).
        #if CLOUDS_VOLUME_SHADOWS_AND_STEPS// || 1
          float directShadowStep = 64;
          float3 sampleShadowPos = worldPos + skies_primary_sun_light_dir.xzy*(directShadowStep*(1+1.5+2.25));
          volTc = getCloudsShadows3dTC(sampleShadowPos, alt_fraction_in_clouds(sampleShadowPos));
          float2 shadow_ambient = getCloudsShadows3d(volTc);
          //ambientV = shadow_ambient.y;//fixme: ambient should be from original, not offseted volTC. Although would be faster.
          //todo: use 2-3 explicit steps, not common function, avoid branching
          baseLightExtinction(shadow_ambient.x, worldPos, heightFraction, directShadowStep, base_mip, 2./CLOUDS_LIGHT_SAMPLES, erosion_level, 0.1, skies_primary_sun_light_dir.xzy, 3, 0.5);
        #endif
        float last_octave_extinction = shadow_ambient.x;
      #else
        float last_octave_extinction = 1.0;
        baseLightExtinction(last_octave_extinction, worldPos, heightFraction,
          128.0,//shadowStepSize
          base_mip, 2./CLOUDS_LIGHT_SAMPLES, erosion_level,
          0.1,//threshold
          skies_primary_sun_light_dir.xzy,
          CLOUDS_LIGHT_SAMPLES,
          0.125*(12./CLOUDS_LIGHT_SAMPLES));
      #endif
      //we integrate ambient separately from sun, to save multiplication per step *cloud_sun_light.
      //this saves few instruction and reduces register pressure
      return float2(dot(sunHelper.phase, getMSExtinction(last_octave_extinction)), ambientV);
    }
  }
  if (shader != clouds_panorama && shader != clouds_alpha_panorama)
  {
    (code) {
      clouds_depth_gbuf@smp2d = clouds_depth_gbuf;
      current_frame_info@f1 = (clouds2_current_frame, 0,0,0);
    }
  } else
  {
    (code) {
      clouds_field_volume_low@smp3d = clouds_field_volume_low;
      lowres_texel_size@f1 = (min(clouds_weather_size/(clouds_field_res.x/clouds_field_downsample_ratio), clouds_thickness2*1000/(clouds_field_res.y/clouds_field_downsample_ratio)));
      current_frame_info@f2 = (clouds_panorama_frame, 1.0 / (clouds_panorama_frame + 1.0),0,0);
    }
    hlsl(code) {
      #if MOBILE_DEVICE
        //less divergence & register space usage is more profitable on mobile devices (less cores/smaller warps)
        //and there is also problems with complex flow control causing some devices to render garbadge
        //
        //disabling this optimization keeps performance same as with this optimization
        //while fixing problems with flow control
        #define CLOUDS_OPTIMIZE_OUTER_LOOP 0
      #else
        #define CLOUDS_OPTIMIZE_OUTER_LOOP CLOUDS_PREBAKED_FIELDS
      #endif
    }
  }
  local float infMul = (((1 - 0.5/skies_froxels_resolution.z) - skies_frustum_scattering_last_tz) / max(1, 245000-skies_froxels_resolution.w));
  (code) {
    //returns skies_frustum_scattering_last_tz at skies_froxels_resolution.w, and 1 - 0.5/skies_froxels_resolution.z at 280km/
    infinite_skies_madd@f3 = (infMul, skies_frustum_scattering_last_tz - skies_froxels_resolution.w*infMul, 1 - 0.5/skies_froxels_resolution.z,0);
    nuke_light_color@f4 = nuke_light_color;
    shadow_steps_for_nuke__trace_steps@f4 = (1 + clouds_steps_per_sequence, 0.5 / (1 + clouds_steps_per_sequence), clouds_trace_steps.x, clouds_trace_steps.y);
  }

  if (lightning_in_clouds == on && shader != clouds_panorama && shader != clouds_alpha_panorama) {
    (code) {
      lightning_point_light_pos@f3 = (lightning_point_light_pos.x + clouds_origin_offset.x, lightning_point_light_pos.y, lightning_point_light_pos.z + clouds_origin_offset.y, 0);
      lightning_point_light_color@f3 = lightning_point_light_color;
      lightning_render_additional_point_light@i1 = (lightning_render_additional_point_light);
      lightning_additional_point_light_natural_fade@i1 = (lightning_additional_point_light_natural_fade);
      lightning_additional_point_params@f3 = (lightning_additional_point_light_radius, lightning_additional_point_light_strength, lightning_additional_point_light_extinction_threshold, 0)
    }
  }
  SAMPLE_CLOUDS_NUKE_INVERSION(code)

  hlsl(code) {
    #define shadow_steps_for_nuke float2(shadow_steps_for_nuke__trace_steps.xy)
    #define trace_steps float2(shadow_steps_for_nuke__trace_steps.zw)

    struct AccumulationConstParams
    {
      float3 pos;
      float cloud_density;
      float3 clouds_hole_offset;
      float height_fraction;
      float mip;
      float erosion_level;
      float beers_term;
      float3 integrated_scattering_transmittance;
    };

    void calculate_additional_lighting(AccumulationConstParams cp, inout float3 additional_lighting)
    {
##if nuke_in_atmosphere == on && shader != clouds_panorama && shader != clouds_alpha_panorama
      if (nuke_light_color.w > 0)
      {
        float lightDist = length(cp.pos - nuke_pos.xyz);
        float radFade = saturate((nuke_light_color.w-lightDist)/nuke_light_color.w);
        if (radFade > 0)
        {
          float3 lightDir = (nuke_pos.xyz - cp.pos)*rcp(lightDist);
          float shadow = 1;
          baseLightExtinction(shadow, cp.pos + cp.clouds_hole_offset, cp.height_fraction, shadow_steps_for_nuke.y*lightDist, cp.mip,
                              2./CLOUDS_LIGHT_SAMPLES, cp.erosion_level, 0.1, lightDir.xyz, shadow_steps_for_nuke.x, 1);
          additional_lighting += pow2((1 - cp.beers_term)) * cp.integrated_scattering_transmittance.z * shadow *
                              radFade * nuke_light_color.rgb * nuke_light_color.w / pow2(lightDist);
        }
      }
      // TODO: enable lightning flash with nuke lights
##elif lightning_in_clouds == on && shader != clouds_panorama && shader != clouds_alpha_panorama
      float lightRadius = lightning_additional_point_params.x;
      if (lightning_render_additional_point_light == 1 && lightRadius > 0)
      {
        float lightDist = length(cp.pos - lightning_point_light_pos);
        BRANCH
        if (lightDist > lightRadius)
          return;
        float lightStrength = lightning_additional_point_params.y;
        float distanceFade = - (lightStrength / lightRadius) * lightDist + lightStrength;
        float naturalFade = 1.0;
        BRANCH
        if (lightning_additional_point_light_natural_fade == 1)
          naturalFade = lightRadius / pow2(lightDist);
        BRANCH
        if (distanceFade > 0)
        {
          float3 lightDir = (lightning_point_light_pos - cp.pos)*rcp(lightDist);
          float shadow = 1;
          baseLightExtinction(shadow, cp.pos + cp.clouds_hole_offset, cp.height_fraction, shadow_steps_for_nuke.y*lightDist, cp.mip,
                              2./CLOUDS_LIGHT_SAMPLES, cp.erosion_level, lightning_additional_point_params.z, lightDir.xyz, shadow_steps_for_nuke.x, 1);
          additional_lighting += pow2((1 - cp.beers_term)) * cp.integrated_scattering_transmittance.z * shadow *
                              distanceFade * lightning_point_light_color.rgb * naturalFade;
        }
      }
##endif
    }
  }

  hlsl(code) {
    float get_scattering_tc_long_z(float dist)
    {
      float tcZ = sqrt(dist*skies_panoramic_scattering__inv_distance.y);
      FLATTEN if (tcZ > skies_panoramic_scattering__inv_distance.w)
        tcZ = saturate(dist*infinite_skies_madd.x + infinite_skies_madd.y);
        //tcZ = 1-pow2(1-saturate(dist*infinite_skies_madd.x + infinite_skies_madd.y));
        //tcZ = sqrt(saturate(dist*infinite_skies_madd.x + infinite_skies_madd.y));
      return tcZ;
    }

    void performSequence(float distStart, int e, float3 view, float stepSize, float end,
                           SunLightingPixelHelper sunPixelHelper,
                           float threshold,
                           inout float weightedSequenceDist,
                           inout float totalSequenceWeight,
                           inout float3 integratedScatteringTransmittance, inout float dist,
                           inout float3 additionalLighting,
                           float2 distMulAdd, float erosion_level, bool first_slice_disapper = false)
    {
      float3 viewStep = view*stepSize;//can be replaced with inout viewStep and add
      float mip = distMulAdd.x != 0 ? clamp(dist/30000-1, 0, 2) : 0;//switch off mip selection on first sequence
      e = min(e, int(floor((end-dist)/stepSize)));//do not go outside planned

      #if !defined(CLOUDS_USE_APPROXIMATE_ALT_FRACTION)
        #if !CLOUDS_JUST_ONE_SEQUENCE && !JUST_CLOSE_SEQUENCE
          #define CLOUDS_USE_APPROXIMATE_ALT_FRACTION 1
        #else
          #define CLOUDS_USE_APPROXIMATE_ALT_FRACTION 0
        #endif
      #endif

      float3 clouds_hole_offset = get_clouds_hole_pos_vec();
      float3 clouds_start_trace = clouds_start_trace_base + clouds_hole_offset;
      #if CLOUDS_OPTIMIZE_OUTER_LOOP
      const int skipLoops = lowres_texel_size/stepSize;
      if (skipLoops > 2)
      {
        float skipStepSize = stepSize*skipLoops;
        int fi = 0;
        LOOP
        for (; fi < e; fi+=skipLoops)
        {
          //this is actually end of loop footer, but we use continue instead of branch.
          float3 sample_pos = view*dist + clouds_start_trace;
          bool isHit = tex3Dlod(clouds_field_volume_low, float4(getFieldTC(sample_pos, clouds_hole_offset),0)).x>0;
          if (isHit)
          {
            dist = (fi != 0) ? dist - skipStepSize : dist;
            fi = (fi != 0) ? fi-skipLoops : fi;
            break;
          }
          dist += skipStepSize;
        }
        e -= fi;

        float3 endPos = view*(dist+(e-1.)*stepSize) + clouds_start_trace;
        int ei = 0;
        LOOP
        for (; ei < e; ei += skipLoops, endPos -= view*skipStepSize)
        {
          //this is actually end of loop footer, but we use continue instead of branch.
          bool isHit = tex3Dlod(clouds_field_volume_low, float4(getFieldTC(endPos, clouds_hole_offset),0)).x>0;

          if (isHit)
          {
            ei = (ei!=0) ? ei-skipLoops : ei;
            break;
          }
        }
        e -= ei;
      }
      #endif

      #if CLOUDS_USE_APPROXIMATE_ALT_FRACTION
      float heightFractionStart, heightFractionStep;
      {
        float3 st = view*dist + clouds_start_trace;
        heightFractionStart = precise_alt_fraction_in_clouds(st);
        float totalDist = e*stepSize;
        float heightFractionEnd = precise_alt_fraction_in_clouds(st + view*totalDist);
        heightFractionStep = (heightFractionEnd-heightFractionStart)/totalDist;
        heightFractionStart -= heightFractionStep*dist;
      }
      #endif

      float negSteps = min(0, max(-e, floor((dist-distStart)/stepSize)));
      e += int(negSteps);
      dist -= negSteps*stepSize;
      float sigmaDs = CLOUDS_SIGMA*stepSize;//0.04..0.012 are valid clouds extinction coef
      //int count = 0;
      LOOP
      for (int i = 0; i < e; ++i, dist += stepSize)
      {
        float3 sample_pos = view*dist + clouds_start_trace;
        // end of end-of-loop footer
        //float erosion_level = saturate(3 + (-1./30000)*dist);//start disappearing at 40km, completely disappears at 60km
        //erosion_level = 1;
        //count++;
        float heightFraction;
        #if CLOUDS_USE_APPROXIMATE_ALT_FRACTION
        heightFraction = heightFractionStart + dist*heightFractionStep;//instead of accurate alt fraction we use partial linear
        float cloudDensity = sampleCloudDensity(sample_pos, erosion_level, mip, heightFraction, true);
        #else
        float cloudDensity = sampleCloudDensityWithHole(sample_pos, erosion_level, mip, heightFraction, clouds_hole_offset);
        #endif

        ##if nuke_in_atmosphere == on
          cloudDensity = sampleNukeCloudsInversion(sample_pos-clouds_hole_offset, cloudDensity, heightFraction);
        ##endif

        //this is for near plane transition. Only needed for first sequence. Cost up to 0.1ms
        if (cloudDensity <= 0.0000001)
          continue;
        //beers law
        //cloudDensity *= sqrt(saturate(dist*distMulAdd.x + distMulAdd.y));//smoothstep(0, 1, (dist*distMulAdd.x + distMulAdd.y));
        if (first_slice_disapper)//that is useful only for first slice
          cloudDensity *= saturate(dist*1./32);
        float beers_term = exp2(cloudDensity * sigmaDs);
        beers_term = lerp(1, beers_term, saturate(dist*distMulAdd.x + distMulAdd.y));//smoothstep(0, 1, (dist*distMulAdd.x + distMulAdd.y));
        float transmittance  = beers_term;
        float weight = 1-transmittance;
        weightedSequenceDist += dist*weight;
        totalSequenceWeight += weight;

        AccumulationConstParams cp;
        cp.pos = sample_pos - clouds_hole_offset;
        cp.cloud_density = cloudDensity;
        cp.clouds_hole_offset = clouds_hole_offset;
        cp.height_fraction = heightFraction;
        cp.mip = mip;
        cp.erosion_level = erosion_level;
        cp.beers_term = beers_term;
        cp.integrated_scattering_transmittance = integratedScatteringTransmittance;

        calculate_additional_lighting(cp, additionalLighting);

        // Get sun luminance according to volumetric shadow and phase function
        float2 luminance = sunAmbientLuminance(sample_pos, heightFraction, mip, erosion_level, sunPixelHelper);

        //improved analytical scattering: frostbite clouds
        float2 integScatt = ( luminance - luminance * beers_term );//analytical integral for beers law. Scattering term is always (cloudDensity*sigma), and integral is divided by (cloudDensity*sigma), so it is just not needed
        //const float3 integScatt = ( luminance * -cloudDensity * sigmaDs);//simple integral

        integratedScatteringTransmittance.rg = integratedScatteringTransmittance.z * integScatt + integratedScatteringTransmittance.rg;
        //integratedScatteringTransmittance.rgb = float(i)/STEPS_PER_SEQUENCE;integratedScatteringTransmittance.a = 0;break;
        integratedScatteringTransmittance.z *= transmittance;
        if (integratedScatteringTransmittance.z<threshold)//early exit if we already get all light
        {
          //re-apply last sample - hides banding
          //but costs 0.05ms on XB1
          #if !_HARDWARE_XBOX && !_HARDWARE_PS4
          integratedScatteringTransmittance.rg = integratedScatteringTransmittance.z * integScatt + integratedScatteringTransmittance.rg;
          integratedScatteringTransmittance.z *= transmittance;
          #endif
          break;
        }
      }
      //integratedScatteringTransmittance = float(count)/e;
      //integratedScatteringTransmittance.z = 0;
    }
    half3 decodeScatteringColor(float2 integratedScattering, float3 worldPos)
    {
      half3 sun_light, amb_color;
      get_sun_sky_light(worldPos, sun_light, amb_color);
      return integratedScattering.x*sun_light + amb_color*integratedScattering.y;
    }

    struct CLOUDS_RET
    {
      half4 target0;
      float dist;
    };
    #include "daCloudsTonemap.hlsl"
    #include <pixelPacking/yCoCgSpace.hlsl>
    CLOUDS_RET get_clouds_ret(float4 integratedScatteringTransmittance, float dist, float3 additional_lighting)
    {
      //integratedScatteringTransmittance.rgb/=max(1e-6, 1-integratedScatteringTransmittance.a);
      //integratedScatteringTransmittance.rgb *= 1./TAA_BRIGHTNESS_SCALE;
      integratedScatteringTransmittance.rgb += additional_lighting;
      #if ALREADY_TONEMAPPED_SCENE && RENDER_TO_TAA_SPACE
        integratedScatteringTransmittance.rgb = PackToYCoCg(integratedScatteringTransmittance.rgb);
        #if TAA_IN_HDR_SPACE
          integratedScatteringTransmittance.rgb *= simple_luma_tonemap(integratedScatteringTransmittance.x, TONEMAPPED_SCENE_EXPOSURE);
        #endif
        #if ALREADY_TONEMAPPED_SCENE == CLOUDS_TONEMAPPED_TO_SRGB
          integratedScatteringTransmittance.x *= 0.5;//todo: should be 1/exposure
          integratedScatteringTransmittance.gb = integratedScatteringTransmittance.gb*0.5+0.5;
        #endif
      #endif
      CLOUDS_RET result;
      result.target0.rgb = integratedScatteringTransmittance.rgb;
      result.target0.a = 1-integratedScatteringTransmittance.a;
      FLATTEN
      if (result.target0.a >= 1-CLOUDS_TRANSMITTANCE_THRESHOLD)
      {
        result.target0.rgb /= result.target0.a;
        result.target0.a = 1;
      }
      result.dist = dist/TRACE_DIST;
      return result;
    }

    float get_rounded_dist(float start, float stepSize, float clouds_offset)
    {
      float ofs = frac(-frac((clouds_offset) * (1./stepSize)));
      return (floor(start*(1./stepSize))+ofs)*stepSize;
    }

    void get_offseted_dist(out float dist, inout float start, float randomOfs, float stepSize, float clouds_offset, float maxRandom, int stepsPerSequence)
    {
      dist = get_rounded_dist(start,  stepSize, clouds_offset);
      start = dist+stepSize*(float(stepsPerSequence));
      dist -= randomOfs*stepSize;
      //dist -= randomOfs*min(stepSize, maxRandom);
    }

    int get_steps(inout float nextStart, float cStep, float nextStepSize, int stepsPerSequence)
    {
      int e = stepsPerSequence;
      float stepMult = nextStepSize/cStep;
      float dif = (get_rounded_dist(nextStart, nextStepSize, clouds_offset) - nextStart)/cStep;
      FLATTEN
      if (dif>=0.0 && dif <= stepMult-1.0);
      {
        e += int(dif)+1;
        nextStart += nextStepSize;
      }
      return e;
    }

    void get_close_fog(float2 scattering_tc, float3 v, float d, out float3 ext, out float3 insc)
    {
      float tcZ = get_scattering_tc_z(d);
      float4 combined = tex3Dlod(skies_frustum_scattering, float4(scattering_tc, tcZ, 0));
      insc.rgb = combined.rgb;
      float3 colored_transmittance = get_fog_prepared_tc(long_get_prepared_scattering_tc(v .y, d, preparedScatteringDistToTc));
      ext = color_scatter_loss(combined, colored_transmittance);
    }
    void get_inf_fog(float2 scattering_tc, float3 v, float d, out float3 ext, out float3 insc)
    {
      float tcZ = get_scattering_tc_long_z(d);
      float4 combined = tex3Dlod(skies_frustum_scattering, float4(scattering_tc, tcZ, 0));
      insc.rgb = combined.rgb;
      float3 colored_transmittance = get_fog_prepared_tc(long_get_prepared_scattering_tc(v .y, d, preparedScatteringDistToTc));
      ext = color_scatter_loss(combined, colored_transmittance);
    }

    float randFast( uint2 pixelPos, float Magic = 3571.0 )
    {
      float2 random2 = ( 1.0 / 4320.0 ) * pixelPos + float2( 0.25, 0.0 );
      float random = frac( dot( random2 * random2, Magic ) );
      random = frac( random * random * (2 * Magic) );
      return random;
    }
    #include <interleavedGradientNoise.hlsl>
    static const float blue_noise_jitter[4*4] =//better make it texture
    {
      0.000000,0.500000,0.125000,0.625000,
      0.750000,0.250000,0.875000,0.375000,
      0.187500,0.687500,0.062500,0.562500,
      0.937500,0.437500,0.812500,0.312500
    };

    CLOUDS_RET trace_clouds(float3 viewVect, float2 texcoord, uint2 screenpos, float2 scatteringTc)
    {
      #ifndef STEPS_PER_SEQUENCE
        #if TEMPORAL_REPROJECTION
          #if CLOUDS_FULLRES
            #define STEPS_PER_SEQUENCE 64 // fullres clouds can utilize more steps, since it's not blurred as much
          #else
            #define STEPS_PER_SEQUENCE 32
          #endif
        #elif JUST_CLOSE_SEQUENCE
        #define STEPS_PER_SEQUENCE closeSequenceSteps
        #else
        #define STEPS_PER_SEQUENCE 64
        #endif
      #endif
      int stepsPerSequence = STEPS_PER_SEQUENCE;
      #if CAN_BE_IN_CLOUDS && JUST_CLOSE_SEQUENCE
        const int SEQUENCE_COUNT = 1;
        stepsPerSequence = steps_per_sequence;
        const float startStepSize = closeSequenceStepSize*(32./stepsPerSequence);
      #elif DUAL_PANORAMA
        const int SEQUENCE_COUNT = 4;
        const float startStepSize = 256;
      #elif CAN_BE_IN_CLOUDS && !TEMPORAL_REPROJECTION
        const int SEQUENCE_COUNT = 4;
        const float startStepSize = 512;//cube or reflection
      #elif CAN_BE_IN_CLOUDS && TEMPORAL_REPROJECTION
        const int SEQUENCE_COUNT = 5;
        stepsPerSequence = steps_per_sequence;
        const float startStepSize = 256*(32./stepsPerSequence);
      #elif !CAN_BE_IN_CLOUDS && TEMPORAL_REPROJECTION
        const int SEQUENCE_COUNT = 3;
        const float startStepSize = 256;
      #else
        const int SEQUENCE_COUNT = 4;
        const float startStepSize = 128;
      #endif
      const float actualTraceDist = (((1U<<SEQUENCE_COUNT)-1)*stepsPerSequence + (1U<<SEQUENCE_COUNT))*startStepSize;
      float stepSize = startStepSize;

      //float2 texcoord = screenpos.xy*clouds_rt_params.zw;
      float viewLenSq = dot(viewVect, viewVect);
      float invViewLen = rsqrt(viewLenSq);
      float viewLen = rcp(invViewLen);
      float3 view   = viewVect*invViewLen;

      float distanceToClouds0, distanceToClouds1;
      distance_to_clouds(-view, distanceToClouds0, distanceToClouds1);

      distanceToClouds1 *= 1000;
      distanceToClouds0 *= 1000;
      float start = distanceToClouds0, end = min(actualTraceDist, distanceToClouds1);

      BRANCH
      if (view.y<0)
        end = min(distance_to_planet(view, INFINITE_TRACE_DIST), end);

      BRANCH
      if (close_layer_should_early_exit())
        return get_clouds_ret(float4(0,0,0,1), end, 0);

      float distToGround = INFINITE_TRACE_DIST;
      #if !INFINITE_SKIES
        if (!clouds_infinite_skies)
        {
          float rawDepth = tex2Dlod(clouds_depth_gbuf, float4(texcoord,0,0)).x;
          float depth = linearize_z(rawDepth, zn_zfar.zw);
          #if CAN_BE_IN_CLOUDS && JUST_CLOSE_SEQUENCE
          FLATTEN
          if (depth < 40-0.5 && start == 0)//40 is copy-paste from daCloudsApply pre-shader
            rawDepth = 0;
          #endif
          distToGround = rawDepth == 0 ? INFINITE_TRACE_DIST : depth*viewLen;
        }
      #endif


      float closeSequenceEnd = closeSequenceStepSize*closeSequenceSteps;
      float infiniteEnd = end;//probably better use distanceToClouds1, to avoid gbuffer interference
      end = min(end, distToGround);
      #if CAN_BE_IN_CLOUDS && JUST_CLOSE_SEQUENCE
      end = min(closeSequenceEnd, end);
      //stepSize = (end-start)/stepsPerSequence;
      #endif
      //start = 0.0;
      //end = 12000;
      //todo: use tile info or previous frame info to get min distance to cloud in tile

      closest_tiled_dist_clamp(start, screenpos.xy);

      BRANCH
      if (end<=start || start<0)
        return get_clouds_ret(float4(0,0,0,1), infiniteEnd , 0);
      SunLightingPixelHelper sunPixelHelper = getSunHelper(view);

      float dist = 0;
      float3 viewStep = view*stepSize;

      #if TEMPORAL_REPROJECTION
        uint frameOver = TAA_CLOUDS_FRAMES;//with 16 results are slightly better, but we need to store "newFrame weight" in taa, to sample it from history, so we adjust weight accordingly (increase new frame weight, where pixel was offscreen in previous frame, not current one)
        float randomOfs = ((uint(current_frame_info.x) + uint(screenpos.x)*2789 + uint(screenpos.y)*2791)&(frameOver-1))/float(frameOver);
        //randomOfs += float((uint(screenpos.x)*5741 + uint(screenpos.y)*5743)%4)*(0.99/(4.0*float(frameOver)));
      #elif DUAL_PANORAMA
        float randomOfs = randFast(uint2(screenpos.xy));
        //randomOfs = randomOfs*0.25 + ((uint(current_frame_info.x)+uint(screenpos.x) + uint(screenpos.y))&3)/4.0;
        //randomOfs = randomOfs*0.25 + ((uint(current_frame_info.x)+uint(screenpos.x) + uint(screenpos.y))&3)/4.0;
        //randomOfs = interleavedGradientNoiseFramed(screenpos.xy, current_frame_info.x%4);
        uint frameOver = PANORAMA_TEMPORAL_SAMPLES;//todo: make this setting
        //randomOfs = ((uint(current_frame_info.x) + uint(screenpos.x)*2789 + uint(screenpos.y)*2791)%frameOver)/float(frameOver);
        randomOfs = ((current_frame_info.x%frameOver) + blue_noise_jitter[(uint(screenpos.x)&3) + 4*(uint(screenpos.y)&3)].x)/frameOver;
        //randomOfs = (current_frame_info.x%frameOver)/frameOver;// + blue_noise_jitter[(uint(screenpos.x)&3) + 4*(uint(screenpos.y)&3)]/frameOver;
        //randomOfs = randFast(screenpos.xy+uint2(uint(current_frame_info.x)&1,(uint(current_frame_info.x)>>1)&1));
        //randomOfs = current_frame_info.x/frameOver;
        //randomOfs = randFast(screenpos.xy+uint2(uint(current_frame_info.x)&1,(uint(current_frame_info.x)>>1)&1));
      #else
        float randomOfs = 0;
      #endif

      // Contains integrated scattered luminance (in rgb ) and trasmittance (in a) along a ray .
      float weightedDist = 0, totalWeight = 0;
      float3 integratedScatteringColor = 0; float integratedTransmittance = 1.0;
      float3 additionalLighting = 0;
      float3 integratedScatteringTransmittanceEncoded = float3(0,0,1);
      float2 distMulAdd = float2(0,1);
      #define GET_FOG get_close_fog

      #if CLOUDS_JUST_ONE_SEQUENCE
        //int count = viewVect.y > 0.1 ? 128 : 196;
        int count = lerp(trace_steps.x, trace_steps.y, sqrt(saturate(viewVect.y)));
        //int count = 256;
        //#if DUAL_PANORAMA
        //  count = lerp(128, 64, (current_frame_info.x%frameOver)/frameOver);
        //#endif
        //int count = min(256, (end-start)/256);
        //start += 128*randomOfs;randomOfs =0;
        stepSize = max(64., (end-start)/count);
        start -= (stepSize)*randomOfs;
        dist = start; start = 0;
        randomOfs = 0;

        /*count = 32;
        stepSize = 32.0;
        randomOfs = 0;
        end = min(end, count*stepSize);
        dist = get_rounded_dist(start, stepSize, clouds_offset);
        if (dist < 0)
          dist += stepSize;
        //get_offseted_dist(dist, start, randomOfs, stepSize, clouds_offset, 64*4);
        start = dist;
        e = (end-start)/stepSize;*/
        #if WEIGHTED_ATMOSPHERE_SCATTERING == WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE
          #define PERFORM_SEQUENCE(st, en) {\
            float weightedSequenceDist = 0, totalSequenceWeight = 0;\
            float3 integratedScatteringTransmittance2 = float3(0,0,1);\
            float3 additionalLighting2 = 0;\
            performSequence(st, en, view, stepSize,end,sunPixelHelper, CLOUDS_TRANSMITTANCE_THRESHOLD/integratedTransmittance,\
                            weightedSequenceDist, totalSequenceWeight, integratedScatteringTransmittance2, dist, additionalLighting2, float2(0,1), 1);\
            float seqAvgDist = weightedSequenceDist/max(1e-9, totalSequenceWeight);\
            float3 decodedScatteringColor = decodeScatteringColor(integratedScatteringTransmittance2.xy, skies_world_view_pos + view*seqAvgDist);\
            if (totalSequenceWeight > 1e-9 && integratedScatteringTransmittance2.z<1)\
            {\
              half3 extinction, inscatter;\
              GET_FOG(scatteringTc, view, seqAvgDist, extinction, inscatter);\
              decodedScatteringColor.rgb = extinction*decodedScatteringColor.rgb + inscatter*(1-integratedScatteringTransmittance2.z); \
            }\
            integratedScatteringColor.rgb += integratedTransmittance*decodedScatteringColor.rgb;\
            additionalLighting.rgb += integratedTransmittance*additionalLighting2;\
            integratedTransmittance *= integratedScatteringTransmittance2.z;\
            weightedDist += weightedSequenceDist; totalWeight += totalSequenceWeight;\
          }
        #else
          #define PERFORM_SEQUENCE(st, en)\
            performSequence(st, en, view, stepSize,end,sunPixelHelper, CLOUDS_TRANSMITTANCE_THRESHOLD,\
                            weightedDist, totalWeight, integratedScatteringTransmittanceEncoded, dist, additionalLighting2, float2(0,1), 1);\
            integratedTransmittance = integratedScatteringTransmittanceEncoded.z;
        #endif

        int e = ceil((end-dist)/stepSize);
        #if WEIGHTED_ATMOSPHERE_SCATTERING == WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE
          e = ceil((end-dist)*0.5/stepSize);//half dist
          PERFORM_SEQUENCE(0, e);
          e = ceil((end-dist)/stepSize);
          PERFORM_SEQUENCE(0, e);
        #else
          PERFORM_SEQUENCE(0, e);
        #endif
      #else
        #if WEIGHTED_ATMOSPHERE_SCATTERING == WEIGHTED_ATMOSPHERE_SCATTERING_SEQUENCE
          #define PERFORM_SEQUENCE(seqNo, mulS) \
            get_offseted_dist(dist, start, randomOfs, stepSize, clouds_offset, 64*4, stepsPerSequence);\
            float weightedSequenceDist = 0, totalSequenceWeight = 0;\
            float3 integratedScatteringTransmittance2 = float3(0,0,1);\
            float3 additionalLighting2 = 0;\
            int e = get_steps(start, stepSize, stepSize*mulS, stepsPerSequence);\
            float erosionLevel = seqNo < 3 ? 1 : 0.5*saturate(3 + (-1./60000)*dist);\
            performSequence(distStart, e, view, stepSize,end,sunPixelHelper, CLOUDS_TRANSMITTANCE_THRESHOLD/integratedTransmittance,\
                            weightedSequenceDist, totalSequenceWeight, integratedScatteringTransmittance2, dist, additionalLighting2, distMulAdd, erosionLevel);\
            float seqAvgDist = weightedSequenceDist/max(1e-9, totalSequenceWeight);\
            float3 decodedScatteringColor = decodeScatteringColor(integratedScatteringTransmittance2.xy, skies_world_view_pos + view*seqAvgDist);\
            if (totalSequenceWeight > 1e-9 && integratedScatteringTransmittance2.z<1)\
            {\
              half3 extinction, inscatter;\
              GET_FOG(scatteringTc, view, seqAvgDist, extinction, inscatter);\
              decodedScatteringColor.rgb = extinction*decodedScatteringColor.rgb + inscatter*(1-integratedScatteringTransmittance2.z); \
            }\
            integratedScatteringColor.rgb += integratedTransmittance*decodedScatteringColor.rgb;\
            additionalLighting.rgb += integratedTransmittance*additionalLighting2;\
            integratedTransmittance *= integratedScatteringTransmittance2.z;\
            weightedDist += weightedSequenceDist; totalWeight += totalSequenceWeight;\
            stepSize=stepSize*mulS;
        #else
          #define PERFORM_SEQUENCE(seqNo, mulS)\
            get_offseted_dist(dist, start, randomOfs, stepSize, clouds_offset, 64*4, stepsPerSequence);\
            int e = get_steps(start, stepSize, stepSize*mulS, stepsPerSequence);\
            float erosionLevel = seqNo < 3 ? 1 : 0.5*saturate(3 + (-1./60000)*dist);\
            float3 additionalLighting2 = 0;\
            performSequence(distStart, e, view, stepSize,end,sunPixelHelper, CLOUDS_TRANSMITTANCE_THRESHOLD,\
                            weightedDist, totalWeight, integratedScatteringTransmittanceEncoded, dist, additionalLighting2, distMulAdd, erosionLevel, first_slice_disappear);\
            additionalLighting.rgb += integratedTransmittance*additionalLighting2;\
            integratedTransmittance = integratedScatteringTransmittanceEncoded.z;\
            stepSize=stepSize*mulS;
        #endif

        float distStart = 0;
        bool first_slice_disappear = false;
        #if CAN_BE_IN_CLOUDS && TEMPORAL_REPROJECTION
          float opacityDist = 3*closeSequenceStepSize;
          distStart = clouds_has_close_sequence ? closeSequenceEnd-closeSequenceStepSize - opacityDist : 0;// + 64*64;//two sequences
          distStart = max(distStart, start);
          start = 0;
          distMulAdd = float2(1./opacityDist, -distStart/opacityDist);
          //distMulAdd = clouds_has_close_sequence ? distMulAdd : float2(0, 1);
          //cross fade
        #elif CAN_BE_IN_CLOUDS && JUST_CLOSE_SEQUENCE
          float opacityDist = 2.*closeSequenceStepSize;
          distMulAdd = float2(-1./opacityDist, (end-closeSequenceStepSize)/opacityDist);
          first_slice_disappear = true;
        #endif
        #if DUAL_PANORAMA
          stepSize = max(8., (end-start)/1024);
        #else
        #endif
        PERFORM_SEQUENCE(0, 2.0)
        distMulAdd = float2(0,1);
        first_slice_disappear = false;
        //integratedScatteringTransmittance = float4(0,0,0,1);weightedDist = 0, totalWeight = 0;
        BRANCH
        if (SEQUENCE_COUNT >= 2 && integratedTransmittance >= CLOUDS_TRANSMITTANCE_THRESHOLD && dist<=end)
        {
          PERFORM_SEQUENCE(1, (SEQUENCE_COUNT == 3 ? 4 : 2))

          BRANCH
          if (SEQUENCE_COUNT >=3 && integratedTransmittance >= CLOUDS_TRANSMITTANCE_THRESHOLD && dist<=end)
          {
            #undef GET_FOG
            #define GET_FOG get_inf_fog
            PERFORM_SEQUENCE(2, (SEQUENCE_COUNT == 4 ? 4 : 2))

            BRANCH
            if (SEQUENCE_COUNT >=4 && integratedTransmittance >= CLOUDS_TRANSMITTANCE_THRESHOLD && dist<=end)
            {
              PERFORM_SEQUENCE(3, 2)
              BRANCH
              if (SEQUENCE_COUNT >=5 && integratedTransmittance >= CLOUDS_TRANSMITTANCE_THRESHOLD && dist<=end)
              {
                PERFORM_SEQUENCE(4, 2)
                BRANCH
                if (SEQUENCE_COUNT >=6 && integratedTransmittance >= CLOUDS_TRANSMITTANCE_THRESHOLD && dist<=end)
                {
                  PERFORM_SEQUENCE(5, 2)
                }
              }
            }
          }
        }
      #endif
      float averageDist = totalWeight>1e-9 ? weightedDist/totalWeight : infiniteEnd;
      #if WEIGHTED_ATMOSPHERE_SCATTERING == WEIGHTED_ATMOSPHERE_SCATTERING_ONCE
      integratedScatteringColor = decodeScatteringColor(integratedScatteringTransmittanceEncoded.xy, skies_world_view_pos + view*averageDist);
      BRANCH
      if (integratedTransmittance<1)
      {
        float3 extinction, inscatter;
        float useDist = totalWeight>1e-9 ? averageDist : 0.5*(start+end);
        GET_FOG(scatteringTc, view, useDist, extinction, inscatter);
        integratedScatteringColor.rgb = extinction*integratedScatteringColor.rgb + inscatter*(1-integratedTransmittance);
      }
      #endif
      #define BLEND_OUT 1
      #if BLEND_OUT
      //const float lastStepSize = (1U<<(SEQUENCE_COUNT-1))*startStepSize;
      const float blendDistEnd = (((1U<<SEQUENCE_COUNT)-1)*stepsPerSequence)*startStepSize;
      const float blendDistStart = blendDistEnd*0.95;
      float blendOut = saturate(1-(averageDist-blendDistStart)/(blendDistEnd-blendDistStart));
      integratedScatteringColor *= blendOut;
      integratedTransmittance = 1-blendOut*(1-integratedTransmittance);
      #endif

      return get_clouds_ret(float4(integratedScatteringColor, integratedTransmittance), averageDist, additionalLighting);
    }
  }
endmacro

shader clouds2_temporal_ps, clouds2_close_temporal_ps, clouds2_direct
{
  cull_mode=none;
  z_write=false;
  if (shader == clouds2_direct)
  {
    blend_src = one;
    blend_dst = isa;
    USE_SPECIAL_VISION()
    SKY_HDR()
  }

  hlsl {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      float2 tc : TEXCOORD0;
      float3 viewVect : TEXCOORD1;
    };
  }

  USE_POSTFX_VERTEX_POSITIONS()
  USE_AND_INIT_VIEW_VEC(vs)
  RAYCAST_CLOUDS(ps)
  ENABLE_ASSERT(ps)

  hlsl(vs) {
    VsOutput clouds_vs(uint vertexId : SV_VertexID)
    {
      VsOutput output;
      float2 pos = getPostfxVertexPositionById(vertexId);
      output.pos = float4(pos.xy, 1, 1);
      #if INFINITE_SKIES
      output.pos.z = 0;
      #endif
      output.tc = screen_to_texcoords(pos);
      output.viewVect = get_view_vec_by_vertex_id(vertexId);
      return output;
    }
  }

  hlsl(ps) {
    struct PS_CLOUDS_RET
    {
      half4 target0            : SV_Target0;
      #if HAS_DEPTH_TARGET
      float target1            : SV_Target1;
      #endif
    };
    PS_CLOUDS_RET clouds_ps(VsOutput input HW_USE_SCREEN_POS)
    {
      float4 screenpos = GET_SCREEN_POS(input.pos);
      float2 texcoord = input.tc;//fixme: remove me in panoram

      //pass from vertex shader, it is faster
      float3 viewVect = input.viewVect;
      //float3 viewVect = view_vecLT + (view_vecRT_minus_view_vecLT)*texcoord.x + (view_vecLB_minus_view_vecLT)*texcoord.y;
      CLOUDS_RET tr = trace_clouds(viewVect, texcoord, uint2(screenpos.xy), texcoord);
      ##if shader == clouds2_direct
      applySpecialVision(tr.target0);
      tr.target0.rgb = pack_hdr(tr.target0.rgb);
      ##endif
      PS_CLOUDS_RET ret;
      ret.target0 = tr.target0;
      #if HAS_DEPTH_TARGET
        ret.target1 = tr.dist;
      #endif
      return ret;
    }
  }

  compile("target_vs", "clouds_vs");
  compile("target_ps", "clouds_ps");
}

float4 clouds2_resolution;
float4 clouds2_dispatch_groups;

shader clouds2_temporal_cs, clouds2_close_temporal_cs//, clouds2_direct_cs
{
  RAYCAST_CLOUDS(cs)
  VIEW_VEC_OPTIMIZED(cs)

  if (shader == clouds2_close_temporal_cs)
  {
    (cs) { invres@f4 = (1./clouds2_resolution.z, 1./clouds2_resolution.w, 0.5/clouds2_resolution.z, 0.5/clouds2_resolution.w); }
  } else
  {
    (cs) { invres@f4 = (1./clouds2_resolution.x, 1./clouds2_resolution.y, 0.5/clouds2_resolution.x, 0.5/clouds2_resolution.y); }
  }

  hlsl(cs) {
    RWTexture2D<float4> target0: register(u0);
    RWTexture2D<float> target1: register(u1);
    //#include <L2_cache_friendly_dispatch.hlsl>

    [numthreads(CLOUD_TRACE_WARP_X, CLOUD_TRACE_WARP_Y, 1)]
    //void cs_main(uint2 dtid : SV_DispatchThreadID)
    void cs_main(uint2 dtid_ : SV_DispatchThreadID, uint2 gid_ : SV_GroupID, uint3 tid_ : SV_GroupThreadID)
    {
      uint2 dtid = dtid_;
      //target0[dtid] = flattenedGroupIdOrigin/float(dispatchGridDim.x*dispatchGridDim.y);
      float2 texcoord = dtid*invres.xy + invres.zw;
      float3 viewVect = getViewVecOptimized(texcoord);
      CLOUDS_RET tr = trace_clouds(viewVect, texcoord, dtid, texcoord);

      target0[dtid] = tr.target0;
      #if HAS_DEPTH_TARGET
      target1[dtid] = tr.dist;
      #endif
    }
  }
  compile("cs_5_0", "cs_main");
}

texture sky_panorama_tex;
include "use_strata_clouds.sh"
float4 clouds_panorama_subpixel;
float4 clouds_panorama_temp_res;
float4 clouds_panorama_tex_res;
float clouds_panorama_blend;

shader clouds_panorama, clouds_alpha_panorama
{
  cull_mode=none;
  z_write=false;
  z_test=false;
  ATMO(ps)
  GET_ATMO(ps)
  if (shader == clouds_panorama)
  {
    USE_SKIES_SUN_COLOR(ps)
    (ps) { skies_transmittance_texture@smp2d = skies_transmittance_texture; }
    (ps) {
      sky_panorama_tex@smp2d = sky_panorama_tex;
      skies_froxels_resolution@f4 = skies_froxels_resolution;
    }
  }

  if (clouds_panorama_split != off)
  {
    //keep it compiled only where it is usefull
    if ((shader != clouds_panorama) || (clouds_panorama_depth_out == on) || (!hardware.vulkan))
    {
      dont_render;
    }
  }

  if (clouds_panorama_split != trace)
  {
    blend_src = sa;
    blend_dst = isa;
  }

  hlsl {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      float2 tc : TEXCOORD0;
    };
  }

  USE_POSTFX_VERTEX_POSITIONS()
  (vs) { tc_pos_ofs@f4 = panoramaTC; }
  (ps) { tc_pos_ofs@f4 = panoramaTC; skies_panorama_mu_horizon@f1 = (skies_panorama_mu_horizon);}
  (ps) { clouds_panorama_blend_weight@f1 = (clouds_panorama_blend,0,0,0); }

  RAYCAST_CLOUDS(ps)
  hlsl(ps) {
    #define USE_STRATA_LOD(a) 0
  }
  USE_STRATA_CLOUDS(ps)
  if (shader == clouds_panorama && use_postfx == off)
  {
    FULL_TONEMAP_LUT_APPLY(ps)
  }

  if (clouds_panorama_split == blend && shader == clouds_panorama)
  {
    USE_SUBPASS_LOADS()
    hlsl(ps)
    {
      SUBPASS_RESOURCE(subpassTrace0, 0, 0); // subpass_read_bind_offset
    }
  }

  hlsl(vs) {
    VsOutput clouds_vs(uint vertexId : SV_VertexID)
    {
      VsOutput output;
      float2 pos = getPostfxVertexPositionById(vertexId);
      output.pos = float4(pos.xy, 0, 1);
      output.tc = screen_to_texcoords(pos);
      if (tc_pos_ofs.z != 0)
        output.tc = output.tc * tc_pos_ofs.zw + tc_pos_ofs.xy;
      return output;
    }
  }

  hlsl(ps) {
    struct PS_CLOUDS_RET
    {
      half4 target0            : SV_Target0;
    ##if shader != clouds_alpha_panorama && clouds_panorama_depth_out == on
      half4 target1            : SV_Target1;
    ##endif
    };

    PS_CLOUDS_RET clouds_ps(VsOutput input HW_USE_SCREEN_POS)
    {
      float4 screenpos = GET_SCREEN_POS(input.pos);
      int2 screenposi = int2(screenpos.xy);
      float2 texcoord = input.tc;
      ##if shader != clouds_alpha_panorama
        //texcoord += clouds_panorama_subpixel_offset.xy;
        //screenposi = int2(clouds_panorama_subpixel.zw)*screenposi.xy + int2(clouds_panorama_subpixel.xy);
        //float2 jitPos = 0.5*float2(((uint(current_frame_info.x)&1)-0.5)/clouds_panorama_tex_res.x, (((uint(current_frame_info.x)>>1)&1)-0.5)/clouds_panorama_tex_res.y);
        //if (uint(current_frame_info.x) >= 4)
        //  jitPos = 0.7*float2(jitPos.x*sin(45*PI/180) + jitPos.y*sin(45*PI/180), -jitPos.x*cos(45*PI/180) + jitPos.y*sin(45*PI/180));
        //texcoord += jitPos;
      ##endif

      if (int(screenpos.y) <= 1 && tc_pos_ofs.z != 0)
        texcoord = 0;
      GENERATE_PANORAMA_VIEWVECT(texcoord)
      GENERATE_PANORAMA_PATCH_VIEWVECT(texcoord)
      if (tc_pos_ofs.z == 0)
      {
        viewVect = patchView;
      }
      ##if shader != clouds_alpha_panorama

        float2 panoramaTc = texcoord;
        if (tc_pos_ofs.z == 0)
          panoramaTc = float2(atan2( viewVect.x, viewVect.z) * (0.5/PI)+0.5, PANORAMA_TC_FROM_VIEW(viewVect.y));
        float2 scatteringTc = panoramaTc;//we render scattering specially for panorama. Better distribution, knowing that not much is needed lower than horizon
        //get_panoramic_scattering_tc(viewVect);
        #if !MOBILE_DEVICE
          float radius = (((uint(current_frame_info.x)%(PANORAMA_TEMPORAL_SAMPLES+1))>>2)+0.5)/((PANORAMA_TEMPORAL_SAMPLES)>>2);
          //blur scattering a bit
          scatteringTc += radius*float2(((uint(current_frame_info.x)&1)-0.5), (((uint(current_frame_info.x)>>1)&1)-0.5))/skies_froxels_resolution.xy;
        #endif
      ##else
        float2 scatteringTc = 0;
      ##endif
      //for panorama in particular, it makes WAY more sense to use same panoramic representation (less detailed when looking down)
      //todo: optimize allocation!

      ##if (clouds_panorama_split == blend) && (shader == clouds_panorama)
        CLOUDS_RET tr;
        tr.target0 = SUBPASS_LOAD(subpassTrace0, texcoord);
        //not used as for now, implement on demand
        tr.dist = 0;//SUBPASS_LOAD(subpassTrace1, texcoord);
      ##else
        CLOUDS_RET tr = trace_clouds(viewVect, texcoord, screenposi, scatteringTc);
      ##endif

      PS_CLOUDS_RET ret;


      ##if (clouds_panorama_split == trace) && (shader == clouds_panorama)
        ret.target0 = tr.target0;
        return ret;
      ##endif

      ##if shader == clouds_alpha_panorama
        tr.target0.a = tr.target0.a;
        ret.target0 = (1 - tr.target0.a)*(1-get_strata_clouds(viewVect, 0).a);
        ret.target0.a = clouds_panorama_blend_weight ? clouds_panorama_blend_weight : 0.1;
      ##else
        //if (tr.target0.a<1)
        half3 sky = 0;
        //BRANCH
        //if (tr.target0.a < 1)
        {
          sky = tex2Dlod(sky_panorama_tex, float4(panoramaTc,0,0)).rgb;
          float nu = dot(viewVect, real_skies_sun_light_dir.xzy);
          Length r = skies_world_view_pos.y/1000+theAtmosphere.bottom_radius;
          if (abs(r - theAtmosphere.top_radius)<0.01)
            r = theAtmosphere.top_radius+0.01;
          BRANCH
          if (visibleSun(nu) && !RayIntersectsGround(theAtmosphere, r, viewVect.y) && real_skies_sun_color.r>0)
          {
            DimensionlessSpectrum sun_transmittance = GetTransmittanceToTopAtmosphereBoundary(
                theAtmosphere,
                SamplerTexture2DFromName(skies_transmittance_texture),
                r, viewVect.y);
            if (sun_transmittance.x > 0 )
              sky += calcSunColor(nu, sun_transmittance, real_skies_sun_color.rgb);
          }
          half4 strata = get_strata_clouds(viewVect, scatteringTc);
          sky.rgb = lerp(sky.rgb, strata.rgb, strata.a);
          //sky = strata.rgb*strata.a;
          tr.target0.rgb = tr.target0.rgb + (1-tr.target0.a)*sky;
          //tr.target0.a = tr.target0.a*(1-strata.a);
        }

        ret.target0 = tr.target0;
        ret.target0.a = clouds_panorama_blend_weight ? clouds_panorama_blend_weight :
          (tr.target0.a > 0 ? lerp(0.15, 0.12, tr.target0.a) : 0.15);
##if clouds_panorama_depth_out == on
        ret.target1 = tr.dist;
        ret.target1.a = current_frame_info.y;
##endif
##if use_postfx == off
  //with PBR we apply tonemap at panorama apply
  //otherwise exposure will be applied wrongly
  #if !PBR_FORWARD_SHADING
        ret.target0.rgb = performLUTTonemap(ret.target0.rgb);
  #endif
##endif
        //ret.target0.a *= 0.5;
        //ret.target0.rgb*=ret.target0.a;
      ##endif
      return ret;
    }
  }

  compile("target_vs", "clouds_vs");
  compile("target_ps", "clouds_ps");
}

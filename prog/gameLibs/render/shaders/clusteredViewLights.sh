include "tile_lighting.sh"
include "punctualLights.sh"
include "clustered/lights_cb.sh"
include "dynamic_lights_count.sh"

macro INIT_CLUSTERED_VIEW_LIGHTS(code)
  INIT_PHOTOMETRY_TEXTURES(code)
  INIT_CLUSTERED_LIGHTS(code)
  INIT_OMNI_LIGHTS_CB(code)
  INIT_SPOT_LIGHTS_CB(code)
  INIT_LIGHT_SHADOWS(code)
  INIT_COMMON_LIGHTS_SHADOWS_CB(code)
  INIT_LIGHTS_CLUSTERED_CB(code)
endmacro

macro USE_CLUSTERED_VIEW_LIGHTS(code)
  hlsl(code) {
    #ifndef DYNAMIC_LIGHTS_SPECULAR
      #define DYNAMIC_LIGHTS_SPECULAR 1
    #endif
  }
  if (dynamic_lights_count != lights_off)
  {
    hlsl(code) {
      #define LAMBERT_LIGHT 1
      #define DYNAMIC_LIGHTS_EARLY_EXIT 1
      #ifndef OMNI_SHADOWS
      #define OMNI_SHADOWS 1
      #endif
    }
    USE_PHOTOMETRY_TEXTURES(code)
    USE_CLUSTERED_LIGHTS(code)
    USE_OMNI_LIGHTS_CB(code)
    USE_LIGHT_SHADOWS(code)
    USE_COMMON_LIGHTS_SHADOWS_CB(code)
    USE_LIGHTS_CLUSTERED_CB(code)
  }
  hlsl(code) {
    #include "pbr/pbr.hlsl"
    #include "clustered/punctualLights.hlsl"
    half3 get_dynamic_lighting(ProcessedGbuffer gbuffer, float3 worldPos, float3 view, float w, float2 screenpos, float NoV, float3 specularColor, float2 tc, half enviAO)
    {
      half3 result = 0;
      ##if (dynamic_lights_count != lights_off)
        half dynamicLightsSpecularStrength = gbuffer.extracted_albedo_ao;
        //BRANCH
        //if (all( abs(lights_box_center_count.xyz-worldPos.xyz) < lights_box_extent))
        {
          #if OMNI_CONTACT_SHADOWS && defined(shadow_frame)
          float3 contactStartCameraToPoint = view*(w*-0.9999+0.01);
          float dither = interleavedGradientNoiseFramed(screenpos, shadow_frame);//if we have temporal aa
          #define OMNI_CONTACT_SHADOWS_CALC \
            BRANCH\
            if (color_and_specular.w > 0 && max(omniLight.r, omniLight.g)>0.01)\
            {\
              float2 hitUV;\
              float contactShadow = contactShadowRayCast(downsampled_far_depth_tex, downsampled_far_depth_tex_samplerstate,
                contactStartCameraToPoint, normalize(pos_and_radius.xyz-worldPos.xyz),\
                w*0.1, 8, dither-0.5, projectionMatrix, w, viewProjectionMatrixNoOfs, hitUV, float2(3,2));\
              omniLight *= contactShadow;\
            }
          #else
           #define OMNI_CONTACT_SHADOWS_CALC
          #endif
          half3 dynamicLighting = 0;
          uint sliceId = min(getSliceAtDepth(w, depthSliceScale, depthSliceBias), CLUSTERS_D);
          uint clusterIndex = getClusterIndex(tc.xy, sliceId);
          uint wordsPerOmni = omniLightsWordCount;
          uint wordsPerSpot = spotLightsWordCount;
          ##if dynamic_lights_count == lights_omnispot_1
            wordsPerSpot = 1;
            wordsPerOmni = 1;
          ##endif
          ##if dynamic_lights_count == lights_omni_1
            wordsPerOmni = 1;
            wordsPerSpot = 0;
          ##endif
          ##if dynamic_lights_count == lights_spot_1
            wordsPerOmni = 0;
            wordsPerSpot = 1;
          ##endif
          // Read range of words of visibility bits
          uint omniAddress = clusterIndex*wordsPerOmni;
          for ( uint omniWordIndex = 0; omniWordIndex < wordsPerOmni; omniWordIndex++ )
          {
            // Load bit mask data per lane
            uint mask = flatBitArray[omniAddress + omniWordIndex];
            uint mergedMask = MERGE_MASK( mask );
            while ( mergedMask != 0 ) // processed per lane
            {
              uint bitIndex = firstbitlow( mergedMask );
              mergedMask ^= ( 1U << bitIndex );
              uint omni_light_index = ((omniWordIndex<<5) + bitIndex);
              #if defined(CHECK_OMNI_LIGHT_MASK)
              if ( !check_omni_light(omni_light_index))
                continue;
              #endif
              RenderOmniLight ol = omni_lights_cb[omni_light_index];
              float4 pos_and_radius = ol.posRadius;
              float4 color_and_specular = getFinalColor(ol, worldPos);
              #if OMNI_SHADOWS
                float4 shadowTcToAtlas = getOmniLightShadowData(omni_light_index);
              #else
                float4 shadowTcToAtlas = float4(0, 0, 0, 0);
              #endif
              half3 omniLight = perform_point_light(worldPos.xyz, view, NoV, gbuffer, specularColor, dynamicLightsSpecularStrength, gbuffer.ao, pos_and_radius, color_and_specular, shadowTcToAtlas, screenpos);//use gbuffer.specularColor for equality with point_lights.sh

              OMNI_CONTACT_SHADOWS_CALC

              dynamicLighting += omniLight;
            }
          }
          uint spotAddress = clusterIndex*wordsPerSpot + ((CLUSTERS_D+1)*CLUSTERS_H*CLUSTERS_W*wordsPerOmni);
          for ( uint spotWordIndex = 0; spotWordIndex < wordsPerSpot; spotWordIndex++ )
          {
            // Load bit mask data per lane
            uint mask = flatBitArray[spotAddress + spotWordIndex];
            uint mergedMask = MERGE_MASK( mask );
            while ( mergedMask != 0 ) // processed per lane
            {
              uint bitIndex = firstbitlow( mergedMask );
              mergedMask ^= ( 1U << bitIndex );
              uint spot_light_index = ((spotWordIndex<<5) + bitIndex);
              #if defined(CHECK_SPOT_LIGHT_MASK)
              if ( !check_spot_light(spot_light_index))
                continue;
              #endif

              RenderSpotLight sl = spot_lights_cb[spot_light_index];
              float4 lightPosRadius = sl.lightPosRadius;
              float4 lightColor = sl.lightColorAngleScale;
              lightColor.w = abs(lightColor.w);
              float4 lightDirection = sl.lightDirectionAngleOffset;
              float2 texId_scale = sl.texId_scale.xy;

              #define EXIT_STATEMENT continue
              #ifndef SPOT_SHADOWS
              #define SPOT_SHADOWS 1
              #endif
              #include "clustered/oneSpotLight.hlsl"
              dynamicLighting += lightBRDF;
            }
          }
          //dynamicLighting += ((clusterGrid[clusterIndex].counts>>8)&0xFF)/8.0;
          half pointLightsFinalAO = (enviAO*0.5+0.5);//we use ssao, since we use it in point_lights.sh (works slow, but not much lights are there)
          result += dynamicLighting*pointLightsFinalAO;
        }
      ##endif
      return result;
    }
  }
endmacro

macro INIT_AND_USE_CLUSTERED_VIEW_LIGHTS(code)
  INIT_CLUSTERED_VIEW_LIGHTS(code)
  USE_CLUSTERED_VIEW_LIGHTS(code)
endmacro

include "pbr.sh"
include "sun_disk_specular.sh"
macro INIT_SKY_GROUND_COLOR()
INIT_ENVI_SPECULAR()
INIT_SKY_UP_DIFFUSE()
(ps)
{
    sun_light_color@f3 = sun_light_color;
    to_sun_direction@f3 = (-from_sun_direction.x, -from_sun_direction.y, -from_sun_direction.z, 0.0) //ground
}
endmacro

macro GET_SKY_GROUND_COLOR()
  hlsl(ps) {
    #define INV_MIN_IOR 100
  }
  USE_ROUGH_TO_MIP()
  STANDARD_BRDF_SHADING()
  USE_SKY_UP_DIFFUSE()
  USE_SKY_SPECULAR()
  USE_SUN_DISK_SPECULAR()
  hlsl(ps) {
    #define HAVE_GROUND_COLOR_FUNCTION 1
    #define PreparedGroundData float
    void prepare_ground_data(float3 v, float distToGround, out PreparedGroundData data) {data = distToGround;}

    float3 get_ground_lit_color(float3 x_, float3 s_, float3 v, float3 sunColor, PreparedGroundData data)
    {
      //return float3(0.1,0.2,0.3);
      float3 view = v.xzy;
      float3 normal = normalize(x_);
      float NdotV = abs(dot(view, normal.xzy));
      float NoV = NdotV+1e-5;
      float linearRoughness = 1-(0.71+0.28*0.5);
      float specularColor = 0.02;

      float3 halfDir = normalize(view+to_sun_direction);
      float NoH = saturate( halfDir.y );
      float VoH = saturate( dot(view, halfDir) );
      
      float D,G;
      float3 F;
      sunDiskSpecular( 0.02, NoV, linearRoughness*linearRoughness, to_sun_direction, view, normal.xzy, D, G, F );
      G = 1;
      float fresnelLight = F.x;
      //D = BRDF_distribution( roughness, NoH );
      //fresnelLight = fresnelSchlick(0.02, VoH).x;
      float NoL = dot(normal, s_);
      float satNoL = saturate(NoL);
      half absNoL = satNoL;//abs(NoL);//absNoL = max(0, to_sun_direction.y);
      half sunSpec = D*G*absNoL;
    
      float maxSpec = 6.0;
      sunSpec = min(sunSpec*fresnelLight, maxSpec);
      half3 land_lit_color = sun_light_color*sunSpec;

      float3 reflectDir = reflect(view, normal.xzy);//float3(-view.x,view.y,-view.z);
      float3 reflectSampleDir = reflectDir;
      reflectSampleDir.y = abs(reflectSampleDir.y);//this hack is preventing reflection below horizon
      //float3 roughReflection = getRoughReflectionVec(reflectSampleDir, float3(0,1,0), envi_roughness);
      float3 roughReflection = reflectSampleDir.xyz;
      land_lit_color += getSkyReflection(linearRoughness, roughReflection, NoV, 0.02)*saturate(1-data/400);
      return land_lit_color;

      //half3 land_lit_color = standardBRDF(NoV, max(0, to_sun_direction.y), diffuseColor.rgb, roughness, linearRoughness, specularColor, -from_sun_direction, -view, half3(0,1,0))*sun_color_0;
      //half3 land_lit_color = standardBRDF(NoV, max(0, to_sun_direction.y), diffuseColor.rgb, roughness, linearRoughness, specularColor, -from_sun_direction, -view, half3(0,1,0))*sun_color_0;
      //half3 environmentAmbientUnoccludedLighting = diffuseColor.rgb * enviUp;
      //land_lit_color += environmentAmbientUnoccludedLighting;

      //return (max(s.y, 0)/PI)* sunColor * float3(0.15,0.2, 0.05);
    }
  }
endmacro

macro INIT_SKY_GROUND_COLOR2()
endmacro

macro GET_SKY_GROUND_COLOR2()
  hlsl(ps) {
    void get_ground_gbuffer(float3 view, out float linearRoughness, out float3 diffuseColor, out float specularColor)
    {
      float planeLevel = (world_view_pos.y-average_ground_level)
      float distToPlane = planeLevel/view.y;
      float3 worldPlanePos = -view*(distToPlane)+world_view_pos;//distance to plane
      half4 clipmapLast = h4tex2D(last_clip_tex, worldPos.xz*world_to_earth_tex.xy+world_to_earth_tex.zw);
      half landAmount = clipmapLast.a;
      //half specularStr = get_specular_intensity_from_land_color(clipmapLast.rgb);//should be in alpha of texture
      //half roughness = 1-get_specular_intensity_from_land_color(clipmapLast.rgb);
      linearRoughness = lerp(0.15, 1, landAmount);
      //half roughness = 1;
      specularColor = lerp(0.02, 0.01, landAmount);//fixme: as in gbuffer.sh!
      diffuseColor = lerp(sky_water_refraction_lit_color.rgb, clipmapLast.rgb, landAmount);
    }

    half3 ground_lit_color(float3 view, float linearRoughness, float3 diffuseColor, float specularColor)
    {
      float NdotV = abs(view.y);
      float NoV = NdotV+1e-5;

      half3 land_lit_color = standardBRDF(NoV, max(0, -from_sun_direction.y), diffuseColor.rgb, linearRoughness*linearRoughness, linearRoughness, specularColor, -from_sun_direction, -view, half3(0,1,0))*sun_color_0;
      half3 environmentAmbientUnoccludedLighting = diffuseColor.rgb * enviUp;
      land_lit_color += environmentAmbientUnoccludedLighting;

      float3 reflectSampleDir = reflectDir;
      reflectSampleDir.y = abs(reflectSampleDir.y);//this hack is preventing reflection below horizon
      //float3 roughReflection = getRoughReflectionVec(reflectSampleDir, float3(0,1,0), envi_roughness);
      float3 roughReflection = reflectSampleDir.xyz;
      land_lit_color += getSkyReflection(envi_roughness, roughReflection, NoV, specularColor);
      return land_lit_color;
    }
  }
endmacro
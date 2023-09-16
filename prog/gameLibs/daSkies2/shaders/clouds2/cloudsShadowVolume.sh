include "clouds_weather.sh"

texture clouds_shadows_volume;
macro INIT_CLOUDS_SHADOWS_VOLUME(code)
  (code) {
    clouds_shadows_volume@smp3d = clouds_shadows_volume;
  }
endmacro
macro USE_CLOUDS_SHADOWS_VOLUME(code)
  hlsl(code) {
    float3 getCloudsShadows3dTC(float3 worldOffsetedPos, float alt_in_clouds)//worldOffsetedPos = worldPos + cloudsOrigin
    {
      float2 tcXZ = worldOffsetedPos.xz*INV_WEATHER_SIZE + 0.5f;
      //tcXZ = clamp(tcXZ, 0.5/CLOUD_SHADOWS_VOLUME_RES_XZ, 1 - 0.5/CLOUD_SHADOWS_VOLUME_RES_XZ);
      return float3(tcXZ, alt_in_clouds);
    }
    float2 getCloudsShadows3d(float3 tc)
    {
      //that is not entirely correct on earlier octaves due to filtering. because (0.5(a+b))^c != 0.5(a^c+b^c). But this is way faster and less memory...
      //we can probably consider storing also FIRST octave separately (i.e 11,11,10 32 bit format), and incorrectly filter only less important octaves (i.e. 2th or 2th/3rd).
      //the difference is primarily on silver-lining (it becomes a bit 'bigger')
      //additionally any other ways to enhance quality (i.e. cascades or making couple of steps first) also helps with that issue
      return tex3Dlod(clouds_shadows_volume, float4(tc, 0)).xy;
    }
  }
endmacro

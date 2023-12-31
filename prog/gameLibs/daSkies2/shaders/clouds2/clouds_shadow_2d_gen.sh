include "sky_shader_global.sh"
include "writeToTex.sh"
include "cloudsShadowVolume.sh"
include "cloudsLighting.sh"


shader build_shadows_2d_ps
{
  WRITE_TO_TEX2D_TC()
  (ps) {INV_WEATHER_SIZE@f1= (1/clouds_weather_size,0,0,0);}
  INIT_CLOUDS_SHADOWS_VOLUME(ps)
  USE_CLOUDS_SHADOWS_VOLUME(ps)
  CLOUDS_MULTIPLE_SCATTERING(ps)

  hlsl(ps) {
    float oneShadow(float2 tc)
    {
      float lastOctave = getCloudsShadows3d(float3(tc,0)).x;
      float_octaves allOctaves = getMSExtinction(lastOctave);
      return dot(clouds_ms_contribution4 . octaves_attributes, allOctaves)*4;//remove phase function
    }
    half ps_main(VsOutput input HW_USE_SCREEN_POS): SV_Target0
    {
      //return oneShadow(input.texcoord);
      #if METERS_BLUR
      //float meters = 64;//meters
      //float3 ofs = float3(meters,-meters, 0)*INV_WEATHER_SIZE;
      return (oneShadow(input.texcoord)*4 +
             oneShadow(input.texcoord + ofs.yy)+
             oneShadow(input.texcoord + ofs.xy)+
             oneShadow(input.texcoord + ofs.yx)+
             oneShadow(input.texcoord + ofs.xx)+
             oneShadow(input.texcoord + ofs.yz)*2+
             oneShadow(input.texcoord + ofs.xz)*2+
             oneShadow(input.texcoord + ofs.zx)*2+
             oneShadow(input.texcoord + ofs.zy)*2)
             /(4*2 + 4 +4)
             ;
      #endif
      float3 dim;
      clouds_shadows_volume.GetDimensions(dim.x, dim.y, dim.z);
      float3 ofs = float3(0.5/dim.x,-0.5/dim.x, 0);
      return (
             oneShadow(input.texcoord + ofs.yy)+
             oneShadow(input.texcoord + ofs.xy)+
             oneShadow(input.texcoord + ofs.yx)+
             oneShadow(input.texcoord + ofs.xx)
             )*0.25;
    }
  }
  compile("target_ps", "ps_main");
}
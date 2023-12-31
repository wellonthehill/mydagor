include "shader_global.sh"

// tweak
float flare_scale = 0.2;
float flare_bias = -5;
float flare_halo = 0.2;
float flare_halo_space_mul = 1;
float flare_ghosts = 0.5;
float flare_ghosts_space_mul = 1;

float uDispersal = 0.27;
float uHaloWidth = 0.8;
float uDistortion = 5;
float uHaloDistortion = 3;
float flare_ghosts_curvature = 0.6;

float flares_threshold = 0;

texture flareLenseRadial;

shader flare_downsample
{
  supports global_frame;

  cull_mode=none;
  z_write=false;

  dynamic texture flareSrc;
  dynamic float4 texelOffset;

  (vs) { texelOffset@f4 = texelOffset; }

  (ps) {
    flareSrc@smp2d = flareSrc;
    flareScaleBias@f4 = (flare_scale, flare_bias, 0.0, 0.0);
  }

  hlsl {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      float4 texcoord01      : TEXCOORD0;
      };
  }
  USE_POSTFX_VERTEX_POSITIONS()

  hlsl(vs) {

    VsOutput flare_downsample_vs(uint vertex_id : SV_VertexID)
    {
      VsOutput output;
      float2 pos = getPostfxVertexPositionById(vertex_id);
      output.pos = float4(pos.x, pos.y, 0, 1);
      float2 texcoord = pos*RT_SCALE_HALF+texelOffset.xy;

      output.texcoord01.xy = texcoord;
      output.texcoord01.zw = float2(0., 0.);
      return output;
    }
  }

  hlsl(ps) {
    half4 flare_downsample_ps(VsOutput IN): SV_Target
    {
      half4 flareVal = tex2Dlod(flareSrc, float4(IN.texcoord01.xy, 0, 0));
      half lum = max(0.0001f, luminance(flareVal.rgb));    // From Chevrolet.

      return (flareVal.rgb * (saturate((lum+flareScaleBias.y)*rcp(lum))*flareScaleBias.x)).rgbg;
    }
  }

  compile("target_vs", "flare_downsample_vs");
  compile("target_ps", "flare_downsample_ps");
}

shader flare_feature
{
  supports global_frame;

  cull_mode=none;
  z_write=false;

  dynamic texture flareSrc;
  dynamic float4 texelOffset;

  (vs) {
    texelOffset@f4 = texelOffset;
    aspect_ratio_mul_add@f4 = (-texelOffset.w/texelOffset.z,-1, .5 + 0.5*texelOffset.w/texelOffset.z, 1.);//width/height == (1/(1/width)/height = (1/height)/(1/width)
  }

  (ps) {
    flareSrc@smp2d = flareSrc;
    flareLenseRadial@smp2d = flareLenseRadial;
    flareHaloGhostsCurvature@f4 = (flare_halo * flare_halo_space_mul, flare_ghosts * flare_ghosts_space_mul, flare_ghosts_curvature, flares_threshold);
    uDispersal_Halo@f3 = (uDispersal, uDispersal*0.5, uHaloWidth, 0);
    distortion@f3 = (-texelOffset.z * uDistortion, 0.0, texelOffset.z * uDistortion, 0);
    halo_distortion@f3 = (-texelOffset.z * uHaloDistortion, 0.0, texelOffset.z * uHaloDistortion, 0);
  }

  hlsl {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      float2 texcoord        : TEXCOORD0;
      float2 halotexcoord    : TEXCOORD1;
      };
  }
  USE_POSTFX_VERTEX_POSITIONS()

  hlsl(vs) {

    VsOutput flare_feature_vs(uint vertex_id : SV_VertexID)
    {
      VsOutput output;
      float2 pos = getPostfxVertexPositionById(vertex_id);
      output.pos = float4(pos.x, pos.y, 0, 1);
      float2 texcoord = pos*RT_SCALE_HALF+texelOffset.xy;
      output.texcoord = -texcoord.xy + float2(1,1);//flip and offset with aspect ratio
      output.halotexcoord = texcoord.xy*aspect_ratio_mul_add.xy + aspect_ratio_mul_add.zw;//flip and offset with aspect ratio


      return output;
    }
  }

  hlsl(ps) {
    half3 chromaTex2D ( float2 texcoord, float3 scale )
    {
        // note: can assume scale = scale.g for cheaper version of the effect
        half3 color;
        color.r = h4tex2D ( flareSrc, ( texcoord*scale.r - (0.5 *scale.r - 0.5) ) ).r;
        color.g = h4tex2D ( flareSrc, ( texcoord*scale.g - (0.5 *scale.g - 0.5) ) ).g;
        color.b = h4tex2D ( flareSrc, ( texcoord*scale.b - (0.5 *scale.b - 0.5) ) ).b;
        return color;
    }

    float2 Abuse ( float2 uv )
    {
        float2 nuv = uv * 2 - 1;
        float  len_n = length(nuv) * rsqrt(2.0);
        float  len_x = pow ( len_n, flareHaloGhostsCurvature.z ) * sqrt(2.0);//pow (, 0.5
        float2 nuvNorm = dot(nuv, nuv) == 0 ? float2(0, 0) : normalize(nuv);
        float2 xnuv = nuvNorm * len_x;
        return xnuv * 0.5 + 0.5;
    }

    half3 textureDistorted(float2 texcoord, float2 direction, float3 distortion)
    {
        half3 color;
        texcoord = Abuse(texcoord);
        color.r = h4tex2D ( flareSrc, texcoord + direction * distortion.r ).r;
        color.g = h4tex2D ( flareSrc, texcoord + direction * distortion.g ).g;
        color.b = h4tex2D ( flareSrc, texcoord + direction * distortion.b ).b;

        color = saturate(color - flareHaloGhostsCurvature.www); //flares_threshold

        return color;
    }
    half3 haloTextureDistorted(float2 texcoord, float2 direction, float3 distortion)
    {
        half3 color;
        color.r = h4tex2D ( flareSrc, texcoord + direction * distortion.r ).r;
        color.g = h4tex2D ( flareSrc, texcoord + direction * distortion.g ).g;
        color.b = h4tex2D ( flareSrc, texcoord + direction * distortion.b ).b;

        color = saturate(color - flareHaloGhostsCurvature.www); //flares_threshold

        return color;
    }

    half4 flare_feature_ps(VsOutput IN): SV_Target
    {
        float2 texcoord = IN.texcoord.xy;

        float2 ghostVec = uDispersal_Halo.yy - texcoord * uDispersal_Halo.xx;
        float2 normalizedGhostVec = dot(ghostVec, ghostVec) == 0 ? float2(0, 0) : normalize(ghostVec);

        // sample ghosts:
        half3 result = 0;
        UNROLL
        for (int i = 0; i < 8; ++i) {
                float2 offset = frac(texcoord + ghostVec * float(i));

                float weight = length(0.5 - offset) * rsqrt(0.5);
                weight = pow(saturate(1.0 - weight), 10);
                half3 ghost = textureDistorted(
                        offset,
                        normalizedGhostVec,
                        distortion);
                result += ghost * weight;
        }

        // center-based 1D color lookup
        float radius = length(texcoord - 0.5);
        ##if flareLenseRadial != NULL
        half3 lookup = tex2D(flareLenseRadial, float2(radius*sqrt(2.f),0)).rgb;
        half3 ghosts = lookup*result;
        ##else
        half3 ghosts = result;
        ##endif




//      sample halo:
        float2 haloGhostVec = 0.5 - IN.halotexcoord;
        float2 normalizedHaloVec = dot(haloGhostVec, haloGhostVec) == 0 ? float2(0, 0) : normalize(haloGhostVec);
        float2 haloVec = normalizedHaloVec * uDispersal_Halo.z;
        float weight = length(float2(0.5,0.5) - frac(IN.halotexcoord + haloVec)) * rsqrt(0.5);
        weight = pow8(saturate(1.0 - weight));
        half3 halo = haloTextureDistorted(
                (IN.halotexcoord + haloVec),
                normalizedHaloVec,
                halo_distortion
        ) * weight;

        return half4(flareHaloGhostsCurvature.x*halo + flareHaloGhostsCurvature.y*ghosts,1);
    }
  }

  compile("target_vs", "flare_feature_vs");
  compile("target_ps", "flare_feature_ps");
}

shader flare_blur
{
  supports global_frame;

  cull_mode=none;
  z_write=false;

  dynamic texture flareSrc;
  dynamic float4 texelOffset;

  dynamic float4 duv1duv2;
  dynamic float4 duv3duv4;

  (vs) { texelOffset@f4 = texelOffset; }
  (ps) {
    flareSrc@smp2d = flareSrc;
    duv1duv2@f4 = duv1duv2;
    duv3duv4@f4 = duv3duv4;
  }

  hlsl {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      float2 texcoord        : TEXCOORD0;
      };
  }
  USE_POSTFX_VERTEX_POSITIONS()

  hlsl(vs) {

    VsOutput flare_blur_vs(uint vertex_id : SV_VertexID)
    {
      VsOutput output;
      float2 pos = getPostfxVertexPositionById(vertex_id);
      output.pos = float4(pos.x, pos.y, 0, 1);
      output.texcoord = pos*RT_SCALE_HALF+texelOffset.xy;
      return output;
    }
  }

  hlsl(ps) {
    half4 flare_blur_ps(VsOutput IN): SV_Target
    {
        float2 texcoord = IN.texcoord;
        half  WeightC = 5.0;
        half4 Weight = half4(4.0,3.0,2.0,1.0);
        half4 color = h4tex2D (flareSrc, texcoord) * WeightC;
        color += tex2D(flareSrc, texcoord + duv1duv2.xy) * Weight[0];
        color += tex2D(flareSrc, texcoord - duv1duv2.xy) * Weight[0];
        color += tex2D(flareSrc, texcoord + duv1duv2.zw) * Weight[1];
        color += tex2D(flareSrc, texcoord - duv1duv2.zw) * Weight[1];
        color += tex2D(flareSrc, texcoord + duv3duv4.xy) * Weight[2];
        color += tex2D(flareSrc, texcoord - duv3duv4.xy) * Weight[2];
        color += tex2D(flareSrc, texcoord + duv3duv4.zw) * Weight[3];
        color += tex2D(flareSrc, texcoord - duv3duv4.zw) * Weight[3];
        return color / ( WeightC + 2*Weight[0] + 2*Weight[1] + 2*Weight[2] * 2*Weight[3] );
    }
  }

  compile("target_vs", "flare_blur_vs");
  compile("target_ps", "flare_blur_ps");
}

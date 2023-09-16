include "shader_global.sh"

float4 mip_target_size;

int prev_mip_tex_register_const_no = 4 always_referenced;

macro GAUSSIAN_MIP_CORE(code)
  hlsl(code) {
    Texture2D prev_mip_tex: register(t4);
    SamplerState prev_mip_tex_samplerstate: register(s4);
  }

  (code) { mip_target_size@f4 = mip_target_size; }

  hlsl(code)
  {
    #define CENTER_WEIGHT 0.13f
    #define SIDE_WEIGHT 0.115f
    #define CORNER_WEIGHT 0.102f
    #define OFFSET_SCALE 0.9f

    float4 gauss_mip(float2 texcoord00)
    {
      float4 finalColor=0;
      float weight=0;

      float2 tcOffset = OFFSET_SCALE * mip_target_size.zw;

      #define GET(a, b, w) finalColor += w * tex2Dlod(prev_mip_tex, float4(texcoord00 + float2(a, b) * tcOffset.xy, 0, 0)); weight += w;

      // center
      GET(0, 0, CENTER_WEIGHT)

      // side
      GET(1, 0, SIDE_WEIGHT)
      GET(-1, 0, SIDE_WEIGHT)
      GET(0, 1, SIDE_WEIGHT)
      GET(0, -1, SIDE_WEIGHT)

      // corner
      GET(1, 1, CORNER_WEIGHT)
      GET(1, -1, CORNER_WEIGHT)
      GET(-1, 1, CORNER_WEIGHT)
      GET(-1, -1, CORNER_WEIGHT)

      return finalColor/weight;
    }
  }
endmacro

shader gaussian_mipchain
{
  no_ablend;
  supports none;
  supports global_frame;

  cull_mode = none;
  z_write = false;
  z_test = false;

  POSTFX_VS_TEXCOORD(0, texcoord00)
  GAUSSIAN_MIP_CORE(ps)

  hlsl(ps)
  {
    half4 gauss_mip_ps(VsOutput input) : SV_Target
    {
      return gauss_mip(input.texcoord00.xy);
    }
  }
  compile("target_ps", "gauss_mip_ps");
}

shader gaussian_mipchain_cs
{
  GAUSSIAN_MIP_CORE(cs)

  hlsl(cs) {
    RWTexture2D<float4> mip_target : register(u0);
  }

  hlsl(cs)
  {
    [numthreads( 8, 8, 1 )]
    void gauss_mip_cs(uint3 DTid : SV_DispatchThreadID)
    {
      mip_target[DTid.xy] = gauss_mip(mip_target_size.zw * (DTid.xy + 0.5));
    }
  }
  compile("target_cs", "gauss_mip_cs");
}

shader bloom_filter_mipchain
{
  no_ablend;
  supports none;
  supports global_frame;

  hlsl(ps) {
    Texture2D prev_mip_tex: register(t4);
    SamplerState prev_mip_tex_samplerstate: register(s4);
  }

  cull_mode = none;
  z_write = false;
  z_test = false;

  POSTFX_VS_TEXCOORD(0, texcoord00)

  (ps) { mip_target_size@f4 = mip_target_size; }

  hlsl(ps)
  {
    #define OFFSET_SCALE 0.9f

    float GetLuminance(float3 v) {return dot(v, float3(0.212671, 0.715160, 0.072169));}
    float4 bloom_mip_ps(VsOutput input) : SV_Target
    {

      const bool bKillFireflies = true;
      #define THRESHOLD(a)
      #define addBlock(block) block+=tex

      float2 TexSize = OFFSET_SCALE * float2(mip_target_size.z, mip_target_size.w);;
      half3 blockTL = 0, blockTR = 0, blockBR = 0, blockBL = 0;
      half3 tex;
      float2 tc = input.texcoord00.xy;
      #define GET(a, b) tex = tex2D(prev_mip_tex, tc + float2(a, b) * TexSize).rgb; tex /= 1 + GetLuminance(tex);

      GET(-2,-2)
      addBlock(blockTL);
      GET(0,-2)
      addBlock(blockTL);addBlock(blockTR);
      GET(2,-2)
      addBlock(blockTR);
      GET(-2,0)
      addBlock(blockTL);addBlock(blockBL);
      GET(0,0)
      addBlock(blockTL);addBlock(blockTR);addBlock(blockBR);addBlock(blockBL);
      GET(2,0)
      addBlock(blockTR);addBlock(blockBR);
      GET(-2,2)
      addBlock(blockBL);
      GET(0,2)
      addBlock(blockBL);addBlock(blockBR);
      GET(2,2)
      addBlock(blockBR);
      half3 blockCC = 0;
      GET(-1,-1)
      addBlock(blockCC);
      GET(1,-1)
      addBlock(blockCC);
      GET(1,1)
      addBlock(blockCC);
      GET(-1,1)
      addBlock(blockCC);
      blockTL *= 0.25; blockTR *= 0.25; blockBR *= 0.25; blockBL *= 0.25; blockCC *= 0.25;
      blockTL /= (1 - GetLuminance(blockTL));
      blockTR /= (1 - GetLuminance(blockTR));
      blockBR /= (1 - GetLuminance(blockBR));
      blockBL /= (1 - GetLuminance(blockBL));
      blockCC /= (1 - GetLuminance(blockCC));
      float3 bloomColor = 0.5 * blockCC + 0.125 * (blockTL + blockTR + blockBR + blockBL);
      return half4(bloomColor, 1);
    }
  }
  compile("target_ps", "bloom_mip_ps");
}

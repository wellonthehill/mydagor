include "shader_global.sh"

shader openxr_screen_mask
{
  supports none;
  supports global_frame;

  cull_mode=none;

  hlsl {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
    };
  }

  channel float4 pos=pos;

  hlsl(vs) {
    struct VsInput
    {
      float4 pos : POSITION;
    };

    VsOutput mask_vs(VsInput v)
    {
      VsOutput o;
      o.pos = v.pos;
      return o;
    }
  }
  compile("target_vs", "mask_vs");

  hlsl(ps) {
    float4 mask_ps(VsOutput i) : SV_Target
    {
      return float4(0, 0, 0, 1);
    }
  }
  compile("target_ps", "mask_ps");
}
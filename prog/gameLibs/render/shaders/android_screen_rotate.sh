include "shader_global.sh"

int android_internal_backbuffer_binding_reg = 15;
int android_screen_rotation = 0;
interval android_screen_rotation: identity < 90, ccw90 < 180, ccw180 < 270, ccw270;

shader android_screen_rotate
{
  cull_mode=none;
  no_ablend;
  z_write=false;
  z_test=false;

  POSTFX_VS_TEXCOORD(0, tc)
  hlsl(ps) {
    Texture2D internal_backbuffer:register(t15); //android_internal_backbuffer_binding_reg
    SamplerState internal_backbuffer_samplerstate:register(s15);

    float4 main_ps(VsOutput IN HW_USE_SCREEN_POS) : SV_Target0
    {
      ##if android_screen_rotation == identity
        float2 tc = IN.tc.xy;
      ##elif android_screen_rotation == ccw90
        float2 tc = float2(IN.tc.y, -IN.tc.x);
      ##elif android_screen_rotation == ccw180
        float2 tc = float2(-IN.tc.x, -IN.tc.y);
      ##elif android_screen_rotation == ccw270
        float2 tc = float2(-IN.tc.y, IN.tc.x);
      ##endif

      return tex2D(internal_backbuffer, tc).rgba;
    }
  }

  compile("target_ps", "main_ps");
}

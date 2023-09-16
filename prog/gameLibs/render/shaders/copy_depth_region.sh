include "shader_global.sh"


shader copy_depth_region
{
  // setup constants
  supports global_frame;
  cull_mode = none;
  //z_write = true;
  //z_test = false;
  
  // init channels
  hlsl(vs) {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
    };
    VsOutput depth_copy_vs(uint vertexId : SV_VertexID)
    {
      VsOutput output;
      float2 inpos = float2((vertexId == 2) ? +3.0 : -1.0, (vertexId == 1) ? -3.0 : 1.0);
      VsOutput o;
      o.pos = float4(inpos, 0.5, 1);
      return o;
    }
  }
  compile("target_vs", "depth_copy_vs");
  
  hlsl(ps) {
    int2 from:register(c15);
    Texture2D depth_tex:register(t15);
    
    float depth_copy_ps(float4 pos:VPOS): SV_Depth
    { 
      return depth_tex[from+int2(pos.xy)].x;
    }
  }
  compile("target_ps", "depth_copy_ps");
}

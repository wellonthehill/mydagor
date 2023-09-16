include "heightmap_common.sh"
texture trees2d;
texture trees2d_depth;
float4 world_to_trees_tex_mul;
float4 world_to_trees_tex_ofs;

macro USE_TREES_ABOVE(code)
  (code) {
    trees2d_depth@smp2d = trees2d_depth;
    trees2d@smp2d = trees2d;
    world_to_trees_tex_ofs@f4 = world_to_trees_tex_ofs;
    world_to_trees_tex_mul@f4 = world_to_trees_tex_mul;
  }
  hlsl(code) {
    bool trees_world_pos_to_worldPos(float2 worldPosXZ, inout float3 worldPos, inout half3 color, bool precise_center)
    {
      float2 tc = worldPosXZ*world_to_trees_tex_mul.x + world_to_trees_tex_mul.yz;
      float2 abstc = abs(tc*2-1);
      if (any(abstc>=1))
        return false;
      if (precise_center)
      {
        tc = (floor(tc*world_to_trees_tex_mul.w)+0.5)/world_to_trees_tex_mul.w;//to get exactly center (not needed in albedo pass)
        worldPosXZ = (tc-world_to_trees_tex_mul.yz)/world_to_trees_tex_mul.x;
      }
      tc -= world_to_trees_tex_ofs.zw;
      float depth = tex2Dlod(trees2d_depth, float4(tc,0,0)).x;
      if (depth == 0)
        return false;
      worldPos = float3(worldPosXZ, depth*world_to_trees_tex_ofs.x + world_to_trees_tex_ofs.y).xzy;
      float h = getHeightLow(calcTcLow(worldPosXZ));
      if (decode_height(h) > worldPos.y - scene_voxels_size.y * 2.0)
        return false;
      color = tex2Dlod(trees2d, float4(tc,0,0)).rgb;
      return true;
    }
  }
endmacro
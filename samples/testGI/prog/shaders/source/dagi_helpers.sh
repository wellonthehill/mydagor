include "dagi_volmap_common_25d.sh"
texture scene_voxels_2d_heightmap;
float4 scene_voxels_2d_heightmap_area;
float4 scene_voxels_2d_heightmap_scale;

macro INIT_VOXELS_HEIGHTMAP_HELPERS(code)
  (code) {
    scene_voxels_2d_heightmap @smp2d = scene_voxels_2d_heightmap;
    scene_voxels_2d_heightmap_area@f4 = scene_voxels_2d_heightmap_area;
    scene_voxels_2d_heightmap_scale@f4 = scene_voxels_2d_heightmap_scale;
  }
  hlsl(code) {
    float ssgi_get_heightmap_2d_height(float3 worldPos)
    {
      return -10;
      float sampledHt = tex2Dlod(scene_voxels_2d_heightmap, float4(worldPos.xz*scene_voxels_2d_heightmap_area.x +scene_voxels_2d_heightmap_area.zw,0,0)).x;
      if (sampledHt == 0)
        sampledHt = 1;
      return scene_voxels_2d_heightmap_scale.y*sampledHt + scene_voxels_2d_heightmap_scale.x;
    }
  }
endmacro

macro SSGI_CLEAR_INITIAL_VOLMAP()
  hlsl(cs) {
    void ssgi_init_volmap(float3 worldPos, float3 lightVoxelSize, inout float3 col0, inout float3 col1, inout float3 col2, inout float3 col3, inout float3 col4, inout float3 col5, bool copied)
    {
      //col0 = col1 = col2 = col3 = col4 = col5 = saturate(worldPos/100);
    }
  }
endmacro

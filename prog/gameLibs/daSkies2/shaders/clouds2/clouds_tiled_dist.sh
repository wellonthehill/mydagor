float4 clouds_tiled_res;
texture clouds_tile_distance;

int clouds_use_fullres = 0;
interval clouds_use_fullres: no < 1, yes;

macro USE_CLOUDS_DISTANCE(code)
  (code) {
    clouds_tile_distance@smp2d = clouds_tile_distance;
  }
  hlsl(code) {
    #define CLOUDS_HAS_TILED_DIST 1
    float closest_tiled_dist_packed(uint2 scrPos)
    {
      return clouds_tile_distance[scrPos>>3].x;
    }
    float closest_tiled_dist(uint2 scrPos)
    {
      return INFINITE_TRACE_DIST*closest_tiled_dist_packed(scrPos);
    }
    void closest_tiled_dist_clamp(inout float start, uint2 scr)
    {
      start = max(start, closest_tiled_dist(scr));
    }

    bool tile_is_empty(uint2 scrPos)//for taa
    {
      return closest_tiled_dist_packed(scrPos) == 1;
    }
  }
endmacro

macro USE_CLOUDS_DISTANCE_STUB(code)
  hlsl(code) {
    #if !CLOUDS_HAS_TILED_DIST
    void closest_tiled_dist_clamp(float start, uint2 scr){}
    bool tile_is_empty(uint2 scrPos) { return false; }
    #endif
  }
endmacro

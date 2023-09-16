include "dafx_shaders.sh"
include "shader_global.sh"


texture dafx_fill_boundary_tex;
buffer dafx_frame_boundary_tmp;
texture dafx_frame_boundary_debug_tex always_referenced;

float4 dafx_fill_boundary_params;
int dafx_fill_boundary_offset;
int dafx_fill_boundary_count = 0;
int dafx_fill_boundary_frame_id = 0;

int dafx_use_experimental_boundary_calc = 0;
interval dafx_use_experimental_boundary_calc: no < 1, yes;


// horribly slow, only used for debugging ->> should be deprecated if there is no problem with the optimized version
shader fill_fx_keyframe_boundary_legacy
{
  (cs){
    dafx_fill_boundary_tex@tex2d = dafx_fill_boundary_tex;
    dafx_fill_boundary_params@f4 = dafx_fill_boundary_params;
    dafx_fill_boundary_offset@i1 = dafx_fill_boundary_offset;
    tile_size@f2 = (dafx_fill_boundary_params.z / dafx_fill_boundary_params.x, dafx_fill_boundary_params.w / dafx_fill_boundary_params.y);
    tile_size_inv@f2 = (dafx_fill_boundary_params.x / dafx_fill_boundary_params.z, dafx_fill_boundary_params.y / dafx_fill_boundary_params.w);
  }

  ENABLE_ASSERT(cs)

  hlsl(cs) {
    RWStructuredBuffer<float4> frame_boundary_result : register(u0);

    float4 transformInverseY(float4 boundary)
    {
      boundary.yw = 1 - boundary.wy;
      return boundary;
    }

    float4 calcBoundaryF(uint4 boundaryI)
    {
      // expand boundary by 1 texel, to make it inclusive
      boundaryI.xy = max(boundaryI.xy, 1u) - 1u;
      boundaryI.zw += 1;

      if (any(boundaryI.xy >= boundaryI.zw))
        return float4(0,0,1,1);

      return transformInverseY(saturate(float4(boundaryI.xy, boundaryI.zw) * tile_size_inv.xyxy));
    }

    [numthreads( 8, 8, 1 )]
    void main_cs( uint2 dtId : SV_DispatchThreadID )
    {
      uint2 frameRes = (uint2)dafx_fill_boundary_params.xy;
      if (any(dtId >= frameRes))
        return;

      float4 nullTexel = texelFetch(dafx_fill_boundary_tex, 0, 0); // assuming the corners are always null (transparent)

      const uint MAX_KEYFRAME_DIM = 4069u; // for safety
      uint2 keyframeDim = clamp((uint2)tile_size, 0u, MAX_KEYFRAME_DIM);
      uint4 boundary = uint4(MAX_KEYFRAME_DIM, MAX_KEYFRAME_DIM, 0, 0);
      uint2 offset = dtId * keyframeDim;
      for (uint y = 0; y < keyframeDim.y; ++y)
      for (uint x = 0; x < keyframeDim.x; ++x)
      {
        uint2 xy = uint2(x, y);
        if (any(nullTexel != texelFetch(dafx_fill_boundary_tex, offset + xy, 0)))
        {
          boundary.xy = min(boundary.xy, xy);
          boundary.zw = max(boundary.zw, xy);
        }
      }

      uint frameId = dtId.y * frameRes.x + dtId.x;
      structuredBufferAt(frame_boundary_result, dafx_fill_boundary_offset + frameId) = calcBoundaryF(boundary);
    }
  }
  compile("target_cs", "main_cs");
}



shader fill_fx_keyframe_boundary_opt_start
{
  ENABLE_ASSERT(cs)
  hlsl(cs) {
    RWStructuredBuffer<uint> dafx_frame_boundary_tmp : register(u0);

    [numthreads( 16, 4, 1 )]
    void main_cs( uint2 dtId : SV_DispatchThreadID )
    {
      if (dtId.x >= DAFX_FLIPBOOK_MAX_KEYFRAME_DIM*DAFX_FLIPBOOK_MAX_KEYFRAME_DIM)
        return;
      structuredBufferAt(dafx_frame_boundary_tmp, dtId.x*4 + dtId.y) = dtId.y < 2 ? 0xFFFFFFFF : 0;
    }
  }
  compile("target_cs", "main_cs");
}

shader fill_fx_keyframe_boundary_opt
{
  (cs){
    dafx_fill_boundary_tex@tex2d = dafx_fill_boundary_tex;
    dafx_fill_boundary_params@f4 = dafx_fill_boundary_params;
    tile_size@f2 = (dafx_fill_boundary_params.z / dafx_fill_boundary_params.x, dafx_fill_boundary_params.w / dafx_fill_boundary_params.y);
  }

  ENABLE_ASSERT(cs)

  hlsl(cs) {
    RWStructuredBuffer<uint> dafx_frame_boundary_tmp : register(u0);

    #define BOUNDARY_CACHE_SIZE 8

##if dafx_use_experimental_boundary_calc == yes
    groupshared uint tmp_boundary_cache[4];
##endif

    [numthreads( BOUNDARY_CACHE_SIZE, BOUNDARY_CACHE_SIZE, 1 )]
    void main_cs( uint2 dtId : SV_DispatchThreadID, uint2 tid : SV_GroupThreadID, uint2 gId : SV_GroupID )
    {
      uint2 texelId = dtId;
      uint2 texRes = (uint2)dafx_fill_boundary_params.zw;

      float4 nullTexel = texelFetch(dafx_fill_boundary_tex, 0, 0); // assuming the corners are always null (transparent)

      uint2 frameRes = (uint2)dafx_fill_boundary_params.xy;
      uint2 keyframeDim = (uint2)tile_size;
      uint2 frameId2d = texelId / keyframeDim;
      uint2 keyframeTexelId = texelId - keyframeDim * frameId2d;
      uint frameId = frameId2d.y * frameRes.x + frameId2d.x;

      bool isNotNull = false;
      if (all(texelId < texRes))
        isNotNull = any(nullTexel != texelFetch(dafx_fill_boundary_tex, texelId, 0));

##if dafx_use_experimental_boundary_calc == yes
      uint2 frameId2d_first = (gId * BOUNDARY_CACHE_SIZE + 0) / keyframeDim;
      uint2 frameId2d_last = (gId * BOUNDARY_CACHE_SIZE + BOUNDARY_CACHE_SIZE - 1) / keyframeDim;
      if (all(frameId2d_first == frameId2d_last)) // meaning all texels in the group are from the same tile
      {
        if (all(tid == 0))
        {
          tmp_boundary_cache[0] = 0xFFFFFFFF;
          tmp_boundary_cache[1] = 0xFFFFFFFF;
          tmp_boundary_cache[2] = 0;
          tmp_boundary_cache[3] = 0;
        }
        GroupMemoryBarrierWithGroupSync();
        if (isNotNull)
        {
          InterlockedMin(tmp_boundary_cache[0], keyframeTexelId.x);
          InterlockedMin(tmp_boundary_cache[1], keyframeTexelId.y);
          InterlockedMax(tmp_boundary_cache[2], keyframeTexelId.x);
          InterlockedMax(tmp_boundary_cache[3], keyframeTexelId.y);
        }
        GroupMemoryBarrierWithGroupSync();
        if (all(tid == 0))
        {
          InterlockedMin(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+0), tmp_boundary_cache[0]);
          InterlockedMin(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+1), tmp_boundary_cache[1]);
          InterlockedMax(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+2), tmp_boundary_cache[2]);
          InterlockedMax(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+3), tmp_boundary_cache[3]);
        }
      }
      else
##endif
      if (isNotNull)
      {
        InterlockedMin(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+0), keyframeTexelId.x);
        InterlockedMin(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+1), keyframeTexelId.y);
        InterlockedMax(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+2), keyframeTexelId.x);
        InterlockedMax(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+3), keyframeTexelId.y);
      }
    }
  }
  compile("target_cs", "main_cs");
}

shader fill_fx_keyframe_boundary_opt_end
{
  (cs){
    dafx_fill_boundary_params@f4 = dafx_fill_boundary_params;
    dafx_fill_boundary_offset@i1 = dafx_fill_boundary_offset;
    tile_size_inv@f2 = (dafx_fill_boundary_params.x / dafx_fill_boundary_params.z, dafx_fill_boundary_params.y / dafx_fill_boundary_params.w);
    dafx_frame_boundary_tmp@buf = dafx_frame_boundary_tmp hlsl { StructuredBuffer<uint> dafx_frame_boundary_tmp@buf; };
  }
  ENABLE_ASSERT(cs)
  hlsl(cs) {
    RWStructuredBuffer<float4> frame_boundary_result : register(u0);

    float4 transformInverseY(float4 boundary)
    {
      boundary.yw = 1 - boundary.wy;
      return boundary;
    }

    float4 calcBoundaryF(uint4 boundaryI)
    {
      // expand boundary by 1 texel, to make it inclusive
      boundaryI.xy = max(boundaryI.xy, 1u) - 1u;
      boundaryI.zw += 1;

      if (any(boundaryI.xy >= boundaryI.zw))
        return float4(0,0,1,1);

      return transformInverseY(saturate(float4(boundaryI.xy, boundaryI.zw) * tile_size_inv.xyxy));
    }

    [numthreads( 8, 8, 1 )]
    void main_cs( uint2 dtId : SV_DispatchThreadID )
    {
      uint2 frameRes = (uint2)dafx_fill_boundary_params.xy;
      if (any(dtId >= frameRes))
        return;

      uint frameId = dtId.y * frameRes.x + dtId.x;
      uint4 boundaryI = uint4(structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+0), structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+1), structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+2), structuredBufferAt(dafx_frame_boundary_tmp, frameId*4+3));
      structuredBufferAt(frame_boundary_result, dafx_fill_boundary_offset + frameId) = calcBoundaryF(boundaryI);
    }
  }
  compile("target_cs", "main_cs");
}


shader clear_fx_keyframe_boundary
{
  (cs){
    dafx_fill_boundary_count@i1 = dafx_fill_boundary_count;
  }
  ENABLE_ASSERT(cs)
  hlsl(cs) {
    RWStructuredBuffer<float4> frame_boundary_result : register(u0);

    [numthreads( 64, 1, 1 )]
    void main_cs( uint dtId : SV_DispatchThreadID )
    {
      if (dtId < dafx_fill_boundary_count)
        structuredBufferAt(frame_boundary_result, dtId) = float4(0,0,1,1);
    }
  }
  compile("target_cs", "main_cs");
}


shader frame_boundary_debug_update
{
  (cs){
    dafx_fill_boundary_tex@smp2d = dafx_fill_boundary_tex;
    dafx_fill_boundary_params@f4 = dafx_fill_boundary_params;
    dafx_fill_boundary_offset@i1 = dafx_fill_boundary_offset;
    dafx_fill_boundary_frame_id@i1 = dafx_fill_boundary_frame_id;
    tile_size@f2 = (dafx_fill_boundary_params.z / dafx_fill_boundary_params.x, dafx_fill_boundary_params.w / dafx_fill_boundary_params.y);
    tile_size_inv@f2 = (dafx_fill_boundary_params.x / dafx_fill_boundary_params.z, dafx_fill_boundary_params.y / dafx_fill_boundary_params.w);
    frames_inv@f2 = (1.0 / dafx_fill_boundary_params.x, 1.0 / dafx_fill_boundary_params.y, 0, 0);
    dafx_frame_boundary_buffer@buf = dafx_frame_boundary_buffer hlsl { StructuredBuffer<float4> dafx_frame_boundary_buffer@buf; };
  }
  ENABLE_ASSERT(cs)
  hlsl(cs) {

    RWTexture2D<float4> outputTex : register(u0);

    float4 getTextureResult(uint2 dtId)
    {
      if (any(dtId >= (uint2)tile_size))
        return 0;

      uint2 frameDim = (int2)dafx_fill_boundary_params.xy;
      uint total_frames = frameDim.x * frameDim.y;
      uint frame_id = (int)dafx_fill_boundary_frame_id % total_frames;

      float2 delta_ofs = float2( frame_id % frameDim.x, frame_id / frameDim.x) * frames_inv;
      float2 delta_tc = (dtId + 0.5) / tile_size;
      float2 tc = delta_ofs + delta_tc * frames_inv;
      float4 result = tex2Dlod(dafx_fill_boundary_tex, float4(tc, 0, 0));

      float4 frame_boundary = structuredBufferAt(dafx_frame_boundary_buffer, dafx_fill_boundary_offset + frame_id);
      frame_boundary.yw = 1 - frame_boundary.wy; // the inverse is stored for rendering, so we have to invert it back
      if (any(delta_tc < frame_boundary.xy || delta_tc > frame_boundary.zw))
        result = lerp(result, float4(1,0,1,1), 0.5);

      return result;
    }

    [numthreads( 8, 8, 1 )]
    void main_cs( uint2 dtId : SV_DispatchThreadID )
    {
      outputTex[dtId] = getTextureResult(dtId);
    }
  }
  compile("target_cs", "main_cs");
}



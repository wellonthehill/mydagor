include "sky_shader_global.sh"
include "viewVecVS.sh"
include "frustum.sh"
include "dagi_volmap_gi.sh"
include "dagi_scene_voxels_common.sh"
include "dagi_inline_raytrace.sh"
include "dagi_helpers.sh"
//include "gpu_occlusion.sh"
//include "sample_voxels.sh"
hlsl {
  #include "dagi_common_types.hlsli"
}

define_macro_if_not_defined INIT_VOXELS_HEIGHTMAP_HELPERS(code)
  hlsl(code) {
    float ssgi_get_heightmap_2d_height(float3 worldPos) {return worldPos.y-100;}
  }
endmacro

buffer frustum_visible_point_voxels;
buffer poissonSamples;

shader light_ss_ambient_voxels_cs
{
  SSGI_USE_VOLMAP_GI_COORD(cs)
  RAY_CAST_VOXELS_AND_INLINE_RT_INIT(cs)
  ENABLE_ASSERT(cs)
  hlsl(cs) {
    #define AVERAGE_CUBE_WARP_SIZE LIGHT_WARP_SIZE
    #include <parallel_average_cube.hlsl>
  }
  USE_CLOSEST_PLANES()
  (cs) {
    frustum_visible_ambient_voxels@buf = frustum_visible_point_voxels hlsl {
      #include "dagi_common_types.hlsli"
      StructuredBuffer<VisibleAmbientVoxelPoint> frustum_visible_ambient_voxels@buf;
    };
    poissonSamples@buf = poissonSamples hlsl {
      Buffer<float4> poissonSamples@buf;
    }
  }
  hlsl(cs) {
    #define __XBOX_REGALLOC_VGPR_LIMIT 16//found by pix
    #define __XBOX_ENABLE_LIFETIME_SHORTENING 1//found by pix
    RWStructuredBuffer<TraceResultAmbientVoxel> traceResults: register(u0);
    #define POISSON_USE_CB 1
    #include <fibonacci_sphere.hlsl>
    StructuredBuffer<AmbientVoxelsPlanes> visible_ambient_voxels_walls_planes: register(t14);
    #include <dagi_integrate_ambient_cube.hlsl>

    #define USE_POISSON 1

    [numthreads(AVERAGE_CUBE_WARP_SIZE, 1, 1)]
    void light_voxels_cs( uint gId : SV_GroupID, uint tid: SV_GroupIndex, uint dtId : SV_DispatchThreadID )//uint3 gId : SV_GroupId,
    {
      const uint NUM_RAYS = THREAD_PER_RAY;
      uint voxelNo = gId/NUM_RAY_GROUPS;
      uint rayGroup = gId%NUM_RAY_GROUPS;
      uint voxel = structuredBufferAt(frustum_visible_ambient_voxels, voxelNo).voxelId;
      uint tag = 0;
      uint3 coord = decode_voxel_coord_safe(voxel, tag);
      //float3 worldPosOfs = decode_voxel_world_posOfs(structuredBufferAt(visible_ambient_voxels, voxelNo).worldPosOfs);
      //float3 worldPos = ambientCoordToWorldPos(coord, cascade_id) + ssgi_ambient_volmap_crd_to_world0_xyz(cascade_id)*(worldPosOfs-0.5);
      float3 worldPos = ambientCoordToWorldPos(coord, cascade_id);

      float3 col0=0, col1=0, col2=0, col3=0, col4=0, col5=0;

      {
        //float2 E = hammersley(tid, NUM_RAYS, random);
        //float2 E = fibonacci_sphere(i, NUM_RAYS);//intentionally use fibonacci sequence with no random. Much faster (due to cache coherency) than randomized (hammersley/fibonacci)
        #if USE_POISSON
          float3 enviLightDir = poissonSamples[rayGroup*NUM_RAYS+tid].xyz;
          //float2 E = POISSON_SAMPLES[(tid + random.y%SAMPLE_NUM)%SAMPLE_NUM];
        #else
          //float2 E = hammersley((rayGroup*NUM_RAYS+tid)%SAMPLE_NUM, SAMPLE_NUM, 0);
          float2 E = fibonacci_sphere(rayGroup*NUM_RAYS+tid, SAMPLE_NUM);
          float3 enviLightDir = uniform_sample_sphere( E ).xyz;
        #endif
        float maxStartDist = min(getProbeDiagonalSize(cascade_id), calc_max_start_dist(enviLightDir, structuredBufferAt(visible_ambient_voxels_walls_planes, voxelNo)));
        float3 colorA = raycast_loop(cascade_id, worldPos, enviLightDir, MAX_TRACE_DIST, maxStartDist);
        half3 enviLightColor = isfinite(colorA.rgb) ? colorA.rgb : 0;
        integrate_cube(enviLightDir, enviLightColor, col0,col1,col2,col3,col4,col5);
      }

      const float parallel_weight = 4./NUM_RAYS;

      PARALLEL_CUBE_AVERAGE

      if (tid == 0)
      {
        TraceResultAmbientVoxel ret;
        ret = (TraceResultAmbientVoxel)0;
        encode_trace_result_colors(ret, col0, col1, col2, col3, col4, col5);
        structuredBufferAt(traceResults, gId) = ret;
      }
    }
  }

  if (gi_quality == raytracing)
  {
    compile("cs_6_5", "light_voxels_cs");
  } else
  {
    compile("cs_5_0", "light_voxels_cs");
  }
}

shader light_ss_combine_ambient_voxels_cs
{
  hlsl(cs)
  {
    #define NO_GRADIENTS_IN_SHADER 1
  }
  SSGI_USE_VOLMAP_GI_COORD(cs)

  hlsl(cs) {
    #define AVERAGE_CUBE_WARP_SIZE COMBINE_WARP_SIZE
    #include <parallel_average_cube.hlsl>
  }
  (cs) { temporal_weight_limit@f1 = (ssgi_temporal_weight_limit); }


  hlsl(cs) {
    StructuredBuffer<VisibleAmbientVoxel> visible_ambient_voxels: register(t15);
    StructuredBuffer<TraceResultAmbientVoxel> visible_ambient_voxels_trace_results: register(t14);
    RWTexture3D<float3>  gi_ambient_volmap : register(u6);
    RWTexture3D<float>   ssgi_ambient_volmap_temporal : register(u7);
    #include <dagi_brigthnes_lerp.hlsl>
    float3 RoundColor10bit( float3 rgb )
    {
      //return Unpack_R11G11B10_FLOAT(Pack_R11G11B10_FLOAT(rgb));
      uint3 color = (uint3(f32tof16(rgb.x), f32tof16(rgb.y), f32tof16(rgb.z)))&0xFFE0;
      //uint3 color = (uint3(f32tof16(rgb.x), f32tof16(rgb.y), f32tof16(rgb.z)) + 16)&0xFFE0;
      return float3(f16tof32(color.x), f16tof32(color.y), f16tof32(color.z));
    }
    float3 lerp_br(float3 oldV, float3 newV, uint tag, inout float maxDiff)//todo: use tag
    {
      float3 absDiff = abs(newV-oldV);
      maxDiff += min(saturate(max3(absDiff)), 0.05*max3(absDiff/newV));
      return lerp(oldV, newV, 0.24+0.25/(1+tag));//starting from 0.15 seem to be working with r11g11b10. 0.125 not enough!
      //return newV;
      //return lerp(oldV, newV, tag == 0 ? 1 : 0.5+0.05*lerpBrightnessValue(oldV, newV));//starting from 0.15 seem to be working with r11g11b10. 0.125 not enough!
      //float v = 1./(tag+1.);
      //FLATTEN
      //if (tag>=16)
      //  v = 0.125*lerpBrightnessValue(oldV, newV);
      //return lerp(oldV, newV, v);
    }

    [numthreads(COMBINE_WARP_SIZE, 1, 1)]
    void light_voxels_cs( uint gId : SV_GroupID, uint tid: SV_GroupIndex, uint dtId : SV_DispatchThreadID )//uint3 gId : SV_GroupId,
    {
      const uint NUM_RAYS = THREAD_PER_RAY;
      uint voxelNo = gId;
      uint voxel = visible_ambient_voxels[voxelNo].voxelId;
      uint tag = 0;

      float3 col0=0,col1=0,col2=0,col3=0,col4=0,col5=0;
      decode_trace_result_colors(visible_ambient_voxels_trace_results[dtId], col0, col1, col2, col3, col4, col5);
      const float parallel_weight = 1.f/NUM_RAY_GROUPS;

      PARALLEL_CUBE_AVERAGE

      if (tid == 0)//or SSGI_TEMPORAL_COPIED_VALUE, depending on performance
      {
        uint3 coord = decode_voxel_coord_safe(voxel, tag);
        //float expWeight = saturate((weight-thresholdWeight)/(NUM_RAYS - thresholdWeight));
        //expWeight *= 0.02;
        float3 vc0,vc1,vc2,vc3,vc4,vc5;
        //#define ROUND_COLOR(c) c = RoundColor10bit(c)//Unpack_R11G11B10_FLOAT(Pack_R11G11B10_FLOAT(c))
        //ROUND_COLOR(col0);ROUND_COLOR(col1);ROUND_COLOR(col2);ROUND_COLOR(col3);ROUND_COLOR(col4);ROUND_COLOR(col5);
        //#undef ROUND_COLOR

        decode_voxel_colors(visible_ambient_voxels[voxelNo], vc0,vc1,vc2,vc3,vc4,vc5);

        float maxBrDiff = 0;
        vc0 = lerp_br(vc0, col0, tag, maxBrDiff);
        vc1 = lerp_br(vc1, col1, tag, maxBrDiff);
        vc2 = lerp_br(vc2, col2, tag, maxBrDiff);
        vc3 = lerp_br(vc3, col3, tag, maxBrDiff);
        vc4 = lerp_br(vc4, col4, tag, maxBrDiff);
        vc5 = lerp_br(vc5, col5, tag, maxBrDiff);
        maxBrDiff *= 1./6.;
        float newTag = SSGI_TEMPORAL_MAX_VALUE + 1.51f/255.f - maxBrDiff;
        newTag = clamp(newTag, SSGI_TEMPORAL_VALID_VALUE, SSGI_TEMPORAL_MAX_VALUE);

        FLATTEN
        if (newTag >= temporal_weight_limit)
        {
          vc0 = col0;
          vc1 = col1;
          vc2 = col2;
          vc3 = col3;
          vc4 = col4;
          vc5 = col5;
        }

        coord.z += ssgi_cascade_z_crd_ofs(cascade_id);
        ssgi_ambient_volmap_temporal[coord] = newTag;
        coord.z += ssgi_cascade_z_crd_ofs(cascade_id)*5;
        uint z_ofs = volmap_y_dim(cascade_id);
        gi_ambient_volmap[coord] = vc0; coord.z += z_ofs;
        gi_ambient_volmap[coord] = vc1; coord.z += z_ofs;
        gi_ambient_volmap[coord] = vc2; coord.z += z_ofs;
        gi_ambient_volmap[coord] = vc3; coord.z += z_ofs;
        gi_ambient_volmap[coord] = vc4; coord.z += z_ofs;
        gi_ambient_volmap[coord] = vc5;
      }
    }
  }
  compile("cs_5_0", "light_voxels_cs");
}

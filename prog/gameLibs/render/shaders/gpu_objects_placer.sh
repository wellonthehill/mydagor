include "shader_global.sh"
include "heightmap_common.sh"
include "toroidal_heightmap.sh"
include "displacement_inc.sh"
include "biomes.sh"
include "gpuobj_displacement_inc.sh"
include "frustum.sh"
include "shore.sh"
include "rendinst_heightmap_ofs.sh"
include "land_mask_inc.sh"

float4 gpu_objects_world_coord;
float gpu_objects_bounding_radius;
float gpu_objects_groups_count;
float gpu_objects_groups_bbox_offset;
float gpu_objects_cell_buffer_offset;
float gpu_objects_group_idx;
float gpu_objects_seed;
float4 gpu_objects_up_vector;
float4 gpu_objects_scale_rotate;
texture noise_128_tex_hash;
texture gpu_objects_map;
float4 gpu_objects_map_size_offset;
float4 gpu_objects_color_from;
float4 gpu_objects_color_to;
float4 gpu_objects_slope_factor;
float4 gpu_objects_coast_range;
int gpu_objects_face_coast;
int gpu_objects_biomes_count;
float4 gpu_objects_weights;

float gpu_objects_rendinst_offset;
float gpu_objects_num_for_placing;
float gpu_objects_num_per_rendinst;
float4 gpu_objects_rendinst_mesh_params;
float4 gpu_objects_on_ri_placing_params;
int gpu_objects_ri_pool_id_offset;

buffer gpu_objects_instance_buf;
buffer gpu_objects_face_areas_doubled_buf;
buffer gpu_objects_num_objects_buf;

int gpu_objects_place_on_water;
int4 gpu_object_ints_to_clear; //(start, count, 0, 0)

int gpu_objects_gpu_instancing = 0;
interval gpu_objects_gpu_instancing: off<1, on;

int gpu_objects_generation_state = 0;
interval gpu_objects_generation_state: first_generation<1, normal;

float4 view_vecLT;
float4 view_vecRT;
float4 view_vecLB;
float4 view_vecRB;
float4 view_dir;

int biom_indexes_const_no = 60 always_referenced;

int gpu_objects_indirect_params_const_no = 13;
int gpu_objects_lod_offsets_buffer_const_no = 14;
int gpu_objects_generation_params_const_no = 15;

float4 gpu_objects_bomb_hole_point_radius_0;
float4 gpu_objects_bomb_hole_point_radius_1;
float4 gpu_objects_bomb_hole_point_radius_2;
float4 gpu_objects_bomb_hole_point_radius_3;

macro USE_GPU_OBJECTS_DATA()
  ENABLE_ASSERT(cs)
  (cs) {
    gpu_objects_world_coord__bounding_radius@f4 = (
      gpu_objects_world_coord.x,
      gpu_objects_world_coord.y,
      gpu_objects_world_coord.z,
      gpu_objects_bounding_radius);
    grid_parameters@f4 = (
      gpu_objects_groups_count,
      gpu_objects_groups_bbox_offset,
      gpu_objects_cell_buffer_offset,
      gpu_objects_group_idx);
    up_vector@f4 = (gpu_objects_up_vector);
    scale_rotate_ranges@f4 = gpu_objects_scale_rotate;
    noise_128_tex_hash@smp2d = noise_128_tex_hash;
    color_from@f4 = gpu_objects_color_from;
    color_to@f4 = gpu_objects_color_to;
    coast_params_seed@f4 = (gpu_objects_coast_range.x,gpu_objects_coast_range.y,gpu_objects_face_coast, gpu_objects_seed);
    gpu_objects_slope_factor@f4 = gpu_objects_slope_factor;
    gpu_objects_weights@f4 = gpu_objects_weights;
    gpu_objects_ri_pool_id_offset_biomes_count@i2 = (gpu_objects_ri_pool_id_offset, gpu_objects_biomes_count, 0, 0);
    gpu_objects_generation_params@buf : register(gpu_objects_generation_params_const_no) hlsl {
      Buffer<float4> gpu_objects_generation_params@buf;
    };
    world_view_pos@f3 = world_view_pos;
    gpu_objects_bomb_hole_point_0@f3 = gpu_objects_bomb_hole_point_radius_0;
    gpu_objects_bomb_hole_point_1@f3 = gpu_objects_bomb_hole_point_radius_1;
    gpu_objects_bomb_hole_point_2@f3 = gpu_objects_bomb_hole_point_radius_2;
    gpu_objects_bomb_hole_point_3@f3 = gpu_objects_bomb_hole_point_radius_3;
    gpu_objects_bomb_hole_radiuses_squared@f4 = (
      gpu_objects_bomb_hole_point_radius_0.w * gpu_objects_bomb_hole_point_radius_0.w,
      gpu_objects_bomb_hole_point_radius_1.w * gpu_objects_bomb_hole_point_radius_1.w,
      gpu_objects_bomb_hole_point_radius_2.w * gpu_objects_bomb_hole_point_radius_2.w,
      gpu_objects_bomb_hole_point_radius_3.w * gpu_objects_bomb_hole_point_radius_3.w
    );
  }
  hlsl(cs) {
    float4 biom_indexes[32] :register(c60);
    float4 biom_indexes_lastreg :register(c92);

    struct GpuObjectsIndirectParams
    {
      int2 cornerPos;
      uint xSize;
      float tileSize;
    };

    #define gpu_objects_ri_pool_id_offset gpu_objects_ri_pool_id_offset_biomes_count.x
    #define gpu_objects_biomes_count      gpu_objects_ri_pool_id_offset_biomes_count.y

    #define gpu_objects_world_coord gpu_objects_world_coord__bounding_radius.xyz
    #define bounding_radius gpu_objects_world_coord__bounding_radius.w
    #define groups_count grid_parameters.x
    #define group_bbox_offset grid_parameters.y
    #define cell_buffer_offset grid_parameters.z
    #define scale_range (scale_rotate_ranges.xy)
    #define rotate_range (scale_rotate_ranges.zw)
    #define coast_range (coast_params_seed.xy)
    #define face_coast (coast_params_seed.z)
    #define seed (coast_params_seed.w)

    #define GPUOBJ_WARP_SIZE_X 4
    #define GPUOBJ_WARP_SIZE_Y 4
    #define REVERSE_GPUOBJ_WARP_SIZE_X (1.0/GPUOBJ_WARP_SIZE_X)
    #define MAX_LODS 4
    #define GENERATE_STRIDE 5

    #define BUF_STRIDE 2
    #define index_count_per_instance(_objNo, _lodNo) uint(loadBuffer(gpu_objects_generation_params, MAX_LODS*BUF_STRIDE*_objNo + BUF_STRIDE*_lodNo + 0).x + 0.1f)
    #define start_index_location(_objNo, _lodNo)     uint(loadBuffer(gpu_objects_generation_params, MAX_LODS*BUF_STRIDE*_objNo + BUF_STRIDE*_lodNo + 0).y + 0.1f)
    #define base_vertex(_objNo, _lodNo)              uint(loadBuffer(gpu_objects_generation_params, MAX_LODS*BUF_STRIDE*_objNo + BUF_STRIDE*_lodNo + 0).z + 0.1f)
    #define object_location(_objNo, _lodNo)          uint(loadBuffer(gpu_objects_generation_params, MAX_LODS*BUF_STRIDE*_objNo + BUF_STRIDE*_lodNo + 0).w + 0.1f)
    #define tile_size(_objNo, _lodNo)                     loadBuffer(gpu_objects_generation_params, MAX_LODS*BUF_STRIDE*_objNo + BUF_STRIDE*_lodNo + 1).x
    #define max_range(_objNo, _lodNo)                     loadBuffer(gpu_objects_generation_params, MAX_LODS*BUF_STRIDE*_objNo + BUF_STRIDE*_lodNo + 1).y

    float2 getTileCoords(uint2 group_coords, uint group_index, uint size_x, int2 corner_pos, float tile_size)
    {
      uint2 groupID;

      groupID.x = group_index.x % size_x;
      groupID.y = group_index.x / size_x;

      float2 floatGThreadPos = float2(group_coords.x, group_coords.y);
      float2 floatThreadPos = float2(groupID.x, groupID.y) + floatGThreadPos*REVERSE_GPUOBJ_WARP_SIZE_X;
      return (floatThreadPos + corner_pos) * tile_size;
    }
  }
endmacro

float gpu_objects_count = 0;
float gpu_objects_no = 0;

hlsl(cs) {
  #define MAX_GPU_OBJECTS_COUNT 64
  #define THREAD_COUNT_FOR_EARLY_CULL 4
}

// special shader for gpu objects invalidation after generation
shader gpu_objects_rebuild_relems {
  USE_GPU_OBJECTS_DATA()

  (cs) {
    objects_countF@f1 = (gpu_objects_count, 0, 0, 0);
  }
  hlsl(cs) {

    RWByteAddressBuffer drawInstancedBuffer : register(u4);

    [numthreads( MAX_GPU_OBJECTS_COUNT, THREAD_COUNT_FOR_EARLY_CULL, 1 )]
    void main(uint3 objNum : SV_GroupThreadID)
    {
      uint objects_count = uint(objects_countF + 0.1);
      uint objNo = objNum.x;
      uint cullingThreadNo = objNum.y;

      BRANCH
      if (objNo<objects_count)
      {
        BRANCH
        if (cullingThreadNo < MAX_LODS)
        {
          uint firstId = GENERATE_STRIDE*(cullingThreadNo+MAX_LODS*objNo);

          storeBuffer(drawInstancedBuffer, 4 * (0 + firstId), index_count_per_instance(objNo, cullingThreadNo));
          // storeBuffer(drawInstancedBuffer, 4 * (1 + firstId), 0);                                          // instanceCount is not resetted
          storeBuffer(drawInstancedBuffer, 4 * (2 + firstId), start_index_location(objNo, cullingThreadNo));  // StartIndexLocation
          storeBuffer(drawInstancedBuffer, 4 * (3 + firstId), base_vertex(objNo, cullingThreadNo));           // base vertex
          storeBuffer(drawInstancedBuffer, 4 * (4 + firstId), 0u);                                            // start instance location
        }
      }
    }
  }
  compile("target_cs", "main");
}

int draw_instanced_buffer_no = 4;
int generate_indirect_buffer_no = 5;
int lod_offsets_buffer_no = 6;
int indirect_params_no = 7;

shader gpu_objects_create_indirect {
  (cs) {
    objects_countF@f1 = gpu_objects_count;

    view_vecLT@f3 = view_vecLT;
    view_vecRT@f3 = view_vecRT;
    view_vecLB@f3 = view_vecLB;
    view_vecRB@f3 = view_vecRB;

    drawInstancedBuffer@uav    : register(draw_instanced_buffer_no) hlsl {
      RWByteAddressBuffer drawInstancedBuffer@uav;
    }
    generateIndirectBuffer@uav : register(generate_indirect_buffer_no) hlsl {
      RWByteAddressBuffer generateIndirectBuffer@uav;
    }
    lodOffsetsBuffer@uav       : register(lod_offsets_buffer_no) hlsl {
      RWByteAddressBuffer lodOffsetsBuffer@uav;
    }
    indirectParams@uav         : register(indirect_params_no) hlsl {
      #define DECLARE_INDIRECT_PARAMS RWStructuredBuffer<GpuObjectsIndirectParams> indirectParams@uav
    }
  }

  USE_GPU_OBJECTS_DATA()
  hlsl(cs) {
    DECLARE_INDIRECT_PARAMS;
    groupshared uint dispatch_count[MAX_GPU_OBJECTS_COUNT];
    // for lods
    groupshared uint max_tiles_count[MAX_GPU_OBJECTS_COUNT][MAX_LODS];

    [numthreads( MAX_GPU_OBJECTS_COUNT, THREAD_COUNT_FOR_EARLY_CULL, 1 )]
    void main(uint3 objNum : SV_GroupThreadID)
    {
      uint objects_count = uint(objects_countF + 0.1);
      uint objNo = objNum.x;
      uint cullingThreadNo = objNum.y;
      uint2 tilesCount = 0;
      int totalCount = 0;
      int2 cornerPos = 0;
      float tileSize = 0;
      float4 lodRadius = 0;

      BRANCH
      if (objNo<objects_count)
      {
        BRANCH
        if (cullingThreadNo < MAX_LODS)
        {
          uint firstId = GENERATE_STRIDE*(cullingThreadNo+MAX_LODS*objNo);
          ##if gpu_objects_generation_state == first_generation
            storeBuffer(drawInstancedBuffer, 4 * (0 + firstId), index_count_per_instance(objNo, cullingThreadNo)); // IndexCountPerInstance
            storeBuffer(drawInstancedBuffer, 4 * (1 + firstId), 0u);                                               // instanceCount
            storeBuffer(drawInstancedBuffer, 4 * (2 + firstId), start_index_location(objNo, cullingThreadNo));     // StartIndexLocation
            storeBuffer(drawInstancedBuffer, 4 * (3 + firstId), base_vertex(objNo, cullingThreadNo));              // base vertex
            storeBuffer(drawInstancedBuffer, 4 * (4 + firstId), 0u);                                               // start instance location
          ##else
            storeBuffer(drawInstancedBuffer, 4 * (1 + firstId), 0u); // reset instanceCount
          ##endif
        }

        tileSize  = tile_size(objNo, 0);
        lodRadius = float4(max_range(objNo, 0), max_range(objNo, 1), max_range(objNo, 2), max_range(objNo, 3));
        float  maxRadius = max(max(lodRadius.x, lodRadius.y), max(lodRadius.z, lodRadius.w));

        int quadSize = ceil(maxRadius / tileSize);

        // early cull for groupthreads
        float3 p1 = world_view_pos + view_vecLT*maxRadius;
        float3 p2 = world_view_pos + view_vecRT*maxRadius;
        float3 p3 = world_view_pos + view_vecLB*maxRadius;
        float3 p4 = world_view_pos + view_vecRB*maxRadius;

        float3 p5 = 0.25f*(p1 + p2 + p3 + p4);

        float2 bMax = float2(max(max(max(p1.x, p2.x), max(p3.x, p4.x)), max(p5.x, world_view_pos.x)),
                             max(max(max(p1.z, p2.z), max(p3.z, p4.z)), max(p5.z, world_view_pos.z)));
        float2 bMin = float2(min(min(min(p1.x, p2.x), min(p3.x, p4.x)), min(p5.x, world_view_pos.x)),
                             min(min(min(p1.z, p2.z), min(p3.z, p4.z)), min(p5.z, world_view_pos.z)));

        float startX = max(floor(bMin.x / tileSize), floor(world_view_pos.x / tileSize) - quadSize);
        float endX = min(ceil(bMax.x / tileSize), ceil(world_view_pos.x / tileSize) + quadSize);
        float startZ = max(floor(bMin.y / tileSize), floor(world_view_pos.z / tileSize) - quadSize);
        float endZ = min(ceil(bMax.y / tileSize), ceil(world_view_pos.z / tileSize) + quadSize);

        tilesCount.x = ceil(endX - startX);
        tilesCount.y = ceil(endZ - startZ);

        totalCount = tilesCount.x * tilesCount.y;
        cornerPos = int2(startX, startZ);

        BRANCH
        if (cullingThreadNo == 0)
        {
          structuredBufferAt(indirectParams, objNo).xSize = tilesCount.x;
          structuredBufferAt(indirectParams, objNo).cornerPos = cornerPos;
          structuredBufferAt(indirectParams, objNo).tileSize = tileSize;

          // count of thread groups for current object
          dispatch_count[objNo] = totalCount;
        }
        BRANCH
        if (cullingThreadNo < MAX_LODS)
          max_tiles_count[objNo][cullingThreadNo] = 0;
      }

      GroupMemoryBarrierWithGroupSync();

      // use all threads in THREAD_COUNT_FOR_EARLY_CULL for calculating actual maximum instance count for each lod

      BRANCH
      if (objNo<objects_count)
      {
        uint cellStart = ceil(totalCount * (cullingThreadNo / float(THREAD_COUNT_FOR_EARLY_CULL)));

        for (uint cell_i = cellStart; cell_i < totalCount * ((cullingThreadNo + 1.0f) / float(THREAD_COUNT_FOR_EARLY_CULL)); cell_i++)
        {
          uint2 centerGroup = uint2(2, 2);
          float2 tileCenter = getTileCoords(centerGroup, cell_i, tilesCount.x, cornerPos, tileSize);
          float dist = length(tileCenter - world_view_pos.xz);
          uint lodNo = dist < lodRadius.x ? 0 : (dist < lodRadius.y ? 1 : (dist < lodRadius.z ? 2 : (dist < lodRadius.w ? 3 : 4)));
          BRANCH
          if (lodNo < 4)
          {
            uint at; InterlockedAdd(max_tiles_count[objNo][lodNo], 1, at);
          }
        }
      }

      GroupMemoryBarrierWithGroupSync();

//      uint sum = 0;

      BRANCH
      if (objNo<objects_count && cullingThreadNo == 0)
      {
        // for now we use single dispatch per object, not the combined dispatch
        //for (uint i = 0; i < objNo; i++)
        //{
        //  sum += dispatch_count[i];
        //}
        // position of first instance for current object
        int lodOffset = 0;
        for (int i = 0; i< MAX_LODS; i++)
        {
          // need to calculatate actual count of objects per lod;
          storeBuffer(lodOffsetsBuffer, (objNo*MAX_LODS + i)*4, object_location(objNo, 0) + lodOffset);
          lodOffset += max_tiles_count[objNo][i] * GPUOBJ_WARP_SIZE_X * GPUOBJ_WARP_SIZE_Y;
        }
      }

      BRANCH
      if (cullingThreadNo == 0 && objNo < objects_count)
      {
        // for now we use single dispatch per object, not the combined dispatch
        //sum += tilesCount.x * tilesCount.y;
        //storeBuffer(generateIndirectBuffer, 4 * 0, sum);
        storeBuffer(generateIndirectBuffer, 4 * (0 + 3 * objNo), tilesCount.x * tilesCount.y);
        ##if gpu_objects_generation_state == first_generation
          storeBuffer(generateIndirectBuffer, 4 * (1 + 3 * objNo), 1u);
          storeBuffer(generateIndirectBuffer, 4 * (2 + 3 * objNo), 1u);
        ##endif
      }
    }
  }
  compile("target_cs", "main");
}

float4 hmap_ofs_thickness_map = (1/2048,1/2048,0,0);
texture hmap_ofs_thickness;

texture perlin_noise3d;

macro GPU_OBJECTS_LOAD_MESH_TRIANGLE()
  hlsl(cs) {
    void load_mesh_triangle_internal(uint start_index, uint face_id, uint base_vertex, uint stride,
                                     out uint4 v1_n, out uint4 v2_n, out uint4 v3_n)
    {
      uint3 indices;
      #define BYTE_PER_INDEX 2
      uint indices_offset = ((start_index + face_id * 3) * BYTE_PER_INDEX);
      uint2 indices_mem = loadBuffer2(indexBuf, indices_offset & ~0x3); //48 bits of need indices, other 16 not needed
      if (indices_offset & 0x2) //first 16 not needed
        indices = uint3(indices_mem.x >> 16, indices_mem.y & 0xffff, indices_mem.y >> 16);
      else //last 16 not needed
        indices = uint3(indices_mem.x & 0xffff, indices_mem.x >> 16, indices_mem.y & 0xffff);
      indices = (indices + base_vertex) * stride; //assumption that stride is multiple by 4

      v1_n = loadBuffer4(vertexBuf, indices.x);
      v2_n = loadBuffer4(vertexBuf, indices.y);
      v3_n = loadBuffer4(vertexBuf, indices.z);
    }

    void load_mesh_triangle(uint start_index, uint face_id, uint base_vertex, uint stride,
                            out float3 v1, out float3 v2, out float3 v3)
    {
      uint4 v1_n, v2_n, v3_n;
      load_mesh_triangle_internal(start_index, face_id, base_vertex, stride, v1_n, v2_n, v3_n);
      v1 = asfloat(v1_n.xyz);
      v2 = asfloat(v2_n.xyz);
      v3 = asfloat(v3_n.xyz);
    }

    float3 decode_normal(uint encoded_normal)
    {
      return (uint3(encoded_normal >> 16, encoded_normal >> 8, encoded_normal) & 0xff) / 127.5 - 1.0;
    }

    void load_mesh_triangle(uint start_index, uint face_id, uint base_vertex, uint stride,
                            out float3 v1, out float3 v2, out float3 v3, out float3 n1, out float3 n2, out float3 n3)
    {
      uint4 v1_n, v2_n, v3_n;
      load_mesh_triangle_internal(start_index, face_id, base_vertex, stride, v1_n, v2_n, v3_n);
      v1 = asfloat(v1_n.xyz);
      v2 = asfloat(v2_n.xyz);
      v3 = asfloat(v3_n.xyz);
      n1 = decode_normal(v1_n.w);
      n2 = decode_normal(v2_n.w);
      n3 = decode_normal(v3_n.w);
    }
  }
endmacro

macro GPU_OBJECTS_CS_INSTANCE_DATA_BUFFER()
  if (small_sampled_buffers == no)
  {
    (cs) {
      instanceBuf@buf = gpu_objects_instance_buf hlsl { Buffer<float4> instanceBuf@buf; }
    }
  } else
  {
    (cs) {
      instanceBuf@buf = gpu_objects_instance_buf hlsl { StructuredBuffer<float4> instanceBuf@buf; }
    }
  }
endmacro

shader gpu_object_rendist_face_areas_cs
{
  (cs) {
    mesh_params@f4 = gpu_objects_rendinst_mesh_params;
    object_density@f1 = (gpu_objects_on_ri_placing_params.x);
  }

  hlsl(cs) {
    RWBuffer<uint> numObjects : register(u0);
    RWBuffer<float> faceAreasDoubled : register(u1);
    ByteAddressBuffer indexBuf : register(t14);
    ByteAddressBuffer vertexBuf : register(t15);
  }

  GPU_OBJECTS_LOAD_MESH_TRIANGLE()
  ENABLE_ASSERT(cs)

  hlsl(cs) {
    #include "gpuObjects/gpu_objects_const.hlsli"

    groupshared float sum_in_group[DISPATCH_WARP_SIZE];

    [numthreads(DISPATCH_WARP_SIZE, 1, 1)]
    void calculate_rendinst_face_areas(uint thread_id : SV_GroupThreadID, uint2 grp_id : SV_GroupID, uint gt_id : SV_DispatchThreadID)
    {
      uint start_index = mesh_params.x;
      uint num_faces = mesh_params.y;
      uint base_vertex = mesh_params.z;
      uint stride = mesh_params.w;
      uint face_id = gt_id;
      BRANCH
      if (face_id < num_faces)
      {
        float3 v1, v2, v3;
        load_mesh_triangle(start_index, face_id, base_vertex, stride, v1, v2, v3);
        float faceAreaDoubled = length(cross(v1 - v3, v2 - v3));
        sum_in_group[thread_id.x] = faceAreaDoubled;
        faceAreasDoubled[face_id] = faceAreaDoubled;
      }
      else
        sum_in_group[thread_id.x] = 0.0;

      GroupMemoryBarrierWithGroupSync();

      const int WARP_SIZE = 32;

      UNROLL
      for (uint i = DISPATCH_WARP_SIZE / 2; i > 0; i >>= 1)
      {
        if (thread_id > i)
          break;

        sum_in_group[thread_id.x] = sum_in_group[thread_id.x] + sum_in_group[thread_id.x + i];

        if (i <= WARP_SIZE)
          GroupMemoryBarrier();
        else
          GroupMemoryBarrierWithGroupSync();
      }

      if (thread_id.x == 0)
      {
        InterlockedAdd(bufferAt(numObjects, 0), uint(0.5 * sum_in_group[0] * object_density));
      }
    }
  }
  compile("cs_5_0", "calculate_rendinst_face_areas");
}

int gpu_object_rendinst_instances_count;

shader gpu_objects_on_rendinst_get_group_count_cs
{
  (cs)
  {
    instances_count@i1 = (gpu_object_rendinst_instances_count);
    numObjects@buf = gpu_objects_num_objects_buf hlsl { Buffer<uint> numObjects@buf; };
  }

  hlsl(cs) {
    #include "gpuObjects/gpu_objects_const.hlsli"

    RWBuffer<uint> group_count : register(u0);

    [numthreads(1, 1, 1)]
    void get_group_count()
    {
      uint object_count = numObjects[0];
      group_count[0] = (object_count + DISPATCH_WARP_SIZE - 1) / DISPATCH_WARP_SIZE;
      group_count[1] = instances_count;
      group_count[2] = 1;
    }
  }
  compile("cs_5_0", "get_group_count");
}

shader gpu_objects_cs, gpu_objects_on_rendinst_cs
{
  if (tex_hmap_low == NULL) {
    LAND_MASK_TEXCOORD(cs)
    INIT_AND_USE_LAND_HEIGHT(cs)
  }
  if (shader == gpu_objects_cs)
  {
    hlsl(cs) {
      #define NO_GRADIENTS_IN_SHADER 1
    }

    INIT_WORLD_HEIGHTMAP_BASE(cs)
    USE_HEIGHTMAP_COMMON_BASE(cs)

    (cs)
    {
      gpu_objects_place_on_water@i1 = (gpu_objects_place_on_water);
      water_level@f1 = (water_level);
      object_noF@f1 = (gpu_objects_no, 0, 0, 0);
    }
    if (shore_distance_field_tex != NULL)
    {
      (cs)
      {
        world_to_heightmap@f4 = world_to_heightmap;
        shore_distance_field_tex@smp2d = shore_distance_field_tex;
        distance_field_texture_size_inv@f1 = (1./distance_field_texture_size,0,0,0);
      }
    }

    INIT_BIOMES(cs)
    USE_BIOMES(cs)

    INIT_TOROIDAL_HEIGHTMAP(cs)

    if (toroidal_heightmap_texarray != NULL)// && gpu_objects_enable_displacement == yes)
    {
      USE_DISPLACEMENT_PHYSMAT(cs)
      (cs) {
        displacementParams@f3 = (hmap_displacement_down, hmap_displacement_up-hmap_displacement_down,
                                -hmap_displacement_down / (hmap_displacement_up - hmap_displacement_down), 0);
        hmap_ofs_thickness@smp2d = hmap_ofs_thickness;
        hmap_ofs_thickness_map@f4 = hmap_ofs_thickness_map;

        hmap_ofs_tex@smp2d = hmap_ofs_tex;
        world_to_hmap_ofs@f4 = world_to_hmap_ofs;
        hmap_ofs_tex_size@f4 = hmap_ofs_tex_size;
      }
      USE_TOROIDAL_HEIGHTMAP_LOWRES(cs)
      hlsl(cs) {
        #define GET_DISPLACEMENT_GIVES_NORMALS 0
        float3 get_displacement(float2 coordsXZ, out float3 surface_normal)
        {
          float height = displacementParams.y * sample_tor_height_lowres(coordsXZ, displacementParams.z) + displacementParams.x;
          float thickness = tex2Dlod(hmap_ofs_thickness, float4(coordsXZ*hmap_ofs_thickness_map.xy + hmap_ofs_thickness_map.zw,0,0)).r;
          surface_normal = float3(0,1,0);

          float2 tc_ofs = coordsXZ*world_to_hmap_ofs.xy + world_to_hmap_ofs.zw;
          float2 tc_centered = saturate(-10*abs(tc_ofs*2-1)+10);
          float weightOfs = (tc_centered.x*tc_centered.y);
          float ofsTex = tc_ofs.x >= 0 && tc_ofs.y >= 0 && tc_ofs.x < 1 && tc_ofs.y < 1 ?
                           2*tex2Dlod(hmap_ofs_tex, float4(tc_ofs,0,0)).r : 1;
          float trackdirt = lerp(thickness, thickness*ofsTex, weightOfs)*hmap_ofs_tex_size.y;
          return float3(0, trackdirt + get_phys_height(height, thickness, ofsTex), 0);
        }
      }
    }
    else
    {
      INIT_AND_USE_GPUOBJ_DISPLACEMENT()
    }

    if (toroidal_heightmap_texarray != NULL && gpu_objects_gpu_instancing == on)
    {
      INIT_TERRAFORM_HEIGHT(cs)
      USE_TERRAFORM_HEIGHT(cs)

      hlsl(cs) {
        bool get_terraform_removal(inout float3 world_pos)
        {
          half tformHeight = get_terraform_height(world_pos);
          world_pos.y += tformHeight;
          return (abs(tformHeight) < 0.5);
        }
      }
    }
    else
    {
      hlsl(cs) {
        #define get_terraform_removal(_param_) true
      }
    }
  }

  USE_GPU_OBJECTS_DATA()
  INIT_AND_USE_FRUSTUM_CHECK_CS()
  if (gpu_objects_map != NULL)
  {
    (cs) {
      map@smp2d = gpu_objects_map;
      map_size_offset@f4 = gpu_objects_map_size_offset;
    }
  }
  if (shader == gpu_objects_on_rendinst_cs)
  {
    GPU_OBJECTS_CS_INSTANCE_DATA_BUFFER()

    (cs) {
      face_areas_doubled@buf = gpu_objects_face_areas_doubled_buf hlsl { StructuredBuffer<float> face_areas_doubled@buf; }
      num_objects@buf = gpu_objects_num_objects_buf hlsl { StructuredBuffer<uint> num_objects@buf; }
      mesh_params@f4 = gpu_objects_rendinst_mesh_params;
      instance_offset__counts@f2 = (gpu_objects_rendinst_offset, gpu_objects_num_per_rendinst, 0, 0);
      placing_params@f4 = gpu_objects_on_ri_placing_params;
      perlin_noise3d@smp3d = perlin_noise3d;
    }
  }
  if(shader == gpu_objects_cs)
  {
    INIT_RENDINST_HEIGHTMAP_OFS(cs)
    USE_RENDINST_HEIGHTMAP_OFS(cs)

    if (gpu_objects_gpu_instancing == on)
    {
      (cs){
        gpuObjectsIndirectParams@buf : register(gpu_objects_indirect_params_const_no) hlsl {
          #define DECLARE_GPU_OBJECT_INDIRECT_PARAMETERS \
            StructuredBuffer<GpuObjectsIndirectParams> gpuObjectsIndirectParams@buf;
        };
        lodOffsetsBuffer@buf : register(gpu_objects_lod_offsets_buffer_const_no) hlsl {
          ByteAddressBuffer lodOffsetsBuffer@buf;
        };
      }
    }
  }

  hlsl(cs) {
    #include "gpuObjects/gpu_objects_const.hlsli"

    RWBuffer<float4> gpuObjectsBuffer : register(u0); // It is a buffer of 4x4 matrices we can't use structured buffer here, because we copy it to buffer, which is used for RI rendering. RI rendering uses buffer of float4.
    // Probably, we should use structured buffer of matrices in RI too.
    ##if shader == gpu_objects_cs

      RWByteAddressBuffer countersBuffer : register(u2);
      RWStructuredBuffer<int> bboxesBuffer : register(u1);
      groupshared float4 bboxes[4 * 4 * 2];

      ##if gpu_objects_gpu_instancing == on
        DECLARE_GPU_OBJECT_INDIRECT_PARAMETERS
      ##endif

    ##else //shader == gpu_objects_on_rendinst_cs
      RWByteAddressBuffer countersBuffer : register(u1);
      ByteAddressBuffer indexBuf : register(t14);
      ByteAddressBuffer vertexBuf : register(t15);
    ##endif
  }

  if (shader == gpu_objects_on_rendinst_cs)
  {
    GPU_OBJECTS_LOAD_MESH_TRIANGLE()
  }

  INIT_HMAP_HOLES(cs)
  USE_HMAP_HOLES(cs)

  hlsl(cs) {

    float rand(float2 co)
    {
      return frac(sin(dot(co.xy, float2(12.9898,78.233))) * 43758.5453);
    }
    float rand3(float3 co)
    {
      return frac(sin(dot(co.xyz, float3(4.1414, 12.9898,78.233))) * 43758.5453);
    }

    float distanceSquared(float3 v1, float3 v2)
    {
      float3 d = v1 - v2;
      return dot(d, d);
    }

    bool isInBombHole(float3 worldPos)
    {
      float4 distancesSquared = float4(
        distanceSquared(worldPos, gpu_objects_bomb_hole_point_0),
        distanceSquared(worldPos, gpu_objects_bomb_hole_point_1),
        distanceSquared(worldPos, gpu_objects_bomb_hole_point_2),
        distanceSquared(worldPos, gpu_objects_bomb_hole_point_3)
      );
      return any(distancesSquared <= gpu_objects_bomb_hole_radiuses_squared);
    }

    void addInstance(float3 pos, float3 direction, float rotate, float scale, inout float4 bbox_min, inout float4 bbox_max, uint flat_group_idx, uint buffer_offset, uint lod_no, float4 color)
    {
      if (isInBombHole(pos))
        return;
      ##if shader == gpu_objects_cs && gpu_objects_gpu_instancing == on
        uint objNo = uint(object_noF + 0.1);
        buffer_offset = loadBuffer(lodOffsetsBuffer, (MAX_LODS*objNo + lod_no)*4);
        uint at; countersBuffer.InterlockedAdd(4 * (GENERATE_STRIDE*(MAX_LODS*objNo + lod_no) + 1), 1u, at);
      ##else
        uint at; countersBuffer.InterlockedAdd(4 * flat_group_idx, 1u, at);
        if (at >= uint(gpu_objects_weights.z))
          return;
      ##endif

      float3 front = normalize(float3(0, direction.z, -direction.y));
##if shader == gpu_objects_on_rendinst_cs
      if (abs(direction.x) < 0.5)
        front = normalize(float3(0, direction.z, -direction.y)); //cross(direction, (1,0,0))
      else
        front = normalize(float3(-direction.z, 0, direction.x)); //cross(direction, (0,1,0))
##endif
      float3 right = normalize(cross(direction, front));

      float rotSin;
      float rotCos;
      sincos(rotate, rotSin, rotCos);
      ##if shader == gpu_objects_cs
        float2 rotateSC1 = float2(rotCos, -rotSin);
        float2 rotateSC2 = float2(rotSin, rotCos);

        right = float3(dot(right.xz, rotateSC1), right.y, dot(right.xz, rotateSC2));
        direction = float3(dot(direction.xz, rotateSC1), direction.y, dot(direction.xz, rotateSC2));
        front = float3(dot(front.xz, rotateSC1), front.y, dot(front.xz, rotateSC2));
      ##else // shader == gpu_objects_on_rendinst_cs
        //rotate along direction
        float3 rotatedRight = right * rotCos + front * rotSin;
        float3 rotatedFront = -right * rotSin + front * rotCos;
        //transpose
        right = float3(rotatedRight.x, direction.x, rotatedFront.x);
        front = float3(rotatedRight.z, direction.z, rotatedFront.z);
        direction = float3(rotatedRight.y, direction.y, rotatedFront.y);
      ##endif
      gpuObjectsBuffer[(at + buffer_offset) * 4 + 0] = float4(right * scale, pos.x);
      gpuObjectsBuffer[(at + buffer_offset) * 4 + 1] = float4(direction * scale, pos.y);
      gpuObjectsBuffer[(at + buffer_offset) * 4 + 2] = float4(front * scale, pos.z);
      uint c = uint(color.x * 255) | (uint(color.y * 255) << 8) | (uint(color.z * 255) << 16) | (uint(color.w * 255) << 24);
      gpuObjectsBuffer[(at + buffer_offset) * 4 + 3] = float4(asfloat(c), asfloat(gpu_objects_ri_pool_id_offset), 0.0, 0.0);

      bbox_min = min(bbox_min, float4(pos - bounding_radius, 0));
      bbox_max = max(bbox_max, float4(pos + bounding_radius, 0));
    }

##if shader == gpu_objects_cs
    [numthreads(GPUOBJ_WARP_SIZE_X, GPUOBJ_WARP_SIZE_Y, 1)]
    void generate_objects_positions(uint2 cell_coords : SV_DispatchThreadID,
                                    uint2 group_coords : SV_GroupThreadID,
                                    uint grp_idx : SV_GroupIndex,
                                    uint2 group_Id : SV_GroupID)
    {
      float4 bboxMin = float4(1e9, 1e9, 1e9, 1e9);
      float4 bboxMax = float4(-1e9, -1e9, -1e9, -1e9);
      int lodNo = 0;
      ##if gpu_objects_gpu_instancing == off
        float2 coords = cell_coords * gpu_objects_world_coord.z + gpu_objects_world_coord.xy;
        float2 randomSeed = float2(seed / 128, (uint)seed % 128);
        float2 randValues = tex2Dlod(noise_128_tex_hash, float4(coords*1. / 128.0 + 0.5 / 128.0 + randomSeed, 0.0, 0.0)).rg;
        coords += randValues.xy * 2*gpu_objects_world_coord.z;
        float3 worldPos = float3(coords.x, 0, coords.y);
      ##else
        uint objNo = uint(object_noF + 0.1);
        GpuObjectsIndirectParams tileData = structuredBufferAt(gpuObjectsIndirectParams, objNo);

        int prev_dispatch_count = 0;
        float2 coords = getTileCoords(group_coords.xy, (group_Id.x - prev_dispatch_count), tileData.xSize, tileData.cornerPos, tileData.tileSize);

        float2 randomSeed = float2(seed / 128, (uint)seed % 128);
        float2 randValues = tex2Dlod(noise_128_tex_hash, float4(coords*1. / 128.0 + 0.5 / 128.0 + randomSeed, 0.0, 0.0)).rg;
        coords += randValues.xy * 2*gpu_objects_world_coord.z;

        float3 worldPos = float3(coords.x, 0, coords.y);

        // lod calculated per whole group
        float4 lodRadius = float4(max_range(objNo, 0), max_range(objNo, 1), max_range(objNo, 2), max_range(objNo, 3));
        float2 groupCenterCoords = getTileCoords(uint2(2, 2), (group_Id.x - prev_dispatch_count), tileData.xSize, tileData.cornerPos, tileData.tileSize);
        float dist = length(groupCenterCoords - world_view_pos.xz);
        lodNo = dist < lodRadius.x ? 0 : (dist < lodRadius.y ? 1 : (dist < lodRadius.z ? 2 : (dist < lodRadius.w ? 3 : 4)));
      ##endif
      float seedMultiplier = 1;
      float shoreRotation = 0.0;
##if (gpu_objects_map != NULL)
      float2 uv = worldPos.xz * map_size_offset.xy + map_size_offset.zw;
      float place = tex2Dlod(map, float4(uv, 0, 0)).r;
      BRANCH
      if (place > 0 && lodNo < MAX_LODS)
##else
      bool placeAllowed = (gpu_objects_biomes_count <= 0);
      BRANCH
      if (!placeAllowed)
      {
        int sampledBiom = getBiomeIndex(worldPos);
        int i = 0;
        LOOP
        for (; i < gpu_objects_biomes_count; ++i)
        {
          placeAllowed = (sampledBiom == biom_indexes[i].x);
          if (placeAllowed)
            break;
        }
        seedMultiplier = biom_indexes[i].y;
      }
      ##if shore_distance_field_tex != NULL
        BRANCH
        if (placeAllowed && coast_range.y >= 0)
        {
          float2 dftc = worldPos.xz * world_to_heightmap.xy + world_to_heightmap.zw;
          float4 sdf = tex2Dlod(shore_distance_field_tex, float4(dftc,0,0));
          placeAllowed = coast_range.x <= sdf.w && sdf.w <= coast_range.y;
          BRANCH
          if (face_coast) {
            float dx = 0.0;
            float dy = 0.0;
            dx = tex2Dlod(shore_distance_field_tex, float4(dftc+float2(distance_field_texture_size_inv,0),0,0)).w-sdf.w;
            dy = tex2Dlod(shore_distance_field_tex, float4(dftc+float2(0,distance_field_texture_size_inv),0,0)).w-sdf.w;
            shoreRotation = atan2(-dy,dx);
          }
        }
      ##endif

      placeAllowed = placeAllowed && get_terraform_removal(worldPos);
      BRANCH
      if (placeAllowed && lodNo < MAX_LODS)
##endif
      {
        float3 surfaceNormal = float3(0, 1, 0);
        float3 displacement = get_displacement(coords, surfaceNormal);
        ##if tex_hmap_low != NULL
          float2 tc_low = worldPos.xz*world_to_hmap_low.xy + world_to_hmap_low.zw;
          if (tc_low.x < 0 || tc_low.y < 0 || tc_low.x > 1 || tc_low.y > 1)
            seedMultiplier = -1;
          float landHeight = getWorldHeight(coords + displacement.xz) + displacement.y;
        ##else
          float landHeight = 0;
          #if HAS_LAND_MASK_TEXCOORD
            bool outOfGrassHeightRange;
            float2 grassHeightTc = get_land_mask_tc(coords + displacement.xz, outOfGrassHeightRange);
            if (!outOfGrassHeightRange)
              landHeight = get_land_height(grassHeightTc);
            else
              seedMultiplier = -1; // no meaningful height information available
          #else
            seedMultiplier = -1; // no height data
          #endif
        ##endif
        if (gpu_objects_place_on_water)
        {
          worldPos = float3(coords.x + displacement.x, water_level, coords.y + displacement.z);
          surfaceNormal = float3(0, 1, 0);
          if (landHeight > water_level)
            seedMultiplier = -1;
        }
        else
        {
          if (checkHeightmapHoles(worldPos))
            seedMultiplier = -1;
          apply_renderinst_hmap_ofs(worldPos.xz, landHeight);
          worldPos = float3(coords.x + displacement.x, landHeight, coords.y + displacement.z);
          #if !GET_DISPLACEMENT_GIVES_NORMALS
          surfaceNormal = getWorldNormal(worldPos);
          #endif
        }
        float3 inclineDelta = (normalize(frac(worldPos) * 2 - 1)) * up_vector.w;
        float3 upDirection = (dot(up_vector.xyz, 1) == 0) ? surfaceNormal : up_vector.xyz;

        float inclineFactor = saturate(gpu_objects_slope_factor.x*(dot(surfaceNormal, float3(0, 1, 0)) - gpu_objects_slope_factor.y));
        inclineFactor = gpu_objects_slope_factor.z > 0 ? inclineFactor : 1 - inclineFactor;
        inclineFactor = gpu_objects_slope_factor.w == 0 ? 1 : inclineFactor;

        float weight = rand(coords);
        bool weightAccepted = (weight >= gpu_objects_weights.x && weight < gpu_objects_weights.y);

        ##if gpu_objects_gpu_instancing == on
          if (!testSphereB(worldPos, 3)) // todo: test actual object radius, for now 3m is far enough
            weightAccepted = false;
        ##endif

        BRANCH
        if (inclineFactor*seedMultiplier > frac(10.345*randValues.y) && weightAccepted)
        {
          float3 dir = normalize(upDirection + inclineDelta);
          float scale = lerp(scale_range.x, scale_range.y, randValues.y);
          float rotate = lerp(rotate_range.x, rotate_range.y, randValues.x) + shoreRotation;
          float4 color = lerp(color_from, color_to,  float4(randValues.x, randValues.y,
            (randValues.x + randValues.y) * 0.5, fmod(randValues.y * 255, randValues.x)));
          addInstance(worldPos, dir, rotate, scale, bboxMin, bboxMax, grid_parameters.w, cell_buffer_offset, lodNo, color);
        }
      }
    ##if gpu_objects_gpu_instancing == off
      bboxes[grp_idx * 2] = bboxMin;
      bboxes[grp_idx * 2 + 1] = bboxMax;
      GroupMemoryBarrierWithGroupSync();
      for (uint i = 8; i > 0; i >>= 1)
      {
        if (grp_idx < i)
        {
          bboxes[grp_idx * 2] = min(bboxes[grp_idx * 2], bboxes[(grp_idx + i) * 2]);
          bboxes[grp_idx * 2 + 1] = max(bboxes[grp_idx * 2 + 1], bboxes[(grp_idx + i) * 2 + 1]);
        }
      }
      if (grp_idx == 0)
      {
        countersBuffer.InterlockedMin(4 * grid_parameters.w, uint(gpu_objects_weights.z));
        BRANCH
        if (all(bboxes[0].xyz < bboxes[1].xyz))
        {
          int4 iBboxMin = int4(bboxes[0] * GPU_OBJ_HLSL_ENCODE_VAL);
          int4 iBboxMax = int4(bboxes[1] * GPU_OBJ_HLSL_ENCODE_VAL);
          InterlockedMin(structuredBufferAt(bboxesBuffer, group_bbox_offset + 0), iBboxMin.x);
          InterlockedMin(structuredBufferAt(bboxesBuffer, group_bbox_offset + 1), iBboxMin.y);
          InterlockedMin(structuredBufferAt(bboxesBuffer, group_bbox_offset + 2), iBboxMin.z);
          //+3 is unused, it maps to bbox3f.bmin.w
          InterlockedMax(structuredBufferAt(bboxesBuffer, group_bbox_offset + 4), iBboxMax.x);
          InterlockedMax(structuredBufferAt(bboxesBuffer, group_bbox_offset + 5), iBboxMax.y);
          InterlockedMax(structuredBufferAt(bboxesBuffer, group_bbox_offset + 6), iBboxMax.z);
          //+7 is unused, it maps to bbox3f.bmax.w
        }
      }
    ##endif
    }
##else // shader == gpu_objects_on_rendinst_cs
    [numthreads(DISPATCH_WARP_SIZE, 1, 1)]
    void generate_objects_positions(uint2 thread_id : SV_DispatchThreadID, uint2 group_id : SV_GroupID)
    {
      uint start_index = mesh_params.x;
      uint num_faces = mesh_params.y;
      uint base_vertex = mesh_params.z;
      uint stride = mesh_params.w;
      uint instance_start = instance_offset__counts.x;
      uint num_per_rendinst = instance_offset__counts.y;
      uint num_for_placing = min(structuredBufferAt(num_objects, 0), num_per_rendinst);
      uint instance_id = group_id.y;

      float3 worldLocalX = instanceBuf[(instance_start + instance_id) * 4 + 0].xyz;
      float3 worldLocalY = instanceBuf[(instance_start + instance_id) * 4 + 1].xyz;
      float3 worldLocalZ = instanceBuf[(instance_start + instance_id) * 4 + 2].xyz;
      float4 worldPos_instanceIdx = instanceBuf[(instance_start + instance_id) * 4 + 3];
      float3 worldLocalPos = worldPos_instanceIdx.xyz;
      uint buffer_offset = uint(worldPos_instanceIdx.w) * num_per_rendinst;

      uint area_seed = thread_id.x + uint(frac(worldLocalPos.x) * 128) + uint(frac(worldLocalPos.z) * 128 * 128);
      area_seed %= 128*128;
      int2 tci = int2(area_seed % 128, area_seed / 128);
      float3 randValues;
      randValues.xy = texelFetch(noise_128_tex_hash, tci, 0).rg;
      randValues.z = rand(randValues.xy);

      float targetArea = structuredBufferAt(face_areas_doubled, num_faces - 1) * randValues.z;
      uint left = 0, right = num_faces - 1;
      int numIterations = ceil(log2(num_faces));
      for (int i = 0; i < numIterations; ++i) //same as `while (left < right)`, but want avoid looping for sure
      {
        uint middle = (left + right) >> 1;
        float area = structuredBufferAt(face_areas_doubled, middle);
        if (area > targetArea)
          right = middle;
        else
          left = middle + 1;
      }
      uint face_id = left;

      float3 v1, v2, v3;
      float3 n1, n2, n3;
      load_mesh_triangle(start_index, face_id, base_vertex, stride, v1, v2, v3, n1, n2, n3);

      float3 center = (v1 + v2 + v3) * (1.0/3);
      float2 randomSeed = float2(seed / 128, (uint)seed % 128);
      randValues.xy = tex2Dlod(noise_128_tex_hash, float4(worldLocalPos.xz + center.xz + thread_id.xx * (1.0/128) + randomSeed, 0.0, 0.0)).rg;
      float2 clippedRand = dot(randValues.xy, 1) > 1 ? 1 - randValues.xy : randValues.xy;

      float3 localPos = (1 - dot(clippedRand, 1)) * v1 + clippedRand.x * v2 + clippedRand.y * v3;
      float3 localNormal = normalize((n1 + n2 + n3) * (1.0/3));
      //flloat3 localNormal = normalize(cross(v2 - v1, v3 - v1));

      float3 worldPos = localPos.x * worldLocalX + localPos.y * worldLocalY + localPos.z * worldLocalZ + worldLocalPos;
      float3 worldNormal = normalize(localNormal.x * worldLocalX + localNormal.y * worldLocalY + localNormal.z * worldLocalZ);

      float weight = rand3(worldPos);
      bool weightAccepted = (weight >= gpu_objects_weights.x && weight < gpu_objects_weights.y);

      BRANCH
      if (thread_id.x < num_for_placing && weightAccepted)
      {
        float noise_gamma = placing_params.y;
        float noise_tile = placing_params.z;
        float noise_threshold = placing_params.w;
        float noise = tex3Dlod(perlin_noise3d, float4(noise_tile * worldPos * (1. / 4), 0)).r;

        BRANCH
        if (thread_id.x < num_for_placing && (noise_gamma == 0 || (pow(noise, noise_gamma) < noise_threshold)))
        {
          float3 dir = worldNormal;

          float scale = lerp(scale_range.x, scale_range.y, randValues.y);
          float rotate = lerp(rotate_range.x, rotate_range.y, randValues.x);
          float4 color = lerp(color_from, color_to,  float4(randValues.x, randValues.y,
            (randValues.x + randValues.y) * 0.5, fmod(randValues.y * 255, randValues.x)));
          float4 bboxMin = 0; //not used
          float4 bboxMax = 0; //not used
          addInstance(worldPos, dir, rotate, scale, bboxMin, bboxMax, uint(worldPos_instanceIdx.w), buffer_offset, 0, color);
        }
      }

      GroupMemoryBarrierWithGroupSync();
      if (thread_id.x == 0)
      {
        countersBuffer.InterlockedMin(4 * uint(worldPos_instanceIdx.w), num_per_rendinst);
      }
    }
##endif
  }
  compile("cs_5_0", "generate_objects_positions");
}

shader gpu_obj_clear_counter_and_bbox_cs
{
  (cs)
  {
    group_idx@f1 = (gpu_objects_group_idx);
    gpu_object_ints_to_clear@i2 = (gpu_object_ints_to_clear);
  }
  ENABLE_ASSERT(cs)
  hlsl(cs)
  {
    #include "gpuObjects/gpu_objects_const.hlsli"
    RWStructuredBuffer<int> bboxesBuffer : register(u1);
    RWByteAddressBuffer cellCount : register(u2);

    [numthreads(GPU_OBJ_BBOX_CLEANER_SIZE, 1, 1)]
    void main(uint dispatch_thread_id : SV_DispatchThreadID)
    {
      BRANCH
      if (dispatch_thread_id == 0)
        storeBuffer(cellCount, 4 * group_idx, 0u);
      BRANCH
      if (dispatch_thread_id >= gpu_object_ints_to_clear.y)
        return;
      const int VERY_LARGE_INT = 0x7FFFFFFF;
      int value = (dispatch_thread_id / 4) % 2 == 0 ? VERY_LARGE_INT : -VERY_LARGE_INT;
      structuredBufferAt(bboxesBuffer, gpu_object_ints_to_clear.x + dispatch_thread_id) = value;
    }
  }
  compile("cs_5_0", "main");
}


shader gpu_objects_on_rendinst_clean_cs
{
  GPU_OBJECTS_CS_INSTANCE_DATA_BUFFER()

  (cs) {
    count@f1 = (gpu_objects_num_for_placing);
  }

  hlsl(cs) {
    #include "gpuObjects/gpu_objects_const.hlsli"
    RWBuffer<uint> counters : register(u1);

    [numthreads(DISPATCH_WARP_SIZE, 1, 1)]
    void bbox_fill(uint thread_id : SV_DispatchThreadID)
    {
      if (thread_id < count)
      {
        uint idx = instanceBuf[thread_id * 4 + 3].w;
        counters[idx] = 0;
      }
    }
  }
  compile("cs_5_0", "bbox_fill");
}

int gpu_objects_gather_target_offset;
int gpu_objects_max_count_in_cell;
int gpu_objects_visible_cells;

shader gpu_objects_gather_matrices_cs
{
  (cs) {
    copy_parameters@i3 = (gpu_objects_gather_target_offset, gpu_objects_max_count_in_cell, gpu_objects_visible_cells, gpu_objects_visible_cells);
  }
  hlsl(cs) {
    #define target_offset copy_parameters.x
    #define max_in_cell copy_parameters.y
    #define visible_cells copy_parameters.z

    #include "gpuObjects/gpu_objects_const.hlsli"
    RWBuffer<float4> targetBuffer : register(u0);
    Buffer<uint2> offsets : register(t0);
    Buffer<float4> matrices : register(t1);

    [numthreads(DISPATCH_WARP_SIZE_XY, DISPATCH_WARP_SIZE_XY, 1)]
    void gather_matrices(uint2 thread_id : SV_DispatchThreadID)
    {
      if (visible_cells <= thread_id.x)
        return;
      uint matricesInCell = offsets[thread_id.x + 1].x - offsets[thread_id.x].x;
      if (matricesInCell <= thread_id.y)
        return;
      uint matrixOffset = (offsets[thread_id.x].y * max_in_cell + thread_id.y) * ROWS_IN_MATRIX;
      uint targetOffset = target_offset + (offsets[thread_id.x].x + thread_id.y) * ROWS_IN_MATRIX;
      targetBuffer[targetOffset + 0] = matrices[matrixOffset + 0];
      targetBuffer[targetOffset + 1] = matrices[matrixOffset + 1];
      targetBuffer[targetOffset + 2] = matrices[matrixOffset + 2];
      targetBuffer[targetOffset + 3] = matrices[matrixOffset + 3];
    }
  }
  compile("cs_5_0", "gather_matrices");
}


include "shader_global.sh"
include "hero_matrix_inc.sh"
include "reprojected_motion_vectors.sh"
include "gbuffer.sh"
include "viewVecVS.sh"
include "monteCarlo.sh"
include "alternate_reflections.sh"
include "ssr_common.sh"

buffer ssr_counters;
buffer ssr_ray_list;
buffer ssr_tile_list;

texture blue_noise_tex;
texture ssr_reflection_tex;
texture ssr_raylen_tex;
texture ssr_reflection_history_tex;
texture ssr_reproj_reflection_tex;
texture ssr_avg_reflection_tex;

texture ssr_variance_tex;
texture ssr_sample_count_tex;

texture prev_downsampled_far_depth_tex;

float4 analytic_light_sphere_pos_r=(0,0,0,0);
float4 analytic_light_sphere_color=(1,0,0,1);

macro INIT_TEXTURES(code)
  INIT_READ_GBUFFER_BASE(code)
  INIT_READ_DEPTH_GBUFFER_BASE(code)
  INIT_READ_MOTION_BUFFER_BASE(code)
  hlsl(code) {
    #define depth_tex depth_gbuf_read
    #define depth_tex_samplerstate depth_gbuf_read_samplerstate
    #define normals_tex normal_gbuf_read
    #define normals_tex_samplerstate normal_gbuf_read_samplerstate
  }
endmacro

macro SSR_COMMON(code)
  ENABLE_ASSERT(code)
  VIEW_VEC_OPTIMIZED(code)
  INIT_HERO_MATRIX(code)
  USE_HERO_MATRIX(code)
  INIT_REPROJECTED_MOTION_VECTORS(code)
  USE_REPROJECTED_MOTION_VECTORS(code)
  INIT_TEXTURES(code)
  USE_MOTION_VEC_DECODE(code)

  (code) {
    world_view_pos@f4 = world_view_pos;
    ssr_world_view_pos@f4 = ssr_world_view_pos;
    prev_frame_tex@smp2d = prev_frame_tex;
    SSRParams@f4 = (SSRParams.x, SSRParams.y, ssr_frameNo.z, ssr_frameNo.y);
    ssr_target_size@f4 = ssr_target_size;

    prev_globtm_no_ofs_psf@f44 = { prev_globtm_no_ofs_psf_0, prev_globtm_no_ofs_psf_1, prev_globtm_no_ofs_psf_2, prev_globtm_no_ofs_psf_3 };
    globtm_no_ofs_psf@f44 = { globtm_no_ofs_psf_0, globtm_no_ofs_psf_1, globtm_no_ofs_psf_2, globtm_no_ofs_psf_3 };
    analytic_light_sphere_pos_r@f4 = analytic_light_sphere_pos_r;
    analytic_light_sphere_color@f4 = analytic_light_sphere_color;
  }

  (cs) {
    downsampled_close_depth_tex@tex = downsampled_close_depth_tex hlsl { Texture2D<float> downsampled_close_depth_tex@tex; }
    downsampled_depth_mip_count@f1 = (downsampled_depth_mip_count);
    lowres_rt_params@f2 = (lowres_rt_params.x, lowres_rt_params.y, 0, 0); //Far and Close depth are the same size
  }

  hlsl(code) {
    #define COMPUTE_GRP_SIZE_X 8
    #define COMPUTE_GRP_SIZE_Y 8
    #define SSR_QUALITY 4

    #define SSR_FFX
    #define FFX_SSSR_INVERTED_DEPTH_RANGE
    #include "../../../3rdPartyLibs/ssr/ffx_sssr.h"

    #define ssr_depth depth_tex
    #define SSR_MOTIONREPROJ 1
    #define CHECK_VALID_MOTION_VECTOR(a) true
    #define REPROJECT_TO_PREV_SCREEN 1
    #define MOTION_VECTORS_TEXTURE motion_gbuf_read

    #define MAX_ACCUM_SAMPLES 32.0
    #define COMPRESS_SAMPLE_COUNT(x) saturate((x) / MAX_ACCUM_SAMPLES)
    #define DECOMPRESS_SAMPLE_COUNT(x) ((x) * MAX_ACCUM_SAMPLES)

    #define COMPRESS_VARIANCE(x) saturate((x) * 0.05)
    #define DECOMPRESS_VARIANCE(x) ((x) * 20.0)

    bool IsGlossyReflection(float roughness) { return roughness < 0.7; }
    bool IsMirrorReflection(float roughness) { return roughness < 0.001; }

    void unpack_material(float2 texcoord, out half3 normal, out half linear_roughness, out float smoothness)
    {
      half4 normal_smoothness = tex2Dlod(normals_tex, float4(texcoord, 0, 0));
      normal = normalize(normal_smoothness.xyz * 2 - 1);
      smoothness = tex2Dlod(material_gbuf_read, float4(texcoord, 0, 0)).x;
      linear_roughness = linearSmoothnessToLinearRoughness(smoothness);
    }

    uint PackRayCoords(uint2 ray_coord, bool copy_horizontal, bool copy_vertical, bool copy_diagonal)
    {
      uint ray_x_15bit = ray_coord.x & ((1u << 15u) - 1u);
      uint ray_y_14bit = ray_coord.y & ((1u << 14u) - 1u);
      uint copy_horizontal_1bit = copy_horizontal ? 1 : 0;
      uint copy_vertical_1bit = copy_vertical ? 1 : 0;
      uint copy_diagonal_1bit = copy_diagonal ? 1 : 0;

      uint packed = (copy_diagonal_1bit << 31) | (copy_vertical_1bit << 30) |
                    (copy_horizontal_1bit << 29) | (ray_y_14bit << 15) | (ray_x_15bit << 0);
      return packed;
    }

    void UnpackRayCoords(uint packed,
                         out uint2 ray_coord, out bool copy_horizontal, out bool copy_vertical, out bool copy_diagonal)
    {
      ray_coord.x = (packed >> 0) & ((1u << 15u) - 1u);
      ray_coord.y = (packed >> 15) & ((1u << 14u) - 1u);
      copy_horizontal = (packed >> 29) & 1;
      copy_vertical = (packed >> 30) & 1;
      copy_diagonal = (packed >> 31) & 1;
    }

    uint bitfieldExtract(uint src, uint off, uint bits){ uint mask=(1U<<bits)-1;return (src>>off)&mask; }
    uint bitfieldInsert(uint src, uint ins, uint bits){ uint mask=(1U<<bits)-1;return (ins&mask)|(src&(~mask)); }

    //  LANE TO 8x8 MAPPING
    //  ===================
    //  00 01 08 09 10 11 18 19
    //  02 03 0a 0b 12 13 1a 1b
    //  04 05 0c 0d 14 15 1c 1d
    //  06 07 0e 0f 16 17 1e 1f
    //  20 21 28 29 30 31 38 39
    //  22 23 2a 2b 32 33 3a 3b
    //  24 25 2c 2d 34 35 3c 3d
    //  26 27 2e 2f 36 37 3e 3f
    uint2 RemapLane8x8(uint lane)
    {
        return uint2(bitfieldInsert(bitfieldExtract(lane, 2, 3), lane, 1),
                     bitfieldInsert(bitfieldExtract(lane, 3, 3), bitfieldExtract(lane, 1, 2), 2));
    }

    uint PackFloat16(float2 v)
    {
      uint2 p = f32tof16(v);
      return p.x | (p.y << 16);
    }

    half2 UnpackFloat16(uint a)
    {
        float2 tmp = f16tof32(uint2(a & 0xFFFF, a >> 16));
        return half2(tmp);
    }
  }

  INIT_ZNZFAR_STAGE(code)
  SSR_CALCULATE(code)
endmacro

shader ssr_classify
{
  INIT_RENDERING_RESOLUTION(cs)
  SSR_COMMON(cs)

  (cs) {
    variance_history@smp2d = ssr_variance_tex;
  }

  hlsl(cs) {
    RWStructuredBuffer<uint> out_ray_list                     : register(u0);
    RWStructuredBuffer<uint> out_tile_list                    : register(u1);
    globallycoherent RWStructuredBuffer<uint> out_ray_counter : register(u2);

    static const bool g_temporal_variance_guided_tracing_enabled = true;
    static const float g_temporal_variance_threshold = 0.02;
    static const int g_samples_per_quad = 1;

    bool IsBaseRay(uint2 dispatch_thread_id) {
      switch (g_samples_per_quad) {
      case 1:
          return ((dispatch_thread_id.x & 1) | (dispatch_thread_id.y & 1)) == 0; // Deactivates 3 out of 4 rays
      case 2:
          return (dispatch_thread_id.x & 1) == (dispatch_thread_id.y & 1); // Deactivates 2 out of 4 rays. Keeps diagonal.
      default: // case 4:
          return true;
      }
    }

    void StoreRay(int index, uint2 ray_coord, bool copy_horizontal, bool copy_vertical, bool copy_diagonal)
    {
      structuredBufferAt(out_ray_list, index) = PackRayCoords(ray_coord, copy_horizontal, copy_vertical, copy_diagonal);
    }

    groupshared uint g_tileCount;

    [numthreads(COMPUTE_GRP_SIZE_X, COMPUTE_GRP_SIZE_Y, 1)]
    void classify_tiles( uint2 Groupid : SV_GroupID, uint2 DTid : SV_DispatchThreadID, uint GI : SV_GroupIndex )
    {
      uint2 group_thread_id = RemapLane8x8(GI);
      uint2 dispatch_thread_id = Groupid * 8 + group_thread_id;

      float2 curViewTc = saturate((dispatch_thread_id + float2(0.5, 0.5)) * rendering_res.zw);

      half3 normal;
      half linear_roughness;
      float smoothness;
      unpack_material(curViewTc, normal, linear_roughness, smoothness);

      /////////////////////////////////////////////////////////////////////////////////////////////

      g_tileCount = 0;

      bool is_first_lane_of_wave = WaveIsFirstLane();

      // Disable offscreen pixels
      bool needs_ray = !(dispatch_thread_id.x >= rendering_res.x || dispatch_thread_id.y >= rendering_res.y);

      float rawDepth = tex2Dlod(depth_tex, float4(curViewTc,0,0)).x;
      float w = linearize_z(rawDepth, zn_zfar.zw);

      // Dont shoot a ray on very rough surfaces.
      bool is_reflective_surface = (w < 0.5*zn_zfar.y);

      bool is_glossy_reflection = IsGlossyReflection(linear_roughness);
      needs_ray = needs_ray && is_glossy_reflection && is_reflective_surface;

      // Do not run the denoiser on mirror reflections.
      bool needs_denoiser = needs_ray && !IsMirrorReflection(linear_roughness);

      // Decide which ray to keep
      bool is_base_ray = IsBaseRay(dispatch_thread_id);

      needs_ray = needs_ray && (!needs_denoiser || is_base_ray); // Make sure to not deactivate mirror reflection rays.

      if (g_temporal_variance_guided_tracing_enabled && needs_denoiser && !needs_ray)
      {
        bool has_temporal_variance = DECOMPRESS_VARIANCE(texelFetch(variance_history, dispatch_thread_id, 0).x) > g_temporal_variance_threshold;
        needs_ray = needs_ray || has_temporal_variance;
      }

      GroupMemoryBarrierWithGroupSync(); // wait until g_tileCount is cleared

      BRANCH
      if (is_glossy_reflection && is_reflective_surface)
        InterlockedAdd(g_tileCount, 1);

      bool require_copy = !needs_ray && needs_denoiser;
      bool copy_horizontal = (g_samples_per_quad != 4) && is_base_ray && WaveReadLaneAt(uint(require_copy), WaveGetLaneIndex() ^ 1u); // QuadReadAcrossX
      bool copy_vertical = (g_samples_per_quad == 1) && is_base_ray && WaveReadLaneAt(uint(require_copy), WaveGetLaneIndex() ^ 2u); // QuadReadAcrossY
      bool copy_diagonal = (g_samples_per_quad == 1) && is_base_ray && WaveReadLaneAt(uint(require_copy), WaveGetLaneIndex() ^ 3u); // QuadReadAcrossDiagonal

      // Compact rays and append them all at once to the ray list
      uint local_ray_index_in_wave = WavePrefixCountBits(needs_ray);
      uint wave_ray_count = WaveActiveCountBits(needs_ray);
      uint base_ray_index;
      BRANCH
      if (is_first_lane_of_wave)
        InterlockedAdd(structuredBufferAt(out_ray_counter, 0), wave_ray_count, base_ray_index);
      base_ray_index = WaveReadLaneFirst(base_ray_index);
      if (needs_ray)
      {
        int ray_index = base_ray_index + local_ray_index_in_wave;
        StoreRay(ray_index, dispatch_thread_id, copy_horizontal, copy_vertical, copy_diagonal);
      }

      GroupMemoryBarrierWithGroupSync(); // Wait until g_tileCount is ready

      if (all(group_thread_id == 0) && g_tileCount > 0)
      {
        uint tile_offset;
        InterlockedAdd(structuredBufferAt(out_ray_counter, 2), 1, tile_offset);
        // Store 16-bit pixel coordinates
        structuredBufferAt(out_tile_list, tile_offset) = (((dispatch_thread_id.y & 0xffffu) << 16) | ((dispatch_thread_id.x & 0xffffu) << 0));
      }
    }
  }
  compile("cs_5_0", "classify_tiles");
}

shader ssr_prepare_indirect_args
{
  ENABLE_ASSERT(cs)
  hlsl(cs) {
    RWStructuredBuffer<uint> ray_counter  : register(u0);
    RWByteAddressBuffer indirect_args     : register(u1);

    [numthreads(1, 1, 1)]
    void prepare_indirect_args( uint2 Groupid : SV_GroupID, uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex )
    {
      { // Intersection args
        uint ray_count = structuredBufferAt(ray_counter, 0);

        storeBuffer(indirect_args, 4 * 0, (ray_count + 63) / 64);
        storeBuffer(indirect_args, 4 * 1, 1);
        storeBuffer(indirect_args, 4 * 2, 1);

        structuredBufferAt(ray_counter, 0) = 0;
        structuredBufferAt(ray_counter, 1) = ray_count;
      }
      { // Denoiser args
          uint tile_count = structuredBufferAt(ray_counter, 2);

          storeBuffer(indirect_args, 4 * 3, tile_count);
          storeBuffer(indirect_args, 4 * 4, 1);
          storeBuffer(indirect_args, 4 * 5, 1);

          structuredBufferAt(ray_counter, 2) = 0;
          structuredBufferAt(ray_counter, 3) = tile_count;
      }
    }
  }
  compile("cs_5_0", "prepare_indirect_args");
}

shader ssr_intersect
{
  SSR_COMMON(cs)
  GET_ALTERNATE_REFLECTIONS(cs)

  (cs) {
    ssr_counters@buf = ssr_counters hlsl { StructuredBuffer<uint> ssr_counters@buf; };
    ssr_ray_list@buf = ssr_ray_list hlsl { StructuredBuffer<uint> ssr_ray_list@buf; };
    blue_noise_tex@smp2d = blue_noise_tex;

    frame_index@f4 = (ssr_frameNo.x, 0, 0, 0);
  }

  hlsl(cs) {
    RWTexture2D<float4> out_reflection                    : register(u0);
    RWTexture2D<float> out_raylen                         : register(u1);

    #define GOLDEN_RATIO  1.61803398875

    float2 SampleRandomVector2D(uint2 pixel)
    {
      float2 E = texelFetch(blue_noise_tex, pixel % 128, 0).xy;
      return float2(frac(E.x + (uint(frame_index.x) & 0xFFu) * GOLDEN_RATIO),
                    frac(E.y + (uint(frame_index.x) & 0xFFu) * GOLDEN_RATIO));
    }

    [numthreads(COMPUTE_GRP_SIZE_X, COMPUTE_GRP_SIZE_Y, 1)]
    void intersect( uint Groupid : SV_GroupID, uint GI : SV_GroupIndex )
    {
      uint ray_index = Groupid * 64 + GI;
      if (ray_index >= structuredBufferAt(ssr_counters, 1)) return;
      uint packed_coords = structuredBufferAt(ssr_ray_list, ray_index);

      uint2 pixelPos;
      bool copy_horizontal, copy_vertical, copy_diagonal;
      UnpackRayCoords(packed_coords, pixelPos, copy_horizontal, copy_vertical, copy_diagonal);

      float2 screenCoordCenter = pixelPos + float2(0.5, 0.5);

      float2 curViewTc = saturate(screenCoordCenter * ssr_target_size.zw);
      float3 viewVect = getViewVecOptimized(curViewTc);

      half3 normal;
      half linear_roughness;
      float smoothness;
      unpack_material(curViewTc, normal, linear_roughness, smoothness);

      float rawDepth = tex2Dlod(depth_tex, float4(curViewTc,0,0)).x;
      float w = linearize_z(rawDepth, zn_zfar.zw) - 0.025;

      float3 originToPoint = viewVect * w;
      float3 worldPos = world_view_pos.xyz + originToPoint;
      float3 realWorldPos = ssr_world_view_pos.xyz + originToPoint;
      float3 N = normal;

      float4 newFrame = 0;
      float hitDist = 1000.0;

      float2 E = SampleRandomVector2D(pixelPos.xy);

      float3x3 tbnTransform = create_tbn_matrix(N);
      float3 viewDirTC = mul(-viewVect, tbnTransform);

      float3 sampledNormalTC = importance_sample_GGX_VNDF(E, viewDirTC, linear_roughness * linear_roughness);

      float3 reflectedDirTC = reflect(-viewDirTC, sampledNormalTC);
      float3 R = mul(reflectedDirTC, transpose(tbnTransform));

      float4 hit_uv_z_fade = hierarchRayMarch(float3(curViewTc, rawDepth), R, linear_roughness, w, originToPoint, 0, globtm_no_ofs_psf, 0);

      BRANCH if( hit_uv_z_fade.z != 0 )
      {
        hit_uv_z_fade.z = ssr_linearize_z(hit_uv_z_fade.z);
        newFrame = sample_vignetted_color( hit_uv_z_fade.xyz, 0, hit_uv_z_fade.z, originToPoint, R, worldPos);// * SSRParams.r;
        float3 capViewVect = getViewVecOptimized(hit_uv_z_fade.xy);
        float3 capturePoint = capViewVect * hit_uv_z_fade.z;
        hitDist = distance(originToPoint, capturePoint);
      }
      else
      {
        get_alternate_reflections(newFrame, pixelPos, originToPoint, normal, false, false);
      }

      // brdf has to be applied here
      newFrame.rgb *= brdf_G_GGX(N, originToPoint, linear_roughness);
      out_reflection[pixelPos] = float4(newFrame);
      out_raylen[pixelPos] = hitDist;

      uint2 copyTarget = pixelPos ^ 1; // flip last bit to find the mirrored coords along the x and y axis within a quad
      if (copy_horizontal)
      {
        uint2 copyCoords = uint2(copyTarget.x, pixelPos.y);
        out_reflection[copyCoords] = float4(newFrame);
        out_raylen[copyCoords] = hitDist;
      }
      if (copy_vertical)
      {
        uint2 copyCoords = uint2(pixelPos.x, copyTarget.y);
        out_reflection[copyCoords] = float4(newFrame);
        out_raylen[copyCoords] = hitDist;
      }
      if (copy_diagonal)
      {
        uint2 copyCoords = copyTarget;
        out_reflection[copyCoords] = float4(newFrame);
        out_raylen[copyCoords] = hitDist;
      }
    }
  }
  compile("cs_5_0", "intersect");
}

shader ssr_reproject
{
  if (motion_gbuf == NULL)
  {
    dont_render;
  }

  INIT_RENDERING_RESOLUTION(cs)
  SSR_COMMON(cs)

  (cs) {
    ssr_counters@buf = ssr_counters hlsl { StructuredBuffer<uint> ssr_counters@buf; };
    ssr_tile_list@buf = ssr_tile_list hlsl { StructuredBuffer<uint> ssr_tile_list@buf; };

    variance_history@smp2d = ssr_variance_tex;
    sample_count_history@smp2d = ssr_sample_count_tex;
    ssr_reflection_tex@smp2d = ssr_reflection_tex;
    ssr_raylen_tex@smp2d = ssr_raylen_tex;
    ssr_reflection_history_tex@smp2d = ssr_reflection_history_tex;

    prev_downsampled_far_depth_tex@smp2d = prev_downsampled_far_depth_tex;
  }

  hlsl(cs) {
    RWTexture2D<float4> out_reprojected         : register(u0);
    RWTexture2D<float4> out_avg_reflection      : register(u1);
    RWTexture2D<float> out_variance             : register(u2);
    RWTexture2D<unorm float> out_sample_count   : register(u3);

    groupshared uint g_shared_storage_0[16][16];
    groupshared uint g_shared_storage_1[16][16];

    void LoadIntoSharedMemory(int2 dispatch_thread_id, int2 group_thread_id)
    {
      // Load 16x16 region into shared memory using 4 8x8 blocks
      const int2 offset[4] = {int2(0, 0), int2(8, 0), int2(0, 8), int2(8, 8)};

      // Intermediate storage
      half4 refl[4];

      // Start from the upper left corner of 16x16 region
      dispatch_thread_id -= 4;

      // Load into registers
      for (int j = 0; j < 4; ++j)
        refl[j] = texelFetch(ssr_reflection_tex, dispatch_thread_id + offset[j], 0);

      // Move to shared memory
      for (int i = 0; i < 4; ++i)
      {
        int2 index = group_thread_id + offset[i];
        g_shared_storage_0[index.y][index.x] = PackFloat16(refl[i].xy);
        g_shared_storage_1[index.y][index.x] = PackFloat16(refl[i].zw);
      }
    }

    half4 LoadFromGroupSharedMemoryRaw(int2 idx)
    {
      return half4(UnpackFloat16(g_shared_storage_0[idx.y][idx.x]),
                   UnpackFloat16(g_shared_storage_1[idx.y][idx.x]));
    }

    #define GAUSSIAN_K 3.0

    #define LOCAL_NEIGHBORHOOD_RADIUS 4
    #define REPROJECTION_NORMAL_SIMILARITY_THRESHOLD 0.9999
    #define AVG_RADIANCE_LUMINANCE_WEIGHT 0.3
    #define REPROJECT_SURFACE_DISCARD_VARIANCE_WEIGHT 1.5
    #define DISOCCLUSION_NORMAL_WEIGHT 1.4
    #define DISOCCLUSION_DEPTH_WEIGHT 1.0
    #define DISOCCLUSION_THRESHOLD 0.9
    #define SAMPLES_FOR_ROUGHNESS(r) (1.0 - exp(-r * 100.0))

    half Luminance(half3 color) { return max(dot(color, half3(0.299, 0.587, 0.114)), 0.001); }

    half ComputeTemporalVariance(half3 history_radiance, half3 radiance)
    {
      half history_luminance = Luminance(history_radiance);
      half luminance = Luminance(radiance);
      half diff = abs(history_luminance - luminance) / max3(history_luminance, luminance, 0.5);
      return diff * diff;
    }

    half GetLuminanceWeight(half3 val)
    {
      half luma = Luminance(val.xyz);
      half weight = max(exp(-luma * AVG_RADIANCE_LUMINANCE_WEIGHT), 1.0e-2);
      return weight;
    }

    half LocalNeighborhoodKernelWeight(half i)
    {
      static const half radius = LOCAL_NEIGHBORHOOD_RADIUS + 1.0;
      return exp(-GAUSSIAN_K * (i * i) / (radius * radius));
    }

    struct moments_t
    {
      half4 mean;
      half4 variance;
    };

    moments_t EstimateLocalNeighbourhoodInGroup(int2 group_thread_id)
    {
      moments_t ret;
      ret.mean = 0;
      ret.variance = 0;

      half accumulated_weight = 0;
      for (int j = -LOCAL_NEIGHBORHOOD_RADIUS; j <= LOCAL_NEIGHBORHOOD_RADIUS; ++j)
      {
        for (int i = -LOCAL_NEIGHBORHOOD_RADIUS; i <= LOCAL_NEIGHBORHOOD_RADIUS; ++i)
        {
          int2 index = group_thread_id + int2(i, j);
          half4 radiance = LoadFromGroupSharedMemoryRaw(index);
          half weight = LocalNeighborhoodKernelWeight(i) * LocalNeighborhoodKernelWeight(j);
          accumulated_weight += weight;

          ret.mean += radiance * weight;
          ret.variance += radiance * radiance * weight;
        }
      }

      ret.mean /= accumulated_weight;
      ret.variance /= accumulated_weight;

      ret.variance = abs(ret.variance - ret.mean * ret.mean);

      return ret;
    }

    float2 GetHitPositionReprojection(int2 dispatch_thread_id, float2 uv, float reflected_ray_length)
    {
      float3 viewVect = getViewVecOptimized(uv);

      float rawDepth = tex2Dlod(depth_tex, float4(uv, 0, 0)).x;
      float w = linearize_z(rawDepth, zn_zfar.zw);

      float surface_depth = w;
      float ray_length = surface_depth + reflected_ray_length;

      float2 screen_pos;
      return get_reprojected_history_uv(viewVect * ray_length, prev_globtm_no_ofs_psf, screen_pos);
    }

    #define length2(x) dot(x, x)

    void PickReprojection(int2 dispatch_thread_id, int2 group_thread_id, uint2 screen_size,
                          half3 normal, half roughness, half ray_len, inout half disocclusion_factor, inout half2 reprojection_uv,
                          inout half4 reprojection)
    {
      moments_t local_neighborhood = EstimateLocalNeighbourhoodInGroup(group_thread_id);

      float2 uv = (float2(dispatch_thread_id) + 0.5) / rendering_res.xy;

      half3 history_normal;
      float history_linear_depth;

      float2 surf_repr_uv = uv + decode_motion_vector(tex2Dlod(motion_gbuf_read, float4(uv,0,0)).rg);
      half4 surf_history = tex2Dlod(ssr_reflection_history_tex, float4(surf_repr_uv, 0, 0));

      float2 hit_repr_uv = GetHitPositionReprojection(dispatch_thread_id, uv, ray_len);
      half4 hit_history = tex2Dlod(ssr_reflection_history_tex, float4(hit_repr_uv, 0, 0));

      half3 surf_normal, hit_normal;
      half surf_roughness, hit_roughness;
      float _unused;
      unpack_material(surf_repr_uv, surf_normal, surf_roughness, _unused);
      unpack_material(hit_repr_uv, hit_normal, hit_roughness, _unused);

      float hit_normal_similarity = dot(hit_normal, normal);
      float surf_normal_similarity = dot(surf_normal, normal);

      // Choose reprojection uv based on similarity to the local neighborhood
      if ((hit_normal_similarity > REPROJECTION_NORMAL_SIMILARITY_THRESHOLD &&
          hit_normal_similarity + 1.0e-3 > surf_normal_similarity &&
          abs(hit_roughness - roughness) < abs(surf_roughness - roughness) + 1.0e-3))
      {
        // Mirror reflection
        history_normal = hit_normal;
        history_linear_depth = linearize_z(tex2Dlod(prev_downsampled_far_depth_tex, float4(hit_repr_uv, 0, 0)).r, zn_zfar.zw);
        reprojection_uv = hit_repr_uv;
        reprojection = hit_history;
      }
      else
      {
        // Reject surface reprojection based on simple distance
        if (length2(surf_history.xyz - local_neighborhood.mean.xyz) <
            REPROJECT_SURFACE_DISCARD_VARIANCE_WEIGHT * length(local_neighborhood.variance))
        {
          // Surface reflection
          history_normal = surf_normal;
          history_linear_depth = linearize_z(tex2Dlod(prev_downsampled_far_depth_tex, float4(surf_repr_uv, 0, 0)).r, zn_zfar.zw);
          reprojection_uv = surf_repr_uv;
          reprojection = surf_history;
        }
        else
        {
          disocclusion_factor = 0.0;
          return;
        }
      }

      disocclusion_factor = 1;
    }

    [numthreads(COMPUTE_GRP_SIZE_X, COMPUTE_GRP_SIZE_Y, 1)]
    void reproject( uint Groupid : SV_GroupID, uint3 DTid : SV_DispatchThreadID, int2 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex )
    {
      uint packed_coords = structuredBufferAt(ssr_tile_list, Groupid);
      int2 dispatch_thread_id = int2(packed_coords & 0xffffu, (packed_coords >> 16) & 0xffffu) + GTid;
      int2 dispatch_group_id = dispatch_thread_id / 8;
      uint2 remapped_group_thread_id = RemapLane8x8(GI);
      uint2 remapped_dispatch_thread_id = dispatch_group_id * 8 + remapped_group_thread_id;

      LoadIntoSharedMemory(remapped_dispatch_thread_id, remapped_group_thread_id);

      GroupMemoryBarrierWithGroupSync();

      remapped_group_thread_id += 4; // center threads in shared memory

      half variance = 1.0;
      half sample_count = 0.0;

      float2 screenCoordCenter = remapped_dispatch_thread_id + float2(0.5,0.5);
      float2 curViewTc = saturate(screenCoordCenter*ssr_target_size.zw);

      half3 normal;
      half linear_roughness;
      float smoothness;
      unpack_material(curViewTc, normal, linear_roughness, smoothness);

      half4 refl = texelFetch(ssr_reflection_tex, remapped_dispatch_thread_id, 0);
      half ray_len = texelFetch(ssr_raylen_tex, remapped_dispatch_thread_id, 0).r;

      if (IsGlossyReflection(linear_roughness))
      {
        half disocclusion_factor;
        float2 reprojection_uv;
        half4 reprojection;
        PickReprojection(remapped_dispatch_thread_id, remapped_group_thread_id, ssr_target_size.xy, normal,
                         linear_roughness, ray_len, disocclusion_factor, reprojection_uv, reprojection);

        if (all(reprojection_uv > 0) && all(reprojection_uv < 1))
        {
          half prev_variance = DECOMPRESS_VARIANCE(tex2Dlod(variance_history, float4(reprojection_uv, 0, 0)).x);
          sample_count = DECOMPRESS_SAMPLE_COUNT(tex2Dlod(sample_count_history, float4(reprojection_uv, 0, 0)).x) * disocclusion_factor;
          half s_max_samples = max(8.0, MAX_ACCUM_SAMPLES * SAMPLES_FOR_ROUGHNESS(linear_roughness));
          sample_count = min(s_max_samples, sample_count + 1);
          half new_variance = ComputeTemporalVariance(refl.xyz, reprojection.xyz);
          if (disocclusion_factor < DISOCCLUSION_THRESHOLD)
          {
            out_reprojected[remapped_dispatch_thread_id] = 0;
            out_variance[remapped_dispatch_thread_id] = COMPRESS_VARIANCE(1);
            out_sample_count[remapped_dispatch_thread_id] = COMPRESS_SAMPLE_COUNT(2);
          }
          else
          {
            half variance_mix = lerp(new_variance, prev_variance, 1.0 / sample_count);
            out_reprojected[remapped_dispatch_thread_id] = reprojection;
            out_variance[remapped_dispatch_thread_id] = variance_mix;
            out_sample_count[remapped_dispatch_thread_id] = COMPRESS_SAMPLE_COUNT(sample_count);
            // Mix in reprojection for radiance mip computation
            refl = lerp(refl, reprojection, 0.3);
          }
        }
        else
        {
          out_reprojected[remapped_dispatch_thread_id] = 0;
          out_variance[remapped_dispatch_thread_id] = COMPRESS_VARIANCE(1);
          out_sample_count[remapped_dispatch_thread_id] = COMPRESS_SAMPLE_COUNT(1);
        }
      }

      ////////////////////////////////////////

      // Downsample 8x8 -> 1 radiance using shared memory
      // Initialize shared array for downsampling
      half weight = GetLuminanceWeight(refl.xyz);
      refl *= weight;
      if (any(remapped_dispatch_thread_id >= ssr_target_size.xy) || any(isinf(refl)) || any(isnan(refl)) || weight > 1.0e3)
      {
        refl = 0;
        weight = 0;
      }

      remapped_group_thread_id -= 4;

      g_shared_storage_0[remapped_group_thread_id.y][remapped_group_thread_id.x] = PackFloat16(refl.xy);
      g_shared_storage_1[remapped_group_thread_id.y][remapped_group_thread_id.x] = PackFloat16(half2(refl.z, weight));

      GroupMemoryBarrierWithGroupSync();

      for (int i = 2; i <= 8; i = i * 2)
      {
        int ox = int(remapped_group_thread_id.x) * i;
        int oy = int(remapped_group_thread_id.y) * i;
        int ix = int(remapped_group_thread_id.x) * i + i / 2;
        int iy = int(remapped_group_thread_id.y) * i + i / 2;
        if (ix < 8 && iy < 8)
        {
          half4 rad_weight00 = LoadFromGroupSharedMemoryRaw(int2(ox, oy));
          half4 rad_weight10 = LoadFromGroupSharedMemoryRaw(int2(ox, iy));
          half4 rad_weight01 = LoadFromGroupSharedMemoryRaw(int2(ix, oy));
          half4 rad_weight11 = LoadFromGroupSharedMemoryRaw(int2(ix, iy));
          half4 sum = rad_weight00 + rad_weight01 + rad_weight10 + rad_weight11;

          g_shared_storage_0[remapped_group_thread_id.y][remapped_group_thread_id.x] = PackFloat16(sum.xy);
          g_shared_storage_1[remapped_group_thread_id.y][remapped_group_thread_id.x] = PackFloat16(sum.zw);
        }
        GroupMemoryBarrierWithGroupSync();
      }

      if (all(remapped_group_thread_id == 0))
      {
        half4 sum = LoadFromGroupSharedMemoryRaw(int2(0, 0));
        half weight_acc = max(sum.w, 1.0e-3);
        half3 radiance_avg = sum.xyz / weight_acc;

        out_avg_reflection[remapped_dispatch_thread_id / 8] = float4(radiance_avg, 0);
      }
    }
  }
  compile("cs_5_0", "reproject");
}

shader ssr_prefilter
{
  INIT_RENDERING_RESOLUTION(cs)
  SSR_COMMON(cs)

  (cs) {
    ssr_counters@buf = ssr_counters hlsl { StructuredBuffer<uint> ssr_counters@buf; };
    ssr_tile_list@buf = ssr_tile_list hlsl { StructuredBuffer<uint> ssr_tile_list@buf; };

    ssr_reflection_tex@tex = ssr_reflection_tex hlsl { Texture2D<float4> ssr_reflection_tex@tex; }
    ssr_variance_tex@tex = ssr_variance_tex hlsl { Texture2D<float> ssr_variance_tex@tex; }
    ssr_avg_reflection_tex@smp2d = ssr_avg_reflection_tex;
  }

  hlsl(cs) {
    RWTexture2D<float4> out_reflection          : register(u0);
    RWTexture2D<float> out_variance             : register(u1);

    groupshared uint g_shared_storage_0[16][16];
    groupshared uint g_shared_storage_1[16][16];

    groupshared uint g_shared_0[16][16];
    groupshared uint g_shared_1[16][16];
    groupshared uint g_shared_2[16][16];
    groupshared uint g_shared_3[16][16];
    groupshared float g_shared_depth[16][16];

    struct neighborhood_sample_t {
        half4 radiance;
        half3 normal;
        half variance;
        float depth;
    };

    neighborhood_sample_t LoadFromSharedMemory(int2 idx)
    {
      neighborhood_sample_t ret;
      ret.radiance.xy = UnpackFloat16(g_shared_0[idx.y][idx.x]);
      ret.radiance.zw = UnpackFloat16(g_shared_1[idx.y][idx.x]);
      ret.normal.xy = UnpackFloat16(g_shared_2[idx.y][idx.x]);
      half2 temp = UnpackFloat16(g_shared_3[idx.y][idx.x]);
      ret.normal.z = temp.x;
      ret.variance = temp.y;
      ret.depth = g_shared_depth[idx.y][idx.x];
      return ret;
    }

    void StoreInSharedMemory(int2 idx, float4 radiance, float variance, float3 normal, float depth)
    {
      g_shared_0[idx.y][idx.x] = PackFloat16(radiance.xy);
      g_shared_1[idx.y][idx.x] = PackFloat16(radiance.zw);
      g_shared_2[idx.y][idx.x] = PackFloat16(normal.xy);
      g_shared_3[idx.y][idx.x] = PackFloat16(float2(normal.z, variance));
      g_shared_depth[idx.y][idx.x] = depth;
    }

    void LoadWithOffset(int2 dispatch_thread_id, int2 _offset,
                        out float4 radiance, out float variance, out float3 normal, out float depth)
    {
      dispatch_thread_id += _offset;
      radiance = texelFetch(ssr_reflection_tex, dispatch_thread_id, 0);
      variance = DECOMPRESS_VARIANCE(texelFetch(ssr_variance_tex, dispatch_thread_id, 0));

      normal = texelFetch(normals_tex, dispatch_thread_id, 0).xyz;
      normal = normalize(normal * 2 - 1);

      depth = texelFetch(depth_tex, dispatch_thread_id, 0).r;
    }

    void StoreWithOffset(int2 group_thread_id, int2 _offset, float4 radiance, float variance, float3 normal, float depth)
    {
      group_thread_id += _offset;
      StoreInSharedMemory(group_thread_id, radiance, variance, normal, depth);
    }

    void InitSharedMemory(int2 dispatch_thread_id, int2 group_thread_id)
    {
      // Load 16x16 region into shared memory.
      const int2 offset[4] = {int2(0, 0), int2(8, 0), int2(0, 8), int2(8, 8)};

      half4 radiance[4];
      half variance[4];
      half3 normal[4];
      float depth[4];

      /// XA
      /// BC

      dispatch_thread_id -= 4; // 1 + 3 => additional band + left band

      UNROLL
      for (int i = 0; i < 4; ++i)
        LoadWithOffset(dispatch_thread_id, offset[i], radiance[i], variance[i], normal[i], depth[i]);

      UNROLL
      for (int j = 0; j < 4; ++j)
        StoreWithOffset(group_thread_id, offset[j], radiance[j], variance[j], normal[j], depth[j]);
    }

    #define RADIANCE_WEIGHT_BIAS 0.6
    #define RADIANCE_WEIGHT_VARIANCE_K 0.1
    #define PREFILTER_VARIANCE_BIAS 0.1
    #define PREFILTER_VARIANCE_WEIGHT 4.4

    #define PREFILTER_NORMAL_SIGMA 65.0 // 512.0
    #define PREFILTER_DEPTH_SIGMA 4.0

    static const float RoughnessSigmaMin = 0.001;
    static const float RoughnessSigmaMax = 0.01;

    float GetEdgeStoppingNormalWeight(half3 normal_p, half3 normal_q, float sigma)
    {
      return pow(clamp(dot(normal_p, normal_q), 0.0, 1.0), sigma);
    }

    /*float GetEdgeStoppingRoughnessWeight(float roughness_p, float roughness_q, float sigma_min, float sigma_max)
    {
      return 1.0 - smoothstep(sigma_min, sigma_max, abs(roughness_p - roughness_q));
    }*/

    half GetEdgeStoppingNormalWeight(half3 normal_p, half3 normal_q)
    {
      return pow(saturate(dot(normal_p, normal_q)), PREFILTER_NORMAL_SIGMA);
    }

    half GetEdgeStoppingDepthWeight(float center_depth, float neighbor_depth)
    {
      return exp(-abs(center_depth - neighbor_depth) * center_depth * PREFILTER_DEPTH_SIGMA);
    }

    half GetRadianceWeight(half3 center_radiance, half3 neighbor_radiance, half variance)
    {
        return max(exp(-(RADIANCE_WEIGHT_BIAS + variance * RADIANCE_WEIGHT_VARIANCE_K) * length(center_radiance - neighbor_radiance)), 1.0e-2);
    }

    void Resolve(int2 group_thread_id, half3 avg_radiance, neighborhood_sample_t center,
                 out half4 resolved_radiance, out half resolved_variance)
    {
      // Initial weight is important to remove fireflies.
      // That removes quite a bit of energy but makes everything much more stable.
      half accumulated_weight = GetRadianceWeight(avg_radiance.xyz, center.radiance.xyz, center.variance);
      half4 accumulated_radiance = center.radiance * accumulated_weight;
      half accumulated_variance = center.variance * accumulated_weight * accumulated_weight;
      // First 15 numbers of Halton(2, 3) streteched to [-3, 3]
      static const uint sample_count = 15;
      static const int2 sample_offsets[] =
      {
        int2(0, 1),
        int2(-2, 1),
        int2(2, -3),
        int2(-3, 0),
        int2(1, 2),
        int2(-1, -2),
        int2(3, 0),
        int2(-3, 3),
        int2(0, -3),
        int2(-1, -1),
        int2(2, 1),
        int2(-2, -2),
        int2(1, 0),
        int2(0, 2),
        int2(3, -1)
      };
      half variance_weight = max(PREFILTER_VARIANCE_BIAS, 1.0 - exp(-(center.variance * PREFILTER_VARIANCE_WEIGHT)));

      for (int i = 0; i < sample_count; ++i)
      {
        int2 new_idx = group_thread_id + sample_offsets[i];
        neighborhood_sample_t neighbor = LoadFromSharedMemory(new_idx);

        half weight = neighbor.radiance.w;
        weight *= GetEdgeStoppingNormalWeight(center.normal.xyz, neighbor.normal.xyz);
        //weight *= GetEdgeStoppingRoughnessWeight(center.normal.w, neighbor.normal.w, RoughnessSigmaMin, RoughnessSigmaMax);
        weight *= GetEdgeStoppingDepthWeight(center.depth, neighbor.depth);
        weight *= GetRadianceWeight(avg_radiance, neighbor.radiance.xyz, center.variance);
        weight *= variance_weight;

        // Accumulate all contributions
        accumulated_weight += weight;
        accumulated_radiance += weight * neighbor.radiance;
        accumulated_variance += weight * weight * neighbor.variance;
      }

      accumulated_radiance /= accumulated_weight;
      accumulated_variance /= (accumulated_weight * accumulated_weight);

      resolved_radiance = accumulated_radiance;
      resolved_variance = accumulated_variance;
    }

    [numthreads(COMPUTE_GRP_SIZE_X, COMPUTE_GRP_SIZE_Y, 1)]
    void prefilter( uint Groupid : SV_GroupID, uint3 DTid : SV_DispatchThreadID, int2 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex )
    {
      uint packed_coords = structuredBufferAt(ssr_tile_list, Groupid);
      int2 dispatch_thread_id = int2(packed_coords & 0xffffu, (packed_coords >> 16) & 0xffffu) + GTid;
      int2 dispatch_group_id = dispatch_thread_id / 8;
      uint2 remapped_group_thread_id = RemapLane8x8(GI);
      uint2 remapped_dispatch_thread_id = dispatch_group_id * 8 + remapped_group_thread_id;

      InitSharedMemory(remapped_dispatch_thread_id, remapped_group_thread_id);

      GroupMemoryBarrierWithGroupSync();

      remapped_group_thread_id += 4; // center threads in shared memory

      neighborhood_sample_t center = LoadFromSharedMemory(remapped_group_thread_id);

      half4 resolved_radiance = center.radiance;
      half resolved_variance = center.variance;

      bool needs_denoiser = true;///*center.variance > 0.0 &&*/ IsGlossyReflection(center.normal.w) && !IsMirrorReflection(center.normal.w);
      if (needs_denoiser)
      {
        half3 avg_radiance = texelFetch(ssr_avg_reflection_tex, remapped_dispatch_thread_id / 8, 0).xyz;
        Resolve(remapped_group_thread_id, avg_radiance, center, resolved_radiance, resolved_variance);
      }

      out_reflection[remapped_dispatch_thread_id] = resolved_radiance;
      out_variance[remapped_dispatch_thread_id] = COMPRESS_VARIANCE(resolved_variance);
    }
  }
  compile("cs_5_0", "prefilter");
}

shader ssr_temporal
{
  INIT_RENDERING_RESOLUTION(cs)
  SSR_COMMON(cs)

  (cs) {
    ssr_counters@buf = ssr_counters hlsl { StructuredBuffer<uint> ssr_counters@buf; };
    ssr_tile_list@buf = ssr_tile_list hlsl { StructuredBuffer<uint> ssr_tile_list@buf; };

    ssr_reflection_tex@tex = ssr_reflection_tex hlsl { Texture2D<float4> ssr_reflection_tex@tex; }
    ssr_variance_tex@tex = ssr_variance_tex hlsl { Texture2D<float> ssr_variance_tex@tex; }
    ssr_reproj_reflection_tex@tex = ssr_reproj_reflection_tex hlsl { Texture2D<float4> ssr_reproj_reflection_tex@tex; }
    ssr_sample_count_tex@tex = ssr_sample_count_tex hlsl { Texture2D<float> ssr_sample_count_tex@tex; }
    ssr_avg_reflection_tex@smp2d = ssr_avg_reflection_tex;
  }

  hlsl(cs) {
    RWTexture2D<float4> out_reflection          : register(u0);
    RWTexture2D<float> out_variance             : register(u1);

    #define LOCAL_NEIGHBORHOOD_RADIUS 4
    #define GAUSSIAN_K 3.0

    groupshared uint g_shared_storage_0[16][16];
    groupshared uint g_shared_storage_1[16][16];

    void LoadIntoSharedMemory(int2 dispatch_thread_id, int2 group_thread_id, int2 screen_size)
    {
      // Load 16x16 region into shared memory using 4 8x8 blocks
      const int2 offset[4] = {int2(0, 0), int2(8, 0), int2(0, 8), int2(8, 8)};

      // Intermediate storage
      half4 refl[4];

      // Start from the upper left corner of 16x16 region
      dispatch_thread_id -= 4;

      // Load into registers
      UNROLL
      for (int i = 0; i < 4; ++i)
        refl[i] = texelFetch(ssr_reflection_tex, dispatch_thread_id + offset[i], 0);

      // Move to shared memory
      UNROLL
      for (int j = 0; j < 4; ++j)
      {
        int2 index = group_thread_id + offset[j];
        g_shared_storage_0[index.y][index.x] = PackFloat16(refl[j].xy);
        g_shared_storage_1[index.y][index.x] = PackFloat16(refl[j].zw);
      }
    }

    half4 LoadFromGroupSharedMemory(int2 idx)
    {
      return half4(UnpackFloat16(g_shared_storage_0[idx.y][idx.x]),
                   UnpackFloat16(g_shared_storage_1[idx.y][idx.x]));
    }

    half LocalNeighborhoodKernelWeight(half i)
    {
      const half radius = LOCAL_NEIGHBORHOOD_RADIUS + 1.0;
      return exp(-GAUSSIAN_K * (i * i) / (radius * radius));
    }

    struct moments_t
    {
      half4 mean;
      half4 variance;
    };

    moments_t EstimateLocalNeighbourhoodInGroup(int2 group_thread_id)
    {
      moments_t ret;
      ret.mean = 0.0;
      ret.variance = 0.0;

      half accumulated_weight = 0;
      for (int j = -LOCAL_NEIGHBORHOOD_RADIUS; j <= LOCAL_NEIGHBORHOOD_RADIUS; ++j)
      {
        for (int i = -LOCAL_NEIGHBORHOOD_RADIUS; i <= LOCAL_NEIGHBORHOOD_RADIUS; ++i)
        {
          int2 index = group_thread_id + int2(i, j);
          half4 radiance = LoadFromGroupSharedMemory(index);
          half weight = LocalNeighborhoodKernelWeight(i) * LocalNeighborhoodKernelWeight(j);
          accumulated_weight += weight;

          ret.mean += radiance * weight;
          ret.variance += radiance * radiance * weight;
        }
      }

      ret.mean /= accumulated_weight;
      ret.variance /= accumulated_weight;

      ret.variance = abs(ret.variance - ret.mean * ret.mean);

      return ret;
    }

    // From "Temporal Reprojection Anti-Aliasing"
    // https://github.com/playdeadgames/temporal
    /**********************************************************************
    Copyright (c) [2015] [Playdead]

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    ********************************************************************/
    half3 ClipAABB(half3 aabb_min, half3 aabb_max, half3 prev_sample)
    {
      // Main idea behind clipping - it prevents clustering when neighbor color space
      // is distant from history sample

      // Here we find intersection between color vector and aabb color box

      // Note: only clips towards aabb center
      half3 aabb_center = 0.5 * (aabb_max + aabb_min);
      half3 extent_clip = 0.5 * (aabb_max - aabb_min) + 0.001;

      // Find color vector
      half3 color_vector = prev_sample - aabb_center;
      // Transform into clip space
      half3 color_vector_clip = color_vector / extent_clip;
      // Find max absolute component
      color_vector_clip = abs(color_vector_clip);
      half max_abs_unit = max(max(color_vector_clip.x, color_vector_clip.y), color_vector_clip.z);

      if (max_abs_unit > 1.0)
        return aabb_center + color_vector / max_abs_unit; // clip towards color vector
      else
        return prev_sample; // point is inside aabb
    }

    half Luminance(half3 color) { return max(dot(color, half3(0.299, 0.587, 0.114)), 0.001); }

    half ComputeTemporalVariance(half3 history_radiance, half3 radiance)
    {
      half history_luminance = Luminance(history_radiance);
      half luminance = Luminance(radiance);
      half diff = abs(history_luminance - luminance) / max(max(history_luminance, luminance), 0.5);
      return diff * diff;
    }

    static const float history_clip_weight = 0.7;

    [numthreads(COMPUTE_GRP_SIZE_X, COMPUTE_GRP_SIZE_Y, 1)]
    void resolve_temporal( uint Groupid : SV_GroupID, uint3 DTid : SV_DispatchThreadID, int2 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex )
    {
      uint packed_coords = structuredBufferAt(ssr_tile_list, Groupid);
      int2 dispatch_thread_id = int2(packed_coords & 0xffffu, (packed_coords >> 16) & 0xffffu) + GTid;
      int2 dispatch_group_id = dispatch_thread_id / 8;
      uint2 remapped_group_thread_id = RemapLane8x8(GI);
      uint2 remapped_dispatch_thread_id = dispatch_group_id * 8 + remapped_group_thread_id;

      LoadIntoSharedMemory(remapped_dispatch_thread_id, remapped_group_thread_id, rendering_res.xy);

      GroupMemoryBarrierWithGroupSync();

      remapped_group_thread_id += 4; // Center threads in shared memory

      half4 center_radiance = LoadFromGroupSharedMemory(remapped_group_thread_id);
      half4 new_signal = center_radiance;

      float2 screenCoordCenter = remapped_dispatch_thread_id + float2(0.5,0.5);
      float2 curViewTc = saturate(screenCoordCenter*ssr_target_size.zw);

      half3 _unused0;
      half roughness;
      float _unused1;
      unpack_material(curViewTc, _unused0, roughness, _unused1);
      half new_variance = DECOMPRESS_VARIANCE(texelFetch(ssr_variance_tex, remapped_dispatch_thread_id, 0));

      half sample_count = 1.0;

      if (IsGlossyReflection(roughness))
      {
        sample_count = DECOMPRESS_SAMPLE_COUNT(texelFetch(ssr_sample_count_tex, remapped_dispatch_thread_id, 0).x);

        half3 avg_radiance = texelFetch(ssr_avg_reflection_tex, remapped_dispatch_thread_id / 8, 0).xyz;

        half4 old_signal = texelFetch(ssr_reproj_reflection_tex, remapped_dispatch_thread_id, 0);
        moments_t local_neighborhood = EstimateLocalNeighbourhoodInGroup(remapped_group_thread_id);

        // Clip history based on the current local statistics
        half3 color_std = (sqrt(local_neighborhood.variance.xyz) + length(local_neighborhood.mean.xyz - avg_radiance)) * history_clip_weight * 1.4;
        local_neighborhood.mean.xyz = lerp(local_neighborhood.mean.xyz, avg_radiance, 0.2);

        half3 radiance_min = local_neighborhood.mean.xyz - color_std;
        half3 radiance_max = local_neighborhood.mean.xyz + color_std;
        old_signal.xyz = ClipAABB(radiance_min, radiance_max, old_signal.xyz);
        half conf_std = sqrt(local_neighborhood.variance.w);
        old_signal.w = clamp(old_signal.w, local_neighborhood.mean.w - conf_std, local_neighborhood.mean.w + conf_std);
        half accumulation_speed = 1.0 / max(sample_count, 1.0);
        half weight = (1.0 - accumulation_speed);
        // Blend with average for small sample count
        new_signal.xyz = lerp(new_signal.xyz, avg_radiance, 1.0 / max(sample_count + 1.0, 1.0));
        { // Clip outliers
          half3 radiance_min = avg_radiance - color_std * 1.0;
          half3 radiance_max = avg_radiance + color_std * 1.0;
          new_signal.xyz = ClipAABB(radiance_min, radiance_max, new_signal.xyz);
        }
        // Blend with history
        new_signal = lerp(new_signal, old_signal, weight);
        new_variance = lerp(ComputeTemporalVariance(new_signal.xyz, old_signal.xyz), new_variance, weight);
        if (any(isinf(new_signal)) || any(isnan(new_signal)) || isinf(new_variance) || isnan(new_variance))
        {
          new_signal = 0.0;
          new_variance = 0.0;
          sample_count = 0;
        }
      }

      out_reflection[remapped_dispatch_thread_id] = new_signal;
      out_variance[remapped_dispatch_thread_id] = COMPRESS_VARIANCE(new_variance);
    }
  }
  compile("cs_5_0", "resolve_temporal");
}
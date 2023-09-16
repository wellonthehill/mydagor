/**********************************************************************
Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
********************************************************************/

#ifndef FFX_SSSR
#define FFX_SSSR
#define FFX_SSSR_FLOAT_MAX                          3.402823466e+38

void FFX_SSSR_InitialAdvanceRay(float3 origin, float3 direction, float3 inv_direction, float2 current_mip_resolution, float2 current_mip_resolution_inv, float2 floor_offset, float2 uv_offset, out float3 position, out float current_t) {
    float2 current_mip_position = current_mip_resolution * origin.xy;

    // Intersect ray with the half box that is pointing away from the ray origin.
    float2 xy_plane = floor(current_mip_position) + floor_offset;
    xy_plane = xy_plane * current_mip_resolution_inv + uv_offset;

    // o + d * t = p' => t = (p' - o) / d
    float2 t = xy_plane * inv_direction.xy - origin.xy * inv_direction.xy;
    current_t = min(t.x, t.y);
    position = origin + current_t * direction;
}

bool FFX_SSSR_AdvanceRay(float3 origin, float3 direction, float3 inv_direction, float2 current_mip_position, float2 current_mip_resolution_inv, float2 floor_offset, float2 uv_offset, float surface_z, inout float3 position, inout float current_t, bool hit_validation) {
    // Skip tile if view space depth is below the finest surface thickness
    bool below_surface = hit_validation && (position.z * 1.01 < surface_z);

    // Create boundary planes
    float2 xy_plane = floor(current_mip_position) + floor_offset;
    xy_plane = xy_plane * current_mip_resolution_inv + uv_offset;
    float3 boundary_planes = float3(xy_plane, surface_z);

    // Intersect ray with the half box that is pointing away from the ray origin.
    // o + d * t = p' => t = (p' - o) / d
    float3 t = boundary_planes * inv_direction - origin * inv_direction;

    // Prevent using z plane when shooting out of the depth buffer.
#ifdef FFX_SSSR_INVERTED_DEPTH_RANGE
    t.z = ((direction.z < 0) && !below_surface) ? t.z : FFX_SSSR_FLOAT_MAX;
#else
    t.z = ((direction.z > 0) && !below_surface) ? t.z : FFX_SSSR_FLOAT_MAX;
#endif

    // Choose nearest intersection with a boundary.
    float t_min = min(min(t.x, t.y), t.z);

#ifdef FFX_SSSR_INVERTED_DEPTH_RANGE
    // Larger z means closer to the camera.
    bool above_surface = (surface_z < position.z) || below_surface;
#else
    // Smaller z means closer to the camera.
    bool above_surface = (surface_z > position.z) || below_surface;
#endif

    // Decide whether we are able to advance the ray until we hit the xy boundaries or if we had to clamp it at the surface.
    // We use the asuint comparison to avoid NaN / Inf logic, also we actually care about bitwise equality here to see if t_min is the t.z we fed into the min3 above.
    bool skipped_tile = asuint(t_min) != asuint(t.z) && above_surface; 

    // Make sure to only advance the ray if we're still above the surface.
    current_t = above_surface ? t_min : current_t;

    // Advance ray
    position = origin + current_t * direction;

    return skipped_tile;
}

float2 FFX_SSSR_GetMipResolution(float2 screen_dimensions, int mip_level) {
    return screen_dimensions * pow(0.5, mip_level);
}

bool in_downsampled_close_depth_boundaries(float2 current_mip_position, int current_mip, float2 current_mip_resolution)
{
    return !((current_mip_position.x < 0) ||
             (current_mip_position.y < 0) ||
             (current_mip_position.x >= floor(current_mip_resolution.x)) ||
             (current_mip_position.y >= floor(current_mip_resolution.y)) ||
             (current_mip >= downsampled_depth_mip_count));
}

// Requires origin and direction of the ray to be in screen space [0, 1] x [0, 1]
float3 FFX_SSSR_HierarchicalRaymarch(float3 origin, float3 direction, float2 screen_size, int most_detailed_mip, uint max_traversal_intersections, out bool valid_hit) {
    const float3 inv_direction = direction != 0 ? 1.0 / direction : FFX_SSSR_FLOAT_MAX;

    // Start on mip with highest detail.
    int current_mip = most_detailed_mip;

    // Could recompute these every iteration, but it's faster to hoist them out and update them.
    float2 current_mip_resolution = FFX_SSSR_GetMipResolution(screen_size, current_mip);
    float2 current_mip_resolution_inv = rcp(current_mip_resolution);

    // Offset to the bounding boxes uv space to intersect the ray with the center of the next pixel.
    // This means we ever so slightly over shoot into the next region. 
    float2 uv_offset = 0.005 * exp2(most_detailed_mip) / screen_size;
    uv_offset = direction.xy < 0 ? -uv_offset : uv_offset;

    // Offset applied depending on current mip resolution to move the boundary to the left/right upper/lower border depending on ray direction.
    float2 floor_offset = direction.xy < 0 ? 0 : 1;
    
    // Initially advance ray to avoid immediate self intersections.
    float current_t;
    float3 position;
    FFX_SSSR_InitialAdvanceRay(origin, direction, inv_direction, current_mip_resolution, current_mip_resolution_inv, floor_offset, uv_offset, position, current_t);

    uint i = 0;
    while (i < max_traversal_intersections && current_mip >= most_detailed_mip) {
        float2 current_mip_position = current_mip_resolution * position.xy;

        #ifdef FFX_SSSR_INVERTED_DEPTH_RANGE
        float surface_z = 1.0;
        #else
        float surface_z = 0.0;
        #endif

        if (in_downsampled_close_depth_boundaries(current_mip_position, current_mip, current_mip_resolution))
            surface_z = texelFetch(downsampled_close_depth_tex, int2(current_mip_position), current_mip).r;

        bool skipped_tile = FFX_SSSR_AdvanceRay(origin, direction, inv_direction, current_mip_position, current_mip_resolution_inv, floor_offset, uv_offset, surface_z, position, current_t, current_mip == most_detailed_mip);
        current_mip += skipped_tile ? 1 : -1;
        current_mip_resolution *= skipped_tile ? 0.5 : 2;
        current_mip_resolution_inv *= skipped_tile ? 2 : 0.5;
        ++i;
    }

    float surface_z = 0.0;
    if (in_downsampled_close_depth_boundaries(screen_size * position.xy, 0, screen_size))
        surface_z = texelFetch(downsampled_close_depth_tex, int2(screen_size * position.xy), 0).r;
    valid_hit = (current_mip < most_detailed_mip) && (surface_z > 0);

    position.z = surface_z;
    return position;
}

#endif //FFX_SSSR

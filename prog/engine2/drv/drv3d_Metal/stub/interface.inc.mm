#include <debug/dag_assert.h>

RaytraceBottomAccelerationStructure *d3d::create_raytrace_bottom_acceleration_structure(RaytraceGeometryDescription *, uint32_t,
  RaytraceBuildFlags)
{
  G_ASSERTF(false, "Use of disabled raytracing API");
  return nullptr;
}

void d3d::delete_raytrace_bottom_acceleration_structure(RaytraceBottomAccelerationStructure *) { G_ASSERTF(false, "Use of disabled raytracing API"); }

RaytraceTopAccelerationStructure *d3d::create_raytrace_top_acceleration_structure(uint32_t, RaytraceBuildFlags) { G_ASSERTF(false, "Use of disabled raytracing API"); return nullptr; }

void d3d::delete_raytrace_top_acceleration_structure(RaytraceTopAccelerationStructure *) { G_ASSERTF(false, "Use of disabled raytracing API"); }

void d3d::set_top_acceleration_structure(ShaderStage, uint32_t, RaytraceTopAccelerationStructure *) { G_ASSERTF(false, "Use of disabled raytracing API"); }

PROGRAM d3d::create_raytrace_program(const int *, uint32_t, const RaytraceShaderGroup *, uint32_t, uint32_t) { G_ASSERTF(false, "Use of disabled raytracing API"); return -1; }

void d3d::trace_rays(Sbuffer *, uint32_t, Sbuffer *, uint32_t, uint32_t, Sbuffer *, uint32_t, uint32_t, Sbuffer *, uint32_t, uint32_t,
  uint32_t, uint32_t, uint32_t)
{
  G_ASSERTF(false, "Use of disabled raytracing API");
}

void d3d::build_bottom_acceleration_structure(RaytraceBottomAccelerationStructure *, RaytraceGeometryDescription *, uint32_t,
  RaytraceBuildFlags, bool)
{
  G_ASSERTF(false, "Use of disabled raytracing API");
}

void d3d::build_top_acceleration_structure(RaytraceTopAccelerationStructure *, Sbuffer *, uint32_t, RaytraceBuildFlags, bool) { G_ASSERTF(false, "Use of disabled raytracing API"); }
void d3d::copy_raytrace_shader_handle_to_memory(PROGRAM, uint32_t, uint32_t, uint32_t, Sbuffer *, uint32_t) { G_ASSERTF(false, "Use of disabled raytracing API"); }
void d3d::write_raytrace_index_entries_to_memory(uint32_t, const RaytraceGeometryInstanceDescription *, void *) { G_ASSERTF(false, "Use of disabled raytracing API"); }
int d3d::create_raytrace_shader(RaytraceShaderType, const uint32_t *, uint32_t) { G_ASSERTF(false, "Use of disabled raytracing API"); return -1; }
void d3d::delete_raytrace_shader(int) { G_ASSERTF(false, "Use of disabled raytracing API"); }

#include <ioSys/dag_fileIo.h>
#include <ioSys/dag_zlibIo.h>
#include <osApiWrappers/dag_files.h>
#include <osApiWrappers/dag_miscApi.h>
#include "device.h"
#include "perfMon/dag_statDrv.h"

using namespace drv3d_vulkan;

const uint32_t RaytracePipelineShaderConfig::stages[RaytracePipelineShaderConfig::count] = {};

const uint32_t RaytracePipelineShaderConfig::registerIndexes[RaytracePipelineShaderConfig::count] = {
  spirv::raytrace::REGISTERS_SET_INDEX};

namespace drv3d_vulkan
{

template <>
void RaytracePipeline::onDelayedCleanupFinish<RaytracePipeline::CLEANUP_DESTROY>()
{
  shutdown(get_device().getVkDevice());
  delete this;
}

} // namespace drv3d_vulkan

RaytracePipeline::RaytracePipeline(VulkanDevice &, ProgramID, VulkanPipelineCacheHandle, LayoutType *l, const CreationInfo &) :
  BasePipeline(l)
{}

void RaytracePipeline::bind(VulkanDevice &, VulkanCommandBufferHandle) {}

void RaytracePipeline::copyRaytraceShaderGroupHandlesToMemory(VulkanDevice &, uint32_t, uint32_t, uint32_t, void *)
{
  G_ASSERTF(false, "RaytracePipeline::copyRaytraceShaderGroupHandlesToMemory called on API without support");
}
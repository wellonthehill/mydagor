#pragma once

#include "break_point.h"
#include "device_state.h"

namespace drv3d_dx12
{
namespace debug
{
namespace pc
{
class DeviceContextState : public break_point::Controller
{
public:
  void debugBeginCommandBuffer(DeviceState &dds, D3DDevice *device, ID3D12GraphicsCommandList *cmd)
  {
    dds.beginCommandBuffer(device, cmd);
  }
  void debugEndCommandBuffer(DeviceState &dds, ID3D12GraphicsCommandList *cmd) { dds.endCommandBuffer(cmd); }
  void debugFramePresent(DeviceState &dds) { dds.handlePresentToPresentCapture(); }
  void debugEventBegin(DeviceState &dds, ID3D12GraphicsCommandList *cmd, eastl::string_view name) { dds.beginSection(cmd, name); }
  void debugEventEnd(DeviceState &dds, ID3D12GraphicsCommandList *cmd) { dds.endSection(cmd); }
  void debugMarkerSet(DeviceState &dds, ID3D12GraphicsCommandList *cmd, eastl::string_view name) { dds.marker(cmd, name); }

  void debugFrameCaptureBegin(DeviceState &dds, ID3D12CommandQueue *, uint32_t, eastl::span<const wchar_t>) { dds.beginCapture(); }
  void debugFrameCaptureEnd(DeviceState &dds, ID3D12CommandQueue *) { dds.endCapture(); }
  void debugFrameCaptureQueueNextFrames(DeviceState &dds, ID3D12CommandQueue *, uint32_t, eastl::span<const wchar_t> filename,
    int frame_count)
  {
    dds.captureNextFrames(filename.data(), frame_count);
  }

  void debugRecordDraw(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &vs,
    const PipelineStageStateBase &ps, BasePipeline &pipeline_base, PipelineVariant &pipeline, uint32_t count, uint32_t instance_count,
    uint32_t start, uint32_t first_instance, D3D12_PRIMITIVE_TOPOLOGY topology)
  {
    dds.draw(getCommandData(), cmd, vs, ps, pipeline_base, pipeline, count, instance_count, start, first_instance, topology);
  }
  void debugRecordDrawIndexed(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &vs,
    const PipelineStageStateBase &ps, BasePipeline &pipeline_base, PipelineVariant &pipeline, uint32_t count, uint32_t instance_count,
    uint32_t index_start, int32_t vertex_base, uint32_t first_instance, D3D12_PRIMITIVE_TOPOLOGY topology)
  {
    dds.drawIndexed(getCommandData(), cmd, vs, ps, pipeline_base, pipeline, count, instance_count, index_start, vertex_base,
      first_instance, topology);
  }
  void debugDrawIndirect(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &vs,
    const PipelineStageStateBase &ps, BasePipeline &pipeline_base, PipelineVariant &pipeline, BufferResourceReferenceAndOffset buffer)
  {
    dds.drawIndirect(getCommandData(), cmd, vs, ps, pipeline_base, pipeline, buffer);
  }
  void debugDrawIndexedIndirect(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &vs,
    const PipelineStageStateBase &ps, BasePipeline &pipeline_base, PipelineVariant &pipeline, BufferResourceReferenceAndOffset buffer)
  {
    dds.drawIndexedIndirect(getCommandData(), cmd, vs, ps, pipeline_base, pipeline, buffer);
  }
  void debugDispatchIndirect(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &state,
    ComputePipeline &pipeline, BufferResourceReferenceAndOffset buffer)
  {
    dds.dispatchIndirect(getCommandData(), cmd, state, pipeline, buffer);
  }
  void debugDispatch(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &state, ComputePipeline &pipeline,
    uint32_t x, uint32_t y, uint32_t z)
  {
    dds.dispatch(getCommandData(), cmd, state, pipeline, x, y, z);
  }

  void debugDispatchMesh(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &vs,
    const PipelineStageStateBase &ps, BasePipeline &pipeline_base, PipelineVariant &pipeline, uint32_t x, uint32_t y, uint32_t z)
  {
    dds.dispatchMesh(getCommandData(), cmd, vs, ps, pipeline_base, pipeline, x, y, z);
  }

  void debugDispatchMeshIndirect(DeviceState &dds, D3DGraphicsCommandList *cmd, const PipelineStageStateBase &vs,
    const PipelineStageStateBase &ps, BasePipeline &pipeline_base, PipelineVariant &pipeline, BufferResourceReferenceAndOffset args,
    BufferResourceReferenceAndOffset count, uint32_t max_count)
  {
    dds.dispatchMeshIndirect(getCommandData(), cmd, vs, ps, pipeline_base, pipeline, args, count, max_count);
  }

  void debugBlit(DeviceState &dds, D3DGraphicsCommandList *cmd) { dds.blit(getCommandData(), cmd); }

  void debugOnDeviceRemoved(DeviceState &dds, D3DDevice *device, HRESULT remove_reason) { dds.onDeviceRemoved(device, remove_reason); }
};
} // namespace pc
} // namespace debug
} // namespace drv3d_dx12
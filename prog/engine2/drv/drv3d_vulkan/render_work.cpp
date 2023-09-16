#include "render_work.h"
#include "device_context.h"
#include "device.h"
#include <ska_hash_map/flat_hash_map2.hpp>
#include <EASTL/sort.h>
#include <gui/dag_visualLog.h>
#include <osApiWrappers/dag_files.h>
#include <osApiWrappers/dag_stackHlp.h>
#include <perfMon/dag_statDrv.h>
#include "util/backtrace.h"

using namespace drv3d_vulkan;

namespace
{

#define VULKAN_CONTEXT_COMMAND_IMPLEMENTATION 1
#define VULKAN_BEGIN_CONTEXT_COMMAND(Name)                  \
  void execute(const Cmd##Name &cmd, ExecutionContext &ctx) \
  {                                                         \
    TIME_PROFILE(vulkan_cmd##Name);                         \
    G_UNUSED(cmd);                                          \
    G_UNUSED(ctx);
#define VULKAN_END_CONTEXT_COMMAND }
// make an alias so we do not need to write cmd.
#define VULKAN_CONTEXT_COMMAND_PARAM(type, name) \
  auto &name = cmd.name;                         \
  G_UNUSED(name);
#define VULKAN_CONTEXT_COMMAND_PARAM_ARRAY(type, name, size) \
  auto &name = cmd.name;                                     \
  G_UNUSED(name);
#include "device_context_cmd.inc"
#undef VULKAN_BEGIN_CONTEXT_COMMAND
#undef VULKAN_END_CONTEXT_COMMAND
#undef VULKAN_CONTEXT_COMMAND_PARAM
#undef VULKAN_CONTEXT_COMMAND_PARAM_ARRAY
#undef VULKAN_CONTEXT_COMMAND_IMPLEMENTATION

struct CmdDumpContext
{
  const RenderWork &renderWork;
  FaultReportDump &dump;
  FaultReportDump::RefId cmdRid;

  void addRef(FaultReportDump::GlobalTag tag, uint64_t id) { dump.addRef(cmdRid, tag, id); }
};

#include "device_context/command_debug_print.inc.cpp"

#define VULKAN_BEGIN_CONTEXT_COMMAND(Name)                                                                            \
  void dumpCommand(const Cmd##Name &cmd, FaultReportDump &dump, const RenderWork &ctx, FaultReportDump::RefId cmdRid) \
  {                                                                                                                   \
    G_UNUSED(ctx);                                                                                                    \
    G_UNUSED(dump);                                                                                                   \
    G_UNUSED(cmd);                                                                                                    \
    G_UNUSED(cmdRid);

#define VULKAN_END_CONTEXT_COMMAND }
#define VULKAN_CONTEXT_COMMAND_PARAM(type, Name)                                                                                \
  {                                                                                                                             \
    String paramValue = dumpCmdParam(cmd.Name, {ctx, dump, cmdRid});                                                            \
    FaultReportDump::RefId rid =                                                                                                \
      dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_PARAM, (uint64_t)&cmd.Name, String(64, "%s = %s", #Name, paramValue)); \
    dump.addRef(rid, FaultReportDump::GlobalTag::TAG_CMD, (uint64_t)&cmd);                                                      \
  }
#define VULKAN_CONTEXT_COMMAND_PARAM_ARRAY(type, Name, size)                                                                    \
  {                                                                                                                             \
    String paramValue = dumpCmdParam(cmd.Name, {ctx, dump, cmdRid});                                                            \
    FaultReportDump::RefId rid =                                                                                                \
      dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_PARAM, (uint64_t)&cmd.Name, String(64, "%s = %s", #Name, paramValue)); \
    dump.addRef(rid, FaultReportDump::GlobalTag::TAG_CMD, (uint64_t)&cmd);                                                      \
  }

#include "device_context_cmd.inc"

#undef VULKAN_BEGIN_CONTEXT_COMMAND
#undef VULKAN_END_CONTEXT_COMMAND
#undef VULKAN_CONTEXT_COMMAND_PARAM
#undef VULKAN_CONTEXT_COMMAND_PARAM_ARRAY

} // namespace

bool RenderWork::recordCommandCallers = false;

void RenderWork::dumpData(FaultReportDump &dump) const
{
  for (auto &&bu : bufferUploads)
  {
    auto at = bufferUploadCopies.begin() + bu.copyIndex;
    auto copyEnd = at + bu.copyCount;
    for (; at != copyEnd; ++at)
    {
      FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_DATA, (uint64_t)&at,
        String(64, "buffer upload %u bytes from 0x" PTR_LIKE_HEX_FMT "[%u] to 0x" PTR_LIKE_HEX_FMT "[%u]", at->size, bu.src.value,
          at->srcOffset, bu.dst.value, at->dstOffset));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(bu.src));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(bu.dst));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
    }
  }

  for (auto &&bu : orderedBufferUploads)
  {
    auto at = orderedBufferUploadCopies.begin() + bu.copyIndex;
    auto copyEnd = at + bu.copyCount;
    for (; at != copyEnd; ++at)
    {
      FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_DATA, (uint64_t)&at,
        String(64, "ordered buffer upload %u bytes from 0x" PTR_LIKE_HEX_FMT "[%u] to 0x" PTR_LIKE_HEX_FMT "[%u]", at->size,
          bu.src.value, at->srcOffset, bu.dst.value, at->dstOffset));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(bu.src));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(bu.dst));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
    }
  }

  for (auto &&bd : bufferDownloads)
  {
    auto at = bufferDownloadCopies.begin() + bd.copyIndex;
    auto copyEnd = at + bd.copyCount;
    for (; at != copyEnd; ++at)
    {
      FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_DATA, (uint64_t)&at,
        String(64, "buffer download %u bytes from 0x" PTR_LIKE_HEX_FMT "[%u] to 0x" PTR_LIKE_HEX_FMT "[%u]", at->size, bd.src.value,
          at->srcOffset, bd.dst.value, at->dstOffset));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(bd.src));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(bd.dst));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
    }
  }

  for (auto &&bf : bufferToHostFlushes)
  {
    FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_DATA, (uint64_t)&bf,
      String(64, "buffer flush to host 0x" PTR_LIKE_HEX_FMT "[%u] %u bytes", bf.buffer.value, bf.offset, bf.range));
    dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(bf.buffer));
    dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
  }

  for (auto &&iu : imageUploads)
  {
    auto at = imageUploadCopies.begin() + iu.copyIndex;
    auto copyEnd = at + iu.copyCount;
    for (; at != copyEnd; ++at)
    {
      FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_DATA, (uint64_t)&at,
        String(64,
          "image upload from 0x" PTR_LIKE_HEX_FMT "[%u]"
          " to 0x%p {0x" PTR_LIKE_HEX_FMT "}[%u-%u][%u]",
          iu.buf.value, at->bufferOffset, iu.image, iu.img.value, at->imageSubresource.baseArrayLayer,
          at->imageSubresource.baseArrayLayer + at->imageSubresource.layerCount, at->imageSubresource.mipLevel));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(iu.buf));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(iu.img));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_OBJECT, (uint64_t)(iu.image));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
    }
  }

  for (auto &&iter : imageDownloads)
  {
    auto at = imageDownloadCopies.begin() + iter.copyIndex;
    auto copyEnd = at + iter.copyCount;
    for (; at != copyEnd; ++at)
    {
      FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_DATA, (uint64_t)&at,
        String(64,
          "image download from 0x" PTR_LIKE_HEX_FMT "[%u]"
          " from 0x%p {0x" PTR_LIKE_HEX_FMT "}[%u-%u][%u]",
          iter.buf.value, at->bufferOffset, iter.image, iter.img.value, at->imageSubresource.baseArrayLayer,
          at->imageSubresource.baseArrayLayer + at->imageSubresource.layerCount, at->imageSubresource.mipLevel));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(iter.buf));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_VK_HANDLE, generalize(iter.img));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_OBJECT, (uint64_t)(iter.image));
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
    }
  }

  for (auto iter = imagesToFillEmptySubresources.begin(); iter != imagesToFillEmptySubresources.end(); ++iter)
  {
    FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD_DATA, (uint64_t)iter,
      String(64, " image empty subres fill 0x" PTR_LIKE_HEX_FMT, *iter));
    dump.addRef(rid, FaultReportDump::GlobalTag::TAG_OBJECT, (uint64_t)*iter);
    dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
  }

  cleanups.dumpData(dump);
}

void RenderWork::submit() {}

void RenderWork::acquire(size_t timeline_abs_idx)
{
  id = timeline_abs_idx;
  cleanups.checkValid();
}

void RenderWork::wait() {}

void RenderWork::cleanup()
{
  bufferUploads.clear();
  bufferUploadCopies.clear();
  orderedBufferUploads.clear();
  orderedBufferUploadCopies.clear();
  bufferDownloads.clear();
  bufferDownloadCopies.clear();
  bufferToHostFlushes.clear();
  imageUploads.clear();
  imageUploadCopies.clear();
  imageDownloads.clear();
  imageDownloadCopies.clear();
  charStore.clear();
  imageCopyInfos.clear();
  unorderedImageCopies.clear();
  unorderedImageColorClears.clear();
  unorderedImageDepthStencilClears.clear();
  imagesToFillEmptySubresources.clear();
#if D3D_HAS_RAY_TRACING && (VK_KHR_ray_tracing_pipeline || VK_KHR_ray_query)
  raytraceBuildRangeInfoKHRStore.clear();
  raytraceGeometryKHRStore.clear();
#endif
  shaderModuleUses.clear();
  commandStream.clear();
#if DAGOR_DBGLEVEL > 0
  commandCallers.clear();
#endif
  generateFaultReport = false;
}

void RenderWork::processCommands(ExecutionContext &ctx)
{
  commandStream.visitAll([&ctx](auto &&value) //
    {
      ctx.beginCmd(&value);
      execute(value, ctx);
      ctx.endCmd();
    });
}

void RenderWork::process()
{
  TIME_PROFILE(vulkan_render_work_process);

  skippedGraphicsPipelines = 0;
  ExecutionContext executionContext(*this);
  executionContext.prepareFrameCore();
  processCommands(executionContext);
  cleanups.backendAfterReplayCleanup(get_device().getContext().getBackend());
}

void RenderWork::shutdown() { cleanup(); }

void RenderWork::dumpCommands(FaultReportDump &dump)
{
#if DAGOR_DBGLEVEL > 0
  uint32_t idx = 0;

  if (recordCommandCallers)
  {
    commandStream.visitAll([&](auto &&) {
      uint64_t callerHash = commandCallers[idx++];

      if (dump.hasEntry(FaultReportDump::GlobalTag::TAG_CALLER_HASH, callerHash))
        return;

      dump.addTagged(FaultReportDump::GlobalTag::TAG_CALLER_HASH, callerHash,
        String(128, "caller stack\n%s", backtrace::get_stack_by_hash(callerHash)));
    });

    idx = 0;
  }
#endif

  size_t workItemId = id;

  commandStream.visitAll([&](auto &&value) {
    FaultReportDump::RefId rid = dump.addTagged(FaultReportDump::GlobalTag::TAG_CMD, (uint64_t)&value, String(value.getName()));
    dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, workItemId);

    dumpCommand(value, dump, *this, rid);

#if DAGOR_DBGLEVEL > 0
    if (recordCommandCallers)
      dump.addRef(rid, FaultReportDump::GlobalTag::TAG_CALLER_HASH, commandCallers[idx++]);
#endif
  });
  const size_t totalSize = getMemorySize();
  const size_t cmdSize = commandStream.size();
  const size_t cmdCap = commandStream.capacity();

  FaultReportDump::RefId rid = dump.add(String(64,
    "work item %016llX cmd buffer stats\n"
    "memory usage: %u Bytes, %u KiBytes, %u MiBytes\n"
    "memory allocated: %u Bytes, %u KiBytes, %u MiBytes\n"
    "efficiency: %f%%\n"
    "total batch memory allocated: %u Bytes, %u KiBytes, %u MiBytes\n",
    id, cmdSize, cmdSize / 1024, cmdSize / 1024 / 1024, cmdCap, cmdCap / 1024, cmdCap / 1024 / 1024,
    cmdCap ? ((double(cmdSize) / cmdCap) * 100.0) : 100.0, totalSize, totalSize / 1024, totalSize / 1024 / 1024));
  dump.addRef(rid, FaultReportDump::GlobalTag::TAG_WORK_ITEM, id);
}

void BufferCopyInfo::optimizeBufferCopies(eastl::vector<BufferCopyInfo> &info, eastl::vector<VkBufferCopy> &copies)
{
  // group copy ops by src/dst match, allows easy merge of multiple copies with same src/dst
  eastl::sort(begin(info), end(info),
    [](const BufferCopyInfo &l, const BufferCopyInfo &r) //
    {
      if (l.src < r.src)
        return true;
      if (l.src > r.src)
        return false;
      if (l.dst < r.dst)
        return true;
      if (l.dst > r.dst)
        return false;
      return l.copyIndex < r.copyIndex;
    });

  // reorganized the buffer copies to match the ordering of the infos
  // this approach is simple but requires additional memory and copies
  // every entry once
  // don't reallocate while we copy stuff around inside this vector
  copies.reserve(copies.size() * 2);
  for (auto &&upload : info)
  {
    auto start = begin(copies) + upload.copyIndex;
    auto stop = start + upload.copyCount;
    upload.copyIndex = copies.size();
    copies.insert(end(copies), start, stop);
  }

  // now merge with same src/dst pair
  for (uint32_t i = info.size() - 1; i > 0; --i)
  {
    auto &l = info[i - 1];
    auto &r = info[i];

    if (l.src != l.dst)
      continue;
    if (l.dst != r.dst)
      continue;
    // those are guaranteed to be back to back
    l.copyCount += r.copyCount;
    // remove right copy
    info.erase(begin(info) + i);
  }
}

namespace
{
bool isSameImageSection(const VkBufferImageCopy &l, const VkBufferImageCopy &r)
{
  return 0 == memcmp(&l.imageSubresource, &r.imageSubresource, sizeof(l.imageSubresource)) &&
         0 == memcmp(&l.imageOffset, &r.imageOffset, sizeof(l.imageOffset)) &&
         0 == memcmp(&l.imageExtent, &r.imageExtent, sizeof(l.imageExtent));
}
} // namespace

void ImageCopyInfo::deduplicate(eastl::vector<ImageCopyInfo> &info, eastl::vector<VkBufferImageCopy> &copies)
{
  for (uint32_t i = 0; i < info.size(); ++i)
  {
    auto &base = info[info.size() - 1 - i];
    for (uint32_t j = i + 1; j < info.size(); ++j)
    {
      auto &compare = info[info.size() - 1 - j];
      if (compare.img != base.img)
        continue;

      for (uint32_t k = 0; k < base.copyCount; ++k)
      {
        auto &copyBase = copies[base.copyIndex + k];

        for (uint32_t l = 0; l < compare.copyCount; ++l)
        {
          auto &copyCompare = copies[compare.copyIndex + l];
          if (isSameImageSection(copyBase, copyCompare))
          {
            copyCompare = copies[compare.copyIndex + compare.copyCount - 1];
            --compare.copyCount;
            // we assume per copy set there is no duplicated copy op, so we can stop
            // duplicated copy sections in the same block are not possible
            break;
          }
        }
      }
    }
  }

  // tidy up empty copies in a second step, makes the checking loop much simpler
  info.erase(eastl::remove_if(begin(info), end(info), [](auto &info) { return info.copyCount == 0; }), end(info));
}

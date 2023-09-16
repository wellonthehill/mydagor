// Copyright 2023 by Gaijin Games KFT, All rights reserved.
#pragma once
#include "driver.h"
#include "vulkan_device.h"

// wrapper for vkCmdPipelineBarrier
// allows to accumulate memory/buffer/image barriers
// and perform them in one place for better efficiency and less code duplication
// also can be used to track various sync problems in one place

namespace drv3d_vulkan
{

class Buffer;
class Image;

class PipelineBarrier
{
public:
  struct AccessFlags
  {
    VkAccessFlags src;
    VkAccessFlags dst;

    AccessFlags swap() { return {dst, src}; }
  };

  struct BufferTemplate
  {
    AccessFlags mask;
    VulkanBufferHandle handle;
  };

  struct ImageTemplate
  {
    AccessFlags mask;
    VulkanImageHandle handle;
    VkImageLayout oldLayout;
    VkImageLayout newLayout;
    VkImageSubresourceRange subresRange;
  };

  struct BarrierCache
  {
    Tab<VkMemoryBarrier> mem;
    Tab<VkBufferMemoryBarrier> buffer;
    Tab<VkImageMemoryBarrier> image;
#if DAGOR_DBGLEVEL > 0
    bool inUse = false;
#endif
  };

private:
  const VulkanDevice &device;
  BarrierCache &cache;

  struct
  {
    BufferTemplate buffer;
    ImageTemplate image;
  } barrierTemplate; //-V730_NOINIT

  struct
  {
    VkPipelineStageFlags src;
    VkPipelineStageFlags dst;
  } pipeStages;

  VkDependencyFlags dependencyFlags;

  struct
  {
    uint32_t mem = 0;
    uint32_t buffer = 0;
    uint32_t image = 0;

    void reset()
    {
      mem = 0;
      buffer = 0;
      image = 0;
    }
  } barriersCount;

  void reset();

public:
  PipelineBarrier(const VulkanDevice &in_device, BarrierCache &cache, VkPipelineStageFlags src_stages = 0,
    VkPipelineStageFlags dst_stages = 0);
  ~PipelineBarrier();

  // primary barrier adders
  void addStages(VkPipelineStageFlags src_stages, VkPipelineStageFlags dst_stages);
  void addDependencyFlags(VkDependencyFlags new_flag);
  void addMemory(AccessFlags mask);
  void addBuffer(AccessFlags mask, VulkanBufferHandle buf, VkDeviceSize offset, VkDeviceSize size);
  void addImage(AccessFlags mask, VulkanImageHandle img, VkImageLayout old_layout, VkImageLayout new_layout,
    const VkImageSubresourceRange &subresources);

  // various overloads & template adders

  void addBuffer(AccessFlags mask, const Buffer *buf, VkDeviceSize offset, VkDeviceSize size);

  void modifyBufferTemplate(AccessFlags mask);
  void modifyBufferTemplate(const Buffer *buf);
  void modifyBufferTemplate(VulkanBufferHandle buf);
  void addBufferByTemplate(VkDeviceSize offset, VkDeviceSize size);

  void modifyImageTemplate(AccessFlags mask, VkImageLayout old_layout, VkImageLayout new_layout);
  void modifyImageTemplate(const Image *img);
  void modifyImageTemplate(uint32_t mip_index, uint32_t mip_range, uint32_t array_index, uint32_t array_range);
  void addImageByTemplate(const VkImageSubresourceRange &subresources);
  void addImageByTemplate(ImageState old_state, ImageState new_state);
  void addImageByTemplateFiltered(ImageState old_state, ImageState new_state);
  void addImageByTemplate();

  // special methods

  // present workaround to keep state lookup bit-compressed
  void addImagePresent(ImageState old_state);
  // barrier inversion method for use-and-restore situations
  void revertImageBarriers(AccessFlags mask, VkImageLayout shared_old_layout);

  // TODO
  // merge any suitable image barriers if possible
  // void merge();

  void submit(VulkanCommandBufferHandle cmd_buffer, bool keep_cache = false);
  bool empty();

  void dbgPrint();
};

template <uint32_t builtinCacheIdx>
class ContextedPipelineBarrier;

class BuiltinPipelineBarrierCache
{
  template <uint32_t builtinCacheIdx>
  friend class ContextedPipelineBarrier;

public:
  enum
  {
    EXECUTION_PRIMARY = 0,
    EXECUTION_SECONDARY = 1,
    SWAPCHAIN = 2,
    BUILTIN_ELEMENTS
  };

private:
  static PipelineBarrier::BarrierCache data[BUILTIN_ELEMENTS];

public:
  static void clear()
  {
    uint32_t memTotal = 0;
    uint32_t bufferTotal = 0;
    uint32_t imageTotal = 0;
    for (uint32_t i = 0; i < BUILTIN_ELEMENTS; ++i)
    {
      memTotal += data[i].mem.size();
      clear_and_shrink(data[i].mem);
      bufferTotal += data[i].buffer.size();
      clear_and_shrink(data[i].buffer);
      imageTotal += data[i].image.size();
      clear_and_shrink(data[i].image);
    }
    debug("vulkan: builtin barrier cache cleaned up, max was: mem %u buf %u img %u", memTotal, bufferTotal, imageTotal);
  }
};

// class is not MT safe, use only inside of thread safe scope
// provides fast builtin cache
template <uint32_t builtinCacheIdx>
class ContextedPipelineBarrier : public PipelineBarrier
{
  static_assert(builtinCacheIdx < BuiltinPipelineBarrierCache::BUILTIN_ELEMENTS, "builtin cache index is out of bounds");

public:
  ContextedPipelineBarrier(const VulkanDevice &in_device, VkPipelineStageFlags src_stages = 0, VkPipelineStageFlags dst_stages = 0) :
    PipelineBarrier(in_device, BuiltinPipelineBarrierCache::data[builtinCacheIdx], src_stages, dst_stages)
  {}
};

} // namespace drv3d_vulkan
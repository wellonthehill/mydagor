#include "device.h"

#if _TARGET_ANDROID
#include <swappy/swappyVk.h>
#endif

using namespace drv3d_vulkan;

namespace
{
bool can_display(VulkanInstance &instance, VulkanPhysicalDeviceHandle device, VulkanSurfaceKHRHandle display_surface, uint32_t family)
{
  VkBool32 support;
  if (VULKAN_CHECK_FAIL(instance.vkGetPhysicalDeviceSurfaceSupportKHR(device, family, display_surface, &support)))
  {
    support = VK_FALSE;
  }
  return (support == VK_TRUE);
}

const char *queue_type_to_name(DeviceQueueType type)
{
  switch (type)
  {
    case DeviceQueueType::GRAPHICS: return "graphics";
    case DeviceQueueType::COMPUTE: return "compute";
    case DeviceQueueType::TRANSFER: return "transfer";
    default: break;
  }
  return "<error unreachable>";
}

struct FlatQueueInfo : DeviceQueueGroup::Info::Queue
{
  VkQueueFlags flags;
};

eastl::vector<FlatQueueInfo> flatten_queue_info(const eastl::vector<VkQueueFamilyProperties> &info)
{
  eastl::vector<FlatQueueInfo> result;
  FlatQueueInfo familyInfo;
  for (auto &&family : info)
  {
    familyInfo.family = &family - info.data();
    familyInfo.timestampBits = family.timestampValidBits;
    familyInfo.flags = family.queueFlags;
    if (family.queueFlags & (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT))
      familyInfo.flags |= VK_QUEUE_TRANSFER_BIT;
    for (familyInfo.index = 0; familyInfo.index < family.queueCount; ++familyInfo.index)
      result.push_back(familyInfo);
  }
  return result;
}

VkQueueFlags get_queue_flags_for_type(DeviceQueueType type)
{
  switch (type)
  {
    case DeviceQueueType::GRAPHICS: return VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT;
    case DeviceQueueType::COMPUTE: return VK_QUEUE_COMPUTE_BIT;
    case DeviceQueueType::TRANSFER: return VK_QUEUE_TRANSFER_BIT;
    default: break;
  }
  // unrechable, but make compiler happy
  return VK_QUEUE_GRAPHICS_BIT;
}

bool use_queue_for_display(DeviceQueueType type) { return type == DeviceQueueType::GRAPHICS; }

DeviceQueueType get_fallback_for(DeviceQueueType type)
{
  switch (type)
  {
    case DeviceQueueType::GRAPHICS: return DeviceQueueType::INVALID;
    case DeviceQueueType::COMPUTE: return DeviceQueueType::GRAPHICS;
    case DeviceQueueType::TRANSFER: return DeviceQueueType::COMPUTE;
    default: break;
  }
  // unrechable, but make comiler happy...
  return DeviceQueueType::INVALID;
}

eastl::vector<FlatQueueInfo>::iterator find_best_match(eastl::vector<FlatQueueInfo> &set, DeviceQueueType type,
  VulkanInstance &instance, VulkanPhysicalDeviceHandle device, VulkanSurfaceKHRHandle display_surface)
{
  const VkQueueFlags requiredFlags = get_queue_flags_for_type(type);
  const bool isUsedForDisplay = use_queue_for_display(type);
  uint32_t baseToManyBits = UINT32_MAX;
  auto base = end(set);
  for (auto at = begin(set); at != end(set); ++at)
  {
    if (requiredFlags != (at->flags & requiredFlags))
      continue;

    if (isUsedForDisplay)
      if (!can_display(instance, device, display_surface, at->family))
        continue;

    uint32_t toManyBits = count_bits(at->flags ^ requiredFlags);
    if (toManyBits < baseToManyBits)
    {
      baseToManyBits = toManyBits;
      base = at;
    }
  }
  return base;
}

bool select_queue(eastl::vector<FlatQueueInfo> &set, DeviceQueueType type, VulkanInstance &instance, VulkanPhysicalDeviceHandle device,
  VulkanSurfaceKHRHandle display_surface, FlatQueueInfo &selection)
{
  debug("vulkan: selecting %s queue...", queue_type_to_name(type));
  auto selected = find_best_match(set, type, instance, device, display_surface);
  if (selected != end(set))
  {
    selection = *selected;
    set.erase(selected);
    debug("vulkan: using family %u index %u as %s queue...", selection.family, selection.index, queue_type_to_name(type));
    return true;
  }
  debug("vulkan: no dedicated queue as %s queue found...", queue_type_to_name(type));
  return false;
}
} // namespace

bool DeviceQueueGroup::Info::init(VulkanInstance &instance, VulkanPhysicalDeviceHandle device, VulkanSurfaceKHRHandle display_surface,
  const eastl::vector<VkQueueFamilyProperties> &info)
{
  auto flatQueueInfo = flatten_queue_info(info);
  carray<FlatQueueInfo, uint32_t(DeviceQueueType::COUNT)> selected;
  carray<bool, uint32_t(DeviceQueueType::COUNT)> isAvialable;
  for (uint32_t i = 0; i < uint32_t(DeviceQueueType::COUNT); ++i)
  {
    isAvialable[i] = select_queue(flatQueueInfo, static_cast<DeviceQueueType>(i), instance, device, display_surface, selected[i]);
  }

  for (uint32_t i = 0; i < uint32_t(DeviceQueueType::COUNT); ++i)
  {
    if (isAvialable[i])
    {
      group[i].family = selected[i].family;
      group[i].index = selected[i].index;
      group[i].timestampBits = selected[i].timestampBits;
    }
    else
    {
      DeviceQueueType type = static_cast<DeviceQueueType>(i);
      for (;;)
      {
        type = get_fallback_for(type);
        if (DeviceQueueType::INVALID == type)
          return false;
        if (isAvialable[uint32_t(type)])
          break;
      }
      group[i] = group[uint32_t(type)];
      debug("vulkan: sharing %s queue as %s queue", queue_type_to_name(type), queue_type_to_name(static_cast<DeviceQueueType>(i)));
    }
  }

  computeCanPresent = can_display(instance, device, display_surface, group[uint32_t(DeviceQueueType::COMPUTE)].family);
  debug("vulkan: compute queue can display: %s", computeCanPresent ? "yes" : "no");


  return true;
}

void DeviceQueueGroup::tidy()
{
  for (int i = 0; i < group.size(); ++i)
  {
    if (group[i])
    {
      for (int j = i + 1; j < group.size(); ++j)
        if (group[i] == group[j])
          group[j] = nullptr;
      delete group[i];
      group[i] = nullptr;
    }
  }
}

DeviceQueueGroup::~DeviceQueueGroup() { tidy(); }

DeviceQueueGroup::DeviceQueueGroup(DeviceQueueGroup &&o) : computeCanPresent(o.computeCanPresent)
{
  mem_copy_from(group, o.group.data());
  mem_set_0(o.group);
}

DeviceQueueGroup &DeviceQueueGroup::operator=(DeviceQueueGroup &&o)
{
  tidy();
  mem_copy_from(group, o.group.data());
  mem_set_0(o.group);
  computeCanPresent = o.computeCanPresent;
  return *this;
}

DeviceQueueGroup::DeviceQueueGroup(VulkanDevice &device, const Info &info) : computeCanPresent(info.computeCanPresent)
{
  mem_set_0(group);
  for (int i = 0; i < info.group.size(); ++i)
  {
    if (!group[i])
    {
      VulkanQueueHandle queue;
      VULKAN_LOG_CALL(device.vkGetDeviceQueue(device.get(), info.group[i].family, info.group[i].index, ptr(queue)));
      group[i] = new DeviceQueue(queue, info.group[i].family, info.group[i].index, info.group[i].timestampBits);
      for (int j = i + 1; j < info.group.size(); ++j)
        if (info.group[i] == info.group[j])
          group[j] = group[i];

#if ENABLE_SWAPPY
      if (i == int(DeviceQueueType::GRAPHICS))
      {
        debug("vulkan: Setting queue family index for Swappy");
        SwappyVk_setQueueFamilyIndex(device.get(), queue, info.group[i].family);
        debug("vulkan: Setting queue family index for Swappy is done");
      }
#endif
    }
  }
}

namespace drv3d_vulkan
{
StaticTab<VkDeviceQueueCreateInfo, uint32_t(DeviceQueueType::COUNT)> build_queue_create_info(const DeviceQueueGroup::Info &info,
  const float *prioset)
{
  StaticTab<VkDeviceQueueCreateInfo, uint32_t(DeviceQueueType::COUNT)> result;
  for (uint32_t i = 0; i < info.group.size(); ++i)
  {
    const DeviceQueueGroup::Info::Queue &q = info.group[i];
    uint32_t j = 0;
    for (; j < result.size(); ++j)
    {
      VkDeviceQueueCreateInfo &createInfo = result[j];
      if (createInfo.queueFamilyIndex == q.family)
      {
        if (createInfo.queueCount <= q.index)
          createInfo.queueCount = q.index + 1;
        break;
      }
    }
    if (j == result.size())
    {
      VkDeviceQueueCreateInfo &createInfo = result.push_back();
      createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
      createInfo.pNext = nullptr;
      createInfo.flags = 0;
      createInfo.queueFamilyIndex = q.family;
      createInfo.queueCount = q.index + 1;
      createInfo.pQueuePriorities = prioset;
    }
  }
  return result;
}

VkResult DeviceQueue::present(VulkanDevice &device, const TrimmedPresentInfo &presentInfo)
{
  WinAutoLock lock{mutex};

  VkPresentInfoKHR pi = {};
  pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  pi.pWaitSemaphores = ary(submitSemaphores.data());
  pi.waitSemaphoreCount = submitSemaphores.size();

  pi.swapchainCount = presentInfo.swapchainCount;
  pi.pSwapchains = presentInfo.pSwapchains;
  pi.pImageIndices = presentInfo.pImageIndices;

  VkResult ret;
#if ENABLE_SWAPPY
  if (presentInfo.enableSwappy)
    ret = SwappyVk_queuePresent(handle, &pi);
  else
#endif
    ret = VULKAN_LOG_CALL_R(device.vkQueuePresentKHR(handle, &pi));
  // TODO: check if it considered waited on error or not, as it can bug out sync pretty easily
  clear_and_shrink(submitSemaphores);
  clear_and_shrink(submitSemaphoresLocation);
  return ret;
}
} // namespace drv3d_vulkan

#pragma once

namespace drv3d_dx12
{
struct RaytraceAccelerationStructure;
namespace resource_manager
{

#if _TARGET_PC_WIN
class ResourceHeapFeatureController : public BufferDescriptorProvider
{
  using BaseType = BufferDescriptorProvider;

  struct Features
  {
    enum Bits
    {
      IS_UMA,
      CAN_MIX_RESOURCES,
      COUNT
    };
    using Type = eastl::bitset<Bits::COUNT>;
  };

  Features::Type features{};

protected:
  void setup(const SetupInfo &info)
  {
    BaseType::setup(info);

    debug("DX12: Checking resource heap properties...");
    D3D12_FEATURE_DATA_ARCHITECTURE archInfo{};
    if (DX12_DEBUG_FAIL(info.device->CheckFeatureSupport(D3D12_FEATURE_ARCHITECTURE, &archInfo, sizeof(archInfo))))
    {
      // assume NUMA system
      features.reset(Features::IS_UMA);
      debug("DX12: Assuming NUMA memory architecture...");
    }
    else
    {
      features.set(Features::IS_UMA, FALSE != archInfo.UMA);
      debug("DX12: %s memory architecture...", archInfo.UMA ? "UMA" : "NUMA");
    }

    D3D12_FEATURE_DATA_D3D12_OPTIONS featureInfo{};
    if (DX12_DEBUG_FAIL(info.device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS, &featureInfo, sizeof(featureInfo))))
    {
      // assume D3D12_RESOURCE_HEAP_TIER_1
      features.reset(Features::CAN_MIX_RESOURCES);
      debug("DX12: Assuming resource heap tier 1...");
    }
    else
    {
      features.set(Features::CAN_MIX_RESOURCES, D3D12_RESOURCE_HEAP_TIER_2 <= featureInfo.ResourceHeapTier);
      debug("DX12: Resource heap tier %u...", static_cast<uint32_t>(featureInfo.ResourceHeapTier));
    }
  }

  // can be useful to make this available to the public
public:
  bool isUMASystem() const { return features.test(Features::IS_UMA); }
  bool canMixResources() const { return features.test(Features::CAN_MIX_RESOURCES); }
};

class MemoryBudgetObserver : public ResourceHeapFeatureController
{
  using BaseType = ResourceHeapFeatureController;

  void updateBudgetLevelStatus();

protected:
  struct MemoryPoolStatus : DXGI_QUERY_VIDEO_MEMORY_INFO
  {
    uint64_t reportedSize;
  };

  struct SetupInfo : BaseType::SetupInfo
  {
    DXGIAdapter *adapter;

    DXGIAdapter *getAdapter() const { return adapter; }
  };

  struct CompletedFrameExecutionInfo : BaseType::CompletedFrameExecutionInfo
  {
    DXGIAdapter *adapter;
  };

  static constexpr uint64_t page_size = 0x10000;
  static constexpr uint64_t static_texture_page_count = 0x1000;
  static constexpr uint64_t rtdsv_texture_page_count = 0x800;
  static constexpr uint64_t buffer_page_count = 0x400;
  static constexpr uint64_t upload_page_count = 0x400;
  static constexpr uint64_t read_back_page_count = 0x100;
  static constexpr uint64_t static_texture_heap_size_scale = 16;
  static constexpr uint64_t rtdsv_texture_heap_size_scale = 4;
  static constexpr uint64_t buffer_heap_size_scale = 8;
  static constexpr uint64_t upload_heap_size_scale = 4;
  static constexpr uint64_t read_back_heap_size_scale = 4;
  static constexpr uint64_t budget_scale_range = static_texture_heap_size_scale * 8;

  union ResourceHeapProperties
  {
    uint32_t raw = 0;
    struct
    {
      uint32_t isRenderTargetOrWriteCombined : 1;
      uint32_t isTexture : 1;
      uint32_t isL0Pool : 1;
    };

    // can only be b101 as b100 is cpu visible write back and b101 is cpu visible write combined,
    // any other bits for cpu visible is unused.
    static constexpr uint32_t max_value = 1 << 2 | 1 << 0;
    static constexpr uint32_t group_count = max_value + 1;
    static constexpr uint32_t bits = 3;

    void presetL0WriteCombine()
    {
      isL0Pool = 1;
      isTexture = 0;
      isRenderTargetOrWriteCombined = 1;
    }

    void presetL0WriteBack()
    {
      isL0Pool = 1;
      isTexture = 0;
      isRenderTargetOrWriteCombined = 0;
    }

    void presetL1Buffer()
    {
      isL0Pool = 0;
      isTexture = 0;
      isRenderTargetOrWriteCombined = 0;
    }

    void presetL1Texture()
    {
      isL0Pool = 0;
      isTexture = 1;
      isRenderTargetOrWriteCombined = 0;
    }

    void presetL1RenderTarget()
    {
      isL0Pool = 0;
      isTexture = 0;
      isRenderTargetOrWriteCombined = 1;
    }

    void presetL1RenderTargetMSAA()
    {
      isL0Pool = 0;
      isTexture = 1;
      isRenderTargetOrWriteCombined = 1;
    }

    void setBufferWriteCombinedCPUMemory() { presetL0WriteCombine(); }

    void setBufferWriteBackCPUMemory() { presetL0WriteBack(); }

    void setTextureMemory(bool is_unified, bool is_uma)
    {
      if (is_unified)
      {
        if (is_uma)
        {
          presetL0WriteCombine();
        }
        else
        {
          presetL1Buffer();
        }
      }
      else
      {
        presetL1Texture();
      }
    }

    void setRenderTargetMemory(bool is_unified, bool is_uma)
    {
      if (is_unified)
      {
        if (is_uma)
        {
          presetL0WriteCombine();
        }
        else
        {
          presetL1Buffer();
        }
      }
      else
      {
        presetL1RenderTarget();
      }
    }

    void setBufferMemory(bool is_uma)
    {
      if (is_uma)
      {
        presetL0WriteCombine();
      }
      else
      {
        presetL1Buffer();
      }
    }

    void setMSAARenderTargetMemory() { presetL1RenderTargetMSAA(); }

    constexpr D3D12_HEAP_TYPE getHeapType() const { return D3D12_HEAP_TYPE_CUSTOM; }

    D3D12_CPU_PAGE_PROPERTY getCpuPageProperty(bool is_uma) const
    {
      if (isL0Pool && !isRenderTargetOrWriteCombined)
      {
        return D3D12_CPU_PAGE_PROPERTY_WRITE_BACK;
      }
      else if (isL0Pool || is_uma)
      {
        return D3D12_CPU_PAGE_PROPERTY_WRITE_COMBINE;
      }
      else
      {
        return D3D12_CPU_PAGE_PROPERTY_NOT_AVAILABLE;
      }
    }

    D3D12_MEMORY_POOL getMemoryPool(bool is_uma) const { return (isL0Pool || is_uma) ? D3D12_MEMORY_POOL_L0 : D3D12_MEMORY_POOL_L1; }

    D3D12_HEAP_FLAGS getFlags(bool is_unified) const
    {
      if (is_unified)
      {
        return D3D12_HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES;
      }
      else
      {
        if (isL0Pool)
        {
          return D3D12_HEAP_FLAG_ALLOW_ONLY_BUFFERS;
        }
        else
        {
          // NOTE: that isTexture can be true here, so this **has** to be checked first.
          if (isRenderTargetOrWriteCombined)
          {
            return D3D12_HEAP_FLAG_ALLOW_ONLY_RT_DS_TEXTURES | D3D12_HEAP_FLAG_ALLOW_SHADER_ATOMICS;
          }
          else if (isTexture)
          {
            return D3D12_HEAP_FLAG_ALLOW_ONLY_NON_RT_DS_TEXTURES | D3D12_HEAP_FLAG_ALLOW_SHADER_ATOMICS;
          }
          else
          {
            return D3D12_HEAP_FLAG_ALLOW_ONLY_BUFFERS | D3D12_HEAP_FLAG_ALLOW_SHADER_ATOMICS;
          }
        }
      }
    }

    bool operator==(const ResourceHeapProperties &other) const { return raw == other.raw; }
    bool operator!=(const ResourceHeapProperties &other) const { return !(*this == other); }

    bool isCPUVisible() const { return 0 != isL0Pool; }

    uint64_t getAlignment() const
    {
      return (!isL0Pool && isRenderTargetOrWriteCombined && isTexture) ? D3D12_DEFAULT_MSAA_RESOURCE_PLACEMENT_ALIGNMENT
                                                                       : D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
    }
  };

  uint64_t getPoolBudget(uint32_t pool_type) const
  {
    auto &pool = poolStates[pool_type];
    return heapBudgetOffset[pool_type] < pool.Budget ? pool.Budget - heapBudgetOffset[pool_type] : pool.Budget;
  }

  uint64_t getAvailablePoolBudget(uint32_t pool_type) const
  {
    auto totalBudget = getPoolBudget(pool_type);

    auto &pool = poolStates[pool_type];
    if (pool.CurrentUsage > totalBudget)
    {
      return 0;
    }
    else if (host_local_memory_pool == pool_type)
    {
      uint64_t virtualTotal = heapBudgetOffset[host_local_memory_pool] < processVirtualTotal
                                ? processVirtualTotal - heapBudgetOffset[host_local_memory_pool]
                                : processVirtualTotal;
      // reduce to total 70% to account for fragmentation and other things
      virtualTotal = (virtualTotal * 7) / 10;
      return min(totalBudget - pool.CurrentUsage,
        virtualTotal > processVirtualAddressUse ? virtualTotal - processVirtualAddressUse : 0);
    }
    else
    {
      return totalBudget - pool.CurrentUsage;
    }
  }

  uint64_t getPhysicalLimit(uint32_t pool_type) const { return poolStates[pool_type].reportedSize; }

  static constexpr uint32_t device_local_memory_pool = 0;
  static constexpr uint32_t host_local_memory_pool = 1;
  static constexpr uint32_t total_memory_pool_count = 2;

  enum class BudgetPressureLevels
  {
    PANIC,
    HIGH,
    MEDIUM,
    LOW,
  };

  static constexpr uint32_t as_uint(BudgetPressureLevels l) { return static_cast<uint32_t>(l); }
  static const char *as_string(BudgetPressureLevels l)
  {
    switch (l)
    {
#define TO_S(name) \
  case BudgetPressureLevels::name: return #name
      TO_S(PANIC);
      TO_S(HIGH);
      TO_S(MEDIUM);
      TO_S(LOW);
#undef TO_S
      default: return "<unknown>";
    }
  }

  MemoryPoolStatus poolStates[total_memory_pool_count]{};
  uint64_t poolBudgetLevels[total_memory_pool_count][static_cast<uint32_t>(BudgetPressureLevels::LOW)]{};
  BudgetPressureLevels poolBudgetLevelstatus[total_memory_pool_count]{};
  uint64_t processVirtualAddressUse = 0;
  uint64_t processVirtualTotal = 0;
  enum class BehaviorBits
  {
    DISABLE_HOST_MEMORY_STATUS_QUERY,
    DISABLE_DEVICE_MEMORY_STATUS_QUERY,
    DISABLE_VIRTUAL_ADDRESS_SPACE_STATUS_QUERY,

    COUNT
  };
  TypedBitSet<BehaviorBits> behaviorStatus;
  // offsets are used to artificially shrink the available budged value we use for further calculations
  uint64_t heapBudgetOffset[total_memory_pool_count]{};

  uint64_t getDeviceLocalRawBudget() const { return poolStates[device_local_memory_pool].Budget; }

  uint64_t getDeviceLocalHeapBudgetOffset() const { return heapBudgetOffset[device_local_memory_pool]; }

  void setDeviceLocalHeapBudgetOffset(uint64_t offset) { heapBudgetOffset[device_local_memory_pool] = offset; }

  BudgetPressureLevels getDeviceLocalBudgetLevel() const { return poolBudgetLevelstatus[device_local_memory_pool]; }

public:
  uint64_t getDeviceLocalBudget() const { return getPoolBudget(device_local_memory_pool); }

  uint64_t getDeviceLocalAvailablePoolBudget() const { return getAvailablePoolBudget(device_local_memory_pool); }

  uint64_t getDeviceLocalPhysicalLimit() const { return getPhysicalLimit(device_local_memory_pool); }

protected:
  uint64_t getDeviceLocalBudgetLimit(BudgetPressureLevels level) const
  {
    return poolBudgetLevels[device_local_memory_pool][as_uint(level)];
  }

  uint64_t getDeviceLocalAvailableForReservation() const { return poolStates[device_local_memory_pool].AvailableForReservation; }

  uint64_t getHostLocalRawBudget() const { return poolStates[host_local_memory_pool].Budget; }

  uint64_t getHostLocalHeapBudgetOffset() const { return heapBudgetOffset[host_local_memory_pool]; }

  void setHostLocalHeapBudgetOffset(uint64_t offset) { heapBudgetOffset[host_local_memory_pool] = offset; }

public:
  uint64_t getHostLocalBudget() const { return getPoolBudget(host_local_memory_pool); }

  uint64_t getHostLocalAvailablePoolBudget() const { return getAvailablePoolBudget(host_local_memory_pool); }

  uint64_t getHostLocalPhysicalLimit() const { return getPhysicalLimit(host_local_memory_pool); }

protected:
  BudgetPressureLevels getHostLocalBudgetLevel() const { return poolBudgetLevelstatus[host_local_memory_pool]; }

  uint64_t getHostLocalBudgetLimit(BudgetPressureLevels level) const
  {
    return poolBudgetLevels[host_local_memory_pool][as_uint(level)];
  }

  // updates done to CurrentUsage are later overwritten by an update of the structures by completeFrameExecution
  // we just modify them to have a good proximate value in between frames to make informed decisions on resource
  // allocation.
  void recordHeapAllocated(uint32_t size, bool is_gpu)
  {
    BaseType::recordHeapAllocated(size, is_gpu);
    if (is_gpu)
    {
      poolStates[device_local_memory_pool].CurrentUsage += size;
      behaviorStatus.reset(BehaviorBits::DISABLE_DEVICE_MEMORY_STATUS_QUERY);
    }
    else
    {
      poolStates[host_local_memory_pool].CurrentUsage += size;
      behaviorStatus.reset(BehaviorBits::DISABLE_HOST_MEMORY_STATUS_QUERY);
    }

    updateBudgetLevelStatus();
  }

  void recordHeapFreed(uint32_t size, bool is_gpu)
  {
    BaseType::recordHeapFreed(size, is_gpu);
    if (is_gpu)
    {
      poolStates[device_local_memory_pool].CurrentUsage -= size;
      behaviorStatus.reset(BehaviorBits::DISABLE_DEVICE_MEMORY_STATUS_QUERY);
    }
    else
    {
      poolStates[host_local_memory_pool].CurrentUsage -= size;
      behaviorStatus.reset(BehaviorBits::DISABLE_HOST_MEMORY_STATUS_QUERY);
    }

    updateBudgetLevelStatus();
  }

  void setup(const SetupInfo &info);

  bool shouldTrimFramePushRingBuffer() const { return getHostLocalBudgetLevel() < BudgetPressureLevels::HIGH; }

  bool shouldTrimUploadRingBuffer() const { return getHostLocalBudgetLevel() < BudgetPressureLevels::HIGH; }

  // Checks current memory status of the system and updates the behavior of the memory manager depending on
  // the memory usage pressure.
  void completeFrameExecution(const CompletedFrameExecutionInfo &info, PendingForCompletedFrameData &data);

  enum class AllocationFlag
  {
    DEDICATED_HEAP,
    DISALLOW_LOCKED_RANGES,
    DISALLOW_LOCKED_HEAP,
    EXISTING_HEAPS_ONLY,
    NEW_HEAPS_ONLY_WITH_BUDGET,

    COUNT
  };

  using AllocationFlags = TypedBitSet<AllocationFlag>;

  uint64_t getHeapSizeFromAllocationSize(uint64_t size, ResourceHeapProperties properties, AllocationFlags flags);
};
#else
#include "resource_memory_heap_heap_components_xbox.inl.h"
#endif

class ResourceMemoryHeapBase : public MemoryBudgetObserver
{
  using BaseType = MemoryBudgetObserver;

protected:
  struct AliasHeapReference
  {
    uint32_t index;
  };
  struct ScratchBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct PushRingBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct UploadRingBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct TempUploadBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct PersistentUploadBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct PersistentReadBackBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct PersistentBidirectionalBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct RaytraceScratchBufferReference
  {
    ID3D12Resource *buffer;
  };
  struct RaytraceBottomLevelAccelerationStructureRefnerence
  {
    RaytraceAccelerationStructure *as;
  };
  struct RaytraceTopLevelAccelerationStructureRefnerence
  {
    RaytraceAccelerationStructure *as;
  };
  using AnyResourceReference = eastl::variant<eastl::monostate, Image *, BufferGlobalId, AliasHeapReference, ScratchBufferReference,
    PushRingBufferReference, UploadRingBufferReference, TempUploadBufferReference, PersistentUploadBufferReference,
    PersistentReadBackBufferReference, PersistentBidirectionalBufferReference, RaytraceScratchBufferReference,
    RaytraceBottomLevelAccelerationStructureRefnerence, RaytraceTopLevelAccelerationStructureRefnerence>;
  struct HeapResourceInfo
  {
    ValueRange<uint32_t> range;
    AnyResourceReference resource;

    HeapResourceInfo() = default;
    HeapResourceInfo(const HeapResourceInfo &) = default;
    HeapResourceInfo(ValueRange<uint32_t> r) : range{r} {}
  };
  struct BasicResourceHeap
  {
    using FreeRangeSetType = eastl::vector<ValueRange<uint32_t>>;
    using UsedRangeSetType = eastl::vector<HeapResourceInfo>;
    FreeRangeSetType freeRanges;
    UsedRangeSetType usedRanges;
    ValueRange<uint32_t> lockedRange{};
    uint32_t totalSize = 0;
    static constexpr uint64_t fragmentation_range = 10000;
    uint32_t fragmentation = 0;

    void updateFragmentation()
    {
      FragmentationCalculatorContext ctx;
      ctx.fragments(freeRanges);
      if (ctx.totalSize())
        fragmentation = fragmentation_range - ((ctx.maxSize() * fragmentation_range) / ctx.totalSize());
    }

    uint32_t freeSize() const
    {
      return eastl::accumulate(begin(freeRanges), end(freeRanges), 0, [](uint32_t v, auto range) { return v + range.size(); });
    }

    uint32_t allocatedSize() const { return totalSize - freeSize(); }

    void lock(ValueRange<uint32_t> range)
    {
      G_ASSERT(!isLocked());
      lockedRange = range;
    }

    void unlock() { lockedRange.reset(); }

    bool isLocked() const { return !lockedRange.empty(); }

    bool isFree() const { return freeRanges.front().size() == totalSize; }

    auto findUsedInfo(ValueRange<uint32_t> range)
    {
      return eastl::lower_bound(begin(usedRanges), end(usedRanges), range,
        [](auto &info, auto range) //
        { return info.range.front() < range.front(); });
    }

    void freeRange(ValueRange<uint32_t> range)
    {
      auto rangeRef = findUsedInfo(range);
      G_ASSERT(rangeRef != end(usedRanges) && rangeRef->range == range);
      if (rangeRef != end(usedRanges) && rangeRef->range == range)
      {
        usedRanges.erase(rangeRef);
      }
      free_list_insert_and_coalesce(freeRanges, range);
      updateFragmentation();
    }

    template <typename T>
    void updateMemoryRangeUse(ValueRange<uint32_t> range, T &&ref)
    {
      auto rangeRef = findUsedInfo(range);
      G_ASSERT(rangeRef != end(usedRanges) && rangeRef->range == range);
      if (rangeRef != end(usedRanges) && rangeRef->range == range)
      {
        rangeRef->resource = eastl::forward<T>(ref);
      }
    }

    template <typename T>
    FreeRangeSetType::iterator selectFirstRange(const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info, T ignore_locked_range)
    {
      auto ed = end(freeRanges);
      auto at = begin(freeRanges);
      auto shouldIgnoreLockedRange = ignore_locked_range || !isLocked();
      for (; at != ed; ++at)
      {
        if (!shouldIgnoreLockedRange && lockedRange.overlaps(*at))
        {
          continue;
        }
        auto alignedStart = align_value<uint32_t>(at->front(), alloc_info.Alignment);
        auto possibleAllocRange = make_value_range(alignedStart, alloc_info.SizeInBytes);
        if (possibleAllocRange.isSubRangeOf(*at))
        {
          break;
        }
      }
      return at;
    }

    template <typename T>
    FreeRangeSetType::iterator selectSmallestRange(const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info,
      FreeRangeSetType::iterator selected, T ignore_locked_range)
    {
      auto ed = end(freeRanges);
      if (selected != ed)
      {
        auto shouldIgnoreLockedRange = ignore_locked_range || !isLocked();
        auto at = selected;
        for (++at; at != ed && selected->size() != alloc_info.SizeInBytes; ++at)
        {
          if (!shouldIgnoreLockedRange && lockedRange.overlaps(*at))
          {
            continue;
          }
          if (at->size() > selected->size())
          {
            continue;
          }
          auto alignedStart = align_value<uint32_t>(at->front(), alloc_info.Alignment);
          auto possibleAllocRange = make_value_range(alignedStart, alloc_info.SizeInBytes);
          if (!possibleAllocRange.isSubRangeOf(*at))
          {
            continue;
          }
          selected = at;
        }
      }
      return selected;
    }

    template <typename T>
    FreeRangeSetType::iterator selectRange(const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info, T ignore_locked_range)
    {
      return selectSmallestRange(alloc_info, selectFirstRange(alloc_info, ignore_locked_range), ignore_locked_range);
    }

    bool isValidRange(FreeRangeSetType::iterator selected) { return end(freeRanges) != selected; }

    ValueRange<uint32_t> allocateFromRange(const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info, FreeRangeSetType::iterator selected)
    {
      auto alignedStart = align_value<uint32_t>(selected->front(), alloc_info.Alignment);
      ;
      auto possibleAllocRange = make_value_range(alignedStart, alloc_info.SizeInBytes);

      if (!possibleAllocRange.isSubRangeOf(*selected))
      {
        return {};
      }

      auto folowup = selected->cutOut(possibleAllocRange);
      if (!folowup.empty())
      {
        if (selected->empty())
        {
          *selected = folowup;
        }
        else
        {
          freeRanges.insert(selected + 1, folowup);
        }
      }
      else if (selected->empty())
      {
        freeRanges.erase(selected);
      }

      updateFragmentation();

      // Add tracking info now, user of memory has to update the entry with its usage info
      auto insertPoint = eastl::lower_bound(begin(usedRanges), end(usedRanges), possibleAllocRange,
        [](auto &info, auto range) //
        { return info.range.front() < range.front(); });
      usedRanges.emplace(insertPoint, possibleAllocRange);
      // if we can no longer allocate anything at this heap, we can shrink the tracking of used
      // ranges to save a bit or memory
      if (freeRanges.empty())
      {
        usedRanges.shrink_to_fit();
      }

      return possibleAllocRange;
    }
  };
  struct HeapGroupExtraData
  {
    uint64_t freeMemorySize = 0;
    uint32_t generation = 0;
    union
    {
      uint32_t rawFlagBits = 0;
      struct
      {
        uint32_t defragFragmentedSpace : 1;
        uint32_t defragUnusedHeaps : 1;
      };
    };

    void reset()
    {
      freeMemorySize = 0;
      generation = 0;
      rawFlagBits = 0;
    }
  };
  enum class DefragmentationReason
  {
    // Allocate had to allocate a new heap because there was enough total free space but no enough contiguous free space
    FRAGMENTED_FREE_SPACE,
    // Defragger should try to move objects around to free a memory heap back to the system
    FREE_UNUSED_HEAPS,
  };
  // Extra platform independent heap group data.
  HeapGroupExtraData heapGroupExtraData[ResourceHeapProperties::group_count];
  OSSpinlock heapGroupMutex;

  void setup(const SetupInfo &info)
  {
    {
      OSSpinlockScopedLock lock{heapGroupMutex};
      for (auto &data : heapGroupExtraData)
      {
        data.reset();
      }
    }
    BaseType::setup(info);
  }

  uint64_t getHeapGroupFreeMemorySize(uint32_t heap_group) const { return heapGroupExtraData[heap_group].freeMemorySize; }
  void addHeapGroupFreeSpace(uint32_t heap_group, uint64_t size) { heapGroupExtraData[heap_group].freeMemorySize += size; }
  void subtractHeapGroupFreeSpace(uint32_t heap_group, uint64_t size) { heapGroupExtraData[heap_group].freeMemorySize -= size; }
  void updateHeapGroupNeedsDefragmentation(uint32_t heap_group, DefragmentationReason reason)
  {
    auto &data = heapGroupExtraData[heap_group];
    if (DefragmentationReason::FRAGMENTED_FREE_SPACE == reason)
    {
      data.defragFragmentedSpace = 1;
    }
    else if (DefragmentationReason::FREE_UNUSED_HEAPS == reason)
    {
      data.defragUnusedHeaps = 1;
    }
  }
  void updateHeapGroupGeneration(uint32_t heap_group) { ++heapGroupExtraData[heap_group].generation; }
  uint32_t getHeapGroupGeneration(uint32_t heap_group) const { return heapGroupExtraData[heap_group].generation; }
  bool heapGroupNeedsDefragmentation(uint32_t heap_group) const
  {
    auto &group = heapGroupExtraData[heap_group];
    return 0 != (group.defragUnusedHeaps | group.defragFragmentedSpace);
  }
  void resetHeapGroupDefragmentationFlags(uint32_t heap_group)
  {
    auto &group = heapGroupExtraData[heap_group];

    group.defragFragmentedSpace = 0;
    group.defragUnusedHeaps = 0;
  }

  // Helper to iterate over free and used range in order of offset into the heap
  // Usage: for(BasicResourceHeapRangesIterator it{heap}; it; ++it) {<do stuff with it>}
  class BasicResourceHeapRangesIterator
  {
    BasicResourceHeap &parent;
    BasicResourceHeap::FreeRangeSetType::iterator freeRangePos;
    BasicResourceHeap::UsedRangeSetType::iterator usedRangePos;

  public:
    BasicResourceHeapRangesIterator(BasicResourceHeap &p) :
      parent{p}, freeRangePos{begin(p.freeRanges)}, usedRangePos{begin(p.usedRanges)}
    {}

    BasicResourceHeapRangesIterator(const BasicResourceHeapRangesIterator &) = default;

    // prefix
    BasicResourceHeapRangesIterator &operator++()
    {
      if (isFreeRange())
      {
        ++freeRangePos;
      }
      else if (isUsedRange())
      {
        ++usedRangePos;
      }
      return *this;
    }

    // postfix
    BasicResourceHeapRangesIterator operator++(int) const
    {
      auto copy = *this;
      return ++(copy);
    }

    // If we reach the end, both isFreeRange and isUsedRange will return false
    bool isFreeRange() const
    {
      if (end(parent.freeRanges) == freeRangePos)
      {
        return false;
      }
      if (end(parent.usedRanges) == usedRangePos)
      {
        return true;
      }
      return freeRangePos->front() < usedRangePos->range.front();
    }

    // If we reach the end, both isFreeRange and isUsedRange will return false
    bool isUsedRange() const
    {
      if (end(parent.usedRanges) == usedRangePos)
      {
        return false;
      }
      if (end(parent.freeRanges) == freeRangePos)
      {
        return true;
      }
      return usedRangePos->range.front() < freeRangePos->front();
    }

    // Will return true until the end is reached
    explicit operator bool() const { return (end(parent.freeRanges) != freeRangePos) || (end(parent.usedRanges) != usedRangePos); }

    // Undefined behavior if static_cast<boo>(*this) == false
    const ValueRange<uint32_t> &getRange() const
    {
      G_ASSERT(static_cast<bool>(*this));
      if (isFreeRange())
      {
        return *freeRangePos;
      }
      return usedRangePos->range;
    }

    // Undefined behavior if static_cast<boo>(*this) == false
    const ValueRange<uint32_t> &operator*() const { return getRange(); }

    // Undefined behavior if static_cast<boo>(*this) == false
    const ValueRange<uint32_t> *operator->() const { return &getRange(); }

    // Undefined behavior if isUsedRange returns false for this
    auto getUsedResource() const -> eastl::add_lvalue_reference_t<decltype(usedRangePos->resource)>
    {
      G_ASSERT(isUsedRange());
      return usedRangePos->resource;
    }
  };

  static ResourceHeapProperties getHeapGroupProperties(::ResourceHeapGroup *heap)
  {
    ResourceHeapProperties props;
    props.raw = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(heap));
    return props;
  }

  static ResourceHeapProperties getHeapProperties(HeapID id)
  {
    ResourceHeapProperties props;
    props.raw = id.group;
    return props;
  }
};

#if _TARGET_XBOX
class ResourceMemoryHeapProvider : public ResourceMemoryHeapBase
{
  using BaseType = ResourceMemoryHeapBase;

protected:
  ResourceMemoryHeapProvider() = default;
  ~ResourceMemoryHeapProvider() = default;
  ResourceMemoryHeapProvider(const ResourceMemoryHeapProvider &) = delete;
  ResourceMemoryHeapProvider &operator=(const ResourceMemoryHeapProvider &) = delete;
  ResourceMemoryHeapProvider(ResourceMemoryHeapProvider &&) = delete;
  ResourceMemoryHeapProvider &operator=(ResourceMemoryHeapProvider &&) = delete;

  struct ResourceHeap : BaseType::BasicResourceHeap
  {
    eastl::unique_ptr<uint8_t[], VirtualFreeCaller> heap;

    bool isPartOf(ResourceMemory mem) const
    {
      auto e = heap.get() + totalSize;
      return heap.get() <= mem.asPointer() && e > mem.asPointer();
    }

    // only valid if isPartOf(mem) is true
    uint32_t calculateOffset(ResourceMemory mem) const { return mem.asPointer() - heap.get(); }

    uint8_t *heapPointer() const { return heap.get(); }

    explicit operator bool() const { return heap.get() != nullptr; }

    void free(ResourceMemory mem)
    {
      auto offset = mem.asPointer() - heap.get();
      auto range = make_value_range(offset, mem.size());
      freeRange(range);
    }

    ResourceMemory allocate(const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info, HeapID heap_id, FreeRangeSetType::iterator selected)
    {
      G_ASSERT(isValidRange(selected));
      auto range = allocateFromRange(alloc_info, selected);
      G_ASSERT(!range.empty());
      return {heap.get() + range.front(), range.size(), heap_id};
    }
  };

  eastl::vector<ResourceHeap> groups[ResourceHeapProperties::group_count];
  bool lockedHeaps = false;

  void listHeaps()
  {
    ByteUnits totalSize;
    ByteUnits freeSize;
    size_t totalHeapCount = 0;
    struct ResourceHeapVisitor
    {
      ByteUnits &totalSize;
      ByteUnits &freeSize;
      size_t &totalHeapCount;

      void visitHeapGroup(uint32_t ident, size_t count, bool is_cpu_visible, bool is_cpu_cached, bool is_gpu_executable)
      {
        debug("DX12: Heap Group %08X (%s, %s%s) with %d heaps", ident, is_cpu_visible ? "CPU visible" : "dedicated GPU",
          is_cpu_visible ? is_cpu_cached ? "CPU cached, " : "CPU write combine, " : "",
          is_gpu_executable ? "GPU executable" : "Not GPU executable", count);
        totalHeapCount += count;
      }

      void visitHeap(ByteUnits total_size, ByteUnits free_size, uint32_t fragmentation_percent)
      {
        totalSize += total_size;
        freeSize += free_size;
        debug("DX12: Size %6.2f %7s Free %6.2f %7s, %3u%% fragmentation", total_size.units(), total_size.name(), free_size.units(),
          free_size.name(), fragmentation_percent);
      }
    };
    visitHeaps(ResourceHeapVisitor{totalSize, freeSize, totalHeapCount});
    debug("DX12: %u resource heaps, with %6.2f %7s in total and %6.2f %7s free", totalHeapCount, totalSize.units(), totalSize.name(),
      freeSize.units(), freeSize.name());
  }

public:
  static D3D12_RESOURCE_STATES propertiesToInitialState(D3D12_RESOURCE_DIMENSION dim, D3D12_RESOURCE_FLAGS flags,
    DeviceMemoryClass memory_class);
  static ResourceHeapProperties getProperties(D3D12_RESOURCE_FLAGS flags, DeviceMemoryClass memory_class, uint64_t aligment);
  static ResourceHeapProperties getPropertiesFromMemory(ResourceMemory memory)
  {
    ResourceHeapProperties p;
    p.raw = memory.getHeapID().group;
    return p;
  }
  void updateMemoryRangeUse(ResourceMemory mem, Image *texture)
  {
    auto heapID = mem.getHeapID();
    if (heapID.isAlias)
    {
      return;
    }

    auto &group = groups[heapID.group];

    OSSpinlockScopedLock lock{heapGroupMutex};
    auto &heap = group[heapID.index];
    heap.updateMemoryRangeUse(make_value_range(heap.calculateOffset(mem), mem.size()), texture);
  }
  void updateMemoryRangeUse(ResourceMemory mem, BufferGlobalId buffer_id)
  {
    auto heapID = mem.getHeapID();
    if (heapID.isAlias)
    {
      return;
    }

    auto &group = groups[heapID.group];

    OSSpinlockScopedLock lock{heapGroupMutex};
    auto &heap = group[heapID.index];
    heap.updateMemoryRangeUse(make_value_range(heap.calculateOffset(mem), mem.size()), buffer_id);
  }
  template <typename T>
  void updateMemoryRangeUse(ResourceMemory mem, T &&ref)
  {
    auto heapID = mem.getHeapID();
    auto &group = groups[heapID.group];

#if _TARGET_XBOXONE
    auto properties = getHeapProperties(heapID);
    if (properties.isESRAM)
    {
      return;
    }
#endif

    OSSpinlockScopedLock lock{heapGroupMutex};
    auto &heap = group[heapID.index];
    heap.updateMemoryRangeUse(make_value_range(heap.calculateOffset(mem), mem.size()), eastl::forward<T>(ref));
  }

protected:
  void setup(const SetupInfo &info);
  void shutdown();
  void preRecovery();

public:
  static D3D12_RESOURCE_STATES getInitialTextureResourceState(D3D12_RESOURCE_FLAGS flags);

  bool preAllocateHeap(ResourceHeapProperties properties, size_t heap_size);

  ResourceMemory allocate(DXGIAdapter *adapter, ID3D12Device *device, ResourceHeapProperties props,
    const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info, AllocationFlags flags);
  void free(ResourceMemory allocation);

  template <typename T>
  void visitHeaps(T clb)
  {
    ResourceHeapProperties properties;
    OSSpinlockScopedLock lock{heapGroupMutex};
    for (properties.raw = 0; properties.raw < array_size(groups); ++properties.raw)
    {
      auto &group = groups[properties.raw];
      clb.visitHeapGroup(properties.raw, group.size(), true, 0 != properties.isCPUCoherent, 0 != properties.isGPUExecutable);
      for (auto &heap : group)
      {
        size_t freeSize = 0;
        for (auto r : heap.freeRanges)
        {
          freeSize += r.size();
        }
        clb.visitHeap(heap.totalSize, freeSize, free_list_calculate_fragmentation(heap.freeRanges));
      }
    }
  }
};
#else
class ResourceMemoryHeapProvider : public ResourceMemoryHeapBase
{
  using BaseType = ResourceMemoryHeapBase;

protected:
  ResourceMemoryHeapProvider() = default;
  ~ResourceMemoryHeapProvider() = default;
  ResourceMemoryHeapProvider(const ResourceMemoryHeapProvider &) = delete;
  ResourceMemoryHeapProvider &operator=(const ResourceMemoryHeapProvider &) = delete;
  ResourceMemoryHeapProvider(ResourceMemoryHeapProvider &&) = delete;
  ResourceMemoryHeapProvider &operator=(ResourceMemoryHeapProvider &&) = delete;

  struct ResourceHeap : BaseType::BasicResourceHeap
  {
    ComPtr<ID3D12Heap> heap;

    bool isPartOf(ResourceMemory mem) const { return mem.getHeap() == heap.Get(); }

    // only valid if isPartOf(mem) is true
    uint32_t calculateOffset(ResourceMemory mem) const { return mem.getRange().front(); }

    ID3D12Heap *heapPointer() const { return heap.Get(); }

    explicit operator bool() const { return heap.Get() != nullptr; }

    void free(ResourceMemory mem) { freeRange(mem.getRange()); }

    ResourceMemory allocate(const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info, HeapID heap_id, FreeRangeSetType::iterator selected)
    {
      G_ASSERT(isValidRange(selected));
      auto range = allocateFromRange(alloc_info, selected);
      G_ASSERT(!range.empty());
      return {heap.Get(), range, heap_id};
    }
  };

  eastl::vector<ResourceHeap> groups[ResourceHeapProperties::group_count];

public:
  static D3D12_RESOURCE_STATES propertiesToInitialState(D3D12_RESOURCE_DIMENSION dim, D3D12_RESOURCE_FLAGS flags,
    DeviceMemoryClass memory_class);
  ResourceHeapProperties getProperties(D3D12_RESOURCE_FLAGS flags, DeviceMemoryClass memory_class, uint64_t aligment);
  static ResourceHeapProperties getPropertiesFromMemory(ResourceMemory memory)
  {
    ResourceHeapProperties p;
    p.raw = memory.getHeapID().group;
    return p;
  }
  void updateMemoryRangeUse(ResourceMemory mem, Image *texture)
  {
    auto heapID = mem.getHeapID();
    if (heapID.isAlias)
    {
      return;
    }

    auto &group = groups[heapID.group];

    OSSpinlockScopedLock lock{heapGroupMutex};
    auto &heap = group[heapID.index];
    heap.updateMemoryRangeUse(mem.getRange(), texture);
  }
  void updateMemoryRangeUse(ResourceMemory mem, BufferGlobalId buffer_id)
  {
    auto heapID = mem.getHeapID();
    if (heapID.isAlias)
    {
      return;
    }

    auto &group = groups[heapID.group];

    OSSpinlockScopedLock lock{heapGroupMutex};
    auto &heap = group[heapID.index];
    heap.updateMemoryRangeUse(mem.getRange(), buffer_id);
  }
  template <typename T>
  void updateMemoryRangeUse(ResourceMemory mem, T &&ref)
  {
    auto heapID = mem.getHeapID();
    auto &group = groups[heapID.group];

    OSSpinlockScopedLock lock{heapGroupMutex};
    auto &heap = group[heapID.index];
    heap.updateMemoryRangeUse(mem.getRange(), eastl::forward<T>(ref));
  }

protected:
  void shutdown();
  void preRecovery();

public:
  static D3D12_RESOURCE_STATES getInitialTextureResourceState(D3D12_RESOURCE_FLAGS flags);

  ResourceMemory allocate(DXGIAdapter *adapter, ID3D12Device *device, ResourceHeapProperties props,
    const D3D12_RESOURCE_ALLOCATION_INFO &alloc_info, AllocationFlags flags);
  void free(ResourceMemory allocation);

  template <typename T>
  void visitHeaps(T clb)
  {
    ResourceHeapProperties props;
    OSSpinlockScopedLock lock{heapGroupMutex};
    for (props.raw = 0; props.raw < array_size(groups); ++props.raw)
    {
      auto &group = groups[props.raw];
      clb.visitHeapGroup(props.raw, group.size(), props.isCPUVisible(),
        props.getCpuPageProperty(isUMASystem()) == D3D12_CPU_PAGE_PROPERTY_WRITE_BACK, true);
      for (auto &heap : group)
      {
        size_t freeSize = 0;
        for (auto r : heap.freeRanges)
        {
          freeSize += r.size();
        }
        clb.visitHeap(heap.totalSize, freeSize, free_list_calculate_fragmentation(heap.freeRanges));
      }
    }
  }
};
#endif

} // namespace resource_manager
} // namespace drv3d_dx12

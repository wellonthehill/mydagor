#pragma once

#include <3d/dag_drv3dConsts.h>

#include "vulkan_device.h"

namespace drv3d_vulkan
{

constexpr uint32_t program_type_bits = 2;
constexpr uint32_t program_type_mask = 1 | 2;
constexpr uint32_t program_type_graphics = 0;
constexpr uint32_t program_type_compute = 1;
constexpr uint32_t program_type_raytrace = 2;

inline int get_program_type(ProgramID id) { return id.get() & program_type_mask; }

inline uint32_t program_to_index(ProgramID id) { return id.get() >> program_type_bits; }

template <typename ItemType, typename IdType>
class ShaderProgramDatabaseStorage;

template <uint32_t progTypeId>
struct ProgramIDWrapper
{
  static ProgramID makeID(LinearStorageIndex index) { return ProgramID((index << program_type_bits) | progTypeId); }

  static bool checkID(ProgramID id) { return progTypeId == get_program_type(id); }

  static LinearStorageIndex getIndexFromID(ProgramID id) { return program_to_index(id); }
};

struct BaseProgram
{
  bool inRemoval = false;
  bool isRemovalPending() { return inRemoval; }
  void removeFromContext(DeviceContext &ctx, ProgramID prog);
};

struct GraphicsProgram : ProgramIDWrapper<program_type_graphics>, BaseProgram
{
  InputLayoutID inputLayout;
  ShaderInfo *vertexShader;
  ShaderInfo *fragmentShader;
  ShaderInfo *geometryShader;
  ShaderInfo *controlShader;
  ShaderInfo *evaluationShader;
  uint32_t refCount = 1;

  struct CreationInfo
  {
    InputLayoutID layout;
    ShaderInfo *vs;
    ShaderInfo *fs;

    uint32_t getHash32() const
    {
      return (uint32_t)layout.get() ^ mem_hash_fnv1<32>((const char *)&vs, sizeof(vs)) ^
             mem_hash_fnv1<32>((const char *)&fs, sizeof(fs));
    }
  };

  GraphicsProgram(const CreationInfo &info);

  bool isSame(const CreationInfo &obj) const
  {
    if (inputLayout != obj.layout)
      return false;

    // as the geometry shader is a child of vs this is enough
    if (vertexShader != obj.vs)
      return false;

    if (fragmentShader != obj.fs)
      return false;

    return true;
  }

  bool usesVertexShader(ShaderInfo *shader) const { return vertexShader == shader; }

  bool usesFragmentShader(ShaderInfo *shader) const { return fragmentShader == shader; }

  static constexpr bool alwaysUnique() { return false; }
  bool release()
  {
    G_ASSERT(refCount > 0);
    return --refCount == 0;
  }
  void onDuplicateAddition() { ++refCount; }
  void addToContext(DeviceContext &ctx, ProgramID prog, const CreationInfo &);
};

struct ComputeProgram : ProgramIDWrapper<program_type_compute>, BaseProgram
{
  struct CreationInfo
  {
    const Tab<spirv::ChunkHeader> &chunks;
    const Tab<uint8_t> &chunk_data;

    CreationInfo() = delete;

    uint32_t getHash32() const { return 0; }
  };

  ComputeProgram(const CreationInfo &){};
  static constexpr bool alwaysUnique() { return true; }
  bool isSame(const CreationInfo &) { return false; }
  bool release() { return true; }
  void onDuplicateAddition() {}
  void addToContext(DeviceContext &ctx, ProgramID prog, const CreationInfo &info);
};

#if D3D_HAS_RAY_TRACING

struct RaytraceProgram : ProgramIDWrapper<program_type_raytrace>, BaseProgram
{
  eastl::unique_ptr<ShaderInfo *[]> shaders;
  eastl::unique_ptr<RaytraceShaderGroup[]> shaderGroups;
  uint32_t groupCount = 0;
  uint32_t shaderCount = 0;
  uint32_t maxRecursionDepth = 0;

  struct CreationInfo
  {
    ShaderProgramDatabaseStorage<ShaderInfo, ShaderID> &shaders;
    const ShaderID *shader_ids;
    uint32_t shader_count;
    const RaytraceShaderGroup *shader_groups;
    uint32_t group_count;
    uint32_t max_recursion_depth;

    CreationInfo() = delete;

    uint32_t getHash32() const { return 0; }
  };

  RaytraceProgram(const CreationInfo &info) :
    shaderCount(info.shader_count), groupCount(info.group_count), maxRecursionDepth(info.max_recursion_depth)
  {
    shaders.reset(new ShaderInfo *[shaderCount]);
    shaderGroups.reset(new RaytraceShaderGroup[groupCount]);
  }

  static constexpr bool alwaysUnique() { return true; }
  bool isSame(const CreationInfo &) { return false; }
  bool release() { return true; }
  void onDuplicateAddition() {}
  void addToContext(DeviceContext &ctx, ProgramID prog, const CreationInfo &info);
};

#endif

} // namespace drv3d_vulkan
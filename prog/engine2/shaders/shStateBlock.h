#pragma once

#include "nonRelocCont.h"
#include <dag/dag_vector.h>
#include <EASTL/fixed_vector.h>
#include <memory/dag_framemem.h>
#include <shaders/dag_shaders.h>
#include <math/dag_Point4.h>
#include <math/integer/dag_IPoint4.h>
#include <3d/dag_drv3dCmd.h>
#include <generic/dag_patchTab.h>
#include <shaders/dag_renderStateId.h>
#include <osApiWrappers/dag_spinlock.h>
#include <util/dag_stdint.h>
#include <util/dag_globDef.h>
#include <3d/dag_drv3dReset.h>
#include "shStateBlk.h"
#include "shRegs.h"

#if _TARGET_XBOX || _TARGET_C1 || _TARGET_C2
#define PLATFORM_HAS_BINDLESS true
#elif _TARGET_PC || _TARGET_ANDROID || _TARGET_C3
#define PLATFORM_HAS_BINDLESS d3d::get_driver_desc().caps.hasBindless
#else
#define PLATFORM_HAS_BINDLESS false
#endif

struct BindlessConstParams
{
  uint32_t constIdx;
  int texId; // if negative - not yet added to to uniqBindlessTex

  bool operator==(const BindlessConstParams &other) const { return constIdx == other.constIdx && texId == other.texId; }
};

void apply_bindless_state(uint32_t const_state_idx, int tex_level);
void clear_bindless_states();
void req_tex_level_bindless(uint32_t const_state_idx, int tex_level);
using added_bindless_textures_t = eastl::fixed_vector<uint32_t, 4, /*overflow*/ true, framemem_allocator>;
int find_or_add_bindless_tex(TEXTUREID tid, added_bindless_textures_t &added_bindless_textures);
void dump_bindless_states_stat();

void apply_slot_textures_state(uint32_t const_state_idx, uint32_t sampler_state_id, int tex_level);
void clear_slot_textures_states();
void dump_slot_textures_states_stat();
void slot_textures_req_tex_level(uint32_t sampler_state_id, int tex_level);

struct ShaderStateBlock
{
  shaders::RenderStateId stateIdx;
  uint32_t samplerIdx = 0, constIdx = 0;
#if _TARGET_STATIC_LIB
  uint16_t refCount = 0;
#else
  uint32_t refCount = 0;
#endif
  uint16_t texLevel = 0;

  static NonRelocatableCont<ShaderStateBlock, /*initialCap*/ 2048> blocks;
  static int deleted_blocks;

  bool operator==(const ShaderStateBlock &b) const
  {
    return stateIdx == b.stateIdx && samplerIdx == b.samplerIdx && constIdx == b.constIdx;
  }

  static int addBlockNoLock(ShaderStateBlock &b)
  {
    G_ASSERT(b.refCount == 0);

    // find equivalent block and use it, when exists
    auto bid = blocks.find_if([&](ShaderStateBlock &eb) {
      if (b == eb && eb.refCount < eastl::numeric_limits<decltype(ShaderStateBlock::refCount)>::max())
      {
        eb.refCount++;
        return true;
      }
      return false;
    });
    if (bid != BAD_STATEBLOCK)
      return bid;

    b.refCount = 1;
    return blocks.push_back(b);
  }

  static int addBlock(ShaderStateBlock &b)
  {
    shaders_internal::BlockAutoLock autoLock;
    return addBlockNoLock(b);
  }

  static void delBlock(int id)
  {
    shaders_internal::BlockAutoLock autoLock;
    ShaderStateBlock *b = blocks.at(id);
    if (!b) // do we really need handle this gracefully?
      return;
    if (b->refCount == 0)
      logmessage(DAGOR_DBGLEVEL > 0 ? LOGLEVEL_ERR : LOGLEVEL_WARN, "trying to remove deleted/broken state block, refCount = %d",
        blocks[id].refCount);
    else if (--b->refCount)
      return;
    deleted_blocks++;
    interlocked_compare_exchange(shaders_internal::cached_state_block, BAD_STATEBLOCK, id);
    return;
  }

public:
  void apply(int tex_level = 15)
  {
    texLevel = tex_level;
#ifndef __SANITIZE_THREAD__ // we might inc. this refCount in other thread right now, benign data race, don't complain about it
    G_FAST_ASSERT(refCount > 0);
#endif
    if (PLATFORM_HAS_BINDLESS)
    {
      apply_bindless_state(constIdx, tex_level);
    }
    else
    {
      apply_slot_textures_state(constIdx, samplerIdx, tex_level);
    }
    shaders::render_states::set(stateIdx);
  }
  void reqTexLevel(int tex_level)
  {
    texLevel = tex_level;
    if (PLATFORM_HAS_BINDLESS)
    {
      req_tex_level_bindless(constIdx, tex_level);
    }
    else
    {
      slot_textures_req_tex_level(samplerIdx, tex_level);
    }
  }
  static void clear()
  {
    shaders_internal::BlockAutoLock autoLock;
    if (PLATFORM_HAS_BINDLESS)
    {
      clear_bindless_states();
    }
    else
    {
      clear_slot_textures_states();
    }
    blocks.clear();
    blocks.push_back(ShaderStateBlock{});
    deleted_blocks = 0;
  }
};

ShaderStateBlock create_bindless_state(const BindlessConstParams *bindless_data, uint8_t bindless_count, const Point4 *consts_data,
  uint8_t consts_count, dag::Span<uint32_t> added_bindless_textures, bool static_block, int stcode_id);

ShaderStateBlock create_slot_textures_state(const TEXTUREID *ps, uint8_t ps_base, uint8_t ps_cnt, const TEXTUREID *vs, uint8_t vs_base,
  uint8_t vs_cnt, const Point4 *consts_data, uint8_t consts_count, bool static_block);

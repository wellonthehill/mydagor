/************************************************************************
  scripted shader element class
************************************************************************/
#ifndef __SCRIPTSELEM_H
#define __SCRIPTSELEM_H

#include "shadersBinaryData.h"
#include <shaders/dag_renderStateId.h>
#include <shaders/dag_shaders.h>
#include <generic/dag_smallTab.h>
#include <osApiWrappers/dag_spinlock.h>
#include <atomic>


/************************************************************************
  forwards
************************************************************************/
class ScriptedShaderMaterial;
class Interval;

/*********************************
 *
 * class ScriptedShaderElement
 *
 *********************************/
class ScriptedShaderElement final : public ShaderElement
{
private:
  ScriptedShaderElement(const shaderbindump::ShaderCode &matcode, ScriptedShaderMaterial &m, const char *info);
  ~ScriptedShaderElement();

public:
  typedef shaders_internal::Tex Tex;
  typedef shaders_internal::Buf Buf;

  struct VarMap
  {
    int32_t varOfs;
    uint16_t intervalId : 14, type : 2;
    uint16_t totalMul;
  };
  struct PackedPassId
  {
    mutable struct Id
    {
      std::atomic<int> v;
      int pr;
    } id; // we cache it inside stateBlocksSpinLock
    PackedPassId() = default;
    PackedPassId(PackedPassId &&p)
    {
      memcpy(this, &p, sizeof(*this));
      memset(&p, 0, sizeof(p));
    }
  };

  const shaderbindump::ShaderCode &code;
  const shaderbindump::ShaderClass &shClass;
  mutable os_spinlock_t stateBlocksSpinLock;
  mutable VDECL usedVdecl; // cached
  uint8_t stageDest;
  enum
  {
    NO_VARMAP_TABLE,
    NO_DYNVARIANT,
    COMPLEX_VARMAP
  };
  uint8_t dynVariantOption = NO_DYNVARIANT;

  // for each dynamic variant create it's own passes
  SmallTab<PackedPassId, MidmemAlloc> passes;

  SmallTab<int, MidmemAlloc> texVarOfs;
  SmallTab<VarMap, MidmemAlloc> varMapTable;
  uint32_t dynVariantCollectionId = 0;

  mutable int tex_level = 15;

public:
  ScriptedShaderElement(ScriptedShaderElement &&) = default;

  const uint8_t *getVars() const { return ((const uint8_t *)this) + sizeof(ScriptedShaderElement); }
  uint8_t *getVars() { return ((uint8_t *)this) + sizeof(ScriptedShaderElement); }

  static ScriptedShaderElement *create(const shaderbindump::ShaderCode &matcode, ScriptedShaderMaterial &m, const char *info);
  void acquireTexRefs();
  void releaseTexRefs();

  void recreateElem(const shaderbindump::ShaderCode &matcode, ScriptedShaderMaterial &m);

  // select current passes by dynamic variants
  int chooseDynamicVariant(dag::ConstSpan<uint8_t> norm_values, unsigned int &out_variant_code) const;
  int chooseDynamicVariant(unsigned int &out_variant_code) const;
  int chooseCachedDynamicVariant(unsigned int variant_code) const;

  void setStatesForVariant(int curVariant, uint32_t program, uint32_t state_index) const;
  void getDynamicVariantStates(int variant_code, int cur_variant, uint32_t &program, uint32_t &state_index,
    shaders::RenderStateId &render_state, uint32_t &const_state, uint32_t &tex_state) const;

  void update_stvar(ScriptedShaderMaterial &m, int stvarid);

  GCC_HOT void exec_stcode(dag::ConstSpan<int> cod, const shaderbindump::ShaderCode::Pass *__restrict code_cp) const;

  SNC_LIKELY_TARGET bool setStates() const override;
  SNC_LIKELY_TARGET void render(int minv, int numv, int sind, int numf, int base_vertex, int prim = PRIM_TRILIST) const override;

  bool setStatesDispatch() const override;
  bool dispatchCompute(int tgx, int tgy, int tgz, GpuPipeline gpu_pipeline = GpuPipeline::GRAPHICS, bool set_states = true) const;
  eastl::array<uint16_t, 3> getThreadGroupSizes() const;
  bool dispatchComputeThreads(int threads_x, int threads_y, int threads_z, GpuPipeline gpu_pipeline, bool set_states) const;
  bool dispatchComputeIndirect(Sbuffer *args, int ofs, GpuPipeline gpu_pipeline = GpuPipeline::GRAPHICS, bool set_states = true) const;

  SNC_LIKELY_TARGET void gatherUsedTex(TextureIdSet &tex_id_list) const override;
  SNC_LIKELY_TARGET bool replaceTexture(TEXTUREID tex_id_old, TEXTUREID tex_id_new) override;
  SNC_LIKELY_TARGET bool hasTexture(TEXTUREID tex_id) const override;

  // Return vertex size on shader input.
  SNC_LIKELY_TARGET unsigned int getVertexStride() const override { return code.vertexStride; }

  SNC_LIKELY_TARGET dag::ConstSpan<ShaderChannelId> getChannels() const { return code.channel; }

  SNC_LIKELY_TARGET void replaceVdecl(VDECL vDecl) override;
  SNC_LIKELY_TARGET VDECL getEffectiveVDecl() const override;

  SNC_LIKELY_TARGET int getSupportedBlock(int variant, int layer) const override;

  // call specified function
  void callFunction(int id, int out_reg, dag::ConstSpan<int> in_regs, char *regs);

  void resetStateBlocks();
  void preCreateStateBlocks();
  void resetShaderPrograms(bool delete_programs = true);
  void preCreateShaderPrograms();
  void detachElem();

  const char *getShaderClassName() const override;
  void setProgram(uint32_t variant);
  PROGRAM getComputeProgram(const shaderbindump::ShaderCode::ShRef *p) const;
  inline void setReqTexLevel(int req_tex_level = 15) const override { tex_level = req_tex_level; }

private:
  static const unsigned int invalid_variant = 0xFFFFFFFF;
  // use upper 16 bit of seFlags for internal needs
  __forceinline void prepareShaderProgram(PackedPassId::Id &pass_id, int variant, unsigned int variant_code) const;
  __forceinline void preparePassId(PackedPassId::Id &pass_id, int variant, unsigned int variant_code) const;
  void preparePassIdOOL(PackedPassId::Id &pass_id, int variant, unsigned int variant_code) const;

  int recordStateBlock(const shaderbindump::ShaderCode::ShRef &p) const;
  VDECL initVdecl() const;

  ScriptedShaderElement(const ScriptedShaderElement &);
  ScriptedShaderElement &operator=(const ScriptedShaderElement &);
};

#endif //__SCRIPTSELEM_H

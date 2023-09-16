#pragma once

#include "shaderSave.h"
#include "intervals.h"
#include "globVar.h"
#include <util/dag_simpleString.h>
#include <util/dag_bindump_ext.h>
#include "shaderTab.h"
#include "shSemCode.h"

class ShaderClass;
class IGenSave;

namespace shaders
{
struct RenderState;
}

struct ShadersBindump
{
  SerializableTab<ShaderGlobal::Var> variable_list;
  IntervalList intervals;
  bindump::Ptr<ShaderStateBlock> empty_block;
  SerializableTab<ShaderStateBlock *> state_blocks;
  SerializableTab<ShaderClass *> shader_classes;
  SerializableTab<shaders::RenderState> render_states;
  SerializableTab<TabFsh> shaders_fsh;
  SerializableTab<TabVpr> shaders_vpr;
  SerializableTab<TabStcode> shaders_stcode;
};

struct ShadersBindumpHeader
{
  int cache_sign;
  int cache_version;
  bindump::EnableHash<ShadersBindump> hash;
  bindump::vector<bindump::string> dependency_files;
};

struct CompressedShadersBindump : ShadersBindumpHeader
{
  uint64_t decompressed_size;
  bindump::vector<uint8_t> compressed_shaders;
  int eof;
};

void init_shader_class();
void close_shader_class();

void add_shader_class(ShaderClass *sc);

int add_fshader(dag::ConstSpan<unsigned> code);
int add_vprog(dag::ConstSpan<unsigned> vs, dag::ConstSpan<unsigned> hs, dag::ConstSpan<unsigned> ds, dag::ConstSpan<unsigned> gs);
int add_stcode(dag::ConstSpan<int> code);
int add_render_state(const ShaderSemCode::Pass &state);

void count_shader_stats(unsigned &uniqueFshBytesInFile, unsigned &uniqueFshCountInFile, unsigned &uniqueVprBytesInFile,
  unsigned &uniqueVprCountInFile, unsigned &stcodeBytes);

bool load_shaders_bindump(ShadersBindump &shaders, bindump::IReader &full_file_reader);
bool link_scripted_shaders(const uint8_t *mapped_data, int data_size, const char *filename);
void save_scripted_shaders(const char *filename, dag::ConstSpan<SimpleString> files);

bool make_scripted_shaders_dump(const char *dump_name, const char *cache_filename, bool strip_shaders_and_stcode, bool pack);

#if _CROSS_TARGET_DX12
struct VertexProgramAndPixelShaderIdents
{
  int vprog;
  int fsh;
};
VertexProgramAndPixelShaderIdents add_phase_one_progs(dag::ConstSpan<unsigned> vs, dag::ConstSpan<unsigned> hs,
  dag::ConstSpan<unsigned> ds, dag::ConstSpan<unsigned> gs, dag::ConstSpan<unsigned> ps);
void recompile_shaders();
#endif
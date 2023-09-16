//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <vecmath/dag_vecMathDecl.h>
#include <3d/dag_textureIDHolder.h>
#include <EASTL/string.h>
#include <EASTL/vector.h>
#include <EASTL/fixed_vector.h>
#include <generic/dag_smallTab.h>
#include <generic/dag_staticTab.h>
#include <math/dag_declAlign.h>
#include <math/dag_Point2.h>
#include <math/dag_Point3.h>
#include <math/dag_Point4.h>
#include <math/dag_TMatrix4.h>
#include <shaders/dag_overrideStateId.h>
#include <3d/dag_texStreamingContext.h>

class DynamicRenderableSceneInstance;
class BaseTexture;
class GeomNodeTree;

#ifndef INVALID_INST_NODE_ID
#define INVALID_INST_NODE_ID 0
#endif

namespace dynrend
{
struct InitialNodes
{
  SmallTab<mat44f> nodesModelTm;
  InitialNodes() {}
  InitialNodes(const DynamicRenderableSceneInstance *instance, const GeomNodeTree *initial_skeleton);
  InitialNodes(const DynamicRenderableSceneInstance *instance, const TMatrix &root_tm);
};


enum class ContextId
{
  MAIN,
  IMMEDIATE,
  FIRST_USER_CONTEXT, // User contexts follow.
  COUNT = FIRST_USER_CONTEXT + 1
};


enum RenderFlags
{
  RENDER_OPAQUE = 0x00000001,
  RENDER_TRANS = 0x00000002,
  RENDER_DISTORTION = 0x00000004,
  APPLY_OVERRIDE_STATE_ID_TO_OPAQUE_ONLY = 0x00000008,
  MERGE_OVERRIDE_STATE = 0x00000010,
  OVERRIDE_RENDER_SKINNED_CHECK = 0x00000020,
};

struct Interval
{
  int varId = 0;
  int setValue = 0;   // Set this value when applying the interval.
  int unsetValue = 0; // Restore this value afterward.
  int instNodeId = INVALID_INST_NODE_ID;
};

typedef StaticTab<Interval, 8> Intervals;
struct DECLSPEC_ALIGN(16) PerInstanceRenderData
{
  uint32_t flags = RENDER_OPAQUE | RENDER_TRANS | RENDER_DISTORTION; // For compatibility with deprecated renderer.
  Intervals intervals;
  shaders::OverrideStateId overrideStateId;
  eastl::fixed_vector<Point4, 3, true> params;
} ATTRIBUTE_ALIGN(16);

struct InstanceContextData
{
  const DynamicRenderableSceneInstance *instance = NULL;
  ContextId contextId = ContextId(-1);
  int baseOffsetRenderData = -1;
};

struct Statistics
{
  int dips;
  int triangles;
};


void init();
void close();
bool is_initialized();


// Should not be changed prior to the render call:
//    node matrices
//    instance origin
//    opacity of nodes (if used in shader)
//    the instance must not be unloaded
//    optional_initial_nodes must be valid
//    create_context/delete_context are not thread-safe
//
// Can be changed after the add call:
//    instance LOD
//    visibility of nodes (hidden or zero opacity)
//    optional_render_data can be deleted

void add(ContextId context_id, const DynamicRenderableSceneInstance *instance, const InitialNodes *optional_initial_nodes = NULL,
  const dynrend::PerInstanceRenderData *optional_render_data = NULL, dag::Span<int> *node_list = NULL,
  const TMatrix4 *customProj = NULL);

// offset_to_origin is used as a hint to the expected offset of the current view position
// relative to the current origin in view space. The same offset is used for motion vectors calculations as well
// so it is assumed that this offset doesn't change between frames.
void prepare_render(ContextId context_id, const TMatrix4 &view, const TMatrix4 &proj,
  const Point3 &offset_to_origin = Point3(0.f, 0.f, 0.f), TexStreamingContext texCtx = TexStreamingContext(0),
  dynrend::InstanceContextData *instanceContextData = NULL);

void render(ContextId context_id, int shader_mesh_stage);
void clear(ContextId context_id);

void clear_all_contexts();

void set_reduced_render(ContextId context_id, float min_elem_radius, bool render_skinned);
void set_prev_view_proj(const TMatrix4_vec4 &prev_view, const TMatrix4_vec4 &prev_proj);
void get_prev_view_proj(TMatrix4_vec4 &prev_view, TMatrix4_vec4 &prev_proj);
void set_local_offset_hint(const Point3 &hint);
void enable_separate_atest_pass(bool enable);

ContextId create_context(const char *name);
void delete_context(ContextId context_id);

enum class RenderMode
{
  Opaque,
  Translucent,
  Distortion
};

void update_reprojection_data(ContextId contextId);

bool set_instance_data_buffer(unsigned stage, ContextId contextId, int baseOffsetRenderData);

void render_one_instance(const DynamicRenderableSceneInstance *instance, RenderMode mode, TexStreamingContext texCtx,
  const InitialNodes *optional_initial_nodes = NULL, const dynrend::PerInstanceRenderData *optional_render_data = NULL);

void opaque_flush(ContextId context_id, TexStreamingContext texCtx, bool include_atest = false);

void set_shaders_forced_render_order(const eastl::vector<eastl::string> &shader_names);

bool can_render(const DynamicRenderableSceneInstance *instance);

bool render_in_tools(const DynamicRenderableSceneInstance *instance, RenderMode mode);

Statistics &get_statistics();
void reset_statistics();
} // namespace dynrend

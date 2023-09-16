//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <daECS/core/template.h>
#include <daECS/core/entityId.h>
#include <daECS/core/componentsMap.h>
#include <EASTL/functional.h>
#include <EASTL/string.h>
#include <generic/dag_tabFwd.h>

class DataBlock;
class SimpleString;

namespace ecs
{
class ChildComponent;
typedef eastl::vector<eastl::pair<eastl::string, ecs::ChildComponent>> ComponentsList;
typedef eastl::function<void(ecs::EntityId, const char *, ComponentsList &&amap)> on_entity_created_cb_t;
typedef eastl::function<void(const char *, bool)> on_import_beginend_cb_t;
typedef eastl::function<void(const DataBlock &blk)> service_datablock_cb;

ecs::ChildComponent load_comp_from_blk(const DataBlock &blk, int param_i);
void load_comp_list_from_blk(const DataBlock &blk, ComponentsList &alist);

void load_templates_blk_file(const char *debug_path_name, const DataBlock &blk, TemplateRefs &templates, TemplateDBInfo *info,
  service_datablock_cb cb = service_datablock_cb());
bool load_templates_blk_file(const char *path, TemplateRefs &templates, TemplateDBInfo *info);
void load_templates_blk(dag::ConstSpan<SimpleString> fnames, TemplateRefs &out_templates, TemplateDBInfo *info = nullptr);
void create_entities_blk(const DataBlock &blk, const char *blk_path,
  const on_entity_created_cb_t &on_entity_created_cb = on_entity_created_cb_t(),
  const on_import_beginend_cb_t &on_import_beginend_cb = on_import_beginend_cb_t());

void load_es_order(const DataBlock &blk, Tab<SimpleString> &es_order, Tab<SimpleString> &es_skip, dag::ConstSpan<const char *> tags);
} // namespace ecs

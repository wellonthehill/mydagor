//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <util/dag_string.h>
#include <ska_hash_map/flat_hash_map2.hpp>
#include <EASTL/vector.h>
#include <daECS/core/component.h>
#include <generic/dag_initOnDemand.h>

class DataBlock;

namespace ecs
{

typedef eastl::vector<eastl::pair<eastl::string, ecs::ChildComponent>> ComponentsList;

class SceneManager;
class Scene
{
public:
  struct EntityRecord
  {
    ComponentsList clist;
    uint32_t order : 31;
    uint32_t toBeSaved : 1;
    eastl::string templateName;
    EntityRecord(ComponentsList &&cl, uint32_t o, const char *tn, bool tbs) :
      clist(eastl::move(cl)), order(o), toBeSaved(tbs ? 1u : 0u), templateName(tn)
    {}
  };
  typedef ska::flat_hash_map<EntityId, EntityRecord, EidHash> EMap;

  struct ImportRecord
  {
    static constexpr uint32_t TOP_IMPORT_ORDER = 0xFFFFFFFFUL;
    eastl::string importScenePath;
    uint32_t order;
  };
  typedef eastl::vector<ImportRecord> ImportScenesList;

  typename EMap::const_iterator begin() const { return entities.begin(); }
  typename EMap::const_iterator end() const { return entities.end(); }
  int entitiesCount() { return entities.size(); }
  const EntityRecord *findEntityRecord(ecs::EntityId eid) const;
  const ecs::ComponentsList *findComponentsList(ecs::EntityId eid) const;
  EntityRecord *findEntityRecordForModify(ecs::EntityId eid);
  void eraseEntityRecord(ecs::EntityId eid);
  void insertEmptyEntityRecord(ecs::EntityId eid, const char *tname);
  void insertEntityRecord(ecs::EntityId eid, const char *tname, ComponentsList const &comps);
  void cloneEntityRecord(ecs::EntityId source_eid, ecs::EntityId dest_eid, const char *template_name);

  const ImportScenesList &getImportsRecordList() const { return imports; }

  bool hasUnsavedChanges() const { return unsavedChanges; }
  void setNewChangesApplied() { unsavedChanges = true; }
  void setAllChangesWereSaved() { unsavedChanges = false; }

private:
  void clear()
  {
    entities.clear();
    imports.clear();
    unsavedChanges = false;
    orderSequence = 0;
  }

  EMap entities;
  uint32_t orderSequence = 0;
  ImportScenesList imports;
  bool unsavedChanges = false;
  friend class SceneManager;
};

class SceneManager
{
public:
  Scene &getActiveScene() { return scene; }
  bool loadScene(const char *path);
  void clearScene() { scene.clear(); }

private:
  Scene scene;
  friend class Scene;
};
extern InitOnDemand<SceneManager> g_scenes;

inline Scene::EntityRecord *Scene::findEntityRecordForModify(ecs::EntityId eid)
{
  auto it = entities.find(eid);
  return (it != entities.end()) ? &it->second : nullptr;
}

inline const Scene::EntityRecord *Scene::findEntityRecord(ecs::EntityId eid) const
{
  return const_cast<Scene *>(this)->findEntityRecordForModify(eid);
}

inline const ecs::ComponentsList *Scene::findComponentsList(ecs::EntityId eid) const
{
  auto erec = findEntityRecord(eid);
  return erec ? &erec->clist : nullptr;
}

inline void Scene::eraseEntityRecord(ecs::EntityId eid)
{
  const auto *erec = findEntityRecord(eid);
  const bool toBeSaved = erec != nullptr && erec->toBeSaved != 0;
  if (entities.erase(eid))
    if (toBeSaved)
      setNewChangesApplied();
}

inline void Scene::insertEmptyEntityRecord(ecs::EntityId eid, const char *tname)
{
  entities.emplace(eid, Scene::EntityRecord{ComponentsList{}, orderSequence++, tname, /*toBeSaved*/ true});
  setNewChangesApplied();
}

inline void Scene::insertEntityRecord(ecs::EntityId eid, const char *tname, ComponentsList const &comps)
{
  entities.emplace(eid, Scene::EntityRecord{ComponentsList(comps), orderSequence++, tname, /*toBeSaved*/ true});
  setNewChangesApplied();
}

inline void Scene::cloneEntityRecord(ecs::EntityId source_eid, ecs::EntityId dest_eid, const char *template_name)
{
  auto it = entities.find(source_eid);
  if (it != entities.end())
  {
    EntityRecord rec{ComponentsList(it->second.clist), orderSequence++,
      template_name ? template_name : it->second.templateName.c_str(),
      /*toBeSaved*/ true};
    entities.insert_or_assign(dest_eid, eastl::move(rec));
    setNewChangesApplied();
  }
}

} // namespace ecs

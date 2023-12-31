#pragma once

#include "../av_plugin.h"
#include <EditorCore/ec_interface.h>

#include <propPanel2/c_control_event_handler.h>
#include <assets/asset.h>
#include <math/dag_geomTree.h>
#include <anim/dag_simpleNodeAnim.h>

class ILodController;
class IObjEntity;
enum CtrlType;

struct AnimCtrlData
{
  TLeafHandle handle;
  CtrlType type;
  dag::Vector<int> childs;
};

struct AnimParamData
{
  int pid;
  DataBlock::ParamType type;
  String name;
};

struct AnimNodeData
{
  AnimNodeData(const char *node_name, dag::Index16 skel_idx, const SimpleNodeAnim &node_anim) :
    name(node_name), skelIdx(skel_idx), anim(node_anim)
  {}
  String name;
  dag::Index16 skelIdx;
  SimpleNodeAnim anim;
};

class AnimTreePlugin : public IGenEditorPlugin, public ControlEventHandler
{
public:
  AnimTreePlugin();
  ~AnimTreePlugin() { AnimTreePlugin::end(); }

  virtual const char *getInternalName() const { return "animTree"; }

  virtual void registered() {}
  virtual void unregistered() {}

  virtual bool begin(DagorAsset *asset);
  virtual bool end();

  virtual void clearObjects() {}
  virtual void onSaveLibrary() {}
  virtual void onLoadLibrary() {}

  virtual bool getSelectionBox(BBox3 &box) const;

  virtual void actObjects(float dt);
  virtual void beforeRenderObjects() {}
  virtual void renderObjects() {}
  virtual void renderTransObjects() {}

  virtual bool supportAssetType(const DagorAsset &asset) const;

  virtual void fillPropPanel(PropertyContainerControlBase &panel);
  virtual void postFillPropPanel() {}

  virtual void onClick(int pcb_id, PropertyContainerControlBase *panel);
  virtual void onChange(int pcb_id, PropertyContainerControlBase *panel);

protected:
  DagorAsset *curAsset = nullptr;

  IObjEntity *entity = nullptr;
  ILodController *ctrl = nullptr;
  const GeomNodeTree *origGeomTree = nullptr;
  GeomNodeTree geomTree;
  String modelName;
  int dynModelId;

  AnimV20::AnimData *selectedA2d = nullptr;
  String selectedA2dName;
  dag::Vector<AnimNodeData> animNodes;
  float animProgress;

  dag::Vector<AnimParamData> ctrlParams;
  dag::Vector<String> fieldNames;
  float animTime;
  int firstKey;
  int lastKey;

  TLeafHandle enumsRootLeaf = nullptr;
  dag::Vector<AnimCtrlData> controllersData;

  TLeafHandle getEnumsRootLeaf(PropertyContainerControlBase *tree);
  bool isEnumOrEnumItem(TLeafHandle leaf, PropertyContainerControlBase *tree);
  void fillTreePanels(PropertyContainerControlBase *panel);
  void fillEnumTree(const DataBlock *settings, PropertyContainerControlBase *panel);
  void fillAnimBlendSettings(PropertyContainerControlBase *tree, PropertyContainerControlBase *group);
  void fillAnimBlendFields(PropertyContainerControlBase *panel, const DataBlock *node, int &field_idx);
  void fillCtrlsSettings(PropertyContainerControlBase *panel);
  void fillCtrlsParamsSettings(PropertyContainerControlBase *panel, const DataBlock *settings, int field_idx);
  void fillCtrlsBlocksSettings(PropertyContainerControlBase *panel, const DataBlock *settings);
  void fillParamSwitchBlockSettings(PropertyContainerControlBase *panel, const DataBlock *settings);
  void fillParamSwitchEnumGen(PropertyContainerControlBase *panel, const DataBlock *nodes);
  void setSelectedParamSwitchSettings(PropertyContainerControlBase *panel);
  void changeParamSwitchType(PropertyContainerControlBase *panel);
  void addNodeParamSwitchList(PropertyContainerControlBase *panel);
  void removeNodeParamSwitchList(PropertyContainerControlBase *panel);
  void saveControllerSettings(PropertyContainerControlBase *panel);
  void saveControllerParamsSettings(PropertyContainerControlBase *panel, DataBlock *settings);
  void saveControllerBlocksSettings(PropertyContainerControlBase *panel, DataBlock *settings);
  void saveParamSwitchBlockSettings(PropertyContainerControlBase *panel, DataBlock *settings);
  void selectDynModel();
  void resetDynModel();
  void reloadDynModel();
  void loadA2dResource(PropertyContainerControlBase *panel);
  void animate(int key);
  int getPidByName(const char *name);
  DataBlock *findBnlProps(const char *name);
};
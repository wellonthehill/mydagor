#pragma once

#include "../av_plugin.h"
// #include "../av_interface.h"
#include "materialRec.h"
#include <propPanel2/c_control_event_handler.h>


class OLAppWindow;
class MaterialParamDescr;
class MatShader;
class MatParam;
class MatTripleInt;
class MatTripleReal;
class MatE3dColor;
class MatCombo;
class MatTexture;
class GeomObject;
class MatCustom;
class Mat2Sided;


class MaterialsPlugin : public IGenEditorPlugin, public ControlEventHandler
{
public:
  MaterialsPlugin();
  ~MaterialsPlugin();

  // IGenEditorPlugin
  virtual const char *getInternalName() const { return "materialsEditor"; }

  virtual void registered();
  virtual void unregistered();

  virtual bool begin(DagorAsset *asset);
  virtual bool end();
  virtual IGenEventHandler *getEventHandler() { return NULL; }

  virtual void clearObjects() {}
  virtual void onSaveLibrary();
  virtual void onLoadLibrary();

  virtual bool getSelectionBox(BBox3 &box) const;

  virtual void actObjects(float dt) {}
  virtual void beforeRenderObjects() {}
  virtual void renderObjects() {}
  virtual void renderTransObjects() {}
  virtual void renderGeometry(Stage stage);

  virtual bool supportAssetType(const DagorAsset &asset) const;

  virtual void fillPropPanel(PropertyContainerControlBase &panel);
  virtual void fillShaderPanel(PropertyContainerControlBase *panel);
  virtual void postFillPropPanel() {}

  virtual void onChange(int pcb_id, PropertyContainerControlBase *panel);
  virtual void onClick(int pcb_id, PropertyContainerControlBase *panel);

private:
  DagorAsset *curAsset;
  MaterialRec *curMat;

  GeomObject *previewGeom;

  Tab<const MaterialParamDescr *> matParamsDescr;
  Tab<const MatShader *> matShaders;
  Tab<MatParam *> matParams;
  Tab<String> shaderParamsNames;

  void initMatParamsDescr(const DataBlock &app_blk);
  void clearMatParamsDescr();

  void initMatShaders(const DataBlock &app_blk);
  void clearMatShaders();

  void createParamsList();
  void addParamToList(const char *name, const E3DCOLOR &color);
  void clearParamsList();

  void updatePreview();

  void getShadersNames(Tab<String> &names) const;

  const MaterialParamDescr *findParameterDescr(const char *name) const;
  const MatShader *findShader(const char *name) const;
  // get existent parameter or create new one
  MatParam &findMatParam(const char *name);

  void fillShaderParams(PropertyContainerControlBase *panel, const MaterialRec &mat, const MatShader &shader);

  void addTexture(PropertyContainerControlBase *panel, const MaterialRec &mat, const char *caption, int ctrl_idx, int tex_idx) const;
  void addTripleInt(PropertyContainerControlBase *panel, const char *caption, const char *script_param, const IPoint2 &constrains,
    int ctrl_idx) const;
  void addTripleReal(PropertyContainerControlBase *panel, const char *caption, const char *script_param, const Point2 &constrains,
    int ctrl_idx) const;
  void addE3dColor(PropertyContainerControlBase *panel, const char *caption, const char *script_param, int col_idx,
    int ctrl_idx) const;
  void addCombo(PropertyContainerControlBase *panel, const char *caption, const char *script_param, const Tab<String> &vals,
    const char *def, int ctrl_idx);
  void addCustom(PropertyContainerControlBase *panel, const char *script_param, int ctrl_idx) const;

  void onShaderParamChange(int pid, PropertyContainerControlBase *panel);
  void onTripleIntChange(PropertyContainerControlBase *panel, const IPoint2 &param_idx, MatTripleInt &param) const;
  void onTripleRealChange(PropertyContainerControlBase *panel, const IPoint2 &param_idx, MatTripleReal &param) const;
  void onE3dColorChange(PropertyContainerControlBase *panel, const IPoint2 &paramIdx, MatE3dColor &param) const;
  void onComboChange(PropertyContainerControlBase *panel, const IPoint2 &param_idx, MatCombo &param) const;
  void onTextureChange(PropertyContainerControlBase *panel, const IPoint2 &param_idx, MatTexture &param) const;
  void onCustomChange(PropertyContainerControlBase *panel, const IPoint2 &param_idx, MatCustom &param) const;
  void onTwoSidedChange(PropertyContainerControlBase *panel, const IPoint2 &param_idx, Mat2Sided &param) const;

  real getCorrectRealVal(real val, const Point2 &constrains) const;

  // x -- param idx, y -- control idx
  IPoint2 getParamIdxFromPid(int pid) const;
};

#include "av_appwnd.h"
#include "av_plugin.h"
#include "assetBuildCache.h"

#include <de3_lightService.h>
#include <de3_lightProps.h>
#include <de3_skiesService.h>
#include <de3_dynRenderService.h>
#include <render/debugTexOverlay.h>

#include <de3_huid.h>

#include <3d/dag_render.h>
#include <3d/dag_drv3d.h>
#include <3d/dag_texPackMgr2.h>
#include <shaders/dag_shaders.h>
#include <shaders/dag_shaderMesh.h>
#include <shaders/dag_shaderBlock.h>

#include <EditorCore/ec_gizmofilter.h>

#include <debug/dag_debug.h>
#include <perfMon/dag_perfMonStat.h>
#include <perfMon/dag_cpuFreq.h>
#include <osApiWrappers/dag_cpuJobs.h>
#include <assets/asset.h>

#include "editableShader.h"
#include "assetUserFlags.h"

extern void *get_generic_dyn_render_service();
extern void *get_tiff_bit_mask_image_mgr();
extern void *get_generic_asset_service();
extern void *get_gen_light_service();
extern void *get_generic_skies_service();
extern void *get_generic_color_range_service();
extern void *get_generic_rendinstgen_service();
extern void *get_generic_spline_gen_service();
extern void *get_generic_wind_service();


extern void terminate_interface_de3();
extern InitOnDemand<DebugTexOverlay> av_show_tex_helper;


static int worldViewPosVarId = -2;

//=============================================================================
void AssetViewerApp::terminateInterface()
{
  av_show_tex_helper.demandDestroy();
  environment::clear();

  for (int i = 0; i < plugin.size(); ++i)
  {
    plugin[i]->unregistered();
    del_it(plugin[i]);
  }

  terminate_interface_de3();
  IEditorCoreEngine::set(NULL);
}


//=============================================================================
void *AssetViewerApp::queryEditorInterfacePtr(unsigned huid)
{
  if (huid == HUID_IBitMaskImageMgr)
    return ::get_tiff_bit_mask_image_mgr();

  if (huid == HUID_IAssetService)
    return ::get_generic_asset_service();

  if (huid == HUID_ISceneLightService)
    return get_gen_light_service();

  if (huid == HUID_ISkiesService)
    return get_generic_skies_service();

  if (huid == HUID_IColorRangeService)
    return get_generic_color_range_service();

  if (huid == HUID_IRendInstGenService)
    return get_generic_rendinstgen_service();

  if (huid == HUID_IDynRenderService)
    return get_generic_dyn_render_service();

  if (huid == HUID_ISplineGenService)
    return get_generic_spline_gen_service();

  if (huid == HUID_IWindService)
    return get_generic_wind_service();

  return NULL;
}

void AssetViewerApp::screenshotRender()
{
  bool last_skipRenderEnvi = skipRenderEnvi;
  if (screenshotObjOnTranspBkg)
    skipRenderObjects = skipRenderEnvi = true;

  queryEditorInterface<IDynRenderService>()->renderScreenshot();

  skipRenderObjects = false;
  skipRenderEnvi = last_skipRenderEnvi;
}

//=============================================================================
bool AssetViewerApp::registerPlugin(IGenEditorPlugin *p)
{
  for (int i = plugin.size() - 1; i >= 0; --i)
  {
    if (plugin[i] == p)
    {
      debug("multiple register %p/%s!", p, p->getInternalName());
      return true;
    }
    else if (!stricmp(plugin[i]->getInternalName(), p->getInternalName()))
    {
      debug("another plugin with the same internal name is already "
            "registered: %p/%s!",
        p, p->getInternalName());
      return false;
    }
  }

  debug("== register plugin %p/%s", p, p->getInternalName());

  plugin.push_back(p);
  sortPlugins();
  p->registered();

  return true;
}


//=============================================================================
bool AssetViewerApp::unregisterPlugin(IGenEditorPlugin *p)
{
  for (int i = plugin.size() - 1; i >= 0; --i)
    if (plugin[i] == p)
    {
      debug("== unregister plugin %p/%s", p, p->getInternalName());
      plugin[i]->unregistered();
      erase_items(plugin, i, 1);
      return true;
    }

  return false;
}


//=============================================================================
void AssetViewerApp::switchToPlugin(int id)
{
  class InfoDrawStub : public IGenEventHandler
  {
    virtual void handleKeyPress(IGenViewportWnd *wnd, int vk, int modif) {}
    virtual void handleKeyRelease(IGenViewportWnd *wnd, int vk, int modif) {}

    virtual bool handleMouseMove(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif) { return false; }
    virtual bool handleMouseLBPress(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif) { return false; }
    virtual bool handleMouseLBRelease(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif) { return false; }
    virtual bool handleMouseRBPress(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif) { return false; }
    virtual bool handleMouseRBRelease(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif) { return false; }
    virtual bool handleMouseCBPress(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif) { return false; }
    virtual bool handleMouseCBRelease(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif) { return false; }
    virtual bool handleMouseWheel(IGenViewportWnd *wnd, int wheel_d, int x, int y, int key_modif) { return false; }
    virtual bool handleMouseDoubleClick(IGenViewportWnd *wnd, int x, int y, int key_modif) { return false; }
    virtual void handleViewChange(IGenViewportWnd *wnd) {}

    virtual void handleViewportPaint(IGenViewportWnd *wnd) { ::get_app().drawAssetInformation(wnd); }
  };
  static InfoDrawStub infoDrawStub;

  if (curAsset && curAsset->testUserFlags(ASSET_USER_FLG_NEEDS_RELOAD))
  {
    curAsset->clrUserFlags(ASSET_USER_FLG_NEEDS_RELOAD);
    switchToPlugin(id);
    reloadAsset(*curAsset, curAsset->getNameId(), curAsset->getType());
    return;
  }

  int curId = curPluginId;

  IGenEditorPlugin *cur = curPlugin();

  const int oldCur = curPluginId;
  curPluginId = id;

  IGenEditorPlugin *next = (curPluginId == -1) ? NULL : plugin[curPluginId];

  if (cur && !cur->end())
  {
    curPluginId = oldCur;
    return;
  }

  showAdditinalPropWindow(next ? next->havePropPanel() : false);
  showAdditinalToolWindow(next ? next->haveToolPanel() : false);

  if (next && !next->begin(curAsset))
  {
    curPluginId = oldCur;
    showAdditinalPropWindow(cur->havePropPanel());
    showAdditinalToolWindow(cur->haveToolPanel());
    cur->begin(curAsset);
    return;
  }

  ged.curEH = next ? next->getEventHandler() : (curAssetPackName.empty() ? NULL : &infoDrawStub);
  ged.setEH(appEH);

  if (autoZoomAndCenter)
    zoomAndCenter();
}


IGenEditorPluginBase *AssetViewerApp::getPluginBase(int idx) { return getPlugin(idx); }
IGenEditorPluginBase *AssetViewerApp::curPluginBase() { return curPlugin(); }
bool IGenEditorPlugin::getVisible() const { return this == get_app().curPlugin(); }

//=============================================================================
int AssetViewerApp::getPluginCount() { return plugin.size(); }


//=============================================================================
IGenEditorPlugin *AssetViewerApp::getPlugin(int idx) { return (idx >= 0 && idx < plugin.size()) ? plugin[idx] : NULL; }


//=============================================================================
int AssetViewerApp::getPluginIdx(IGenEditorPlugin *plug) const
{
  for (int i = 0; i < plugin.size(); ++i)
    if (plugin[i] == plug)
      return i;

  return -1;
}


//=============================================================================
void *AssetViewerApp::getInterface(int interface_uid)
{
  for (int i = 0; i < plugin.size(); ++i)
  {
    void *iface = plugin[i]->queryInterfacePtr(interface_uid);
    if (iface)
      return iface;
  }

  return NULL;
}


//=============================================================================
void AssetViewerApp::getInterfaces(int interface_uid, Tab<void *> &interfaces)
{
  for (int i = 0; i < plugin.size(); ++i)
  {
    void *iface = plugin[i]->queryInterfacePtr(interface_uid);
    if (iface)
      interfaces.push_back(iface);
  }
}


//==================================================================================================
IWndManager *AssetViewerApp::getWndManager() const
{
  G_ASSERT(mManager && "AssetViewerApp::getWndManager(): window manager == NULL!");
  return mManager;
}


//==================================================================================================
PropPanel2 *AssetViewerApp::getCustomPanel(int id) const
{
  switch (id)
  {
    case GUI_PLUGIN_TOOLBAR_ID: return mPluginTool;
  }

  return NULL;
}


//==================================================================================================
void *AssetViewerApp::addToolbar(int height)
{
  void *toolbar = mManager->splitNeighbourWindow(hwndToolbar, 0, height, WA_TOP);
  if (!toolbar)
    toolbar = mManager->splitWindow(0, 0, height, WA_TOP);
  G_ASSERT(toolbar);
  return toolbar;
}


//==================================================================================================
void AssetViewerApp::addPropPanel(int type, int width)
{
  void *propbar = mManager->splitNeighbourWindow(hwndPPanel, 0, width, WA_RIGHT);
  if (!propbar)
    propbar = mManager->splitWindow(0, 0, width, WA_RIGHT);
  G_ASSERT(propbar);

  mManager->setWindowType(propbar, type);
  mManager->setHeader(propbar, HEADER_TOP);
  mManager->fixWindow(propbar, true);
}


void AssetViewerApp::removePropPanel(void *hwnd) { mManager->removeWindow(hwnd); }


//==============================================================================
void AssetViewerApp::updateViewports() { shouldUpdateViewports = true; }


//==============================================================================
void AssetViewerApp::setViewportCacheMode(ViewportCacheMode mode) { ged.setViewportCacheMode(mode); }


//==============================================================================
void AssetViewerApp::invalidateViewportCache() { ged.invalidateCache(); }


//==============================================================================
int AssetViewerApp::getViewportCount() { return ged.getViewportCount(); }


//==============================================================================
IGenViewportWnd *AssetViewerApp::getViewport(int n) { return ged.getViewport(n); }


//==============================================================================
IGenViewportWnd *AssetViewerApp::getRenderViewport() { return ged.getRenderViewport(); }


//==============================================================================
IGenViewportWnd *AssetViewerApp::getCurrentViewport() { return ged.getCurrentViewport(); }


//==============================================================================
void AssetViewerApp::setViewportZnearZfar(real zn, real zf) { ged.setZnearZfar(zn, zf); }


//==============================================================================
IGenViewportWnd *AssetViewerApp::screenToViewport(int &x, int &y) { return ged.screenToViewport(x, y); }


//==============================================================================
bool AssetViewerApp::getSelectionBox(BBox3 &box)
{
  box.setempty();

  IGenEditorPlugin *current = curPlugin();

  return current ? current->getSelectionBox(box) : false;
}

//==============================================================================
void AssetViewerApp::setupColliderParams(int, const BBox3 &) {}

//==================================================================================================
bool AssetViewerApp::traceRay(const Point3 &src, const Point3 &dir, float &dist, Point3 *out_norm, bool use_zero_plane)
{
  if (fabs(dir.y) < 0.0001)
    return false;

  real t = -src.y / dir.y;
  if (t > 0 && t < dist)
  {
    dist = t;

    if (out_norm)
    {
      if (dir.y < 0)
        *out_norm = Point3(0, 1, 0);
      else
        *out_norm = Point3(0, -1, 0);
    }

    return true;
  }

  return false;
}


//==============================================================================
void AssetViewerApp::actObjects(real dt)
{
  cpujobs::release_done_jobs();
  ged.act();

  static float timeToTrackFiles = 0;
  timeToTrackFiles -= dt;

  environment::renderEnviEntity(assetLtData);

  if (timeToTrackFiles < 0)
  {
    timeToTrackFiles = 0.5;
    if (assetMgr.trackChangesContinuous(-1))
      ::post_base_update_notify_dabuild();
  }

  for (int i = 0; i < plugin.size(); ++i)
    plugin[i]->actObjects(dt);

  static unsigned last_t = 0;
  if (last_t + 1000 < get_time_msec())
  {
    perfmonstat::dump_stat();
    last_t = get_time_msec();
  }

  update_editable_shader();
}


//==============================================================================
void AssetViewerApp::beforeRenderObjects()
{
  ddsx::tex_pack2_perform_delayed_data_loading();
  ViewportWindow *vpw = ged.getRenderViewport();
  if (vpw)
    vpw->setViewProj();

  IGenEditorPlugin *curPlug = curPlugin();

  if (worldViewPosVarId == -2)
    worldViewPosVarId = ::get_shader_variable_id("world_view_pos");
  if (worldViewPosVarId >= 0)
    ShaderGlobal::set_color4(worldViewPosVarId, Color4(::grs_cur_view.pos.x, ::grs_cur_view.pos.y, ::grs_cur_view.pos.z, 1.f));

  plugin[0]->beforeRenderObjects();
  if (curPlug)
    curPlug->beforeRenderObjects();

  if (shouldUpdateViewports)
  {
    shouldUpdateViewports = false;
    ged.redrawClientRect();
  }
}


//==============================================================================
void AssetViewerApp::renderObjects()
{
  if (skipRenderObjects)
    return;
  ShaderGlobal::setBlock(-1, ShaderGlobal::LAYER_FRAME);
  renderGrid();

  IGenEditorPlugin *curPlug = curPlugin();

  if (curPlug)
  {
    plugin[0]->renderObjects();
    curPlug->renderObjects();
  }
}


//==============================================================================
void AssetViewerApp::renderTransObjects()
{
  if (skipRenderObjects)
    return;
  IGenEditorPlugin *curPlug = curPlugin();

  if (curPlug)
  {
    ShaderGlobal::setBlock(-1, ShaderGlobal::LAYER_FRAME);
    ShaderGlobal::setBlock(-1, ShaderGlobal::LAYER_SCENE);
    plugin[0]->renderTransObjects();
    curPlug->renderTransObjects();
  }

  if (av_show_tex_helper.get())
  {
    int w = 1, h = 1;
    EDITORCORE->getRenderViewport()->getViewportSize(w, h);
    av_show_tex_helper->setTargetSize(Point2(w, h));
    av_show_tex_helper->render();
  }
}


//==============================================================================
void AssetViewerApp::renderGrid()
{
  Tab<Point3> pt(tmpmem);
  Tab<Point3> dirs(tmpmem);

  Point3 center;

  const int gridConersNum = 4;
  const int gridDirectionsNum = 2;
  const real fakeGridSize = 200.f;
  const real perspectiveZoom = 600.f;

  pt.resize(gridConersNum);
  dirs.resize(gridDirectionsNum);

  TMatrix camera;
  ViewportWindow *vpw = ged.getRenderViewport();

  vpw->clientRectToWorld(pt.data(), dirs.data(), grid.getStep() * fakeGridSize);
  vpw->getCameraTransform(camera);

  float dh = fabs(camera.getcol(3).y - grid.getGridHeight()) + 1;
  grid.render(pt.data(), dirs.data(), fabs(vpw->isOrthogonal() ? vpw->getOrthogonalZoom() : perspectiveZoom / dh),
    ged.findViewportIndex(vpw));
}

//==============================================================================

void AssetViewerApp::setGizmo(IGizmoClient *gc, ModeType type)
{
  // set a new gizmoclient
  ged.tbManager->setGizmoClient(gc, type);

  if (gc && gizmoEH->getGizmoClient() == gc)
  {
    gizmoEH->setGizmoType(type);
    repaint();
    return;
  }

  if (gizmoEH->getGizmoClient())
    gizmoEH->getGizmoClient()->release();

  gizmoEH->setGizmoType(type);
  gizmoEH->setGizmoClient(gc);
  gizmoEH->zeroOverAndSelected();

  ged.setEH(appEH);
  repaint();
}


//==============================================================================

void AssetViewerApp::startGizmo(IGenViewportWnd *wnd, int x, int y, bool inside, int buttons, int key_modif)
{
  if (gizmoEH->getGizmoClient() && gizmoEH->getGizmoType() == MODE_None)
  {
    IGenEventHandler *eh = ged.curEH;
    ged.curEH = NULL;
    gizmoEH->handleMouseLBPress(wnd, x, y, inside, buttons, key_modif);
    ged.curEH = eh;
  }
}

//==============================================================================

IEditorCoreEngine::ModeType AssetViewerApp::getGizmoModeType() { return gizmoEH->getGizmoType(); }

//==============================================================================

bool AssetViewerApp::isGizmoOperationStarted() const { return gizmoEH->isStarted(); }

//==============================================================================
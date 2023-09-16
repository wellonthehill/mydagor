#include <3d/dag_drv3d.h>
#include <3d/dag_drv3dCmd.h>
#include <3d/dag_render.h>
#include <3d/dag_texMgrTags.h>
#include <3d/dag_resPtr.h>
#include <3d/dag_texPackMgr2.h>

#include <render/scopeRenderTarget.h>
#include <render/dxtcompress.h>
#include <render/partialDxtRender.h>
#include <landMesh/lmeshManager.h>
#include <landMesh/lmeshRenderer.h>
#include <landMesh/lastClip.h>
#include <shaders/dag_shaders.h>
#include <shaders/dag_shaderBlock.h>
#include <perfMon/dag_cpuFreq.h>
#include <math/dag_TMatrix4.h>
#include <osApiWrappers/dag_miscApi.h>
#include <debug/dag_debug.h>
#include <math/dag_bounds2.h>
#include <render/toroidal_update.h>
#include <math/dag_adjpow2.h>
#include <render/bcCompressor.h>

void render_last_clip_in_box(const BBox3 &land_box_part, const Point2 &half_texel, LandMeshData &data)
{
  shaders::overrides::set(data.flipCullStateId);

  Point2 geomOfs(land_box_part.width().x * half_texel.x, land_box_part.width().z * half_texel.y);
  Point3 pos = land_box_part.center();

  BBox3 landBBox = data.lmeshMgr->getBBox();
  pos.y = landBBox[1].y + 10;
  LandMeshRenderer &renderer = *data.lmeshRenderer;
  LandMeshManager &provider = *data.lmeshMgr;
  renderer.prepare(provider, pos, 0.f);
  TMatrix vtm = TMatrix::IDENT;
  vtm.setcol(0, 1, 0, 0);
  vtm.setcol(1, 0, 0, 1);
  vtm.setcol(2, 0, 1, 0);
  d3d::settm(TM_VIEW, vtm);
  TMatrix4 proj;
  proj = matrix_ortho_off_center_lh(land_box_part[0].x + geomOfs.x, land_box_part[1].x + geomOfs.x, land_box_part[1].z + geomOfs.y,
    land_box_part[0].z + geomOfs.y, landBBox[0].y - 10, landBBox[1].y + 10);
  d3d::settm(TM_PROJ, &proj);
  if (data.start_render)
    data.start_render();
  ShaderGlobal::setBlock(data.global_frame_id, ShaderGlobal::LAYER_FRAME);

  renderer.setRenderInBBox(land_box_part);
  // if (::app->renderer->isCompatibilityMode())
  //   renderer.setRenderClipmapWithPosition(true);//since we don't render with depth anyway
  renderer.render(provider, renderer.RENDER_CLIPMAP);
  // if (::app->renderer->isCompatibilityMode())
  //   renderer.setRenderClipmapWithPosition(false);
  renderer.setRenderInBBox(BBox3());
  if (data.decals_cb)
  {
    static int land_mesh_prepare_clipmap_blockid = ShaderGlobal::getBlockId("land_mesh_prepare_clipmap");
    ShaderGlobal::setBlock(land_mesh_prepare_clipmap_blockid, ShaderGlobal::LAYER_SCENE);
    data.decals_cb(land_box_part);
    // if (::app->objectsGroupList)
    //   ::app->objectsGroupList->renderDecals(landBoxPart);
    ShaderGlobal::setBlock(-1, ShaderGlobal::LAYER_SCENE);
  }

  shaders::overrides::reset();
}

void render_last_clip_in_box_tor(const BBox3 &land_box_part, const Point2 &half_texel, LandMeshData &data, Point2 &tor_offsets,
  ToroidalHelper &tor_helper)
{
  shaders::overrides::set(data.flipCullStateId);

  Point2 geomOfs(land_box_part.width().x * half_texel.x, land_box_part.width().z * half_texel.y);
  Point3 pos = land_box_part.center();

  BBox3 landBBox = data.lmeshMgr->getBBox();
  pos.y = landBBox[1].y + 10;
  LandMeshRenderer &renderer = *data.lmeshRenderer;
  LandMeshManager &provider = *data.lmeshMgr;
  renderer.prepare(provider, pos, 0.f);

  ToroidalGatherCallback::RegionTab regions;
  float texelSize = data.texelSize;
  Point3 posN = land_box_part.center();
  IPoint2 newTexelOrigin = ipoint2(floor(Point2::xz(posN) / (texelSize)));
  ToroidalGatherCallback cb(regions);
  toroidal_update(newTexelOrigin, tor_helper, tor_helper.texSize * 0.33f, cb);
  toroidal_update(newTexelOrigin, tor_helper, tor_helper.texSize * 0.33f, cb);

  TMatrix view;
  view.setcol(0, 1, 0, 0);
  view.setcol(1, 0, 0, 1);
  view.setcol(2, 0, 1, 0);
  view.setcol(3, 0, 0, 0);

  d3d::settm(TM_VIEW, view);

  for (int i = 0; i < regions.size(); ++i)
  {
    const ToroidalQuadRegion &reg = regions[i];

    BBox2 box(point2(reg.texelsFrom) * texelSize, point2(reg.texelsFrom + reg.wd) * texelSize);

    BBox3 box3(Point3::xVy(box[0], 0.0f), Point3::xVy(box[1], 0.0f));
    TMatrix4 proj = matrix_ortho_off_center_lh(box3[0].x + geomOfs.x, box3[1].x + geomOfs.x, box3[1].z + geomOfs.y,
      box3[0].z + geomOfs.y, landBBox[0].y - 10.0f, landBBox[1].y + 10.0f);

    d3d::settm(TM_PROJ, &proj);
    d3d::setview(reg.lt.x, reg.lt.y, reg.wd.x, reg.wd.y, 0, 1);

    TMatrix4 viewProj = TMatrix4(view) * proj;

    Point3 posT = box3.center();
    posT.y = landBBox[1].y + 10;
    renderer.prepare(provider, posT, 0.f);
    if (data.start_render)
      data.start_render();
    ShaderGlobal::setBlock(data.global_frame_id, ShaderGlobal::LAYER_FRAME);

    renderer.setRenderInBBox(box3);
    renderer.render(provider, renderer.RENDER_CLIPMAP);

    renderer.setRenderInBBox(BBox3());

    if (data.decals_cb)
    {
      static int land_mesh_prepare_clipmap_blockid = ShaderGlobal::getBlockId("land_mesh_prepare_clipmap");
      ShaderGlobal::setBlock(land_mesh_prepare_clipmap_blockid, ShaderGlobal::LAYER_SCENE);
      data.decals_cb(box3);
      ShaderGlobal::setBlock(-1, ShaderGlobal::LAYER_SCENE);
    }
  }

  renderer.setRenderInBBox(BBox3());

  shaders::overrides::reset();

  tor_offsets = Point2(((tor_helper.mainOrigin - newTexelOrigin) % tor_helper.texSize));
  tor_offsets /= (float)tor_helper.texSize;
}

static void fixedClipPartialRenderCb(int lineNo, int linesCount, int picHeight, void *userData)
{
  d3d::clearview(CLEAR_TARGET, 0x00000000, 1.0f, 0);
  LandMeshData &data = *(LandMeshData *)userData;

  BBox3 landBBox = data.lmeshMgr->getBBox();
  BBox3 landBox = landBBox;
  LandMeshManager *lmeshMgr = data.lmeshMgr;
  // due to error in splitting in editor. Although error is fixed, this will ensure backward comptibility with old data
  landBox[0].x = lmeshMgr->getCellOrigin().x * lmeshMgr->getLandCellSize();
  landBox[0].z = lmeshMgr->getCellOrigin().y * lmeshMgr->getLandCellSize();
  landBox[1].x = (lmeshMgr->getNumCellsX() + lmeshMgr->getCellOrigin().x) * lmeshMgr->getLandCellSize() - lmeshMgr->getGridCellSize();
  landBox[1].z = (lmeshMgr->getNumCellsY() + lmeshMgr->getCellOrigin().y) * lmeshMgr->getLandCellSize() - lmeshMgr->getGridCellSize();
  BBox3 landBoxPart(Point3(landBox[0].x, landBox[0].y, lerp(landBox[0].z, landBox[1].z, lineNo / float(picHeight))),
    Point3(landBox[1].x, landBox[1].y, lerp(landBox[0].z, landBox[1].z, (lineNo + linesCount) / float(picHeight))));
  Point2 halfTexel(HALF_TEXEL_OFSF / picHeight, HALF_TEXEL_OFSF / linesCount);

  render_last_clip_in_box(landBoxPart, halfTexel, data);
}

#define SAVE_RT 0

void apply_last_clip_anisotropy(const UniqueTexHolder &last_clip)
{
  if (last_clip)
    last_clip->setAnisotropy(max(2, ::dgs_tex_anisotropy));
}

void preload_textures_for_last_clip()
{
  prefetch_managed_textures_by_textag(TEXTAG_LAND);
  if (EASTL_UNLIKELY(!is_managed_textures_streaming_load_on_demand()))
  {
    ddsx::tex_pack2_perform_delayed_data_loading();
    return;
  }
  // this wait prevents (possible) subsequent wait inside prepare_fixed_clip() in main thread
  Tab<TEXTUREID> land_tex;
  textag_get_list(TEXTAG_LAND, land_tex);
  prefetch_and_wait_managed_textures_loaded(land_tex);
}

template <typename T>
void render_and_compress(const T &render_func, UniqueTexHolder &last_clip, const LandMeshData &data, int numMips)
{
  UniqueTex temp = dag::create_tex(NULL, data.texture_size, data.texture_size, TEXFMT_A8R8G8B8 | TEXCF_RTARGET | TEXCF_SRGBWRITE, 1,
    "temp_last_clip_tex");

  render_func(temp);
  {
    d3d::GpuAutoLock acquire;
    auto bcType = get_texture_compression_type(TEXFMT_ETC2_RGBA);
    auto temp_comp = eastl::make_unique<BcCompressor>(bcType, numMips, data.texture_size, data.texture_size, 1, "etc2_compressor");
    int j = data.texture_size;
    for (int i = 0; i < numMips; i++)
    {
      temp_comp->updateFromMip(temp.getTexId(), 0, i);
      temp_comp->copyToMip(last_clip.getTex2D(), i, 0, 0, i, 0, 0, j, j);
      j /= 2;
    }
  }
  temp.close();
}

void prepare_fixed_clip(UniqueTexHolder &last_clip, LandMeshData &data, bool update_game_screen)
{
  last_clip.close();
  if (!data.lmeshMgr || !data.lmeshRenderer)
    return;

  preload_textures_for_last_clip();

  data.texture_size = min(data.texture_size, min(d3d::get_driver_desc().maxtexw, d3d::get_driver_desc().maxtexh));
  int numMips = 1;
  const int partHeight = 128;
  for (int tsz = data.texture_size; tsz > partHeight; tsz >>= 1)
    numMips++;
  debug("create last clip of size %dx%d, %d mips", data.texture_size, data.texture_size, numMips);
  int64_t reft = ref_time_ticks();
  enum class LastClipComp
  {
    NONE,
    DXT,
    ETC2
  };
  LastClipComp compression = LastClipComp::NONE;
#if SAVE_RT || _TARGET_TVOS
  compression = LastClipComp::NONE;

#elif _TARGET_IOS || _TARGET_ANDROID
  const bool allowETC2 = ::dgs_get_settings()->getBlockByNameEx("graphics")->getBool("allowETC2", true);
  if (allowETC2 && d3d::check_texformat(TEXFMT_ETC2_RGBA))
    compression = LastClipComp::ETC2;
#else
  if (d3d::check_texformat(TEXFMT_DXT1 | data.texflags) && data.use_dxt)
    compression = LastClipComp::DXT;
#endif

  const unsigned flags = [&]() -> unsigned {
    switch (compression)
    {
      case LastClipComp::DXT: return TEXFMT_DXT1 | data.texflags;
      case LastClipComp::ETC2:
        numMips = get_log2i_of_pow2(data.texture_size) - 1;
        // TODO: Change RGBA to RGB when 3-channel compression becomes available
        return TEXFMT_ETC2_RGBA;
      default: numMips = 0; return TEXFMT_A8R8G8B8 | TEXCF_RTARGET | TEXCF_GENERATEMIPS | TEXCF_SRGBWRITE;
    }
  }();

  last_clip = dag::create_tex(NULL, data.texture_size, data.texture_size, TEXCF_SRGBREAD | flags, numMips, "last_clip_tex");
  d3d_err(last_clip.getTex2D());

  int render_normalmapVarId = get_shader_variable_id("render_with_normalmap", true);
  ShaderGlobal::set_int(render_normalmapVarId, 0); //==
  // render
  TMatrix4 ovtm, oproj;
  d3d::gettm(TM_VIEW, &ovtm);
  d3d::gettm(TM_PROJ, &oproj);
  Driver3dPerspective p;
  bool perspvalid = d3d::getpersp(p);
  // int64_t reft = ref_time_ticks();
  bool gamma_mips = true;
#if _TARGET_C1 | _TARGET_C2

#endif

  auto plain_render = [&](auto &tex) {
    d3d::GpuAutoLock acquire;
    d3d::setwire(0);
    {
      SCOPE_RENDER_TARGET;
      d3d::set_render_target(tex.getTex2D(), 0);
      d3d::clearview(CLEAR_TARGET, 0x00000000, 1.0f, 0);
      for (int y = 0; y < data.texture_size; y += partHeight)
      {
        d3d::driver_command(DRV3D_COMMAND_D3D_FLUSH, NULL, NULL, NULL);
        d3d::setview(0, y, data.texture_size - 1, partHeight, 0, 1);
        fixedClipPartialRenderCb(y, partHeight, data.texture_size, (void *)&data);
      }
    }
    d3d::resource_barrier({tex.getBaseTex(), RB_RO_SRV | RB_STAGE_PIXEL, 0, 0});
  };

  switch (compression)
  {
    case LastClipComp::DXT:
      PartialDxtRender(last_clip.getTex2D(), NULL, partHeight, data.texture_size, data.texture_size, numMips,
        (flags & TEXFMT_MASK) == TEXFMT_DXT5, false, &fixedClipPartialRenderCb, &data, gamma_mips, update_game_screen);
      break;
    case LastClipComp::ETC2: render_and_compress(plain_render, last_clip, data, numMips); break;
    default:
      plain_render(last_clip);
      last_clip.getTex2D()->generateMips();
      break;
  }

  // debug("total last clip time = %dus",get_time_usec(reft));
  d3d::driver_command(DRV3D_COMMAND_ACQUIRE_OWNERSHIP, NULL, NULL, NULL);
  d3d::settm(TM_VIEW, &ovtm);
  d3d::settm(TM_PROJ, &oproj);
  if (perspvalid)
    d3d::setpersp(p);
  if (::grs_draw_wire)
    d3d::setwire(1);
  d3d::driver_command(DRV3D_COMMAND_RELEASE_OWNERSHIP, NULL, NULL, NULL);
  debug("last clip prepared in %dus", get_time_usec(reft));
#if SAVE_RT
  save_rt_image_as_tga(last_clip, "last_clip.tga");
#endif

  apply_last_clip_anisotropy(last_clip);
  last_clip->texmipmap(TEXMIPMAP_LINEAR);
  last_clip->texfilter(TEXFILTER_BEST);
  last_clip->texaddr(TEXADDR_MIRROR);

  LandMeshManager *lmeshMgr = data.lmeshMgr;
  BBox3 landBox = lmeshMgr->getBBox();
  landBox[0].x = lmeshMgr->getCellOrigin().x * lmeshMgr->getLandCellSize();
  landBox[0].z = lmeshMgr->getCellOrigin().y * lmeshMgr->getLandCellSize();
  landBox[1].x = (lmeshMgr->getNumCellsX() + lmeshMgr->getCellOrigin().x) * lmeshMgr->getLandCellSize() - lmeshMgr->getGridCellSize();
  landBox[1].z = (lmeshMgr->getNumCellsY() + lmeshMgr->getCellOrigin().y) * lmeshMgr->getLandCellSize() - lmeshMgr->getGridCellSize();
  Color4 world_to_last_clip(1.f / landBox.width().x, 1.f / landBox.width().z, -landBox[0].x / landBox.width().x,
    -landBox[0].z / landBox.width().z);
  static int world_to_last_clipVardId = get_shader_variable_id("world_to_last_clip", true);
  ShaderGlobal::set_color4(world_to_last_clipVardId, world_to_last_clip);
}

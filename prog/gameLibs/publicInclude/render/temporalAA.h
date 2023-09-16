//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <math/dag_TMatrix4.h>
#include <3d/dag_textureIDHolder.h>
#include <generic/dag_carray.h>
#include <render/viewDependentResource.h>
#include <3d/dag_resourcePool.h>
#include <math/integer/dag_IPoint2.h>
#include <shaders/dag_postFxRenderer.h>

#include <EASTL/optional.h>

class DataBlock;

struct TemporalAAParams
{
  bool useHalton = true;
  bool useAdaptiveFilter = false;
  float subsampleScale = 0.5f;
  float newframeFalloffStill = 0.15f;
  float newframeFalloffMotion = 0.09f;
  float newframeFalloffDynamicStill = 0.15f;
  float newframeFalloffDynamicMotion = 0.05f;
  float frameWeightMinStill = 0.1f;
  float frameWeightMinMotion = 0.16f;
  float frameWeightMinDynamicStill = 0.1f;
  float frameWeightMinDynamicMotion = 0.16f;
  float frameWeightMotionThreshold = 0.f;
  float frameWeightMotionMax = 0.025f;
  float motionDifferenceMax = 2.f;
  float motionDifferenceMaxWeight = 0.5f;
  float sharpening = 0.2f;
  float clampingGamma = 1.2f;
  int subsamples = 4;
  float maxMotion = 4.f;
  float scaleAabbWithMotionSteepness = 0.f;
  float scaleAabbWithMotionMax = INFINITY;
  float scaleAabbWithMotionMaxForTAAU = -1.0;
};

class TMatrix4D;
extern Point2 get_taa_jitter(int counter, const TemporalAAParams &p);
extern void set_temporal_reprojection_matrix(const TMatrix4D &cur_view_proj_no_jitter, const TMatrix4D &prev_view_proj_jittered);
extern void set_temporal_resampling_filter_parameters(const Point2 &temporal_jitter_proj_offset);
extern void set_temporal_miscellaneous_parameters(float dt, int wd, const TemporalAAParams &p);
extern void set_temporal_parameters(const TMatrix4D &cur_view_proj_no_jitter, const TMatrix4D &prev_view_proj_jittered,
  const Point2 &temporal_jitter_proj_offset, float dt, int wd, const TemporalAAParams &p);

class TemporalAA
{
public:
  typedef TemporalAAParams Params;

  TemporalAA(const char *shader, const IPoint2 &output_resolution, const IPoint2 &input_resolution, int tex_fmt,
    bool low_quality = false, const char *name = nullptr);

  void loadParamsFromBlk(const DataBlock *blk);

  bool beforeRenderFrame();
  bool beforeRenderView(const TMatrix4 &cur_globtm_no_jitter);
  RTarget::CPtr apply(TEXTUREID currentFrameId);

  void invalidate()
  {
    frame.forEach([](int &f) { f = 0; });
  }
  bool isValid() const { return prevGlobTm.current().has_value(); }
  Point2 getPersJitterOffset() const { return jitterTexelOfs; }
  const IPoint2 &getInputResolution() const { return inputResolution; }
  bool isUpsampling() const { return inputResolution != outputResolution; }
  float getLodBias() const { return lodBias; }

  void setCurrentView(int view);

  Params params;

private:
  Params getDefaultParams() const;

  const IPoint2 inputResolution;
  const IPoint2 outputResolution;

  PostFxRenderer render;

  ViewDependentResource<int, 2> frame;
  ViewDependentResource<eastl::optional<TMatrix4>, 2> prevGlobTm;

  Point2 jitterPixelOfs;
  Point2 jitterTexelOfs;

  RTargetPool::Ptr historyTexPool;
  RTargetPool::Ptr wasDynamicTexPool;
  RTargetPool::Ptr resolvedFramePool;
  ViewDependentResource<RTarget::Ptr, 2> historyTex;
  ViewDependentResource<RTarget::Ptr, 2> wasDynamicTex;

  float lodBias;

  bool enabled = true;
  bool validPersp = false;

  int dtUsecs = 0;
};

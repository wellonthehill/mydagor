//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <ecs/core/entityManager.h>

namespace gpu_objects
{
struct PlacingParameters
{
  int seed = 0;
  Point2 scale = Point2(1, 1);
  Point3 upVector = Point3(0, 1, 0);
  float inclineDelta = 0;
  Color4 slopeFactor;
  Point2 rotate = Point2(0, 0);
  Point2 weightRange = Point2(0, 1);
  String map;
  Point4 mapSizeOffset;
  Color4 colorFrom;
  Color4 colorTo;
  Tab<Point4> biomes;
  float hardness = 1;
  bool decal = false;
  bool transparent = false;
  bool distorsion = false;
  float sparseWeight = 0;
  bool placeOnWater = false;
  bool enableDisplacement = false;
  bool renderIntoShadows = false;
  Point2 coastRange = Point2(-1, -1);
  bool faceCoast = false;
};
PlacingParameters prepare_gpu_object_parameters(int, const Point3 &, float, const Point2 &, const Point2 &, const Point4 &, const bool,
  const String &, const Point2 &, const Point2 &, const E3DCOLOR &, const E3DCOLOR &, const Point2 &, const ecs::Array &,
  const float &, const bool, const bool, const bool, const float &, const bool, const bool, const bool, const Point2 &, const bool);
} // namespace gpu_objects

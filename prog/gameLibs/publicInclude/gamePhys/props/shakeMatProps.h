//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <math/dag_Point2.h>

class DataBlock;

namespace physmat
{
struct ShakeMatProps
{
  Point2 shakePeriod;
  Point2 shakePow;
  Point2 shakeMult;

  void load(const DataBlock *blk);
  static const ShakeMatProps *get_props(int prop_id);
  static void register_props_class();
  static bool can_load(const DataBlock *);
};
}; // namespace physmat

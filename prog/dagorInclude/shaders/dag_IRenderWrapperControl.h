//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <math/dag_mathBase.h>

// Interface for applying beforeRender and BeforeRenderTrans policies
class IRenderWrapperControl
{
public:
  virtual int checkVisible(const BSphere3 &sph, const BBox3 *bbox) = 0;
  virtual void beforeRender(int value, bool trans) = 0;
  virtual void afterRender(int value, bool trans) = 0;
  virtual void destroy() = 0;
};

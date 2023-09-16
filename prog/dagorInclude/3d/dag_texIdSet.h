//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <3d/dag_resId.h>
#include <EASTL/vector_set.h>
#include <generic/dag_span.h>

class TextureIdSet : public eastl::vector_set<TEXTUREID>
{
public:
  void reset() { clear(); }

  bool add(TEXTUREID tid) { return insert(tid).second; }
  bool del(TEXTUREID tid) { return erase(tid); }
  bool has(TEXTUREID tid) const { return find(tid) != end(); }
};

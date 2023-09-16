//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <vecmath/dag_vecMath.h>
#include <anim/dag_animKeys.h>

namespace AnimV20Math
{
// Key data

__forceinline real interp_key(const AnimV20::AnimKeyReal &a, real t) { return ((a.k3 * t + a.k2) * t + a.k1) * t + a.p; }

__forceinline vec3f interp_key(const AnimV20::AnimKeyPoint3 &a, vec4f t)
{
  return v_madd(v_madd(v_madd(a.k3, t, a.k2), t, a.k1), t, a.p);
}

__forceinline vec4f interp_key(const AnimV20::AnimKeyQuat &a, const AnimV20::AnimKeyQuat &b, real t)
{
  return v_quat_qsquad(t, a.p, a.b0, a.b1, b.p);
}

} // end of namespace AnimV20Math

//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <EASTL/numeric_limits.h>


namespace dabfg
{

/// Type for daBfg node execution priorities
using priority_t = int32_t;

/// Default priority that is used when none is specified explicitly.
inline constexpr priority_t PRIO_DEFAULT = 0;

/// Max priority: the node will be executed as late as possible.
inline constexpr priority_t PRIO_AS_LATE_AS_POSSIBLE = eastl::numeric_limits<priority_t>::max();

/// Min priority: the node will be executed as early as possible.
inline constexpr priority_t PRIO_AS_EARLY_AS_POSSIBLE = eastl::numeric_limits<priority_t>::min();

} // namespace dabfg

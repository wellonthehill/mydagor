//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

class SqModules;

namespace bindquirrel
{
void bind_datacache(SqModules *module_mgr);
void shutdown_datacache();
} // namespace bindquirrel

//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

namespace Sqrat
{
class Object;
}

namespace darg
{
class IEventList
{
public:
  virtual bool sendEvent(const char *id, const Sqrat::Object &data) = 0;
};
} // namespace darg

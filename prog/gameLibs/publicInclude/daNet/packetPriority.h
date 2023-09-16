//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <stdint.h>


enum PacketPriority : uint8_t
{
  SYSTEM_PRIORITY,
  HIGH_PRIORITY,
  MEDIUM_PRIORITY,
  LOW_PRIORITY,

  NUMBER_OF_PRIORITIES
};

enum PacketReliability : uint8_t
{
  UNRELIABLE,
  UNRELIABLE_SEQUENCED,
  RELIABLE_ORDERED,
  RELIABLE_UNORDERED,

  NUMBER_OF_RELIABILITIES
};

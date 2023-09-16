//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

enum class GpuReadbackResultState
{
  IN_PROGRESS,
  SUCCEEDED,
  FAILED,
  ID_NOT_FOUND,
  SYSTEM_NOT_INITIALIZED
};

inline bool is_gpu_readback_query_successful(GpuReadbackResultState rs) { return rs == GpuReadbackResultState::SUCCEEDED; }

inline bool is_gpu_readback_query_failed(GpuReadbackResultState rs) { return rs >= GpuReadbackResultState::FAILED; }

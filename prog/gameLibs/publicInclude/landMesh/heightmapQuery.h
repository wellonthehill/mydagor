//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include "gpuReadbackQuery/gpuReadbackResult.h"
#include "landMesh/heightmap_query_result.hlsli"

class Point2;
struct HeightmapQueryResult;

namespace heightmap_query
{
void init();
void close();
void update();

int query(const Point2 &world_pos_2d);
GpuReadbackResultState get_query_result(int query_id, HeightmapQueryResult &result);
} // namespace heightmap_query

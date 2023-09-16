//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

// forward declarations for external classes
struct TexImage32;
struct TexPixel32;
class IGenLoad;


// load AVIF file (RGBX/RGBA)
TexImage32 *load_avif32(const char *fn, IMemAlloc *mem, bool *out_used_alpha = nullptr);
TexImage32 *load_avif32(IGenLoad &crd, IMemAlloc *mem, bool *out_used_alpha = nullptr);

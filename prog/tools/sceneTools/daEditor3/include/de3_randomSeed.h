//
// DaEditor3
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

class IRandomSeedHolder
{
public:
  static constexpr unsigned HUID = 0x0D9B6B02u; // IRandomSeedHolder


  virtual void setSeed(int new_seed) = 0;
  virtual int getSeed() = 0;
  virtual void setPerInstanceSeed(int seed) = 0;
  virtual int getPerInstanceSeed() = 0;

  virtual bool isSeedSetSupported() { return true; }
};

//
// Dagor Tech 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <util/dag_simpleString.h>

struct TwoStepRelPath
{
  void setSdkRoot(const char *root_dir, const char *subdir = nullptr);

  const char *mkRelPath(const char *fpath);

protected:
  SimpleString sdkRoot;
  int sdkRootLen = 0, sdkRootLen1 = -1;
  char buf[512] = {0};
};

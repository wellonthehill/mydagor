#define __UNLIMITED_BASE_PATH     1
#define __SUPPRESS_BLK_VALIDATION 1
#define __DEBUG_FILEPATH          "*"
// Copyright 2023 by Gaijin Games KFT, All rights reserved.
#include "common.h"
#include <startup/dag_mainCon.inc.cpp>
#include "blk2dag.h"


int DagorWinMain(bool debugmode)
{
  dd_add_base_path("");
  printf("Dagor BLK -> DAG Converter v1.1 \n"
         "Copyright (C) Gaijin Games KFT, 2023\n\n");

  int argc = __argc;

  if (argc < 2 || argc > 3)
  {
    printf("Usage: blk2dag <input_file> <output_file>\n");
    exit(1);
  }

  String input_name(__argv[1]);
  String output_name(__argv[2]);

  Blk2Dag *converter = new Blk2Dag;

  if (!converter->work(input_name, output_name))
  {
    printf("Convert failed.\n");
    return -1;
  }

  SAFE_DELETE(converter);
  printf("Convert ok.\n");
  return 0;
}

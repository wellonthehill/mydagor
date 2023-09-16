//
// DaEditor3
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <EditorCore/ec_decl.h>

class IDagorEd2Engine;
class IClipping;

class DagorEdAppWindow;
class DagorEdAppEventHandler;
class DagorEdPluginData;
class DagorEdPluginData;

class RenderableEditableObject;
class CoolConsole;
class DataBlock;

void dagored_init_all_plugins(const DataBlock &app_blk);

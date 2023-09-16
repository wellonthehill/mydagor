#include "joy_classdrv.h"
#include <humanInput/dag_hiCreate.h>
#include <humanInput/dag_hiDInput.h>
#include <debug/dag_debug.h>
using namespace HumanInput;

IGenJoystickClassDrv *HumanInput::createJoystickClassDriver(bool exclude_xinput, bool remap_360)
{
  if (!dinput8)
  {
    debug_ctx("DINPUT 8 must be initialized before this call!");
    return NULL;
  }

  Di8JoystickClassDriver *cd = new (inimem) Di8JoystickClassDriver(exclude_xinput, remap_360);
  if (!cd->init())
  {
    delete cd;
    cd = NULL;
  }
  return cd;
}

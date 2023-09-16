#include <workCycle/dag_startupModules.h>
#include <startup/dag_inpDevClsDrv.h>
#include <humanInput/dag_hiCreate.h>


void dagor_init_joystick()
{
  if (!global_cls_drv_joy)
    global_cls_drv_joy = HumanInput::createTvosJoystickClassDriver();
}

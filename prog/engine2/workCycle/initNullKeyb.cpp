#include <workCycle/dag_startupModules.h>
#include <startup/dag_inpDevClsDrv.h>
#include <humanInput/dag_hiCreate.h>

void dagor_init_keyboard_null()
{
  if (!global_cls_drv_kbd)
    global_cls_drv_kbd = HumanInput::createNullKeyboardClassDriver();
}

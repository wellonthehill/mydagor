#include <util/dag_globDef.h>
#include <ioSys/dag_zlibIo.h>

void ZlibLoadCB::issueFatal() { G_ASSERT(0 && "restricted by design"); }
void ZlibSaveCB::issueFatal() { G_ASSERT(0 && "restricted by design"); }

#include "dasScripts.h"
#include "dasBinding.h"
#include "guiScene.h"

#include <osApiWrappers/dag_files.h>
#include <osApiWrappers/dag_direct.h>

using namespace das;


namespace darg
{

struct DargContext final : das::Context
{
  DargContext(GuiScene *scene_, uint32_t stackSize) : das::Context(stackSize), scene(scene_) {}

  DargContext(Context &ctx, uint32_t category) = delete;

  void to_out(const das::LineInfo *, const char *message) { debug("daRg-das: %s", message); }

  void to_err(const das::LineInfo *, const char *message) { scene->errorMessageWithCb(message); }

  GuiScene *scene = nullptr;
};


void DasLogWriter::output()
{
  int newPos = tellp();
  if (newPos != pos)
  {
    int len = newPos - pos;
    debug("daRg-das: %.*s", len, data.data() + pos);
    pos = newPos;
  }
}


class DargFileAccess final : public das::ModuleFileAccess
{
public:
  DargFileAccess() {}

  DargFileAccess(const char *pak) : das::ModuleFileAccess(pak, das::make_smart<DargFileAccess>()) {}

  virtual das::FileInfo *getNewFileInfo(const das::string &fname) override;
  //  virtual das::ModuleInfo getModuleInfo(const das::string & req, const das::string & from) const override;
};


das::FileInfo *DargFileAccess::getNewFileInfo(const das::string &fname)
{
  file_ptr_t f = df_open(fname.c_str(), DF_READ);
  if (!f)
    return nullptr;

  const uint32_t fileLength = df_length(f);

  char *source = (char *)das_aligned_alloc16(fileLength + 1);
  if (df_read(f, source, fileLength) != fileLength)
  {
    df_close(f);
    das_aligned_free16(source);
    logerr("Cannot read file '%s'", fname.c_str());
    return nullptr;
  }

  df_close(f);
  source[fileLength] = 0;

  auto info = das::make_unique<das::TextFileInfo>(source, fileLength, true);
  return setFileInfo(fname, std::move(info));
}

/****************************************************************************/


/****************************************************************************/

DasScriptsData::DasScriptsData() : fAccess(make_smart<DargFileAccess>())
{
  typeGuiContextRef = dbgInfoHelper.makeTypeInfo(nullptr, makeType<StdGuiRender::GuiContext &>(moduleGroup));
  typeConstElemRenderDataRef = dbgInfoHelper.makeTypeInfo(nullptr, makeType<const ElemRenderData &>(moduleGroup));
  typeConstRenderStateRef = dbgInfoHelper.makeTypeInfo(nullptr, makeType<const RenderState &>(moduleGroup));
  typeConstPropsRef = dbgInfoHelper.makeTypeInfo(nullptr, makeType<const Properties &>(moduleGroup));
}


bool DasScriptsData::is_das_inited()
{
  if (!daScriptEnvironment::bound)
    return false;

  bool isDargBound = false;
  das::Module::foreach([&](Module *module) -> bool {
    if (module->name == "darg")
    {
      isDargBound = true;
      return false;
    }
    return true;
  });
  return isDargBound;
}


static void process_loaded_script(const das::Context &ctx, const char *filename)
{
  const uint64_t heapBytes = ctx.heap->bytesAllocated();
  const uint64_t stringHeapBytes = ctx.stringHeap->bytesAllocated();
  if (heapBytes > 0)
    logerr("daScript: script <%s> allocated %@ bytes for global variables", filename, heapBytes);
  if (stringHeapBytes > 0)
  {
    das::string strings = "";
    ctx.stringHeap->forEachString([&](const char *str) {
      if (strings.length() < 250)
        strings.append_sprintf("%s\"%s\"", strings.empty() ? "" : ", ", str);
    });
    logerr("daRg-das: script <%s> allocated %@ bytes for global strings. Allocated strings: %s", filename, stringHeapBytes,
      strings.c_str());
  }
}


static SQInteger load_das(HSQUIRRELVM vm)
{
  const char *filename = nullptr;
  sq_getstring(vm, 2, &filename);

  GuiScene *guiScene = GuiScene::get_from_sqvm(vm);
  G_ASSERT(guiScene);
  DasScriptsData *dasMgr = guiScene->dasScriptsData.get();
  if (!dasMgr)
    return sq_throwerror(vm, "Not using daScript in this VM");

  CodeOfPolicies policies;
  // policies.ignore_shared_modules = hard_reload;

  eastl::string strFileName(filename);

  dasMgr->fAccess->invalidateFileInfo(strFileName); // force reload, let quirrel script manage lifetime

  ProgramPtr program = compileDaScript(strFileName, dasMgr->fAccess, dasMgr->logWriter, dasMgr->moduleGroup, policies);

  if (program->failed())
  {
    eastl::string details(eastl::string::CtorSprintf{}, "Failed to compile '%s'", filename);

    for (const Error &e : program->errors)
    {
      details += "\n=============\n";
      details += das::reportError(e.at, e.what, e.extra, e.fixme, e.cerr);
    }
    guiScene->errorMessageWithCb(details.c_str());
    return sqstd_throwerrorf(vm, "Failed to compile '%s'", filename);
  }

  auto ctx = make_smart<DargContext>(guiScene, program->getContextStackSize());

  if (!program->simulate(*ctx.get(), dasMgr->logWriter))
  {
    eastl::string details(eastl::string::CtorSprintf{}, "Failed to simulate '%s'", filename);

    for (const Error &e : program->errors)
    {
      details += "\n=============\n";
      details += reportError(e.at, e.what, e.extra, e.fixme, e.cerr);
    }

    details += ctx->getStackWalk(nullptr, true, true);

    guiScene->errorMessageWithCb(details.c_str());
    return sqstd_throwerrorf(vm, "Failed to simulate '%s", filename);
  }

  process_loaded_script(*ctx, filename);

  DasScript *s = new DasScript();
  s->filename = filename;
  s->ctx = ctx;
  s->program = program;

  // Sqrat::ClassType<DasScript>::PushNativeInstance(vm, s);

  sq_pushobject(vm, Sqrat::ClassType<DasScript>::getClassData(vm)->classObj);
  G_VERIFY(SQ_SUCCEEDED(sq_createinstance(vm, -1)));
  Sqrat::ClassType<DasScript>::SetManagedInstance(vm, -1, s);

  return 1;
}


void bind_das(Sqrat::Table &exports)
{
  HSQUIRRELVM vm = exports.GetVM();

  Sqrat::Class<DasScript, Sqrat::NoConstructor<DasScript>> sqDasScript(vm, "DasScript");

  exports.SquirrelFunc("load_das", load_das, 2, ".s");
}

} // namespace darg

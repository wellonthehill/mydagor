#pragma once

#include <generic/dag_span.h>
#include <generic/dag_tab.h>

// forwards
class ShaderStateBlock;
class ShaderClass;
namespace mkbindump
{
class GatherNameMap;
}


// binary dump utility functions
namespace bindumphlp
{
void sortShaders(dag::ConstSpan<ShaderStateBlock *> blocks);
void patchStCode(dag::Span<int> code, dag::ConstSpan<int> remapTable);

// builds global variables remapping table
void countRefAndRemapGlobalVars(Tab<int> &dest_ref, dag::ConstSpan<ShaderClass *> shaderClasses, mkbindump::GatherNameMap &varMap);
} // namespace bindumphlp

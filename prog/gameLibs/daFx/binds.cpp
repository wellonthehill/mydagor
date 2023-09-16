#include "binds.h"
#include "buffers.h"
#include <shaders/dag_shaders.h>
#include <daFx/dafx_global_data_desc.hlsli>

namespace dafx
{
FastNameMapTS<false> fxSysNameMap;

bool register_value_binds(ValueBindMap &dst, const eastl::string &sys_name, const eastl::vector<ValueBindDesc> &binds, int size_limit,
  bool is_opt)
{
  G_UNUSED(sys_name);
  for (const ValueBindDesc &desc : binds)
  {
    G_ASSERTF(desc.offset >= 0 && desc.size > 0 && desc.offset <= 0xFFFFFF && desc.size <= 0xFF,
      "%s: desc.name=%s desc.offset=%d desc.size=%d", sys_name.c_str(), desc.name.c_str(), desc.offset, desc.size);
    if (desc.name.empty() || desc.offset < 0 || desc.size <= 0 || desc.offset + desc.size > size_limit)
    {
      logerr("dafx: sys: %s, register_value_binds invalid desc, (%s, %d, %d, %d)", sys_name.c_str(), desc.name.c_str(), desc.offset,
        desc.size, size_limit);
      return false;
    }

    int nameId = fxSysNameMap.addNameId(desc.name.c_str(), desc.name.length());
    ValueBindMap::iterator it = dst.find(nameId);
    if (it == dst.end())
    {
      dst.insert(nameId).first->second = {(unsigned)desc.offset, (unsigned)desc.size};
    }
    else
    {
      const ValueBind &v = it->second;
      if (!is_opt)
      {
        logerr("dafx: sys: %s, register_value_binds value:%s is already registered", sys_name.c_str(), desc.name.c_str());
        return false;
      }

      if (desc.offset != v.offset || desc.size != v.size)
      {
        logerr("dafx: sys: %s, register_value_binds '%s' is conflicted with the existed one (%d->%d, %d->%d)", sys_name.c_str(),
          desc.name.c_str(), desc.offset, v.offset, desc.size, v.size);
        return false;
      }
    }
  }
  return true;
}

ValueBindId create_local_value_binds(Binds &dst, const eastl::string &sys_name, const eastl::vector<ValueBindDesc> &binds,
  int size_limit)
{
  ValueBindId rid = dst.localValues.emplaceOne();
  ValueBindMap *v = dst.localValues.get(rid);
  G_ASSERT_RETURN(v, ValueBindId());

  return register_value_binds(*v, sys_name, binds, size_limit, false) ? rid : ValueBindId();
}

void release_local_value_binds(Binds &dst, ValueBindId rid)
{
  if (rid)
    dst.localValues.destroyReference(rid);
}

bool register_global_value_binds(Binds &dst, const eastl::string &sys_name, const eastl::vector<ValueBindDesc> &binds)
{
  return register_value_binds(dst.globalValues, sys_name, binds, DAFX_GLOBAL_DATA_SIZE, true);
}
} // namespace dafx
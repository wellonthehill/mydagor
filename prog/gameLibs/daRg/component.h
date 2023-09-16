#pragma once


#include <daRg/dag_renderObject.h>
#include <dag/dag_vector.h>
#include <memory/dag_framemem.h>

#include <sqrat.h>


namespace darg
{

class StringKeys;
class Behavior;


class Component
{
public:
  using TmpVector = dag::Vector<Component, framemem_allocator>;

  static bool build_component(Component &comp, const Sqrat::Object &desc, const StringKeys *csk, const Sqrat::Object &parent_builder);

  void readChildrenObjects(const Sqrat::Object &parent_builder, const StringKeys *csk,
    dag::Vector<Sqrat::Object, framemem_allocator> &out_children) const;

  void reset();

private:
  static void check_if_desc_may_be_component(const Sqrat::Table &desc, const Sqrat::Object &nearest_builder, const StringKeys *csk);

  static int read_robj_type(const Sqrat::Table &desc, const StringKeys *csk);
  static void read_behaviors(const Sqrat::Table &desc, const StringKeys *csk, dag::Vector<Behavior *> &behaviors);

  static bool resolve_description(const Sqrat::Object &desc, Sqrat::Table &desc_tbl, Sqrat::Object &builder);

public:
  Sqrat::Object uniqueKey;

  int rendObjType = ROBJ_NONE;

  Sqrat::Table scriptDesc;
  Sqrat::Object scriptBuilder;

  dag::Vector<Behavior *> behaviors;
};


} // namespace darg

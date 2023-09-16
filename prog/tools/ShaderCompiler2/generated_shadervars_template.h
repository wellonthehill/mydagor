#pragma once


// This file was generated by template {{template}}
// Please do not commit manual changes made to this file
// You can change it locally. But if you want it to be changed for everyone, then change the template
// Then you will have to recompile all the shaders

#include <supp/dag_shadervar_generator.h>

// clang-format off
#ifdef SHADERVARS_DISABLE_ASSERT
#define SHADERVARS_ASSERT(...)
#else
#define SHADERVARS_ASSERT G_ASSERT
#endif

namespace shadervars
{
namespace detail
{
{{for shadervars}}
  template<typename = void>
  Node {{shadervar_name}}_node("{{shadervar_name}}");
{{end for shadervars}}
}  // namespace detail
{{for shadervars}}
  static const int &{{shadervar_name}} = detail::{{shadervar_name}}_node<>.shadervarId;
{{end for shadervars}}
} // namespace shadervars

namespace intervals
{
{{for intervals}}
  // Interval name: {{interval_name}}
  enum class {{IntervalName}}
  {
{{for values}}
    {{VALUE_NAME}} = {{value}}, // {{value_name}}
{{end for values}}
    {{LAST_VALUE_NAME}},        // {{last_value_name}}
  };

  inline bool verify({{IntervalName}} value)
  {
    return
{{for values}}
      value == {{IntervalName}}::{{VALUE_NAME}} ||
{{end for values}}
      value == {{IntervalName}}::{{LAST_VALUE_NAME}};
  }

  inline bool set_{{interval_name}}({{IntervalName}} value)
  {
    SHADERVARS_ASSERT(verify(value));
    return ShaderGlobal::set_int(shadervars::{{interval_name}}, static_cast<int>(value));
  }

  inline const char *{{interval_name}}_to_string(int value)
  {
{{for values}}
    if (value <= {{value}})
      return "{{value_name}}";
{{end for values}}
    return "{{last_value_name}}";
  }

  inline const char *{{interval_name}}_to_string({{IntervalName}} value)
  {
    return {{interval_name}}_to_string(static_cast<int>(value));
  }

  inline eastl::optional<{{IntervalName}}> string_to_{{interval_name}}(const char *str)
  {
{{for values}}
    if (strcmp(str, "{{value_name}}") == 0)
      return {{IntervalName}}::{{VALUE_NAME}};
{{end for values}}
    if (strcmp(str, "{{last_value_name}}") == 0)
      return {{IntervalName}}::{{LAST_VALUE_NAME}};
    return eastl::nullopt;
  }

  template<typename Func>
  void foreach_{{interval_name}}(Func &&func)
  {
{{for values}}
    func({{IntervalName}}::{{VALUE_NAME}}, "{{value_name}}");
{{end for values}}
    func({{IntervalName}}::{{LAST_VALUE_NAME}}, "{{last_value_name}}");
  }

  class {{IntervalName}}ConVarBase : public ConVarT<int, true>
  {
  public:
    {{IntervalName}}ConVarBase(const char *name, {{IntervalName}} def_val)
      : ConVarT(name
        , static_cast<int>(def_val)
        , static_cast<int>({{IntervalName}}::{{FIRST_VALUE_NAME}})
        , static_cast<int>({{IntervalName}}::{{LAST_VALUE_NAME}})
        , nullptr)
    {}
    void describeValue(char *buf, size_t buf_size) const override
    {
      snprintf(buf, buf_size, "%s = %d - %s ["
        {{for values}} "%d - %s, " {{end for values}} "%s]",
        getName(), ConVarT::get(), {{interval_name}}_to_string(ConVarT::get()),
{{for values}}
          {{value}}, "{{value_name}}",
{{end for values}}
          "{{last_value_name}}");
    }
  };
  using {{IntervalName}}ConVar = IntervalConVar<{{IntervalName}}ConVarBase, {{IntervalName}}>;
{{end for intervals}}
} // namespace intervals

#undef SHADERVARS_ASSERT

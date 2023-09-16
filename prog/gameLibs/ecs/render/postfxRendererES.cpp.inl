#include <ecs/render/postfx_renderer.h>
#include <daECS/core/componentTypes.h>

struct PostFxRendererConstruct final : public PostFxRenderer
{
public:
  PostFxRendererConstruct() = default;
  PostFxRendererConstruct(ecs::EntityManager &mgr, ecs::EntityId eid, ecs::component_index_t index)
  {
    const char *component_name = mgr.getDataComponents().getComponentNameById(index);
    eastl::string tmpName(eastl::string::CtorSprintf(), "%s_name", component_name);
    const ecs::string *shader_name = mgr.getNullable<ecs::string>(eid, ECS_HASH_SLOW(tmpName.c_str()));
    eastl::string tmpOptional(eastl::string::CtorSprintf(), "%s_is_optional", component_name);
    bool isOptional = mgr.getOr<bool>(eid, ECS_HASH_SLOW(tmpOptional.c_str()), false);
    if (shader_name)
      ((PostFxRenderer *)this)->init(shader_name->c_str(), nullptr, !isOptional);
  }
};

ECS_REGISTER_MANAGED_TYPE(PostFxRenderer, nullptr,
  typename ecs::CreatorSelector<PostFxRenderer ECS_COMMA PostFxRendererConstruct>::type);

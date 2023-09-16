#include <dasModules/aotSoundEvent.h>
#include <daScript/ast/ast_policy_types.h>
#include <daScript/simulate/sim_policy.h>

namespace das
{
IMPLEMENT_OP1_EVAL_POLICY(BoolNot, sndsys::EventHandle);
IMPLEMENT_OP2_EVAL_BOOL_POLICY(Equ, sndsys::EventHandle);
IMPLEMENT_OP2_EVAL_BOOL_POLICY(NotEqu, sndsys::EventHandle);

IMPLEMENT_OP1_EVAL_POLICY(BoolNot, SoundVarId);
IMPLEMENT_OP2_EVAL_BOOL_POLICY(Equ, SoundVarId);
IMPLEMENT_OP2_EVAL_BOOL_POLICY(NotEqu, SoundVarId);
}; // namespace das

namespace soundevent_bind_dascript
{
struct SoundEventHandleAnnotation final : das::ManagedValueAnnotation<sndsys::EventHandle>
{
  SoundEventHandleAnnotation(das::ModuleLibrary &ml) : ManagedValueAnnotation(ml, "SoundEventHandle", " ::sndsys::EventHandle") {}
  void walk(das::DataWalker &walker, void *data) override
  {
    if (!walker.reading)
    {
      const sndsys::EventHandle *t = (sndsys::EventHandle *)data;
      G_STATIC_ASSERT((eastl::is_same<int32_t, sndsys::sound_handle_t>::value));
      int32_t value = sndsys::sound_handle_t(*t);
      walker.Int(value);
    }
  }
  bool canBePlacedInContainer() const override { return true; }
};

struct SoundVarIdAnnotation final : das::ManagedValueAnnotation<SoundVarId>
{
  SoundVarIdAnnotation(das::ModuleLibrary &ml) : ManagedValueAnnotation(ml, "SoundVarId", " ::SoundVarId") {}
  void walk(das::DataWalker &walker, void *data) override
  {
    if (!walker.reading)
    {
      const SoundVarId *t = (SoundVarId *)data;
      G_STATIC_ASSERT((eastl::is_same<uint64_t, sndsys::var_id_t>::value));
      uint64_t value = sndsys::var_id_t(*t);
      walker.UInt64(value);
    }
  }
  bool canBePlacedInContainer() const override { return true; }
};

struct SoundEventAnnotation final : das::ManagedStructureAnnotation<SoundEvent, false>
{
  SoundEventAnnotation(das::ModuleLibrary &ml) : ManagedStructureAnnotation("SoundEvent", ml)
  {
    cppName = " ::SoundEvent";
    addField<DAS_BIND_MANAGED_FIELD(handle)>("handle");
    addField<DAS_BIND_MANAGED_FIELD(abandonOnReset)>("abandonOnReset");
    addField<DAS_BIND_MANAGED_FIELD(enabled)>("enabled");
  }
  void walk(das::DataWalker &walker, void *data) override
  {
    if (!walker.reading)
    {
      const SoundEvent *t = (SoundEvent *)data;
      int32_t eidV = int32_t(sndsys::sound_handle_t(t->handle));
      walker.Int(eidV);
    }
  }
  bool canCopy() const override { return false; }
  bool canMove() const override { return false; }
  bool canClone() const override { return false; }
};

struct SoundGroupAnnotation final : das::ManagedStructureAnnotation<SoundEventGroup, false>
{
  SoundGroupAnnotation(das::ModuleLibrary &ml) : ManagedStructureAnnotation("SoundEventGroup", ml) { cppName = " ::SoundEventGroup"; }
  void walk(das::DataWalker &walker, void *data) override
  {
    if (!walker.reading)
    {
      const SoundEventGroup *t = (SoundEventGroup *)data;
      int32_t eidV = int32_t(t->sounds.size());
      walker.Int(eidV);
    }
  }
  bool canCopy() const override { return false; }
  bool canMove() const override { return false; }
  bool canClone() const override { return false; }
};

struct VisualLabelAnnotation : das::ManagedStructureAnnotation<sndsys::VisualLabel, false>
{
  VisualLabelAnnotation(das::ModuleLibrary &ml) : ManagedStructureAnnotation("VisualLabel", ml)
  {
    cppName = " ::sndsys::VisualLabel";
    addField<DAS_BIND_MANAGED_FIELD(pos)>("pos");
    addField<DAS_BIND_MANAGED_FIELD(radius)>("radius");
    addFieldEx("name", "name", offsetof(sndsys::VisualLabel, name), das::makeType<char *>(ml));
  }
  bool hasNonTrivialCopy() const override { return false; } // for emplace(push_clone) to the containers in das
  bool canBePlacedInContainer() const override { return true; }
};
} // namespace soundevent_bind_dascript

#define SND_BIND_FUN_EX(FUN, NAME, SIDE_EFFECTS) \
  das::addExtern<DAS_BIND_FUN(FUN)>(*this, lib, NAME, SIDE_EFFECTS, "soundevent_bind_dascript::" #FUN)
#define SND_BIND_FUN(FUN, SIDE_EFFECTS) SND_BIND_FUN_EX(FUN, #FUN, SIDE_EFFECTS)

namespace soundevent_bind_dascript
{
class SoundEventModule final : public das::Module
{
public:
  SoundEventModule() : das::Module("soundEvent")
  {
    das::ModuleLibrary lib(this);

    addAnnotation(das::make_smart<SoundEventHandleAnnotation>(lib));
    addAnnotation(das::make_smart<SoundVarIdAnnotation>(lib));
    addAnnotation(das::make_smart<SoundEventAnnotation>(lib));
    addAnnotation(das::make_smart<SoundGroupAnnotation>(lib));
    addAnnotation(das::make_smart<VisualLabelAnnotation>(lib));

    das::addFunctionBasic<sndsys::EventHandle>(*this, lib);
    das::addFunctionBasic<SoundVarId>(*this, lib);
    addFunction(
      das::make_smart<das::BuiltInFn<das::Sim_BoolNot<sndsys::EventHandle>, bool, sndsys::EventHandle>>("!", lib, "BoolNot"));
    addFunction(das::make_smart<das::BuiltInFn<das::Sim_BoolNot<SoundVarId>, bool, SoundVarId>>("!", lib, "BoolNot"));

    das::addCtorAndUsing<sndsys::VisualLabel>(*this, lib, "VisualLabel", "::sndsys::VisualLabel");
    das::addCtorAndUsing<sndsys::VisualLabels>(*this, lib, "VisualLabels", "::sndsys::VisualLabels");

    SND_BIND_FUN(add_sound, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN_EX(add_sound_with_pos, "add_sound", das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(remove_sound, das::SideEffects::modifyArgument);
    SND_BIND_FUN(release_all_sounds, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(abandon_all_sounds, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(reject_sound, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN_EX(reject_sound_with_stop, "reject_sound", das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(release_sound, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(get_sound, das::SideEffects::none);
    SND_BIND_FUN(has_sound, das::SideEffects::none);
    SND_BIND_FUN_EX(has_sound_with_name_path, "has_sound", das::SideEffects::none);
    SND_BIND_FUN(get_num_sounds, das::SideEffects::none);
    SND_BIND_FUN_EX(get_num_sounds_with_id, "get_num_sounds", das::SideEffects::none);
    SND_BIND_FUN(get_max_capacity, das::SideEffects::none);
    SND_BIND_FUN(update_sounds, das::SideEffects::modifyArgumentAndExternal);

    SND_BIND_FUN_EX(is_valid_event_handle, "is_valid", das::SideEffects::none);
    SND_BIND_FUN(invalid_sound_event_handle, das::SideEffects::none);

    SND_BIND_FUN_EX(play_with_name, "play", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(play_with_name_pos, "play", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(play_with_name_path_pos, "play", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(play_with_name_path_pos_far, "play", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(play_with_name_pos_vol, "play", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(delayed_play_with_name_path_pos, "delayed_play", das::SideEffects::modifyExternal);

    SND_BIND_FUN_EX(play_sound_with_name, "play", das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN_EX(play_sound_with_name_pos, "play", das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN_EX(play_sound_with_name_path_pos, "play", das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN_EX(play_sound_with_name_pos_vol, "play", das::SideEffects::modifyArgumentAndExternal);

    SND_BIND_FUN_EX(oneshot_with_name_pos, "oneshot", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(oneshot_with_name, "oneshot", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(oneshot_with_name_pos_far, "oneshot", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(delayed_oneshot_with_name_pos, "delayed_oneshot", das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(delayed_oneshot_with_name, "delayed_oneshot", das::SideEffects::modifyExternal);

    SND_BIND_FUN(should_play, das::SideEffects::modifyExternal);
    SND_BIND_FUN_EX(should_play_ex, "should_play", das::SideEffects::modifyExternal);

    SND_BIND_FUN(is_oneshot, das::SideEffects::accessExternal);
    SND_BIND_FUN(is_playing, das::SideEffects::accessExternal);
    SND_BIND_FUN(is_valid_event, das::SideEffects::accessExternal);
    SND_BIND_FUN(is_valid_event_instance, das::SideEffects::accessExternal);

    SND_BIND_FUN(get_max_distance, das::SideEffects::accessExternal);
    SND_BIND_FUN_EX(get_max_distance_name, "get_max_distance", das::SideEffects::accessExternal);

    SND_BIND_FUN(has, das::SideEffects::modifyExternal);

    SND_BIND_FUN(set_pos, das::SideEffects::modifyExternal);
    SND_BIND_FUN(set_var, das::SideEffects::modifyExternal);
    SND_BIND_FUN(set_var_optional, das::SideEffects::modifyExternal);
    SND_BIND_FUN(set_var_global, das::SideEffects::modifyExternal);
    SND_BIND_FUN(invalid_sound_var_id, das::SideEffects::none);
    SND_BIND_FUN(get_var_id_global, das::SideEffects::accessExternal);
    SND_BIND_FUN_EX(set_var_global_with_id, "set_var_global", das::SideEffects::modifyExternal);

    SND_BIND_FUN(set_volume, das::SideEffects::modifyExternal);
    SND_BIND_FUN(set_pitch, das::SideEffects::modifyExternal);

    SND_BIND_FUN(get_timeline_position, das::SideEffects::accessExternal);
    SND_BIND_FUN(set_timeline_position, das::SideEffects::modifyExternal);
    SND_BIND_FUN(get_length, das::SideEffects::modifyExternal);

    SND_BIND_FUN(release_immediate, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(release, das::SideEffects::modifyArgumentAndExternal);

    SND_BIND_FUN(abandon_immediate, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(abandon, das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN_EX(abandon_with_delay, "abandon", das::SideEffects::modifyArgumentAndExternal);
    SND_BIND_FUN(keyoff, das::SideEffects::modifyExternal);
    SND_BIND_FUN(is_3d, das::SideEffects::accessExternal);

    SND_BIND_FUN_EX(das_query_visual_labels, "query_visual_labels", das::SideEffects::modifyExternal);

    verifyAotReady();
  }

  virtual das::ModuleAotType aotRequire(das::TextWriter &tw) const override
  {
    tw << "#include <dasModules/aotSoundEvent.h>\n";
    return das::ModuleAotType::cpp;
  }
};
} // namespace soundevent_bind_dascript

REGISTER_MODULE_IN_NAMESPACE(SoundEventModule, soundevent_bind_dascript);

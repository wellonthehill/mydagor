#ifndef _DAGOR_GAMELIB_SOUNDSYSTEM_VISUALLABELSINTERNAL_H_
#define _DAGOR_GAMELIB_SOUNDSYSTEM_VISUALLABELSINTERNAL_H_
#pragma once

namespace FMOD
{
namespace Studio
{
class EventInstance;
class EventDescription;
} // namespace Studio
} // namespace FMOD

namespace sndsys
{
class EventAttributes;

void update_visual_labels(float dt);
void invalidate_visual_labels();
void append_visual_label(const FMOD::Studio::EventDescription &event_description, const EventAttributes &attributes);
int get_visual_label_idx(const char *name);
} // namespace sndsys

#endif

//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <sqrat.h>


typedef struct SQVM *HSQUIRRELVM;

namespace darg
{
#define DARG_STRING_KEYS_LIST \
  KEY(action)                 \
  KEY(active)                 \
  KEY(angle)                  \
  KEY(animations)             \
  KEY(attach)                 \
  KEY(behavior)               \
  KEY(bgColor)                \
  KEY(borderColor)            \
  KEY(borderRadius)           \
  KEY(borderWidth)            \
  KEY(brightness)             \
  KEY(btnId)                  \
  KEY(btnName)                \
  KEY(buttons)                \
  KEY(canDrop)                \
  KEY(charMask)               \
  KEY(children)               \
  KEY(click)                  \
  KEY(clickableInfo)          \
  KEY(clipChildren)           \
  KEY(color)                  \
  KEY(colorTable)             \
  KEY(commands)               \
  KEY(counterAct)             \
  KEY(counterBeforeRender)    \
  KEY(curAngle)               \
  KEY(curSector)              \
  KEY(cursor)                 \
  KEY(cursorNavAnchor)        \
  KEY(cursorPos)              \
  KEY(data)                   \
  KEY(defaultUrl)             \
  KEY(delay)                  \
  KEY(description)            \
  KEY(detach)                 \
  KEY(devId)                  \
  KEY(disableInput)           \
  KEY(drag)                   \
  KEY(draw)                   \
  KEY(drawFunc)               \
  KEY(dragAndDropState)       \
  KEY(dragMouseButton)        \
  KEY(dropData)               \
  KEY(duration)               \
  KEY(easing)                 \
  KEY(elem)                   \
  KEY(ellipsis)               \
  KEY(eventId)                \
  KEY(eventHandlers)          \
  KEY(eventName)              \
  KEY(eventPassThrough)       \
  KEY(fValue)                 \
  KEY(fallbackImage)          \
  KEY(fgColor)                \
  KEY(fillColor)              \
  KEY(flex)                   \
  KEY(flipX)                  \
  KEY(flipY)                  \
  KEY(flow)                   \
  KEY(focusOnClick)           \
  KEY(font)                   \
  KEY(fontFx)                 \
  KEY(fontFxColor)            \
  KEY(fontFxFactor)           \
  KEY(fontFxOffsX)            \
  KEY(fontFxOffsY)            \
  KEY(fontSize)               \
  KEY(fontTex)                \
  KEY(fontTexBov)             \
  KEY(fontTexSu)              \
  KEY(fontTexSv)              \
  KEY(formattedText)          \
  KEY(from)                   \
  KEY(gap)                    \
  KEY(globalTimer)            \
  KEY(group)                  \
  KEY(h)                      \
  KEY(halign)                 \
  KEY(handle)                 \
  KEY(hangingIndent)          \
  KEY(hiFreq)                 \
  KEY(hint)                   \
  KEY(hold)                   \
  KEY(hotkeys)                \
  KEY(hotspot)                \
  KEY(hover)                  \
  KEY(hplace)                 \
  KEY(ignoreConsumerCallback) \
  KEY(ignoreEarlyClip)        \
  KEY(ignoreWheel)            \
  KEY(image)                  \
  KEY(imageAffectsLayout)     \
  KEY(imageHalign)            \
  KEY(imageValign)            \
  KEY(imeNoAutoCap)           \
  KEY(imeNoCopy)              \
  KEY(indent)                 \
  KEY(inputPassive)           \
  KEY(inputType)              \
  KEY(isDraggingKnob)         \
  KEY(isHidden)               \
  KEY(isPlaying)              \
  KEY(isViewport)             \
  KEY(joystickScroll)         \
  KEY(keepAspect)             \
  KEY(key)                    \
  KEY(knob)                   \
  KEY(knobOffset)             \
  KEY(last)                   \
  KEY(lastT)                  \
  KEY(lastX)                  \
  KEY(lastY)                  \
  KEY(lineSpacing)            \
  KEY(lineWidth)              \
  KEY(loFreq)                 \
  KEY(loop)                   \
  KEY(lowLineCount)           \
  KEY(lowLineCountAlign)      \
  KEY(margin)                 \
  KEY(max)                    \
  KEY(maxChars)               \
  KEY(maxContentWidth)        \
  KEY(maxHeight)              \
  KEY(maxWidth)               \
  KEY(min)                    \
  KEY(minFontSize)            \
  KEY(minHeight)              \
  KEY(minWidth)               \
  KEY(monoWidth)              \
  KEY(moveResizeCursors)      \
  KEY(moveResizeModes)        \
  KEY(movie)                  \
  KEY(movieFileName)          \
  KEY(moviePlayer)            \
  KEY(soundPlayer)            \
  KEY(onAbort)                \
  KEY(onAttach)               \
  KEY(onBlur)                 \
  KEY(onChange)               \
  KEY(onClick)                \
  KEY(onDetach)               \
  KEY(onDoubleClick)          \
  KEY(onDragMode)             \
  KEY(onDrop)                 \
  KEY(onElemState)            \
  KEY(onEnter)                \
  KEY(onEscape)               \
  KEY(onExit)                 \
  KEY(onFinish)               \
  KEY(onFocus)                \
  KEY(onHover)                \
  KEY(onSliderMouseMove)      \
  KEY(onMouseMove)            \
  KEY(onMouseWheel)           \
  KEY(onPointerPress)         \
  KEY(onPointerMove)          \
  KEY(onPointerRelease)       \
  KEY(onRecalcLayout)         \
  KEY(onReturn)               \
  KEY(onScroll)               \
  KEY(onStart)                \
  KEY(onTouchHold)            \
  KEY(touchHoldTime)          \
  KEY(onWrongInput)           \
  KEY(opacity)                \
  KEY(orientation)            \
  KEY(padding)                \
  KEY(pageScroll)             \
  KEY(panMouseButton)         \
  KEY(parSpacing)             \
  KEY(parallaxK)              \
  KEY(password)               \
  KEY(phase)                  \
  KEY(picSaturate)            \
  KEY(pivot)                  \
  KEY(play)                   \
  KEY(playFadeOut)            \
  KEY(pos)                    \
  KEY(preformatted)           \
  KEY(priority)               \
  KEY(priorityOffset)         \
  KEY(prop)                   \
  KEY(rendObj)                \
  KEY(rotate)                 \
  KEY(rtAlwaysUpdate)         \
  KEY(rtRecalcLayout)         \
  KEY(rumble)                 \
  KEY(safeAreaMargin)         \
  KEY(saturation)             \
  KEY(setupFunc)              \
  KEY(scale)                  \
  KEY(screenOffs)             \
  KEY(script)                 \
  KEY(scrollEventPrevContH)   \
  KEY(scrollEventPrevContW)   \
  KEY(scrollEventPrevElemH)   \
  KEY(scrollEventPrevElemW)   \
  KEY(scrollEventPrevX)       \
  KEY(scrollEventPrevY)       \
  KEY(scrollHandler)          \
  KEY(scrollOffsX)            \
  KEY(scrollOffsY)            \
  KEY(scrollOnHover)          \
  KEY(scrollSpeed)            \
  KEY(scrollToEdge)           \
  KEY(sectorsCount)           \
  KEY(size)                   \
  KEY(skipDirPadNav)          \
  KEY(sortChildren)           \
  KEY(sortOrder)              \
  KEY(sound)                  \
  KEY(spacing)                \
  KEY(speed)                  \
  KEY(start)                  \
  KEY(stextChangeCount)       \
  KEY(stextLastKey)           \
  KEY(stextLastVal)           \
  KEY(stickCursor)            \
  KEY(stickNo)                \
  KEY(stop)                   \
  KEY(stopHotkeys)            \
  KEY(stopHover)              \
  KEY(stopMouse)              \
  KEY(subPixel)               \
  KEY(tagsTable)              \
  KEY(target)                 \
  KEY(texOffs)                \
  KEY(text)                   \
  KEY(textOverflowX)          \
  KEY(textOverflowY)          \
  KEY(threshold)              \
  KEY(tint)                   \
  KEY(title)                  \
  KEY(to)                     \
  KEY(transform)              \
  KEY(transitions)            \
  KEY(translate)              \
  KEY(trigger)                \
  KEY(unit)                   \
  KEY(update)                 \
  KEY(updateCounterElem)      \
  KEY(validateStaticText)     \
  KEY(valign)                 \
  KEY(viscosity)              \
  KEY(vplace)                 \
  KEY(w)                      \
  KEY(watch)                  \
  KEY(waitForChildrenFadeOut) \
  KEY(xmbNode)                \
  KEY(zOrder)                 \
  KEY(opacityCenterMinMult)   \
  KEY(opacityCenterRelativeDist)


class StringKeys
{
public:
#define KEY(x) Sqrat::Object x;
  DARG_STRING_KEYS_LIST
#undef KEY

public:
  void init(HSQUIRRELVM vm);

private:
  void getStr(HSQUIRRELVM vm, const char *str, Sqrat::Object &obj);
};

} // namespace darg

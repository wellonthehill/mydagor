//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

//
// forward declarations for all AnimV20 namespaces and classes
//
namespace AnimV20
{
// general anim data holder structs
struct AnimKeyPoint3;
struct AnimKeyQuat;
struct AnimKeyReal;

template <class KEY>
struct AnimChan;
typedef AnimChan<AnimKeyPoint3> AnimChanPoint3;
typedef AnimChan<AnimKeyQuat> AnimChanQuat;
typedef AnimChan<AnimKeyReal> AnimChanReal;
struct AnimKeyLabel;

// shareable animation (a2d)
class AnimData;

// general anim interfaces
class IGenericIrq;
class AnimCommonStateHolder;
class IAnimBlendNode;
typedef AnimCommonStateHolder IPureAnimStateHolder;
typedef AnimCommonStateHolder IAnimStateHolder;

// shareable animation graph
class AnimationGraph;

// leaf blend node variations
class AnimBlendNodeLeaf;
class AnimBlendNodeContinuousLeaf;
class AnimBlendNodeSingleLeaf;
class AnimBlendNodeStillLeaf;
class AnimBlendNodeParametricLeaf;
class AnimBlendNodeNull;

// blend controllers
class AnimBlendCtrl_1axis;
class AnimBlendCtrl_Fifo3;
class AnimBlendCtrl_RandomSwitcher;
class AnimBlendCtrl_Hub;
class AnimBlendCtrl_Blender;
class AnimBlendCtrl_BinaryIndirectSwitch;

// post-blend controllers
class AnimPostBlendCtrl;
class AnimPostBlendAlignCtrl;

// motion matching controller
class IMotionMatchingController;

// general anim character interfaces
class IAnimStateDirector2;
class IAnimStateDirector2Debug;
struct AnimCharCreationProps;
class AnimcharBaseComponent;
class AnimcharRendComponent;
class IAnimCharacter2;

// generally internal structures
struct AnimTmpWeightedNode;
struct AnimFifo3Queue;

// generally internal classes and interface implementations
class AnimBlender;
class AnimCondState;
class AnimStateDirector;
} // namespace AnimV20

//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <daScript/daScript.h>
#include <dasModules/aotEcs.h>
#include <dasModules/dasModulesCommon.h>
#include <dasModules/dasManagedTab.h>
#include <dasModules/aotProps.h>
#include <daECS/core/componentType.h>
#include <gamePhys/ballistics/projectileBallisticProps.h>
#include <gamePhys/ballistics/shellBallisticProps.h>
#include <gamePhys/ballistics/shellBallistics.h>
#include <gamePhys/ballistics/rocketMotorProps.h>
#include <ecs/gamePhys/ballistics.h>

MAKE_TYPE_FACTORY(ProjectileProps, ballistics::ProjectileProps);
MAKE_TYPE_FACTORY(ShellProps, ballistics::ShellProps);
MAKE_TYPE_FACTORY(RocketMotorProps, ballistics::RocketMotorProps);

using RocketMotorPropsArrayFloat2 = carray<float, 2>;
DAS_BIND_ARRAY(RocketMotorPropsArrayFloat2, RocketMotorPropsArrayFloat2, Point3);

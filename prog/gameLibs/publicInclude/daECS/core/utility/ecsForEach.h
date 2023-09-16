//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#define ECS_EXPAND(x) x

#define ECS_FOR_EACH_1(WHAT, X)       WHAT(X)
#define ECS_FOR_EACH_2(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_1(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_3(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_2(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_4(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_3(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_5(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_4(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_6(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_5(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_7(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_6(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_8(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_7(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_9(WHAT, X, ...)  WHAT(X) ECS_EXPAND(ECS_FOR_EACH_8(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_10(WHAT, X, ...) WHAT(X) ECS_EXPAND(ECS_FOR_EACH_9(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_11(WHAT, X, ...) WHAT(X) ECS_EXPAND(ECS_FOR_EACH_10(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_12(WHAT, X, ...) WHAT(X) ECS_EXPAND(ECS_FOR_EACH_11(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_13(WHAT, X, ...) WHAT(X) ECS_EXPAND(ECS_FOR_EACH_12(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_14(WHAT, X, ...) WHAT(X) ECS_EXPAND(ECS_FOR_EACH_13(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH_15(WHAT, X, ...) WHAT(X) ECS_EXPAND(ECS_FOR_EACH_14(WHAT, __VA_ARGS__))
//... repeat as needed
#define ECS_FOR_EACH_NARG(...)        ECS_FOR_EACH_NARG_(__VA_ARGS__, ECS_FOR_EACH_RSEQ_N())
#define ECS_FOR_EACH_NARG_(...)       ECS_EXPAND(ECS_FOR_EACH_ARG_N(__VA_ARGS__))

#define ECS_FOR_EACH_ARG_N(_1, _2, _3, _4, _5, _6, _7, _8, _9, _10, _11, _12, _13, _14, _15, N, ...) N

#define ECS_FOR_EACH_RSEQ_N()       15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
#define ECS_CONCATENATE(x, y)       x##y
#define ECS_FOR_EACH_(N, WHAT, ...) ECS_EXPAND(CONCATENATE(ECS_FOR_EACH_, N)(WHAT, __VA_ARGS__))
#define ECS_FOR_EACH(WHAT, ...)     ECS_FOR_EACH_(ECS_FOR_EACH_NARG(__VA_ARGS__), WHAT, __VA_ARGS__)

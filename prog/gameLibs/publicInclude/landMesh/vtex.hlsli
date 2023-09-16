#define TILE_WIDTH (128) // size of indirection
#define TILE_WIDTH_BITS (7)
#define TEX_MIPS (7)

#ifdef CLIPMAP_USE_RI_VTEX
  #define MAX_RI_VTEX_CNT_BITS (3)
#else
  #define MAX_RI_VTEX_CNT_BITS (0)
#endif

#define MAX_VTEX_CNT (1 << MAX_RI_VTEX_CNT_BITS)
#define MAX_RI_VTEX_CNT (MAX_VTEX_CNT - 1) // excluding terrain

#define FEEDBACK_WIDTH (320)
#define FEEDBACK_HEIGHT (192)

#define TILE_PACKED_X_BITS (7)
#define TILE_PACKED_Y_BITS (7)
#define TILE_PACKED_MIP_BITS (3)
#define TILE_PACKED_COUNT_BITS (32 - (TILE_PACKED_X_BITS + TILE_PACKED_Y_BITS + TILE_PACKED_MIP_BITS))

#define TEX_TOTAL_ELEMENTS (TILE_WIDTH * TILE_WIDTH * TEX_MIPS * MAX_VTEX_CNT)

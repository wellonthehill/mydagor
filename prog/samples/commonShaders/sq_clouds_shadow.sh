include "clouds_shadow.sh"

macro SQ_INIT_CLOUDS_SHADOW()
  INIT_CLOUDS_SHADOW(to_sun_direction)
endmacro

macro SQ_CLOUDS_SHADOW()
  USE_CLOUDS_SHADOW()
endmacro
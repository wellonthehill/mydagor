int num_probe_mips = 7 always_referenced;

macro USE_ROUGH_TO_MIP()
hlsl {

#define ROUGHEST_MIP 0.5h
#define ROUGHNESS_MIP_SCALE 1.2h
#ifndef NUM_PROBE_MIPS
#define NUM_PROBE_MIPS 7.h
#endif

half ComputeReflectionCaptureMipFromRoughness(half Roughness)
{
  half LevelFrom1x1 = ROUGHEST_MIP - ROUGHNESS_MIP_SCALE * log2(max(1e-6h, Roughness));
  return NUM_PROBE_MIPS - 1.h - LevelFrom1x1;
}

float ComputeReflectionCaptureRoughnessFromMip( float Mip )
{
  float LevelFrom1x1 = NUM_PROBE_MIPS - 1.0 - Mip;
  return exp2( ROUGHEST_MIP * rcp(ROUGHNESS_MIP_SCALE) - LevelFrom1x1 * rcp(ROUGHNESS_MIP_SCALE)  );
}

}
endmacro

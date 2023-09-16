hlsl {
  float4 mulPointTm(float3 pt, float4x4 tm)
  {
#if INTEL_PRECISE_BUG_WORKAROUND
    return INVARIANT(mul(float4(pt, 1), tm)); // GPU hung bug on Intel 4000 and 5000 GPU families when PRECISE modifier is used on the original function.
#else
    return INVARIANT(pt.x*tm[0] + (pt.y*tm[1] + (pt.z*tm[2]+tm[3])));
#endif
  }
}

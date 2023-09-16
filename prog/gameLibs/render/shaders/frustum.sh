float4 frustumPlane03X;
float4 frustumPlane03Y;
float4 frustumPlane03Z;
float4 frustumPlane03W;
float4 frustumPlane4;
float4 frustumPlane5;
macro INIT_AND_USE_FRUSTUM_CHECK_BASE(stage)
  (stage) {
    frustumPlane03X@f4 = frustumPlane03X;
    frustumPlane03Y@f4 = frustumPlane03Y;
    frustumPlane03Z@f4 = frustumPlane03Z;
    frustumPlane03W@f4 = frustumPlane03W;
    frustumPlane4@f4 = frustumPlane4;
    frustumPlane5@f4 = frustumPlane5;
  }
  hlsl(stage) {
    #include "frustum_culling.hlsl"
    bool testSphereB(float3 center, float radius)
    {
      return baseTestSphereB(center, radius, frustumPlane03X, frustumPlane03Y, frustumPlane03Z, frustumPlane03W, frustumPlane4, frustumPlane5);
    }
    bool testBoxB(float3 minb, float3 maxb)
    {
      float3 center = 0.5*(maxb+minb);
      return baseTestBoxExtentB(center, maxb-center, frustumPlane03X, frustumPlane03Y, frustumPlane03Z, frustumPlane03W, frustumPlane4, frustumPlane5);
    }
    bool testBoxExtentB(float3 centerb, float3 extentb)
    {
      return baseTestBoxExtentB(centerb, extentb, frustumPlane03X, frustumPlane03Y, frustumPlane03Z, frustumPlane03W, frustumPlane4, frustumPlane5);
    }
  }
endmacro

macro INIT_AND_USE_FRUSTUM_CHECK_CS()
  INIT_AND_USE_FRUSTUM_CHECK_BASE(cs)
endmacro


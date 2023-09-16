include "shader_global.sh"
include "ssao_use.sh"
include "viewVecVS.sh"
include "monteCarlo.sh"

include "contact_shadows.sh"
include "gbuffer.sh"
include "get_additional_ao.sh"
include "get_additional_shadows.sh"
include "ssao_reprojection.sh"

int ssao_quality = 1;
interval ssao_quality:depth_only<1, ssao_normals<3, bnao;

int blur_quality = 0;
interval blur_quality:ok<1, good;


// SSAO tweaking parameters are:
float ssao_radius_factor = 64.0;                        // smaller - bigger radius ~32..512
float ssao_ambient_cutoff = 0.18;                        // cutoff angle factor  ~0.05..0.3
float4 ssao_blur_weights = (0.9, 0.75, 0.5, 0.25);      // weights for each blur distance
float   ssao_blur_depth_near = 0.05;                      // depth threshold up-close: meters
float   ssao_blur_depth_far = 0.002;                     // depth threshold at z-far: percentage of zfar!
float4 ssao_frame_no = (0,0,0,0);
texture ssao_prev_tex;
texture prev_downsampled_far_depth_tex;

//bnao
float sampleRadius = 0.075;
float4 globtm_no_ofs_psf_0;
float4 globtm_no_ofs_psf_1;
float4 globtm_no_ofs_psf_2;
float4 globtm_no_ofs_psf_3;
texture random_pattern_tex;
texture downsampled_normals;
texture downsampled_checkerboard_depth_tex;

hlsl(ps) {
  #define OUTPUT_CONE 0
  #if OUTPUT_CONE
  #define OUT_TYPE half4
  half4 encodeBNAO(half3 normal, half AO)
  {
    return half4(normal.xyz*0.5+0.5, AO);
  }
  half4 encodeBNAO(half4 bnao)
  {
    return encodeBNAO(bnao.xyz, bnao.w);
  }
  half4 decodeBNAO(half4 bnao_encoded)
  {
    return half4(bnao_encoded.xyz*2-1, bnao_encoded.w);
  }
  #else
  #define OUT_TYPE SSAO_TYPE
  #define encodeBNAO(ao) (ao)
  #define decodeBNAO(ao) (ao)
  #endif

  #define SHADER_OUT_TYPE OUT_TYPE
}

hlsl(ps) {
  #define BENT_CONES_PATTERN 3
  #define BENT_CONES_SAMPLES 8
  #define BENT_CONES_RAY_STEPS 2
}

float SSAO_effect = 0.95;
float SSAOZ = 2.0;
float SSAOW = 2.0;
float SSAOOFS = -0.075;

define_macro_if_not_defined APPLY_ADDITIONAL_AO(code)
  hlsl(code) {
    float getAdditionalAmbientOcclusion(float ssao, float3 worldPos, float3 worldNormal, float2 screenTc){return ssao;}
  }
endmacro

macro SS_BENT_CONES()
  (ps) {
    sampleRadius__invMaxDistance@f2 = (sampleRadius, 1.0 / (2.0*sampleRadius), 0, 0);
    downsampled_normals@smp2d = downsampled_normals;
    random_pattern_tex@smp2d = random_pattern_tex;
    bent_cones_frame_no@f2 = ssao_frame_no;
    SSAO_params@f4 = (SSAO_effect, SSAOOFS, SSAOZ, SSAOW);//???
  }

  //crytek
  hlsl(ps) {
    #define BENT_CONES_ON 1
    #if !BENT_CONES_ON
    #define CRYTEK_ON 1
    //requires change in pattern
    #endif
    float3 mirror( float3 vDir, float3 vPlane )
    {
      float3 reflected = vDir - 2 * vPlane * dot(vPlane,vDir);
      if (dot(reflected, vPlane) < 0)
        reflected=-reflected;
      return reflected;
    }
    half crytek_ao(float2 screenTC, int2 itexCoord, float fSceneDepthM, float3 wsPosition, float3 wsNormal)
    {
      // define kernel
      const half step = 1.f - 1.f/8.f;
      const half fScale = 0.025f;
      const half3 arrKernel[8] =
      {
        normalize(half3( 1, 1, 1))*fScale*(step),
        normalize(half3(-1,-1,-1))*fScale*(2 * step),
        normalize(half3(-1,-1, 1))*fScale*(3 * step),
        normalize(half3(-1, 1,-1))*fScale*(4 * step),
        normalize(half3(-1, 1 ,1))*fScale*(5 * step),
        normalize(half3( 1,-1,-1))*fScale*(6 * step),
        normalize(half3( 1,-1, 1))*fScale*(7 * step),
        normalize(half3( 1, 1,-1))*fScale*(8 * step),
      };

      int patternIndex = (itexCoord.x%BENT_CONES_PATTERN) + (itexCoord.y%BENT_CONES_PATTERN) * BENT_CONES_PATTERN;//fixme:optimize

      // create random rot matrix
      float3 rotSample = texelFetch(random_pattern_tex, int2(patternIndex, bent_cones_frame_no.y), 0).xyz;

      //half fSceneDepth = tex2D( sceneDepthSampler, screenTC.xy ).r;

      // range conversions
      //half fSceneDepthM = fSceneDepth * PS_NearFarClipDist.y;

      half3 vSampleScale = SSAO_params.zzw
        * saturate(fSceneDepthM / 5.3f) // make area smaller if distance less than 5 meters
        * (1.f + fSceneDepthM / 8.f ); // make area bigger if distance more than 32 meters

      float used_zfar = 1;//zn_zfar.y;
      float used_inv_zfar = 1;//rcp(used_zfar);
      float fDepthRangeScale = used_zfar * 0.85f*rcp(vSampleScale.z);

      // convert from meters into SS units
      vSampleScale.xy *= 1.0f / fSceneDepthM;
      vSampleScale.z  *= 2.0f*used_inv_zfar;// / zn_zfar.y;

      float fDepthTestSoftness = 64.f/vSampleScale.z;

      // sample
      half4 vSkyAccess = 0.f;
      half4 arrSceneDepth2[2];
      half3 vIrrSample;
      half4 vDistance;
      float4 fRangeIsInvalid;

      #define bHQ 0

      float fHQScale = 0.5f;
      half ao = 0;
      UNROLL
      for(int i=0; i<2; i++)
      {
        vIrrSample = mirror(arrKernel[i*4+0], rotSample) * vSampleScale;
        arrSceneDepth2[0].x = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        if (bHQ)
        {
          vIrrSample.xyz *= fHQScale;
          arrSceneDepth2[1].x = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        }

        vIrrSample = mirror(arrKernel[i*4+1], rotSample) * vSampleScale;
        arrSceneDepth2[0].y = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        if (bHQ)
        {
          vIrrSample.xyz *= fHQScale;
          arrSceneDepth2[1].y = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        }

        vIrrSample = mirror(arrKernel[i*4+2], rotSample) * vSampleScale;
        arrSceneDepth2[0].z = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        if (bHQ)
        {
          vIrrSample.xyz *= fHQScale;
          arrSceneDepth2[1].z = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        }

        vIrrSample = mirror(arrKernel[i*4+3], rotSample) * vSampleScale;
        arrSceneDepth2[0].w = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        if (bHQ)
        {
          vIrrSample.xyz *= fHQScale;
          arrSceneDepth2[1].w = linearize_z(tex2Dlod( downsampled_far_depth_tex, float4(screenTC.xy + vIrrSample.xy,0,0) ).r, zn_zfar.zw)*used_inv_zfar + vIrrSample.z;
        }

        float fDefVal = 0.7f;
        half4 weights = 1;

        UNROLL
        for(int s=0; s<(bHQ ? 2 : 1); s++)
        {
          vDistance = fSceneDepthM*used_inv_zfar - arrSceneDepth2[s];
          float4 vDistanceScaled = vDistance * fDepthRangeScale;
          fRangeIsInvalid = (saturate( abs(vDistanceScaled) ) + saturate( vDistanceScaled ))/2;
          vSkyAccess += lerp(saturate((-vDistance)*fDepthTestSoftness), fDefVal, fRangeIsInvalid);
        }
        //ao += dot(vSkyAccess, weights)*rcp(dot(weights,1));
        //vSkyAccess = 0;
      }
      //ao = ao + SSAO_params.y;

      ao = dot( vSkyAccess, (bHQ ? 1/16.0f : 1/8.0f)*2.0 ) + SSAO_params.y; // 0.075f

      return saturate(ao*ao);
    }
  }
  //end of


  hlsl(ps) {
    #define inSampleRadius (sampleRadius__invMaxDistance.x)
    #define inInvMaxDistance (sampleRadius__invMaxDistance.y)

    float checkSSVisibilitySmooth(
      float csPositionW,
      //const in float4x4 viewMatrix,
      float4x4 viewProjectionMatrixNoOfs,
      float3 wsCameraToPoint,
      float invOutlierDistance,
      float invOutlierDistanceW,
      float lod)
    {
      // transform world space sample to camera space
      //float3 csSample = (viewMatrix * float4(wsSample, 1.0)).xyz;

      // project to ndc and then to texture space to sample depth/position buffer to check for occlusion
      float4 ndcSamplePosition = mul(float4(wsCameraToPoint, 1.0), viewProjectionMatrixNoOfs);
      float csSampleZ = ndcSamplePosition.w;
      //if(ndcSamplePosition.w == 0.0) continue;
      ndcSamplePosition.xy *= rcp(ndcSamplePosition.w);
      float2 tsSamplePosition = ndcSamplePosition.xy * float2(0.5, -0.5) + float2(0.5,0.5);//todo: can be moved to viewProjectionMatrix

      // optimization: replace position buffer with depth buffer
      // here we get a world space position
      // we found the background...
      //float4 wsReferenceSamplePosition = texture(positionTexture, tsSamplePosition);
      float wsReferenceRawDepth = tex2Dlod(half_res_depth_tex, float4(tsSamplePosition,0,lod)).x;
      //float wsReferenceRawDepth = tex2Dlod(half_res_depth_tex, float4(sampleScreen,0,lod)).x;
      float wsReferenceSampleW  = linearize_z(wsReferenceRawDepth, zn_zfar.zw);
      //float3 wsReferenceSamplePosition = world_view_pos + viewVect*wsReferenceSampleW;
      // transform to camera space
      //float3 csReferenceSamplePosition = (viewMatrix * float4(wsReferenceSamplePosition.xyz, 1.0)).xyz;

      //////////////////////////////////////////////////////////////////////////
      // optional: apply some code to handle background
      //////////////////////////////////////////////////////////////////////////

      // check for occlusion (within camera space, simple test along z axis; remember z axis goes along -z in OpenGL!)
      // optimized code checks depth values
      // could apply small depth bias here to avoid precision errors
      return (wsReferenceSampleW < csSampleZ) ? saturate(pow2(invOutlierDistance - wsReferenceSampleW*invOutlierDistanceW)) : 1;
      //return (wsReferenceSampleW < csSampleZ) ? 0 : 1;
      //return saturate(pow2(invOutlierDistance - wsReferenceSampleW*invOutlierDistanceW));
    }

    void checkSSVisibilityWithRayMarchingSmooth(
      float csPositionW,
      //const in float4x4 viewMatrix,
      float4x4 viewProjectionMatrixNoOfs,
      float3 wsCameraToPoint, float invOutlierDistance, float invOutlierDistanceW,
      float3 ray, float sampleRadius,
      float rayMarchingStartOffset,
      inout float visibility, float lodOfs)
    {
      UNROLL
      for(int k=0; k<BENT_CONES_RAY_STEPS; k++) {
        // world space sample radius within we check for occluders (larger radius needs more ray marching steps)
        float3 wsSample = wsCameraToPoint + ray * (sampleRadius * (float(k) * float(1.0f/BENT_CONES_RAY_STEPS) + rayMarchingStartOffset));
        visibility *= checkSSVisibilitySmooth(
          csPositionW,
          viewProjectionMatrixNoOfs,
          wsSample, invOutlierDistance, invOutlierDistanceW,
            k+lodOfs);
      }
    }

    void calcBentNormals(float2 texcoord, int2 itexCoord, float3 wsPosition, float3 wsNormal, float w, float4x4 viewProjectionMatrixNoOfs, out OUT_TYPE outBNAO)
    {
      outBNAO = 1;

      //////////////////////////////////////////////////////////////////////////
      // ws = world space
      // cs = camera space
      // ndc = normal device coordinates
      // ts = texture space
      //////////////////////////////////////////////////////////////////////////
      // background
      //float3 csPosition = (viewMatrix * float4(wsPosition.xyz, 1.0)).xyz;
      //float3 wsNormal = texelFetch(normalTexture, itexCoord, 0).rgb;
      //float3 wsNormal = decodeNormal(tex2Dlod(normal_gbuf, float4(texcoord,0,0)).xyz*2-1);// instead, use correct normal, from most farthest pixel

      float ao = 0.0;
      float3 bentNormal = 0.0;
      float visibilityRays = 0.0;

      // get a different set of samples, depending on pixel position in pattern
      //int patternIndex = itexCoord.x + itexCoord.y * BENT_CONES_PATTERN;
      int patternIndex = (itexCoord.x + itexCoord.y * BENT_CONES_PATTERN+int(bent_cones_frame_no.x))%(BENT_CONES_PATTERN*BENT_CONES_PATTERN);//fixme:optimize

      //patternIndex = 0;
      float inInvMaxDistanceW = inInvMaxDistance * rcp(w);
      float weight = 0;
      UNROLL
      for (int i=0; i<BENT_CONES_SAMPLES; i++)
      {
        //////////////////////////////////////////////////////////////////////////
        // seed texture holds samples
        // y selects pattern
        // x coordinate gives samples from set
        //float4 data = random_pattern[patternIndex][i];
        float4 data = texelFetch(random_pattern_tex, int2(patternIndex, i), 0);
        //float4 data = random_pattern[patternIndex*BENT_CONES_SAMPLES + i];
        //float4 data = texelFetch(seedTexture, int2(i, patternIndex), 0);
        float rayMarchingStartOffset = data.a;
        //float3 ray = data.rbg;
        float3 ray = tangent_to_world( data.xyz, wsNormal);
        //float3 ray = data.rgb;
        //float3 ray = data.x*u + data.y*v + data.z*w;
        // bring it to the local hemisphere
        // we do not need a ONB, because we have a uniform distribution
        // simple inversion is ok
        //FLATTEN
        //if(dot(ray, wsNormal) < 0.0)
        //  ray = -ray;
        //////////////////////////////////////////////////////////////////////////
        // perform ray marching along the direction
        float visibility = 1.0;
        // if the occluder is too far away, we cannot count the sample
        // screen-space limitation, which could be reduced by depth peeling or scene voxelization

        checkSSVisibilityWithRayMarchingSmooth(
          w,
          viewProjectionMatrixNoOfs,
          wsPosition.xyz, inInvMaxDistance, inInvMaxDistanceW,
          ray, inSampleRadius*w, rayMarchingStartOffset,
          visibility, i>BENT_CONES_SAMPLES/2 ? 1 : 1);
        //////////////////////////////////////////////////////////////////////////


        // evaluate the ray marching steps
        // visibility encodes how much this direction is occluded
        // one could also do that binary, but that may cause artifacts, when visibilty is checked in SS

        // note: we assume no occlusion if the occluder is too far away
        // for bent normals we cannot simply "skip" these directions
        #if OUTPUT_CONE
        bentNormal += ray * visibility;
        visibilityRays += visibility;
        #endif

        ao += visibility;
      }

      float resultAO = ao * rcp((float)BENT_CONES_SAMPLES);
      //float resultAO = ao * rcp(weight);
      #if OUTPUT_CONE
      half3 resultNormal = 0;
      FLATTEN
      if (dot(bentNormal, 1) != 0.0) {
        bentNormal *= rcp(visibilityRays);
        resultNormal.xyz = bentNormal-wsNormal;
        //resultNormal.xyz = clamp(bentNormal-wsNormal,-1,1);//outBNAO.xyz = encodeNormal(bentNormal-wsNormal);
      }
      outBNAO = encodeBNAO(resultNormal, resultAO);
      outBNAO.w*=outBNAO.w;
      #else
      outBNAO = resultAO*resultAO;
      #endif
    }
  }
endmacro

float g_scale = 4;
macro INIT_AWESOME_SSAO_PARAMS()
  (ps) {
    depth_rescale@f4 = (1 / zn_zfar.y, 0, zn_zfar.x, zn_zfar.y);
    ssao_pixel_size@f2 = ( 1./(lowres_rt_params.x), 1./(lowres_rt_params.y), 0.0, 0.0 );
    ssao_radius@f4 = ( lowres_rt_params.x/ssao_radius_factor, 1.0/ssao_radius_factor, lowres_rt_params.x/(lowres_rt_params.y*ssao_radius_factor), lowres_rt_params.y/lowres_rt_params.x );
    ssao_ambient_inv_cutoff@f1 = (1.0 / ssao_ambient_cutoff, 0, 0, 0);
    downsampled_normals@smp2d = downsampled_normals;
    g_scale@f1 = (g_scale,0,0,0);
  }
endmacro

macro INIT_ALCHEMY_AO()
hlsl(ps) {
  #define g_SSAOPhase (ssao_frame_no.x%1024)

  /*
  Source of whole algorithm: http://graphics.cs.williams.edu/papers/SAOHPG12/ plus some minor modifications (right now I removed mips)

  Source licence:
  \author Morgan McGuire and Michael Mara, NVIDIA Research

  Reference implementation of the Scalable Ambient Obscurance (SAO) screen-space ambient obscurance algorithm.

  The optimized algorithmic structure of SAO was published in McGuire, Mara, and Luebke, Scalable Ambient Obscurance,
  <i>HPG</i> 2012, and was developed at NVIDIA with support from Louis Bavoil.

  The mathematical ideas of AlchemyAO were first described in McGuire, Osman, Bukowski, and Hennessy, The
  Alchemy Screen-Space Ambient Obscurance Algorithm, <i>HPG</i> 2011 and were developed at
  Vicarious Visions.

  DX11 HLSL port by Leonardo Zide of Treyarch

  <hr>

  Open Source under the "BSD" license: http://www.opensource.org/licenses/bsd-license.php

  Copyright (c) 2011-2012, NVIDIA
  All rights reserved.

  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


  */

  #define NUM_SAMPLES (8)

  static const int ROTATIONS[] = { 1, 1, 2, 3, 2, 5, 2, 3, 2,
  3, 3, 5, 5, 3, 4, 7, 5, 5, 7,
  9, 8, 5, 5, 7, 7, 7, 8, 5, 8,
  11, 12, 7, 10, 13, 8, 11, 8, 7, 14,
  11, 11, 13, 12, 13, 19, 17, 13, 11, 18,
  19, 11, 11, 14, 17, 21, 15, 16, 17, 18,
  13, 17, 11, 17, 19, 18, 25, 18, 19, 19,
  29, 21, 19, 27, 31, 29, 21, 18, 17, 29,
  31, 31, 23, 18, 25, 26, 25, 23, 19, 34,
  19, 27, 21, 25, 39, 29, 17, 21, 27 };

  /** Used for preventing AO computation on the sky (at infinite depth) and defining the CS Z to bilateral depth key scaling.
  This need not match the real far plane*/
  //#define FAR_PLANE_Z (90.0)

  // This is the number of turns around the circle that the spiral pattern makes.  This should be prime to prevent
  // taps from lining up.  This particular choice was tuned for NUM_SAMPLES == 9
  static const int NUM_SPIRAL_TURNS = ROTATIONS[NUM_SAMPLES-1];

  /** World-space AO radius in scene units (r).  e.g., 1.0m */
  static const float radius = 0.7;
  /** radius*radius*/
  static const float radius2 = (radius*radius);

  /** Bias to avoid AO in smooth corners, e.g., 0.01m */
  static const float bias = 0.02f;

  /** The height in pixels of a 1m object if viewed from 1m away.
  You can compute it from your projection matrix.  The actual value is just
  a scale factor on radius; you can simply hardcode this to a constant (~500)
  and make your radius value unitless (...but resolution dependent.)  */
  static const float projScale = 500.0f;

  /** Reconstruct camera-space P.xyz from screen-space S = (x, y) in
  pixels and camera-space z < 0.  Assumes that the upper-left pixel center
  is at (0.5, 0.5) [but that need not be the location at which the sample tap
  was placed!]
  */

  /** Reconstructs screen-space unit normal from screen-space position */
  float3 reconstructCSFaceNormal(float3 C)
  {
    return normalize(cross(ddy_fine(C), ddx_fine(C)));
  }

  /** Returns a unit vector and a screen-space radius for the tap on a unit disk (the caller should scale by the actual disk radius) */
  float2 tapLocation(int sampleNumber, float spinAngle, out float ssR)
  {
    // Radius relative to ssR
    float alpha = float(sampleNumber + 0.5) * (1.0 / NUM_SAMPLES);
    float angle = alpha * (NUM_SPIRAL_TURNS * 6.28) + spinAngle;

    ssR = alpha;
    float sin_v, cos_v;
    sincos(angle, sin_v, cos_v);
    return float2(cos_v, sin_v);
  }
  float3 getPosition(float2 curViewTc, float depth)
  {
    return depth*lerp(lerp(view_vecLT, view_vecRT, curViewTc.x), lerp(view_vecLB, view_vecRB, curViewTc.x), curViewTc.y);
  }

  float3 getOffsetPosition(float2 tc, float2 unitOffset, float ssR)
  {
    float2 curTc = tc+unitOffset*ssR*ssao_pixel_size.xy;
    return getPosition(curTc, RetrieveDepth(curTc, 0));
  }


  /** Compute the occlusion due to sample with index \a i about the pixel at \a ssC that corresponds
  to camera-space point \a C with unit normal \a n_C, using maximum screen-space sampling radius \a ssDiskRadius */
  float sampleAO(in float invPos, in float2 vpos, in int2 ssC, in float3 C, in float3 n_C, in float ssDiskRadius, in int tapIndex, in float randomPatternRotationAngle)
  {
    // Offset on the unit disk, spun for this pixel
    float ssR;
    float2 unitOffset = tapLocation(tapIndex, randomPatternRotationAngle, ssR);
    ssR *= ssDiskRadius;

    // The occluding point in camera space
    float3 Q = getOffsetPosition(vpos, unitOffset, ssR);//getOffsetPosition(ssC, unitOffset, ssR);

    /*{
    float3 diff = Q - C;
    float diffLen2 = dot(diff,diff);
    float invDiffLen = rsqrt(diffLen2);
    float3 v = diff*invDiffLen;
    float d = rcp(invDiffLen)*invPos*g_scale;
    half ao = saturate(dot(n_C, v))*(1.0/(1.0+pow2(d)));
    return 1-pow2(1-ao);
    }*/

    float3 v = Q - C;

    float vv = dot(v, v);
    float vn = dot(v, n_C);

    const float epsilon = 0.02f;
    float f = max(radius2 - vv, 0.0);
    return f * f * f * max((vn - bias) * rcp(epsilon + vv), 0.0);
  }

  float def_SSAO(int2 ssC, float depth, float2 vPos, float3 cameraToPoint, float3 normalsWS)
  {
    float invDepth = rcp(depth);

    // Pixel being shaded

    float2 output = float2(1,1);

    // World space point being shaded
    float3 C = cameraToPoint;

    output.g = C.z;

    // Hash function used in the HPG12 AlchemyAO paper
    float randomPatternRotationAngle = (3 * ssC.x ^ ssC.y + ssC.x * ssC.y) * 10 + g_SSAOPhase;

    // Choose the screen-space sample radius
    float ssDiskRadius = projScale * radius *invDepth;

    float sum = 0.0;

    UNROLL
    for (int i = 0; i < NUM_SAMPLES; ++i)
    {
         sum += sampleAO(invDepth, vPos, ssC, C, normalsWS, ssDiskRadius, i, randomPatternRotationAngle);
    }
    //return 1-sum/NUM_SAMPLES;

    const float temp = radius2 * radius;
    sum /= temp * temp;

    float A = max(0.0f, 1.0f - sum * 1.0f * (4.0f / NUM_SAMPLES));
    //return A;

    // bilat filter 1-pixel wide for "free"
    if (abs(ddx_fine(depth)) < 0.2f)
    {
      A -= ddx_fine(A) * ((ssC.x & 1) - 0.5);
      A -= ddy_fine(A) * ((ssC.y & 1) - 0.5);
    }
    //output.r = lerp(A, 1.0f, 1.0f - saturate(0.5f * C.z)); // this algorithm has problems with near surfaces... lerp it out smoothly
    //float difference = saturate(1.0f - 5 * abs(C.z - keyPrevFrame));
    //output.r = lerp(output.r, aoPrevFrame, 0.95f*difference);

    return A;
  }
}
endmacro

macro USE_AWESOME_SSAO()
  hlsl(ps) {
    static const uint SAMPLE_NUM = 4;
    static const uint FRAMES_NUM = 8;

    //fixme: move to constant buffer! otherwise it is suboptimal!
    static const float2 POISSON_SAMPLES[SAMPLE_NUM*FRAMES_NUM] =
    {
      float2( 0.337219344255f, 0.57229881707f ),
      float2( -0.573982177743f, -0.799635574054f ),
      float2( 0.679255251604f, -0.65997901429f ),
      float2( -0.892186823575f, 0.404959480819f ),

      float2( 0.816424053179f, -0.548170142661f ),
      float2( -0.833925266583f, 0.545581110136f ),
      float2( -0.525005773899f, -0.805277049262f ),
      float2( 0.324521580535f, 0.785584251486f ),

      float2( -0.365103620512f, -0.871708293801f ),
      float2( 0.30268865232f, 0.924430192218f ),
      float2( 0.919585398916f, -0.258148956848f ),
      float2( -0.878812342437f, 0.332246828123f ),

      float2( -0.679374536212f, -0.663335212756f ),
      float2( 0.704181074766f, 0.648385817291f ),
      float2( -0.675304741649f, 0.657206995364f ),
      float2( 0.730600839551f, -0.615268393278f ),

      float2( 0.882880032571f, -0.252055365939f ),
      float2( -0.815902405519f, 0.279264733888f ),
      float2( -0.209182819347f, -0.808498547699f ),
      float2( 0.359405243809f, 0.921547588839f ),

      float2( -0.058305608623f, 0.907915085075f ),
      float2( -0.156033484238f, -0.977887612536f ),
      float2( 0.98067075742f, 0.0142957188351f ),
      float2( -0.982131816966f, 0.05922295699f ),

      float2( 0.485243100439f, 0.43545130271f ),
      float2( -0.77682740988f, -0.587696460901f ),
      float2( 0.429579595122f, -0.894642710457f ),
      float2( -0.720340535983f, 0.641385073215f ),

      float2( 0.574746847182f, -0.673570114093f ),
      float2( -0.384732521594f, 0.908689777207f ),
      float2( -0.725552751165f, -0.57621829525f ),
      float2( 0.831738405676f, 0.549035049699f ),
    };
    // 1d-noise
    float rand(float2 co)
    {
        return frac(sin(dot(co.xy ,float2(12.9898,78.233))) * 43758.5453);
    }

    // 4d-noise
    float4 rand4(float2 co)
    {
        return float4(
                    rand(co),
                    rand(co+float2(1,0)),
                    rand(co+float2(0,1)),
                    rand(co+float2(1,1))
                    );
    }
    ##if (ssao_quality == ssao_normals)
    float3 getPosition(float2 curViewTc, float depth)
    {
      return depth * lerp(
        lerp(view_vecLT, view_vecRT, curViewTc.x),
        lerp(view_vecLB, view_vecRB, curViewTc.x),
        curViewTc.y);
    }
    half getSSDO(float2 tc, float lod, float invPos, float3 wsPos, float3 wsNormal)
    {
      float3 diff = getPosition(tc, RetrieveDepth(tc, lod)) - wsPos;
      float diffLen2 = dot(diff,diff);
      float invDiffLen = rsqrt(diffLen2);
      float3 v = diff*invDiffLen;
      //float d = rcp(invDiffLen)*invPos*g_scale;
      float bias = 0.5;
      half ao = saturate(dot(wsNormal,v)*rcp(bias+diffLen2*pow2(invPos*g_scale)));
      //half ao = saturate(dot(wsNormal,v)*(1.0/(1.0+pow2(d))));
      //half ao = saturate(dot(wsNormal,v));
      return ao;
      //return 1-pow2(1-ao);
    }
    ##endif
    half GetOcclusion ( float pos, float invPos, float2 coord, float2 dudv, float lod, float3 wsPos, float3 wsNormal )
    {
      ##if (ssao_quality == ssao_normals)
        return getSSDO(coord + dudv,lod, invPos, wsPos, wsNormal)+getSSDO(coord - dudv, lod, invPos, wsPos, wsNormal);
      ##else
        float pPos = RetrieveDepth(coord + dudv, lod);
        float SSnorm = RetrieveDepth(coord - dudv, lod);
        float sample1 = (pos*rcp(pPos)) - (SSnorm*invPos);
        // 1-(2*x/CUTOFF-1)^2
        float sample2 = 2.0*(sample1*ssao_ambient_inv_cutoff)-1.0;
        sample1 =  saturate ( 1.0 - sample2*sample2 );
        return (sample1*rsqrt ( sample1 + 0.000000001));
      ##endif
    }

    static const float NUM_SPIRAL_TURNS = 1.f;
    static const int NUM_SAMPLES = 4;
    float2 tapLocation(float alpha, float spinAngle)
    {
      float angle = alpha * (NUM_SPIRAL_TURNS * 6.28f) + spinAngle;

      float sin_v, cos_v;
      sincos(angle, sin_v, cos_v);
      return float2(cos_v, sin_v)*(alpha*2);
    }

    half def_SSAO ( int2 ssC, float pos, float2 coord, float3 cameraToPoint, float3 wsNormal )
    {
      float invPos = rcp(pos);

      half occlusion = 0.0;
      //uint frameRandom = uint(ssr_frameNo.y);
      ///*
      #define POISSON 1
      #if POISSON == 1

      uint baseId = ((ssao_frame_no.x%1024) + float(ssC.x)*1213 + float(ssC.y) * 1217)%FRAMES_NUM;
      baseId*=SAMPLE_NUM;
      float2 uv1 = POISSON_SAMPLES[baseId] * ssao_radius.yz;
      float2 uv2 = POISSON_SAMPLES[baseId+0] * ssao_radius.yz;
      float2 uv3 = POISSON_SAMPLES[baseId+1] * ssao_radius.yz;
      float2 uv4 = POISSON_SAMPLES[baseId+2] * ssao_radius.yz;
      #elif POISSON == 2

    // Hash function used in the HPG12 AlchemyAO paper
      float spinAngle = ((3 * ssC.x ^ ssC.y + ssC.x * ssC.y) * 10 + ssao_frame_no.x*0.51);
      //spin = ssao_frame_no.y;
      float2 uv1 = tapLocation(0.125, spinAngle) * ssao_radius.yz;
      float2 uv2 = tapLocation(0.375, spinAngle) * ssao_radius.yz;
      float2 uv3 = tapLocation(0.625, spinAngle) * ssao_radius.yz;
      float2 uv4 = tapLocation(0.875, spinAngle) * ssao_radius.yz;
      #else

      float  frameRandom = ssao_frame_no.y;
      float4 randcoord4 = rand4(coord+frameRandom);
      float4 noise0 = randcoord4 * 3.0 - 1.5;
      float2 uv1 = noise0.xy * ssao_radius.yz;
      float2 uv2 = noise0.yz * ssao_radius.yz;
      float2 uv3 = noise0.zw * ssao_radius.yz;
      float2 uv4 = noise0.wx * ssao_radius.yz;
      #endif

      /*/
      uint seed = rand_seed(coord);
      float2 uv1 = GetDuDv(seed);
      float2 uv2 = GetDuDv(seed);
      float2 uv3 = GetDuDv(seed);
      float2 uv4 = GetDuDv(seed);
      //*/
      occlusion  = GetOcclusion ( pos, invPos, coord, uv1, 0, cameraToPoint, wsNormal );
      occlusion += GetOcclusion ( pos, invPos, coord, uv2, 0, cameraToPoint, wsNormal );
      occlusion += GetOcclusion ( pos, invPos, coord, uv3, 0, cameraToPoint, wsNormal );
      occlusion += GetOcclusion ( pos, invPos, coord, uv4, 0, cameraToPoint, wsNormal );
      /*##if ssao_quality==awesome// || ssao_quality!=awesome
      {
        frameRandom = ssao_frame_no.w;
        randcoord4 = rand4(coord+frameRandom);
        float4 noise0 = randcoord4 * 6.0 - 3;
        float2 uv1 = noise0.xy * ssao_radius.yz;
        float2 uv2 = noise0.yz * ssao_radius.yz;
        float2 uv3 = noise0.zw * ssao_radius.yz;
        float2 uv4 = noise0.wx * ssao_radius.yz;
        occlusion += GetOcclusion ( pos, invPos, coord, uv1, 1, cameraWorldPos, wsNormal );
        occlusion += GetOcclusion ( pos, invPos, coord, uv2, 1, cameraWorldPos, wsNormal );
        occlusion += GetOcclusion ( pos, invPos, coord, uv3, 1, cameraWorldPos, wsNormal );
        occlusion += GetOcclusion ( pos, invPos, coord, uv4, 1, cameraWorldPos, wsNormal );
        occlusion *= 0.125;
      }
        occlusion *= 0.125;
      ##endif
      */

      ##if ssao_quality==ssao_normals
        occlusion *= 0.125;
        return pow2(saturate(1-occlusion));
      ##endif

      ##if ssao_quality==depth_only
        occlusion *= 0.25;
      ##endif
      occlusion = saturate(1-occlusion);
      ##if hardware.fsh_5_0
      if (abs(ddx_fine(pos)) < 0.2f)
      {
        occlusion -= ddx_fine(occlusion) * ((ssC.x & 1) - 0.5);
        occlusion -= ddy_fine(occlusion) * ((ssC.y & 1) - 0.5);
      }
      ##endif

      return occlusion;
    }
 }
endmacro

shader ssao
{
  (ps) {
    world_view_pos@f3 = world_view_pos;
    lowres_rt_params@f4 = lowres_rt_params;
    viewProjectionMatrixNoOfs@f44 = { globtm_no_ofs_psf_0, globtm_no_ofs_psf_1, globtm_no_ofs_psf_2, globtm_no_ofs_psf_3 };
    ssao_frame_no@f4 = ssao_frame_no;
    downsampled_far_depth_tex@smp2d = downsampled_far_depth_tex;
    half_res_depth_tex@smp2d = downsampled_checkerboard_depth_tex;
    screen_pos_to_texcoord@f2 = screen_pos_to_texcoord;
    from_sun_direction@f3 = from_sun_direction;
    shadow_params@f3 = (0, shadow_frame, contact_shadow_len, 0);
    depth_gbuf@smp2d = depth_gbuf;
  }
  INIT_ZNZFAR()
  hlsl(ps) {
    float RetrieveDepth ( float2 tc, float lod )
    {
      return linearize_z(tex2Dlod(downsampled_far_depth_tex, float4(tc,0,lod)).x, zn_zfar.zw);
    }
  }

  if (ssao_quality == bnao)
  {
    SS_BENT_CONES()
    USE_AND_INIT_VIEW_VEC_PS()
  } else
  {
    if (ssao_quality == ssao_normals)
    {
      (ps) {
        view_vecLT@f3=view_vecLT;
        view_vecRT@f3=view_vecRT;
        view_vecLB@f3=view_vecLB;
        view_vecRB@f3=view_vecRB;
      }
    } else
    {
      USE_AND_INIT_VIEW_VEC_PS()
    }
    INIT_AWESOME_SSAO_PARAMS()
    USE_AWESOME_SSAO()//0.45 of bent cones AO
    //INIT_ALCHEMY_AO()
  }
  USE_AND_INIT_VIEW_VEC_VS()

  cull_mode=none;
  z_write=false;
  z_test=false;

  POSTFX_VS_TEXCOORD_VIEWVEC(0, tc, viewVect)

  SSAO_REPROJECTION(ps, ssao_prev_tex)

  hlsl(ps) {
    #define csm_distance shadow_params.x
    #define shadow_frame shadow_params.y
    #define contact_shadow_len shadow_params.z
  }

  CONTACT_SHADOWS()
  APPLY_ADDITIONAL_AO(ps)
  APPLY_ADDITIONAL_SHADOWS(ps)


  hlsl(ps) {
    //#undef BENT_CONES_ON

    /*float solidAngle(float3 v, float d2, float3 receiverNormal,
                     float3 emitterNormal, float emitterArea)
    {
      float result = emitterArea
        * saturate(dot(emitterNormal, -v))
        * saturate(dot(receiverNormal, v))
        / (d2 + emitterArea );
      return result;
    } // end solidAngle()

    float solidAngle2side(float3 v, float d2, float3 receiverNormal,
                     float3 emitterNormal, float emitterArea)
    {
      float result = emitterArea
        * abs(dot(emitterNormal, -v))
        * saturate(dot(receiverNormal, v))
        / (d2 + emitterArea );
      return result;
    } // end solidAngle()*/

    SHADER_OUT_TYPE SSAO_ps(VsOutput IN HW_USE_SCREEN_POS) : SV_Target
    {
      float4 scrpos = GET_SCREEN_POS(IN.pos);
      float2 screenTC = IN.tc.xy;
      float rawDepth = tex2Dlod(downsampled_far_depth_tex, float4(screenTC,0,0)).x;
      float depth1 = linearize_z(rawDepth, zn_zfar.zw);
      BRANCH
      if (depth1 >= zn_zfar.y*0.99)
        return 1;

      //float2 viewScreenTC = (scrpos.xy*2)*screen_pos_to_texcoord;
      //float3 cameraWorldPos = lerp(lerp(view_vecLT,view_vecRT, viewScreenTC.x),lerp(view_vecLB,view_vecRB, viewScreenTC.x), viewScreenTC.y) * depth1;
      //actually: this will work ONLY for even screen resolutions
      float3 cameraToPoint = IN.viewVect * depth1;
      SSAO_TYPE ssao = (SSAO_TYPE)1;
      ##if (ssao_quality != depth_only)
        float3 wsNormal = tex2Dlod(downsampled_normals, float4(screenTC,0,0)).xyz*2-1;
        #if BENT_CONES_ON
        calcBentNormals(screenTC, int2(screenTC*lowres_rt_params.xy), cameraToPoint, wsNormal, depth1, viewProjectionMatrixNoOfs, ssao);
        #elif CRYTEK_ON
        ssao.x = crytek_ao(screenTC, int2(screenTC*lowres_rt_params.xy), depth1, cameraToPoint, wsNormal);
        #else
        ssao.x = def_SSAO(scrpos.xy, depth1, screenTC, cameraToPoint, wsNormal).x;
        #endif
        ssao.x = getAdditionalAmbientOcclusion(ssao.x, world_view_pos + cameraToPoint, wsNormal, screenTC);
      ##else
        ssao.x = def_SSAO(scrpos.xy, depth1, screenTC, cameraToPoint, 0).x;
        ssao.x = getAdditionalAmbientOcclusion(ssao.x, world_view_pos + cameraToPoint, normalize(cross(ddx(cameraToPoint), ddy(cameraToPoint))), screenTC);
      ##endif

      //BRANCH
      //if (shadow>0.01)
      #if SSAO_CONTACT_SHADOWS
      {
        float2 screenpos = scrpos.xy;
        float3 viewVect = IN.viewVect;
        float w = depth1;

        float dither = interleavedGradientNoiseFramed(screenpos, floor(shadow_frame));//if we have temporal aa
        dither = interleavedGradientNoise(screenpos);
        //dither = 0.5;
        float2 hitUV;
        float offset = 0.0001;
        ##if (ssao_quality != depth_only)
          float sunNdotL = dot(wsNormal, from_sun_direction);
          float sunNoL = abs(sunNdotL);
          offset = lerp(0.05, 0.0001, sunNoL);
        ##else
          float sunNdotL = 0.25;
          float3 wsNormal = 0;
        ##endif
        ssao.y = contactShadowRayCast(downsampled_far_depth_tex, downsampled_far_depth_tex_samplerstate, cameraToPoint - normalize(viewVect)*(w*offset+0.005), -from_sun_direction, w*contact_shadow_len, 20, dither-0.5, projectionMatrix, w, viewProjectionMatrixNoOfs, hitUV, float2(100, 99));
        ssao.x *= lerp(ssao.y*0.2+0.8, 1, saturate(sunNdotL*2));//assume that sky is brighter towards the sun
        //ssao.y = contactShadowRayCast(depth_gbuf, depth_gbuf_samplerstate, cameraToPoint-normalize(viewVect)*(w*0.0001+0.005), -from_sun_direction, w*contact_shadow_len, 20, dither-0.5, projectionMatrix, float3(screenTC.xy, rawDepth), w, viewProjectionMatrix, hitUV, float2(100, 99));
        ssao.y = getAdditionalShadow(ssao.y, cameraToPoint, wsNormal);
      }
      #endif

      reproject_ssao(ssao, cameraToPoint, screenTC, depth1);

      return ssao;
    }
  }

  compile("target_ps", "SSAO_ps");
}



shader ssao_blur
{

  cull_mode=none;
  z_write=false;

  (ps) {
    srcTex@smp2d = ssao_tex;
    depth_rescale@f4 = (1 / zn_zfar.y, -10 / zn_zfar.y, zn_zfar.x, zn_zfar.y);
    ssao_blur_depth_cutoff@f2 = (ssao_blur_depth_near, ssao_blur_depth_far*zn_zfar.y, 0, 0);
    ssao_blur_weights_1234@f4 = ssao_blur_weights;
    half_res_depth_tex@smp2d = downsampled_checkerboard_depth_tex;
  }

  dynamic float4 texelOffset;
  dynamic int ssaoBlurVertical;// 0 - horizontal, 1- vertical
  interval ssaoBlurVertical: horizontal < 1, vertical;
  (vs) { texelOffset@f4 = texelOffset; }

  if (ssaoBlurVertical == horizontal)
  {
    (ps) { offset0@f4 = (texelOffset.z, 2*texelOffset.z, 3*texelOffset.z, 4*texelOffset.z); }
  } else
  {
    (ps) { offset0@f4 = (texelOffset.w, 2*texelOffset.w, 3*texelOffset.w, 4*texelOffset.w); }
  }
  hlsl(ps) {
    ##if ssaoBlurVertical == horizontal
      #define OFFSET_1 float2(offset0.x,0)
      #define OFFSET_2 float2(offset0.y,0)
      #define OFFSET_3 float2(offset0.z,0)
    ##else
      #define OFFSET_1 float2(0,offset0.x)
      #define OFFSET_2 float2(0,offset0.y)
      #define OFFSET_3 float2(0,offset0.z)
    ##endif
  }


  hlsl {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      float2 texcoord        : TEXCOORD0;
    };
  }
  USE_POSTFX_VERTEX_POSITIONS()

  hlsl(vs) {
    VsOutput ssao_blur_vs(uint vertex_id : SV_VertexID)
    {
      VsOutput output;
      float2 pos = getPostfxVertexPositionById(vertex_id);
      output.pos = float4(pos.x, pos.y, 0, 1);
      output.texcoord = pos*RT_SCALE_HALF+texelOffset.xy;
      return output;
    }
  }

  INIT_ZNZFAR()
  hlsl(ps) {
    #define RetrieveDepth(tc) linearize_z(tex2Dlod(half_res_depth_tex, float4(tc,0,0)).x, zn_zfar.zw)
    #define RetrieveDepthOffset(tc, ofs) linearize_z(tex2Dlod(half_res_depth_tex, float4(tc+ofs,0,0)).x, zn_zfar.zw)
    #define RetrieveSSAO(tc) (tex2Dlod(srcTex, float4(tc,0,0)). SSAO_ATTRS)
    #define RetrieveSSAOOffset(tc, ofs) (tex2Dlod(srcTex, float4(tc+ofs,0,0)). SSAO_ATTRS)
    SSAO_TYPE DepthBlurGaussian(float2 texcoord)
    {
        float dCur = RetrieveDepth(texcoord);

        float nZ = saturate(dCur*depth_rescale.x + depth_rescale.y);
        float depthThreshold = lerp(ssao_blur_depth_cutoff.x, ssao_blur_depth_cutoff.y, sqrt(nZ));
        float depthThresholdInv = 1.0 / depthThreshold;

        // start with current sample at weight 1
        SSAO_TYPE color = RetrieveSSAO(texcoord);
        half counter = 1.0;

        // looks like the compiler does not unroll loops by hand
        // as soon as they exceed certain length

        // 1
        float d_m2 = RetrieveDepthOffset(texcoord, -OFFSET_2);
        float d_m1 = RetrieveDepthOffset(texcoord, -OFFSET_1);
        float d_p1 = RetrieveDepthOffset(texcoord, OFFSET_1);
        float d_p2 = RetrieveDepthOffset(texcoord, OFFSET_2);

        SSAO_TYPE c_m2 = RetrieveSSAOOffset(texcoord, -OFFSET_2);
        SSAO_TYPE c_m1 = RetrieveSSAOOffset(texcoord, -OFFSET_1);
        SSAO_TYPE c_p1 = RetrieveSSAOOffset(texcoord, OFFSET_1);
        SSAO_TYPE c_p2 = RetrieveSSAOOffset(texcoord, OFFSET_2);
        {
            half weight1 = ssao_blur_weights_1234.x - saturate(abs(dCur - d_p1)*depthThresholdInv)*ssao_blur_weights_1234.x;
            half weight2 = ssao_blur_weights_1234.x - saturate(abs(dCur - d_m1)*depthThresholdInv)*ssao_blur_weights_1234.x;
            color += c_p1*weight1;
            color += c_m1*weight2;
            counter += weight1 + weight2;
        }
        // 2
        {
            half weight1 = ssao_blur_weights_1234.y - saturate(abs(dCur - d_p2)*depthThresholdInv)*ssao_blur_weights_1234.y;
            half weight2 = ssao_blur_weights_1234.y - saturate(abs(dCur - d_m2)*depthThresholdInv)*ssao_blur_weights_1234.y;
            color += c_p2*weight1;
            color += c_m2*weight2;
            counter += weight1 + weight2;
        }
        ##if blur_quality==good
        // 3
        {
            float d2 = RetrieveDepthOffset(texcoord, -OFFSET_3);
            float d1 = RetrieveDepthOffset(texcoord, OFFSET_3);
            SSAO_TYPE c2 = RetrieveSSAOOffset(texcoord, -OFFSET_3);
            SSAO_TYPE c1 = RetrieveSSAOOffset(texcoord, OFFSET_3);
            half weight1 = ssao_blur_weights_1234.z - saturate(abs(dCur - d1)*depthThresholdInv)*ssao_blur_weights_1234.z;
            half weight2 = ssao_blur_weights_1234.z - saturate(abs(dCur - d2)*depthThresholdInv)*ssao_blur_weights_1234.z;
            color += c1*weight1;
            color += c2*weight2;
            counter += weight1 + weight2;
        }
        ##endif
        color *= rcp(counter);
        return color;
    }

    OUT_TYPE ssao_blur_ps(VsOutput IN): SV_Target
    {
      return DepthBlurGaussian(IN.texcoord);
    }
  }

  compile("target_vs", "ssao_blur_vs");
  compile("target_ps", "ssao_blur_ps");
}


shader bent_cones_random_pattern
{
  cull_mode = none;
  z_write = false;
  z_test = false;

  POSTFX_VS(0)

  (ps) { sampleRadius@f1 = (sampleRadius); }
  hlsl(ps) {
    float rand(float2 co)
    {
      return frac(sin(dot(co.xy, float2(12.9898,78.233))) * 43758.5453);
    }
    float2 rand2(float2 co)
    {
      return float2(rand(co), rand(co+float2(1,0)));
    }
    uint rand_seed(float2 texcoord)
    {
      float2 seed = rand2(texcoord);
      return uint(seed.x * 7829 + seed.y * 113);
    }
    uint rand_lcg(inout uint g_rng_state)
    {
      // LCG values from Numerical Recipes
      g_rng_state = 1664525U * g_rng_state + 1013904223U;
      return g_rng_state;
    }

    float rand_lcg_float(inout uint g_rng_state)
    {
      uint ret = rand_lcg(g_rng_state);
      //return float(ret) * (1.0 / 4294967296.0);
      return frac(float(ret) * (1.0 / 262144.0));
    }



    float3 unitSphericalToCarthesian(float phi, float cosTheta)
    {
      float3 result;
      float theta = acos(cosTheta);
      float sinTheta = sin(theta);
      //float sinTheta = sqrt( 1 - cosTheta * cosTheta );
      result.x = sin(phi) * sinTheta;
      result.y = cos(phi) * sinTheta;
      result.z = cosTheta;
      return result;
    }
    float4 random_pattern_ps(float4 screenpos : VPOS) : SV_Target
    {
      float rayMarchingBias = 1 / float(BENT_CONES_RAY_STEPS) / 1000.0f;

      /*uint seed = rand_seed(screenpos.xy/4.0);
      float xi0, xi1, xi2;
      xi0 = rand_lcg_float(seed);
      while ((xi1 = rand_lcg_float(seed)) == xi0 || (xi1 == 0.0));
      while ((xi2 = rand_lcg_float(seed)) == xi1);

      float3 direction = unitSphericalToCarthesian((2*PI) * xi0, xi1);

      float offset = xi2 / float(BENT_CONES_RAY_STEPS);
      return float4(direction, offset + rayMarchingBias);*/

      uint seed = rand_seed(screenpos.xy/4.0);
      float offset = rand_lcg_float(seed) / float(BENT_CONES_RAY_STEPS);
      int2 scrPos = int2(screenpos.xy);

      float2 E = hammersley( scrPos.x+scrPos.y*(BENT_CONES_PATTERN*BENT_CONES_PATTERN), BENT_CONES_PATTERN*BENT_CONES_PATTERN*BENT_CONES_SAMPLES, 0 );
      //return float4(uniform_sample_sphere(E).xyz, offset + rayMarchingBias);
      return float4(cosine_sample_hemisphere(E).xyz, offset + rayMarchingBias);
    }
  }
  compile("target_ps", "random_pattern_ps");
}
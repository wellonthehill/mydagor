include "skinning_inc2.sh"
hlsl {
##if shader == dynamic_tele
  #define VERTEX_TANGENT 1
##else
  #define VERTEX_TANGENT 0
##endif
}

int instance_init_pos_const_no = 69;

float droplets_scale = 0;
interval droplets_scale : droplets_scale_off < 0.01, droplets_scale_on;

int hack_globtm_from_register = 0;
interval hack_globtm_from_register : hack_globtm_from_register_off < 1, hack_globtm_from_register_on;

int dyn_model_render_pass = 0;
interval dyn_model_render_pass : render_pass_normal < 1, render_pass_velocity < 2, render_pass_cockpit<3, render_to_depth<4,
  render_pass_xray<5, render_pass_normals;

int is_in_hangar = 0;
interval  is_in_hangar : is_in_hangar_false < 1, is_in_hangar_true;

int cutting = 0;
interval cutting : cutting_off < 1, cutting_on;

texture cut_noise_tex;
float4 cutting_plane_0 = (0, 0, 0, 1);
float4 cutting_plane_1 = (0, 0, 0, 1);
float4 cutting_plane_2 = (0, 0, 0, 1);
float4 cut_color = (0.15, 0.15, 0.15, 1);
float4 cut_params = (0.5, 0.2, 10, 1);

float4 texcoord_offset = (0, 0, 0, 0);

float4 droplets_tm_line_0 = (1, 0, 0, 0);
float4 droplets_tm_line_1 = (0, 1, 0, 0);
float4 droplets_tm_line_2 = (0, 0, 1, 0);

float4 dynamic_cube_params = (0, 0, 0, 0);

texture self_reflection_tex;
texture self_reflection_depth_tex;

float4 cockpit_illumination_detect = (0.5, 0.5, 0.5, 0);
float4 cockpit_illumination_color = (0.15, 0.2, 0.2, 0);

float enable_cockpit_illumination = 0;
interval enable_cockpit_illumination : enable_cockpit_illumination_off < 0.5, enable_cockpit_illumination_on;

texture cloud_transparency_mask_tex;

float tank_specular_color_mul = 20;
float tank_specular_power = 400;

float4 hatching_color = (1, 1, 1, 1);
float4 hatching_fresnel = (1, 1, 1, 1);
float4 hatching_type = (1, 1, 0, 0);





macro INIT_CUBEMAP()
//fixme: to be removed
  hlsl(ps) {
    half4 sample_dynamic_cube(float3 texcoord)
      { return gamma_to_linear_rgba(texCUBElod(envi_probe_specular, float4(texcoord,0)));}
  }
endmacro

macro USE_FLOAT_POS_PACKING()
  hlsl(vs){
    float3 unpack_pos(float3 pos) { return pos; }
  }
endmacro
int dynamic_pos_unpack_reg = 67;
macro USE_SHORT_POS_PACKING()
  hlsl(vs){
    float4 pos_unp_s_mul: register(c68);
    float4 pos_unp_s_ofs: register(c67);
    // unpack positions using dynmodel bbox
    float3 unpack_pos(float3 pos) { return pos*pos_unp_s_mul.xyz + pos_unp_s_ofs.xyz; }
  }
endmacro

macro USE_DIFFUSE_TC()
  hlsl {
    #define DIFFUSE_TC(type, name, tc) type name: tc;
  }
  hlsl(vs){
    #define SET_DIFFUSETC(outtc, intc) outtc = intc;
  }
endmacro

macro NOT_USE_DIFFUSE_TC()
  hlsl {
    #define DIFFUSE_TC(type, name, tc)
  }
  hlsl(vs){
    #define SET_DIFFUSETC(outtc, intc)
  }
endmacro

macro SPECIAL_RENDER_ALPHATEST_USE()

  if (dyn_model_render_pass == render_to_depth)
  {
    hlsl(ps) {
      half4 render_depth_ps(VsOutput input) : SV_Target
      {
        half4 diffuseColor = h4tex2D(diffuse_tex, input.diffuseTexcoord);
        clip_alpha(diffuseColor.a);
        return float4(0, 0, 0, diffuseColor.a);       // Return 0 to be consistent with black_ps. Color output used in tank outlines.
      }
    }
    compile("target_ps", "render_depth_ps");
  }
  else if (dyn_model_render_pass == render_pass_velocity)
  {
    hlsl(ps) {
      half4 render_pass_velocity_atest(VsOutput input) : SV_Target
      {
        half4 diffuse = h4tex2D(diffuse_tex, input.diffuseTexcoord);
        return half4(1, 1, 1, diffuse.a);
      }

    }
    compile("target_ps", "render_pass_velocity_atest");
  }
endmacro

macro SPECIAL_RENDER_NOALPHATEST()

  if (dyn_model_render_pass == render_to_depth)
  {
    hlsl(ps) {
      half4 black_ps() : SV_Target
      {
        return half4(0, 0, 0, 0); // Return 0 to be consistent with black_ps. Color output used in tank outlines.
      }
    }
    compile("target_ps", "black_ps");
  }
  else if (dyn_model_render_pass == render_pass_velocity)
  {
    hlsl(ps) {
      half4 render_pass_velocity() : SV_Target
      {
        return half4(1, 1, 1, 1);
      }
    }
    compile("target_ps", "render_pass_velocity");
  }
endmacro



macro SPECIAL_RENDER_ALPHATEST_CHOOSE()
  if (atest == atestOn)
  {
    SPECIAL_RENDER_ALPHATEST_USE()
  } else
  {
    SPECIAL_RENDER_NOALPHATEST()
  }
endmacro



macro INIT_XRAY_RENDER()

  (ps)
  {
    hatching_color@f4 = hatching_color;
    hatching_fresnel@f4 = hatching_fresnel;
    hatching_type@f4 = hatching_type;
  }

  hlsl(ps) {

    float4 xray_lighting(float3 point_to_eye, float3 world_normal)
    {
      float fresnel = saturate(1 - dot(world_normal, normalize(point_to_eye).xyz));
      fresnel = saturate(lerp(hatching_type.y, hatching_type.z, pow2(fresnel)) + hatching_type.x * world_normal.y);
      float3 colorRet = lerp(hatching_fresnel, hatching_color * hatching_type.w, fresnel);
      return float4(colorRet.rgb, hatching_color.a);
    }
  }
endmacro

macro XRAY_RENDER_USE(point_to_eye_name, normal_name, color)
  INIT_XRAY_RENDER()

  hlsl(ps) {
    half4 render_pass_xray(VsOutput input) : SV_Target
    {
      float3 worldNormal = normalize(input.normal_name.xyz);
    ##if dyn_model_render_pass == render_pass_normals
      return float4(worldNormal * 0.5f + 0.5f, hatching_color.a);
    ##else
      return xray_lighting(input.point_to_eye_name.xyz, worldNormal);
    ##endif
    }
  }
  compile("target_ps", "render_pass_xray");
endmacro



macro DYNAMIC_SIMPLE_VS_BASE()

  if (two_sided)
  {
    cull_mode = none;
  }


  channel short4n pos=pos bounding_pack;
  channel color8 norm=norm unsigned_pack;
  channel short2 tc[0]=tc[0] mul_4k;

  if (shader == dynamic_glass_chrome || shader == dynamic_masked_chrome || shader == dynamic_masked_chrome_bump || shader == dynamic_alpha_blend || shader == dynamic_simple)
  {
    if (num_bones != no_bones)
    {
      channel color8 tc[4] = extra[0];

      if (num_bones > one_bone)
      {
        channel color8 tc[5] = extra[1];
      }
    }
  }


  if (shader == dynamic_masked_chrome_bump)
  {
    hlsl(vs) {
      float3 instance_init_pos:register(c69);
      }
  }

  if (shader == dynamic_masked_glass_chrome  || shader == dynamic_tele)
  {
    //channel color8 tc[2] = extra[50] unsigned_pack;
    //channel color8 tc[3] = extra[51] unsigned_pack;
  }
  if ((shader == dynamic_masked_chrome_bump || shader == aces_weapon_fire) || (shader != dynamic_glass_chrome && shader != dynamic_mirror && shader != dynamic_tele))
  {
    USE_DIFFUSE_TC()
    if (dyn_model_render_pass == render_to_depth || dyn_model_render_pass == render_pass_velocity)
    {
      hlsl {
        struct VsOutput 
        { 
          VS_OUT_POSITION(pos) 
          DIFFUSE_TC(float2, diffuseTexcoord, TEXCOORD2)
        };
      }
    }
  } else
  {
    NOT_USE_DIFFUSE_TC()
    if (dyn_model_render_pass == render_to_depth || dyn_model_render_pass == render_pass_velocity)
    {
      hlsl(vs) {
        struct VsOutput 
        { 
          VS_OUT_POSITION(pos) 
        }; 
      }
    }
  }

  hlsl {

##if dyn_model_render_pass == render_to_depth || dyn_model_render_pass == render_pass_velocity
##elif shader == dynamic_simple || shader == dynamic_land_mesh_combined

    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      //float4 screenTexcoord                   : TEXCOORD0;

      DIFFUSE_TC(float2, diffuseTexcoord, TEXCOORD0)

      float3 pointToEye                       : TEXCOORD6;
      float4 normal__depth                    : TEXCOORD7;

    };

##else   // dynamic_masked_...

    struct VsOutput
    {
      VS_OUT_POSITION(pos)
      float3 normal                           : TEXCOORD0;

      DIFFUSE_TC(float2, diffuseTexcoord, TEXCOORD1)
## if shader == dynamic_masked_chrome

      float3 pointToEye                       : TEXCOORD2;

## elif shader == dynamic_masked_chrome_bump

      float4 pointToEye__polishing            : TEXCOORD2;

      #if USE_PAINTED_COLOR
        float2 paint_uv             : TEXCOORD5;
      #endif

## else    // dynamic_null, dynamic_illum, dynamic_alpha_blend, aces_weapon_fire

      float3 pointToEye                       : TEXCOORD2;

      //float3 lighting                         : TEXCOORD3;
      //float3 sun01lighting                    : TEXCOORD4;

## endif
    };

##endif
  }


//---------------------------------------------------
// VS stuff.
//---------------------------------------------------


  if (shader != dynamic_glass_chrome && shader != dynamic_mirror && shader != dynamic_tele)
  {
    if (shader == aces_weapon_fire)
    {
      (vs)
      {
        texcoord_offset@f2 = texcoord_offset;
      }
    } else if (shader == dynamic_masked_chrome_bump)
    {
      static float texcoord_mulp = 0;
      (vs){ texcoord_offset@f2 = (texcoord_offset.x*texcoord_mulp, texcoord_offset.y*texcoord_mulp, 0, 0); }
    }
  }

  if (shader == collimator || shader == gyro_sight)
  {
    (vs)
    {
      collimator_u@f4 = collimator_u;
      collimator_v@f4 = collimator_v;
      collimator_2_u@f4 = collimator_2_u;
      collimator_2_v@f4 = collimator_2_v;
      gyro_sight_u@f4 = gyro_sight_u;
      gyro_sight_v@f4 = gyro_sight_v;
    }
  }

  DECL_POSTFX_TC_VS_RT()
  USE_SHORT_POS_PACKING()

  if (shader == dynamic_glass_chrome || shader == dynamic_masked_chrome || shader == dynamic_masked_chrome_bump || shader == dynamic_alpha_blend || shader == dynamic_simple)
  {
    INIT_OPTIONAL_SKINNING()
  } else
  {
    INIT_NO_SKINNING()
  }

  hlsl(vs) {
    struct VsInput
    {
      float3 pos                  : POSITION;   // W defaults to 1.
      float3 normal               : NORMAL;
      int2  diffuseTexcoord      : TEXCOORD0;

##if shader == dynamic_masked_chrome_bump || shader == propeller_front || shader == dynamic_masked_glass_chrome
      #if VERTEX_TANGENT
      float4 packedDu             : TEXCOORD2;
      float4 packedDv             : TEXCOORD3;
      #endif
##endif
      INIT_BONES_VSINPUT(TEXCOORD4, TEXCOORD5)
    };
  }
  if (shader == dynamic_glass_chrome || shader == dynamic_masked_chrome || shader == dynamic_masked_chrome_bump || shader == dynamic_alpha_blend || shader == dynamic_simple)
  {
    OPTIONAL_SKINNING_SHADER()
  } else
  {
    NO_SKINNING_VS()
  }

  (vs)
  {
    droplets_tm_line_0@f4 = droplets_tm_line_0;
    droplets_tm_line_1@f4 = droplets_tm_line_1;
    droplets_tm_line_2@f4 = droplets_tm_line_2;
  }

  hlsl(vs) {

##if hack_globtm_from_register == hack_globtm_from_register_on
    float4 params : register(c48); // PARAMS_VS_CONST
##endif

    VsOutput dynamic_simple_vs(VsInput input)
    {
      VsOutput output;

      // unpack positions using dynmodel bbox
      input.pos.xyz = unpack_pos(input.pos);

      // unpack texcoord0
      float2 diffuseTexcoord = input.diffuseTexcoord / 4096.;

      // Skinning.

      float4 worldPos;
      float3 worldDu;
      float3 worldDv;
      float3 worldNormal;
      float3 localNormal = BGR_SWIZZLE(input.normal)*2-1;

##if shader == dynamic_tele
      //localNormal (always!?) = float3(-1,0,0) -> localDu=float3(0,-1,0); & localDv=float3(0,0,-1);
      float3 localDv = normalize(cross(localNormal, float3(0,1,0)));
      float3 localDu = normalize(cross(localNormal, localDv));
##elif shader == dynamic_masked_chrome_bump || shader == propeller_front || shader == dynamic_masked_glass_chrome
      #if VERTEX_TANGENT
      float3 localDu = BGR_SWIZZLE(input.packedDu)*2-1;
      float3 localDv = BGR_SWIZZLE(input.packedDv)*2-1;
      #else
      float3 localDu = float3(1,0,0), localDv = float3(1,0,0);
      #endif
##else
      float3 localDu = float3(1,0,0);
      float3 localDv = float3(1,0,0);
##endif
      instance_skinning(
        input,
        float4(input.pos, 1.),
        localNormal,
        localDu,
        localDv,
        worldPos,
        output.pos,
        worldNormal,
        worldDu,
        worldDv);

      float4 unpackedOutputPos = output.pos;
##if dyn_model_render_pass == render_to_depth || dyn_model_render_pass == render_pass_velocity

//##ifdef atest_use
## if (shader == dynamic_masked_chrome_bump || shader == aces_weapon_fire)
      SET_DIFFUSETC(output.diffuseTexcoord.xy, diffuseTexcoord + texcoord_offset.xy);
## else
      SET_DIFFUSETC(output.diffuseTexcoord, diffuseTexcoord);
## endif
//##endif

##else

      worldNormal = normalize(worldNormal);

##if (shader == dynamic_masked_chrome_bump || shader == aces_weapon_fire)
      SET_DIFFUSETC(output.diffuseTexcoord.xy, diffuseTexcoord + texcoord_offset.xy);
##else
      SET_DIFFUSETC(output.diffuseTexcoord, diffuseTexcoord);
##endif

##if shader == dynamic_simple || shader == dynamic_land_mesh_combined

      output.pointToEye.xyz = world_view_pos - worldPos;
      output.normal__depth.xyz = worldNormal;
      output.normal__depth.w = unpackedOutputPos.w;

##else // shader == dynamic_simple

##if shader == dynamic_masked_chrome_bump
      output.pointToEye__polishing.xyz = world_view_pos - worldPos;
      #if USE_PAINTED_COLOR
        output.paint_uv = painting_color_uv(instance_init_pos.xyz);
      #endif
##elif shader != dynamic_mirror && shader != dynamic_tele
      output.pointToEye.xyz = world_view_pos - worldPos;
##endif

      output.normal = worldNormal;

##if shader == dynamic_masked_chrome_bump || shader == propeller_front || shader == dynamic_masked_glass_chrome || shader == dynamic_tele

      #if VERTEX_TANGENT
      output.dU = worldDu;
      output.dV = worldDv;
      #endif
##endif

##if shader == dynamic_masked_chrome_bump

##  if hack_globtm_from_register == hack_globtm_from_register_on
     output.pointToEye__polishing.w = 0.15 * params.z;
##  else
     output.pointToEye__polishing.w = 0;
##  endif


##endif

##endif

##endif //renderModelForShadow != renderModelForShadowMask

      return output;
    }
  }
  compile("target_vs", "dynamic_simple_vs");

endmacro

macro DYNAMIC_SIMPLE_VS_ATEST_USE()
  DYNAMIC_SIMPLE_VS_BASE()
endmacro

macro DYNAMIC_SIMPLE_VS_NOATEST()
  DYNAMIC_SIMPLE_VS_BASE()
endmacro

macro DYNAMIC_SIMPLE_VS_ATEST_CHOOSE()
  DYNAMIC_SIMPLE_VS_BASE()
endmacro


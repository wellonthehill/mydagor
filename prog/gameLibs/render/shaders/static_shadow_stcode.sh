texture static_shadow_tex;

int static_shadows_cascades = 0;
interval static_shadows_cascades: off<1, one < 2, two;

float static_cascade_start = -1;

float4 static_shadow_matrix_0_0 = (0, 0, 0, 0);
float4 static_shadow_matrix_1_0 = (0, 0, 0, 0);
float4 static_shadow_matrix_2_0 = (0, 0, 0, 0);
float4 static_shadow_matrix_3_0 = (-1,-1,-1,0);
float4 static_shadow_matrix_0_1 = (0, 0, 0, 0);
float4 static_shadow_matrix_1_1 = (0, 0, 0, 0);
float4 static_shadow_matrix_2_1 = (0, 0, 0, 0);
float4 static_shadow_matrix_3_1 = (-1,-1,-1,0);
float4 static_shadow_cascade_0_scale_ofs_z_tor = (0, 0, 0, 0);
float4 static_shadow_cascade_1_scale_ofs_z_tor = (0, 0, 0, 0);

float4 global_static_shadow_fxaa_dir;

macro INIT_STATIC_SHADOW_BASE_ONE_CASCADE_STCODE(code)
  if (hardware.fsh_5_0)
  {
    (code) { static_shadow_tex@shdArray = static_shadow_tex; }
  }
  else
  {
    (code) { static_shadow_tex@shd = static_shadow_tex; }
  }

  (code) {
    // cascade 0 matrix, returns cascade 0 tc (not offseted with tor)
    staticShadowWorldRenderMatrix_0@f4[] =
    {
      static_shadow_matrix_0_0,
      static_shadow_matrix_1_0,
      static_shadow_matrix_2_0,
      static_shadow_matrix_3_0
    };
    static_shadow_cascade_0_tor@f2 = (static_shadow_cascade_0_scale_ofs_z_tor.z,static_shadow_cascade_0_scale_ofs_z_tor.w,0,0);
    static_cascade_start@f1 = static_cascade_start;
  }
endmacro

macro INIT_STATIC_SHADOW_BASE_SECOND_CASCADE_STCODE(code)//each cascade needs 7 floats + 1-2 for vignette distance
  (code) {
    // cascade 1 matrix, returns cascade 1 tc (not offseted with tor)
    staticShadowWorldRenderMatrix_1@f4[] =
    {
      static_shadow_matrix_0_1,
      static_shadow_matrix_1_1,
      static_shadow_matrix_2_1,
      static_shadow_matrix_3_1
    };
    static_shadow_cascade_1_scale_ofs_z_tor@f4 = static_shadow_cascade_1_scale_ofs_z_tor;
    static_shadow_cascade_1_tor@f2 = (static_shadow_cascade_1_scale_ofs_z_tor.z,static_shadow_cascade_1_scale_ofs_z_tor.w,0,0);
  }
endmacro

macro INIT_STATIC_SHADOW_BASE_ONE_CASCADE(code)
  if (use_extended_global_frame_block == no)
  {
    INIT_STATIC_SHADOW_BASE_ONE_CASCADE_STCODE(code)
  }
endmacro

macro INIT_STATIC_SHADOW_BASE_SECOND_CASCADE(code)
  if (use_extended_global_frame_block == no)
  {
    INIT_STATIC_SHADOW_BASE_SECOND_CASCADE_STCODE(code)
  }
endmacro

macro INIT_STATIC_SHADOW_BASE_STCODE(code)
  INIT_STATIC_SHADOW_BASE_ONE_CASCADE_STCODE(code)
  if (static_shadows_cascades == two)
  {
    INIT_STATIC_SHADOW_BASE_SECOND_CASCADE_STCODE(code)
  }
endmacro

macro INIT_STATIC_SHADOW_BASE(code)
  if (use_extended_global_frame_block == no)
  {
    INIT_STATIC_SHADOW_BASE_STCODE(code)
  }
endmacro

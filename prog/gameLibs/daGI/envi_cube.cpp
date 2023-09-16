#include <math/dag_math3d.h>
#include <daGI/daGI.h>

#include <3d/dag_drv3d.h>
#include <3d/dag_tex3d.h>
#include <shaders/dag_computeShaders.h>
#include <perfMon/dag_statDrv.h>

#include <math/dag_hlsl_floatx.h>
#include "shaders/dagi_envi_cube_consts.hlsli"
using namespace dagi;

void GI3D::VolmapCommonData::initEnviCube()
{
  ssgi_calc_envi_ambient_cube_cs.reset(new_compute_shader("ssgi_calc_envi_ambient_cube_cs"));
  ssgi_average_ambient_cube_cs.reset(new_compute_shader("ssgi_average_ambient_cube_cs"));
  enviCube = dag::buffers::create_ua_sr_structured(sizeof(AmbientCube), 1, "gi_ambient_cube");
  enviCubes = dag::buffers::create_ua_sr_structured(sizeof(AmbientCube), NUM_ENVI_CALC_CUBES, "gi_ambient_cubes");
  enviCubeValid = false;
}

void GI3D::VolmapCommonData::calcEnviCube()
{
  if (enviCubeValid || !ssgi_calc_envi_ambient_cube_cs)
    return;
  TIME_D3D_PROFILE(ssgi_calc_envi_cube);

  d3d::set_rwbuffer(STAGE_CS, 0, enviCubes.getBuf());
  // todo: we can make it temporal, one group per frame as well
  // currently it is pretty fast, but it make sense if there are rare envi changes
  // if we have gradual envi chane (i.e. time of day), it is better temporarily blend in new each frame
  ssgi_calc_envi_ambient_cube_cs->dispatch(NUM_ENVI_CALC_CUBES, 1, 1);
  d3d::resource_barrier({enviCubes.getBuf(), RB_RO_SRV | RB_STAGE_COMPUTE});

  d3d::set_rwbuffer(STAGE_CS, 0, enviCube.getBuf());
  d3d::set_buffer(STAGE_CS, 15, enviCubes.getBuf());
  ssgi_average_ambient_cube_cs->dispatch(1, 1, 1);
  d3d::set_buffer(STAGE_CS, 15, 0);
  d3d::set_rwbuffer(STAGE_CS, 0, 0);
  d3d::resource_barrier({enviCube.getBuf(), RB_RO_SRV | RB_STAGE_COMPUTE});
  enviCubeValid = true;
}

void GI3D::calcEnviCube() { common.calcEnviCube(); }

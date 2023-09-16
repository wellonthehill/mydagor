#define MAX_TRACERS 2048

#define TRACER_RIBBON_SEGMENTS_COUNT 512
#define TRACER_SEGMENTS_COUNT 16
#define TRACER_COMMAND_WARP_SIZE 16
#define TRACER_CULL_WARP_SIZE 16
#define TRACER_MAX_UPDATE_COMMANDS (4096-4)
#define TRACER_MAX_CREATE_COMMANDS ((4096-4)/4)
#define TRACER_MAX_CULL_COMMANDS (4096-14)

#ifndef GPU_TARGET
#pragma pack(push, 1)
#endif

struct GPUSmokeTracer//todo: compress.
{
  float3 p0;
  float pad0;
  float3 dir; //changes on create only, needed for update&culling
  float pad1;

  float3 head_color;//changes on create only, needed for culling only (creates head)
  float burnTime;// for head

  float4 smoke_color_density;//changes on create only, needed for culling only(creates tail)

  float ttl, radiusStart;//changes on create only, needed for update&culling
  float startTime;//changes on create only, needed for update&culling
  float padding;
};

struct GPUSmokeTracerVertices//todo: compress. needed for rendering
{
  float4 pos_dist;
  float time;
  float padding0;
  float padding1;
  float padding2;
};

struct GPUSmokeTracerDynamic
{
  float3 movingDir;//changes on update, needed for update (normalized val)
  uint firstVert_totalVerts;//changes on update/culling, needed on update&culling
  float radius, len;//changes on update, needed for culling
  float padding0;
  float padding1;
};

struct TracerUpdateCommand
{
  float3 pos;
  uint id;
  #ifndef GPU_TARGET
  TracerUpdateCommand() = default;
  TracerUpdateCommand(int id_, const Point3 &p):id(id_), pos(p){}
  #endif
};

struct GPUSmokeTracerTailRender//todo: compress me!
{
  float4 smoke_color_density;//can be compressed
  float ttl, radiusStart;//can be compressed
  float startTime;
  uint firstVert_totalVerts;
  uint id;
  float padding0;
  float padding1;
  float padding2;
};

struct GPUSmokeTracerHeadRender//todo: compress me!
{
  float3 p0;
  float pad0;
  float3 p1;
  float radius;//can be compressed

  float4 color;//can be compressed
};

struct TracerCreateCommand
{
  float3 pos0; float ttl;
  float3 dir; uint id;
  float4 smoke_color;
  float4 head_color__burnTime;
  #ifndef GPU_TARGET
  TracerCreateCommand() = default;
  TracerCreateCommand(int id_, const float3 &p0, const float3 &d, float ttl_, const float4 &smoke_color_, const float4 &head_color_):
    id(id_), pos0(p0), dir(d), ttl(ttl_), smoke_color(smoke_color_), head_color__burnTime(head_color_){}
  #endif
};

#ifdef GPU_TARGET
float get_tracers_max_turbulence_radius(float radiusStart) {return (radiusStart*2+0.25);}

#define TRACERS_WIND_RADIUS_STR 0.1
float get_tracers_max_wind_radius(float radiusStart){return TRACERS_WIND_RADIUS_STR*radiusStart;}

float3 get_tracers_wind(float time)
{
  return -time*TRACERS_WIND_RADIUS_STR*float3(1,0,1);//todo: unified wind solution (particles, volumetrics, tracers)
}

#endif

#ifndef GPU_TARGET
#pragma pack(pop)
#endif

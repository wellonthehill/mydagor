include "shader_global.sh"
include "indoor_light_probes.sh"

float debug_indoor_boxes_size = 1.0;

shader debug_indoor_boxes
{
  z_test = true;
  z_write = true;
  cull_mode = none;

  (vs)
  {
    globtm@f44 = globtm;
    debug_indoor_boxes_size@f1 = (debug_indoor_boxes_size);
  }


  hlsl
  {
    struct VsOutput
    {
      VS_OUT_POSITION(pos)
    };
  }

  (vs) {
    indoor_probes_data@cbuf = indoor_active_probes_data hlsl {
      #include <indoor_probes_const.hlsli>
      cbuffer indoor_probes_data@cbuf
      {
        float4 indoor_probe_boxes[MAX_ACTIVE_PROBES * 3];
        float4 indoor_probe_pos_and_cubes[MAX_ACTIVE_PROBES];
      }
    }
    indoor_probe_cells@buf = indoor_probe_cells_clusters hlsl {
      StructuredBuffer<uint4> indoor_probe_cells@buf;
    };
  }

  hlsl(vs)
  {
    VsOutput debug_indoor_boxes_vs(uint vertexId : SV_VertexID)
    {
      uint boxId = vertexId / 36;
      uint indexIndex = vertexId % 36;

      uint indices[36] =
      {
        0, 1, 2, 0, 2, 3,
        1, 5, 6, 1, 6, 2,
        5, 4, 7, 5, 7, 6,
        4, 0, 3, 4, 3, 7,
        0, 1, 5, 0, 5, 4,
        3, 2, 6, 3, 6, 7
      };

      float3 vertices[8] =
      {
        float3(0, 0, 0),
        float3(1, 0, 0),
        float3(1, 1, 0),
        float3(0, 1, 0),
        float3(0, 0, 1),
        float3(1, 0, 1),
        float3(1, 1, 1),
        float3(0, 1, 1),
      };
      float3 localPos = vertices[indices[indexIndex]] - 0.5f;

      float3 boxSize = debug_indoor_boxes_size * float3(indoor_probe_boxes[boxId * 3 + 0].w, indoor_probe_boxes[boxId * 3 + 1].w, indoor_probe_boxes[boxId * 3 + 2].w);
      if (indoor_probe_pos_and_cubes[boxId].w == float(INVALID_CUBE_ID))
      {
        //draw nothing
        VsOutput result;
        result.pos = float4(50, 50, 50, 1);
        return result;
      }
      localPos *= boxSize;
      float3 boxX = indoor_probe_boxes[boxId * 3 + 0].xyz;
      float3 boxY = indoor_probe_boxes[boxId * 3 + 1].xyz;
      float3 boxZ = indoor_probe_boxes[boxId * 3 + 2].xyz;

      float3 worldPos = localPos.x * boxX + localPos.y * boxY + localPos.z * boxZ + indoor_probe_pos_and_cubes[boxId].xyz;

      VsOutput result;
      result.pos = mul(float4(worldPos, 1), globtm);

      return result;
    }
  }
  compile("target_vs", "debug_indoor_boxes_vs");

  hlsl(ps)
  {
    half3 debug_indoor_boxes_ps(VsOutput input):SV_Target0
    {
      return float3(0,1,0);
    }
  }
  compile("target_ps", "debug_indoor_boxes_ps");
}

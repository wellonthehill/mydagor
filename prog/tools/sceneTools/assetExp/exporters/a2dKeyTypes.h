#pragma once

#include <math/dag_Point3.h>
#include <math/dag_Quat.h>
#include <vecmath/dag_vecMathDecl.h>
#include <generic/dag_tab.h>
#include <dag/dag_vector.h>
#include <util/dag_globDef.h>


struct OldAnimKeyReal
{
  real p, k1, k2, k3;
};
struct OldAnimKeyPoint3
{
  Point3 p, k1, k2, k3;
};
struct OldAnimKeyQuat
{
  real pw, bw;
  real sinpw, sinbw;
  Quat p, b0, b1;
};

struct ChannelData
{
  struct Anim
  {
    void *key;
    int *keyTime;
    int keyNum;
    int keyOfs, keyTimeOfs;
  };
  Anim *nodeAnim = nullptr;
  int nodeNum = 0;
  char **nodeName = nullptr;
  real *nodeWt = nullptr;
  unsigned channelType = 0;
  unsigned dataType = 0;
  int nodeAnimOfs = 0;
  int nodeNameOfs = 0;
  int nodeWtOfs = 0;

  ~ChannelData() { clear(); }

  void alloc(int node_num)
  {
    nodeAnim = new Anim[node_num];
    nodeName = new char *[node_num];
    nodeWt = new real[node_num];
    nodeNum = node_num;
  }
  void clear()
  {
    del_it(nodeAnim);
    del_it(nodeName);
    del_it(nodeWt);
    nodeNum = 0;
  }
  static int cmp(const ChannelData *a, const ChannelData *b)
  {
    return a->dataType == b->dataType ? a->channelType - b->channelType : a->dataType - b->dataType;
  }
  static void findDataTypeRange(int dt, dag::ConstSpan<ChannelData> list, int &start, int &num)
  {
    for (start = 0; start < list.size(); start++)
      if (list[start].dataType == dt)
      {
        for (num = 1; start + num < list.size(); num++)
          if (list[start + num].dataType != dt)
            break;
        return;
      }
    start = num = 0;
  }
};
DAG_DECLARE_RELOCATABLE(ChannelData);

vec4f interp_point3(ChannelData::Anim &a, int t);
vec4f interp_quat(ChannelData::Anim &a, int t);

namespace animopt
{
typedef int TimeValue;

struct PosKey
{
  TimeValue t;
  Point3 p, i, o;
};
struct RotKey
{
  TimeValue t;
  Quat p, i, o;
};

void convert_to_PosKey(Tab<PosKey> &pos, OldAnimKeyPoint3 *k, const int *kt, int num);
void convert_to_RotKey(Tab<RotKey> &rot, OldAnimKeyQuat *k, const int *kt, int num, int rot_resample_freq = 0);

void convert_to_OldAnimKeyPoint3(OldAnimKeyPoint3 *k, int *kt, PosKey *s, int num);
void convert_to_OldAnimKeyQuat(OldAnimKeyQuat *k, int *kt, RotKey *s, int num);
} // namespace animopt

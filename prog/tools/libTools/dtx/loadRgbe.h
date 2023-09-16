#ifndef _GAIJIN_DAGOR_LOADRGBE_H
#define _GAIJIN_DAGOR_LOADRGBE_H


#include <image/dag_texPixel.h>
#include <memory/dag_mem.h>


class IGenLoad;


struct HDRImageInfo
{
  real exposure;
  real gamma;
};


TexImageF *load_rgbe(const char *fn, IMemAlloc *mem, HDRImageInfo *ii);

TexImageF *load_rgbe(IGenLoad &crd, int datalen, IMemAlloc *mem, HDRImageInfo *ii);


#endif

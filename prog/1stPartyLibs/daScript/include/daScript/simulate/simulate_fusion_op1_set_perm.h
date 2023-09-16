// set int and numeric

#define IMPLEMENT_OP1_SET_INTEGER_FUSION_POINT(OPNAME) \
    IMPLEMENT_SET_OP1_FUSION_POINT(__forceinline,OPNAME,Int,int32_t,int32_t); \
    IMPLEMENT_SET_OP1_FUSION_POINT(__forceinline,OPNAME,UInt,uint32_t,uint32_t); \
    IMPLEMENT_SET_OP1_FUSION_POINT(_msc_inline_bug,OPNAME,Int64,int64_t,int64_t); \
    IMPLEMENT_SET_OP1_FUSION_POINT(_msc_inline_bug,OPNAME,UInt64,uint64_t,uint64_t);

#define IMPLEMENT_OP1_SET_NUMERIC_FUSION_POINT(OPNAME) \
    IMPLEMENT_OP1_SET_INTEGER_FUSION_POINT(OPNAME); \
    IMPLEMENT_SET_OP1_FUSION_POINT(__forceinline,OPNAME,Float,float,float); \
    IMPLEMENT_SET_OP1_FUSION_POINT(__forceinline,OPNAME,Double,double,double);

#define IMPLEMENT_OP1_SET_SCALAR_FUSION_POINT(OPNAME) \
    IMPLEMENT_OP1_SET_NUMERIC_FUSION_POINT(OPNAME); \
    IMPLEMENT_SET_OP1_FUSION_POINT(__forceinline,OPNAME,Bool,bool,bool);

#define IMPLEMENT_OP1_SET_WORKHORSE_FUSION_POINT(OPNAME) \
    IMPLEMENT_OP1_SET_SCALAR_FUSION_POINT(OPNAME); \
    IMPLEMENT_SET_OP1_FUSION_POINT(__forceinline,OPNAME,Ptr,StringPtr,StringPtr); \
    IMPLEMENT_SET_OP1_FUSION_POINT(__forceinline,OPNAME,Ptr,VoidPtr,StringPtr);

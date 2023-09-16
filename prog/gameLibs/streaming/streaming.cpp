#include <streaming/streaming.h>
#include <debug/dag_debug.h>


#if _TARGET_C1 || _TARGET_C2


#elif _TARGET_XBOX
namespace xbox
{
extern bool is_streaming();
}
#define IS_STREAMING() xbox::is_streaming()
#else
#define IS_STREAMING() (false)
#endif

static bool is_streaming_now_flag = false;

namespace streaming
{

bool is_streaming_now() { return IS_STREAMING() || is_streaming_now_flag; }

void set_streaming_now(bool on) { is_streaming_now_flag = on; }

} // namespace streaming

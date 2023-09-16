#include "internal.h"

#include <stdlib.h>
#include <unistd.h>

namespace folders
{
namespace internal
{
static String game_name;

void platform_initialize(const char *app_name) { game_name = app_name; }

String get_exe_dir() { return {}; }

String get_game_dir()
{
  String dir;
  get_current_work_dir(dir);
  return dir;
}

String get_gamedata_dir()
{
  G_ASSERT_RETURN(!game_name.empty(), {});
  String gameData;
  gameData.printf(260, "%s/%s/%s", getenv("HOME"), "Documents", game_name);
  return gameData;
}

String get_temp_dir() { return String("/tmp/"); }

String get_local_appdata_dir() { return get_gamedata_dir(); }

String get_common_appdata_dir() { return get_gamedata_dir(); }

String get_downloads_dir()
{
  String downloadsDir;
  String gameData = get_gamedata_dir();
  downloadsDir.printf(0, "%s/%s", gameData, "downloads");
  return downloadsDir;
}
} // namespace internal
} // namespace folders

//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#if _TARGET_PC_WIN
#include <windows.h>
#include <malloc.h>
#include <osApiWrappers/dag_progGlobals.h>
#endif

inline void win_set_process_dpi_aware()
{
#if _TARGET_PC_WIN
#if !defined(DAGOR_NO_DPI_AWARE) || (DAGOR_NO_DPI_AWARE != 1)
#if defined(DAGOR_NO_DPI_AWARE) && (DAGOR_NO_DPI_AWARE < 0)
  for (unsigned i = 1; i < __argc; i++)
    if (strcmp(__argv[i], "-noHDPI") == 0)
      return;
#endif

  if (HMODULE hm = LoadLibraryA("user32.dll"))
  {
    typedef DPI_AWARENESS_CONTEXT(WINAPI * PSetThreadDpiAwarenessContext)(DPI_AWARENESS_CONTEXT);
    PSetThreadDpiAwarenessContext SetThreadDpiAwarenessContext =
      (PSetThreadDpiAwarenessContext)(void *)GetProcAddress(hm, "SetThreadDpiAwarenessContext"); // SetProcessDpiAwarenessContext does
                                                                                                 // not work here because it cannot
    DPI_AWARENESS_CONTEXT res = NULL; // override compatibility options of the parent process (far.exe for example),
    if (SetThreadDpiAwarenessContext) // while the SetThreadDpiAwarenessContext can.
      res = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE);

    BOOL(WINAPI * SetProcessDPIAware)(void) = (BOOL(WINAPI *)(void))(void *)GetProcAddress(hm, "SetProcessDPIAware");
    if (SetProcessDPIAware)
      SetProcessDPIAware();

    UINT(WINAPI * GetDpiForSystem)(void) = (UINT(WINAPI *)(void))(void *)GetProcAddress(hm, "GetDpiForSystem");
    if (GetDpiForSystem)
      win32_system_dpi = GetDpiForSystem();

    FreeLibrary(hm);
  }
#endif // DAGOR_NO_DPI_AWARE
#endif
}

inline void win_recover_systemroot_env()
{
#if _TARGET_PC_WIN
  DWORD len = GetEnvironmentVariableW(L"SystemRoot", NULL, 0);
  wchar_t *varBuf = (wchar_t *)alloca((len > MAX_PATH ? len : MAX_PATH) * sizeof(wchar_t));
  WIN32_FILE_ATTRIBUTE_DATA attrs;
  if (len && GetEnvironmentVariableW(L"SystemRoot", varBuf, len) && GetFileAttributesExW(varBuf, GetFileExInfoStandard, &attrs) &&
      (attrs.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    return;
  if (GetWindowsDirectoryW(varBuf, MAX_PATH))
    SetEnvironmentVariableW(L"SystemRoot", varBuf);
#endif
}

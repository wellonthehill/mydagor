#include <osApiWrappers/dag_globalMutex.h>
#include <osApiWrappers/dag_lockProfiler.h>
#if _TARGET_PC_WIN
#include <windows.h>
#elif _TARGET_APPLE | _TARGET_PC_LINUX
#include <semaphore.h>
#include <fcntl.h>
#endif
#include <util/dag_globDef.h>
#include <stdio.h>
#include <string.h>

void *global_mutex_create(const char *mutex_name)
{
  char name[260];
#if _TARGET_PC_WIN
  SNPRINTF(name, sizeof(name), "Global\\%s", mutex_name);
  HANDLE mutex = CreateMutex(NULL, FALSE, name);
  return mutex;
#elif _TARGET_APPLE | _TARGET_PC_LINUX
  G_ASSERT(strchr(mutex_name, '/') == NULL);
  SNPRINTF(name, sizeof(name), "/%s", mutex_name);
  sem_t *sem = sem_open(name, O_CREAT, 0644, 1);
  G_VERIFY(sem);
  return sem;
#else
  G_UNUSED(name);
  (void)(mutex_name);
  return NULL;
#endif
}

int global_mutex_enter(void *mutex)
{
  ScopeLockProfiler<da_profiler::DescGlobalMutex> lp;
  G_UNUSED(lp);
#if _TARGET_PC_WIN
  int ret = WaitForSingleObject(mutex, INFINITE) == WAIT_OBJECT_0 ? 0 : -1;
#elif _TARGET_APPLE | _TARGET_PC_LINUX
  sem_t *sem = (sem_t *)mutex;
  int ret = sem ? sem_wait(sem) : -1;
#else
  (void)(mutex);
  int ret = -1;
#endif
  return ret;
}

int global_mutex_leave(void *mutex)
{
#if _TARGET_PC_WIN
  return ReleaseMutex(mutex) ? 0 : -1;
#elif _TARGET_APPLE | _TARGET_PC_LINUX
  sem_t *sem = (sem_t *)mutex;
  return sem ? sem_post(sem) : -1;
#else
  (void)(mutex);
  return -1;
#endif
}

int global_mutex_destroy(void *mutex, const char *mutex_name)
{
#if _TARGET_PC_WIN
  return CloseHandle(mutex) ? 0 : -1;
  G_UNUSED(mutex_name);
#elif _TARGET_APPLE | _TARGET_PC_LINUX
  sem_t *sem = (sem_t *)mutex;
  if (sem)
  {
    int ret = sem_close(sem);
    if (ret)
      return ret;
    return sem_unlink(mutex_name);
  }
  else
    return -1;
#else
  (void)(mutex);
  (void)(mutex_name);
  return -1;
#endif
}

#define EXPORT_PULL dll_pull_osapiwrappers_globalMutex
#include <supp/exportPull.h>

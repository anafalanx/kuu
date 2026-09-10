/*
 * launch.h -- born-in-job process launch, the Windows substrate under `proc`.
 *
 * A supervised child is placed into its Job Object by the kernel at
 * CreateProcess time (PROC_THREAD_ATTRIBUTE_JOB_LIST), before its first thread
 * runs, so nothing it spawns can escape supervision.  The job carries
 * KILL_ON_JOB_CLOSE: when kuu's last handle to it closes, for any reason
 * including kuu's own death, every process in the tree is terminated.  That
 * is the no-orphans law, and it is the kernel's promise rather than kuu's.
 *
 * Exactly the three stdio handles are inherited, as private duplicates.  Batch
 * targets go through a defensively quoted cmd.exe (cmdline.h).  A bare command
 * name resolves from PATH only, never from the current directory.
 */
#ifndef KUU_LAUNCH_H
#define KUU_LAUNCH_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "kuu.h"
#include <stdint.h>

typedef struct ku_stdio {
    HANDLE in, out, err;
} ku_stdio;

/* Resolve a program name to an absolute executable path (malloc'd UTF-8).
 * Returns 0; 1 when nothing matched (PROC notfound); 2 when the name is not
 * valid UTF-8 (PROC encoding). */
int ku_resolve_exe(const char *program, char **exe);

/* Create a Job Object with KILL_ON_JOB_CLOSE; NULL with `fail` set. */
HANDLE ku_job_new(ku_fail *fail);

typedef struct ku_limits {
    uint64_t memory;
    int64_t cpu_ms;
    DWORD processes;
} ku_limits;

/* Apply positive job-wide limits before any process is born in the job. */
int ku_job_limits(HANDLE job, const ku_limits *limits, ku_fail *fail);

/* Open the null device for reading (write == 0) or reading and writing. */
HANDLE ku_open_nul(int write);

/* Build a sorted UTF-16 environment block: kuu's own environment with `keys`
 * overriding (values[i] != NULL) or removing (values[i] == NULL) entries.
 * Keys are compared case-insensitively.  malloc'd; caller frees. */
int ku_env_block(int count, const char *const *keys, const char *const *values,
                 wchar_t **block, ku_fail *fail);

/* Launch `exe` (absolute) with `argv` as the child's argv.  `cwd` may be
 * NULL.  With a job handle the child is born into it.  With `job` == NULL
 * (the detach path) the child gets no console of ours, its own process group,
 * and leaves kuu's own job when that job permits breakaway; jobs enclosing kuu
 * itself are left alone.  `env` may be NULL to inherit.  On success sets *pid
 * and *process (a handle the caller closes).  Failures fill `fail` with domain
 * PROC and code launch, encoding, or badvalue. */
int ku_launch(const char *exe, int argc, const char *const *argv, const char *cwd,
              HANDLE job, const ku_stdio *io, const wchar_t *env,
              DWORD *pid, HANDLE *process, ku_fail *fail);

#endif /* KUU_LAUNCH_H */

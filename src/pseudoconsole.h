/* Pseudoconsole ownership across the 23H2 and 24H2+ shutdown contracts. */
#ifndef KUU_PSEUDOCONSOLE_H
#define KUU_PSEUDOCONSOLE_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "kuu.h"

typedef struct ku_console ku_console;

int ku_console_open(COORD size, HANDLE input, HANDLE output, ku_console **out, ku_fail *fail);
HPCON ku_console_handle(const ku_console *console);
int ku_console_legacy(const ku_console *console);
void ku_console_release(ku_console *console);
/* Transfers ownership; never touches Lua or waits for the console to exit. */
void ku_console_close(ku_console *console);
/* Legacy only: begin natural close while retaining the owner's context. */
void ku_console_end(ku_console *console);
/* Legacy only: transfer an output with no pending I/O to the native drainer. */
void ku_console_abandon(ku_console *console, HANDLE output);
/* After Lua transfers its pipes: join all workers before the process exits. */
void ku_console_shutdown(void);

#endif

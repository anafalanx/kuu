/* 23H2 closes synchronously and must keep draining final console output.
 * Reserve both workers and their events before creating the HPCON. They
 * never access Lua, child state or the event loop. 24H2+ keeps the OS path. */
#include "pseudoconsole.h"
#include <stdlib.h>
#include <string.h>

typedef HRESULT (WINAPI *release_console_fn)(HPCON);

struct ku_console {
    HPCON handle;
    HANDLE close_event, thread, drain_event, drain_thread, read_event, output;
    int released;
    release_console_fn release;
    struct ku_console *next;
};

/* Only the Lua-owning thread accesses the list and transfers pipe ownership. */
static ku_console *closers;

static void free_console(ku_console *console)
{
    if (console->thread != NULL) CloseHandle(console->thread);
    if (console->drain_thread != NULL) CloseHandle(console->drain_thread);
    if (console->close_event != NULL) CloseHandle(console->close_event);
    if (console->drain_event != NULL) CloseHandle(console->drain_event);
    if (console->read_event != NULL) CloseHandle(console->read_event);
    free(console);
}

static void reap_closers(void)
{
    ku_console **link = &closers;
    while (*link != NULL) {
        ku_console *console = *link;
        if (console->released && WaitForSingleObject(console->thread, 0) == WAIT_OBJECT_0 &&
            WaitForSingleObject(console->drain_thread, 0) == WAIT_OBJECT_0) {
            *link = console->next;
            free_console(console);
        } else {
            link = &console->next;
        }
    }
}

static DWORD WINAPI close_worker(void *context)
{
    ku_console *console = context;
    WaitForSingleObject(console->close_event, INFINITE);
    if (console->handle != NULL) ClosePseudoConsole(console->handle);
    return 0;
}

static DWORD WINAPI drain_worker(void *context)
{
    ku_console *console = context;
    WaitForSingleObject(console->drain_event, INFINITE);
    if (console->output != NULL) {
        char buffer[65536];
        for (;;) {
            OVERLAPPED io = {0};
            /* This pipe was attached to the loop. The documented low event
             * bit suppresses IOCP packets for these private worker reads. */
            io.hEvent = (HANDLE)((ULONG_PTR)console->read_event | 1);
            ResetEvent(console->read_event);
            DWORD bytes;
            if (!ReadFile(console->output, buffer, sizeof buffer, NULL, &io) &&
                GetLastError() != ERROR_IO_PENDING) break;
            if (!GetOverlappedResult(console->output, &io, &bytes, TRUE) || bytes == 0) break;
        }
        CloseHandle(console->output);
    }
    return 0;
}

int ku_console_open(COORD size, HANDLE input, HANDLE output, ku_console **out, ku_fail *fail)
{
    *out = NULL;
    reap_closers();
    ku_console *console = calloc(1, sizeof *console);
    if (console == NULL) {
        return ku_fail_set(fail, "PTY", "oserror", "out of memory creating the pseudoconsole");
    }
    /* This export does not exist on 23H2. Never put it in the import table. */
    FARPROC address = GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "ReleasePseudoConsole");
    _Static_assert(sizeof console->release == sizeof address, "function pointer size");
    memcpy(&console->release, &address, sizeof address);
    if (console->release == NULL) {
        console->close_event = CreateEventW(NULL, TRUE, FALSE, NULL);
        if (console->close_event == NULL) goto reserve_failed;
        console->drain_event = CreateEventW(NULL, TRUE, FALSE, NULL);
        if (console->drain_event == NULL) goto reserve_failed;
        console->read_event = CreateEventW(NULL, TRUE, FALSE, NULL);
        if (console->read_event == NULL) goto reserve_failed;
        console->thread = CreateThread(NULL, 0, close_worker, console, 0, NULL);
        if (console->thread == NULL) goto reserve_failed;
        console->drain_thread = CreateThread(NULL, 0, drain_worker, console, 0, NULL);
        if (console->drain_thread == NULL) goto reserve_failed;
        console->next = closers;
        closers = console;
    }
    HRESULT hr = CreatePseudoConsole(size, input, output, 0, &console->handle);
    if (FAILED(hr)) {
        ku_console_close(console);
        return ku_fail_set(fail, "PTY", "oserror", "cannot create the pseudoconsole (HRESULT 0x%08lx)", (unsigned long)hr);
    }
    *out = console;
    return 0;

reserve_failed: {
    DWORD error = GetLastError();
    /* No HPCON exists yet; the first worker has nothing to close. */
    if (console->thread != NULL) {
        SetEvent(console->close_event);
        WaitForSingleObject(console->thread, INFINITE);
    }
    free_console(console);
    return ku_fail_set(fail, "PTY", "oserror", "cannot reserve console cleanup workers (error %lu)", (unsigned long)error);
}
}

HPCON ku_console_handle(const ku_console *console) { return console->handle; }
int ku_console_legacy(const ku_console *console) { return console->release == NULL; }

void ku_console_release(ku_console *console)
{
    if (console->release != NULL) console->release(console->handle);
}

void ku_console_end(ku_console *console)
{
    /* Natural legacy exit: the loop still reads all final output. */
    SetEvent(console->close_event);
}

void ku_console_abandon(ku_console *console, HANDLE output)
{
    /* No pending loop read may reference this pipe when ownership moves. */
    console->output = output;
    console->released = 1;
    SetEvent(console->drain_event);
    SetEvent(console->close_event);
    reap_closers();
}

void ku_console_close(ku_console *console)
{
    if (console->close_event != NULL) {
        ku_console_abandon(console, NULL);
    } else {
        if (console->handle != NULL) ClosePseudoConsole(console->handle);
        free_console(console);
    }
}

void ku_console_shutdown(void)
{
    /* Lua has transferred abandoned outputs; workers can finish independently
     * of its destroyed state. Never kill a closer in the middle of the OS call. */
    for (ku_console *console = closers; console != NULL; console = console->next) {
        WaitForSingleObject(console->thread, INFINITE);
        WaitForSingleObject(console->drain_thread, INFINITE);
    }
    reap_closers();
}

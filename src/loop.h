/*
 * loop.h -- the event loop and coroutine scheduler.
 *
 * One thread owns the Lua state and one I/O completion port.  Every wait a
 * program performs, a child finishing, a pipe delivering bytes, a timer
 * expiring, another task ending, is a completion the loop processes on that
 * thread.  A palette call that must wait parks its coroutine on a waiter and
 * yields; the completion wakes the waiter; the loop resumes the coroutine.
 * Scripts therefore read as straight-line code while the host multiplexes.
 *
 * Invariants:
 *   - No other thread touches the Lua state.  A future foreign thread may only
 *     PostQueuedCompletionStatus to the port.
 *   - The completion key of every packet is a `ku_source *`, so the loop knows
 *     what kind of packet it holds before it touches anything else.
 *   - An outstanding overlapped request (`ku_io`) is owned by the loop until
 *     its packet arrives.  An owner that goes away orphans its requests
 *     (`src = NULL`); the loop frees them on arrival.  Nothing is freed while
 *     the kernel may still write to it.
 *   - The main chunk and every spawned task run as coroutines driven here.
 *     A coroutine that yields without parking has nothing to wait for and is
 *     failed with SCHED yield.
 */
#ifndef KUU_LOOP_H
#define KUU_LOOP_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stddef.h>
#include <stdint.h>

#include "kuu.h"
#include "lua.h"

typedef struct ku_loop ku_loop;
typedef struct ku_io ku_io;
typedef struct ku_source ku_source;
typedef struct ku_timer ku_timer;
typedef struct ku_waiter ku_waiter;
typedef struct ku_driver ku_driver;

/* ---- completion sources ------------------------------------------------- */

typedef enum { KU_SRC_IO = 1, KU_SRC_JOB = 2, KU_SRC_POSTED = 3 } ku_source_kind;

struct ku_source {
    ku_source_kind kind;
    void *owner;
    /* KU_SRC_IO: an overlapped request finished.  `error` is 0 or a Win32
     * error such as ERROR_BROKEN_PIPE; `bytes` is the transfer count. */
    void (*on_io)(ku_source *src, ku_io *io, DWORD bytes, DWORD error);
    /* KU_SRC_JOB: a Job Object message (JOB_OBJECT_MSG_*), with the pid it
     * concerns where the message has one. */
    void (*on_job)(ku_source *src, DWORD message, DWORD pid);
    /* KU_SRC_POSTED: a packet a foreign thread posted with ku_loop_post; the
     * only thing such a thread may do to the loop. */
    void (*on_posted)(ku_source *src, void *value, DWORD bytes);
};

/* Post a packet from any thread.  The loop calls src->on_posted on its own
 * thread.  Pair with ku_loop_expect before and ku_loop_received in the handler. */
int ku_loop_post(ku_loop *loop, ku_source *src, void *value, DWORD bytes);

/* An overlapped request.  Allocate with ku_io_new, post with ReadFile or
 * WriteFile on `handle` using &io->ov, then call ku_io_posted (or free it
 * again with ku_io_free when the call failed outright and no packet will
 * come).  `buf` is the request's own buffer when `cap` > 0. */
struct ku_io {
    OVERLAPPED ov; /* first, so the packet's OVERLAPPED pointer is the request */
    ku_source *src;
    HANDLE handle;
    unsigned char *buf;
    DWORD cap;
    int kind; /* owner-defined tag */
    ku_loop *loop;
};

ku_io *ku_io_new(ku_loop *loop, ku_source *src, HANDLE handle, DWORD cap);
void ku_io_posted(ku_io *io);  /* a packet will arrive for this request */
void ku_io_orphan(ku_io *io);  /* owner gone: the loop frees it on arrival */
void ku_io_free(ku_io *io);    /* no packet is coming */

/* ---- timers ------------------------------------------------------------- */

struct ku_timer {
    int64_t due_ms;
    size_t index; /* position in the heap, or KU_TIMER_IDLE */
    void (*fire)(ku_timer *timer);
    void *owner;
};
#define KU_TIMER_IDLE ((size_t)-1)

void ku_timer_init(ku_timer *timer, void (*fire)(ku_timer *), void *owner);
int ku_timer_arm(ku_loop *loop, ku_timer *timer, int64_t delay_ms); /* 0 ok, -1 oom */
void ku_timer_cancel(ku_loop *loop, ku_timer *timer);
int64_t ku_now_ms(void); /* monotonic milliseconds */

/* ---- drivers: coroutines the loop runs ----------------------------------- */

struct ku_driver {
    lua_State *co;
    int ref;      /* registry reference keeping `co` alive */
    int finished; /* the coroutine returned or failed */
    int status;   /* LUA_OK or the error status */
    /* Called once on the loop thread when the coroutine finishes.  For
     * LUA_OK the results are on `co`'s stack (`nresults` of them); otherwise
     * the error object is on top. */
    void (*on_finish)(ku_driver *driver, int nresults);
    void *owner;
};

/* Take ownership of `co` (already holding the function and `nargs`
 * arguments) and queue its first resume. */
int ku_driver_start(ku_loop *loop, ku_driver *driver, lua_State *co, int nargs);

/* ---- waiters: parked coroutines ------------------------------------------ */

/* Push the wake results onto `L` and return their count.  Set `w->raise`
 * to have the single pushed value raised instead of returned. */
typedef int (*ku_push_fn)(lua_State *L, ku_waiter *w);

struct ku_waiter {
    ku_loop *loop;
    void *owner;
    ku_push_fn push;
    void (*on_timeout)(ku_waiter *w); /* owner hook: forget this waiter, its timeout fired */
    /* owner hook: the wait is abandoned unfinished (a deadlock raised into an
     * in-place wait); forget the waiter and free what only the push would
     * have freed.  on_timeout stands in when this is NULL. */
    void (*on_abandon)(ku_waiter *w);
    void (*on_wake)(ku_waiter *w);    /* owner hook: called by ku_wake before any resume */
    ku_waiter *next;                  /* for the owner's list */
    int done;
    int timed_out;
    int raise;
    /* for the owner: what the wake carries, filled at wake time so the push
     * never needs the owner to still exist */
    void *data;
    int data_ref; /* a registry reference released after the push */
    void *tag;    /* the owner's own bookkeeping, untouched by the loop */
    /* private to the loop */
    lua_State *co;
    int ref;
    ku_driver *driver;
    ku_timer timer;
    int deadline_ref; /* token for the enclosing scope, or LUA_NOREF */
    int deadline_hit;
};

ku_waiter *ku_waiter_new(ku_loop *loop, void *owner, ku_push_fn push);

/* Park the running coroutine on `w` until ku_wake or the timeout (negative:
 * none).  Call as `return ku_wait(L, w, timeout_ms);` from a C function.
 * When the caller cannot yield (a metamethod, a non-yieldable C boundary)
 * the loop is pumped in place instead; the program's other coroutines keep
 * running meanwhile. */
int ku_wait(lua_State *L, ku_waiter *w, int64_t timeout_ms);

/* Owner side: the condition holds; resume the parked coroutine. */
void ku_wake(ku_waiter *w);

/* ---- the loop ------------------------------------------------------------ */

ku_loop *ku_loop_new(lua_State *L, ku_fail *fail);
void ku_loop_free(ku_loop *loop);
ku_loop *ku_loop_of(lua_State *L); /* the loop registered for this state */

HANDLE ku_loop_port(ku_loop *loop);
lua_State *ku_loop_state(ku_loop *loop); /* the main state that owns the loop */
int ku_loop_attach(ku_loop *loop, HANDLE handle, ku_source *src);      /* file/pipe */
int ku_loop_attach_job(ku_loop *loop, HANDLE job, ku_source *src);     /* job messages */
void ku_loop_expect(ku_loop *loop);   /* a packet will arrive (a job is alive) */
void ku_loop_received(ku_loop *loop); /* ...and it did */

/* Run until `main` finishes.  Returns 0, or -1 when every coroutine is
 * parked and nothing can wake them (the deadlock is reported by the caller). */
int ku_loop_run(ku_loop *loop, ku_driver *main);

#endif /* KUU_LOOP_H */

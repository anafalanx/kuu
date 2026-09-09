/* loop.c -- the event loop and coroutine scheduler; see loop.h. */
#include "loop.h"
#include "err.h"

#include "lauxlib.h"

#include <stdlib.h>
#include <string.h>

#define KU_LOOP_KEY "kuu.loop"

typedef struct ready_entry {
    ku_driver *driver;
    int nargs;
    struct ready_entry *next;
} ready_entry;

struct ku_loop {
    lua_State *L;
    HANDLE port;
    ku_timer **heap;
    size_t heap_len, heap_cap;
    ready_entry *ready_head, *ready_tail;
    size_t pending;     /* packets still to arrive: outstanding I/O and live jobs */
    ku_driver *current; /* the driver whose coroutine is running right now */
    int parked;         /* that coroutine parked on a waiter during this resume */
};

/* ---- time ------------------------------------------------------------------ */

int64_t ku_now_ms(void)
{
    static LARGE_INTEGER frequency;
    if (frequency.QuadPart == 0) {
        QueryPerformanceFrequency(&frequency);
    }
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return (int64_t)(now.QuadPart / (frequency.QuadPart / 1000));
}

/* ---- timers: a binary min-heap on due_ms --------------------------------- */

static void heap_swap(ku_loop *lp, size_t a, size_t b)
{
    ku_timer *t = lp->heap[a];
    lp->heap[a] = lp->heap[b];
    lp->heap[b] = t;
    lp->heap[a]->index = a;
    lp->heap[b]->index = b;
}

static void heap_up(ku_loop *lp, size_t i)
{
    while (i > 0) {
        size_t parent = (i - 1) / 2;
        if (lp->heap[parent]->due_ms <= lp->heap[i]->due_ms) {
            break;
        }
        heap_swap(lp, parent, i);
        i = parent;
    }
}

static void heap_down(ku_loop *lp, size_t i)
{
    for (;;) {
        size_t left = 2 * i + 1, right = left + 1, least = i;
        if (left < lp->heap_len && lp->heap[left]->due_ms < lp->heap[least]->due_ms) {
            least = left;
        }
        if (right < lp->heap_len && lp->heap[right]->due_ms < lp->heap[least]->due_ms) {
            least = right;
        }
        if (least == i) {
            break;
        }
        heap_swap(lp, i, least);
        i = least;
    }
}

void ku_timer_init(ku_timer *timer, void (*fire)(ku_timer *), void *owner)
{
    timer->due_ms = 0;
    timer->index = KU_TIMER_IDLE;
    timer->fire = fire;
    timer->owner = owner;
}

int ku_timer_arm(ku_loop *lp, ku_timer *timer, int64_t delay_ms)
{
    ku_timer_cancel(lp, timer);
    if (lp->heap_len == lp->heap_cap) {
        size_t cap = lp->heap_cap ? lp->heap_cap * 2 : 16;
        ku_timer **grown = (ku_timer **)realloc(lp->heap, cap * sizeof *grown);
        if (grown == NULL) {
            return -1;
        }
        lp->heap = grown;
        lp->heap_cap = cap;
    }
    timer->due_ms = ku_now_ms() + (delay_ms < 0 ? 0 : delay_ms);
    timer->index = lp->heap_len;
    lp->heap[lp->heap_len++] = timer;
    heap_up(lp, timer->index);
    return 0;
}

void ku_timer_cancel(ku_loop *lp, ku_timer *timer)
{
    size_t i = timer->index;
    if (i == KU_TIMER_IDLE) {
        return;
    }
    timer->index = KU_TIMER_IDLE;
    lp->heap_len--;
    if (i != lp->heap_len) {
        lp->heap[i] = lp->heap[lp->heap_len];
        lp->heap[i]->index = i;
        heap_down(lp, i);
        heap_up(lp, i);
    }
}

static void fire_due_timers(ku_loop *lp)
{
    int64_t now = ku_now_ms();
    while (lp->heap_len > 0 && lp->heap[0]->due_ms <= now) {
        ku_timer *t = lp->heap[0];
        ku_timer_cancel(lp, t);
        t->fire(t);
    }
}

/* ---- the ready queue -------------------------------------------------------- */

static int enqueue(ku_loop *lp, ku_driver *driver, int nargs)
{
    ready_entry *e = (ready_entry *)malloc(sizeof *e);
    if (e == NULL) {
        return -1;
    }
    e->driver = driver;
    e->nargs = nargs;
    e->next = NULL;
    if (lp->ready_tail != NULL) {
        lp->ready_tail->next = e;
    } else {
        lp->ready_head = e;
    }
    lp->ready_tail = e;
    return 0;
}

static void resume_driver(ku_loop *lp, ku_driver *d, int nargs)
{
    ku_driver *previous = lp->current;
    int previous_parked = lp->parked;
    lp->current = d;
    lp->parked = 0;
    int nresults = 0;
    int status = lua_resume(d->co, lp->L, nargs, &nresults);
    int parked = lp->parked;
    lp->current = previous;
    lp->parked = previous_parked;

    if (status == LUA_YIELD) {
        if (parked) {
            return; /* a waiter owns it now */
        }
        /* A yield that reached the host without a waiter: nothing will ever
         * resume it.  Fail the coroutine with a real error object. */
        lua_settop(d->co, 0);
        ku_err_push(d->co, "SCHED", "yield", "the program yielded with nothing to wait for");
        status = LUA_ERRRUN;
        nresults = 1;
    }
    d->finished = 1;
    d->status = status;
    d->on_finish(d, status == LUA_OK ? nresults : 1);
}

static void drain_ready(ku_loop *lp)
{
    while (lp->ready_head != NULL) {
        ready_entry *e = lp->ready_head;
        lp->ready_head = e->next;
        if (lp->ready_head == NULL) {
            lp->ready_tail = NULL;
        }
        ku_driver *d = e->driver;
        int nargs = e->nargs;
        free(e);
        resume_driver(lp, d, nargs);
    }
}

int ku_driver_start(ku_loop *lp, ku_driver *driver, lua_State *co, int nargs)
{
    driver->co = co;
    driver->finished = 0;
    driver->status = LUA_OK;
    lua_pushthread(co);
    lua_xmove(co, lp->L, 1);
    driver->ref = luaL_ref(lp->L, LUA_REGISTRYINDEX);
    return enqueue(lp, driver, nargs);
}

/* ---- I/O requests ------------------------------------------------------------ */

ku_io *ku_io_new(ku_loop *lp, ku_source *src, HANDLE handle, DWORD cap)
{
    ku_io *io = (ku_io *)calloc(1, sizeof *io);
    if (io == NULL) {
        return NULL;
    }
    if (cap > 0) {
        io->buf = (unsigned char *)malloc(cap);
        if (io->buf == NULL) {
            free(io);
            return NULL;
        }
    }
    io->src = src;
    io->handle = handle;
    io->cap = cap;
    io->loop = lp;
    return io;
}

void ku_io_posted(ku_io *io)
{
    io->loop->pending++;
}

void ku_io_orphan(ku_io *io)
{
    io->src = NULL;
}

void ku_io_free(ku_io *io)
{
    if (io != NULL) {
        free(io->buf);
        free(io);
    }
}

/* ---- waiters ------------------------------------------------------------------ */

static void waiter_timer_fire(ku_timer *timer)
{
    ku_waiter *w = (ku_waiter *)timer->owner;
    w->timed_out = 1;
    if (w->on_timeout != NULL) {
        w->on_timeout(w);
    }
    ku_wake(w);
}

ku_waiter *ku_waiter_new(ku_loop *lp, void *owner, ku_push_fn push)
{
    ku_waiter *w = (ku_waiter *)calloc(1, sizeof *w);
    if (w == NULL) {
        return NULL;
    }
    w->loop = lp;
    w->owner = owner;
    w->push = push;
    w->ref = LUA_NOREF;
    w->data_ref = LUA_NOREF;
    ku_timer_init(&w->timer, waiter_timer_fire, w);
    return w;
}

void ku_wake(ku_waiter *w)
{
    if (w->done) {
        return;
    }
    w->done = 1;
    ku_timer_cancel(w->loop, &w->timer);
    if (w->on_wake != NULL) {
        w->on_wake(w); /* an aggregate may wake its real waiter here */
    }
    if (w->co != NULL) {
        enqueue(w->loop, w->driver, 0);
    }
}

static int pump_once(ku_loop *lp, const int *stop);

static int wait_finish(lua_State *L, int status, lua_KContext ctx)
{
    (void)status;
    ku_waiter *w = (ku_waiter *)ctx;
    if (w->ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, w->ref);
        w->ref = LUA_NOREF;
    }
    if (!w->done) {
        /* The in-place pump found nothing that could wake this waiter. */
        if (w->data_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, w->data_ref);
        }
        free(w);
        return ku_err_raise(L, "SCHED", "deadlock", "nothing can wake this wait");
    }
    int n = w->push(L, w);
    int raise = w->raise;
    if (w->data_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, w->data_ref);
    }
    free(w);
    if (raise) {
        return lua_error(L);
    }
    return n;
}

int ku_wait(lua_State *L, ku_waiter *w, int64_t timeout_ms)
{
    ku_loop *lp = w->loop;
    if (timeout_ms >= 0 && ku_timer_arm(lp, &w->timer, timeout_ms) != 0) {
        free(w);
        return ku_err_raise(L, "SCHED", "oserror", "out of memory arming a timer");
    }
    if (!w->done && lua_isyieldable(L) && lp->current != NULL && lp->current->co == L) {
        w->co = L;
        w->driver = lp->current;
        lua_pushthread(L);
        w->ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lp->parked = 1;
        return lua_yieldk(L, 0, (lua_KContext)w, wait_finish);
    }
    /* Cannot yield here (a metamethod, a foreign coroutine, a C boundary):
     * drive the loop in place until this waiter is done. */
    w->co = NULL;
    while (!w->done) {
        if (pump_once(lp, &w->done) < 0) {
            break;
        }
    }
    return wait_finish(L, LUA_OK, (lua_KContext)w);
}

/* ---- the loop ------------------------------------------------------------------ */

ku_loop *ku_loop_new(lua_State *L, ku_fail *fail)
{
    ku_loop *lp = (ku_loop *)calloc(1, sizeof *lp);
    if (lp == NULL) {
        ku_fail_set(fail, "STATE", "oserror", "out of memory creating the event loop");
        return NULL;
    }
    lp->L = L;
    lp->port = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 1);
    if (lp->port == NULL) {
        free(lp);
        ku_fail_set(fail, "STATE", "oserror", "cannot create the completion port (error %lu)",
                    (unsigned long)GetLastError());
        return NULL;
    }
    lua_pushlightuserdata(L, lp);
    lua_setfield(L, LUA_REGISTRYINDEX, KU_LOOP_KEY);
    return lp;
}

void ku_loop_free(ku_loop *lp)
{
    if (lp == NULL) {
        return;
    }
    while (lp->ready_head != NULL) {
        ready_entry *e = lp->ready_head;
        lp->ready_head = e->next;
        free(e);
    }
    CloseHandle(lp->port);
    free(lp->heap);
    free(lp);
}

ku_loop *ku_loop_of(lua_State *L)
{
    lua_getfield(L, LUA_REGISTRYINDEX, KU_LOOP_KEY);
    ku_loop *lp = (ku_loop *)lua_touserdata(L, -1);
    lua_pop(L, 1);
    return lp;
}

HANDLE ku_loop_port(ku_loop *lp)
{
    return lp->port;
}

lua_State *ku_loop_state(ku_loop *lp)
{
    return lp->L;
}

int ku_loop_attach(ku_loop *lp, HANDLE handle, ku_source *src)
{
    return CreateIoCompletionPort(handle, lp->port, (ULONG_PTR)src, 0) == lp->port ? 0 : -1;
}

int ku_loop_attach_job(ku_loop *lp, HANDLE job, ku_source *src)
{
    JOBOBJECT_ASSOCIATE_COMPLETION_PORT association;
    association.CompletionKey = src;
    association.CompletionPort = lp->port;
    return SetInformationJobObject(job, JobObjectAssociateCompletionPortInformation,
                                   &association, sizeof association)
               ? 0
               : -1;
}

void ku_loop_expect(ku_loop *lp)
{
    lp->pending++;
}

void ku_loop_received(ku_loop *lp)
{
    if (lp->pending > 0) {
        lp->pending--;
    }
}

static void dispatch(ku_loop *lp, const OVERLAPPED_ENTRY *entry)
{
    ku_source *src = (ku_source *)entry->lpCompletionKey;
    if (src == NULL) {
        return;
    }
    if (src->kind == KU_SRC_JOB) {
        src->on_job(src, entry->dwNumberOfBytesTransferred, (DWORD)(ULONG_PTR)entry->lpOverlapped);
        return;
    }
    ku_io *io = (ku_io *)entry->lpOverlapped;
    if (io == NULL) {
        return;
    }
    if (lp->pending > 0) {
        lp->pending--;
    }
    if (io->src == NULL) {
        ku_io_free(io); /* its owner is gone */
        return;
    }
    DWORD bytes = 0, error = 0;
    if (!GetOverlappedResult(io->handle, &io->ov, &bytes, FALSE)) {
        error = GetLastError();
    }
    io->src->on_io(io->src, io, bytes, error);
}

/* Run the ready coroutines, then wait for the next event and handle it.
 * Returns early, without waiting, once `*stop` is set by something that ran.
 * Returns -1 when nothing is ready, no timer is armed, and no packet can
 * arrive: every coroutine is parked forever. */
static int pump_once(ku_loop *lp, const int *stop)
{
    drain_ready(lp);
    fire_due_timers(lp);
    if (lp->ready_head != NULL || (stop != NULL && *stop)) {
        return 0;
    }
    DWORD wait;
    if (lp->heap_len > 0) {
        int64_t delay = lp->heap[0]->due_ms - ku_now_ms();
        wait = delay <= 0 ? 0 : (delay > 0x7fffffff ? 0x7fffffff : (DWORD)delay);
    } else if (lp->pending > 0) {
        wait = INFINITE;
    } else {
        return -1;
    }
    OVERLAPPED_ENTRY entries[64];
    ULONG count = 0;
    if (!GetQueuedCompletionStatusEx(lp->port, entries, 64, &count, wait, FALSE)) {
        count = 0; /* WAIT_TIMEOUT, or an error that a later call will repeat */
    }
    for (ULONG i = 0; i < count; i++) {
        dispatch(lp, &entries[i]);
    }
    fire_due_timers(lp);
    return 0;
}

int ku_loop_run(ku_loop *lp, ku_driver *main)
{
    while (!main->finished) {
        if (pump_once(lp, &main->finished) < 0 && !main->finished) {
            return -1;
        }
    }
    return 0;
}

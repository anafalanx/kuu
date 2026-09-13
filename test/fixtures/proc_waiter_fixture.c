/* Exact ownership checks for production aggregate-wait completion/cleanup.
 * No child process or heap-size heuristic is needed. LTO removes unused proc.c
 * entry points; the tiny wake driver below models completion delivery. */
#include <stdio.h>
#include <stdlib.h>

static void *watched[2];
static unsigned freed[2];
static void counted_free(void *pointer);

#define free counted_free
#include "../../src/proc.c"
#undef free

static void counted_free(void *pointer)
{
    for (int i = 0; i < 2; i++) {
        if (pointer != NULL && pointer == watched[i]) freed[i]++;
    }
    free(pointer);
}

void ku_wake(ku_waiter *w)
{
    if (w->done) return;
    w->done = 1;
    if (w->on_wake != NULL) w->on_wake(w);
    /* Like the real ku_wake, use the waiter after its owner's callback. */
    if (w->co != NULL || !w->done) abort();
}

static int exercise(int completions, int need_all)
{
    ku_child children[2] = {0};
    ku_waiter main_waiter = {0};
    multi_wait *m = calloc(1, sizeof *m);
    if (m == NULL) return 0;
    m->count = m->remaining = 2;
    m->need_all = need_all;
    m->winner = -1;
    m->main = &main_waiter;
    m->subs = calloc(2, sizeof *m->subs);
    m->children = calloc(2, sizeof *m->children);
    m->results = calloc(2, sizeof *m->results);
    if (m->subs == NULL || m->children == NULL || m->results == NULL) abort();
    for (int i = 0; i < 2; i++) {
        ku_waiter *sub = calloc(1, sizeof *sub);
        if (sub == NULL) abort();
        watched[i] = sub;
        freed[i] = 0;
        sub->tag = m;
        sub->on_wake = multi_sub_woken;
        m->subs[i] = sub;
        m->children[i] = &children[i];
        children[i].waiters = sub;
    }
    for (int i = 0; i < completions; i++) {
        ku_waiter *sub = m->subs[i];
        ku_result *result = calloc(1, sizeof *result);
        if (result == NULL) abort();
        result->refs = 1;
        children[i].waiters = NULL; /* child_check_done unlinks before waking */
        sub->data = result;
        ku_wake(sub);
    }
    int woke = completions > 0 && (!need_all || completions == 2);
    int passed = main_waiter.done == woke && freed[0] == 0 && freed[1] == 0;
    multi_cleanup(m);
    passed = passed && freed[0] == 1 && freed[1] == 1
        && children[0].waiters == NULL && children[1].waiters == NULL;
    watched[0] = watched[1] = NULL;
    return passed;
}

int main(void)
{
    if (!exercise(2, 1) || !exercise(1, 0) || !exercise(0, 1) || !exercise(1, 1)) return 1;
    /* A failed allocation of any of the three side arrays also uses cleanup. */
    multi_wait *partial = calloc(1, sizeof *partial);
    if (partial == NULL) return 2;
    partial->count = 2;
    multi_cleanup(partial);
    puts("aggregate waiter ownership: complete, partial, timeout, allocation failure");
    return 0;
}

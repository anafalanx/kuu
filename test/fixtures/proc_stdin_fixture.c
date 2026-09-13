/* Exercise production stdin ownership with a WriteFile that remains pending.
 * The fixture observes the bytes the OS would retain, while the producer
 * reallocates and compacts its queue. No allocator-placement luck is needed. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const unsigned char *pending_bytes;
static DWORD pending_length;
static BOOL pending_write(HANDLE handle, LPCVOID bytes, DWORD length, LPDWORD written, LPOVERLAPPED ov);

#define WriteFile pending_write
#include "../../src/proc.c"
#undef WriteFile

static BOOL pending_write(HANDLE handle, LPCVOID bytes, DWORD length, LPDWORD written, LPOVERLAPPED ov)
{
    (void)handle;
    (void)written;
    (void)ov;
    pending_bytes = bytes;
    pending_length = length;
    SetLastError(ERROR_IO_PENDING);
    return FALSE;
}

ku_io *ku_io_new(ku_loop *loop, ku_source *source, HANDLE handle, DWORD cap)
{
    ku_io *io = calloc(1, sizeof *io);
    if (io == NULL) abort();
    io->buf = cap > 0 ? malloc(cap) : NULL;
    if (cap > 0 && io->buf == NULL) abort();
    io->cap = cap;
    io->loop = loop;
    io->src = source;
    io->handle = handle;
    return io;
}

void ku_io_posted(ku_io *io) { (void)io; }
void ku_io_free(ku_io *io) { free(io->buf); free(io); }
void ku_wake(ku_waiter *waiter) { waiter->done = 1; }

static void complete_write(ku_child *child)
{
    child->in_off += pending_length;
    ku_io_free(child->in_io);
    child->in_io = NULL;
    stdin_post(child);
}

static int all_bytes(unsigned char byte)
{
    for (DWORD i = 0; i < pending_length; i++) {
        if (pending_bytes[i] != byte) return 0;
    }
    return 1;
}

int main(void)
{
    size_t initial = 2 * 1024 * 1024;
    unsigned char *input = malloc(initial * 2);
    if (input == NULL) return 2;
    memset(input, 'a', initial * 2);
    ku_child c = {0};
    c.in_handle = (HANDLE)(uintptr_t)1;
    if (stdin_queue(&c, input, initial) != 0) return 3;
    stdin_post(&c);
    if (c.in_io == NULL || pending_bytes != c.in_io->buf || pending_bytes == c.in_data) return 4;
    const unsigned char *owned = pending_bytes;
    memset(input, 'b', initial * 2);
    if (stdin_queue(&c, input, initial * 2) != 0) return 5;
    if (owned != pending_bytes || pending_length != KU_WRITE_CHUNK || !all_bytes('a')) return 6;
    ku_io_free(c.in_io);
    free(c.in_data);

    /* Complete/replace chunks while a constant 2 MiB backlog stays pending.
     * More than 32 MiB passes through without growing the backing allocation. */
    memset(&c, 0, sizeof c);
    c.in_handle = (HANDLE)(uintptr_t)1;
    memset(input, 'a', initial);
    if (stdin_queue(&c, input, initial) != 0) return 7;
    stdin_post(&c);
    for (int i = 0; i < 512; i++) {
        if (!all_bytes('a')) return 8;
        complete_write(&c);
        if (stdin_queue(&c, input, KU_WRITE_CHUNK) != 0) return 9;
        if (c.in_len - c.in_off != initial || c.in_cap > initial * 2) return 10;
    }
    ku_io_free(c.in_io);
    free(c.in_data);
    free(input);
    puts("stdin ownership and bounded retention");

    /* A ready reader has not consumed its data until its continuation runs.
     * Repeated notifications must not double-count it, and close must still
     * find and cancel it without counting its wake twice. */
    ku_child reader_child = {0};
    read_request request = {READ_LINE, 0, 0};
    ku_waiter reader = {0};
    reader.data = &request;
    reader_child.out.data = (unsigned char *)"payload\n";
    reader_child.out.len = 8;
    reader_child.out.limit = 64;
    reader_child.out.reader = &reader;
    stream_notify(&reader_child, &reader_child.out);
    if (!reader.done || reader_child.woken != 1 || reader_child.out.reader != &reader) return 11;
    stream_notify(&reader_child, &reader_child.out);
    if (reader_child.woken != 1) return 12;
    wake_reader_closed(&reader_child, &reader_child.out);
    if (reader_child.out.reader != NULL || request.mode != READ_CLOSED || reader_child.woken != 1) return 13;
    puts("notified reader reservation and close ownership");
    return 0;
}

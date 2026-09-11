/* Exercise the production dispatcher with real canceled pipe I/O after its
 * source has gone away. Including loop.c keeps this test seam private. */
#include "loop.c"
#include <stdio.h>

int main(void)
{
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    int result = 1;
    ku_loop loop = {0};
    HANDLE reader = INVALID_HANDLE_VALUE, writer = INVALID_HANDLE_VALUE;
    ku_source *source = NULL;
    ku_io *io = NULL;
    int posted = 0;
    wchar_t name[128];
    swprintf(name, sizeof name / sizeof *name, L"\\\\.\\pipe\\kuu-orphan-%lu",
             (unsigned long)GetCurrentProcessId());
    loop.port = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 1);
    if (loop.port == NULL) goto done;
    source = VirtualAlloc(NULL, sizeof *source, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (source == NULL) goto done;
    source->kind = KU_SRC_IO;
    reader = CreateNamedPipeW(name, PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED,
                             PIPE_TYPE_BYTE | PIPE_WAIT, 1, 1024, 1024, 0, NULL);
    if (reader == INVALID_HANDLE_VALUE) goto done;
    writer = CreateFileW(name, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
    if (writer == INVALID_HANDLE_VALUE) goto done;
    if (ku_loop_attach(&loop, reader, source) != 0) goto done;
    io = ku_io_new(&loop, source, reader, 16);
    if (io == NULL) goto done;
    io->ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (io->ov.hEvent == NULL) goto done;
    if (ReadFile(reader, io->buf, io->cap, NULL, &io->ov) ||
        GetLastError() != ERROR_IO_PENDING) goto done;
    ku_io_posted(io);
    posted = 1;
    if (!CancelIoEx(reader, &io->ov)) goto done;
    if (WaitForSingleObject(io->ov.hEvent, 5000) != WAIT_OBJECT_0) goto done;
    ku_io_orphan(io);
    /* Decommit makes the source's ended lifetime deterministic: old dispatch
     * read its completion key here before checking the orphan marker. */
    if (!VirtualFree(source, 0, MEM_RELEASE)) goto done;
    source = NULL;
    OVERLAPPED_ENTRY entry;
    ULONG count = 0;
    if (!GetQueuedCompletionStatusEx(loop.port, &entry, 1, &count, 5000, FALSE) ||
        count != 1 || entry.lpOverlapped != &io->ov) goto done;
    dispatch(&loop, &entry);
    io = NULL;
    posted = 0;
    if (loop.pending != 0) goto done;
    puts("orphaned completion safely dispatched");
    result = 0;

done:
    if (result != 0) fprintf(stderr, "orphaned completion fixture failed (error %lu)\n",
                             (unsigned long)GetLastError());
    if (posted) {
        CancelIoEx(reader, &io->ov);
        WaitForSingleObject(io->ov.hEvent, INFINITE);
    }
    ku_io_free(io);
    if (source != NULL) VirtualFree(source, 0, MEM_RELEASE);
    if (reader != INVALID_HANDLE_VALUE) CloseHandle(reader);
    if (writer != INVALID_HANDLE_VALUE) CloseHandle(writer);
    if (loop.port != NULL) CloseHandle(loop.port);
    return result;
}

/* Hold a file or directory without sharing until the parent sends one byte.
 * Tests pass an ASCII relative path beneath the fixture's working directory. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    HANDLE file = CreateFileA(argv[1], GENERIC_READ, 0, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "cannot lock input: %lu\n", (unsigned long)GetLastError());
        return 1;
    }
    puts("LOCKED");
    fflush(stdout);
    (void)getchar();
    CloseHandle(file);
    return 0;
}

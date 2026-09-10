/* Bounded child workloads for the Job Object limits tests. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        return 2;
    }
    if (strcmp(argv[1], "memory") == 0) {
        void *memory = VirtualAlloc(NULL, (SIZE_T)1024 * 1024 * 1024, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
        printf("allocation=%s\n", memory == NULL ? "refused" : "accepted");
        fflush(stdout);
        Sleep(10000); /* keep the process alive until the notification is consumed */
        if (memory != NULL) {
            VirtualFree(memory, 0, MEM_RELEASE);
        }
        return 0;
    }
    if (strcmp(argv[1], "cpu") == 0) {
        volatile unsigned long long counter = 0;
        ULONGLONG end = GetTickCount64() + 10000;
        while (GetTickCount64() < end) {
            for (unsigned i = 0; i < 100000; i++) {
                counter++;
            }
        }
        return counter == 0;
    }
    return 2;
}

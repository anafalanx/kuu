/* An actual console client: pipe-only launches cannot satisfy ReadConsoleW. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE), output = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode = 0, written = 0;
    if (!GetConsoleMode(input, &mode) || !GetConsoleMode(output, &mode)) {
        fputs("not a console\n", stderr);
        return 7;
    }
    if (argc > 1 && strcmp(argv[1], "volume") == 0) {
        const wchar_t line[] = L"abcdefghijklmnopqrstuvwxyz0123456789\r\n";
        for (int i = 0; i < 4000; i++) {
            if (!WriteConsoleW(output, line, (DWORD)(sizeof line / sizeof *line - 1), &written, NULL)) return 8;
        }
        WriteConsoleW(output, L"VOLUME-DONE\r\n", 13, &written, NULL);
        return 0;
    }
    WriteConsoleW(output, L"Console input:", 14, &written, NULL);
    wchar_t line[128];
    DWORD read = 0;
    if (!ReadConsoleW(input, line, 127, &read, NULL)) return 9;
    WriteConsoleW(output, L"received:", 9, &written, NULL);
    WriteConsoleW(output, line, read, &written, NULL);
    CONSOLE_SCREEN_BUFFER_INFO screen;
    if (!GetConsoleScreenBufferInfo(output, &screen)) return 10;
    char size[80];
    int n = snprintf(size, sizeof size, "size:%d,%d\r\n", screen.dwSize.X, screen.dwSize.Y);
    WriteFile(output, size, (DWORD)n, &written, NULL);
    return 0;
}

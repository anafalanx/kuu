/* Deterministic argv fuzzing against Windows' parser; never executes input. */
#include "cmdline.h"
#include "wintext.h"

#include <windows.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static uint32_t state;
static unsigned pick(unsigned limit)
{
    state = state * UINT32_C(1664525) + UINT32_C(1013904223);
    return (state >> 8) % limit;
}

static void dump(int argc, const char *const *argv)
{
    for (int i = 0; i < argc; i++) {
        fprintf(stderr, "argv[%d] hex=", i);
        for (const unsigned char *p = (const unsigned char *)argv[i]; *p; p++) {
            fprintf(stderr, "%02x", (unsigned)*p);
        }
        fputc('\n', stderr);
    }
}

static int check(int argc, const char *const *argv)
{
    char *line = ku_make_cmdline(argc, argv);
    wchar_t *wide = line ? ku_utf8_to_wide(line) : NULL;
    int count = 0;
    wchar_t **parsed = wide ? CommandLineToArgvW(wide, &count) : NULL;
    int ok = parsed != NULL && count == argc;
    for (int i = 0; ok && i < argc; i++) {
        wchar_t *expected = ku_utf8_to_wide(argv[i]);
        ok = expected != NULL && wcscmp(parsed[i], expected) == 0;
        free(expected);
    }
    if (parsed != NULL) LocalFree(parsed);
    free(wide);
    free(line);

    /* Batch safety has a different grammar. Exercise accepted strings and
     * explicit CR/LF rejection, without invoking a shell on fuzzed text. */
    int newline = 0;
    for (int i = 1; i < argc; i++) {
        if (strpbrk(argv[i], "\r\n") != NULL) newline = 1;
    }
    char *batch = NULL;
    const char *error = NULL;
    int result = ku_make_batch_cmdline("C:\\project space\\build.cmd", argc - 1, argv + 1, &batch, &error);
    ok = ok && (newline ? result == -1 && batch == NULL && error != NULL
                        : result == 0 && batch != NULL && error == NULL);
    free(batch);
    if (!ok) dump(argc, argv);
    return ok;
}

int main(int argc, char **argv)
{
    if (argc != 3) return 2;
    char *end = NULL;
    unsigned long cases = strtoul(argv[1], &end, 10);
    if (*end || cases == 0 || cases > 1000000) return 2;
    unsigned long seed = strtoul(argv[2], &end, 10);
    if (*end || seed == 0) return 2;
    state = (uint32_t)seed;
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    static const char *const corpus[] = {
        "", " ", "\t", "\\", "\"", "\\\"", "x \\", "\\\\\" x\\\\", "\r\n",
        "%PATH%", "!x! & | < > ^ ( )", "\xc3\xa9", "\xe6\xbc\xa2\xe5\xad\x97", "\xf0\x9f\x8c\x99",
    };
    for (size_t i = 0; i < sizeof corpus / sizeof *corpus; i++) {
        const char *args[] = { "kuu.exe", corpus[i] };
        if (!check(2, args)) return 1;
    }
    static const char *const tokens[] = {
        "a", "0", " ", "\t", "\\", "\"", "\r", "\n", "%", "!", "^", "&", "|", "<", ">", "(", ")",
        "\xc3\xa9", "\xe6\xbc\xa2", "\xf0\x9f\x8c\x99",
    };
    for (unsigned long iteration = 1; iteration <= cases; iteration++) {
        char storage[8][4097];
        const char *args[9] = { "kuu.exe" }; /* argv[0] has special Windows rules. */
        int count = 1 + (int)pick(8);
        for (int i = 1; i <= count; i++) {
            size_t length = 0;
            unsigned n = pick(iteration % 100 == 0 ? 1025 : 65);
            for (unsigned j = 0; j < n; j++) {
                const char *token = tokens[pick((unsigned)(sizeof tokens / sizeof *tokens))];
                size_t bytes = strlen(token);
                memcpy(storage[i - 1] + length, token, bytes);
                length += bytes;
            }
            storage[i - 1][length] = '\0';
            args[i] = storage[i - 1];
        }
        if (!check(count + 1, args)) {
            fprintf(stderr, "command-line fuzz failed: seed=%lu case=%lu\n", seed, iteration);
            return 1;
        }
    }
    printf("command-line fuzz: %lu cases, seed %lu passed\n", cases, seed);
    return 0;
}

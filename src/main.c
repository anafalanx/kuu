/*
 * main.c -- kuu's entry: routes, the program coroutine, and error reporting.
 *
 * Routes:
 *   kuu FILE [arg ...]        run a program file
 *   kuu - [arg ...]           run a program read from standard input
 *   kuu -e SCRIPT [arg ...]   run an inline script
 *   kuu --version | --help
 *
 * The program runs inside a coroutine the host creates.  In this milestone
 * nothing waits, so a yield reaching the host is an error; from the scheduler
 * milestone on, palette calls yield here and completions resume.  Arguments
 * reach the main chunk as `...` and as require("rt").args.  Standard streams
 * are binary: what the program writes is what leaves the process.
 */
#include "kuu.h"
#include "program.h"
#include "state.h"
#include "wintext.h"

#include "lauxlib.h"
#include "lua.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(FILE *to)
{
    fputs(KUU_NAME " " KUU_VERSION " -- a Lua 5.5 runtime for agents on Windows\n"
          "usage: kuu FILE [arg ...]        run a Lua program file\n"
          "       kuu - [arg ...]           run a program read from standard input\n"
          "       kuu -e SCRIPT [arg ...]   run an inline script\n"
          "       kuu --version | --help\n",
          to);
}

static int report_fail(const ku_fail *fail)
{
    fprintf(stderr, "%s: %s %s: %s\n", KUU_NAME, fail->domain, fail->code, fail->message);
    return KUU_EXIT_ENTRY;
}

static int usage_fail(const char *message)
{
    fprintf(stderr, "%s: ENTRY usage: %s\n", KUU_NAME, message);
    usage(stderr);
    return KUU_EXIT_ENTRY;
}

static int protected_tostring(lua_State *L)
{
    luaL_tolstring(L, 1, NULL);
    return 1;
}

/* The error object is on top of `co`.  Print "kuu: message" and the
 * coroutine's traceback, leaving `co`'s stack intact for lua_closethread. */
static void report_error(lua_State *L, lua_State *co)
{
    lua_xmove(co, L, 1);
    int type = lua_type(L, -1);
    if (type == LUA_TSTRING || type == LUA_TNUMBER) {
        lua_tostring(L, -1);
    } else if (luaL_getmetafield(L, -1, "__tostring") != LUA_TNIL) {
        lua_pop(L, 1);
        lua_pushcfunction(L, protected_tostring);
        lua_insert(L, -2);
        if (lua_pcall(L, 1, 1, 0) != LUA_OK || lua_type(L, -1) != LUA_TSTRING) {
            lua_pop(L, 1);
            lua_pushliteral(L, "(error object cannot be converted to a string)");
        }
    } else {
        const char *name = luaL_typename(L, -1);
        lua_pop(L, 1);
        lua_pushfstring(L, "(error object is a %s value)", name);
    }
    luaL_traceback(L, co, lua_tostring(L, -1), 0);
    fprintf(stderr, "%s: %s\n", KUU_NAME, lua_tostring(L, -1));
    lua_pop(L, 2);
}

static int run_program(const ku_launch *launch, const ku_program *program,
                       const char *chunkname)
{
    ku_fail fail;
    lua_State *L = ku_state_new(launch, &fail);
    if (L == NULL) {
        return report_fail(&fail);
    }
    lua_State *co = lua_newthread(L);
    int status = luaL_loadbufferx(co, program->text, program->length, chunkname, "t");
    if (status != LUA_OK) {
        const char *message = lua_tostring(co, -1);
        fprintf(stderr, "%s: %s\n", KUU_NAME,
                message != NULL ? message : "cannot load the program");
        lua_close(L);
        return KUU_EXIT_PROGRAM;
    }
    for (int i = 0; i < launch->argc; i++) {
        lua_pushstring(co, launch->argv[i]);
    }
    int results = 0;
    status = lua_resume(co, L, launch->argc, &results);
    int exit_code = KUU_EXIT_OK;
    if (status == LUA_YIELD) {
        fprintf(stderr, "%s: SCHED yield: the program yielded with nothing to wait for\n",
                KUU_NAME);
        exit_code = KUU_EXIT_PROGRAM;
    } else if (status != LUA_OK) {
        report_error(L, co);
        exit_code = KUU_EXIT_PROGRAM;
    }
    /* Close pending to-be-closed variables, whether the program finished,
     * failed, or yielded.  An error raised while closing is a failure too. */
    if (lua_closethread(co, L) != LUA_OK) {
        const char *message = lua_tostring(co, -1);
        fprintf(stderr, "%s: error while closing: %s\n", KUU_NAME,
                message != NULL ? message : "(error object is not a string)");
        exit_code = KUU_EXIT_PROGRAM;
    }
    lua_close(L);
    return exit_code;
}

static char *executable_path_utf8(void)
{
    DWORD capacity = 512;
    for (;;) {
        wchar_t *buffer = (wchar_t *)malloc(capacity * sizeof(wchar_t));
        if (buffer == NULL) {
            return NULL;
        }
        DWORD n = GetModuleFileNameW(NULL, buffer, capacity);
        if (n == 0) {
            free(buffer);
            return NULL;
        }
        if (n < capacity - 1) {
            char *utf8 = ku_wide_to_utf8(buffer, -1);
            free(buffer);
            return utf8;
        }
        free(buffer);
        if (capacity >= 65536) {
            return NULL;
        }
        capacity *= 2;
    }
}

static char *current_directory_utf8(void)
{
    DWORD n = GetCurrentDirectoryW(0, NULL);
    if (n == 0) {
        return NULL;
    }
    wchar_t *buffer = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (buffer == NULL) {
        return NULL;
    }
    if (GetCurrentDirectoryW(n, buffer) == 0) {
        free(buffer);
        return NULL;
    }
    char *utf8 = ku_wide_to_utf8(buffer, -1);
    free(buffer);
    return utf8;
}

/* The directory holding a program file, absolute, UTF-8, no trailing separator
 * (except for a drive root such as "C:\"). */
static char *program_directory_utf8(const wchar_t *program)
{
    DWORD n = GetFullPathNameW(program, 0, NULL, NULL);
    if (n == 0) {
        return NULL;
    }
    wchar_t *full = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (full == NULL) {
        return NULL;
    }
    wchar_t *file_part = NULL;
    if (GetFullPathNameW(program, n, full, &file_part) == 0 || file_part == NULL) {
        free(full);
        return NULL;
    }
    size_t length = (size_t)(file_part - full);
    while (length > 0 && (full[length - 1] == L'\\' || full[length - 1] == L'/')) {
        if (length == 3 && full[1] == L':') {
            break; /* keep "C:\" */
        }
        length--;
    }
    char *utf8 = ku_wide_to_utf8(full, (int)length);
    free(full);
    return utf8;
}

int wmain(int argc, wchar_t **argv)
{
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);

    if (argc < 2) {
        usage(stderr);
        return KUU_EXIT_ENTRY;
    }
    char **words = (char **)calloc((size_t)argc, sizeof(char *));
    if (words == NULL) {
        fprintf(stderr, "%s: ENTRY oserror: out of memory\n", KUU_NAME);
        return KUU_EXIT_ENTRY;
    }
    for (int i = 1; i < argc; i++) {
        words[i] = ku_wide_to_utf8(argv[i], -1);
        if (words[i] == NULL) {
            fprintf(stderr, "%s: ENTRY encoding: argument %d is not valid UTF-16\n",
                    KUU_NAME, i);
            return KUU_EXIT_ENTRY;
        }
    }

    const char *first = words[1];
    if (strcmp(first, "--version") == 0) {
        printf("%s %s (%s)\n", KUU_NAME, KUU_VERSION, LUA_RELEASE);
        return KUU_EXIT_OK;
    }
    if (strcmp(first, "--help") == 0) {
        usage(stdout);
        return KUU_EXIT_OK;
    }

    ku_launch launch;
    memset(&launch, 0, sizeof launch);
    launch.exe = executable_path_utf8();
    if (launch.exe == NULL) {
        fprintf(stderr, "%s: ENTRY oserror: cannot determine the executable path\n", KUU_NAME);
        return KUU_EXIT_ENTRY;
    }

    ku_program program;
    ku_fail fail;
    const char *chunkname;
    if (strcmp(first, "-e") == 0) {
        if (argc < 3) {
            return usage_fail("-e needs a script: kuu -e SCRIPT [arg ...]");
        }
        launch.route = "eval";
        launch.root = current_directory_utf8();
        launch.argc = argc - 3;
        launch.argv = (const char *const *)(words + 3);
        size_t length = strlen(words[2]);
        unsigned char *bytes = (unsigned char *)malloc(length > 0 ? length : 1);
        if (bytes == NULL) {
            fprintf(stderr, "%s: ENTRY oserror: out of memory\n", KUU_NAME);
            return KUU_EXIT_ENTRY;
        }
        memcpy(bytes, words[2], length);
        if (ku_program_from_bytes(bytes, length, "the inline script", &program, &fail) != 0) {
            return report_fail(&fail);
        }
        chunkname = "=(command line)";
    } else if (strcmp(first, "-") == 0) {
        launch.route = "stdin";
        launch.root = current_directory_utf8();
        launch.argc = argc - 2;
        launch.argv = (const char *const *)(words + 2);
        if (ku_program_read_stdin(&program, &fail) != 0) {
            return report_fail(&fail);
        }
        chunkname = "=stdin";
    } else if (first[0] == '-') {
        char message[256];
        snprintf(message, sizeof message, "unknown option '%s'", first);
        return usage_fail(message);
    } else {
        launch.route = "file";
        launch.program = first;
        launch.root = program_directory_utf8(argv[1]);
        launch.argc = argc - 2;
        launch.argv = (const char *const *)(words + 2);
        char what[KU_PROGRAM_WHAT_MAX];
        snprintf(what, sizeof what, "program file '%s'", first);
        if (ku_program_read_file(argv[1], what, &program, &fail) != 0) {
            return report_fail(&fail);
        }
        size_t length = strlen(first) + 2;
        char *name = (char *)malloc(length);
        if (name == NULL) {
            fprintf(stderr, "%s: ENTRY oserror: out of memory\n", KUU_NAME);
            return KUU_EXIT_ENTRY;
        }
        snprintf(name, length, "@%s", first);
        chunkname = name;
    }
    if (launch.root == NULL) {
        fprintf(stderr, "%s: ENTRY oserror: cannot determine the program directory\n", KUU_NAME);
        return KUU_EXIT_ENTRY;
    }
    int exit_code = run_program(&launch, &program, chunkname);
    ku_program_free(&program);
    return exit_code;
}

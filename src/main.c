/*
 * main.c -- kuu's entry: routes, the program coroutine, and error reporting.
 *
 * Routes:
 *   kuu FILE [arg ...]        run a program file
 *   kuu - [arg ...]           run a program read from standard input
 *   kuu -e SCRIPT [arg ...]   run an inline script
 *   kuu version | --version | --help
 *
 * The program runs inside a coroutine the host creates.  In this milestone
 * nothing waits, so a yield reaching the host is an error; from the scheduler
 * milestone on, palette calls yield here and completions resume.  Arguments
 * reach the main chunk as `...` and as require("rt").args.  Standard streams
 * are binary: what the program writes is what leaves the process.
 */
#include "kuu.h"
#include "loop.h"
#include "payload.h"
#include "program.h"
#include "state.h"
#include "wintext.h"

#include "lauxlib.h"
#include "lua.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The mingw C runtime expands wildcards in argv unless told not to.  A program
 * that receives "*.lua" must receive the four characters, not a listing. */
int _CRT_glob = 0;

static int usage_fail(const char *message);

static void usage(FILE *to)
{
    fputs(KUU_NAME " " KUU_VERSION " -- a Lua 5.5 runtime for agents on Windows\n"
          "usage: kuu FILE [arg ...]        run a Lua program file\n"
          "       kuu - [arg ...]           run a program read from standard input\n"
          "       kuu -e SCRIPT [arg ...]   run an inline script\n"
          "       kuu docs [PAGE | search TEXT]   the manual, from inside the executable\n"
          "       kuu run [TASK [arg ...]]  run a task from the nearest tasks.lua\n"
          "       kuu list [--json]         list those tasks\n"
          "       kuu check [--json] [PATH ...]   parse, global declarations, requires\n"
          "       kuu version | --version | --help\n",
          to);
}

/* ---- the manual, carried in the executable ------------------------------- */

static int page_name_length(const char *name)
{
    /* "docs/proc.md" -> the length of "proc" */
    const char *slash = strchr(name, '/');
    const char *base = slash != NULL ? slash + 1 : name;
    const char *dot = strrchr(base, '.');
    return (int)((dot != NULL ? dot : base + strlen(base)) - base);
}

static int docs_route(int argc, const char *const *argv)
{
    if (argc == 0) {
        printf("kuu %s manual. Pages:\n", KUU_VERSION);
        for (const ku_payload_entry *e = ku_payload; e->name != NULL; e++) {
            if (strncmp(e->name, "docs/", 5) == 0) {
                printf("  %.*s\n", page_name_length(e->name), e->name + 5);
            }
        }
        printf("\nkuu docs PAGE prints a page; kuu docs search TEXT finds lines.\n");
        return KUU_EXIT_OK;
    }
    if (strcmp(argv[0], "search") == 0) {
        if (argc < 2) {
            return usage_fail("docs search needs text to look for");
        }
        const char *needle = argv[1];
        size_t needle_length = strlen(needle);
        int hits = 0;
        for (const ku_payload_entry *e = ku_payload; e->name != NULL; e++) {
            if (strncmp(e->name, "docs/", 5) != 0) {
                continue;
            }
            const char *text = (const char *)e->bytes;
            int line = 1;
            for (const char *p = text; *p != '\0'; line++) {
                const char *end = strchr(p, '\n');
                size_t length = end != NULL ? (size_t)(end - p) : strlen(p);
                for (size_t i = 0; i + needle_length <= length; i++) {
                    if (_strnicmp(p + i, needle, needle_length) == 0) {
                        printf("%.*s:%d: %.*s\n", page_name_length(e->name), e->name + 5, line, (int)length, p);
                        hits++;
                        break;
                    }
                }
                if (end == NULL) {
                    break;
                }
                p = end + 1;
            }
        }
        if (hits == 0) {
            printf("nothing in the manual mentions '%s'\n", needle);
        }
        return KUU_EXIT_OK;
    }
    char name[256];
    snprintf(name, sizeof name, "docs/%s.md", argv[0]);
    const ku_payload_entry *e = ku_payload_find(name);
    if (e == NULL) {
        fprintf(stderr, "%s: ENTRY notfound: no manual page '%s'; kuu docs lists them\n", KUU_NAME, argv[0]);
        return KUU_EXIT_ENTRY;
    }
    fwrite(e->bytes, 1, e->length, stdout);
    return KUU_EXIT_OK;
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

static void main_finished(ku_driver *driver, int nresults)
{
    (void)driver; /* the loop records the status; main reads it below */
    (void)nresults;
}

static int run_program(const ku_launch *launch, const ku_program *program,
                       const char *chunkname)
{
    ku_fail fail;
    lua_State *L = ku_state_new(launch, &fail);
    if (L == NULL) {
        return report_fail(&fail);
    }
    ku_loop *loop = ku_loop_new(L, &fail);
    if (loop == NULL) {
        lua_close(L);
        return report_fail(&fail);
    }
    lua_State *co = lua_newthread(L);
    int status = luaL_loadbufferx(co, program->text, program->length, chunkname, "t");
    if (status != LUA_OK) {
        const char *message = lua_tostring(co, -1);
        fprintf(stderr, "%s: %s\n", KUU_NAME,
                message != NULL ? message : "cannot load the program");
        lua_close(L);
        ku_loop_free(loop);
        return KUU_EXIT_PROGRAM;
    }
    for (int i = 0; i < launch->argc; i++) {
        lua_pushstring(co, launch->argv[i]);
    }
    /* The program is the first coroutine the loop drives.  Palette calls
     * that wait park it; completions resume it; it ends when it returns. */
    ku_driver driver;
    memset(&driver, 0, sizeof driver);
    driver.on_finish = main_finished;
    if (ku_driver_start(loop, &driver, co, launch->argc) != 0) {
        fprintf(stderr, "%s: STATE oserror: out of memory\n", KUU_NAME);
        lua_close(L);
        ku_loop_free(loop);
        return KUU_EXIT_ENTRY;
    }
    int exit_code = KUU_EXIT_OK;
    if (ku_loop_run(loop, &driver) < 0) {
        fprintf(stderr, "%s: SCHED deadlock: every task is waiting and nothing can wake them\n",
                KUU_NAME);
        exit_code = KUU_EXIT_PROGRAM;
    } else if (driver.status != LUA_OK) {
        report_error(L, co);
        exit_code = KUU_EXIT_PROGRAM;
    }
    /* Close pending to-be-closed variables, whether the program finished,
     * failed, or was left parked.  lua_closethread reports a thread's original
     * error status again, so only a program that finished cleanly can learn
     * something new here: an error raised by a __close handler. */
    int close_status = lua_closethread(co, L);
    if (driver.status == LUA_OK && close_status != LUA_OK) {
        const char *message = lua_tostring(co, -1);
        fprintf(stderr, "%s: error while closing: %s\n", KUU_NAME,
                message != NULL ? message : "(error object is not a string)");
        exit_code = KUU_EXIT_PROGRAM;
    }
    lua_close(L); /* collects every child handle: their jobs close, their trees die */
    ku_loop_free(loop);
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

/* A structured exception anywhere in kuu is a defect in kuu.  Windows would
 * end the process silently, or worse, with a dialog no agent can click; kuu
 * says what and where on standard error and exits with a code of its own.
 * Only WriteFile is used here: the C runtime may be the thing that broke. */
static LONG WINAPI crash_filter(EXCEPTION_POINTERS *info)
{
    const EXCEPTION_RECORD *record = info->ExceptionRecord;
    const char *what = "structured exception";
    switch (record->ExceptionCode) {
    case EXCEPTION_ACCESS_VIOLATION:
        what = "access violation";
        break;
    case EXCEPTION_STACK_OVERFLOW:
        what = "stack overflow";
        break;
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
        what = "integer division by zero";
        break;
    case EXCEPTION_ILLEGAL_INSTRUCTION:
        what = "illegal instruction";
        break;
    case EXCEPTION_IN_PAGE_ERROR:
        what = "in-page error";
        break;
    default:
        break;
    }
    HMODULE module = NULL;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCWSTR)record->ExceptionAddress, &module);
    unsigned long long offset =
        module != NULL ? (unsigned long long)((const char *)record->ExceptionAddress - (const char *)module) : 0;
    char text[320];
    int n = snprintf(text, sizeof text,
                     "%s: crashed: %s (0x%08lx) at %s+0x%llx; this is a defect in %s itself\n", KUU_NAME, what,
                     (unsigned long)record->ExceptionCode,
                     module == NULL ? "an unknown address" : (module == GetModuleHandleW(NULL) ? KUU_NAME : "a system module"),
                     offset, KUU_NAME);
    if (n > 0) {
        DWORD written = 0;
        WriteFile(GetStdHandle(STD_ERROR_HANDLE), text, (DWORD)n, &written, NULL);
    }
    ExitProcess(KUU_EXIT_CRASH);
    return EXCEPTION_EXECUTE_HANDLER;
}

/* Routes borrow argv; their early returns cannot leak its conversion. */
static int run_entry(int argc, wchar_t **argv, char **words)
{
    const char *first = words[1];
    if (strcmp(first, "--version") == 0 || strcmp(first, "version") == 0) {
        if (argc != 2) return usage_fail("version takes no arguments; use ./version to run a file");
        printf("%s %s (%s)\n", KUU_NAME, KUU_VERSION, LUA_RELEASE);
        return KUU_EXIT_OK;
    }
    if (strcmp(first, "--help") == 0) {
        usage(stdout);
        return KUU_EXIT_OK;
    }
    if (strcmp(first, "docs") == 0) {
        return docs_route(argc - 2, (const char *const *)(words + 2));
    }
    if (strcmp(first, "--crash-test") == 0) {
        /* The crash handler's own test: a real access violation, raised. */
        RaiseException(EXCEPTION_ACCESS_VIOLATION, EXCEPTION_NONCONTINUABLE, 0, NULL);
        return KUU_EXIT_ENTRY;
    }
    /* Verbs are Lua programs carried in the payload under lua/cmd; they run
     * like any program, with the arguments after the verb. */
    char verb_name[128];
    if (first[0] != '-' && strlen(first) < 100) {
        snprintf(verb_name, sizeof verb_name, "lua/cmd/%s.lua", first);
        const ku_payload_entry *verb = ku_payload_find(verb_name);
        if (verb != NULL) {
            ku_launch launch;
            memset(&launch, 0, sizeof launch);
            launch.exe = executable_path_utf8();
            launch.route = "cmd";
            launch.program = first;
            launch.root = current_directory_utf8();
            launch.argc = argc - 2;
            launch.argv = (const char *const *)(words + 2);
            if (launch.exe == NULL || launch.root == NULL) {
                fprintf(stderr, "%s: ENTRY oserror: cannot determine the executable or current directory\n", KUU_NAME);
                free((void *)launch.exe);
                free((void *)launch.root);
                return KUU_EXIT_ENTRY;
            }
            ku_program program;
            program.owned = NULL;
            program.text = (const char *)verb->bytes;
            program.length = verb->length;
            char chunkname[160];
            snprintf(chunkname, sizeof chunkname, "=kuu/%s", verb_name);
            int exit_code = run_program(&launch, &program, chunkname);
            free((void *)launch.exe);
            free((void *)launch.root);
            return exit_code;
        }
    }

    ku_launch launch;
    memset(&launch, 0, sizeof launch);
    launch.exe = executable_path_utf8();
    if (launch.exe == NULL) {
        fprintf(stderr, "%s: ENTRY oserror: cannot determine the executable path\n", KUU_NAME);
        return KUU_EXIT_ENTRY;
    }

    ku_program program = {0};
    ku_fail fail;
    const char *chunkname;
    char *owned_chunkname = NULL;
    int exit_code = KUU_EXIT_ENTRY;
    if (strcmp(first, "-e") == 0) {
        if (argc < 3) {
            exit_code = usage_fail("-e needs a script: kuu -e SCRIPT [arg ...]");
            goto done;
        }
        launch.route = "eval";
        launch.root = current_directory_utf8();
        launch.argc = argc - 3;
        launch.argv = (const char *const *)(words + 3);
        size_t length = strlen(words[2]);
        unsigned char *bytes = (unsigned char *)malloc(length > 0 ? length : 1);
        if (bytes == NULL) {
            fprintf(stderr, "%s: ENTRY oserror: out of memory\n", KUU_NAME);
            goto done;
        }
        memcpy(bytes, words[2], length);
        if (ku_program_from_bytes(bytes, length, "the inline script", &program, &fail) != 0) {
            exit_code = report_fail(&fail);
            goto done;
        }
        chunkname = "=(command line)";
    } else if (strcmp(first, "-") == 0) {
        launch.route = "stdin";
        launch.root = current_directory_utf8();
        launch.argc = argc - 2;
        launch.argv = (const char *const *)(words + 2);
        if (ku_program_read_stdin(&program, &fail) != 0) {
            exit_code = report_fail(&fail);
            goto done;
        }
        chunkname = "=stdin";
    } else if (first[0] == '-') {
        char message[256];
        snprintf(message, sizeof message, "unknown option '%s'", first);
        exit_code = usage_fail(message);
        goto done;
    } else {
        launch.route = "file";
        launch.program = first;
        launch.root = program_directory_utf8(argv[1]);
        launch.argc = argc - 2;
        launch.argv = (const char *const *)(words + 2);
        char what[KU_PROGRAM_WHAT_MAX];
        snprintf(what, sizeof what, "program file '%s'", first);
        if (ku_program_read_file(argv[1], what, &program, &fail) != 0) {
            exit_code = report_fail(&fail);
            goto done;
        }
        size_t length = strlen(first) + 2;
        char *name = (char *)malloc(length);
        if (name == NULL) {
            fprintf(stderr, "%s: ENTRY oserror: out of memory\n", KUU_NAME);
            goto done;
        }
        snprintf(name, length, "@%s", first);
        chunkname = name;
        owned_chunkname = name;
    }
    if (launch.root == NULL) {
        fprintf(stderr, "%s: ENTRY oserror: cannot determine the program directory\n", KUU_NAME);
        goto done;
    }
    exit_code = run_program(&launch, &program, chunkname);
done:
    free(owned_chunkname);
    ku_program_free(&program);
    free((void *)launch.exe);
    free((void *)launch.root);
    return exit_code;
}

int wmain(int argc, wchar_t **argv)
{
    /* No dialog ever: an agent cannot click.  The crash filter reports and
     * exits; the stack guarantee lets it run even after a stack overflow. */
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
    SetUnhandledExceptionFilter(crash_filter);
    ULONG guarantee = 64 * 1024;
    SetThreadStackGuarantee(&guarantee);

    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    /* The C runtime converts narrow paths (io.open) with the LC_CTYPE code
     * page.  UTF-8 there makes Lua's own file functions agree with the rest
     * of kuu; collation and numerics stay in the "C" locale, so string order
     * and the decimal point are unchanged. */
    setlocale(LC_CTYPE, ".UTF8");

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
            for (int j = 1; j < i; j++) free(words[j]);
            free(words);
            return KUU_EXIT_ENTRY;
        }
    }

    int exit_code = run_entry(argc, argv, words);
    for (int i = 1; i < argc; i++) free(words[i]);
    free(words);
    return exit_code;
}

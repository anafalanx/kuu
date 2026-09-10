/* Private archive.list worker. The public Lua API runs this in a supervised
 * copy of kuu, so compressed input cannot block the parent's event loop and
 * its deadline can terminate the entire reader. No files are extracted.
 * archiveint.dll ships alongside Windows tar.exe; load only from System32.
 * Resolve the required libarchive ABI explicitly and fail if unavailable. */
#include "state.h"
#include "err.h"
#include "fspath.h"
#include "hold.h"
#include "values.h"
#include "wintext.h"
#include "lauxlib.h"
#include <stdlib.h>
#include <string.h>

struct archive;
struct archive_entry;
typedef struct archive_api {
    struct archive *(*read_new)(void);
    int (*read_free)(struct archive *);
    int (*filter_all)(struct archive *);
    int (*format_all)(struct archive *);
    int (*open_w)(struct archive *, const wchar_t *, size_t);
    int (*next)(struct archive *, struct archive_entry **);
    const wchar_t *(*pathname_w)(struct archive_entry *);
} archive_api;

typedef struct reader {
    HMODULE module;
    struct archive *archive;
    archive_api api;
    ku_wpath path;
    char *name;
} reader;

static void reader_free(void *ptr)
{
    reader *r = ptr;
    if (r->archive != NULL) r->api.read_free(r->archive);
    if (r->module != NULL) FreeLibrary(r->module);
    ku_wpath_free(&r->path);
    free(r->name);
    free(r);
}

static int list_native(lua_State *L)
{
    const char *file = ku_check_cstring(L, 1, "ARCHIVE", "archive path");
    ku_hold *hold = ku_hold_new(L, reader_free);
    lua_toclose(L, lua_gettop(L));
    reader *r = calloc(1, sizeof *r);
    hold->ptr = r;
    if (r == NULL) return ku_err_fail(L, "ARCHIVE", "oserror", "out of memory");
    ku_fail fail;
    if (ku_wpath_make(file, &r->path, &fail) != 0)
        return ku_err_fail(L, "ARCHIVE", fail.code, "%s", fail.message);
    r->module = LoadLibraryExW(L"archiveint.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (r->module == NULL)
        return ku_err_fail(L, "ARCHIVE", "oserror", "Windows archiveint.dll is unavailable in System32 (error %lu)", (unsigned long)GetLastError());
#define BIND(field, symbol) do { \
    FARPROC address = GetProcAddress(r->module, symbol); \
    if (address == NULL) return ku_err_fail(L, "ARCHIVE", "oserror", "Windows archiveint.dll lacks " symbol); \
    _Static_assert(sizeof r->api.field == sizeof address, "function pointer size"); \
    memcpy(&r->api.field, &address, sizeof address); \
} while (0)
    BIND(read_new, "archive_read_new");
    BIND(read_free, "archive_read_free");
    BIND(filter_all, "archive_read_support_filter_all");
    BIND(format_all, "archive_read_support_format_all");
    BIND(open_w, "archive_read_open_filename_w");
    BIND(next, "archive_read_next_header");
    BIND(pathname_w, "archive_entry_pathname_w");
#undef BIND
    r->archive = r->api.read_new();
    if (r->archive == NULL) return ku_err_fail(L, "ARCHIVE", "oserror", "cannot allocate the Windows archive reader");
    /* ARCHIVE_WARN (-20) from filter_all can merely mean an optional external
     * decompressor is unavailable. open/next must succeed without warnings. */
    if (r->api.filter_all(r->archive) < -20 || r->api.format_all(r->archive) < 0)
        return ku_err_fail(L, "ARCHIVE", "failed", "cannot enable Windows archive formats");
    int status = r->api.open_w(r->archive, r->path.text, 65536);
    if (status != 0) return ku_err_fail(L, "ARCHIVE", "failed", "cannot open the archive (Windows archive status %d)", status);
    lua_newtable(L);
    size_t total = 0;
    lua_Integer count = 0;
    for (;;) {
        struct archive_entry *entry = NULL;
        status = r->api.next(r->archive, &entry);
        if (status == 1) break; /* ARCHIVE_EOF */
        if (status != 0) return ku_err_fail(L, "ARCHIVE", "failed", "cannot read an archive header (Windows archive status %d)", status);
        const wchar_t *wide = r->api.pathname_w(entry);
        r->name = ku_wide_to_utf8(wide, -1);
        if (r->name == NULL) return ku_err_fail(L, "ARCHIVE", "encoding", "an archive entry has no valid Unicode filename");
        size_t length = strlen(r->name);
        total += length;
        if (total > (size_t)64 * 1024 * 1024 || count >= 1000000)
            return ku_err_fail(L, "ARCHIVE", "toobig", "archive listing exceeds 64 MiB of names or one million entries");
        /* Windows extraction interprets backslashes as separators as well. */
        for (size_t i = 0; i < length; i++) if (r->name[i] == '\\') r->name[i] = '/';
        lua_pushlstring(L, r->name, length);
        lua_rawseti(L, -2, ++count);
        free(r->name);
        r->name = NULL;
    }
    return 1;
}

int ku_open_archive_native(lua_State *L)
{
    lua_pushcfunction(L, list_native);
    return 1;
}

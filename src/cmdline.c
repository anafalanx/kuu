/* cmdline.c -- Windows command-line quoting; see cmdline.h. */
#include "cmdline.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* ---- a small growable byte buffer ---------------------------------------- */

typedef struct {
    char *p;
    size_t len;
    size_t cap;
    int failed;
} sb_t;

static int sb_init(sb_t *b)
{
    b->cap = 64;
    b->len = 0;
    b->failed = 0;
    b->p = (char *)malloc(b->cap);
    if (b->p == NULL) {
        b->cap = 0;
        b->failed = 1;
        return -1;
    }
    b->p[0] = '\0';
    return 0;
}

static int sb_ensure(sb_t *b, size_t extra)
{
    if (b->failed) {
        return -1;
    }
    if (extra > SIZE_MAX - b->len - 1) {
        b->failed = 1;
        return -1;
    }
    size_t need = b->len + extra + 1;
    if (need > b->cap) {
        size_t cap = b->cap;
        while (cap < need) {
            if (cap > SIZE_MAX / 2) {
                cap = need;
                break;
            }
            cap *= 2;
        }
        char *p = (char *)realloc(b->p, cap);
        if (p == NULL) {
            b->failed = 1;
            return -1;
        }
        b->p = p;
        b->cap = cap;
    }
    return 0;
}

static void sb_putc(sb_t *b, char c)
{
    if (sb_ensure(b, 1) != 0) {
        return;
    }
    b->p[b->len++] = c;
    b->p[b->len] = '\0';
}

static void sb_puts(sb_t *b, const char *s)
{
    size_t n = strlen(s);
    if (sb_ensure(b, n) != 0) {
        return;
    }
    memcpy(b->p + b->len, s, n);
    b->len += n;
    b->p[b->len] = '\0';
}

static char *xstrdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *r = (char *)malloc(n);
    if (r != NULL) {
        memcpy(r, s, n);
    }
    return r;
}

/* ---- EscapeArg (the CommandLineToArgvW convention) ----------------------- *
 *
 * Quote only when the argument is empty or contains a space or tab;
 * backslashes are doubled only when they precede a double quote or the closing
 * quote; embedded quotes become \".
 */
char *ku_escape_arg(const char *s)
{
    if (s == NULL) {
        return NULL;
    }
    size_t len = strlen(s);
    if (len == 0) {
        return xstrdup("\"\"");
    }
    int has_space = 0;
    size_t growth = 0;
    for (size_t i = 0; i < len; i++) {
        char c = s[i];
        if (c == '"' || c == '\\') {
            growth++;
        } else if (c == ' ' || c == '\t') {
            has_space = 1;
        }
    }
    if (growth == 0 && !has_space) {
        return xstrdup(s);
    }
    sb_t b;
    if (sb_init(&b) != 0) {
        return NULL;
    }
    if (has_space) {
        sb_putc(&b, '"');
    }
    int slashes = 0;
    for (size_t i = 0; i < len; i++) {
        char c = s[i];
        if (c == '\\') {
            slashes++;
            sb_putc(&b, '\\');
        } else if (c == '"') {
            for (; slashes > 0; slashes--) {
                sb_putc(&b, '\\'); /* double the run preceding the quote */
            }
            sb_putc(&b, '\\'); /* escape the quote itself */
            sb_putc(&b, '"');
        } else {
            slashes = 0;
            sb_putc(&b, c);
        }
    }
    if (has_space) {
        for (; slashes > 0; slashes--) {
            sb_putc(&b, '\\'); /* double the trailing run before the close quote */
        }
        sb_putc(&b, '"');
    }
    if (b.failed) {
        free(b.p);
        return NULL;
    }
    return b.p;
}

char *ku_make_cmdline(int argc, const char *const *argv)
{
    if (argc < 0 || (argc > 0 && argv == NULL)) {
        return NULL;
    }
    sb_t b;
    if (sb_init(&b) != 0) {
        return NULL;
    }
    for (int i = 0; i < argc; i++) {
        if (i > 0) {
            sb_putc(&b, ' ');
        }
        char *e = ku_escape_arg(argv[i]);
        if (e == NULL) {
            free(b.p);
            return NULL;
        }
        sb_puts(&b, e);
        free(e);
    }
    if (b.failed) {
        free(b.p);
        return NULL;
    }
    return b.p;
}

/* ---- batch detection ----------------------------------------------------- */

static int ci_eq(const char *a, const char *b)
{
    while (*a && *b) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z') {
            ca = (char)(ca + 32);
        }
        if (cb >= 'A' && cb <= 'Z') {
            cb = (char)(cb + 32);
        }
        if (ca != cb) {
            return 0;
        }
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

int ku_is_batch_target(const char *exe)
{
    const char *dot = NULL;
    for (const char *c = exe; *c; c++) {
        if (*c == '/' || *c == '\\') {
            dot = NULL; /* a new path element begins */
        } else if (*c == '.') {
            dot = c;
        }
    }
    if (dot == NULL) {
        return 0;
    }
    return ci_eq(dot, ".bat") || ci_eq(dot, ".cmd");
}

/* ---- batch command line (CVE-2024-24576 mitigation) ---------------------- *
 *
 * cmd.exe re-parses the /c payload with rules EscapeArg does not satisfy: an
 * embedded quote can close cmd's quoting, after which & | < > become live
 * operators.  So the script and each argument are individually quoted,
 * embedded quotes are doubled ("") in cmd's own convention, backslash runs are
 * doubled so the batch's argv parse still round-trips, and every '%' is
 * rewritten `%%cd:~,%` (a zero-length substring of the always-present %cd%) so
 * cmd cannot expand %VAR% out of the text.
 */

static void append_neutralized(sb_t *b, const char *s)
{
    for (size_t i = 0; s[i]; i++) {
        if (s[i] == '%') {
            sb_puts(b, "%%cd:~,");
        }
        sb_putc(b, s[i]);
    }
}

/* ASCII symbols that do not force quoting; every other non-alphanumeric
 * ASCII character, and any control character, does. */
static const char *BATCH_UNQUOTED = "#$*+-./:?@\\_";

static int is_ascii_alnum(unsigned char c)
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static void append_batch_arg(sb_t *b, const char *arg)
{
    size_t len = strlen(arg);
    int quote = (len == 0) || (arg[len - 1] == '\\');
    if (!quote) {
        for (size_t i = 0; i < len; i++) {
            unsigned char c = (unsigned char)arg[i];
            int ascii_needs_quote =
                (c < 0x80) && !(is_ascii_alnum(c) || (c != 0 && strchr(BATCH_UNQUOTED, c) != NULL));
            int is_control = (c < 0x20) || (c == 0x7f);
            if (ascii_needs_quote || is_control) {
                quote = 1;
                break;
            }
        }
    }
    if (quote) {
        sb_putc(b, '"');
    }
    /* '\\' '"' '%' '\r' are ASCII and never occur inside a UTF-8 multibyte
     * sequence, so a byte walk acts on exactly the characters it should. */
    int backslashes = 0;
    for (size_t i = 0; i < len; i++) {
        char c = arg[i];
        if (c == '\\') {
            backslashes++;
        } else {
            if (c == '"') {
                for (int k = 0; k < backslashes; k++) {
                    sb_putc(b, '\\');
                }
                sb_putc(b, '"'); /* doubled quote: cmd's literal quote */
            } else if (c == '%' || c == '\r') {
                sb_puts(b, "%%cd:~,");
            }
            backslashes = 0;
        }
        sb_putc(b, c);
    }
    if (quote) {
        for (int k = 0; k < backslashes; k++) {
            sb_putc(b, '\\');
        }
        sb_putc(b, '"');
    }
}

static int has_cr_or_lf(const char *s)
{
    return strchr(s, '\r') != NULL || strchr(s, '\n') != NULL;
}

int ku_make_batch_cmdline(const char *script, int argc, const char *const *args,
                          char **out, const char **error)
{
    if (out != NULL) {
        *out = NULL;
    }
    if (script == NULL || out == NULL || error == NULL || argc < 0 ||
        (argc > 0 && args == NULL)) {
        if (error != NULL) {
            *error = "invalid batch command-line input";
        }
        return -1;
    }
    size_t slen = strlen(script);
    if (strchr(script, '"') != NULL || (slen > 0 && script[slen - 1] == '\\')) {
        *error = "a batch script path may not contain a quote or end with a backslash";
        return -1;
    }
    if (has_cr_or_lf(script)) {
        *error = "a batch script path may not contain a carriage return or newline";
        return -1;
    }
    sb_t b;
    if (sb_init(&b) != 0) {
        *error = "out of memory";
        return -1;
    }
    sb_puts(&b, "cmd.exe /e:ON /v:OFF /d /c \""); /* opens the outer /c quote */
    sb_putc(&b, '"');                             /* opens the script's own quote */
    append_neutralized(&b, script);
    sb_putc(&b, '"');
    for (int i = 0; i < argc; i++) {
        if (has_cr_or_lf(args[i])) {
            free(b.p);
            *error = "a batch argument may not contain a carriage return or newline";
            return -1;
        }
        sb_putc(&b, ' ');
        append_batch_arg(&b, args[i]);
    }
    sb_putc(&b, '"'); /* closes the outer /c quote */
    if (b.failed) {
        free(b.p);
        *error = "out of memory";
        return -1;
    }
    *out = b.p;
    return 0;
}

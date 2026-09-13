/*
 * kuu.h -- the runtime's identity and the one failure shape its host code uses.
 *
 * kuu is a Lua 5.5 runtime for agents on Windows: one static executable that
 * runs a program file, a program on stdin, or an inline script, and (in later
 * milestones) offers a native palette for processes, files, and the network.
 * Everything the host reports to a human or an agent is spelled the same way:
 * "kuu: DOMAIN code: message".  The same triple is what Lua-side errors carry.
 */
#ifndef KUU_H
#define KUU_H

#include <stddef.h>

/* N.N: two nonnegative integer components, compared numerically. Release
 * numbers do not encode semantic-version compatibility categories. The literal
 * is the source the Makefile and Windows version resource read, and the numeric
 * minimum-version guard parses it rather than keeping a second copy. */
#define KUU_NAME "kuu"
#define KUU_VERSION "0.11"
#define KUU_VERSION_W L"0.11"

/* Exit codes.  2 means kuu never started the program (usage, entry, state);
 * 1 means the program itself failed; anything else is the program's own
 * os.exit value. */
#define KUU_EXIT_OK 0
#define KUU_EXIT_PROGRAM 1
#define KUU_EXIT_ENTRY 2
#define KUU_EXIT_CRASH 3   /* a structured exception inside kuu: a defect in kuu itself */

/* A failure the host describes before or outside Lua: a closed domain, a
 * closed code within it, and one line of text.  Functions that can fail take
 * a `ku_fail *` and return non-zero after filling it. */
typedef struct ku_fail {
    const char *domain;
    const char *code;
    /* Wide enough for a failure that names a long path and still says why:
     * an extended-length path is bounded at 32,767 characters, but the ones
     * a project has are hundreds, and 1024 cut the reason off the end. */
    char message[4096];
} ku_fail;

/* Fill `fail` and return 1, so callers can write `return ku_fail_set(...)`. */
int ku_fail_set(ku_fail *fail, const char *domain, const char *code,
                const char *format, ...);

#endif /* KUU_H */

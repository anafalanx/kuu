/*
 * program.h -- reading program text for the host.
 *
 * A program reaches kuu as bytes from a file or from standard input.  Both
 * routes go through ku_program_from_bytes, so the two cannot drift: a UTF-8
 * BOM is skipped, the bytes must be strict UTF-8 (refused otherwise, never
 * repaired), a first line starting with '#' is skipped with its newline kept so
 * line numbers hold, and CRLF is left alone because Lua's lexer already treats
 * it as one line end.  Programs are bounded at 16 MiB so a runaway writer
 * fails here, by name, rather than in the allocator.
 */
#ifndef KUU_PROGRAM_H
#define KUU_PROGRAM_H

#include <stddef.h>
#include <wchar.h>

#include "kuu.h"

#define KU_PROGRAM_MAX (16u * 1024u * 1024u)

/* Room for a "program file '...'" description; longer paths are truncated in
 * messages only, never in the open. */
#define KU_PROGRAM_WHAT_MAX 1200

typedef struct ku_program {
    unsigned char *owned; /* the malloc'd buffer; free with ku_program_free */
    const char *text;     /* the chunk to load, inside `owned` */
    size_t length;
} ku_program;

/* Read a whole file.  `what` names it in messages ("program file 'x.lua'").
 * ENTRY codes: notfound, access, badvalue (not a regular file), toobig,
 * encoding, oserror. */
int ku_program_read_file(const wchar_t *path, const char *what,
                         ku_program *out, ku_fail *fail);

/* Read all of standard input.  ENTRY codes: stdin, toobig, encoding, oserror. */
int ku_program_read_stdin(ku_program *out, ku_fail *fail);

/* Decode bytes into a program.  Takes ownership of `bytes` in every case. */
int ku_program_from_bytes(unsigned char *bytes, size_t length, const char *what,
                          ku_program *out, ku_fail *fail);

void ku_program_free(ku_program *program);

#endif /* KUU_PROGRAM_H */

/*
 * payload.h -- the files kuu carries inside its executable.
 *
 * The Lua files under lua/ are kuu's own modules, reachable through `require`;
 * the Markdown files under docs/ are the manual.  The table is generated at
 * build time by tools/embed.c from those directories, sorted by name, so the
 * executable is reproducible.
 */
#ifndef KUU_PAYLOAD_H
#define KUU_PAYLOAD_H

#include <stddef.h>

typedef struct ku_payload_entry {
    const char *name; /* "lua/cli.lua", "docs/index.md" */
    const unsigned char *bytes;
    size_t length;
} ku_payload_entry;

extern const ku_payload_entry ku_payload[];
extern const size_t ku_payload_count;

/* The entry named exactly `name`, or NULL. */
const ku_payload_entry *ku_payload_find(const char *name);

#endif /* KUU_PAYLOAD_H */

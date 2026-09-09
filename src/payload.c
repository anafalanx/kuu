/* payload.c -- lookup in the embedded file table; see payload.h. */
#include "payload.h"

#include <string.h>

const ku_payload_entry *ku_payload_find(const char *name)
{
    for (const ku_payload_entry *e = ku_payload; e->name != NULL; e++) {
        if (strcmp(e->name, name) == 0) {
            return e;
        }
    }
    return NULL;
}

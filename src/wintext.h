/*
 * wintext.h -- the one UTF-8 <-> UTF-16 boundary for kuu's Win32 code.
 *
 * Lua strings are bytes, UTF-8 by convention; Win32 wants UTF-16.  Every
 * conversion here is STRICT in both directions.  Without MB_ERR_INVALID_CHARS
 * and WC_ERR_INVALID_CHARS the Win32 converters substitute U+FFFD and report
 * success, so a name holding an unpaired surrogate or a malformed byte would be
 * silently rewritten and the host would open, launch, or list a DIFFERENT
 * object.  The rule in both directions: a name we cannot represent is refused
 * (NULL) and the caller reports it; it is never renamed.
 *
 * Results are malloc'd and NUL-terminated; the caller frees them.
 */
#ifndef KUU_WINTEXT_H
#define KUU_WINTEXT_H

#include <stddef.h>
#include <wchar.h>

/* UTF-8 (NUL-terminated) -> UTF-16.  NULL on invalid input or allocation failure. */
wchar_t *ku_utf8_to_wide(const char *utf8);

/* UTF-16 -> UTF-8.  `count` is the number of UTF-16 units, or -1 for a
 * NUL-terminated string.  NULL on an unpaired surrogate, a zero count, or
 * allocation failure. */
char *ku_wide_to_utf8(const wchar_t *wide, int count);

/* 1 when `bytes` is strict UTF-8 (RFC 3629: no overlongs, no surrogates, no
 * code points above U+10FFFF).  Embedded NUL bytes are valid UTF-8. */
int ku_utf8_valid(const unsigned char *bytes, size_t length);

/* The system's text for a Win32 error code, UTF-8, trailing whitespace
 * removed.  Never NULL: falls back to "Windows error N". Caller frees. */
char *ku_win_error_message(unsigned long error);

#endif /* KUU_WINTEXT_H */

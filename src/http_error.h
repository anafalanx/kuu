#ifndef KUU_HTTP_ERROR_H
#define KUU_HTTP_ERROR_H
#include <stddef.h>
const char *ku_http_error_code(unsigned long error);
void ku_http_error_message(char *out, size_t size, const char *what, unsigned long error);
#endif

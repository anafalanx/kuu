/* Exercise the production classifier/formatter without changing real certs. */
#include "http_error.h"
#include <stdio.h>
#include <string.h>
int main(void)
{
    for (unsigned long code = 12185; code <= 12188; code++) {
        char message[512];
        ku_http_error_message(message, sizeof message, "cannot send request", code);
        if (strcmp(ku_http_error_code(code), "tls") != 0 || strstr(message, "ERROR_WINHTTP_") == NULL || strstr(message, "check") == NULL) return 1;
        puts(message);
    }
    if (strcmp(ku_http_error_code(12029), "connect") != 0 || strcmp(ku_http_error_code(12002), "timeout") != 0 || strcmp(ku_http_error_code(5), "oserror") != 0) return 2;
    return 0;
}

/* WinHTTP's TLS failures keep their semantic code and actionable context. */
#include "http_error.h"
#include "wintext.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>
#include <stdio.h>
#include <stdlib.h>

const char *ku_http_error_code(unsigned long error)
{
    switch (error) {
    case ERROR_WINHTTP_TIMEOUT: return "timeout";
    case ERROR_WINHTTP_NAME_NOT_RESOLVED: return "notfound";
    case ERROR_WINHTTP_CANNOT_CONNECT:
    case ERROR_WINHTTP_CONNECTION_ERROR: return "connect";
    case ERROR_WINHTTP_SECURE_FAILURE:
    case ERROR_WINHTTP_SECURE_CERT_CN_INVALID:
    case ERROR_WINHTTP_SECURE_CERT_DATE_INVALID:
    case ERROR_WINHTTP_SECURE_INVALID_CA:
    case ERROR_WINHTTP_SECURE_INVALID_CERT:
    case ERROR_WINHTTP_SECURE_CERT_REV_FAILED:
    case ERROR_WINHTTP_SECURE_CERT_REVOKED:
    case ERROR_WINHTTP_SECURE_CERT_WRONG_USAGE:
    case ERROR_WINHTTP_SECURE_CHANNEL_ERROR:
    case ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED:
    case ERROR_WINHTTP_CLIENT_CERT_NO_PRIVATE_KEY:
    case ERROR_WINHTTP_CLIENT_CERT_NO_ACCESS_PRIVATE_KEY:
    case ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED_PROXY:
    case ERROR_WINHTTP_SECURE_FAILURE_PROXY: return "tls";
    case ERROR_WINHTTP_INVALID_URL:
    case ERROR_WINHTTP_UNRECOGNIZED_SCHEME: return "badvalue";
    default: return "oserror";
    }
}

void ku_http_error_message(char *out, size_t size, const char *what, unsigned long error)
{
    const char *hint = NULL;
    if (error == ERROR_WINHTTP_CLIENT_CERT_NO_PRIVATE_KEY)
        hint = "ERROR_WINHTTP_CLIENT_CERT_NO_PRIVATE_KEY: the TLS client certificate has no associated private key; check the certificate and the execution account's certificate store";
    else if (error == ERROR_WINHTTP_CLIENT_CERT_NO_ACCESS_PRIVATE_KEY)
        hint = "ERROR_WINHTTP_CLIENT_CERT_NO_ACCESS_PRIVATE_KEY: the execution account cannot access the TLS client certificate's private key; check its key permissions";
    else if (error == ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED_PROXY)
        hint = "ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED_PROXY: the proxy requires a TLS client certificate; check the execution account's proxy and certificate configuration";
    else if (error == ERROR_WINHTTP_SECURE_FAILURE_PROXY)
        hint = "ERROR_WINHTTP_SECURE_FAILURE_PROXY: TLS validation failed at the proxy; check the proxy certificate and trust configuration";
    if (hint != NULL) {
        snprintf(out, size, "%s: %s (error %lu)", what, hint, error);
        return;
    }
    char *text = ku_win_error_message(error);
    snprintf(out, size, "%s: %s (error %lu)", what, text != NULL ? text : "Windows request failed", error);
    free(text);
}

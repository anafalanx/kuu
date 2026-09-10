/* signature.c -- embedded Authenticode signatures, verified off the loop. */
#include "err.h"
#include "fspath.h"
#include "hold.h"
#include "loop.h"
#include "signature.h"
#include "values.h"
#include "wintext.h"
#include "lauxlib.h"
#include <wintrust.h>
#include <softpub.h>
#include <wincrypt.h>
#include <stdlib.h>
#include <string.h>

typedef struct signature_request {
    ku_source source;
    ku_loop *loop;
    ku_waiter *waiter;
    int ref;
    HANDLE thread;
    ku_wpath path;
    int revocation, signed_file, timestamped;
    LONG trust;
    DWORD error;
    char *signer, *issuer;
    char thumbprint[41];
} signature_request;

static void request_free(void *ptr)
{
    signature_request *r = ptr;
    /* The registry holds this request through its posted completion. At Lua
     * shutdown, join before the loop itself is freed: a worker can still post. */
    if (r->thread) { WaitForSingleObject(r->thread, INFINITE); CloseHandle(r->thread); }
    ku_wpath_free(&r->path);
    free(r->signer); free(r->issuer); free(r);
}

static const char *trust_reason(LONG status)
{
    switch (status) {
    case CERT_E_EXPIRED: case CERT_E_VALIDITYPERIODNESTING: return "expired";
    case TRUST_E_BAD_DIGEST: return "tampered";
    case CERT_E_REVOKED: case CRYPT_E_REVOKED: return "revoked";
    case TRUST_E_EXPLICIT_DISTRUST: return "distrusted";
    case CERT_E_REVOCATION_FAILURE: case CRYPT_E_REVOCATION_OFFLINE: case CRYPT_E_NO_REVOCATION_CHECK:
        return "revocation";
    case TRUST_E_TIME_STAMP: case TRUST_E_COUNTER_SIGNER: return "timestamp";
    case CERT_E_WRONG_USAGE: case CERT_E_PURPOSE: return "usage";
    case CERT_E_UNTRUSTEDROOT: case CERT_E_UNTRUSTEDCA: case CERT_E_UNTRUSTEDTESTROOT:
    case CERT_E_CHAINING: case CERT_E_ISSUERCHAINING: case TRUST_E_SUBJECT_NOT_TRUSTED:
    case TRUST_E_NO_SIGNER_CERT: return "untrusted";
    default: return "invalid";
    }
}

static char *certificate_name(PCCERT_CONTEXT certificate, DWORD flags)
{
    DWORD size = CertGetNameStringW(certificate, CERT_NAME_SIMPLE_DISPLAY_TYPE, flags, NULL, NULL, 0);
    if (!size) return NULL;
    wchar_t *wide = malloc((size_t)size * sizeof(wchar_t));
    if (!wide) return NULL;
    char *text = NULL;
    if (CertGetNameStringW(certificate, CERT_NAME_SIMPLE_DISPLAY_TYPE, flags, NULL, wide, size))
        text = ku_wide_to_utf8(wide, -1);
    free(wide);
    return text;
}

static void inspect_signer(signature_request *r, HCERTSTORE store, HCRYPTMSG message)
{
    DWORD bytes = 0;
    if (!CryptMsgGetParam(message, CMSG_SIGNER_INFO_PARAM, 0, NULL, &bytes)) return;
    CMSG_SIGNER_INFO *signer = malloc(bytes);
    if (!signer) { r->error = ERROR_OUTOFMEMORY; return; }
    if (!CryptMsgGetParam(message, CMSG_SIGNER_INFO_PARAM, 0, signer, &bytes)) { free(signer); return; }
    for (DWORD i = 0; i < signer->UnauthAttrs.cAttr; ++i) {
        const char *oid = signer->UnauthAttrs.rgAttr[i].pszObjId;
        if (oid && (!strcmp(oid, szOID_RSA_counterSign) || !strcmp(oid, szOID_RFC3161_counterSign)))
            r->timestamped = 1;
    }
    CERT_INFO info;
    memset(&info, 0, sizeof info);
    info.Issuer = signer->Issuer;
    info.SerialNumber = signer->SerialNumber;
    PCCERT_CONTEXT certificate = CertFindCertificateInStore(store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
                                                            0, CERT_FIND_SUBJECT_CERT, &info, NULL);
    if (certificate) {
        r->signer = certificate_name(certificate, 0);
        r->issuer = certificate_name(certificate, CERT_NAME_ISSUER_FLAG);
        BYTE hash[20];
        DWORD size = sizeof hash;
        if (CertGetCertificateContextProperty(certificate, CERT_SHA1_HASH_PROP_ID, hash, &size) && size == sizeof hash) {
            static const char digits[] = "0123456789ABCDEF";
            for (size_t i = 0; i < sizeof hash; ++i) {
                r->thumbprint[i * 2] = digits[hash[i] >> 4];
                r->thumbprint[i * 2 + 1] = digits[hash[i] & 15];
            }
        }
        CertFreeCertificateContext(certificate);
    }
    free(signer);
}

/* A damaged PE certificate can fail CryptQueryObject's decoder while still
 * being an embedded signature. Inspect only the bounded security directory;
 * never infer signature presence from a catalog-backed trust result. */
static int pe_has_certificate(HANDLE file)
{
    IMAGE_DOS_HEADER dos;
    DWORD read = 0;
    LARGE_INTEGER size, offset;
    offset.QuadPart = 0;
    if (!GetFileSizeEx(file, &size) || !SetFilePointerEx(file, offset, NULL, FILE_BEGIN) ||
        !ReadFile(file, &dos, sizeof dos, &read, NULL) || read != sizeof dos ||
        dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < (LONG)sizeof dos) return 0;
    offset.QuadPart = dos.e_lfanew;
    if (offset.QuadPart > size.QuadPart - (LONGLONG)(sizeof(DWORD) + sizeof(IMAGE_FILE_HEADER))) return 0;
    if (!SetFilePointerEx(file, offset, NULL, FILE_BEGIN)) return 0;
    DWORD magic;
    IMAGE_FILE_HEADER header;
    if (!ReadFile(file, &magic, sizeof magic, &read, NULL) || read != sizeof magic || magic != IMAGE_NT_SIGNATURE ||
        !ReadFile(file, &header, sizeof header, &read, NULL) || read != sizeof header) return 0;
    union { IMAGE_OPTIONAL_HEADER32 x32; IMAGE_OPTIONAL_HEADER64 x64; } optional;
    memset(&optional, 0, sizeof optional);
    if (header.SizeOfOptionalHeader > sizeof optional ||
        !ReadFile(file, &optional, header.SizeOfOptionalHeader, &read, NULL) || read != header.SizeOfOptionalHeader) return 0;
    IMAGE_DATA_DIRECTORY directory;
    if (optional.x64.Magic == IMAGE_NT_OPTIONAL_HDR64_MAGIC && optional.x64.NumberOfRvaAndSizes > IMAGE_DIRECTORY_ENTRY_SECURITY &&
        header.SizeOfOptionalHeader >= offsetof(IMAGE_OPTIONAL_HEADER64, DataDirectory) + 5 * sizeof directory)
        directory = optional.x64.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY];
    else if (optional.x32.Magic == IMAGE_NT_OPTIONAL_HDR32_MAGIC && optional.x32.NumberOfRvaAndSizes > IMAGE_DIRECTORY_ENTRY_SECURITY &&
             header.SizeOfOptionalHeader >= offsetof(IMAGE_OPTIONAL_HEADER32, DataDirectory) + 5 * sizeof directory)
        directory = optional.x32.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY];
    else return 0;
    return directory.VirtualAddress != 0 && directory.Size >= 8 &&
           (uint64_t)directory.VirtualAddress + directory.Size <= (uint64_t)size.QuadPart;
}

static DWORD WINAPI verify_thread(void *ptr)
{
    signature_request *r = ptr;
    HANDLE file = CreateFileW(r->path.text, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        r->error = GetLastError();
    } else {
        HCERTSTORE store = NULL;
        HCRYPTMSG message = NULL;
        BOOL decoded = CryptQueryObject(CERT_QUERY_OBJECT_FILE, r->path.text, CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
                                        CERT_QUERY_FORMAT_FLAG_BINARY, 0, NULL, NULL, NULL, &store, &message, NULL);
        r->signed_file = decoded || pe_has_certificate(file);
        if (!r->signed_file) {
            if (message) CryptMsgClose(message);
            if (store) CertCloseStore(store, 0);
            CloseHandle(file);
            ku_loop_post(r->loop, &r->source, r, 0);
            return 0;
        }
        LARGE_INTEGER beginning;
        beginning.QuadPart = 0;
        SetFilePointerEx(file, beginning, NULL, FILE_BEGIN);
        WINTRUST_FILE_INFO info;
        memset(&info, 0, sizeof info);
        info.cbStruct = sizeof info;
        info.pcwszFilePath = r->path.text;
        info.hFile = file;
        WINTRUST_DATA data;
        memset(&data, 0, sizeof data);
        data.cbStruct = sizeof data;
        data.dwUIChoice = WTD_UI_NONE;
        data.fdwRevocationChecks = r->revocation ? WTD_REVOKE_WHOLECHAIN : WTD_REVOKE_NONE;
        data.dwUnionChoice = WTD_CHOICE_FILE;
        data.pFile = &info;
        data.dwStateAction = WTD_STATEACTION_VERIFY;
        data.dwProvFlags = r->revocation ? WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT :
                                          WTD_REVOCATION_CHECK_NONE | WTD_CACHE_ONLY_URL_RETRIEVAL;
        GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
        r->trust = WinVerifyTrust((HWND)INVALID_HANDLE_VALUE, &action, &data);
        if (decoded) inspect_signer(r, store, message);
        if (message) CryptMsgClose(message);
        if (store) CertCloseStore(store, 0);
        data.dwStateAction = WTD_STATEACTION_CLOSE;
        WinVerifyTrust((HWND)INVALID_HANDLE_VALUE, &action, &data);
        CloseHandle(file);
    }
    ku_loop_post(r->loop, &r->source, r, 0);
    return 0;
}

static int signature_push(lua_State *L, ku_waiter *waiter)
{
    signature_request *r = waiter->data;
    if (r->error) {
        const char *code = r->error == ERROR_FILE_NOT_FOUND || r->error == ERROR_PATH_NOT_FOUND ? "notfound" :
                           r->error == ERROR_ACCESS_DENIED || r->error == ERROR_SHARING_VIOLATION ? "access" : "oserror";
        return ku_err_fail(L, "SYS", code, "cannot read signature: Windows error %lu", (unsigned long)r->error);
    }
    lua_createtable(L, 0, 7);
    lua_pushboolean(L, r->signed_file); lua_setfield(L, -2, "signed");
    if (!r->signed_file) return 1;
    lua_pushboolean(L, r->trust == ERROR_SUCCESS); lua_setfield(L, -2, "valid");
    if (r->trust != ERROR_SUCCESS) {
        lua_pushstring(L, trust_reason(r->trust)); lua_setfield(L, -2, "reason");
    }
    if (r->signer) { lua_pushstring(L, r->signer); lua_setfield(L, -2, "signer"); }
    if (r->issuer) { lua_pushstring(L, r->issuer); lua_setfield(L, -2, "issuer"); }
    if (r->thumbprint[0]) { lua_pushstring(L, r->thumbprint); lua_setfield(L, -2, "thumbprint"); }
    lua_pushboolean(L, r->timestamped); lua_setfield(L, -2, "timestamped");
    return 1;
}

static void signature_posted(ku_source *source, void *value, DWORD bytes)
{
    (void)value; (void)bytes;
    signature_request *r = source->owner;
    ku_loop_received(r->loop);
    ku_waiter *waiter = r->waiter;
    r->waiter = NULL;
    int ref = r->ref;
    r->ref = LUA_NOREF;
    if (waiter) {
        waiter->data = r;
        waiter->data_ref = ref; /* the hold stays alive through any Lua allocation in push */
        ku_wake(waiter);
    } else {
        luaL_unref(ku_loop_state(r->loop), LUA_REGISTRYINDEX, ref);
    }
}

static void signature_abandon(ku_waiter *waiter)
{
    signature_request *r = waiter->owner;
    r->waiter = NULL; /* WinVerifyTrust cannot be cancelled; completion releases its holder. */
}

int ku_sys_signature(lua_State *L)
{
    if (lua_type(L, 1) != LUA_TSTRING) ku_err_raise(L, "SYS", "badvalue", "signature path must be a string");
    const char *path = ku_check_cstring(L, 1, "SYS", "path");
    int revocation = 0;
    if (!lua_isnoneornil(L, 2)) {
        if (!lua_istable(L, 2)) ku_err_raise(L, "SYS", "badvalue", "signature options must be a table");
        lua_pushnil(L);
        while (lua_next(L, 2)) {
            const char *key = lua_type(L, -2) == LUA_TSTRING ? lua_tostring(L, -2) : "";
            if (lua_type(L, -2) == LUA_TSTRING) ku_check_cstring(L, -2, "SYS", "option name");
            if (strcmp(key, "revocation") || lua_type(L, -1) != LUA_TBOOLEAN)
                ku_err_raise(L, "SYS", "badvalue", "signature accepts only a boolean revocation option");
            revocation = lua_toboolean(L, -1);
            lua_pop(L, 1);
        }
    }
    ku_hold *local = ku_hold_new(L, request_free);
    lua_toclose(L, -1);
    signature_request *r = calloc(1, sizeof *r);
    if (!r) ku_err_raise(L, "SYS", "oserror", "out of memory");
    local->ptr = r;
    r->ref = LUA_NOREF;
    ku_fail failure;
    if (ku_wpath_make(path, &r->path, &failure)) ku_err_raise(L, "SYS", "badvalue", "%s", failure.message);
    DWORD attributes = GetFileAttributesW(r->path.text);
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY))
        ku_err_raise(L, "SYS", "badvalue", "signature needs a file, not a directory");
    r->loop = ku_loop_of(L);
    r->source.kind = KU_SRC_POSTED;
    r->source.owner = r;
    r->source.on_posted = signature_posted;
    r->revocation = revocation;
    ku_hold *pending = ku_hold_new(L, request_free);
    pending->ptr = r;
    local->ptr = NULL;
    r->ref = luaL_ref(L, LUA_REGISTRYINDEX);
    ku_waiter *waiter = ku_waiter_new(r->loop, r, signature_push);
    if (!waiter) {
        luaL_unref(L, LUA_REGISTRYINDEX, r->ref);
        return ku_err_fail(L, "SYS", "oserror", "out of memory");
    }
    waiter->on_abandon = signature_abandon;
    waiter->on_timeout = signature_abandon;
    r->waiter = waiter;
    ku_loop_expect(r->loop);
    r->thread = CreateThread(NULL, 0, verify_thread, r, 0, NULL);
    if (!r->thread) {
        DWORD error = GetLastError();
        ku_loop_received(r->loop);
        r->waiter = NULL;
        free(waiter);
        luaL_unref(L, LUA_REGISTRYINDEX, r->ref);
        return ku_err_fail(L, "SYS", "oserror", "cannot create signature worker: Windows error %lu", (unsigned long)error);
    }
    return ku_wait(L, waiter, -1);
}

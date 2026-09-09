/*
 * sha256sum.c -- a build tool: the SHA-256 of a file, printed as sha256sum
 * would print it, "<hex>  <name>", for the release sidecar.
 *
 *   sha256sum FILE
 *
 * Windows' own cryptography (CNG), nothing vendored; plain C, compiled by the
 * same gcc as everything else, run by make.  Never kuu.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: sha256sum FILE\n");
        return 2;
    }
    FILE *in = fopen(argv[1], "rb");
    if (in == NULL) {
        fprintf(stderr, "sha256sum: cannot open %s\n", argv[1]);
        return 1;
    }
    BCRYPT_ALG_HANDLE alg = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0) != 0 ||
        BCryptCreateHash(alg, &hash, NULL, 0, NULL, 0, 0) != 0) {
        fprintf(stderr, "sha256sum: CNG refused SHA-256\n");
        return 1;
    }
    static unsigned char buffer[65536];
    size_t got;
    while ((got = fread(buffer, 1, sizeof buffer, in)) > 0) {
        if (BCryptHashData(hash, buffer, (ULONG)got, 0) != 0) {
            fprintf(stderr, "sha256sum: hashing failed\n");
            return 1;
        }
    }
    fclose(in);
    unsigned char digest[32];
    if (BCryptFinishHash(hash, digest, sizeof digest, 0) != 0) {
        fprintf(stderr, "sha256sum: hashing failed\n");
        return 1;
    }
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    const char *name = argv[1];
    for (const char *p = argv[1]; *p != '\0'; p++) {
        if (*p == '\\' || *p == '/') {
            name = p + 1;
        }
    }
    for (size_t i = 0; i < sizeof digest; i++) {
        printf("%02x", digest[i]);
    }
    printf("  %s\n", name);
    return 0;
}

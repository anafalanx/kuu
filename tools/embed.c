/*
 * embed.c -- a build tool: turn files into a C source with their bytes.
 *
 *   embed OUTPUT.c DIR ...
 *
 * Every regular file under each DIR (one level, sorted by name) becomes an
 * entry in the generated table `ku_payload[]`, named "<dir>/<file>", with its
 * bytes as an unsigned char array.  kuu's `require` and its manual read from
 * that table, so kuu ships its own Lua and documentation inside the executable
 * without kuu having to build kuu: this tool is plain C, compiled by the same
 * gcc as everything else, and run by make.  The output is deterministic.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <io.h>

typedef struct entry {
    char *name;   /* "dir/file" with forward slashes */
    char *path;   /* how to open it */
} entry;

static int compare_entries(const void *a, const void *b)
{
    return strcmp(((const entry *)a)->name, ((const entry *)b)->name);
}

static int collect(const char *dir, entry **entries, size_t *count, size_t *capacity)
{
    char pattern[MAX_PATH];
    snprintf(pattern, sizeof pattern, "%s\\*", dir);
    WIN32_FIND_DATAA data;
    HANDLE find = FindFirstFileA(pattern, &data);
    if (find == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "embed: cannot list %s\n", dir);
        return -1;
    }
    do {
        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            continue;
        }
        if (*count == *capacity) {
            size_t next = *capacity ? *capacity * 2 : 32;
            entry *grown = (entry *)realloc(*entries, next * sizeof *grown);
            if (grown == NULL) {
                FindClose(find);
                return -1;
            }
            *entries = grown;
            *capacity = next;
        }
        size_t dir_length = strlen(dir), name_length = strlen(data.cFileName);
        entry *e = &(*entries)[*count];
        e->name = (char *)malloc(dir_length + 1 + name_length + 1);
        e->path = (char *)malloc(dir_length + 1 + name_length + 1);
        if (e->name == NULL || e->path == NULL) {
            free(e->name);
            free(e->path);
            FindClose(find);
            return -1;
        }
        snprintf(e->name, dir_length + 1 + name_length + 1, "%s/%s", dir, data.cFileName);
        snprintf(e->path, dir_length + 1 + name_length + 1, "%s\\%s", dir, data.cFileName);
        for (char *c = e->name; *c; c++) {
            if (*c == '\\') {
                *c = '/';
            }
        }
        (*count)++;
    } while (FindNextFileA(find, &data));
    DWORD error = GetLastError();
    FindClose(find);
    if (error != ERROR_NO_MORE_FILES) {
        fprintf(stderr, "embed: cannot finish listing %s\n", dir);
        return -1;
    }
    return 0;
}

static int same_contents(const char *a, const char *b)
{
    FILE *left = fopen(a, "rb"), *right = fopen(b, "rb");
    if (left == NULL || right == NULL) {
        if (left != NULL) fclose(left);
        if (right != NULL) fclose(right);
        return 0;
    }
    unsigned char x[4096], y[4096];
    int same = 1;
    for (;;) {
        size_t nx = fread(x, 1, sizeof x, left), ny = fread(y, 1, sizeof y, right);
        if (nx != ny || memcmp(x, y, nx) != 0 || ferror(left) || ferror(right)) {
            same = 0;
            break;
        }
        if (nx == 0) break;
    }
    fclose(left);
    fclose(right);
    return same;
}

static FILE *temporary_output(const char *output, char **path)
{
    size_t size = strlen(output) + 48;
    char *temp = (char *)malloc(size);
    if (temp == NULL) return NULL;
    for (unsigned int attempt = 0; attempt < 32; attempt++) {
        snprintf(temp, size, "%s.tmp-%lu-%u", output, (unsigned long)GetCurrentProcessId(), attempt);
        HANDLE handle = CreateFileA(temp, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
        if (handle == INVALID_HANDLE_VALUE) {
            DWORD error = GetLastError();
            if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) continue;
            break;
        }
        int fd = _open_osfhandle((intptr_t)handle, _O_BINARY | _O_WRONLY);
        if (fd < 0) {
            CloseHandle(handle);
            DeleteFileA(temp);
            break;
        }
        FILE *out = _fdopen(fd, "wb");
        if (out == NULL) {
            _close(fd);
            DeleteFileA(temp);
            break;
        }
        *path = temp;
        return out;
    }
    free(temp);
    return NULL;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: embed OUTPUT.c DIR ...\n");
        return 2;
    }
    entry *entries = NULL;
    size_t count = 0, capacity = 0;
    char *temp = NULL;
    FILE *out = NULL;
    int status = 1;
    for (int i = 2; i < argc; i++) {
        if (collect(argv[i], &entries, &count, &capacity) != 0) {
            goto done;
        }
    }
    qsort(entries, count, sizeof *entries, compare_entries);

    out = temporary_output(argv[1], &temp);
    if (out == NULL) {
        fprintf(stderr, "embed: cannot write %s\n", argv[1]);
        goto done;
    }
    fprintf(out, "/* generated by tools/embed.c; do not edit */\n#include \"payload.h\"\n\n");
    for (size_t i = 0; i < count; i++) {
        FILE *in = fopen(entries[i].path, "rb");
        if (in == NULL) {
            fprintf(stderr, "embed: cannot read %s\n", entries[i].path);
            goto done;
        }
        fprintf(out, "static const unsigned char file_%zu[] = {\n", i);
        unsigned char buffer[4096];
        size_t total = 0, got;
        while ((got = fread(buffer, 1, sizeof buffer, in)) > 0) {
            for (size_t k = 0; k < got; k++) {
                fprintf(out, "%u,%s", buffer[k], ((total + k) % 24 == 23) ? "\n" : "");
            }
            total += got;
        }
        int read_error = ferror(in);
        fclose(in);
        if (read_error) {
            fprintf(stderr, "embed: cannot finish reading %s\n", entries[i].path);
            goto done;
        }
        fprintf(out, "0};\n"); /* a trailing NUL, so text entries are C strings too */
    }
    fprintf(out, "\nconst ku_payload_entry ku_payload[] = {\n");
    for (size_t i = 0; i < count; i++) {
        fprintf(out, "    {\"%s\", file_%zu, sizeof(file_%zu) - 1},\n", entries[i].name, i, i);
    }
    fprintf(out, "    {NULL, NULL, 0},\n};\nconst size_t ku_payload_count = %zu;\n", count);
    int write_error = ferror(out);
    if (fclose(out) != 0) write_error = 1;
    out = NULL;
    if (write_error) {
        fprintf(stderr, "embed: cannot finish writing %s\n", argv[1]);
        goto done;
    }
    if (same_contents(argv[1], temp)) {
        /* make invokes us to detect additions/deletions. Keep unchanged
         * output current without recompiling the generated C. */
        if (!DeleteFileA(temp)) {
            fprintf(stderr, "embed: cannot remove temporary %s\n", temp);
            goto done;
        }
    } else if (!MoveFileExA(temp, argv[1], MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        fprintf(stderr, "embed: cannot replace %s (error %lu)\n", argv[1], (unsigned long)GetLastError());
        goto done;
    }
    status = 0;
done:
    if (out != NULL) fclose(out);
    if (temp != NULL) {
        if (status != 0) DeleteFileA(temp);
        free(temp);
    }
    for (size_t i = 0; i < count; i++) {
        free(entries[i].name);
        free(entries[i].path);
    }
    free(entries);
    return status;
}

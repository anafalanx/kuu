/* Exercise the actual resource generator with a two-component version. */
#define KUU_H
#define KUU_VERSION "12.34"
#define main versionrc_main
#include "../../tools/versionrc.c"
#undef main
#include <string.h>

int main(int argc, char **argv)
{
    unsigned parts[2];
    static const char *const invalid[] = {
        "", "0", "0.10.0", "0.11junk", "0.11.0.0", "-1.2", "1.+2",
        "1.-2", "1..2", "1.", ".2", "1.65536", "65536.1",
        "99999999999999999999.2", "1.2 ", " 1.2", "1e1.2"
    };
    for (size_t i = 0; i < sizeof invalid / sizeof invalid[0]; ++i) {
        if (version_parts(invalid[i], parts)) return 1;
    }
    if (!version_parts("0.0", parts) || parts[0] != 0 || parts[1] != 0) return 1;
    if (!version_parts("65535.65535", parts) || parts[0] != 65535 || parts[1] != 65535) return 1;
    if (versionrc_main(argc, argv) != 0) return 1;
    FILE *file = fopen(argv[1], "rb");
    if (file == NULL) return 1;
    char text[4096];
    size_t n = fread(text, 1, sizeof text - 1, file);
    text[n] = '\0';
    fclose(file);
    if (strstr(text, "FILEVERSION 12,34,0,0") == NULL ||
        strstr(text, "PRODUCTVERSION 12,34,0,0") == NULL ||
        strstr(text, "\"FileVersion\", \"12.34\"") == NULL ||
        strstr(text, "\"ProductVersion\", \"12.34\"") == NULL) return 1;
    puts("version resource retains the N.N string and zero-pads the Windows tuple");
    return 0;
}

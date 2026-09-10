/* Write malformed UTF-16 that reg.set deliberately cannot create. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

int main(int argc, char **argv)
{
    const char *prefix = "Software\\kuu-test-suite\\";
    if (argc != 2 || strncmp(argv[1], prefix, strlen(prefix)) != 0) {
        return 2;
    }
    HKEY key = NULL;
    if (RegOpenKeyExA(HKEY_CURRENT_USER, argv[1], 0, KEY_SET_VALUE, &key) != ERROR_SUCCESS) {
        return 1;
    }
    const wchar_t bad_string[] = { 0xd800, 0 };
    const wchar_t bad_expand[] = { 0xdc00, 0 };
    const wchar_t bad_multi[] = { L'a', 0, 0xd800, 0, 0 };
    const BYTE odd_string[] = { 0x41 };
    int failed = 0;
    failed |= RegSetValueExW(key, L"bad_string", 0, REG_SZ, (const BYTE *)bad_string, sizeof bad_string) != ERROR_SUCCESS;
    failed |= RegSetValueExW(key, L"bad_expand", 0, REG_EXPAND_SZ, (const BYTE *)bad_expand, sizeof bad_expand) != ERROR_SUCCESS;
    failed |= RegSetValueExW(key, L"bad_multi", 0, REG_MULTI_SZ, (const BYTE *)bad_multi, sizeof bad_multi) != ERROR_SUCCESS;
    failed |= RegSetValueExW(key, L"odd_string", 0, REG_SZ, odd_string, sizeof odd_string) != ERROR_SUCCESS;
    RegCloseKey(key);
    return failed;
}

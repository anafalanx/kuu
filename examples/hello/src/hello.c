/* hello.c -- the whole program: built by a Zig this repository pins by hash. */
#include <stdio.h>

int main(int argc, char **argv)
{
    const char *who = argc > 1 ? argv[1] : "world";
    printf("hello, %s: built by zig, run by kuu\n", who);
    return 0;
}

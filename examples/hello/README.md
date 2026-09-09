# hello

The smallest repository kuu drives end to end: one C file, a compiler pinned
by hash, and a `tasks.lua`. Nothing here is installed on the machine and
nothing is looked up on `PATH`.

```text
tasks.lua          the tasks: hydrate, build, test, hello, clean
tools/lock.json    Zig 0.16.0, by url, sha256, size, and what `zig version` must say
src/hello.c        the program
.tools/            where Zig lands; git ignores it
build/             hello.exe and Zig's cache; git ignores it
```

With `kuu.exe` anywhere on your path, from this directory or below it:

```text
kuu run                    the default task, test: hydrate, build, run and check
kuu run build --release    an optimised build
kuu run hello moon         run it with an argument
kuu list                   the tasks and their arguments
kuu verify --deep          the toolchain against the lock, re-hashing the executable
kuu check                  tasks.lua parses, declares its globals, and its requires resolve
```

The first `kuu run` downloads the 97 MB Zig archive into `.tools/.downloads`,
checks its hash and size against the lock, unpacks it beside, runs
`zig version` and compares, and stamps it. Every run after that costs one stamp
check. Editing `tools/lock.json` makes the tool stale and the next run
re-installs it from the cache, or downloads the new bytes.

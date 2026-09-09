# proc

Children with decided lifetimes.

```lua
local proc = require("proc")
```

Every child kuu supervises is born into its own Windows Job Object, before its
first instruction runs, and the job is marked to kill on close. When kuu's
handle to the job goes away, because the program closed the child, dropped it,
finished, failed, or was killed itself, every process in that tree is
terminated by the kernel. This is the no-orphans law, and it is Windows'
promise rather than kuu's. Only `proc.detach` steps outside it, on purpose.

Waiting never blocks other tasks: `run` and `wait` park the calling coroutine
and the loop resumes it when the child is complete. Complete means the whole
job is empty and stdout and stderr have reached end of file, so a grandchild
that outlives the child keeps the result open, as it should.

## proc.run

```lua
local r, e = proc.run { "git", "status", "--short",
  cwd = "C:/work/app",           -- default: kuu's own
  env = { GIT_PAGER = "", HOME = false },   -- added or removed on top of kuu's
  timeout = "30s",               -- kill the tree and report status "timeout"
  stdin = bytes,                 -- written to the child, then closed
  maxout = "64M",                -- per stream; the default
}
local r = proc.run("cmd.exe", "/c", "echo hi")   -- plain arguments, no options
```

The array part is the command: the executable and its arguments, each a
string. A bare name such as `git` resolves from `PATH` only, never from the
current directory; a name with a separator is used as given; names without an
extension try `.exe`, `.com`, `.bat`, `.cmd`. Arguments are quoted for the
child exactly by the rules the child's C runtime parses them with, so what you
pass is what it receives: spaces, quotes, and backslashes need no escaping.

`r` is the result:

| field | meaning |
|---|---|
| `status` | `"exit"`, `"timeout"`, or `"killed"` |
| `code` | the exit code as an integer, untruncated |
| `out`, `err` | stdout and stderr as bytes |
| `pid` | the child's process id |
| `elapsed` | seconds from launch to completion |
| `truncated` | true when a stream exceeded `maxout` and the rest was dropped |

A timeout is a result, not an error: branch on `r.status`. `e` is set only when
the child could not be started, with these codes:

| PROC code | when |
|---|---|
| `notfound` | the program is not on `PATH` or does not exist |
| `launch` | Windows refused to create the process; the message says why |
| `badvalue` | a bad option value (`nil, err` for `cwd` that does not exist; raised for a malformed value) |
| `encoding` | a name is not valid UTF-8 |
| `usage` | raised: no command, a wrong argument shape, an unknown option |

Unknown option names raise rather than pass silently, so a typo cannot
become a run with the wrong settings.

## proc.start and the child handle

```lua
local c <close> = proc.start { "server.exe", "--port", "8080", timeout = "10m" }
c.pid                    -- integer
c:running()              -- true until the tree is done
local r, e = c:wait("5s")   -- the same result table as run; nil, PROC timeout if late
c:kill()                 -- terminate the tree now; wait then reports "killed"
c:close()                -- kill if still running, release everything
```

`start` accepts the same table as `run`. The `timeout` is the child's, counted
from launch and enforced whether or not anyone waits; a `wait` timeout only
bounds the wait. The handle is also closed by `<close>` at the end of its block
and by garbage collection, and either closing kills a tree that still runs.
After `close`, every method raises `PROC closed`. Repeated waits on a finished
child return the same result.

## proc.detach

```lua
local pid, e = proc.detach { "updater.exe", "--quiet", cwd = "C:/app" }
```

Starts a process that kuu does not supervise: it gets no console of kuu's, its
own process group, the null device for its standard streams, and it lives on
after kuu exits. Options are `cwd` and `env` only. If kuu itself runs inside a
job that permits breakaway, the process leaves that job; jobs that enclose kuu
and forbid breakaway keep it, which is that environment's policy, not kuu's.

kuu's own child jobs permit breakaway, so a program that kuu runs can itself
detach a process, and only a process that asks to break away leaves; nothing
escapes supervision by accident.

## proc.alive and proc.kill

```lua
proc.alive(pid)        -- true while a process with that id runs
proc.kill(pid)         -- true, or nil, PROC notfound | access | oserror
```

For processes kuu did not start. `kill` terminates one process, not a tree;
use a supervised child when the tree matters.

## Two things to know

- **`cmd.exe` parses its own line.** Quoting is done for programs that parse
  their command line the normal way. `cmd.exe /c` re-parses its argument by
  its own rules, so give it one plain argument without embedded quotes, or
  write a `.cmd` file and run that. Batch files are launched through a
  defensively quoted `cmd.exe`, the mitigation for CVE-2024-24576, so an
  argument like `a&b` reaches the script literally.
- **Output is bytes.** Windows programs write in whatever encoding they
  choose; `cmd.exe` writes CRLF line ends and the console code page. Decode
  deliberately.

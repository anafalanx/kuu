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
| `status` | `"exit"`, `"timeout"`, `"killed"`, or `"limit"` |
| `limit` | only for `status = "limit"`: `"memory"`, `"cpu"`, or `"processes"` |
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
| `oserror` | a job, pipe, or another launch resource could not be created |

Unknown option names raise rather than pass silently, so a typo cannot
become a run with the wrong settings.

`run` accepts `cwd`, `env`, `timeout`, `stdin`, `maxout`, `inherit`, and
`limits`; `start` additionally accepts `stream`. An omitted `timeout` has
no time limit; zero requests an immediate timeout. `inherit` and `stream`
default to false. Environment names are compared ignoring case: duplicates,
empty names, `=`, and NUL are refused, as are NUL bytes in text values.

## Limits

```lua
proc.run { "build.exe", timeout = "10m",
  limits = { memory = "512M", cpu = "30s", processes = 8 } }
```

`limits` applies to `run`, `start`, and `task.exec`. All three bounds are
job-wide, across the child and its descendants: `memory` is committed bytes,
`cpu` is accumulated user-mode CPU time, and `processes` is the number alive
at once, including the initial child. Each optional bound must be positive;
unknown names and malformed bounds raise `PROC badvalue`. An empty table
sets no bounds. `detach` does not accept limits.

Windows refuses allocations and child creation that exceed memory and process
limits; kuu terminates the job when the corresponding notification arrives.
The kernel terminates a job that exhausts its CPU time. The result has
`status = "limit"` and names the bound in `limit`. `timeout` is independently
elapsed wall-clock time; keep it when a child can wait without using CPU.
An intentional breakaway still follows the rules described under `detach`.

## proc.start and the child handle

```lua
local c <close> = proc.start { "server.exe", "--port", "8080", timeout = "10m" }
c.pid                    -- integer
c:running()              -- true until the tree is done
local r, e = c:wait("5s")   -- the same result table as run; nil, PROC timeout if late
c:kill()                 -- terminate the tree now; wait then reports "killed"
c:close()                -- kill if still running, release everything
```

`start` accepts the same table as `run`, plus `stream = true`. Both accept
`inherit = true`. The `timeout` is the child's, counted from launch and
enforced whether or not anyone waits; a `wait` timeout only bounds the wait.
The handle is also closed by `<close>` at the end of its block and by garbage
collection, and either closing kills a tree that still runs. `close` is
idempotent; after it, `pid` is nil and the other methods raise `PROC closed`.
Repeated waits on a finished child return
the same result.

## Streams

```lua
local c <close> = proc.start { "tool.exe", stream = true }
c:write("first line\n")          -- queued to the child's stdin; true, or nil, PROC closed | toobig
c:close_stdin()                  -- EOF for the child once the queue has drained
c:read("line", "5s")             -- the next stdout line without its ending; nil at EOF
c:read(4096)                     -- up to that many bytes, once at least one is there
c:read("some")                   -- whatever has arrived, once anything has
c:read("all")                    -- everything to EOF
c:read_err("line")               -- the same for stderr
for line in c:lines() do ... end -- stdout lines to EOF; c:err_lines() likewise
```

In stream mode the program reads the pipes itself, so `wait` reports the exit
with empty `out` and `err`. Reads that must wait park the calling task and
accept a timeout, returning `nil, err` with `PROC timeout` while the data stays
buffered. One task at a time may read a given stream; a second raises
`PROC busy`. `maxout` becomes the backpressure point: when that much is unread,
kuu stops reading and the child blocks on its write until the program catches
up, so nothing is ever truncated. Closing the child wakes a parked reader with
`PROC closed`. A child that does not read its stdin is not an error; a child
that never gets its stdin closed may never exit, so `close_stdin` when you are
done.

The stdin queue has its own fixed 64 MiB bound, independent of `maxout`.
`write` returns `nil, PROC toobig` when a write cannot be queued within it.

## The console

```lua
proc.run { "vim", "notes.md", inherit = true }
```

With `inherit = true` the child receives kuu's own standard handles: colours,
pagers, prompts, and Ctrl-C reach it as if it had been started from the
terminal, with every supervision guarantee intact. Nothing is captured; `out`
and `err` are empty. It cannot be combined with `stdin` or `stream`.

## Waiting on several children

```lua
local first, result = proc.wait_any({ a, b, c }, "1m")   -- the handle and its result
local results = proc.wait_all({ a, b, c }, "10m")        -- results in the order given
```

Both return `nil, err` with `PROC timeout` when the duration passes; the
children keep running. Children that already finished answer at once.

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

## proc.list, proc.find, proc.tree

```lua
proc.list()                    -- every process on the machine, sorted by pid
proc.find { name = "node" }    -- by executable name, ignoring case and the extension
proc.find { pid = 4120 }       -- one entry, or none
proc.find { port = 8080 }      -- the owners of TCP listeners on that port
proc.tree(pid)                 -- the entry with its `children`, recursively; nil, PROC notfound
```

An entry:

| field | |
|---|---|
| `pid`, `parent`, `name`, `threads` | from the process snapshot; always present |
| `exe` | the full UTF-8 path of the executable, with forward slashes like `fs.absolute` |
| `cmdline` | the command line as the kernel holds it |
| `started` | when the process began, an instant for [`time`](time.md) |
| `cpu` | seconds of kernel plus user time so far |
| `memory`, `private` | the working set and the private bytes |

The last six need the process opened for querying and are absent when this
user may not: system processes, another user's, protected ones. `find`
returns a list, empty when nothing matches; looking for something that is
not there is not an error. It takes exactly one of `name`, `pid`, `port` and
raises PROC badvalue otherwise. `tree` answers `nil, PROC notfound` for an
unknown pid. Process ids are reused, so a `parent` may name a process that
exited long ago and whose id now belongs to something unrelated.
Tree expansion stops after 64 levels; a deepest entry then has no expanded
children.

## Complete error codes

| PROC code | when |
|---|---|
| `notfound` | a command or requested process does not exist |
| `launch` | Windows refused to start the command |
| `access` | `kill` cannot open the process for termination |
| `badvalue` | malformed arguments or option values; usually raised, but returned for a refused working directory or invalid `kill` pid |
| `encoding` | a command, path, environment entry, or process-name filter is not UTF-8 |
| `usage` | raised: an invalid call shape, unknown option, incompatible stream modes, or a read/write without stream mode |
| `timeout` | a child wait, stream read, `wait_any`, or `wait_all` outlasted its wait duration |
| `closed` | raised for a closed handle; returned when stdin is closed or a pending read's handle closes |
| `busy` | raised: another task is already reading that stream |
| `toobig` | stdin could not queue the write within its 64 MiB bound |
| `oserror` | Windows, snapshot, or allocation failure |

Waiting can also propagate the scheduler's `SCHED` errors, including
`deadline`; see [sched](sched.md). Child results with `status = "timeout"`,
`"killed"`, or `"limit"` are result states, not error codes.

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

## Tools that construct their own commands

Kuu preserves the argument vector it passes to a child. A child may construct
another command string internally. For example, Windows `windres` uses a shell
for its preprocessor by default and can split checkout paths containing spaces.
Use its `--use-temp-file` mode and relative resource/include paths from a build
directory. Quoting only the original Kuu argument cannot repair that internal
command. Process metadata's `cmdline` stays verbatim; only `exe` is normalized.
Use `fs.canon` identity when different path spellings or aliases must compare equal.

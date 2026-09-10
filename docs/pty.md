# pty -- provisional console automation

`local pty = require "pty"`

`pty` drives Windows console programs through ConPTY. It is **provisional**
and outside the planned 1.0 API freeze. Use `proc` for ordinary subprocesses.

```lua
global none
global <const> require, assert
local pty = require "pty"
local p <close> = assert(pty.spawn { "cmd.exe", "/d", "/q", cols = 120, rows = 30 })
assert(p:expect({ ">" }, "5s"))
assert(p:write("echo hello\r"))
local text, which = assert(p:expect({ "hello", "error" }, "5s"))
assert(p:write("exit\r"))
assert(p:wait("5s"))
```

## Launch and lifetime

`pty.spawn { exe, args..., cols = 120, rows = 30, cwd = path, env = table,
timeout = duration, maxout = "64M", limits = table }` returns a console
handle or `nil, err`. Dimensions must be integers from 1 to 32767. The
command, `cwd`, environment overrides/removals, lifetime `timeout`, and
job `limits` follow [proc](proc.md). Without a lifetime timeout the child
can run indefinitely. `stdin`, `stream`, `inherit` and unknown options are
refused; input is written through the console handle.

The child is born into a kill-on-close job. `p.pid` identifies that child.
Windows also starts a `conhost.exe` process: it is visible in `proc.tree`
under the hosting kuu process, and exits when the console session ends.
It is a console host, not an extra application launched by the script.
Use `<close>` to terminate the child tree and release the console on all
paths. `p:close()` is idempotent. The host's pipe ends use overlapped I/O;
read, expect, and process waits keep the event loop running. On kuu's
minimum supported Windows release, closing the console is asynchronous.

`p:write(bytes)` queues UTF-8 console input and returns `true` or `nil, err`.
Use `"\r"` for Enter. Input includes control sequences when the console
application expects them. The pending input queue is bounded at 64 MiB.
`p:resize(cols, rows)` changes the console buffer size and returns
`true` or `nil, err`.

`p:wait([timeout])` returns the [proc result](proc.md), including `status`,
`code`, `pid`, `elapsed` and optional `limit`. Output is consumed through
`read`/`expect`; the result's `out` and `err` are empty. A wait timeout
returns `nil, PTY timeout` and leaves the child alive. `p:kill()` terminates
the entire child job; `wait` can still observe its result. A scope deadline
interrupts the current wait with `SCHED deadline`; it does not close `p`.

## Output and matching

`p:read([timeout])` returns the next raw byte chunk, including VT sequences.
It returns `nil` at EOF, or `nil, PTY timeout` when nothing arrives in time.
The default read timeout is unlimited. Both stdout and stderr use the same
console stream. Raw chunks may split a UTF-8 character or a VT sequence.

`p:text()` returns the plain text consumed so far by `read` and `expect`.
It does not wait for or drain unread output. The filter retains partial
UTF-8 characters and escape sequences across reads, drops CSI and OSC,
applies carriage return, line feed and backspace, preserves tabs, and ignores other control
bytes. Carriage return makes subsequent characters overwrite the current
line; backspace erases its previous character. This is a text filter with
no cursor addressing, screen model, full-screen editor support, or display
width calculation. Resizing may cause a program to redraw and repeat text.

`p:expect({ pattern, ... } [, timeout])` searches that plain text using
**Lua patterns**, returning `text, index`: all unconsumed text through the
match and the one-based pattern index. The earliest match wins; array order
breaks ties. Matching resumes after the previous match. Rewriting consumed
characters on the current line makes the changed region available again.
An empty match advances the cursor by one byte. Captures are not returned.
The timeout defaults to 30 seconds; zero polls already available output.
Timeout leaves the console alive and the unmatched text available for the
next call. EOF before a match is `nil, PTY closed`. Only one `read` or
`expect` may be active per console; a second raises `PTY busy`.

`maxout` is a positive byte size and bounds both buffered raw output and
the accumulated transcript input. Crossing the transcript cap returns
`nil, PTY toobig` on this and later reads/expect calls. Close the console
or use a larger cap when spawning a new one. Read while a chatty program
runs: waiting for exit without draining a full output buffer can leave that
program blocked on output.

## Errors

The closed PTY code set is `badvalue` (invalid command/options/dimensions,
duration, or a rejected Lua pattern), `notfound` (executable), `encoding`
(invalid UTF-8 command/environment), `launch` (process creation), `busy`
(concurrent read or pending input conflict), `closed` (closed handle or EOF
before a match), `timeout` (wait expired), `toobig` (output/input bound),
and `oserror` (native operation or allocation failure). Invalid arguments
raise; operational failures return `nil, err`. An enclosing deadline raises
`SCHED deadline` internally and is caught by its `sched.deadline` scope.

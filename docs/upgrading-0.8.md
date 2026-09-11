# Upgrading to 0.8

0.8 lowers the Windows 11 minimum to **23H2** and fixes a memory-lifetime
defect in the JSON duplicate-key diagnostic. Windows Server still requires
2025 or later. The public Lua API is unchanged from 0.7, and `pty` remains
provisional and outside the planned 1.0 freeze.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, run `kuu check`, and run the project's tasks.
Projects using 0.7 features can keep their existing minimum-version guard;
projects deployed to 23H2 should require 0.8 or later. For earlier releases,
also read [upgrading to 0.7](upgrading-0.7.md) and the
[0.6 duration migration](upgrading-0.6.md).

## Windows 11 23H2

The signed 0.7 executable imports `ReleasePseudoConsole`, which 23H2 does
not provide, and fails before any Lua program can run. In 0.8 that function
is resolved only when the host exports it. The original 0.7 release asset
and checksum remain unchanged.

On 23H2, console shutdown uses independent close and output-drain workers.
Natural close waits for the entire supervised job and preserves final
output. Explicit close finishes canceled I/O before handing the pipe to a
native drainer; resize is refused once shutdown can begin. Newer Windows
versions retain their existing release and asynchronous-close path. See
[pty](pty.md) for the lifetime contract.

Queued I/O completions also keep a stable dispatch key after their owner is
released, so a Lua finalizer can run another process during shutdown without
accessing freed console state.

## JSON diagnostics

`json.decode` now formats a duplicate-key error while the parser still owns
the key's bytes. Previously it freed those bytes first, causing a use after
free while constructing the message. Duplicate keys still return
`nil, err` with domain `JSON` and code `duplicate`.

The [observed shortcomings](shortcomings.md) record the compatibility
validation and unresolved intermittent file-access and process-tree checks.
This release does not claim to resolve those separate findings.

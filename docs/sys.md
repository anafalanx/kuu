# sys

Facts about this machine and this process, read fresh on every call.

```lua
local sys = require("sys")
local i = sys.info()
-- i.windows.build      26200            an integer; Windows 11 is 22000 and above
-- i.windows.revision   6584             the update build revision, the fourth number
-- i.windows.version    "10.0.26200"     what the kernel reports, truthfully
-- i.windows.display    "25H2"           the marketing name, from the registry
-- i.windows.server     false            a Windows Server edition
-- i.hostname           "FORGE"
-- i.user               "anafa"
-- i.elevated           false            running with administrator rights
-- i.cpus               16
-- i.arch               "x64"            or "arm64"
-- i.memory.total       68584734720      bytes; i.memory.available likewise
-- i.drives             { { letter = "C:", type = "fixed" }, { letter = "D:", type = "removable" } }
-- i.uptime             84213.5          seconds since boot
-- i.pid                4120
-- i.codepage           1252             the ANSI code page programs without UTF-8 use
-- i.process            { handles = 61, working_set = 9437184, peak_working_set = 9502720, private = 5242880 }
```

`process` is this kuu, in bytes and handles, for a program that keeps an eye
on itself; the soak test watches it across rounds.

Drive types are `fixed`, `removable`, `remote`, `cdrom`, `ramdisk`, or
`unknown`. The version comes from `RtlGetVersion`, which tells the truth
where the older calls lie to programs without a manifest. `elevated` is what a
PowerShell script means by `IsInRole(Administrator)`: this process, now, with
this token. Nothing here is cached and nothing here writes.

## sys.signature

```lua
local signature, e = sys.signature("installer.exe")
local signature, e = sys.signature("installer.exe", { revocation = true })
```

An unsigned file returns `{ signed = false }`. An embedded signed file returns
`{ signed = true, valid = true, signer, issuer, thumbprint, timestamped }`.
`signer` and `issuer` are the certificate display names, and `thumbprint` is
the leaf certificate's 40-character uppercase SHA-1 identifier. `timestamped`
reports the presence of a countersignature or RFC 3161 timestamp attribute.
It is separate from validity; an invalid timestamp can still be present.

A failed trust check returns `signed = true, valid = false, reason = ...`.
Reasons are `expired`, `untrusted`, `tampered`, `revoked`, `distrusted`,
`revocation` (the revocation check could not complete), `timestamp`, `usage`,
or `invalid` (another trust failure). Certificate identity fields can be absent
if a damaged signature could not be decoded. A trust failure is a result,
not `nil, err`.

Only embedded Authenticode signatures are inspected. Files signed only through
a Windows catalog report `signed = false`; no catalog lookup is performed.
Revocation checks and network certificate retrieval are disabled by default.
`revocation = true` enables chain revocation checking and may use the network.
Verification runs on a worker so the Lua loop keeps running. A surrounding
`sched.deadline` can abandon the wait, but Windows' verification itself cannot
be cancelled; its resources remain owned until it finishes. Shutdown waits
for an outstanding verification to finish before freeing the loop.

`valid` means Windows accepted the signature under the selected trust policy.
Before running an installer, also match its signer or pinned thumbprint to the
identity you expect. Signature inspection opens the file for reading and
prevents writes while checking it; it does not reserve the path after return.

## Errors

The complete SYS code set is `notfound` (missing signature path), `access`
(the file cannot be read or is open for writing), `badvalue` (raised for a
malformed path, a directory, or signature options), and `oserror` (other
Windows or allocation failures). `sys.info` has no expected error return.

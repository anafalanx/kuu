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

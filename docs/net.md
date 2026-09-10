# net

The network as seen from this machine: what a name resolves to, whether a
port answers, who is listening here, and which addresses this machine has.
Where an agent would reach for `Test-NetConnection`, `Resolve-DnsName`,
`Get-NetTCPConnection`, `netstat -ano`, or `ipconfig`.

```lua
local net = require "net"

net.resolve("example.org")              -- { { address = "93.184.215.14", family = "ipv4" }, ... }
net.probe("localhost", 5432, "2s")      -- { address = "127.0.0.1", family = "ipv4", elapsed = 0.003 }
net.listeners()                         -- { { port = 135, address = "0.0.0.0", family = "ipv4", pid = 1204, name = "svchost.exe" }, ... }
net.addresses()                         -- { { adapter = "Ethernet", address = "192.168.1.20", family = "ipv4", prefix = 24, up = true, ... }, ... }
```

Resolving and probing park the calling task and let the others run; both
take a timeout, five seconds unless given. `listeners` and `addresses` take
synchronous snapshots of Windows' local tables.

## net.resolve

```lua
net.resolve(name [, timeout])   -- { { address, family }, ... } | nil, err
```

Every address the name resolves to, IPv4 and IPv6, in the order the system
returns them. An address literal resolves to itself, so a caller need not
check first. `family` is `"ipv4"` or `"ipv6"`. IPv6 addresses keep their
numeric interface scope, such as `fe80::1%1`, in both `resolve` and
`addresses`; `probe` accepts that same spelling.

Failures: `nil, NET resolve` when the name has no address, `nil, NET timeout`
when nothing answered in time. An empty name, a name with NUL, or a malformed timeout is a
programming error and raises NET badvalue.

## net.probe

```lua
net.probe(host, port [, timeout])   -- { address, family, elapsed } | nil, err
```

Resolves the host, then tries to open a TCP connection to each address in
turn until one accepts; the connection is closed at once. The result says
which address answered and how many seconds the whole probe took. A port
that is closed answers with `nil, NET refused`; one behind a silent
firewall, or an address nobody has, ends in `nil, NET timeout`; no route at
all is `nil, NET unreachable`. The timeout bounds the whole probe, resolution
included.

Windows retries a refused connection before giving up, so `refused` arrives
after about two seconds, even on the loopback interface. Give a probe three
seconds or more when you need refused told apart from silence; a short
timeout is fine when you only care whether the port is up yet.

```lua
-- wait for a service to come up
local deadline = sched.clock() + 30
repeat
  local up = net.probe("127.0.0.1", 8080, "1s")
  if up then break end
  sched.sleep("500ms")
until sched.clock() > deadline
```

## net.listeners

```lua
net.listeners()   -- { { port, address, family, pid, name }, ... }
```

Every TCP port with a listening socket on this machine, sorted by port, with
the address it is bound to (`0.0.0.0` or `::` for all interfaces), the owning
process id, and that process's executable name where a process by that id
still exists. The same table answers `proc.find { port = }` in
[`proc`](proc.md), which gives the owner's full entry. UDP is not listed.

## net.addresses

```lua
net.addresses()   -- { { adapter, description, address, family, prefix, up, loopback, mac }, ... }
```

One row per unicast address on every adapter, loopback and link-local
included: the adapter's friendly name and description, the address and its
family, the on-link prefix length, whether the adapter is up, whether it is
the loopback interface, and its MAC address when it has one. To find the
machine's own routable IPv4, filter for `up`, not `loopback`, `family ==
"ipv4"`, and an address not starting with `169.254.`.

## Errors

Domain `NET`.

| code | when |
|---|---|
| `resolve` | the name has no address |
| `refused` | the port is closed: the host answered with a reset |
| `timeout` | nothing answered within the timeout |
| `unreachable` | no route to the address, or the address cannot be used from here |
| `badvalue` | a bad host, port, or timeout (raised) |
| `oserror` | Winsock or the IP helper failed in some other way |

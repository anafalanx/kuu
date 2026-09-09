-- net/probe.lua -- the resolving half of net.probe: a host name is resolved
-- first and every address is tried in turn until one answers.  Installed
-- into the net table when the module opens; the C half probes one literal
-- address.
global none
global <const> require, ipairs, type, tostring, error, math

return function(net)
  local sched = require "sched"
  local err = require "err"
  local cli = require "cli"
  local reach = net.probe

  -- net.probe(host, port [, timeout]) -> { address, family, elapsed } | nil, err
  --   NET resolve | refused | timeout | unreachable | oserror; the default timeout is 5s
  function net.probe(host, port, timeout)
    if type(host) ~= "string" or host == "" then
      error(err.new("NET", "badvalue", "probe needs a host name or address"), 2)
    end
    if math.type(port) ~= "integer" or port < 1 or port > 65535 then
      error(err.new("NET", "badvalue", "the port must be 1 to 65535"), 2)
    end
    local ms = 5000
    if timeout ~= nil then
      ms = cli.duration(timeout)
      if ms == nil then error(err.new("NET", "badvalue", "the probe timeout must be a duration such as \"2s\""), 2) end
    end
    local started = sched.clock()
    local deadline = started + ms / 1000
    local addresses, e = net.resolve(host, ms / 1000)
    if addresses == nil then return nil, e end
    local last
    for _, a in ipairs(addresses) do
      local remaining = deadline - sched.clock()
      if remaining <= 0 then
        return nil, err.new("NET", "timeout", "no answer from " .. host .. ":" .. tostring(port) .. " within the timeout")
      end
      local ok, e2 = reach(a.address, port, remaining)
      if ok then
        return { address = a.address, family = a.family, elapsed = sched.clock() - started }
      end
      last = e2
    end
    return nil, last
  end
end

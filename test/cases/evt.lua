global none
global <const> require, ipairs, type, tostring, math, pcall

return function(T)
  local check = T.check
  local evt, err, time = require "evt", require "err", require "time"
  local logs, le = evt.logs()
  local application, system = false, false
  for _, name in ipairs(logs or {}) do
    if name == "Application" then application = true end
    if name == "System" then system = true end
  end
  check("channel enumeration contains Application and System", application and system, tostring(le))
  local since = time.now() - 86400
  local rows, e = evt.read("System", { since = since, limit = 20 })
  check("System's recent events return a bounded table", type(rows) == "table" and #rows <= 20, tostring(e))
  local shape, order = true, true
  for i, row in ipairs(rows or {}) do
    shape = shape and type(row.time) == "number" and row.time >= since - 0.002 and type(row.level) == "string"
      and math.type(row.id) == "integer" and type(row.provider) == "string"
      and type(row.message) == "string" and math.type(row.record) == "integer" and type(row.computer) == "string"
    if i > 1 and row.record >= rows[i - 1].record then order = false end
  end
  check("events have typed fields and newest records first", shape and order)
  local errors, ee = evt.read("System", { level = "error", limit = 8 })
  local filtered = errors ~= nil
  for _, row in ipairs(errors or {}) do filtered = filtered and row.level == "error" end
  check("the error-level filter holds", filtered, tostring(ee))
  if rows and rows[1] then
    local provider = rows[1].provider
    local selected, se = evt.read("System", { provider = provider, limit = 3 })
    local holds = selected ~= nil and #selected > 0
    for _, row in ipairs(selected or {}) do holds = holds and row.provider == provider end
    check("the provider filter holds", holds, tostring(se))
  end
  local none, ne = evt.read("kuu-no-such-channel-6a573dd0")
  check("an absent channel is EVT notfound", none == nil and err.is(ne, "EVT", "notfound"), tostring(ne))
  local future, fe = evt.read("System", { since = time.now() + 86400, limit = 1 })
  check("a query with no events returns an empty table", future ~= nil and #future == 0, tostring(fe))
  for _, options in ipairs({ { limit = 0 }, { limit = 100001 }, { limit = 1.5 }, { limit = "10" },
      { level = "fatal" }, { since = "yesterday" }, { since = math.huge }, { provider = "bad\0name" },
      { unknown = true }, { provider = 42 }, { level = true }, { ["limit\0other"] = 1 } }) do
    local ok, be = pcall(evt.read, "System", options)
    check("bad event options raise EVT badvalue", not ok and err.is(be, "EVT", "badvalue"), tostring(be))
  end
  local ok, be = pcall(evt.read, "System\0other")
  check("a NUL in a channel is refused", not ok and err.is(be, "EVT", "badvalue"), tostring(be))
  local quoted, qe = evt.read("System", { provider = "absent' or Level=1 or 'provider", limit = 1 })
  check("a quote in a provider stays literal", quoted ~= nil and #quoted == 0, tostring(qe))
end

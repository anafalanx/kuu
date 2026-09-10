-- env.lua -- the live environment and the persisted one, under a variable of our own.
global none
global <const> require, tostring, type, string, pcall, os, select, pairs, next, ipairs

return function(T)
  local check = T.check
  local env = require "env"
  local reg = require "reg"
  local err = require "err"
  local sys = require "sys"
  local proc = require "proc"
  local hash = require "hash"

  local name = "KUU_TEST_" .. (hash.uuid():gsub("-", "")):sub(1, 8):upper()
  check("an unset variable is nil", env.get(name) == nil)
  check("set makes it visible to os.getenv and env.all",
    env.set(name, "één") == true and env.get(name) == "één" and os.getenv(name) == "één" and env.all()[name] == "één")
  local r = proc.run { T.exe, "-e", "io.write(os.getenv('" .. name .. "'))" }
  check("children inherit it", r ~= nil and r.out == "één", r and r.out)
  check("expand fills in references", env.expand("%" .. name .. "%/x") == "één/x" and env.expand("%SystemRoot%") == os.getenv("SystemRoot"))
  check("set to nil removes it, twice is fine", env.set(name, nil) == true and env.get(name) == nil and env.set(name, nil) == true)
  local okn, en = pcall(env.set, "A=B", "x")
  check("a name with = is ENV badvalue", not okn and err.is(en, "ENV", "badvalue"), tostring(en))
  local all, seen = env.all(), {}
  for k in pairs(all) do seen[k:lower()] = true end
  check("all has the usual suspects, named as the process was given them", seen.systemroot and seen.path and seen.temp, tostring(next(all)))

  check("nothing persisted under our name yet", env.persisted(name) == nil)
  check("persist stores the value for the user", env.persist(name, "plain") == true)
  local v, t = env.persisted(name)
  check("persisted reads it back as a string", v == "plain" and t == "string", tostring(v))
  check("a value with a % is stored as expandstring",
    env.persist(name, "%SystemRoot%\\bin") and select(2, env.persisted(name)) == "expandstring" and select(2, reg.get("HKCU\\Environment", name)) == "expandstring")
  check("the process environment is untouched by persisting", env.get(name) == nil)
  check("forget removes it", env.forget(name) == true and env.persisted(name) == nil)
  local none, e = env.forget(name)
  check("forgetting again is nil, ENV notfound", none == nil and err.is(e, "ENV", "notfound"), tostring(e))
  local okb, eb = pcall(env.persist, name, "x", "galaxy")
  check("an unknown scope is ENV badvalue", not okb and err.is(eb, "ENV", "badvalue"), tostring(eb))
  if not sys.info().elevated then
    none, e = env.persist(name, "x", "machine")
    check("the machine scope without elevation is nil, ENV access", none == nil and err.is(e, "ENV", "access"), tostring(e))
  end
  local path = env.persisted("Path")
  check("the user's persisted Path reads unexpanded, or is absent", path == nil or type(path) == "string")
  do
    env.set(name, "")
    check("an empty live variable remains distinct from an unset one",
      env.get(name) == "" and os.getenv(name) == "" and env.all()[name] == "")
    local child = proc.run { T.exe, "-e", "assert(os.getenv('" .. name .. "') == ''); io.write('empty')" }
    check("a child inherits an empty variable", child and child.code == 0 and child.out == "empty")
    local calls = {
      function() return env.get(name .. "\0ignored") end,
      function() return os.getenv(name .. "\0ignored") end,
      function() return env.set(name .. "\0ignored", "wrong") end,
      function() return env.set(name, "before\0after") end,
      function() return env.expand("before\0after") end,
      function() return env.persisted(name .. "\0ignored") end,
      function() return env.persist(name .. "\0ignored", "wrong") end,
      function() return env.persist(name, "before\0after") end,
      function() return env.forget(name .. "\0ignored") end,
    }
    for i, call in ipairs(calls) do
      local ok, e = pcall(call)
      check("environment native text refuses NUL, case " .. i, not ok and err.is(e, "ENV", "badvalue"), tostring(e))
    end
    check("refused NUL arguments do not change or persist the real variable", env.get(name) == "" and env.persisted(name) == nil)
    env.set(name, nil)
    check("removing an empty variable makes it absent", env.get(name) == nil and os.getenv(name) == nil)
  end

end

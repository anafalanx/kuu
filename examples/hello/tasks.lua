-- tasks.lua -- the hello example: a C program built with a Zig pinned by hash.
--
--   kuu run                    hydrate the toolchain (a download once, a stamp check after), build, test
--   kuu run build --release    just build, optimised
--   kuu run hello moon         run the program with an argument
--   kuu list | kuu verify --deep | kuu check
global none
global <const> require, ipairs, tostring, string, io, print

local task = require "task"
local toolchain = require "toolchain"
local proc = require "proc"
local fs = require "fs"
local err = require "err"

local LOCK, TOOLS = "tools/lock.json", ".tools"

task "hydrate" {
  desc = "fetch the pinned Zig into .tools, or confirm it is there",
  run = function()
    local report, e = toolchain.hydrate(LOCK, TOOLS, {
      progress = function(step, name, detail) io.stderr:write("  ", step, " ", name, ": ", detail, "\n") end,
    })
    if not report then return nil, e end
    for _, t in ipairs(report.tools) do
      print(string.format("  %-8s %s %s", t.action, t.name, t.version or ""))
    end
  end,
}

task "build" {
  desc = "compile src/hello.c to build/hello.exe with zig cc",
  deps = { "hydrate" },
  args = { { "--release", type = "flag", help = "optimise with -O2 instead of -g" } },
  run = function(opts)
    local zig, e = toolchain.path(LOCK, "zig", TOOLS)
    if not zig then return nil, e end
    fs.mkdir("build")
    return task.exec {
      zig, "cc", opts.release and "-O2" or "-g", "-Wall", "-Wextra", "-Werror",
      "src/hello.c", "-o", "build/hello.exe",
      env = { ZIG_GLOBAL_CACHE_DIR = "build/zig-cache", ZIG_LOCAL_CACHE_DIR = "build/zig-cache" },
    }
  end,
}

task "test" {
  desc = "run build/hello.exe and check what it says",
  deps = { "build" },
  run = function()
    local r, e = proc.run { "build/hello.exe", "moon", timeout = "10s" }
    if not r then return nil, e end
    if r.status ~= "exit" or r.code ~= 0 then
      return nil, err.new("TEST", "failed", "hello.exe " .. r.status .. " " .. tostring(r.code))
    end
    -- hello.exe writes through the C runtime in text mode, so its newline
    -- arrives as CRLF; kuu hands over the bytes as they are
    local got = r.out:gsub("\r?\n$", "")
    if got ~= "hello, moon: built by zig, run by kuu" then
      return nil, err.new("TEST", "failed", "unexpected output: " .. string.format("%q", r.out))
    end
    print("  hello.exe said what it should")
  end,
}

task "hello" {
  desc = "run build/hello.exe with an argument",
  deps = { "build" },
  args = { { "who", default = "world", help = "whom to greet" } },
  run = function(opts) return task.exec { "build/hello.exe", opts.who } end,
}

task "clean" {
  desc = "remove build/ (the toolchain in .tools stays)",
  run = function() fs.remove("build", { recursive = true }) end,
}

task.default "test"

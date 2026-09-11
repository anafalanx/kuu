-- An authored description of the palette's interface, read by `check`.
-- A private module: the leading underscore puts it outside the public
-- contract, and nothing outside check is meant to require it.
--
-- The manifest is authored, never inferred.  That law is usually about not
-- scanning implementation text; here it has a second, measured reason.  The
-- closed sets are documented for people, in at least two spellings -- a bare
-- `notfound` in a table headed "FS code", and a combined `ARCHIVE notfound`
-- elsewhere -- and an attempt to scrape them returned option names, result
-- fields and `re`'s flags as though they were error codes, and nothing at all
-- for six domains.  So they are written here by hand, once, and
-- test/cases/palette.lua checks this file against the runtime and the manual
-- in both directions.
--
-- What a checker buys from this, in the order the contract audit ranked it:
--   * `err.is(e, DOMAIN, code)` with a code that domain does not have --
--     today the call returns false, the branch never runs, and nothing says so
--   * a comparison of a closed-set field against a non-member, such as
--     `r.status == "exited"`, which fails the same silent way
--   * a misspelled field on a result or an option table
--   * `rt.version` compared by text, the one live instance on record
--
-- Types are spelled as strings.  A name in `scalars` or `enums` refers to
-- this file; anything else is a Lua type name.  A trailing `?` means the
-- field may be absent.  `a|b` is either.
global none

return {

-- Nominal scalars.  Each is a Lua number or string that carries a unit or a
-- shape the language cannot see, which is exactly where mistakes hide: the
-- worst bug on record turned a 100 ms deadline into a 100 second one between
-- two APIs that both took `number`.
scalars = {
  Duration = { over = "number|string",
    note = "seconds as a number, or a unit string: 250ms, 30s, 1.5m, 2h, 2d, 1h30m. A string without a unit is refused." },
  Size     = { over = "number|string",
    note = "bytes as a number, or a size string: 16M, 8G." },
  Instant  = { over = "number",
    note = "seconds since the Unix epoch, fractional, exact to the millisecond." },
  Version  = { over = "string",
    note = "Major.Minor.Patch since 0.9.0. Never compared by text: use rt.version_at_least." },
  Hex      = { over = "string", note = "lowercase hex digits." },
},

-- Closed sets.  A comparison against a non-member is the silent failure this
-- description exists to catch.
enums = {
  ProcStatus = { "exit", "timeout", "killed", "limit" },
  ProcLimit  = { "memory", "cpu", "processes" },
  FsKind     = { "file", "directory", "link", "other" },
  LinkType   = { "junction", "directory symlink", "file symlink" },
  WatchAction = { "added", "removed", "modified", "renamed", "overflow" },
  SvcState   = { "running", "stopped", "start_pending", "stop_pending",
                 "paused", "pause_pending", "continue_pending" },
  SvcStart   = { "auto", "manual", "disabled", "boot", "system" },
  SigReason  = { "expired", "untrusted", "tampered", "revoked", "distrusted",
                 "revocation", "timestamp", "usage", "invalid" },
  RegType    = { "string", "expandstring", "multistring", "dword", "qword",
                 "binary", "unknown" },
  LogLevel   = { "debug", "info", "warn", "error", "off" },
  EvtLevel   = { "critical", "error", "warning", "information", "verbose" },
  DriveType  = { "fixed", "removable", "remote", "cdrom", "ramdisk", "unknown" },
  Family     = { "ipv4", "ipv6" },
  Route      = { "file", "stdin", "eval", "cmd" },
  Scope      = { "user", "machine" },
  CliType    = { "flag", "string", "int", "number", "duration", "size" },
},

-- Every error domain and its complete code set, as each module page states
-- it.  This is the highest-value entry in the file: 240 err.is call sites in
-- the measured corpus, every one of which is a pair of string literals that
-- nothing checks today.
errors = {
  ENTRY   = { "usage", "notfound", "access", "badvalue", "toobig", "encoding",
              "stdin", "oserror" },
  RT      = { "badvalue" },
  PROC    = { "notfound", "launch", "access", "badvalue", "encoding", "usage",
              "timeout", "closed", "busy", "toobig", "oserror" },
  FS      = { "notfound", "dangling", "access", "exists", "notempty", "toobig",
              "encoding", "badvalue", "usage", "timeout", "closed", "oserror" },
  HTTP    = { "timeout", "notfound", "connect", "tls", "toobig", "mismatch",
              "status", "badvalue", "encoding", "usage", "oserror" },
  NET     = { "resolve", "refused", "timeout", "unreachable", "badvalue",
              "oserror" },
  SCHED   = { "timeout", "deadline", "badvalue", "yield", "deadlock", "oserror" },
  JSON    = { "parse", "duplicate", "depth", "badvalue", "encoding", "oserror" },
  CSV     = { "parse", "badvalue" },
  INI     = { "badvalue" },
  HASH    = { "badvalue", "encoding", "notfound", "access", "closed", "oserror" },
  TEXT    = { "invalid", "unencodable", "unsupported", "badvalue", "toobig",
              "oserror" },
  RE      = { "badpattern", "badvalue", "invalid", "limit", "oserror" },
  TIME    = { "badvalue", "oserror" },
  ARCHIVE = { "notfound", "failed", "badvalue", "timeout", "encoding", "toobig",
              "oserror" },
  LOG     = { "badvalue", "usage", "oserror" },
  MEM     = { "toobig", "badvalue", "corrupt", "unreadable" },
  SYNC    = { "busy", "badvalue", "oserror", "encoding" },
  SYS     = { "notfound", "access", "badvalue", "oserror" },
  REG     = { "notfound", "access", "badvalue", "encoding", "oserror" },
  ENV     = { "badvalue", "notfound", "access", "oserror" },
  SVC     = { "notfound", "access", "timeout", "badvalue", "oserror" },
  EVT     = { "notfound", "access", "badvalue", "oserror" },
  PTY     = { "badvalue", "notfound", "encoding", "launch", "busy", "closed",
              "timeout", "toobig", "oserror" },
  TASK    = { "noproject", "badvalue", "usage", "unknown", "cycle", "failed",
              "exit" },
  CHECK   = { "notfound" },
  CLI     = { "usage", "badvalue" },
},

-- Shared shapes, named so a function need not repeat them.
records = {
  Err = {
    domain = "string", code = "string", message = "string", exit = "integer?",
  },
  Limits = {
    memory = "Size?", cpu = "Duration?", processes = "integer?",
  },
  ProcResult = {
    status = "ProcStatus", limit = "ProcLimit?", code = "integer",
    out = "string", err = "string", pid = "integer", elapsed = "number",
    truncated = "boolean?",
  },
  Stat = {
    kind = "FsKind", size = "integer", mtime = "Instant", ctime = "Instant",
    atime = "Instant", attrs = "integer", hidden = "boolean",
    readonly = "boolean", system = "boolean", reparse = "string?",
    volume = "Hex", file = "Hex", links = "integer",
  },
  Canon = {
    path = "string", volume = "Hex", file = "Hex", kind = "FsKind",
    links = "integer",
  },
  Response = {
    status = "integer", headers = "table", rawheaders = "string",
    body = "string", bytes = "integer", path = "string?",
  },
},

-- Per-module function descriptions.  Deep where the measured traffic is:
-- fs, err, json, sched, rt and proc carry the most field access in the
-- corpus.  Absent entries mean not yet written, never "takes anything".
modules = {

  proc = {
    run = { options_at = 1,
      options = { cwd = "string?", env = "table?", timeout = "Duration?",
                  stdin = "string?", maxout = "Size?", inherit = "boolean?",
                  limits = "Limits?" },
      result  = "ProcResult",
      errors  = { "notfound", "launch", "badvalue", "encoding", "usage", "oserror" },
    },
    start = { options_at = 1,
      options = { cwd = "string?", env = "table?", timeout = "Duration?",
                  stdin = "string?", maxout = "Size?", inherit = "boolean?",
                  limits = "Limits?", stream = "boolean?" },
      result  = "handle",
      errors  = { "notfound", "launch", "badvalue", "encoding", "usage", "oserror" },
    },
    detach   = { options_at = 1, options = { cwd = "string?", env = "table?" }, result = "integer" },
    alive    = { result = "boolean" },
    kill     = { result = "boolean", errors = { "notfound", "access", "oserror" } },
    list     = { result = "table" },
    find     = { options_at = 1, options = { name = "string?", pid = "integer?", port = "integer?" },
                 result = "table", errors = { "badvalue" } },
    tree     = { result = "table", errors = { "notfound" } },
    wait_any = { result = "handle", errors = { "timeout" } },
    wait_all = { result = "table", errors = { "timeout" } },
  },

  fs = {
    read   = { options_at = 2, options = { encoding = "string?", maxbytes = "Size?" },
               result = "string",
               errors = { "notfound", "access", "toobig", "encoding", "badvalue", "oserror" } },
    write  = { options_at = 3, options = { append = "boolean?", atomic = "boolean?" },
               result = "boolean",
               errors = { "access", "notfound", "encoding", "badvalue", "oserror" } },
    exists = { result = "FsKind|boolean" },
    stat   = { options_at = 2, options = { follow = "boolean?" }, result = "Stat",
               errors = { "notfound", "dangling", "access", "oserror" } },
    canon  = { result = "Canon", errors = { "notfound", "dangling", "access", "oserror" } },
    same   = { result = "boolean" },
    link   = { result = "table|boolean" },
    mkdir  = { options_at = 2, options = { parents = "boolean?" }, result = "boolean",
               errors = { "exists", "access", "oserror" } },
    remove = { options_at = 2, options = { recursive = "boolean?" }, result = "boolean",
               errors = { "notfound", "notempty", "access", "oserror" } },
    rename = { options_at = 3, options = { replace = "boolean?" }, result = "boolean",
               errors = { "exists", "notfound", "access", "oserror" } },
    copy   = { options_at = 3, options = { replace = "boolean?" }, result = "boolean",
               errors = { "exists", "notfound", "access", "oserror" } },
    list   = { result = { entries = "table", errors = "table" } },
    dirs   = { options_at = 2, options = { depth = "integer?", prune = "table?" },
               result = { root = "string", paths = "table", dirs = "integer",
                          skipped = "table", links = "table", errors = "table",
                          pruned = "integer", depthlimited = "integer",
                          maxdepth = "integer" } },
    glob   = { options_at = 2, options = { kind = "FsKind?" }, result = "table" },
    watch  = { options_at = 2, options = { recursive = "boolean?", raw = "boolean?" },
               result = "handle", errors = { "notfound", "access", "oserror" } },
    space  = { result = { total = "integer", free = "integer", available = "integer" } },
    tempfile = { options_at = 1, options = { dir = "string?", prefix = "string?", suffix = "string?" },
                 result = "string", errors = { "badvalue", "access", "oserror" } },
    tempdir  = { options_at = 1, options = { dir = "string?", prefix = "string?" },
                 result = "string", errors = { "badvalue", "access", "oserror" } },
  },

  http = {
    get     = { options_at = 2, options = { to = "string?", sha256 = "string?", timeout = "Duration?",
                            maxbody = "Size?", headers = "table?", redirect = "string?" },
                result = "Response",
                errors = { "timeout", "notfound", "connect", "tls", "toobig",
                           "mismatch", "status", "oserror" } },
    post    = { options_at = 3, options = { type = "string?", timeout = "Duration?",
                            maxbody = "Size?", headers = "table?", redirect = "string?" },
                result = "Response",
                errors = { "timeout", "notfound", "connect", "tls", "toobig", "oserror" } },
    request = { options_at = 1, options = { method = "string?", url = "string", body = "string?",
                            type = "string?", to = "string?", sha256 = "string?",
                            timeout = "Duration?", maxbody = "Size?",
                            headers = "table?", redirect = "string?" },
                result = "Response",
                errors = { "timeout", "notfound", "connect", "tls", "toobig",
                           "mismatch", "status", "oserror" } },
  },

  json = {
    encode    = { options_at = 2, options = { pretty = "boolean?" }, result = "string",
                  errors = { "badvalue", "encoding", "depth", "oserror" } },
    decode    = { result = "any", errors = { "parse", "duplicate", "depth" } },
    array     = { result = "table" },
    object    = { result = "table", errors = { "badvalue" } },
    is_array  = { result = "boolean" },
    is_object = { result = "boolean" },
  },

  sched = {
    spawn    = { result = "handle" },
    sleep    = { errors = { "badvalue" } },
    clock    = { result = "number" },
    now      = { result = "Instant" },
    deadline = { errors = { "deadline", "badvalue" } },
  },

  rt = {
    version          = { field = "Version" },
    version_at_least = { result = "boolean", errors = { "badvalue" } },
    lua              = { field = "string" },
    route            = { field = "Route" },
    exe              = { field = "string" },
    program          = { field = "string?" },
    args             = { field = "table" },
    root             = { result = "string" },
    source           = { result = "string?" },
  },

  err = {
    new = { result = "Err" },
    is  = { result = "boolean", domain_arg = 2, code_arg = 3 },
  },

},
}

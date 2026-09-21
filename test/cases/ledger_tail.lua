-- ledger_tail.lua -- suffix extraction preserves the historical row/anchor
-- rules, including their deliberate difference for trailing CR-only rows.
global none
global <const> require, ipairs, pcall, tostring, table, string

return function(T)
  local fs, json, hash, time = require "fs", require "json", require "hash", require "time"
  local ledger, err, rt = require "_ledger", require "err", require "rt"
  local check = T.check
  local work = fs.absolute(T.work .. "/ledger-tail")
  fs.remove(work, { recursive = true })
  fs.mkdir(work)
  local today = time.iso():sub(1, 10)
  local yesterday = time.iso(time.now() - 86400):sub(1, 10)
  local earlier = time.iso(time.now() - 2 * 86400):sub(1, 10)
  local function row(id, padding)
    return json.encode { v = 1, kuu = rt.version, root = work, kind = "task",
      name = "row-" .. id, at = 1, seconds = 0, status = "ok", sequence = id, padding = padding or "" }
  end
  local one, two, three = row(1), row(2), row(3)
  local function sized(id, bytes) return row(id, string.rep("x", bytes - #row(id))) end
  local long = row(2, string.rep("x", 32785))
  local malformed_long = string.rep("x", 32785)
  local cases = {
    { name = "empty", text = "", n = 5, expected = {} },
    { name = "LF-only", text = "\n\n", n = 3, expected = {} },
    { name = "CRLF-only", text = "\r\n\r\n", n = 1, expected = {} },
    { name = "no-final-newline", text = one, n = 5, expected = { 1 }, anchor = one },
    { name = "ordinary", text = one .. "\n" .. two .. "\n", n = 2, expected = { 1, 2 }, anchor = two },
    { name = "blank-LF-rows", text = "\n" .. one .. "\n\n" .. two .. "\n\n", n = 2,
      expected = { 1, 2 }, anchor = two },
    { name = "CRLF-records", text = one .. "\r\n" .. two .. "\r\n", n = 2,
      expected = { 1, 2 }, anchor = two },
    { name = "CR-only-final-row", text = one .. "\n\r\n", n = 1, expected = {}, anchor = one },
    { name = "malformed-final-row", text = one .. "\n{bad\n", n = 1, expected = {}, anchor = "{bad" },
    { name = "invalid-rows-consume-count", text = one .. "\nnull\n" .. two .. "\nfalse\n", n = 3,
      expected = { 2 }, anchor = "false" },
    { name = "long-final-record", text = one .. "\n" .. long .. "\n", n = 2,
      expected = { 1, 2 }, anchor = long },
    { name = "long-earlier-record", text = long .. "\n" .. three, n = 2,
      expected = { 2, 3 }, anchor = three },
    { name = "long-LF-suffix", text = one .. string.rep("\n", 32785), n = 1, expected = { 1 }, anchor = one },
    { name = "long-malformed-final-row", text = one .. "\n" .. malformed_long, n = 1,
      expected = {}, anchor = malformed_long },
    { name = "leading-CR", text = "\r" .. one .. "\r\n", n = 1, expected = { 1 }, anchor = "\r" .. one },
  }
  -- Put the separator immediately before, at, and after a reversed chunk
  -- boundary, with and without an ordinary trailing newline.
  for _, length in ipairs { 8190, 8191, 8192, 8193, 16383, 16384 } do
    local last = sized(2, length)
    cases[#cases + 1] = { name = "chunk-seam-" .. length,
      text = one .. "\n" .. last .. "\n", n = 2, expected = { 1, 2 }, anchor = last }
  end
  cases[#cases + 1] = { name = "multiple-days", days = {
    { earlier, one .. "\n" }, { yesterday, two .. "\n" }, { today, three .. "\n" },
  }, n = 3, expected = { 1, 2, 3 }, anchor = three }
  cases[#cases + 1] = { name = "newest-empty-day", days = {
    { earlier, one .. "\n" }, { yesterday, two .. "\n" }, { today, "\n\n" },
  }, n = 2, expected = { 1, 2 }, anchor = two }
  cases[#cases + 1] = { name = "newest-CR-only-day", days = {
    { yesterday, one .. "\n" }, { today, "\r\n" },
  }, n = 1, expected = {}, anchor = one }
  cases[#cases + 1] = { name = "newest-invalid-day", days = {
    { yesterday, one .. "\n" }, { today, "false\n" },
  }, n = 1, expected = {}, anchor = "false" }

  local original_write = fs.write
  for _, case in ipairs(cases) do
    local root = work .. "/" .. case.name
    local dir = root .. "/.kuu/ledger"
    fs.mkdir(dir)
    for _, day in ipairs(case.days or { { today, case.text } }) do
      fs.write(dir .. "/" .. day[1] .. ".ndjson", day[2])
    end
    local recent, failure = ledger.tail(root, case.n)
    local selected = {}
    for _, record in ipairs(recent or {}) do selected[#selected + 1] = record.sequence end
    check("tail suffix selection is preserved: " .. case.name,
      recent ~= nil and table.concat(selected, ",") == table.concat(case.expected, ","),
      failure and tostring(failure) or table.concat(selected, ","))

    -- Capture the actual append bytes without suppressing the write. A
    -- pre-existing unterminated row is still appended as-is; this change
    -- deliberately does not repair old history or alter its byte protocol.
    local appended
    fs.write = function(path, bytes, options)
      if path == dir .. "/" .. today .. ".ndjson" and options and options.append then appended = bytes end
      return original_write(path, bytes, options)
    end
    local ran, written, why = pcall(ledger.record, { root = root, dir = dir, written = 0 }, {
      kind = "task", name = "append", at = 1, seconds = 0, status = "ok",
    })
    fs.write = original_write
    local record = appended and json.decode(appended)
    local expected = case.anchor and hash.sum("sha256", case.anchor)
    check("the append predecessor keeps its exact legacy bytes: " .. case.name,
      ran and written and record and record.prev == expected, tostring(why or written))
  end

  local root = work .. "/unreadable"
  local dir = root .. "/.kuu/ledger"
  fs.mkdir(dir)
  fs.write(dir .. "/" .. yesterday .. ".ndjson", one .. "\n")
  fs.write(dir .. "/" .. today .. ".ndjson", two .. "\n")
  local original_read, old_day_reads = fs.read, 0
  fs.read = function(path, options)
    if path == dir .. "/" .. today .. ".ndjson" then return nil, err.new("FS", "access", "held newest day") end
    if path == dir .. "/" .. yesterday .. ".ndjson" then old_day_reads = old_day_reads + 1 end
    return original_read(path, options)
  end
  local ran_tail, result, tail_error = pcall(ledger.tail, root, 2)
  local ran_record, written, record_error = pcall(ledger.record, { root = root, dir = dir, written = 0 }, {
    kind = "task", name = "append", at = 1, seconds = 0, status = "ok",
  })
  fs.read = original_read
  check("suffix tail reading preserves a newest-day read failure without consulting older history",
    ran_tail and result == nil and err.is(tail_error, "FS", "access") and old_day_reads == 0, tostring(tail_error))
  check("append still refuses an unreadable predecessor and leaves its bytes unchanged",
    ran_record and written == nil and err.is(record_error, "FS", "access")
      and fs.read(dir .. "/" .. today .. ".ndjson") == two .. "\n", tostring(record_error))
  fs.remove(work, { recursive = true })
end

-- re.lua -- regular expressions on PCRE2: find, match, gmatch, gsub, split,
-- exec, compile, escape; flags; Unicode; empty matches; the refusals.
global none
global <const> require, ipairs, tostring, type, string, table, pcall, select

return function(T)
  local check, contains = T.check, T.contains
  local re = require "re"
  local err = require "err"

  -- find and match, like string.find and string.match but regular
  local s, e = re.find("the year 2026 came", "\\d+")
  check("find gives one-based inclusive positions", s == 10 and e == 13)
  local a, b = re.find("key = value", "(\\w+)\\s*=\\s*(\\w+)")
  local st, en, k, v = re.find("key = value", "(\\w+)\\s*=\\s*(\\w+)")
  check("find returns captures after the positions", st == 1 and en == 11 and k == "key" and v == "value" and a == 1 and b == 11)
  check("match returns the whole match without groups, the captures with", re.match("x=42", "\\d+") == "42" and select(2, re.match("x=42", "(\\w)=(\\d+)")) == "42")
  check("no match is nil", re.find("abc", "\\d") == nil and re.match("abc", "\\d") == nil)
  check("init works as in string.find, negative from the end", re.find("a1b2", "\\d", 3) == 4 and re.find("a1b2", "\\d", -1) == 4 and re.find("a1b2", "\\d", 5) == nil)
  check("alternation, the thing Lua patterns lack", re.match("cat dog", "dog|bird") == "dog")
  check("counted repetition and classes", re.match("2026-09-09", "\\d{4}-\\d{2}-\\d{2}") == "2026-09-09")
  check("an unset optional group is nil in the middle of the returns", select(2, re.match("ac", "(a)(b)?(c)")) == nil and select(3, re.match("ac", "(a)(b)?(c)")) == "c")

  -- flags
  check("i is caseless", re.match("HELLO", "hello", 1, "i") == "HELLO" and re.match("HELLO", "hello") == nil)
  check("m makes ^ and $ per line, across CRLF too", #re.split("a\r\nb\nc", "$", "m") >= 3 and re.match("a\r\nb", "^b", 1, "m") == "b")
  check("s lets . cross lines", re.match("a\nb", "a.b", 1, "s") == "a\nb" and re.match("a\nb", "a.b") == nil)
  check("x ignores whitespace and comments in the pattern", re.match("ab", "a b # letters", 1, "x") == "ab")
  check("UTF-8 is the default: . is a character", re.match("é", "^.$") == "é" and #re.match("é", "^.$") == 2)
  check("b matches bytes: . is one byte", re.match("é", "^.$", 1, "b") == nil and re.match("é", "^..$", 1, "b") == "é")
  check("u makes \\w Unicode-aware", re.match("été", "^\\w+$", 1, "u") == "été" and re.match("été", "^\\w+$") == nil)
  local ok, raised = pcall(re.match, "x", "x", 1, "q")
  check("an unknown flag is RE badvalue", not ok and err.is(raised, "RE", "badvalue"), tostring(raised))
  ok, raised = pcall(re.match, "x", "x", 1, "bu")
  check("b and u exclude each other", not ok and err.is(raised, "RE", "badvalue"))

  -- gmatch
  local words = {}
  for w in re.gmatch("one two  three", "\\w+") do words[#words + 1] = w end
  check("gmatch iterates whole matches", table.concat(words, ",") == "one,two,three")
  local pairs_found = {}
  for key, value in re.gmatch("a=1;b=2", "(\\w)=(\\d)") do pairs_found[#pairs_found + 1] = key .. value end
  check("gmatch yields captures", table.concat(pairs_found, ",") == "a1,b2")
  local empties = 0
  for _ in re.gmatch("abc", "x*") do empties = empties + 1 end
  check("empty matches advance one character at a time and stop", empties == 4, tostring(empties))
  local chars = {}
  for c in re.gmatch("aé\r\nb", "") do chars[#chars + 1] = "[" .. c .. "]" end
  check("advancing past an empty match steps over a whole UTF-8 character and over CRLF", #chars == 5, tostring(#chars))

  -- gsub
  local out, n = re.gsub("2026-09-09", "(\\d+)-(\\d+)-(\\d+)", "$3/$2/$1")
  check("gsub with $n references", out == "09/09/2026" and n == 1, out)
  out = re.gsub("john smith", "(?<first>\\w+) (?<last>\\w+)", "${last}, ${first}")
  check("gsub with ${name} references", out == "smith, john", out)
  out = re.gsub("price 5", "\\d", "$$$0")
  check("$$ is a dollar and $0 the whole match", out == "price $5", out)
  out, n = re.gsub("a b c", "\\w", function(w) return w:upper() end)
  check("gsub with a function, called with the match", out == "A B C" and n == 3)
  out = re.gsub("a b c", "\\w", { a = "1", c = "3" })
  check("gsub with a table keeps what the table lacks", out == "1 b 3", out)
  out = re.gsub("aaa", "a", "b", 2)
  check("gsub honours the count limit", out == "bba", out)
  out, n = re.gsub("abc", "x*", "-")
  check("gsub with empty matches inserts between characters", out == "-a-b-c-" and n == 4, out)
  ok, raised = pcall(re.gsub, "a", "a", "$9")
  check("a reference beyond the groups is RE badvalue", not ok and err.is(raised, "RE", "badvalue"), tostring(raised))
  ok, raised = pcall(re.gsub, "a", "a", "$")
  check("a lone $ is RE badvalue", not ok and err.is(raised, "RE", "badvalue"))
  ok, raised = pcall(re.gsub, "a", "(a)", "${nope}")
  check("an unknown group name is RE badvalue", not ok and err.is(raised, "RE", "badvalue"))

  -- split
  check("split on a pattern", table.concat(re.split("a, b,c ,d", "\\s*,\\s*"), "|") == "a|b|c|d")
  check("split keeps empty fields between separators and at the end", table.concat(re.split("a,,b,", ","), "|") == "a||b|")
  check("split with an empty pattern gives characters", table.concat(re.split("abc", ""), "|") == "a|b|c")
  check("split with no match is the whole string", #re.split("abc", ",") == 1 and re.split("abc", ",")[1] == "abc")
  check("split of the empty string is one empty piece", #re.split("", ",") == 1)

  -- exec: everything about one match
  local m = re.exec("Date: 2026-09-09", "(?<year>\\d{4})-(?<month>\\d{2})-(\\d{2})")
  check("exec gives positions, numbered captures, and names", m and m.start == 7 and m.stop == 16 and m[1] == "2026" and m[3] == "09" and m.year == "2026" and m.month == "09", tostring(m and m.start))
  m = re.exec("ac", "(a)(b)?(c)")
  check("exec marks an unset group false, so the table has no holes", m and m[2] == false and #m == 3)
  check("exec of no match is nil", re.exec("abc", "\\d") == nil)

  -- compile: the same operations as methods, plus facts
  local rx = re.compile("(?<key>\\w+)=(?<value>\\d+)")
  check("a compiled regex knows its groups and names", rx.groups == 2 and rx.names.key == 1 and rx.names.value == 2 and tostring(rx) == "kuu.re (2 groups)")
  check("methods mirror the functions", rx:find("x=1") == 1 and rx:match("x=1") == "x" and rx:exec("x=1").value == "1"
    and rx:gsub("x=1 y=2", "${value}") == "1 2" and #rx:split("a x=1 b") == 2)
  local seen = {}
  for key in rx:gmatch("x=1 y=2") do seen[#seen + 1] = key end
  check("gmatch as a method", table.concat(seen, ",") == "x,y")
  ok, raised = pcall(re.compile, "(unclosed")
  check("a bad pattern is RE badpattern with the offset", not ok and err.is(raised, "RE", "badpattern") and contains(raised.message, "offset"), tostring(raised))

  -- Unicode subjects and the b flag
  ok, raised = pcall(re.find, "bad \255 byte", "byte")
  check("a subject that is not UTF-8 is refused by name with the b hint", not ok and err.is(raised, "RE", "invalid") and contains(raised.message, "flag b"), tostring(raised))
  check("with b the same subject matches as bytes", re.find("bad \255 byte", "byte", 1, "b") == 7)
  ok, raised = pcall(re.find, "é", ".", 2)
  check("an init inside a character is refused", not ok and err.is(raised, "RE", "invalid"), tostring(raised))

  -- escape
  check("escape makes a literal pattern", re.escape("a.b*c?(d)") == "a\\.b\\*c\\?\\(d\\)" and re.match("a.b*c?(d)", re.escape("a.b*c?(d)")) == "a.b*c?(d)")
  check("escape leaves letters, digits, and UTF-8 alone", re.escape("héllo_1") == "héllo_1")

  -- volume: a megabyte through gsub in reasonable time
  local big = string.rep("word 123 ", 100000)
  local t0 = require("sched").clock()
  local replaced, count = re.gsub(big, "\\d+", "#")
  local took = require("sched").clock() - t0
  check("a megabyte of gsub finishes in under a second", count == 100000 and #replaced == #big - 200000 and took < 1.0, string.format("%.2fs", took))
  ok, raised = pcall(re.match, string.rep("a", 30) .. "b", "^(a+)+$")
  check("a catastrophic pattern hits the limit and is RE limit, not a hang", not ok and err.is(raised, "RE", "limit"), tostring(raised))
end

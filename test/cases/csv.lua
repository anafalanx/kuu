-- csv.lua -- RFC 4180 decoding and encoding, the Windows variants, records.
global none
global <const> require, ipairs, tostring, type, string, pcall, table

return function(T)
  local check = T.check
  local csv = require "csv"
  local err = require "err"

  local rows = csv.decode('a,b,c\r\n1,"two, with comma","three ""quoted"""\r\n4,,6\r\n')
  check("rows decode with quoted separators and doubled quotes",
    #rows == 3 and rows[2][2] == "two, with comma" and rows[2][3] == 'three "quoted"' and rows[3][2] == "" and rows[3][3] == "6",
    tostring(rows[2] and rows[2][3]))
  local lf = csv.decode("a,b\n1,2\n3,4")
  check("LF line ends and no final line end", #lf == 3 and lf[3][2] == "4")
  local multi = csv.decode('x,y\n"line one\nline two",2\n')
  check("a quoted field spans lines", #multi == 2 and multi[2][1] == "line one\nline two")
  local bom = csv.decode("\239\187\191a;b\r\n1;2\r\n", { separator = ";" })
  check("a BOM is skipped and another separator honoured", bom[1][1] == "a" and bom[2][2] == "2")
  local tsv = csv.decode("a\tb\n1\t2\n", { separator = "\t" })
  check("tabs separate TSV", tsv[2][1] == "1" and tsv[2][2] == "2")
  local blank = csv.decode("a,b\n\n1,2\n\n")
  check("blank lines are skipped", #blank == 2)
  local recs = csv.decode("name,age\r\nann,41\r\nbob,7\r\n", { header = true })
  check("header mode yields records and remembers the columns",
    #recs == 2 and recs[1].name == "ann" and recs[2].age == "7" and recs.columns[2] == "age")
  local none, e = csv.decode('a,b\n1,"open\n')
  check("an unterminated quote is CSV parse with the line",
    none == nil and err.is(e, "CSV", "parse") and e.message:find("line 2", 1, true) ~= nil, tostring(e))
  none, e = csv.decode('a,b\n1,x"y\n')
  check("a stray quote is CSV parse", none == nil and err.is(e, "CSV", "parse"), tostring(e))
  none, e = csv.decode('a,b\n"1"x,2\n')
  check("text after a closing quote is CSV parse", none == nil and err.is(e, "CSV", "parse"), tostring(e))
  none, e = csv.decode("a,b\n1,2,3\n")
  check("a ragged row is CSV parse unless allowed", none == nil and err.is(e, "CSV", "parse"), tostring(e))
  local ragged = csv.decode("a,b\n1,2,3\n", { ragged = true })
  check("ragged rows can be allowed", ragged ~= nil and #ragged[2] == 3)
  local okb, eb = pcall(csv.decode, "a,b", { separator = ",," })
  check("a bad separator is CSV badvalue", not okb and err.is(eb, "CSV", "badvalue"), tostring(eb))

  local text = csv.encode { { "a", "b" }, { 1, "x,y" }, { true, 'say "hi"' }, { " padded", "" } }
  check("encode quotes only where needed and ends lines with CRLF",
    text == 'a,b\r\n1,"x,y"\r\ntrue,"say ""hi"""\r\n" padded",\r\n', text)
  local back = csv.decode(text)
  check("encode and decode round-trip", back[2][2] == "x,y" and back[3][2] == 'say "hi"' and back[4][1] == " padded")
  local records = csv.encode({ { name = "ann", age = 41 }, { name = "bob" } }, { columns = { "name", "age" }, newline = "\n" })
  check("records encode with a header in column order, missing fields empty", records == "name,age\nann,41\nbob,\n", records)
  check("decoded records encode back with their columns", csv.encode(recs, { newline = "\n" }) == "name,age\nann,41\nbob,7\n")
  check("a BOM can be asked for", csv.encode({ { "a" } }, { bom = true }):sub(1, 3) == "\239\187\191")
  check("a header can be left out", csv.encode({ { name = "x" } }, { columns = { "name" }, header = false }) == "x\r\n")
  local oke, ee = pcall(csv.encode, { { {} } })
  check("a table as a field is CSV badvalue", not oke and err.is(ee, "CSV", "badvalue"), tostring(ee))
end

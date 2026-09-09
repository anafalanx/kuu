local m = require("mod")
local p = require("sub.pkg")
local rt = require("rt")
print(m.hi, p.name, rt.route, rt.program ~= nil)

-- A pending to-be-closed variable must be closed when the program fails.
local guard <close> = setmetatable({}, {
    __close = function(_, err)
        io.stderr:write("closed with: ", tostring(err), "\n")
    end,
})
error("failing on purpose")

-- luacheck configuration for squircle (norns script)
-- norns runs scripts in a custom environment where these names are injected
-- as globals. list them explicitly so luacheck does not flag them as undefined.

std = "min"

globals = {
 -- norns core objects
 "arc",
 "audio",
 "clock",
 "controlspec",
 "crow",
 "engine",
 "grid",
 "metro",
 "midi",
 "norns",
 "params",
 "screen",
 "tab",
 "util",
 -- norns script callbacks (must be global for norns to call them)
 "init",
 "cleanup",
 "redraw",
 "key",
 "enc",
}

-- 212: unused argument — common in norns callbacks (e.g. `function key(n, z)`)
ignore = { "212" }

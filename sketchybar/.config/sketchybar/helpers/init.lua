-- Add the sketchybar Lua module to the package cpath
local home = os.getenv("HOME") or ("/Users/" .. os.getenv("USER"))
local sodir = home .. "/.local/share/sketchybar_lua"
package.cpath = package.cpath .. ";" .. sodir .. "/?.so"

-- (Re)build SbarLua when it is missing, or when it was built against a different
-- Lua version than the one now running. A Homebrew `lua` upgrade changes the C
-- ABI, so a stale module crashes on load and sketchybar silently crash-loops
-- with an invisible bar. We stamp the Lua version we built against and rebuild
-- whenever it no longer matches _VERSION (e.g. "Lua 5.5").
local stamp = sodir .. "/.luaversion"
local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local contents = f:read("a")
	f:close()
	return contents
end

if read_file(stamp) ~= _VERSION then
	os.execute(
		"rm -rf /tmp/SbarLua && git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && (cd /tmp/SbarLua && make install) && rm -rf /tmp/SbarLua"
	)
	local f = io.open(stamp, "w")
	if f then
		f:write(_VERSION)
		f:close()
	end
end

os.execute("(cd helpers && make)")

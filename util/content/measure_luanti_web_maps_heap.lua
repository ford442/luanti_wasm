#!/usr/bin/env lua
-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- What the themed maps cost the Lua heap, measured rather than guessed.
--
--   lua5.1 util/content/measure_luanti_web_maps_heap.lua <dump>...
--   (normally run by util/content/test_luanti_web_maps.py, which writes the
--   dumps from the committed schematics)
--
-- Runs lw_world's real schematic loader (lw_world/schems.lua) over each map,
-- with core.read_schematic stubbed to build the same table the engine's
-- l_read_schematic pushes: one {name, prob, param2} table per cell. Prints,
-- per map, the heap the loaded piece keeps for the session and the peak while
-- it loads (the engine's per-cell table is garbage as soon as the loader is
-- done with it, but it all exists at once first).
--
-- Lua 5.1 on wasm32 lays a TValue out the same as on x86-64 (a double and a
-- tag, sixteen bytes), so the array parts, which are nearly all of it, weigh
-- the same in the browser as here.
--
-- A dump is three lines: "sx sy sz", the node names separated by spaces, and
-- then "<content> <param2>" pairs, one cell each, in schematic order.

local SCRIPT = arg[0]
local ROOT = SCRIPT:match("^(.*)/util/content/") or "."

DIR_DELIM = "/"

local dumps = {}

local function read_dump(path)
	local file = assert(io.open(path, "r"))
	local sx, sy, sz = file:read("*n", "*n", "*n")
	file:read("*l")
	local names = {}
	for name in file:read("*l"):gmatch("%S+") do
		names[#names + 1] = name
	end
	local content, param2 = {}, {}
	local count = sx * sy * sz
	for i = 1, count do
		content[i], param2[i] = file:read("*n", "*n")
	end
	file:close()
	return {size = {x = sx, y = sy, z = sz}, names = names,
		content = content, param2 = param2}
end

local peak_kib = 0

-- Every entry point schems.lua touches at load, and nothing else: the
-- measurement is of the loader, not of a stub engine.
core = {
	get_modpath = function(name)
		return ROOT .. "/games/luanti_web/mods/" .. name
	end,
	register_tool = function() end,
	register_on_leaveplayer = function() end,
	read_schematic = function(path)
		local name = path:match("([%w_]+)%.mts$")
		local dump = assert(dumps[name], "no dump for " .. tostring(name))
		local data = {}
		for i = 1, #dump.content do
			data[i] = {
				name = dump.names[dump.content[i] + 1],
				prob = 254,
				param2 = dump.param2[i],
			}
		end
		local schem = {size = dump.size, data = data}
		peak_kib = math.max(peak_kib, collectgarbage("count"))
		return schem
	end,
}

local schems = dofile(ROOT .. "/games/luanti_web/mods/lw_world/schems.lua")

local order = {}
for index = 1, #arg do
	local path = arg[index]
	local name = path:match("([%w_]+)%.dump$")
	dumps[name] = read_dump(path)
	order[#order + 1] = name
end

local kept = {}
local total_kept, total_peak = 0, 0
for _, name in ipairs(order) do
	collectgarbage("collect")
	local before = collectgarbage("count")
	peak_kib = before
	-- Stop the collector while loading so the peak is the real high-water
	-- mark, not whatever an incremental step happened to leave.
	collectgarbage("stop")
	kept[#kept + 1] = schems.load(name)
	peak_kib = math.max(peak_kib, collectgarbage("count"))
	collectgarbage("restart")
	collectgarbage("collect")
	local retained = collectgarbage("count") - before
	local peak = peak_kib - before
	total_kept = total_kept + retained
	total_peak = math.max(total_peak, peak)
	local size = dumps[name].size
	print(("MAP %s %d %.1f %.1f"):format(name, size.x * size.y * size.z,
		retained, peak))
end
print(("TOTAL %.1f %.1f"):format(total_kept, total_peak))

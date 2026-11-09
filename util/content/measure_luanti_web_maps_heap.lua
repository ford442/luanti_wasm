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
-- The loader keeps a piece run-length encoded in two strings, so what it keeps
-- is string bytes, which weigh the same in the browser as here. (Lua 5.1 on
-- wasm32 also lays a TValue out the same as on x86-64, sixteen bytes, so the
-- transient per-cell tables peak at the same height too.)
--
-- Before it measures anything it checks the encoding: every cell of every map
-- must read back through schems.read_row / schems.node_at as the node and
-- param2 it was loaded from, and a synthetic piece covers the cases the
-- committed maps may never hit (never-place and ignore cells, runs past 255,
-- rows wider than one run). A mismatch is an error, exit status 1.
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

-- What a cell must read back as: its node name (nil for a cell the piece never
-- places) and its param2 (0 for such a cell, which the encoder normalises).
local function check_piece(piece, cells, label)
	local sx, sy, sz = piece.size.x, piece.size.y, piece.size.z
	local nodes, param2 = {}, {}
	for z = 0, sz - 1 do
		for y = 0, sy - 1 do
			-- A full row, then a clipped one from the middle: the stamper
			-- reads whatever slice a chunk boundary leaves it.
			for _, range in ipairs({{0, sx - 1}, {math.floor(sx / 3), sx - 1 - math.floor(sx / 4)}}) do
				schems.read_row(piece, y, z, range[1], range[2], nodes, param2)
				for x = range[1], range[2] do
					local want = cells[z * sy * sx + y * sx + x + 1]
					local got = nodes[x + 1] ~= 0 and piece.names[nodes[x + 1]] or nil
					if got ~= want.name or (got and param2[x + 1] ~= want.param2)
							or (not got and param2[x + 1] ~= 0) then
						error(("%s: cell %d,%d,%d reads back as %s/%d, was %s/%d"):format(
							label, x, y, z, tostring(got), param2[x + 1],
							tostring(want.name), want.param2))
					end
				end
			end
			for x = 0, sx - 1, 7 do
				local want = cells[z * sy * sx + y * sx + x + 1]
				if schems.node_at(piece, x, y, z) ~= want.name then
					error(("%s: node_at(%d,%d,%d) disagrees"):format(label, x, y, z))
				end
			end
		end
	end
end

do
	-- 600 x 1 x 3 (rows wider than MAX_RUN), with long runs, single cells,
	-- never-place (prob 0) and ignore cells, and param2 on both sides of a run.
	local sx, sy, sz = 600, 1, 3
	local data, cells = {}, {}
	for i = 1, sx * sy * sz do
		local x = (i - 1) % sx
		local z = math.floor((i - 1) / sx)
		local entry = {name = "air", prob = 254, param2 = 0}
		if z == 1 and x % 97 == 0 then
			entry.name = "default:stone"
			entry.param2 = x % 24
		elseif z == 1 and x >= 100 and x < 130 then
			entry.prob = 0
			entry.param2 = 9
		elseif z == 1 and x >= 200 and x < 210 then
			entry.name = "ignore"
		elseif z == 2 and x >= 10 then
			entry.name = "default:dirt"
			entry.param2 = x < 400 and 3 or 255
		end
		data[i] = entry
		local never = entry.prob == 0 or entry.name == "ignore"
		cells[i] = {name = (not never) and entry.name or nil,
			param2 = (not never) and entry.param2 or 0}
	end
	local saved = core.read_schematic
	core.read_schematic = function()
		return {size = {x = sx, y = sy, z = sz}, data = data}
	end
	local piece = schems.load("selftest")
	core.read_schematic = saved
	check_piece(piece, cells, "selftest")
end

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
	-- After the measurement: the reference cells would count as kept.
	local cells = {}
	for i = 1, #dumps[name].content do
		cells[i] = {name = dumps[name].names[dumps[name].content[i] + 1],
			param2 = dumps[name].param2[i]}
	end
	check_piece(kept[#kept], cells, name)
	local peak = peak_kib - before
	total_kept = total_kept + retained
	total_peak = math.max(total_peak, peak)
	local size = dumps[name].size
	print(("MAP %s %d %.1f %.1f"):format(name, size.x * size.y * size.z,
		retained, peak))
end
print(("TOTAL %.1f %.1f"):format(total_kept, total_peak))

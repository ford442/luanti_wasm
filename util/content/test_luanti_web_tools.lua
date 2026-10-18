#!/usr/bin/env lua
-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Headless checks for the showcase authoring tools. Stubs `core` and loads
-- lw_tools/logic.lua, so the clone cap, paint, lights and stamps can be
-- exercised without a running engine.
--
--   lua util/content/test_luanti_web_tools.lua
--   (also invoked by util/content/test_luanti_web_tools.py)

local SCRIPT = arg[0]
local ROOT = SCRIPT:match("^(.*)/util/content/") or "."
local LOGIC = ROOT .. "/games/luanti_web/mods/lw_tools/logic.lua"

local failures = 0

local function fail(message)
	failures = failures + 1
	io.stderr:write("FAIL: " .. message .. "\n")
end

local function assert_true(cond, message)
	if not cond then
		fail(message)
	end
end

local function assert_eq(got, expected, message)
	if got ~= expected then
		fail(("%s: got %s, expected %s"):format(message, tostring(got), tostring(expected)))
	end
end

--------------------------------------------------------------------------
-- Stub engine
--------------------------------------------------------------------------

local world = {}
local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

core = {
	registered_nodes = {},
	pos_to_string = function(pos)
		return ("(%d,%d,%d)"):format(pos.x, pos.y, pos.z)
	end,
	get_node = function(pos)
		return world[key(pos)] or {name = "air", param1 = 0, param2 = 0}
	end,
	set_node = function(pos, node)
		world[key(pos)] = {
			name = node.name,
			param1 = node.param1 or 0,
			param2 = node.param2 or 0,
		}
	end,
	swap_node = function(pos, node)
		core.set_node(pos, node)
	end,
	remove_node = function(pos)
		world[key(pos)] = nil
	end,
}

local function register(name, def)
	core.registered_nodes[name] = def or {}
end

register("air", {buildable_to = true})
register("lw_nodes:wool_white")
register("lw_nodes:wool_red")
register("lw_nodes:wool_blue")
register("lw_nodes:stone_brick")
register("lw_nodes:hidden_light", {buildable_to = false})
register("lw_nodes:column")
register("lw_nodes:gold_trim")
register("lw_nodes:lamp")
register("lw_nodes:frame")
register("lw_theater:seat")
for _, name in ipairs({
	"grey", "dark_grey", "black", "orange", "yellow", "green", "dark_green",
	"cyan", "violet", "magenta", "pink", "brown", "tan",
}) do
	register("lw_nodes:wool_" .. name)
end

local function FakeStack()
	local meta = {node = "", param2 = 0, stamp = 0, description = ""}
	return {
		get_meta = function()
			return {
				get_string = function(_, k) return meta[k] or "" end,
				set_string = function(_, k, v) meta[k] = v end,
				get_int = function(_, k) return tonumber(meta[k]) or 0 end,
				set_int = function(_, k, v) meta[k] = v end,
			}
		end,
	}
end

lw_nodes = {
	wool_colors = {
		{name = "white"}, {name = "grey"}, {name = "dark_grey"}, {name = "black"},
		{name = "red"}, {name = "orange"}, {name = "yellow"}, {name = "green"},
		{name = "dark_green"}, {name = "cyan"}, {name = "blue"}, {name = "violet"},
		{name = "magenta"}, {name = "pink"}, {name = "brown"}, {name = "tan"},
	},
}

dofile(LOGIC)

--------------------------------------------------------------------------
-- Clone volume
--------------------------------------------------------------------------

assert_eq(lw_tools.MAX_CLONE_VOLUME, 32 * 32 * 32, "clone volume cap")
assert_eq(lw_tools.MAX_CLONE_SIDE, 32, "clone side documented as 32")

local function p(x, y, z) return {x = x, y = y, z = z} end

local minp, maxp, size, volume = lw_tools.check_clone_volume(p(0, 0, 0), p(31, 31, 31))
assert_true(minp ~= nil, "32³ must be allowed")
assert_eq(volume, 32768, "32³ volume")
assert_eq(size.x, 32, "32³ x")

local over, err = lw_tools.check_clone_volume(p(0, 0, 0), p(31, 31, 32))
assert_true(over == nil, "32x32x33 must be rejected")
assert_true(err:find("32", 1, true) ~= nil, "error mentions the cap")

--------------------------------------------------------------------------
-- Paint: sample + stamp + wool cycle
--------------------------------------------------------------------------

world = {}
core.set_node(p(1, 2, 3), {name = "lw_nodes:wool_red", param2 = 4})
local paint = FakeStack()
local _, sampled = lw_tools.sample_node(paint, p(1, 2, 3))
assert_true(sampled:find("wool_red", 1, true), "sample names the node")
local name, param2 = lw_tools.get_paint_node(paint)
assert_eq(name, "lw_nodes:wool_red", "sampled name")
assert_eq(param2, 4, "sampled param2")

core.set_node(p(4, 5, 6), {name = "lw_nodes:stone_brick", param2 = 0})
lw_tools.paint_node(paint, p(4, 5, 6))
local painted = core.get_node(p(4, 5, 6))
assert_eq(painted.name, "lw_nodes:wool_red", "paint stamps the sampled type")
assert_eq(painted.param2, 4, "paint keeps sampled param2")

local _, air_err = lw_tools.paint_node(paint, p(9, 9, 9))
assert_true(air_err ~= nil, "painting air is refused")

local _, msg = lw_tools.cycle_wool(paint, 1)
-- red is index 5 of 16; next is orange.
assert_eq(lw_tools.get_paint_node(paint), "lw_nodes:wool_orange", "wool cycle forward")
lw_tools.cycle_wool(paint, -1)
assert_eq(lw_tools.get_paint_node(paint), "lw_nodes:wool_red", "wool cycle back")

-- Wrap from white backwards to tan.
local white = FakeStack()
lw_tools.set_paint_node(white, "lw_nodes:wool_white", 0)
lw_tools.cycle_wool(white, -1)
assert_eq(lw_tools.get_paint_node(white), "lw_nodes:wool_tan", "wool cycle wraps")

--------------------------------------------------------------------------
-- Param2 wrap
--------------------------------------------------------------------------

world = {}
core.set_node(p(0, 0, 0), {name = "lw_theater:seat", param2 = 255})
assert_eq(lw_tools.nudge_param2(p(0, 0, 0), 1), 0, "param2 wraps 255+1")
assert_eq(lw_tools.nudge_param2(p(0, 0, 0), 8), 8, "param2 +8")
assert_eq(lw_tools.nudge_param2(p(0, 0, 0), -9), 255, "param2 wraps below 0")

--------------------------------------------------------------------------
-- Clone copy/paste, including air, and the ignore abort
--------------------------------------------------------------------------

world = {}
core.set_node(p(10, 1, 10), {name = "lw_nodes:wool_blue", param2 = 2})
core.set_node(p(11, 1, 10), {name = "lw_nodes:wool_white", param2 = 0})
-- (10,2,10) stays air so paste punches a hole
local clip, copy_msg = lw_tools.copy_region(p(10, 1, 10), p(11, 2, 10))
assert_true(clip ~= nil, "copy succeeds: " .. tostring(copy_msg))
assert_eq(clip.volume, 4, "2x2x1 copy volume")

local _, paste_msg = lw_tools.paste_region(clip, p(20, 5, 20))
assert_true(paste_msg:find("Pasted", 1, true), "paste reports")
assert_eq(core.get_node(p(20, 5, 20)).name, "lw_nodes:wool_blue", "paste origin")
assert_eq(core.get_node(p(21, 5, 20)).name, "lw_nodes:wool_white", "paste +x")
assert_eq(core.get_node(p(20, 6, 20)).name, "air", "paste copies air")
assert_eq(core.get_node(p(10, 1, 10)).name, "lw_nodes:wool_blue", "source untouched")

local saved_get = core.get_node
core.get_node = function(pos)
	if pos.x == 0 and pos.y == 0 and pos.z == 0 then
		return {name = "ignore", param1 = 0, param2 = 0}
	end
	return saved_get(pos)
end
local bad, bad_err = lw_tools.copy_region(p(0, 0, 0), p(1, 0, 0))
assert_true(bad == nil, "copy aborts on ignore")
assert_true(bad_err:find("loaded", 1, true), "ignore error")
core.get_node = saved_get

local _, no_clip = lw_tools.paste_region(nil, p(0, 0, 0))
assert_true(no_clip:find("Copy", 1, true), "paste without clipboard")

--------------------------------------------------------------------------
-- Light wand
--------------------------------------------------------------------------

world = {}
local ok, light_msg = lw_tools.place_light(p(0, 8, 0))
assert_true(ok, "place light in air: " .. tostring(light_msg))
assert_eq(core.get_node(p(0, 8, 0)).name, "lw_nodes:hidden_light", "hidden light")
core.set_node(p(1, 8, 0), {name = "lw_nodes:stone_brick"})
local blocked = lw_tools.place_light(p(1, 8, 0))
assert_true(blocked == nil, "light wand does not replace solids")
ok = lw_tools.remove_light(p(0, 8, 0))
assert_true(ok, "remove hidden light")
assert_eq(core.get_node(p(0, 8, 0)).name, "air", "removed light is air")

--------------------------------------------------------------------------
-- Schematic stamp
--------------------------------------------------------------------------

world = {}
local column = lw_tools.stamp_nodes("column", p(0, 0, 0), 0)
assert_eq(#column, 6, "column is 6 nodes (plaza_column)")
assert_eq(column[1].node.name, "lw_nodes:column", "column shaft")
assert_eq(column[5].node.name, "lw_nodes:gold_trim", "column capital")
assert_eq(column[6].node.name, "lw_nodes:lamp", "column lamp")
assert_eq(column[6].pos.y, 5, "lamp at y+5")

-- facedir 0 faces +Z, so a seat row runs +X.
local seats = lw_tools.stamp_nodes("seat_row", p(0, 0, 0), 0)
assert_eq(#seats, lw_tools.SEAT_ROW_LENGTH, "seat row length")
assert_eq(seats[1].node.param2, 0, "seats keep facedir")
assert_eq(seats[#seats].pos.x, lw_tools.SEAT_ROW_LENGTH - 1, "row along +X")
assert_eq(seats[#seats].pos.z, 0, "row does not drift in z")

-- facedir 2 faces -Z; right is -X.
local seats2 = lw_tools.stamp_nodes("seat_row", p(0, 0, 0), 2)
assert_eq(seats2[#seats2].pos.x, -(lw_tools.SEAT_ROW_LENGTH - 1), "row along -X")

local frame = lw_tools.stamp_nodes("frame", p(0, 0, 0), 0)
-- 5x5 hollow: 5*4 - 4 corners double-counted = 16.
assert_eq(#frame, 16, "5x5 frame border")
local interior = false
for _, entry in ipairs(frame) do
	if entry.pos.x == 2 and entry.pos.y == 2 and entry.pos.z == 0 then
		interior = true
	end
end
assert_true(not interior, "frame leaves the interior alone")

local n, placed = lw_tools.place_stamp("column", p(5, 1, 5), 0)
assert_eq(n, 6, "place_stamp writes the column")
assert_eq(core.get_node(p(5, 6, 5)).name, "lw_nodes:lamp", "placed lamp")

local stamp = FakeStack()
assert_eq(lw_tools.current_stamp(stamp), "seat_row", "default stamp")
lw_tools.cycle_stamp(stamp, 1)
assert_eq(lw_tools.current_stamp(stamp), "column", "cycle to column")
lw_tools.cycle_stamp(stamp, 1)
assert_eq(lw_tools.current_stamp(stamp), "frame", "cycle to frame")
lw_tools.cycle_stamp(stamp, 1)
assert_eq(lw_tools.current_stamp(stamp), "seat_row", "cycle wraps")
lw_tools.cycle_stamp(stamp, -1)
assert_eq(lw_tools.current_stamp(stamp), "frame", "cycle back")

--------------------------------------------------------------------------
-- Facetir helper
--------------------------------------------------------------------------

assert_eq(lw_tools.facedir_from_dir({x = 0, y = 0, z = 1}), 0, "look +Z")
assert_eq(lw_tools.facedir_from_dir({x = 1, y = 0, z = 0}), 1, "look +X")
assert_eq(lw_tools.facedir_from_dir({x = 0, y = 0, z = -1}), 2, "look -Z")
assert_eq(lw_tools.facedir_from_dir({x = -1, y = 0, z = 0}), 3, "look -X")

if failures > 0 then
	io.stderr:write(failures .. " check(s) failed\n")
	os.exit(1)
end
print("authoring tools checks ok")

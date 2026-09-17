#!/usr/bin/env lua
-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Headless checks for the themed map pack. Stubs `core` and loads lw_nodes,
-- lw_theater and lw_maps so the registry, the per-player atmosphere, the
-- flickering lanterns and `/maps` can be exercised without a running engine.
--
--   lua util/content/test_luanti_web_maps.lua
--   (also invoked by util/content/test_luanti_web_maps.py)
--
-- It also prints every registered node name as `NODE <name>`, which is how
-- the Python half checks that no schematic places a node nothing defines —
-- guessing the names out of the Lua source would miss every one that a
-- helper like register_stair_and_slab() builds by concatenation.

local SCRIPT = arg[0]
local ROOT = SCRIPT:match("^(.*)/util/content/") or "."
local MODS = ROOT .. "/games/luanti_web/mods"

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

function string.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

DIR_DELIM = "/"

--------------------------------------------------------------------------
-- Stub engine
--------------------------------------------------------------------------

vector = {
	new = function(x, y, z)
		if type(x) == "table" then
			return {x = x.x, y = x.y, z = x.z}
		end
		return {x = x or 0, y = y or 0, z = z or 0}
	end,
}
function vector.offset(v, x, y, z)
	return {x = v.x + x, y = v.y + y, z = v.z + z}
end

local world = {}
local metas = {}
local timers = {}
local commands = {}
local globalsteps = {}
local entities = {}
local spawned = {}
local afters = {}

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

core = {
	registered_nodes = {},
	registered_items = {},
	registered_entities = entities,
	registered_chatcommands = commands,
	get_modpath = function(name)
		return MODS .. "/" .. name
	end,
	get_node = function(pos)
		return world[key(pos)] or {name = "air", param1 = 0, param2 = 0}
	end,
	set_node = function(pos, node)
		world[key(pos)] = {name = node.name, param1 = node.param1 or 0,
			param2 = node.param2 or 0}
	end,
	swap_node = function(pos, node)
		core.set_node(pos, node)
	end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		local store = metas[k]
		return {
			set_int = function(_, field, value) store[field] = value end,
			get_int = function(_, field) return store[field] or 0 end,
			set_string = function(_, field, value) store[field] = value end,
			get_string = function(_, field) return store[field] or "" end,
		}
	end,
	get_node_timer = function(pos)
		local k = key(pos)
		return {
			start = function(_, interval) timers[k] = interval end,
			get_timeout = function() return timers[k] or 0 end,
		}
	end,
	register_node = function(name, def)
		def = def or {}
		def.name = name
		core.registered_nodes[name] = def
		core.registered_items[name] = def
	end,
	register_craftitem = function(name, def)
		def = def or {}
		def.name = name
		core.registered_items[name] = def
	end,
	register_tool = function(name, def)
		core.register_craftitem(name, def)
	end,
	register_alias = function() end,
	register_entity = function(name, def) entities[name] = def end,
	register_chatcommand = function(name, def) commands[name] = def end,
	register_globalstep = function(fn) globalsteps[#globalsteps + 1] = fn end,
	register_on_joinplayer = function() end,
	register_on_leaveplayer = function() end,
	register_on_placenode = function() end,
	register_on_dignode = function() end,
	register_on_generated = function() end,
	register_privilege = function() end,
	rotate_node = function() end,
	add_entity = function(pos, name) spawned[#spawned + 1] = {pos = pos, name = name} end,
	get_objects_inside_radius = function() return {} end,
	get_connected_players = function() return core._players or {} end,
	get_player_by_name = function(name)
		for _, player in ipairs(core._players or {}) do
			if player:get_player_name() == name then
				return player
			end
		end
		return nil
	end,
	emerge_area = function() end,
	after = function(_, fn) afters[#afters + 1] = fn end,
	log = function() end,
	chat_send_player = function() end,
	formspec_escape = function(s) return s end,
	get_item_group = function(name, group)
		local def = core.registered_nodes[name]
		return def and def.groups and def.groups[group] or 0
	end,
	settings = {get = function() return nil end, get_bool = function() return false end},
	setting_get_pos = function() return nil end,
	get_timeofday = function() return 0.45 end,
	set_timeofday = function() end,
	serialize = function() return "" end,
	deserialize = function() return nil end,
	get_mod_storage = function()
		return {
			get_string = function() return "" end,
			set_string = function() end,
		}
	end,
	sound_play = function() return 1 end,
	sound_stop = function() end,
	get_worldpath = function() return ROOT end,
	mkdir = function() end,
	pos_to_string = function(pos)
		return ("(%d,%d,%d)"):format(pos.x, pos.y, pos.z)
	end,
}

dofile(MODS .. "/lw_nodes/init.lua")
dofile(MODS .. "/lw_theater/init.lua")
dofile(MODS .. "/lw_maps/init.lua")

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function FakePlayer(name)
	local pos = {x = 0, y = 10, z = -14}
	local sky, ratio
	return {
		get_player_name = function() return name end,
		get_pos = function() return {x = pos.x, y = pos.y, z = pos.z} end,
		set_pos = function(_, to) pos = {x = to.x, y = to.y, z = to.z} end,
		set_sky = function(_, value) sky = value end,
		override_day_night_ratio = function(_, value) ratio = value end,
		_sky = function() return sky end,
		_ratio = function() return ratio end,
	}
end

local function step(dtime)
	for _, fn in ipairs(globalsteps) do
		fn(dtime)
	end
end

--------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------

assert_eq(#lw_maps.maps, 3, "three maps are registered")
assert_eq(lw_maps.base_y, 5, "map schematics are stamped at world y 5")

local seen_schems = {}
for _, map in ipairs(lw_maps.maps) do
	assert_true(map.title and map.blurb ~= nil, map.id .. " has a title and a blurb")
	assert_true(not seen_schems[map.schem], map.id .. " has its own schematic")
	seen_schems[map.schem] = true
	-- The spawn has to be inside the footprint, or a visitor arrives in the
	-- moat with the map behind them.
	assert_true(map.spawn.x >= map.min.x and map.spawn.x <= map.max.x
		and map.spawn.z >= map.min.z and map.spawn.z <= map.max.z,
		map.id .. " spawns inside its own footprint")
	assert_eq(lw_maps.at(map.spawn), map, map.id .. " claims its own spawn")
end

-- Islands must not overlap each other, or two schematics fight over a chunk.
for i = 1, #lw_maps.maps do
	for j = i + 1, #lw_maps.maps do
		local a, b = lw_maps.maps[i], lw_maps.maps[j]
		assert_true(a.max.x < b.min.x or b.max.x < a.min.x
			or a.max.z < b.min.z or b.max.z < a.min.z,
			a.id .. " and " .. b.id .. " overlap")
	end
end

-- And none of them may sit on the showcase island (x -36..36, z -22..66).
for _, map in ipairs(lw_maps.maps) do
	assert_true(map.max.x < -36 or map.min.x > 36
		or map.max.z < -22 or map.min.z > 66,
		map.id .. " overlaps the hub island")
end

assert_eq(lw_maps.at({x = 0, y = 10, z = -14}), nil, "the plaza is not a themed map")

--------------------------------------------------------------------------
-- Per-player atmosphere
--------------------------------------------------------------------------

local player = FakePlayer("visitor")
core._players = {player}

step(1.0)
assert_eq(player:_ratio(), nil, "the hub leaves the day/night ratio alone")

local halloween = lw_maps.by_id["halloween"]
player:set_pos(halloween.spawn)
step(1.0)
assert_eq(player:_ratio(), halloween.day_night_ratio, "the lane is dusk")
assert_true(player:_sky() ~= nil and player:_sky().fog ~= nil,
	"the lane sets a fogged sky")

player:set_pos({x = 0, y = 10, z = -14})
step(1.0)
assert_eq(player:_ratio(), nil, "walking back to the hub restores daylight")

local garden = lw_maps.by_id["fruit_garden"]
player:set_pos(garden.spawn)
step(1.0)
assert_eq(player:_ratio(), nil, "the garden is plain daylight")

--------------------------------------------------------------------------
-- /maps
--------------------------------------------------------------------------

local maps_command = commands["maps"]
assert_true(maps_command ~= nil, "/maps is registered")

local ok, message = maps_command.func("visitor", "")
assert_true(ok, "/maps with no argument lists")
for _, map in ipairs(lw_maps.maps) do
	assert_true(message:find(map.id, 1, true) ~= nil,
		"/maps lists " .. map.id)
end

player:set_pos({x = 0, y = 10, z = -14})
ok = maps_command.func("visitor", " snow_mountain ")
assert_true(ok, "/maps snow_mountain travels")
local snow = lw_maps.by_id["snow_mountain"]
assert_eq(lw_maps.at(player:get_pos()), snow, "/maps lands on the mountain")

ok = maps_command.func("visitor", "atlantis")
assert_true(not ok, "/maps rejects an unknown map")

--------------------------------------------------------------------------
-- Flickering lanterns
--------------------------------------------------------------------------

local flicker = core.registered_nodes["lw_maps:flicker"]
assert_true(flicker ~= nil, "the flicker controller is registered")
assert_eq(flicker.drawtype, "airlike", "the controller is invisible")
assert_eq(flicker.walkable, false, "the controller is not solid")

local at = {x = 4, y = 11, z = 7}
local lantern = {x = at.x, y = at.y - 1, z = at.z}
core.set_node(lantern, {name = "lw_maps:jack_o_lantern", param2 = 2})
flicker.on_construct(at)
assert_true(core.get_node_timer(at):get_timeout() > 0, "the controller arms a timer")

local states = {}
for _ = 1, 60 do
	flicker.on_timer(at)
	states[core.get_node(lantern).name] = true
end
assert_true(states["lw_maps:jack_o_lantern"], "the lantern is lit sometimes")
assert_true(states["lw_maps:pumpkin"], "the lantern gutters sometimes")
assert_eq(core.get_node(lantern).param2, 2, "flickering keeps the lantern's facing")

-- A visitor who digs the lantern out gets a hole, not a pumpkin farm.
core.set_node(lantern, {name = "air"})
for _ = 1, 20 do
	flicker.on_timer(at)
end
assert_eq(core.get_node(lantern).name, "air", "the controller leaves a dug lantern alone")

--------------------------------------------------------------------------
-- The weather vane
--------------------------------------------------------------------------

local vane = entities["lw_maps:weather_vane"]
assert_true(vane ~= nil, "the weather vane entity is registered")
assert_eq(vane.initial_properties.static_save, false,
	"the vane must not accumulate in the map file")

--------------------------------------------------------------------------
-- Node list, for the Python half
--------------------------------------------------------------------------

local names = {}
for name in pairs(core.registered_nodes) do
	names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
	print("NODE " .. name)
end

if failures > 0 then
	io.stderr:write(failures .. " failure(s)\n")
	os.exit(1)
end
print("lw_maps: all checks passed")

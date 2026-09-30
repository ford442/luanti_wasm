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
	register_on_mods_loaded = function() end,
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
	-- Emerges finish when the test says so (see `pending_emerges`), which is
	-- how /maps is checked to wait for the ground before it moves anyone.
	emerge_area = function(minp, maxp, callback)
		if callback then
			core._emerges[#core._emerges + 1] = function()
				callback(nil, nil, 0)
			end
		end
	end,
	_emerges = {},
	get_us_time = function() return core._us end,
	_us = 0,
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
	local resets = 0
	return {
		get_player_name = function() return name end,
		get_pos = function() return {x = pos.x, y = pos.y, z = pos.z} end,
		set_pos = function(_, to) pos = {x = to.x, y = to.y, z = to.z} end,
		-- Mirrors the engine: only a call with no argument resets the sky; a
		-- table, even an empty one, changes just the fields it names.
		set_sky = function(_, value)
			if value == nil then
				sky = nil
				resets = resets + 1
			else
				sky = sky or {}
				for k, v in pairs(value) do
					sky[k] = v
				end
			end
		end,
		override_day_night_ratio = function(_, value) ratio = value end,
		_sky = function() return sky end,
		_ratio = function() return ratio end,
		_resets = function() return resets end,
	}
end

local function finish_emerges()
	local queue = core._emerges
	core._emerges = {}
	for _, fn in ipairs(queue) do
		fn()
	end
end

local function step(dtime)
	for _, fn in ipairs(globalsteps) do
		fn(dtime)
	end
end

--------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------

assert_true(#lw_maps.maps >= 3, "the three original maps are registered")
assert_eq(lw_maps.base_y, 5, "map schematics are stamped at world y 5")

local seen_schems = {}
for _, map in ipairs(lw_maps.maps) do
	assert_true(map.title and map.blurb ~= nil, map.id .. " has a title and a blurb")
	assert_eq(map.schem, "map_" .. map.id, map.id .. " uses its own map_<id> schematic")
	assert_true(not seen_schems[map.schem], map.id .. " has its own schematic")
	seen_schems[map.schem] = true
	-- The spawn has to be inside the footprint, or a visitor arrives in the
	-- moat with the map behind them.
	assert_true(map.spawn.x >= map.min.x and map.spawn.x <= map.max.x
		and map.spawn.z >= map.min.z and map.spawn.z <= map.max.z,
		map.id .. " spawns inside its own footprint")
	assert_eq(lw_maps.at(map.spawn), map, map.id .. " claims its own spawn")
	for _, entity in ipairs(map.entities) do
		local def = entities[entity.name]
		assert_true(def ~= nil, map.id .. " places unregistered entity " .. entity.name)
		assert_eq(def and def.initial_properties.static_save, false,
			entity.name .. " must not accumulate in the map file")
		assert_eq(lw_maps.at(entity.pos), map, entity.name .. " is on " .. map.id)
	end
	-- For the Python half, which checks the entity sits where the schematic
	-- left room for it.
	for _, entity in ipairs(map.entities) do
		print(("ENTITY %s %s %d %d %d"):format(map.id, entity.name,
			entity.at.x, entity.at.y, entity.at.z))
	end
	print(("MAP %s"):format(map.id))
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
-- An empty table would leave the lane's fog on the hub: set_sky() with no
-- argument is the engine's only reset.
assert_eq(player:_sky(), nil, "walking back to the hub resets the sky")

local garden = lw_maps.by_id["fruit_garden"]
player:set_pos(garden.spawn)
step(1.0)
assert_eq(player:_ratio(), nil, "the garden is plain daylight")

-- Map to map directly (as /maps does) must not carry the lane's fog along.
player:set_pos(halloween.spawn)
step(1.0)
local snow = lw_maps.by_id["snow_mountain"]
player:set_pos(snow.spawn)
step(1.0)
assert_eq(player:_sky().fog.fog_distance, snow.sky.fog.fog_distance,
	"the mountain has its own fog, not the lane's")
for _, map in ipairs(lw_maps.maps) do
	player:set_pos(map.spawn)
	step(1.0)
	assert_eq(player:_ratio(), map.day_night_ratio, map.id .. " sets its own time of day")
	if map.sky then
		assert_eq(player:_sky().sky_color.day_sky, map.sky.sky_color.day_sky,
			map.id .. " sets its own sky")
		assert_eq(player:_sky().fog and player:_sky().fog.fog_distance,
			map.sky.fog and map.sky.fog.fog_distance,
			map.id .. " has exactly its own fog")
	else
		assert_eq(player:_sky(), nil, map.id .. " is seen in the hub's own sky")
	end
end
player:set_pos({x = 0, y = 10, z = -14})
step(1.0)

--------------------------------------------------------------------------
-- /maps
--------------------------------------------------------------------------

local maps_command = commands["maps"]
assert_true(maps_command ~= nil, "/maps is registered")
for _, map in ipairs(lw_maps.maps) do
	assert_true(maps_command.params:find(map.id, 1, true) ~= nil,
		"/maps' usage names " .. map.id)
end

local ok, message = maps_command.func("visitor", "")
assert_true(ok, "/maps with no argument lists")
for _, map in ipairs(lw_maps.maps) do
	assert_true(message:find(map.id, 1, true) ~= nil,
		"/maps lists " .. map.id)
end

for _, map in ipairs(lw_maps.maps) do
	player:set_pos({x = 0, y = 10, z = -14})
	ok = maps_command.func("visitor", " " .. map.id .. " ")
	assert_true(ok, "/maps " .. map.id .. " travels")
	-- Nobody moves until the ground under the spawn has been emerged.
	assert_eq(lw_maps.at(player:get_pos()), nil,
		"/maps " .. map.id .. " waits for the emerge before moving anyone")
	finish_emerges()
	assert_eq(lw_maps.at(player:get_pos()), map, "/maps lands on " .. map.id)
end

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
-- Chasing lanterns
--------------------------------------------------------------------------

local chase = core.registered_nodes["lw_maps:chase"]
assert_true(chase ~= nil, "the chase controller is registered")
assert_eq(chase.drawtype, "airlike", "the chase controller is invisible")

-- A loop of lanterns, each controller carrying its place in param2.
local loop = {}
for index = 0, lw_maps.CHASE_PERIOD - 1 do
	local top = {x = 40 + index, y = 11, z = 7}
	core.set_node({x = top.x, y = 10, z = top.z}, {name = "lw_maps:jack_o_lantern"})
	core.set_node(top, {name = "lw_maps:chase", param2 = index})
	chase.on_construct(top)
	loop[#loop + 1] = top
end
for tick = 0, lw_maps.CHASE_PERIOD * 2 do
	core._us = tick * 500000 + 1
	local lit = 0
	for index, top in ipairs(loop) do
		chase.on_timer(top)
		local name = core.get_node({x = top.x, y = 10, z = top.z}).name
		assert_eq(name == "lw_maps:jack_o_lantern", lw_maps.chase_lit(index - 1, tick),
			("chase lamp %d at tick %d"):format(index - 1, tick))
		if name == "lw_maps:jack_o_lantern" then
			lit = lit + 1
		end
	end
	assert_eq(lit, lw_maps.CHASE_WIDTH, "the same number of lamps are lit every tick")
end
-- Every registered pair can be driven, both ways.
for _, pair in ipairs(lw_maps.lamp_pairs) do
	assert_true(core.registered_nodes[pair.lit] ~= nil, pair.lit .. " is a node")
	assert_true(core.registered_nodes[pair.unlit] ~= nil, pair.unlit .. " is a node")
	local spot = {x = 60, y = 11, z = 7}
	core.set_node({x = 60, y = 10, z = 7}, {name = pair.lit, param2 = 3})
	lw_maps.set_lamp(spot, false)
	assert_eq(core.get_node({x = 60, y = 10, z = 7}).name, pair.unlit,
		pair.lit .. " dims to " .. pair.unlit)
	lw_maps.set_lamp(spot, true)
	assert_eq(core.get_node({x = 60, y = 10, z = 7}).name, pair.lit,
		pair.unlit .. " lights to " .. pair.lit)
	assert_eq(core.get_node({x = 60, y = 10, z = 7}).param2, 3,
		"lighting keeps a lamp's facing")
end

--------------------------------------------------------------------------
-- The weather vane
--------------------------------------------------------------------------

local vane = entities["lw_maps:weather_vane"]
assert_true(vane ~= nil, "the weather vane entity is registered")
assert_eq(vane.initial_properties.static_save, false,
	"the vane must not accumulate in the map file")

--------------------------------------------------------------------------
-- The atlas: causeways from the plaza to every map
--------------------------------------------------------------------------

-- lw_world's layout constants, read out of init.lua rather than copied, so a
-- building that moves is a building the causeways are checked against.
local function read_file(path)
	local file = assert(io.open(path, "r"))
	local text = file:read("*a")
	file:close()
	return text
end

local init_source = read_file(MODS .. "/lw_world/init.lua")
local function layout_box(name)
	local x0, x1, z0, z1 = init_source:match("local " .. name ..
		" = {x0 = (%-?%d+), x1 = (%-?%d+), z0 = (%-?%d+), z1 = ([^}]+)}")
	assert(x0, "cannot find " .. name .. " in lw_world/init.lua")
	-- THEATER's z1 is an expression; everything north of it is theater anyway.
	return {x0 = tonumber(x0), x1 = tonumber(x1), z0 = tonumber(z0),
		z1 = tonumber(z1) or 66}
end
local function number(name)
	return tonumber(init_source:match("local " .. name .. " = (%d+)"))
end

local ISLAND = (function()
	local x0, z0, x1, z1 = init_source:match(
		"local ISLAND = {x0 = (%-?%d+), z0 = (%-?%d+), x1 = (%-?%d+), z1 = (%-?%d+)}")
	return {x0 = tonumber(x0), z0 = tonumber(z0), x1 = tonumber(x1), z1 = tonumber(z1)}
end)()
local PLAZA = layout_box("PLAZA")
local HUB_BUILDINGS = {
	library = layout_box("LIBRARY"),
	gallery = layout_box("GALLERY"),
	courtyard = layout_box("COURTYARD"),
	theater = layout_box("THEATER"),
}
local GROUND = number("GROUND")
local FLOOR, WATER = GROUND + 1, GROUND - 1
local HUB = {x0 = ISLAND.x0 - 8, z0 = ISLAND.z0 - 8, x1 = ISLAND.x1 + 8, z1 = ISLAND.z1 + 8}

local atlas = dofile(MODS .. "/lw_world/maps.lua")

local ops, stages = {}, {}
lw_dance = {register_stage = function(def) stages[#stages + 1] = def end}
local api = {
	fill = function(x0, y0, z0, x1, y1, z1, name)
		ops[#ops + 1] = {x0 = math.min(x0, x1), y0 = math.min(y0, y1),
			z0 = math.min(z0, z1), x1 = math.max(x0, x1), y1 = math.max(y0, y1),
			z1 = math.max(z0, z1), name = name}
	end,
	schem = function(x, y, z, name)
		for _, map in ipairs(lw_maps.maps) do
			if map.schem == name then
				return {size = map.size}
			end
		end
		error("the atlas stamps " .. name .. ", which no map registers")
	end,
	label = function() end,
	GROUND = GROUND, FLOOR = FLOOR, WATER = WATER,
	ISLAND = ISLAND, PLAZA = PLAZA, HUB = HUB,
}
api.put = function(x, y, z, name) api.fill(x, y, z, x, y, z, name) end
api.walls = function() error("maps.lua is not expected to build walls") end

local reach = atlas.build(api)
local causeways = atlas.causeways(api)

local along_x = atlas.along_x

local function inside(box, x, z)
	return x >= box.x0 and x <= box.x1 and z >= box.z0 and z <= box.z1
end
local function overlaps(a, b)
	return not (a.x1 < b.x0 or b.x1 < a.x0 or a.z1 < b.z0 or b.z1 < a.z0)
end
local function describe(box)
	return ("x %d..%d, z %d..%d"):format(box.x0, box.x1, box.z0, box.z1)
end

-- The last op to touch (x, y, z) wins, exactly as lw_world stamps them.
local function node_at(x, y, z)
	for index = #ops, 1, -1 do
		local op = ops[index]
		if x >= op.x0 and x <= op.x1 and y >= op.y0 and y <= op.y1
				and z >= op.z0 and z <= op.z1 then
			return op.name
		end
	end
	return nil
end

local by_map = {}
for _, way in ipairs(causeways) do
	assert_true(lw_maps.by_id[way.map] ~= nil, "a causeway leads to unknown map " .. way.map)
	assert_true(not by_map[way.map], way.map .. " has two causeways")
	by_map[way.map] = way
end

for _, map in ipairs(lw_maps.maps) do
	local way = by_map[map.id]
	assert_true(way ~= nil, map.id .. " has no causeway from the plaza")
	if way then
		local legs = way.legs
		local first, last = legs[1], legs[#legs]
		-- Starts on the plaza's edge, ends on the map's.
		assert_true(overlaps(first, PLAZA), map.id .. ": the first leg does not " ..
			"start at the plaza")
		local fp = atlas.footprint(map)
		local grown = {x0 = fp.x0 - 1, z0 = fp.z0 - 1, x1 = fp.x1 + 1, z1 = fp.z1 + 1}
		assert_true(overlaps(last, grown), map.id .. ": the last leg (" ..
			describe(last) .. ") stops short of the map (" .. describe(fp) .. ")")
		for index = 2, #legs do
			assert_true(overlaps(legs[index - 1], legs[index]),
				("%s: leg %d does not meet leg %d"):format(map.id, index - 1, index))
		end

		-- Walk it: plaza, every leg, then straight in to the spawn.
		local walk = {}
		local function mark(x, z)
			walk[x .. "," .. z] = true
		end
		for _, leg in ipairs(legs) do
			for x = leg.x0, leg.x1 do
				for z = leg.z0, leg.z1 do
					mark(x, z)
				end
			end
		end
		local sx, sz = map.spawn.x, map.spawn.z
		-- The landing: from the spawn out to the footprint edge nearest the
		-- last leg, which has to be where the deck is.
		local toward_x = along_x(last)
		if toward_x then
			local dir = (last.x0 + last.x1) / 2 < sx and -1 or 1
			local x = sx
			while inside(fp, x, sz) do
				mark(x, sz)
				x = x + dir
			end
			assert_true(inside(last, x, sz),
				map.id .. ": the spawn row does not meet the causeway at the map edge")
		else
			local dir = (last.z0 + last.z1) / 2 < sz and -1 or 1
			local z = sz
			while inside(fp, sx, z) do
				mark(sx, z)
				z = z + dir
			end
			assert_true(inside(last, sx, z),
				map.id .. ": the spawn column does not meet the causeway at the map edge")
		end
		local start = nil
		for x = first.x0, first.x1 do
			for z = first.z0, first.z1 do
				if inside(PLAZA, x, z) then
					start = start or (x .. "," .. z)
				end
			end
		end
		assert_true(start ~= nil, map.id .. ": no leg cell is on the plaza")
		local seen, queue = {[start] = true}, {start}
		while #queue > 0 do
			local cell = table.remove(queue)
			local x, z = cell:match("(-?%d+),(-?%d+)")
			x, z = tonumber(x), tonumber(z)
			for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
				local next_cell = (x + d[1]) .. "," .. (z + d[2])
				if walk[next_cell] and not seen[next_cell] then
					seen[next_cell] = true
					queue[#queue + 1] = next_cell
				end
			end
		end
		assert_true(seen[sx .. "," .. sz] ~= nil,
			map.id .. ": the causeway does not connect the plaza to the spawn")

		-- Every deck cell is paved at GROUND with head room above it, once
		-- every later op (another island, another causeway) has had its say.
		for _, leg in ipairs(legs) do
			for x = leg.x0, leg.x1 do
				for z = leg.z0, leg.z1 do
					if not inside(PLAZA, x, z) and not inside(fp, x, z) then
						local deck = node_at(x, GROUND, z)
						assert_true(deck == "lw_nodes:paving",
							("%s: causeway cell (%d, %d) is %s, not paving"):format(
								map.id, x, z, tostring(deck)))
						for y = FLOOR, FLOOR + 1 do
							local above = node_at(x, y, z)
							assert_true(above == "air" or above == nil,
								("%s: causeway cell (%d, %d, %d) is blocked by %s"):format(
									map.id, x, y, z, tostring(above)))
						end
					end
				end
			end
		end

		-- Nothing a leg may run through: another map's island, a hub
		-- building, or the hub tour north of the plaza.
		for _, leg in ipairs(legs) do
			for _, other in ipairs(lw_maps.maps) do
				if other ~= map then
					local beach = atlas.footprint(other)
					beach = {x0 = beach.x0 - atlas.RIM, z0 = beach.z0 - atlas.RIM,
						x1 = beach.x1 + atlas.RIM, z1 = beach.z1 + atlas.RIM}
					assert_true(not overlaps(leg, beach),
						("%s: a leg (%s) crosses %s's island"):format(map.id,
							describe(leg), other.id))
				end
			end
			for name, box in pairs(HUB_BUILDINGS) do
				assert_true(not overlaps(leg, box),
					("%s: a leg (%s) runs through the %s"):format(map.id,
						describe(leg), name))
			end
			assert_true(leg.z0 > ISLAND.z1 + 3 or leg.z1 < PLAZA.z1
				or leg.x1 < ISLAND.x0 - 3 or leg.x0 > ISLAND.x1 + 3,
				("%s: a leg (%s) crosses the hub tour north of the plaza"):format(
					map.id, describe(leg)))
		end
		-- The gate stands in the plaza.
		assert_true(inside(PLAZA, way.gate.x, way.gate.z),
			map.id .. ": the gate is not in the plaza")
	end
end

-- Causeways do not cross or touch each other: two decks side by side read as
-- one wide road that forks for no reason.
for i = 1, #causeways do
	for j = i + 1, #causeways do
		for _, a in ipairs(causeways[i].legs) do
			for _, b in ipairs(causeways[j].legs) do
				local grown = {x0 = a.x0 - 2, z0 = a.z0 - 2, x1 = a.x1 + 2, z1 = a.z1 + 2}
				assert_true(not overlaps(grown, b),
					("the %s and %s causeways run into each other (%s, %s)"):format(
						causeways[i].map, causeways[j].map, describe(a), describe(b)))
			end
		end
	end
	-- And no gate post lands on another causeway.
	local way = causeways[i]
	for j = 1, #causeways do
		if j ~= i then
			for _, leg in ipairs(causeways[j].legs) do
				assert_true(not inside({x0 = leg.x0 - 2, z0 = leg.z0 - 2,
					x1 = leg.x1 + 2, z1 = leg.z1 + 2}, way.gate.x, way.gate.z),
					way.map .. "'s gate stands on the " .. causeways[j].map .. " causeway")
			end
		end
	end
end

-- One sea: between the showcase island's moat and every island, and all the
-- way round each, there is water — no hole a visitor can see the void through.
for x = reach.min.x, reach.max.x, 3 do
	for z = reach.min.z, reach.max.z, 3 do
		if not inside(HUB, x, z) then
			local here = node_at(x, WATER, z)
			assert_true(here ~= nil and here ~= "air",
				("the atlas sea has a hole at (%d, %d, %d)"):format(x, WATER, z))
		end
	end
end
assert_true(#stages >= 2, "the atlas registers its dance stages")

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

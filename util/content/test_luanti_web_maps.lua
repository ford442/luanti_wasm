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

-- Everything else from the engine's own vector library (distance, copy,
-- dir_to_rotation, rotate ...), so the laser beams are aimed with the same
-- arithmetic the server uses. The two stubs above stay: plain tables are what
-- the rest of this harness compares against.
do
	local stub = vector
	dofile(ROOT .. "/builtin/common/vector.lua")
	local engine = vector
	vector = stub
	for name, fn in pairs(engine) do
		if stub[name] == nil then
			stub[name] = fn
		end
	end
end

function table.copy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[table.copy(k)] = table.copy(v)
	end
	return out
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

-- An entity, reduced to what the map props do to one: where it is, how it is
-- turned and dressed, and whether it has been removed.
local function FakeObject(pos, name)
	local object = {_pos = {x = pos.x, y = pos.y, z = pos.z}, _name = name,
		_props = {}, _removed = false, _moves = 0}
	function object:get_pos()
		if self._removed then
			return nil
		end
		return {x = self._pos.x, y = self._pos.y, z = self._pos.z}
	end
	function object:set_pos(to)
		self._pos = {x = to.x, y = to.y, z = to.z}
	end
	function object:move_to(to)
		self._moves = self._moves + 1
		self:set_pos(to)
	end
	function object:set_rotation(rot)
		self._rot = rot
	end
	function object:set_properties(props)
		for k, v in pairs(props) do
			self._props[k] = v
		end
	end
	function object:remove()
		self._removed = true
	end
	function object:get_luaentity()
		return {name = name}
	end
	return object
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
	register_on_shutdown = function() end,
	register_on_punchnode = function(fn)
		core._punchnode[#core._punchnode + 1] = fn
	end,
	_punchnode = {},
	register_on_placenode = function() end,
	register_on_dignode = function() end,
	register_on_generated = function() end,
	register_privilege = function() end,
	rotate_node = function() end,
	add_entity = function(pos, name)
		local object = FakeObject(pos, name)
		spawned[#spawned + 1] = {pos = pos, name = name, object = object}
		return object
	end,
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
	get_gametime = function() return core._gametime end,
	_gametime = 0,
	-- Particles are only counted: who they were for, and which spawners are
	-- still alive.
	add_particlespawner = function(def)
		core._next_spawner = core._next_spawner + 1
		core._spawners[core._next_spawner] = def
		return core._next_spawner
	end,
	delete_particlespawner = function(id)
		core._spawners[id] = nil
	end,
	_next_spawner = 0,
	_spawners = {},
	add_particle = function(def)
		core._particles[#core._particles + 1] = def
	end,
	_particles = {},
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
dofile(MODS .. "/lw_amps/init.lua")
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
-- The rainbow storm: rain and lightning only while someone is on the island
--------------------------------------------------------------------------

local function run_afters()
	local queue = afters
	afters = {}
	for _, fn in ipairs(queue) do
		fn()
	end
end

local function spawners()
	local count = 0
	for _ in pairs(core._spawners) do
		count = count + 1
	end
	return count
end

-- The registry walk above already stood on the storm once; drop whatever
-- flash that left pending.
run_afters()

local storm = lw_maps.by_id["rainbow_storm"]
assert_true(storm ~= nil and storm.storm ~= nil, "the rainbow storm has a storm")

-- The beat: deterministic from gametime, every 6 to 8 seconds, and every rod
-- gets struck.
local flashes, struck, previous = 0, {}, nil
for t = 0, 200 do
	local k = lw_maps.storm_flash(t)
	if k then
		flashes = flashes + 1
		if previous then
			assert_true(t - previous >= 6 and t - previous <= 8,
				("flashes at %d and %d are not 6-8 s apart"):format(previous, t))
		end
		previous = t
		struck[k % #storm.storm.rods + 1] = true
		assert_eq(lw_maps.storm_flash(t), k, "the same second is the same flash")
	end
end
assert_true(flashes >= 25, "the storm flashes about every seven seconds")
for index = 1, #storm.storm.rods do
	assert_true(struck[index], ("rod %d is struck"):format(index))
end

-- Nobody on the island: no rain, no lightning, whatever the clock says.
player:set_pos({x = 0, y = 10, z = -14})
step(1.0)
core._particles = {}
core._gametime = 0
step(0.1)
assert_eq(spawners(), 0, "no rain while nobody is on the storm")
assert_eq(#core._particles, 0, "no lightning while nobody is on the storm")

-- On the island: one rain spawner attached to the visitor, for the visitor.
player:set_pos(storm.spawn)
core._gametime = 3
step(1.0)
assert_eq(spawners(), 1, "rain starts when a visitor arrives")
local spawner = core._spawners[core._next_spawner]
assert_eq(spawner.attached, player, "the rain follows the visitor")
assert_eq(spawner.playername, "visitor", "the rain is drawn for the visitor only")
assert_eq(spawner.texture, "lw_rain.png", "the rain uses the streak texture")
step(1.0)
assert_eq(spawners(), 1, "staying on the island keeps one spawner, not a pile")

-- A flash: a white sky, then the storm's own sky back; a bolt onto a rod.
local storm_sky = player:_sky().sky_color.day_sky
core._gametime = 21
core._particles = {}
step(0.05)
assert_true(#core._particles > 0, "a flash second draws a bolt")
assert_true(player:_sky().sky_color.day_sky ~= storm_sky, "the sky flashes")
assert_eq(player:_ratio(), 1, "the flash lights the island")
local rod = lw_maps.to_world(storm, storm.storm.rods[
	lw_maps.storm_flash(21) % #storm.storm.rods + 1])
local lowest = math.huge
for _, particle in ipairs(core._particles) do
	assert_eq(particle.playername, "visitor", "the bolt is drawn for the visitor only")
	assert_true(math.abs(particle.pos.x - rod.x) < 1 and math.abs(particle.pos.z - rod.z) < 1,
		"the bolt comes down on the rod")
	lowest = math.min(lowest, particle.pos.y - particle.size / 20)
end
assert_true(lowest >= rod.y + 0.5 - 0.01, "the bolt stops at the top of the rod")
local drawn = #core._particles
step(0.05)
assert_eq(#core._particles, drawn, "one bolt per flash, not one per step")
run_afters()
assert_eq(player:_sky().sky_color.day_sky, storm_sky, "the storm's sky comes back")
assert_eq(player:_ratio(), storm.day_night_ratio, "the storm's dimness comes back")
assert_eq(player:_sky().fog.fog_distance, storm.sky.fog.fog_distance,
	"the storm keeps its fog through a flash")

-- Off the island between the flash and its end: the hub's sky stays.
core._gametime = 27
step(0.05)
player:set_pos({x = 0, y = 10, z = -14})
step(1.0)
run_afters()
assert_eq(player:_sky(), nil, "a flash does not follow the visitor home")
assert_eq(player:_ratio(), nil, "the hub is midday again")
assert_eq(spawners(), 0, "the rain stops when the visitor leaves")

-- /maps from the storm to the lane carries neither rain nor storm along.
player:set_pos(storm.spawn)
step(1.0)
assert_eq(spawners(), 1, "rain starts again on the way back")
player:set_pos(halloween.spawn)
step(1.0)
assert_eq(spawners(), 0, "the lane is dry")
assert_eq(player:_ratio(), halloween.day_night_ratio, "the lane is still dusk")
assert_eq(player:_sky().fog.fog_distance, halloween.sky.fog.fog_distance,
	"the lane has its own fog, not the storm's")
core._particles = {}
core._gametime = 42
step(0.05)
assert_eq(#core._particles, 0, "no lightning on the lane")
player:set_pos({x = 0, y = 10, z = -14})
step(1.0)

--------------------------------------------------------------------------
-- The arenas: the song only in the concert arena, lasers round both trusses
--------------------------------------------------------------------------

-- The Around arena is a light show now: no amps, so walking on never starts
-- the song or sends its files.
local around = lw_maps.by_id["around_arena"]
assert_true(around ~= nil and around.amps == nil and around.lasers ~= nil,
	"the Around arena has lasers and no song")
for _, map in ipairs(lw_maps.maps) do
	assert_true(map.amps == nil or map.id == "concert_arena",
		map.id .. " plays a song; only the concert arena may")
end
print(("TRACK %s %d %d %d %d %d"):format(around.id, around.lasers.track.x0,
	around.lasers.track.z0, around.lasers.track.x1, around.lasers.track.z1,
	around.lasers.track.y))
assert_eq(lw_maps.track_length(around.lasers.track), 96, "the Around truss is 96 nodes round")
player:set_pos(around.spawn)
step(1.0)
assert_eq(lw_amps.now_playing(), nil, "walking into the Around arena plays nothing")
assert_true(lw_maps.show_objects(around.id) ~= nil, "but its lasers run")
player:set_pos({x = 0, y = 10, z = -14})
step(1.0)

local arena = lw_maps.by_id["concert_arena"]
assert_true(arena ~= nil and arena.amps ~= nil and arena.lasers ~= nil,
	"the concert arena has a stage and lasers")
assert_true(arena.size.x >= 2 * around.size.x - 1 and arena.size.z >= 2 * around.size.z - 1,
	"the concert arena is about twice the Around arena on each side")
-- For the Python half, which checks there is a cab under each source.
print(("AMPS %s %d %d %d %d %d %d"):format(arena.id,
	arena.amps.left.x, arena.amps.left.y, arena.amps.left.z,
	arena.amps.right.x, arena.amps.right.y, arena.amps.right.z))
local truss = arena.lasers.track
print(("TRACK %s %d %d %d %d %d"):format(arena.id, truss.x0, truss.z0,
	truss.x1, truss.z1, truss.y))
assert_true(lw_amps.get_song(arena.amps.song) ~= nil, "the arena plays a registered song")

-- The loop: corner to corner, east along the south side first.
local edge = truss.x1 - truss.x0
assert_eq(lw_maps.track_length(truss), 4 * edge, "the truss runs all round the edge")
local function track_at(s)
	local x, z = lw_maps.track_point(truss, s)
	return x .. "," .. z
end
assert_eq(track_at(0), "0,0", "the loop starts at the south-west corner")
assert_eq(track_at(edge), edge .. ",0", "then runs east")
assert_eq(track_at(2 * edge), edge .. "," .. edge, "then north")
assert_eq(track_at(3 * edge), "0," .. edge, "then west")
assert_eq(track_at(4 * edge), "0,0", "and closes")
assert_eq(track_at(4 * edge - 6), "0,6", "the last side runs south")

local function on_truss(pos)
	local x, z = pos.x - arena.origin.x, pos.z - arena.origin.z
	local on_edge = math.abs(x - truss.x0) < 1e-6 or math.abs(x - truss.x1) < 1e-6
		or math.abs(z - truss.z0) < 1e-6 or math.abs(z - truss.z1) < 1e-6
	return on_edge and x >= truss.x0 - 1e-6 and x <= truss.x1 + 1e-6
		and z >= truss.z0 - 1e-6 and z <= truss.z1 + 1e-6
		and math.abs(pos.y - (arena.origin.y + truss.y + 0.8)) < 1e-6
end

local function live(slots)
	local count = 0
	for _, slot in ipairs(slots or {}) do
		if slot.emitter and slot.emitter:get_pos() and slot.beam and slot.beam:get_pos() then
			count = count + 1
		end
	end
	return count
end

local hub = {x = 0, y = 10, z = -14}
assert_eq(lw_amps.now_playing(), nil, "nothing plays before anyone arrives")
assert_eq(lw_maps.show_objects(arena.id), nil, "no lasers before anyone arrives")

-- Walking on starts the song out of the arena's own cabs, and the lasers.
player:set_pos(arena.spawn)
step(0.5)
local left_source, right_source = lw_amps.get_amps()
assert_eq(lw_amps.now_playing(), arena.amps.song, "arriving starts Around")
assert_true(left_source ~= nil and vector.equals(left_source,
	lw_maps.to_world(arena, arena.amps.left)), "the left channel is the arena's left cab")
assert_true(right_source ~= nil and vector.equals(right_source,
	lw_maps.to_world(arena, arena.amps.right)), "the right channel is its right cab")
assert_eq(player:_ratio(), arena.day_night_ratio, "it is night in the arena")

local slots = lw_maps.show_objects(arena.id)
assert_eq(live(slots), #arena.lasers.colors, "one emitter and beam per colour")
local before = {}
for index, slot in ipairs(slots) do
	assert_true(on_truss(slot.emitter:get_pos()), ("emitter %d rides the truss"):format(index))
	before[index] = slot.emitter:get_pos()
	-- The beam runs from the emitter to the floor: centred between them, as
	-- long as the gap, and its local +Y pointed along it.
	local beam = slot.beam
	local from, mid = slot.emitter:get_pos(), beam:get_pos()
	local to = vector.subtract(vector.multiply(mid, 2), from)
	local length = vector.distance(from, to)
	local dir = vector.direction(from, to)
	local up = vector.rotate({x = 0, y = 1, z = 0}, beam._rot)
	assert_true(vector.distance(up, dir) < 1e-6, ("beam %d points from emitter to floor"):format(index))
	assert_true(math.abs(beam._props.visual_size.y - length) < 0.25,
		("beam %d is as long as the gap"):format(index))
	assert_true(to.y < from.y - 5, ("beam %d comes down onto the floor"):format(index))
	assert_true(math.abs(to.y - (arena.origin.y + arena.lasers.target.y - 0.5)) < 0.05,
		("beam %d lands on the floor's top face"):format(index))
end

-- They race: each one moves on along the truss, a lap every eight bars.
step(0.1)
step(0.1)
for index, slot in ipairs(slots) do
	local now = slot.emitter:get_pos()
	assert_true(on_truss(now), ("emitter %d stays on the truss"):format(index))
	assert_true(vector.distance(now, before[index]) > 1,
		("emitter %d is racing"):format(index))
end
local lap = arena.lasers.lap_beats * 60 / arena.lasers.bpm
assert_true(math.abs(lap - 64 * 60 / 175) < 1e-9, "a lap is sixteen bars of Around")
assert_true(math.abs(lw_maps.track_length(truss) / arena.lasers.lap_beats
	- lw_maps.track_length(around.lasers.track) / around.lasers.lap_beats) < 1e-9,
	"the concert lasers race as fast as the Around arena's")

-- An emitter whose block unloaded is put back, not doubled.
slots[1].emitter:remove()
step(0.1)
assert_eq(live(lw_maps.show_objects(arena.id)), #arena.lasers.colors,
	"a lost emitter is replaced")

-- One that could not be spawned does not strand its beam when the show ends.
local orphan = lw_maps.show_objects(arena.id)[2]
orphan.emitter:remove()
orphan.emitter = nil
local orphan_beam = orphan.beam
player:set_pos(hub)
step(0.5)
assert_eq(orphan_beam:get_pos(), nil, "a beam without its emitter is still removed")
player:set_pos(arena.spawn)
step(0.5)
slots = lw_maps.show_objects(arena.id)

-- Stopping it from a cab sticks while the visitor stays.
lw_amps.stop()
step(1.0)
assert_eq(lw_amps.now_playing(), nil, "a cab-punched stop is not undone by staying")

-- Walking off takes the lasers away; walking back on starts both again;
-- walking off with the song playing stops it.
player:set_pos(hub)
step(0.5)
assert_eq(lw_maps.show_objects(arena.id), nil, "the lasers go when the last visitor does")
for _, slot in ipairs(slots) do
	assert_true(slot.emitter:get_pos() == nil and slot.beam:get_pos() == nil,
		"and are removed, not left behind")
end
player:set_pos(arena.spawn)
step(0.5)
assert_eq(lw_amps.now_playing(), arena.amps.song, "coming back starts it again")
player:set_pos(hub)
step(0.5)
assert_eq(lw_amps.now_playing(), nil, "leaving stops the arena's song")

-- A song started by hand while nobody is on the stage is left alone, and a
-- song already coming out of someone else's cabs is not taken over.
lw_amps.play(arena.amps.song)
step(1.0)
assert_eq(lw_amps.now_playing(), arena.amps.song, "a song started from afar plays on")
lw_amps.stop()
local own_left, own_right = {x = 200, y = 10, z = 7}, {x = 210, y = 10, z = 7}
lw_amps.set_amps(own_left, own_right)
lw_amps.play(arena.amps.song)
player:set_pos(arena.spawn)
step(0.5)
local still_left = lw_amps.get_amps()
assert_true(vector.equals(still_left, own_left), "arriving does not move cabs already playing")
player:set_pos(hub)
step(0.5)
assert_eq(lw_amps.now_playing(), arena.amps.song, "nor stop a song that is not the arena's")
lw_amps.stop()
step(1.0)

-- Without lw_amps at all the arena is quiet, not broken.
local saved_amps = lw_amps
lw_amps = nil
player:set_pos(arena.spawn)
local quiet_ok = pcall(step, 0.5)
assert_true(quiet_ok, "the arena works without lw_amps")
assert_eq(live(lw_maps.show_objects(arena.id)), #arena.lasers.colors,
	"and still has its lasers")
player:set_pos(hub)
step(0.5)
lw_amps = saved_amps

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
	BUILDINGS = {HUB_BUILDINGS.library, HUB_BUILDINGS.gallery,
		HUB_BUILDINGS.courtyard, HUB_BUILDINGS.theater},
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
		-- Starts on the plaza's edge, or for a spur on the beach of the map
		-- it leaves, and ends on the map's own edge.
		local start_box = PLAZA
		if way.from then
			local from = lw_maps.by_id[way.from]
			assert_true(from ~= nil and from.id ~= map.id,
				map.id .. ": the spur leaves unknown map " .. tostring(way.from))
			local beach = atlas.footprint(from)
			start_box = {x0 = beach.x0 - atlas.RIM - 1, z0 = beach.z0 - atlas.RIM - 1,
				x1 = beach.x1 + atlas.RIM + 1, z1 = beach.z1 + atlas.RIM + 1}
		end
		assert_true(overlaps(first, start_box), map.id .. ": the first leg does not " ..
			"start at the plaza (or the beach it is a spur from)")
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
				if inside(start_box, x, z) then
					start = start or (x .. "," .. z)
				end
			end
		end
		assert_true(start ~= nil, map.id .. ": no leg cell is on the plaza (or the beach it leaves)")
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
		-- The gate stands in the plaza, or on the beach a spur leaves.
		local gate_box = PLAZA
		if way.from then
			local beach = atlas.footprint(lw_maps.by_id[way.from])
			gate_box = {x0 = beach.x0 - atlas.RIM, z0 = beach.z0 - atlas.RIM,
				x1 = beach.x1 + atlas.RIM, z1 = beach.z1 + atlas.RIM}
			assert_true(not inside(beach, way.gate.x, way.gate.z),
				map.id .. ": the gate stands inside " .. way.from)
		end
		assert_true(inside(gate_box, way.gate.x, way.gate.z),
			map.id .. ": the gate is not in the plaza (or on the beach it leaves)")
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

-- Causeway rails stay off the plaza and out of the hub buildings' walls: the
-- arena's causeway runs right along the gallery's south face.
for _, op in ipairs(ops) do
	if op.name == "lw_nodes:fence" then
		assert_true(not inside(PLAZA, op.x0, op.z0),
			("a causeway rail stands on the plaza at (%d, %d)"):format(op.x0, op.z0))
		for name, box in pairs(HUB_BUILDINGS) do
			assert_true(not inside(box, op.x0, op.z0),
				("a causeway rail is put into the %s at (%d, %d)"):format(name,
					op.x0, op.z0))
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
-- Lighthouse lamp sting
--------------------------------------------------------------------------

local function punch(pos, name)
	local node = {name = name}
	for _, fn in ipairs(core._punchnode) do
		fn(pos, node)
	end
end

local tide = lw_maps.by_id["lighthouse_tide"]
local lamp_pos
for _, entity in ipairs(tide.entities) do
	if entity.name == "lw_maps:lighthouse_beam" then
		lamp_pos = vector.offset(entity.pos, 0, -1, 0)
	end
end
assert_true(lamp_pos ~= nil, "the lighthouse beam marks the lamp under it")

local played = {}
local real_sound = core.sound_play
core.sound_play = function(name, spec)
	played[#played + 1] = {name = name, spec = spec}
	return 1
end
punch(lamp_pos, "lw_nodes:lamp")
assert_eq(#played, 1, "punching the lantern lamp plays one sting")
assert_eq(played[1].name, "lw_lighthouse", "the sting is the lighthouse horn")
assert_eq(played[1].spec.pos, lamp_pos, "the horn plays at the lamp")
punch({x = lamp_pos.x + 4, y = lamp_pos.y, z = lamp_pos.z}, "lw_nodes:lamp")
assert_eq(#played, 1, "a different lamp on the island stays quiet")
punch(lamp_pos, "lw_nodes:stone")
assert_eq(#played, 1, "punching something else at the lamp stays quiet")

core.sound_play = nil
local ok_silent = pcall(punch, lamp_pos, "lw_nodes:lamp")
assert_true(ok_silent, "punching the lamp with sound off does not error")
core.sound_play = real_sound

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

#!/usr/bin/env lua
-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Headless checks for the dance director. Stubs `core`, `vector` and enough of
-- ObjectRef to load lw_dance whole, then runs a routine on a stage built out
-- of marker nodes and watches what the cast actually does.
--
--   lua util/content/test_luanti_web_routines.lua
--   (also invoked by util/content/test_luanti_web_routines.py)

local SCRIPT = arg[0]
local ROOT = SCRIPT:match("^(.*)/util/content/") or "."
local MODPATH = ROOT .. "/games/luanti_web/mods/lw_dance"

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
		fail(("%s: got %s, expected %s"):format(message, tostring(got),
			tostring(expected)))
	end
end

local function assert_near(got, expected, slack, message)
	if type(got) ~= "number" or math.abs(got - expected) > slack then
		fail(("%s: got %s, expected %s +/- %s"):format(message, tostring(got),
			tostring(expected), tostring(slack)))
	end
end

--------------------------------------------------------------------------
-- Engine bits the mod expects to exist
--------------------------------------------------------------------------

DIR_DELIM = "/"

function string.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function string.split(s, sep)
	local out = {}
	for piece in s:gmatch("([^" .. (sep or " ") .. "]+)") do
		out[#out + 1] = piece
	end
	return out
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

vector = {}
function vector.new(x, y, z)
	if type(x) == "table" then
		return {x = x.x, y = x.y, z = x.z}
	end
	return {x = x or 0, y = y or 0, z = z or 0}
end
function vector.copy(v) return vector.new(v) end
function vector.zero() return vector.new(0, 0, 0) end
local function scalar(v)
	return type(v) == "number" and {x = v, y = v, z = v} or v
end
function vector.add(a, b)
	b = scalar(b)
	return vector.new(a.x + b.x, a.y + b.y, a.z + b.z)
end
function vector.subtract(a, b)
	b = scalar(b)
	return vector.new(a.x - b.x, a.y - b.y, a.z - b.z)
end
function vector.distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end
function vector.equals(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end
function vector.round(v)
	return vector.new(math.floor(v.x + 0.5), math.floor(v.y + 0.5),
		math.floor(v.z + 0.5))
end
function vector.direction(from, to)
	local d = vector.subtract(to, from)
	local length = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
	if length == 0 then
		return vector.zero()
	end
	return vector.new(d.x / length, d.y / length, d.z / length)
end

--------------------------------------------------------------------------
-- Stub engine
--------------------------------------------------------------------------

local world = {}
local players = {}
local entities = {}
local globalsteps = {}
local commands = {}
local joinplayer = {}
local logged = {}
local afters = {}
local gametime = 0

local function key(pos)
	return math.floor(pos.x) .. "," .. math.floor(pos.y) .. "," .. math.floor(pos.z)
end

-- An entity that records what was done to it, which is the whole point: the
-- checks below are about what the director *sends*, not about rendering.
local function FakeObject(pos, name)
	local self = {
		pos = vector.new(pos),
		yaw = 0,
		removed = false,
		properties = {},
		animations = {},
		bones = {},
		bone_calls = 0,
		attached_to = nil,
		attach_position = nil,
	}
	self.ref = {
		get_pos = function()
			if self.removed then
				return nil
			end
			return self.pos
		end,
		set_pos = function(_, p) self.pos = vector.new(p) end,
		get_yaw = function() return self.yaw end,
		set_yaw = function(_, y) self.yaw = y end,
		set_properties = function(_, props)
			for k, v in pairs(props) do
				self.properties[k] = v
			end
		end,
		set_armor_groups = function() end,
		set_texture_mod = function() end,
		set_animation = function(_, range, speed, blend, loop)
			self.animations[#self.animations + 1] = range
		end,
		play_animation = function() end,
		set_bone_override = function(_, bone, override)
			self.bones[bone] = override
			self.bone_calls = self.bone_calls + 1
		end,
		set_attach = function(_, parent, bone, position, rotation)
			self.attached_to = parent
			self.attach_position = position
		end,
		remove = function() self.removed = true end,
		get_luaentity = function()
			if self.removed then
				return nil
			end
			return self.entity
		end,
		is_player = function() return false end,
	}
	self.entity = {object = self.ref, name = name}
	entities[#entities + 1] = self
	return self
end

core = {
	registered_nodes = {},
	registered_entities = {},
	registered_chatcommands = commands,
	get_modpath = function() return MODPATH end,
	get_game_info = function()
		return {id = "luanti_web", path = ROOT .. "/games/luanti_web"}
	end,
	get_dir_list = function(dir, dirs_only)
		-- Only the routines directory is ever listed, and only for files.
		local out = {}
		local pipe = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
		if not pipe then
			return out
		end
		for line in pipe:lines() do
			out[#out + 1] = line
		end
		pipe:close()
		return out
	end,
	pos_to_string = function(pos)
		return ("(%d,%d,%d)"):format(pos.x, pos.y, pos.z)
	end,
	get_node = function(pos)
		return world[key(pos)] or {name = "air", param1 = 0, param2 = 0}
	end,
	set_node = function(pos, node)
		world[key(pos)] = {name = node.name, param1 = 0, param2 = node.param2 or 0}
	end,
	find_nodes_in_area = function(min, max, names)
		local want = type(names) == "table" and names or {names}
		local out = {}
		for at, node in pairs(world) do
			local x, y, z = at:match("^(-?%d+),(-?%d+),(-?%d+)$")
			x, y, z = tonumber(x), tonumber(y), tonumber(z)
			if x >= min.x and x <= max.x and y >= min.y and y <= max.y
					and z >= min.z and z <= max.z then
				for _, pattern in ipairs(want) do
					local group = pattern:match("^group:(.+)$")
					if (group and core.get_item_group(node.name, group) > 0)
							or pattern == node.name then
						out[#out + 1] = {x = x, y = y, z = z}
						break
					end
				end
			end
		end
		return out
	end,
	get_item_group = function(name, group)
		local def = core.registered_nodes[name]
		return def and def.groups and def.groups[group] or 0
	end,
	add_entity = function(pos, name)
		local def = core.registered_entities[name]
		local obj = FakeObject(pos, name)
		if def then
			for k, v in pairs(def) do
				if k ~= "initial_properties" then
					obj.entity[k] = v
				end
			end
			if def.on_activate then
				def.on_activate(obj.entity)
			end
		end
		return obj.ref
	end,
	get_connected_players = function()
		local out = {}
		for _, player in pairs(players) do
			out[#out + 1] = player
		end
		return out
	end,
	get_player_by_name = function(name) return players[name] end,
	chat_send_player = function() end,
	dir_to_yaw = function(dir) return -math.atan2(dir.x, dir.z) end,
	yaw_to_dir = function(yaw)
		return vector.new(-math.sin(yaw), 0, math.cos(yaw))
	end,
	get_gametime = function() return gametime end,
	after = function(delay, fn) afters[#afters + 1] = fn end,
	log = function(level, message)
		logged[#logged + 1] = (level or "") .. ": " .. (message or "")
	end,
	register_node = function(name, def)
		def = def or {}
		def.name = name
		core.registered_nodes[name] = def
	end,
	register_entity = function(name, def)
		core.registered_entities[name] = def
	end,
	register_chatcommand = function(name, def) commands[name] = def end,
	register_globalstep = function(fn) globalsteps[#globalsteps + 1] = fn end,
	register_on_joinplayer = function(fn) joinplayer[#joinplayer + 1] = fn end,
	register_on_leaveplayer = function() end,
	register_on_dieplayer = function() end,
	register_on_shutdown = function() end,
	register_on_player_receive_fields = function() end,
	show_formspec = function() end,
	close_formspec = function() end,
	formspec_escape = function(s) return s end,
	get_player_window_information = function() return nil end,
}

-- lw_dance uses lw_nodes.wool_texture for the mascot's cube.
lw_nodes = {
	wool_texture = function(hex) return "lw_wool.png^[multiply:" .. hex end,
}

local function step(dtime)
	gametime = gametime + dtime
	for _, fn in ipairs(globalsteps) do
		fn(dtime)
	end
	-- The engine steps entities too, and the raft moves in its own on_step.
	for _, entity in ipairs(entities) do
		if not entity.removed and entity.entity.on_step then
			entity.entity.on_step(entity.entity, dtime)
		end
	end
end

local function FakePlayer(name, pos)
	local ctrl = {}
	local player
	player = {
		is_player = function() return true end,
		get_player_name = function() return name end,
		get_pos = function() return vector.new(pos) end,
		set_pos = function(_, p) pos = vector.new(p) end,
		get_player_control = function() return ctrl end,
		get_wield_index = function() return player.slot end,
		set_wield_index = function(_, slot) player.slot = slot end,
		get_look_horizontal = function() return 0 end,
		set_look_horizontal = function() end,
		set_look_vertical = function() end,
		set_properties = function() end,
		set_animation = function(_, range) player.anim = range end,
		play_animation = function() end,
		set_bone_override = function(_, bone, override)
			player.bones = player.bones or {}
			player.bones[bone] = override
		end,
		hud_add = function() return 1 end,
		hud_change = function() end,
		hud_remove = function() end,
		slot = 1,
		ctrl = ctrl,
	}
	players[name] = player
	return player
end

dofile(MODPATH .. "/init.lua")

--------------------------------------------------------------------------
-- The catalog is shared
--------------------------------------------------------------------------

assert_true(lw_dance.get_move("groove") ~= nil, "groove is registered")
assert_true(type(lw_dance.play_move) == "function", "play_move is public")
assert_eq(lw_dance.MAX_DANCERS, 8, "dancer cap")

--------------------------------------------------------------------------
-- The shipped routine files load
--------------------------------------------------------------------------

for _, id in ipairs({"chorus_line_v1", "porch_haunt", "fruit_stomp"}) do
	local routine = lw_dance.get_routine(id)
	assert_true(routine ~= nil, id .. " is registered")
	if routine then
		for _, step_def in ipairs(routine.steps) do
			assert_true(step_def.move == nil or lw_dance.get_move(step_def.move) ~= nil,
				id .. " step move " .. tostring(step_def.move) .. " exists")
			assert_true(step_def.role == "*" or routine.roles[step_def.role] ~= nil,
				id .. " step role " .. tostring(step_def.role) .. " has a dancer")
			assert_true(step_def.t <= routine.length,
				id .. " step at " .. step_def.t .. "s is inside the routine")
		end
		assert_true(#routine.dancers <= lw_dance.MAX_DANCERS, id .. " is within the cap")
	end
end

local chorus = lw_dance.get_routine("chorus_line_v1")
-- 32 beats at 120 bpm is sixteen seconds, and the beats have to survive.
assert_near(chorus.length, 16, 0.001, "chorus length in seconds")
assert_near(chorus.steps[2].t, 4, 0.001, "beat 8 at 120bpm is 4s")
assert_near(chorus.steps[2].beat, 8, 0.001, "beat is kept alongside seconds")

--------------------------------------------------------------------------
-- Formations
--------------------------------------------------------------------------

local line = lw_dance.formation_offsets({kind = "line", spacing = 2}, 3)
assert_eq(line[1].right, 0, "line puts the lead in the middle")
assert_eq(line[2].right, -2, "line goes out to one side")
assert_eq(line[3].right, 2, "line goes out to the other")
local wedge = lw_dance.formation_offsets({kind = "wedge", spacing = 2}, 3)
assert_eq(wedge[1].back, 0, "wedge points at the audience")
assert_true(wedge[2].back > 0, "wedge opens away from the audience")
local circle = lw_dance.formation_offsets({kind = "circle", spacing = 3}, 4)
assert_eq(#circle, 4, "circle places everybody")

--------------------------------------------------------------------------
-- A stage made of marker nodes
--------------------------------------------------------------------------

-- Audience to the south, exactly like the theater.
local STAGE = {x = 0, y = 9, z = 57}
core.set_node({x = 0, y = 9, z = 57}, {name = "lw_dance:mark_lead"})
core.set_node({x = -2, y = 9, z = 57}, {name = "lw_dance:mark_1"})
core.set_node({x = 2, y = 9, z = 57}, {name = "lw_dance:mark_2"})
lw_dance.register_stage({
	routine = "chorus_line_v1",
	pos = STAGE,
	node = {x = 6, y = 9, z = 58},
	facing = {x = 0, y = 0, z = -1},
})

local watcher = FakePlayer("watcher", {x = 0, y = 9, z = 50})

local director, message = lw_dance.start_routine("chorus_line_v1")
assert_true(director ~= nil, "the routine starts: " .. tostring(message))

local cast = {}
for index, dancer in pairs(director.cast) do
	cast[index] = dancer
end
assert_eq(#cast, 3, "three dancers on stage")

-- Marks win over the formation, and a dancer's feet sit on the mark's floor.
assert_eq(cast[1].home.x, 0, "lead is on mark_lead")
assert_near(cast[1].home.y, 8.5, 0.001, "feet are on the floor under the mark")
assert_eq(cast[2].home.x, -2, "left is on mark_1")
assert_eq(cast[3].home.x, 2, "right is on mark_2")
assert_true(cast[1].obj ~= nil and cast[1].obj:get_pos() ~= nil, "lead exists")

-- `audience` is the stage's own direction, so the cast faces south.
local south = -math.atan2(0, -1)
assert_near(cast[1].obj:get_yaw(), south, 0.001, "the cast faces the audience")

-- Everybody starts on the groove, and poses are actually being sent.
step(0.1)
assert_eq(cast[1].clip.move, "groove", "step at t=0 put the cast on the groove")
local moved = 0
for _, entity in ipairs(entities) do
	moved = moved + entity.bone_calls
end
assert_true(moved > 0, "bone keys are sent to the dancers")

-- Four seconds in (beat 8) the lead spins and nobody else does.
for _ = 1, 40 do
	step(0.1)
end
assert_eq(cast[1].clip.move, "spin", "the lead spins on beat 8")
assert_eq(cast[2].clip.move, "groove", "the others keep grooving")

-- Beat 16: both wings wave. Two entities, two different moves, one clock.
for _ = 1, 40 do
	step(0.1)
end
assert_eq(cast[2].clip.move, "wave", "left waves on beat 16")
assert_eq(cast[3].clip.move, "wave", "right waves on beat 16")

-- Seek is a real seek: it lands on the state the clock says, not on a restart.
lw_dance.seek_routine("chorus_line_v1", 4.5)
assert_eq(cast[1].clip.move, "spin", "seeking to 4.5s lands mid-spin")
assert_true(cast[1].clip.t > 0, "the clip is wound forward, not restarted")

-- BPM is a speed control because the beats were kept.
local ok_bpm = lw_dance.set_routine_bpm("chorus_line_v1", 240)
assert_true(ok_bpm, "bpm can be set")
assert_near(director.rate, 2, 0.001, "240 over 120 runs at double speed")
lw_dance.set_routine_bpm("chorus_line_v1", 120)

-- It loops.
lw_dance.seek_routine("chorus_line_v1", 15.9)
step(0.2)
assert_true(director.t < 1, "the routine wraps round rather than running off")

--------------------------------------------------------------------------
-- A player dances along without being driven
--------------------------------------------------------------------------

local guest = FakePlayer("guest", {x = -2, y = 9, z = 57})
local joined = lw_dance.join_routine(guest, "chorus_line_v1")
assert_true(joined, "a visitor can join the routine")
assert_true(lw_dance.is_dancing(guest), "joining puts them in dance mode")
assert_eq(director.followers["guest"], "left", "the mark they stand on is their role")
local before = guest.get_pos()
lw_dance.seek_routine("chorus_line_v1", 8.0)
assert_eq(lw_dance.current_move(guest), "wave", "the routine hands them the step")
local after = guest.get_pos()
assert_true(vector.equals(before, after), "the director never moves a player")

-- Their own key takes the floor back.
lw_dance.run_slot(guest, 1)
assert_eq(director.followers["guest"], nil, "pressing a key leaves the routine")
assert_eq(lw_dance.current_move(guest), "groove", "and plays what they pressed")

--------------------------------------------------------------------------
-- Stopping puts everything back
--------------------------------------------------------------------------

local objs = {}
for index, dancer in pairs(director.cast) do
	objs[index] = dancer.obj
end
local stopped = lw_dance.stop_routine("chorus_line_v1")
assert_true(stopped, "the routine stops")
assert_eq(lw_dance.running["chorus_line_v1"], nil, "and is no longer running")
for index, obj in pairs(objs) do
	assert_true(obj:get_pos() == nil, "dancer " .. index .. " is gone")
end

--------------------------------------------------------------------------
-- The cap
--------------------------------------------------------------------------

local crowd = {}
for index = 1, 12 do
	crowd[index] = {role = "d" .. index, model = "person"}
end
lw_dance.register_routine({
	id = "test_crowd",
	title = "Crowd",
	bpm = 120,
	dancers = crowd,
	steps = {{beat = 0, role = "*", move = "groove"}},
})
local big = lw_dance.start_routine("test_crowd", {pos = {x = 0, y = 9, z = 0}, yaw = 0})
assert_true(big ~= nil, "an oversized routine still runs")
local on_stage = 0
for _ in pairs(big.cast) do
	on_stage = on_stage + 1
end
assert_eq(on_stage, lw_dance.MAX_DANCERS, "only the cap goes on stage")
lw_dance.stop_routine("test_crowd")

--------------------------------------------------------------------------
-- Fail soft: a rig with no skeleton still dances
--------------------------------------------------------------------------

assert_eq(lw_dance.models.mascot_melon.boned, false, "the mascot has no skeleton")
lw_dance.register_routine({
	id = "test_boneless",
	title = "Boneless",
	dancers = {{role = "lead", model = "mascot_melon"}},
	steps = {{t = 0, role = "*", move = "groove"}},
	length = 8,
})
local boneless = lw_dance.start_routine("test_boneless",
	{pos = {x = 20, y = 9, z = 20}, yaw = 0})
assert_true(boneless ~= nil, "a boneless cast starts")
local mascot = boneless.cast[1]
-- A cube hangs off its middle, so it has to be lifted clear of the floor the
-- mark puts it on or it stands knee-deep in the ground.
assert_near(mascot.obj:get_pos().y, mascot.home.y + lw_dance.models.mascot_melon.lift,
	0.001, "a cube rig is lifted onto the floor, not into it")
FakePlayer("nearby", {x = 20, y = 9, z = 20})
local seen_yaw, seen_y = {}, {}
for _ = 1, 30 do
	step(0.1)
	seen_yaw[#seen_yaw + 1] = mascot.obj:get_yaw()
	seen_y[#seen_y + 1] = mascot.obj:get_pos().y
end
local turned, bounced = false, false
for index = 2, #seen_yaw do
	if math.abs(seen_yaw[index] - seen_yaw[1]) > 0.01 then
		turned = true
	end
	if math.abs(seen_y[index] - seen_y[1]) > 0.01 then
		bounced = true
	end
end
assert_true(turned, "a boneless dancer still turns on the beat")
assert_true(bounced, "a boneless dancer still bounces on the beat")
lw_dance.stop_routine("test_boneless")

--------------------------------------------------------------------------
-- Attach: a rider keeps playing its clip while its carrier moves
--------------------------------------------------------------------------

lw_dance.register_routine({
	id = "test_ride",
	title = "Ride",
	dancers = {{
		role = "rider",
		model = "berry",
		ride = "lw_dance:float",
		path = {from = {x = -4, y = 0, z = 0}, to = {x = 4, y = 0, z = 0}, speed = 2},
	}},
	steps = {{t = 0, role = "*", move = "stomp"}},
	length = 8,
})
local ride = lw_dance.start_routine("test_ride",
	{pos = {x = 40, y = 9, z = 40}, yaw = 0})
assert_true(ride ~= nil, "a riding cast starts")
local rider = ride.cast[1]
assert_true(rider.carrier ~= nil, "the rider got a carrier")
local carrier_start = rider.carrier:get_pos()
FakePlayer("rider_watcher", {x = 40, y = 9, z = 40})
local keys_before = nil
for _, entity in ipairs(entities) do
	if entity.ref == rider.obj then
		keys_before = entity.bone_calls
	end
end
local travelled = 0
for _ = 1, 20 do
	step(0.1)
	travelled = math.max(travelled,
		vector.distance(carrier_start, rider.carrier:get_pos()))
end
assert_true(travelled > 1, "the carrier actually travels")
assert_true(vector.distance(rider.obj:get_pos(), carrier_start) < 20,
	"the rider stays with its carrier")
local keys_after = nil
for _, entity in ipairs(entities) do
	if entity.ref == rider.obj then
		keys_after = entity.bone_calls
	end
end
assert_true(keys_after > keys_before, "the rider keeps playing its clip aboard")
lw_dance.stop_routine("test_ride")

--------------------------------------------------------------------------
-- The command surface
--------------------------------------------------------------------------

assert_true(core.registered_chatcommands["routine"] ~= nil, "/routine exists")
local listed = select(2, core.registered_chatcommands["routine"].func("watcher", "list"))
assert_true(listed:find("chorus_line_v1") ~= nil, "/routine list names the routines")
local started = core.registered_chatcommands["routine"].func("watcher",
	"start chorus_line_v1")
assert_true(started, "/routine start runs one")
core.registered_chatcommands["routine"].func("watcher", "stop")
assert_eq(lw_dance.running["chorus_line_v1"], nil, "/routine stop stops it")

assert_true(core.registered_nodes["lw_dance:director"] ~= nil, "director node")
assert_true(core.registered_nodes["lw_dance:mark_lead"] ~= nil, "lead mark node")
assert_true(core.registered_nodes["lw_dance:mark_8"] ~= nil, "mark 8 node")
assert_eq(lw_dance.mark_slot["lw_dance:mark_lead"], 0, "the lead mark is slot 0")

if failures > 0 then
	io.stderr:write(("%d check(s) failed\n"):format(failures))
	os.exit(1)
end

print("dance routine checks ok")

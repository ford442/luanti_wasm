#!/usr/bin/env lua
-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Headless checks for the waterfall cascade's bicycles and gems. Stubs `core`
-- and loads lw_cascade, so the fusing rules, the gems on the ground, the bike
-- racks and a ride that ends in a breakdown can be exercised without a
-- running engine.
--
--   lua util/content/test_luanti_web_cascade.lua
--   (also invoked by util/content/test_luanti_web_cascade.py)

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

DIR_DELIM = "/"

--------------------------------------------------------------------------
-- Stub engine
--------------------------------------------------------------------------

dofile(ROOT .. "/builtin/common/vector.lua")

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

-- Item stacks and inventories, reduced to names and counts.
function ItemStack(item)
	local name, count = "", 0
	if type(item) == "string" and item ~= "" then
		name = item:match("^(%S+)")
		count = tonumber(item:match("%s(%d+)$")) or 1
	elseif type(item) == "table" then
		name, count = item:get_name(), item:get_count()
	end
	local stack = {_name = name, _count = count}
	function stack:get_name() return self._count > 0 and self._name or "" end
	function stack:get_count() return self._count end
	function stack:is_empty() return self._count == 0 end
	function stack:take_item(n)
		n = math.min(n or 1, self._count)
		self._count = self._count - n
		return ItemStack(n > 0 and (self._name .. " " .. n) or "")
	end
	return stack
end

local function FakeInventory(size)
	local slots = {}
	for i = 1, size do
		slots[i] = ItemStack("")
	end
	local inv = {_slots = slots}
	function inv:count(name)
		local n = 0
		for _, s in ipairs(slots) do
			if s:get_name() == name then
				n = n + s:get_count()
			end
		end
		return n
	end
	function inv:contains_item(_, item)
		local stack = ItemStack(item)
		return self:count(stack:get_name()) >= stack:get_count()
	end
	function inv:remove_item(_, item)
		local stack = ItemStack(item)
		local want = stack:get_count()
		for _, s in ipairs(slots) do
			if want > 0 and s:get_name() == stack:get_name() then
				want = want - s:take_item(want):get_count()
			end
		end
		return ItemStack(stack:get_name() .. " " .. (stack:get_count() - want))
	end
	function inv:add_item(_, item)
		local stack = ItemStack(item)
		for _, s in ipairs(slots) do
			if s:get_name() == stack:get_name() then
				s._count = s._count + stack:get_count()
				return ItemStack("")
			end
		end
		for i, s in ipairs(slots) do
			if s:is_empty() then
				slots[i] = ItemStack(stack:get_name() .. " " .. stack:get_count())
				return ItemStack("")
			end
		end
		return stack
	end
	return inv
end

local world, metas, timers = {}, {}, {}
local objects = {}
local chats = {}
local spawners = {}

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function FakeObject(pos)
	local object = {_pos = vector.new(pos), _vel = vector.new(0, 0, 0), _yaw = 0,
		_props = {}, _removed = false}
	function object:get_pos()
		return not self._removed and vector.new(self._pos) or nil
	end
	function object:set_pos(to) self._pos = vector.new(to) end
	function object:get_velocity() return vector.new(self._vel) end
	function object:set_velocity(v) self._vel = vector.new(v) end
	function object:set_acceleration(a) self._acc = a end
	function object:get_yaw() return self._yaw end
	function object:set_yaw(yaw) self._yaw = yaw end
	function object:set_rotation(rot) self._rot = rot end
	function object:set_properties(props)
		for k, v in pairs(props) do
			self._props[k] = v
		end
	end
	function object:set_armor_groups() end
	function object:is_player() return false end
	function object:get_attach() return nil end
	function object:remove() self._removed = true end
	function object:get_luaentity() return self._entity end
	return object
end

local function FakePlayer(name, pos)
	local player = FakeObject(pos)
	player._inv = FakeInventory(32)
	player._control = {}
	player._look = 0
	function player:get_player_name() return name end
	function player:is_player() return true end
	function player:get_inventory() return self._inv end
	function player:get_player_control() return self._control end
	function player:get_look_horizontal() return self._look end
	function player:get_look_dir() return {x = -math.sin(self._look), y = 0, z = math.cos(self._look)} end
	function player:get_attach() return self._parent end
	function player:set_attach(parent) self._parent = parent end
	function player:set_detach() self._parent = nil end
	function player:set_animation(range) self._anim = range end
	function player:set_eye_offset(first) self._eye = first end
	function player:get_luaentity() return nil end
	objects[#objects + 1] = player
	return player
end

local entity_defs = {}
local players = {}

core = {
	registered_nodes = {},
	registered_items = {},
	registered_entities = entity_defs,
	get_modpath = function(name) return MODS .. "/" .. name end,
	register_node = function(name, def)
		def.name = name
		core.registered_nodes[name] = def
		core.registered_items[name] = def
	end,
	register_craftitem = function(name, def)
		def.name = name
		core.registered_items[name] = def
	end,
	register_entity = function(name, def) def.name = name; entity_defs[name] = def end,
	register_chatcommand = function(name, def) core._commands[name] = def end,
	_commands = {},
	register_on_leaveplayer = function(fn) core._leave = fn end,
	rotate_node = function() end,
	get_node = function(pos) return world[key(pos)] or {name = "air", param2 = 0} end,
	set_node = function(pos, node)
		world[key(pos)] = {name = node.name, param2 = node.param2 or 0}
		metas[key(pos)] = nil
	end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		local store = metas[k]
		return {
			set_int = function(_, f, v) store[f] = v end,
			get_int = function(_, f) return store[f] or 0 end,
			set_string = function(_, f, v) store[f] = v end,
			get_string = function(_, f) return store[f] or "" end,
		}
	end,
	get_node_timer = function(pos)
		return {start = function(_, t) timers[key(pos)] = t end}
	end,
	facedir_to_dir = function(fd)
		return ({[0] = {x = 0, y = 0, z = 1}, {x = 1, y = 0, z = 0},
			{x = 0, y = 0, z = -1}, {x = -1, y = 0, z = 0}})[fd]
	end,
	dir_to_yaw = function(dir) return -math.atan2(dir.x, dir.z) end,
	add_entity = function(pos, name, staticdata)
		local def = entity_defs[name]
		local object = FakeObject(pos)
		local entity = setmetatable({name = name, object = object}, {__index = def})
		object._entity = entity
		object._props = table.copy(def.initial_properties)
		objects[#objects + 1] = object
		if def.on_activate then
			def.on_activate(entity, staticdata, 0)
		end
		return object
	end,
	get_objects_inside_radius = function(pos, radius)
		local out = {}
		for _, object in ipairs(objects) do
			local at = object:get_pos()
			if at and vector.distance(at, pos) <= radius then
				out[#out + 1] = object
			end
		end
		return out
	end,
	get_player_by_name = function(name) return players[name] end,
	get_gametime = function() return core._gametime end,
	_gametime = 100,
	chat_send_player = function(name, text) chats[#chats + 1] = {name = name, text = text} end,
	add_particlespawner = function(def) spawners[#spawners + 1] = def; return #spawners end,
	serialize = function(t)
		local parts = {}
		for k, v in pairs(t) do
			parts[#parts + 1] = ("%s=%q"):format(k, v)
		end
		return "return {" .. table.concat(parts, ",") .. "}"
	end,
	deserialize = function(s)
		if type(s) ~= "string" or s:sub(1, 7) ~= "return " then
			return nil
		end
		return (loadstring or load)(s)()
	end,
}

dofile(MODS .. "/lw_cascade/init.lua")

local function last_chat(name)
	for i = #chats, 1, -1 do
		if chats[i].name == name then
			return chats[i].text
		end
	end
	return ""
end

local function live(name)
	local out = {}
	for _, object in ipairs(objects) do
		local entity = object:get_luaentity()
		if object:get_pos() and entity and entity.name == name then
			out[#out + 1] = object
		end
	end
	return out
end

--------------------------------------------------------------------------
-- Fusing rules
--------------------------------------------------------------------------

local gems = {}
for _, gem in ipairs(lw_cascade.GEMS) do
	gems[gem.name] = true
	assert_true(core.registered_items["lw_cascade:gem_" .. gem.name] ~= nil,
		gem.name .. " gem is registered")
	assert_eq(lw_cascade.gem_color("lw_cascade:gem_" .. gem.name), gem.name,
		"the item name gives back the colour")
	assert_true(gem.hex:match("^#%x%x%x%x%x%x$") ~= nil, gem.name .. " has a colour")
end
assert_eq(lw_cascade.gem_color("lw_nodes:stone"), nil, "stone is not a gem")
assert_eq(lw_cascade.gem_color("lw_cascade:gem_plaid"), nil, "nor is a colour nobody registered")

for _, recipe in ipairs(lw_cascade.RECIPES) do
	local a, b, made = recipe[1], recipe[2], recipe[3]
	assert_true(gems[a] and gems[b] and gems[made], "a recipe names real gems")
	assert_true(a ~= b, "no gem fuses with its own colour")
	assert_eq(lw_cascade.fuse(a, b), made, a .. " + " .. b)
	assert_eq(lw_cascade.fuse(b, a), made, b .. " + " .. a .. " (order does not matter)")
end
for _, color in ipairs(lw_cascade.PRIMARY) do
	assert_eq(lw_cascade.fuse(color, color), nil, color .. " does not fuse with itself")
	assert_true(core.registered_nodes["lw_cascade:geode_" .. color] ~= nil,
		color .. " has a geode")
	assert_eq(core.registered_nodes["lw_cascade:geode_" .. color].drop,
		"lw_cascade:gem_" .. color, "a " .. color .. " geode drops its gem")
end
assert_eq(lw_cascade.fuse("red", "yellow"), "orange", "red and yellow make orange")
assert_eq(lw_cascade.fuse("violet", "yellow"), "prism", "a secondary and its complement make a prism")
assert_eq(#lw_cascade.partners("prism"), 0, "a prism is where fusing ends")
assert_true(lw_cascade.fuse_hint("prism"):find("as far as fusing goes") ~= nil,
	"and says so")
-- Every gem can be made from geodes alone.
local makeable = {}
for _, color in ipairs(lw_cascade.PRIMARY) do
	makeable[color] = true
end
for _ = 1, 3 do
	for _, recipe in ipairs(lw_cascade.RECIPES) do
		if makeable[recipe[1]] and makeable[recipe[2]] then
			makeable[recipe[3]] = true
		end
	end
end
for name in pairs(gems) do
	assert_true(makeable[name], name .. " can be made from what the geodes give")
end

--------------------------------------------------------------------------
-- Fusing in the hand
--------------------------------------------------------------------------

local visitor = FakePlayer("visitor", {x = 0, y = 0, z = 0})
players.visitor = visitor
local inv = visitor:get_inventory()

local red = ItemStack("lw_cascade:gem_red 2")
local left = lw_cascade.fuse_in_inventory(red, visitor)
assert_eq(left:get_count(), 2, "nothing to fuse with: the gem stays")
assert_true(last_chat("visitor"):find("fuses with yellow") ~= nil, "and the visitor is told what would")

inv:add_item("main", "lw_cascade:gem_blue")
left = lw_cascade.fuse_in_inventory(red, visitor)
assert_eq(left:get_count(), 1, "fusing uses up one wielded gem")
assert_eq(inv:count("lw_cascade:gem_blue"), 0, "and the partner from the pockets")
assert_eq(inv:count("lw_cascade:gem_violet"), 1, "red and blue fuse into violet")
inv:add_item("main", "lw_cascade:gem_yellow")
local violet = ItemStack("lw_cascade:gem_violet")
inv:remove_item("main", "lw_cascade:gem_violet")
lw_cascade.fuse_in_inventory(violet, visitor)
assert_eq(inv:count("lw_cascade:gem_prism"), 1, "violet and yellow fuse into a prism")

-- A right click on a node with its own right click goes to the node.
local clicked = false
core.registered_nodes["test:seat"] = {on_rightclick = function() clicked = true end}
world[key({x = 5, y = 0, z = 5})] = {name = "test:seat"}
local def = core.registered_items["lw_cascade:gem_red"]
def.on_place(ItemStack("lw_cascade:gem_red"), visitor,
	{type = "node", under = {x = 5, y = 0, z = 5}, above = {x = 5, y = 1, z = 5}})
assert_true(clicked, "a gem right-clicked on a seat sits on the seat, not fuses")

--------------------------------------------------------------------------
-- Gems on the ground
--------------------------------------------------------------------------

local stack = ItemStack("lw_cascade:gem_red 3")
stack = def.on_drop(stack, visitor, visitor:get_pos())
assert_eq(stack:get_count(), 2, "Q drops one gem at a time")
local dropped = live("lw_cascade:gem")
assert_eq(#dropped, 1, "as a gem on the ground")
local gem = dropped[1]:get_luaentity()
assert_eq(gem.color, "red", "of the colour that was dropped")
assert_true(dropped[1]:get_velocity().z > 0, "thrown along the look")
assert_true(core.deserialize(gem:get_staticdata()).color == "red", "it keeps its colour when saved")

-- Punching pushes it away from the puncher.
dropped[1]:set_pos({x = 0, y = 0, z = 2})
gem:on_punch(visitor, 1, {}, {x = 0, y = 0, z = 1})
local v = dropped[1]:get_velocity()
assert_true(v.z > 4 and math.abs(v.x) < 1e-6 and v.y > 0, "a punch sends it rolling away")
-- Friction stops it on the ground, not in the air.
local slowed = lw_cascade.gem_friction({x = 4, y = 0, z = 0}, 0.1, true)
assert_true(slowed.x < 4 and slowed.x > 0, "the ground slows it")
assert_eq(lw_cascade.gem_friction({x = 4, y = 0, z = 0}, 0.1, false).x, 4, "the air does not")
assert_eq(lw_cascade.gem_friction({x = 0.02, y = 0, z = 0}, 0.1, true).x, 0, "a crawl is a stop")

-- Walking into it shoves it on.
dropped[1]:set_velocity({x = 0, y = 0, z = 0})
visitor:set_pos({x = 0, y = 0, z = 1.5})
gem.tick = 1
gem:on_step(0.1, {touching_ground = true})
assert_true(dropped[1]:get_velocity().z >= lw_cascade.GEM.bump, "a walker shoves it ahead")
visitor:set_pos({x = 0, y = 0, z = 0})

-- Two that roll together fuse.
local blue = lw_cascade.spawn_gem({x = 0, y = 0, z = 2.4}, "blue")
gem.pusher = "visitor"
gem.tick = 1
dropped[1]:set_velocity({x = 0, y = 0, z = 0})
gem:on_step(0.1, {touching_ground = true})
assert_true(dropped[1]:get_pos() == nil and blue:get_pos() == nil, "both fused gems are gone")
local made = live("lw_cascade:gem")
assert_eq(#made, 1, "one gem in their place")
assert_eq(made[1] and made[1]:get_luaentity().color, "violet", "red and blue roll into violet")
assert_true(last_chat("visitor"):find("fuse into a violet gem") ~= nil, "the pusher hears about it")
-- Same colours just bump.
local r1 = lw_cascade.spawn_gem({x = 10, y = 0, z = 10}, "green")
local r2 = lw_cascade.spawn_gem({x = 10, y = 0, z = 10.3}, "green")
r1:get_luaentity().tick = 1
r1:get_luaentity():on_step(0.1, {touching_ground = true})
assert_true(r1:get_pos() ~= nil and r2:get_pos() ~= nil, "two green gems do not fuse")

-- Right click picks it up.
made[1]:get_luaentity():on_rightclick(visitor)
assert_true(made[1]:get_pos() == nil, "picked up")
assert_eq(inv:count("lw_cascade:gem_violet"), 1, "into the pockets")
-- It fades after a long time on the ground, like an item.
r1:get_luaentity().age = lw_cascade.GEM.lifetime + 1
r1:get_luaentity():on_step(0.1, {touching_ground = true})
assert_true(r1:get_pos() == nil, "an old gem fades")

--------------------------------------------------------------------------
-- Geodes grow back
--------------------------------------------------------------------------

local geode_pos = {x = 3, y = 3, z = 3}
world[key(geode_pos)] = {name = "lw_cascade:geode_yellow"}
core.registered_nodes["lw_cascade:geode_yellow"].after_dig_node(geode_pos)
assert_eq(core.get_node(geode_pos).name, "lw_cascade:geode_spent", "a dug geode goes dull")
assert_eq(timers[key(geode_pos)], lw_cascade.GEODE_REGROW, "and starts growing back")
assert_eq(core.registered_nodes["lw_cascade:geode_spent"].drop, "", "a dull geode has no gem")
core.registered_nodes["lw_cascade:geode_spent"].on_timer(geode_pos)
assert_eq(core.get_node(geode_pos).name, "lw_cascade:geode_yellow", "it grows back its own colour")

--------------------------------------------------------------------------
-- Bicycles
--------------------------------------------------------------------------

local B = lw_cascade.BIKE
-- Pedalling, braking, coasting.
local speed = 0
for _ = 1, 40 do
	speed = lw_cascade.bike_speed(speed, {up = true}, 0.1)
end
assert_eq(speed, B.max_speed, "pedalling tops out at max speed")
local coasting = lw_cascade.bike_speed(speed, {}, 0.5)
assert_true(coasting < speed and coasting > 0, "letting go coasts")
local braking = lw_cascade.bike_speed(speed, {down = true}, 0.5)
assert_true(braking < coasting, "braking is harder than coasting")
assert_eq(lw_cascade.bike_speed(0.1, {down = true}, 0.5), 0, "braking stops rather than reversing")
assert_true(lw_cascade.bike_speed(0, {down = true}, 1) < 0, "from a stop, back backs up")
assert_true(lw_cascade.bike_speed(0, {down = true}, 10) >= -B.reverse, "slowly")

for count = 1, 50 do
	local life = lw_cascade.bike_life(lw_cascade.bike_seed({x = -1, y = 9, z = -90}, count))
	assert_true(life >= B.life_min and life <= B.life_min + B.life_spread,
		"a bike's life is within its range")
end
assert_eq(lw_cascade.bike_worn_out({odometer = 10, life = 80, ride_time = 5}), nil, "a new bike rides")
assert_eq(lw_cascade.bike_worn_out({odometer = 80, life = 80, ride_time = 5}), "distance",
	"it gives out after its distance")
assert_eq(lw_cascade.bike_worn_out({odometer = 1, life = 80, ride_time = B.max_ride}), "time",
	"or after its time")
assert_true(lw_cascade.rack_ready(nil, 0), "a rack with no broken bike is ready")
assert_true(not lw_cascade.rack_ready(100, 100 + B.respawn - 1), "not straight after a breakdown")
assert_true(lw_cascade.rack_ready(100, 100 + B.respawn), "and ready again after the respawn")

-- A rack puts out a bike, one at a time.
local rack = {x = 0, y = 9, z = -90}
world[key(rack)] = {name = "lw_cascade:bike_rack", param2 = 1}
local rack_def = core.registered_nodes["lw_cascade:bike_rack"]
assert_eq(rack_def.walkable, false, "the bike stands in the rack's cell")
rack_def.on_construct(rack)
assert_true(timers[key(rack)] ~= nil, "a rack runs on a node timer")
rack_def.on_timer(rack)
local bikes = live("lw_cascade:bicycle")
assert_eq(#bikes, 1, "a rack puts out a bike")
assert_eq(entity_defs["lw_cascade:bicycle"].initial_properties.static_save, false,
	"bikes are never saved")
rack_def.on_timer(rack)
assert_eq(#live("lw_cascade:bicycle"), 1, "and only one")
local bike_obj = bikes[1]
local bike = bike_obj:get_luaentity()
assert_true(math.abs(bike_obj:get_yaw() - core.dir_to_yaw({x = 1, y = 0, z = 0})) < 1e-6,
	"parked along the rack")
assert_true(lw_cascade.racks[key(rack)] ~= nil, "/bike knows where the rack is")

-- Ride it.
local rider = FakePlayer("rider", {x = 1, y = 9, z = -90})
players.rider = rider
bike:on_punch(rider)
assert_eq(rider:get_attach(), bike_obj, "punching a bike gets on it")
assert_eq(bike.driver, "rider", "it knows who is riding")
local other = FakePlayer("other", {x = 1, y = 9, z = -91})
players.other = other
bike:on_rightclick(other)
assert_eq(other:get_attach(), nil, "nobody else gets on")
assert_true(last_chat("other"):find("rider is riding") ~= nil, "and is told why")

rider._control = {up = true}
rider._look = 0
for _ = 1, 10 do
	bike:on_step(0.1, {touching_ground = true})
	bike_obj:set_pos(vector.add(bike_obj:get_pos(), vector.multiply(bike_obj:get_velocity(), 0.1)))
end
assert_true(bike_obj:get_velocity().z > 0, "pedalling rides the way the rider looks")
assert_true(bike.odometer > 0, "and runs up the odometer")
assert_true(lw_cascade.bike_status(rider):find("You have ridden") ~= nil, "/bike reports the ride")
rider._look = math.pi / 2
bike:on_step(0.1, {touching_ground = true})
assert_true(bike_obj:get_velocity().x < 0, "it steers with the rider's look")

-- Ride it into the ground.
rider._look = 0
local guard = 0
while not bike.broken and guard < 2000 do
	guard = guard + 1
	bike:on_step(0.1, {touching_ground = true})
	bike_obj:set_pos(vector.add(bike_obj:get_pos(), vector.multiply(bike_obj:get_velocity(), 0.1)))
end
assert_true(bike.broken, "a bike breaks down in the end")
assert_true(bike.odometer >= bike.life or bike.ride_time >= B.max_ride, "after its distance or time")
assert_eq(rider:get_attach(), nil, "and throws its rider off")
assert_true(last_chat("rider"):find("This bike is done") ~= nil, "who is told to find another")
bike:on_rightclick(rider)
assert_eq(rider:get_attach(), nil, "a broken bike cannot be ridden")

-- The rack waits before it puts out another.
for _ = 1, 200 do
	bike:on_step(0.1, {touching_ground = true})
end
assert_true(bike_obj:get_pos() == nil, "the wreck clears away")
rack_def.on_timer(rack)
assert_eq(#live("lw_cascade:bicycle"), 0, "the rack has no bike straight away")
assert_true(core.get_meta(rack):get_string("infotext"):find("arrives in") ~= nil,
	"and says when the next one comes")
core._gametime = core._gametime + B.respawn
rack_def.on_timer(rack)
assert_eq(#live("lw_cascade:bicycle"), 1, "then a new one")
local second = live("lw_cascade:bicycle")[1]:get_luaentity()
assert_true(second.seed ~= bike.seed, "which is not the same bike")

-- Sneak gets off; a bike ridden off and left goes back to its rack.
second:on_rightclick(rider)
assert_eq(rider:get_attach(), second.object, "on the new one")
rider._control = {sneak = true}
second:on_step(0.1, {touching_ground = true})
assert_eq(rider:get_attach(), nil, "sneak gets off")
assert_eq(second.driver, nil, "and the bike is free")
for _ = 1, math.ceil(B.idle_limit / 0.5) + 2 do
	second:on_step(0.5, {touching_ground = true})
end
assert_true(second.object:get_pos() == nil, "a bike left lying about is taken back")
rack_def.on_timer(rack)
assert_eq(#live("lw_cascade:bicycle"), 1, "and its rack puts out a fresh one at once")

-- Leaving the game mid-ride frees the bike.
local third = live("lw_cascade:bicycle")[1]:get_luaentity()
rider._control = {}
third:on_punch(rider)
core._leave(rider)
players.rider = nil
third:on_step(0.1, {touching_ground = true})
assert_eq(third.driver, nil, "a rider who leaves frees the bike")

assert_true(core._commands.bike ~= nil and core._commands.gems ~= nil, "/bike and /gems exist")
local ok, text = core._commands.gems.func("visitor", "")
assert_true(ok and text:find("red %+ yellow = orange") ~= nil, "/gems lists the recipes")

if failures > 0 then
	io.stderr:write(failures .. " failure(s)\n")
	os.exit(1)
end
print("cascade checks ok")

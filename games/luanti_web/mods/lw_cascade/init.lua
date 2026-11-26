-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The waterfall cascade's two things to do: bicycles you find in racks and
-- ride until they break, and gems you dig out of geodes and fuse into other
-- colours, then drop and push around.
--
-- Both are cheap on purpose. A bike is one entity with no vehicle physics
-- beyond "go where the rider looks", and it is never saved: a rack puts one
-- out while its block is loaded and nobody has broken its last one lately. A
-- gem on the ground is one small entity that slows down by itself. Nothing
-- here does damage, and there is still no crafting: gems fuse in the hand
-- (right click) or on the ground (roll two into each other).

lw_cascade = {}

local MP = core.get_modpath("lw_cascade")
dofile(MP .. DIR_DELIM .. "logic.lua")

local GEM, BIKE = lw_cascade.GEM, lw_cascade.BIKE

local function chat(player, message)
	if player and player.is_player and player:is_player() and message then
		core.chat_send_player(player:get_player_name(), message)
	end
end

local function now()
	return core.get_gametime and core.get_gametime() or 0
end

local function sparkle(pos, color, amount)
	core.add_particlespawner({
		amount = amount or 16,
		time = 0.4,
		minpos = vector.offset(pos, -0.3, -0.2, -0.3),
		maxpos = vector.offset(pos, 0.3, 0.3, 0.3),
		minvel = {x = -1.5, y = 0.5, z = -1.5}, maxvel = {x = 1.5, y = 2.5, z = 1.5},
		minacc = {x = 0, y = -3, z = 0}, maxacc = {x = 0, y = -3, z = 0},
		minexptime = 0.4, maxexptime = 0.9,
		minsize = 1, maxsize = 2,
		texture = "lw_mist.png^[multiply:" .. color,
		glow = 14,
	})
end

--------------------------------------------------------------------------
-- Gems
--------------------------------------------------------------------------

local function gem_image(gem)
	if gem.name == "prism" then
		return "lw_gem.png^[brighten"
	end
	return "lw_gem.png^[multiply:" .. gem.hex
end

-- A pushable gem on the ground, `velocity` optional.
function lw_cascade.spawn_gem(pos, color, velocity)
	local object = core.add_entity(pos, "lw_cascade:gem", color)
	if object and velocity then
		object:set_velocity(velocity)
	end
	return object
end

-- Right click with a gem: fuse it with the first gem in the visitor's
-- inventory it has a recipe with. Returns the wielded stack, one lighter if
-- it fused.
function lw_cascade.fuse_in_inventory(itemstack, player)
	local color = lw_cascade.gem_color(itemstack:get_name())
	if not (color and player and player.get_inventory) then
		return itemstack
	end
	local inv = player:get_inventory()
	for _, partner in ipairs(lw_cascade.partners(color)) do
		local other = lw_cascade.gem_item(partner.with)
		if inv:contains_item("main", other) then
			inv:remove_item("main", other)
			itemstack:take_item(1)
			local made = ItemStack(lw_cascade.gem_item(partner.makes))
			local left = inv:add_item("main", made)
			if not left:is_empty() then
				lw_cascade.spawn_gem(vector.offset(player:get_pos(), 0, 1, 0), partner.makes)
			end
			sparkle(vector.offset(player:get_pos(), 0, 1.2, 0),
				lw_cascade.gem_by_name[partner.makes].hex)
			chat(player, ("%s + %s: they fuse into a %s gem."):format(
				lw_cascade.gem_title(color), lw_cascade.gem_title(partner.with),
				lw_cascade.gem_title(partner.makes)))
			return itemstack
		end
	end
	chat(player, lw_cascade.fuse_hint(color))
	return itemstack
end

-- Q drops one gem at a time, as a gem you can push rather than an item that
-- just sits there, thrown a little way along the visitor's look.
function lw_cascade.drop_gem(itemstack, dropper)
	local color = lw_cascade.gem_color(itemstack:get_name())
	if not (color and dropper and dropper.get_pos) then
		return itemstack
	end
	local dir = dropper.get_look_dir and dropper:get_look_dir() or {x = 0, y = 0, z = 1}
	local eye = vector.offset(dropper:get_pos(), 0, 1.3, 0)
	local pos = vector.offset(eye, dir.x * 0.7, dir.y * 0.7, dir.z * 0.7)
	if lw_cascade.spawn_gem(pos, color, {x = dir.x * 3, y = dir.y * 3 + 1.5, z = dir.z * 3}) then
		itemstack:take_item(1)
	end
	return itemstack
end

for _, gem in ipairs(lw_cascade.GEMS) do
	local image = gem_image(gem)
	core.register_craftitem("lw_cascade:gem_" .. gem.name, {
		description = gem.desc .. " Gem\n" ..
			"Right click: fuse with another gem you carry\n" ..
			"Q: drop it, then punch it or walk into it to push it",
		inventory_image = image,
		wield_image = image,
		stack_max = 99,
		-- Not in the palette: a gem is something you dig for.
		groups = {lw_gem = 1, not_in_creative_inventory = 1},
		on_place = function(itemstack, placer, pointed)
			-- A node's own right click (a seat, a console) comes first.
			if pointed and pointed.type == "node" then
				local node = core.get_node(pointed.under)
				local def = core.registered_nodes[node.name]
				if def and def.on_rightclick then
					return def.on_rightclick(pointed.under, node, placer, itemstack, pointed)
				end
			end
			return lw_cascade.fuse_in_inventory(itemstack, placer)
		end,
		on_secondary_use = function(itemstack, user)
			return lw_cascade.fuse_in_inventory(itemstack, user)
		end,
		on_drop = function(itemstack, dropper)
			return lw_cascade.drop_gem(itemstack, dropper)
		end,
	})
end

-- Geodes: stone with crystals in it, in the three primaries. Dig one for its
-- gem and it goes dull, then grows its crystal back.
lw_cascade.GEODE_REGROW = 60

local function geode_tile(hex)
	return "lw_stone.png^(lw_geode.png^[multiply:" .. hex .. ")"
end

for _, color in ipairs(lw_cascade.PRIMARY) do
	local gem = lw_cascade.gem_by_name[color]
	core.register_node("lw_cascade:geode_" .. color, {
		description = gem.desc .. " Geode\nDig it for a " .. color .. " gem; it grows back",
		tiles = {geode_tile(gem.hex)},
		paramtype = "light",
		light_source = 5,
		is_ground_content = false,
		drop = lw_cascade.gem_item(color),
		groups = {cracky = 2, lw_geode = 1},
		after_dig_node = function(pos)
			core.set_node(pos, {name = "lw_cascade:geode_spent"})
			core.get_meta(pos):set_string("regrow", color)
			core.get_node_timer(pos):start(lw_cascade.GEODE_REGROW)
		end,
	})
end

core.register_node("lw_cascade:geode_spent", {
	description = "Spent Geode\nIts crystal grows back in a minute",
	tiles = {geode_tile("#4a4a58")},
	is_ground_content = false,
	drop = "",
	groups = {cracky = 2, not_in_creative_inventory = 1},
	on_timer = function(pos)
		local color = core.get_meta(pos):get_string("regrow")
		if not lw_cascade.gem_by_name[color] then
			color = "red"
		end
		core.set_node(pos, {name = "lw_cascade:geode_" .. color})
		return false
	end,
})

local GEM_BOX = {-0.2, -0.2, -0.2, 0.2, 0.2, 0.2}

core.register_entity("lw_cascade:gem", {
	initial_properties = {
		physical = true,
		collide_with_objects = false,
		collisionbox = GEM_BOX,
		selectionbox = {-0.25, -0.25, -0.25, 0.25, 0.25, 0.25},
		visual = "wielditem",
		wield_item = "lw_cascade:gem_red",
		visual_size = {x = 0.3, y = 0.3},
		automatic_rotate = 0.6,
		glow = 8,
		-- A dropped gem is the visitor's, so it keeps, like a dropped item,
		-- until it fades after GEM.lifetime on the ground.
		static_save = true,
	},
	color = "red",
	age = 0,
	tick = 0,
	on_activate = function(self, staticdata, dtime_s)
		local data = core.deserialize(staticdata or "")
		if type(data) == "table" then
			self.color = data.color
			self.age = (data.age or 0) + (dtime_s or 0)
		elseif type(staticdata) == "string" and staticdata ~= "" then
			self.color = staticdata
		end
		if not lw_cascade.gem_by_name[self.color] then
			self.color = "red"
		end
		self.object:set_properties({
			wield_item = lw_cascade.gem_item(self.color),
			infotext = lw_cascade.gem_title(self.color) .. " gem\n" ..
				"Punch to push, right click to pick up",
		})
		self.object:set_armor_groups({immortal = 1})
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
	end,
	get_staticdata = function(self)
		return core.serialize({color = self.color, age = self.age})
	end,
	on_punch = function(self, puncher, _, _, dir)
		if puncher and puncher.get_pos then
			local from = puncher:get_pos()
			local push = lw_cascade.push_velocity(from, self.object:get_pos(), GEM.push)
			if dir and push.x == 0 and push.z == 0 then
				push = {x = dir.x * GEM.push, y = 0, z = dir.z * GEM.push}
			end
			push.y = GEM.pop
			self.object:set_velocity(push)
			self.pusher = puncher.get_player_name and puncher:get_player_name() or nil
		end
		return true
	end,
	on_rightclick = function(self, clicker)
		if not (clicker and clicker.get_inventory) then
			return
		end
		local left = clicker:get_inventory():add_item("main", lw_cascade.gem_item(self.color))
		if left:is_empty() then
			self.fused = true
			self.object:remove()
		else
			chat(clicker, "Your pockets are full.")
		end
	end,
	on_step = function(self, dtime, moveresult)
		if self.fused then
			return
		end
		self.age = self.age + dtime
		if self.age > GEM.lifetime then
			self.object:remove()
			return
		end
		local on_ground = moveresult and moveresult.touching_ground
		local velocity = self.object:get_velocity()
		local slowed = lw_cascade.gem_friction(velocity, dtime, on_ground)
		if slowed.x ~= velocity.x or slowed.z ~= velocity.z then
			self.object:set_velocity(slowed)
		end

		self.tick = self.tick + dtime
		if self.tick < 0.2 then
			return
		end
		self.tick = 0
		local pos = self.object:get_pos()
		for _, other in ipairs(core.get_objects_inside_radius(pos, GEM.bump_radius)) do
			if other:is_player() then
				-- Walking into a gem shoves it on ahead, a little faster
				-- than the walker, so it rolls out of the way.
				if not other:get_attach() then
					local v = other:get_velocity()
					local speed = math.max(GEM.bump, math.sqrt(v.x * v.x + v.z * v.z) + 1)
					local push = lw_cascade.push_velocity(other:get_pos(), pos, speed)
					push.y = math.max(self.object:get_velocity().y, 0.5)
					self.object:set_velocity(push)
					self.pusher = other:get_player_name()
				end
			else
				local entity = other:get_luaentity()
				if entity and entity ~= self and entity.name == "lw_cascade:gem"
						and not entity.fused
						and vector.distance(pos, other:get_pos()) <= GEM.fuse_radius then
					local made = lw_cascade.fuse(self.color, entity.color)
					if made then
						lw_cascade.fuse_on_ground(self, entity, made)
						return
					end
				end
			end
		end
	end,
})

-- Two gems that rolled into each other: both go, the gem they make pops up
-- between them.
function lw_cascade.fuse_on_ground(a, b, made)
	a.fused, b.fused = true, true
	local pa, pb = a.object:get_pos(), b.object:get_pos()
	local mid = {x = (pa.x + pb.x) / 2, y = math.max(pa.y, pb.y) + 0.1, z = (pa.z + pb.z) / 2}
	local who = a.pusher or b.pusher
	local colors = {a.color, b.color}
	a.object:remove()
	b.object:remove()
	lw_cascade.spawn_gem(mid, made, {x = 0, y = 3, z = 0})
	sparkle(mid, lw_cascade.gem_by_name[made].hex, 24)
	local player = who and core.get_player_by_name(who)
	if player then
		chat(player, ("The %s and %s gems roll together and fuse into a %s gem."):format(
			colors[1], colors[2], made))
	end
end

--------------------------------------------------------------------------
-- Bicycles
--------------------------------------------------------------------------

-- Bike racks put out a bike when they have none and their last one did not
-- break in the last BIKE.respawn seconds. Everything about who is riding
-- what lives in these tables, never in the world: a bike is not saved, and
-- after a restart every rack simply puts out a new one.
local parked = {}    -- rack key -> the bike object it put out last
local wrecked = {}   -- rack key -> gametime its last bike broke
local riding = {}    -- player name -> the bike object they are on
lw_cascade.racks = {} -- rack key -> position, for every rack whose timer has run

local RACK_INTERVAL = 4
local SIT_FRAMES = {x = 81, y = 160}
local STAND_FRAMES = {x = 0, y = 79}

local function rack_key(pos)
	return ("%d,%d,%d"):format(pos.x, pos.y, pos.z)
end

local function alive(object)
	return object ~= nil and object:get_pos() ~= nil
end

local function rack_infotext(pos, text)
	core.get_meta(pos):set_string("infotext", "Bike rack\n" .. text)
end

-- One tick of a rack: put a bike out if it should have one.
function lw_cascade.rack_tick(pos)
	local key = rack_key(pos)
	lw_cascade.racks[key] = vector.new(pos)
	local bike = parked[key]
	if alive(bike) then
		local entity = bike:get_luaentity()
		if entity and entity.driver then
			rack_infotext(pos, "Its bike is out with " .. entity.driver .. ".")
		elseif entity and entity.broken then
			rack_infotext(pos, "Its bike just broke down.")
		else
			rack_infotext(pos, "Right click (or punch) the bike to ride it.")
		end
		return
	end
	parked[key] = nil
	if not lw_cascade.rack_ready(wrecked[key], now()) then
		rack_infotext(pos, ("A new bike arrives in %d s."):format(
			math.ceil(BIKE.respawn - (now() - wrecked[key]))))
		return
	end
	local meta = core.get_meta(pos)
	local count = meta:get_int("bikes") + 1
	meta:set_int("bikes", count)
	local node = core.get_node(pos)
	local yaw = core.dir_to_yaw(core.facedir_to_dir(node.param2 % 4))
	local object = core.add_entity(pos, "lw_cascade:bicycle", core.serialize({
		rack = key, seed = lw_cascade.bike_seed(pos, count), yaw = yaw,
	}))
	parked[key] = object
	wrecked[key] = nil
	rack_infotext(pos, "Right click (or punch) the bike to ride it.")
end

-- A low rail with a post at each end: the bike stands against it, in the
-- rack's own cell, so the rack is not walkable.
local RACK_BOX = {
	{0.28, -0.5, -0.45, 0.4, 0.15, -0.35},
	{0.28, -0.5, 0.35, 0.4, 0.15, 0.45},
	{0.28, 0.05, -0.45, 0.4, 0.15, 0.45},
	{0.25, -0.5, -0.45, 0.43, -0.44, 0.45},
}

core.register_node("lw_cascade:bike_rack", {
	description = "Bike Rack\nPuts out a bicycle; when one breaks down it gets another",
	drawtype = "nodebox",
	tiles = {"lw_polished_stone.png^[multiply:#8a9ab0"},
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	walkable = false,
	on_place = core.rotate_node,
	node_box = {type = "fixed", fixed = RACK_BOX},
	selection_box = {type = "fixed", fixed = {-0.45, -0.5, -0.45, 0.45, 0.2, 0.45}},
	is_ground_content = false,
	groups = {cracky = 2, oddly_breakable_by_hand = 2},
	on_construct = function(pos)
		rack_infotext(pos, "A bike will be along in a moment.")
		core.get_node_timer(pos):start(RACK_INTERVAL)
	end,
	on_timer = function(pos)
		lw_cascade.rack_tick(pos)
		return true
	end,
	on_destruct = function(pos)
		local key = rack_key(pos)
		local bike = parked[key]
		local entity = alive(bike) and bike:get_luaentity()
		if entity and not entity.driver then
			bike:remove()
		end
		parked[key] = nil
		lw_cascade.racks[key] = nil
	end,
	on_rightclick = function(pos, _, clicker)
		local bike = parked[rack_key(pos)]
		local entity = alive(bike) and bike:get_luaentity()
		if entity and not entity.driver and not entity.broken then
			lw_cascade.mount(entity, clicker)
		else
			chat(clicker, core.get_meta(pos):get_string("infotext"))
		end
	end,
})

local function set_rider_pose(player, sitting)
	if player.set_animation then
		player:set_animation(sitting and SIT_FRAMES or STAND_FRAMES, 15, 0, true)
	end
	if player.set_eye_offset then
		if sitting then
			player:set_eye_offset({x = 0, y = -2, z = 0}, {x = 0, y = 0, z = -6})
		else
			player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
		end
	end
end

function lw_cascade.mount(self, player)
	if not (player and player.is_player and player:is_player()) then
		return false
	end
	local name = player:get_player_name()
	if self.broken then
		chat(player, "This bike is broken. Find another at a bike rack (/bike).")
		return false
	end
	if self.driver then
		chat(player, self.driver == name and "You are already on it." or
			self.driver .. " is riding this one.")
		return false
	end
	if alive(riding[name]) or player:get_attach() then
		chat(player, "You can only ride one thing at a time.")
		return false
	end
	local dance = rawget(_G, "lw_dance")
	if dance and dance.is_dancing and dance.is_dancing(player) then
		dance.exit(player)
	end
	self.driver = name
	self.taken = true
	self.idle = 0
	riding[name] = self.object
	player:set_attach(self.object, "", {x = 0, y = 3, z = -1}, {x = 0, y = 0, z = 0})
	set_rider_pose(player, true)
	chat(player, "You are riding. Forward pedals, back brakes, jump hops, sneak " ..
		"gets off. No bike lasts for ever: /bike says how this one is doing.")
	return true
end

function lw_cascade.dismount(self, player, message)
	if self.driver then
		riding[self.driver] = nil
	end
	self.driver = nil
	self.idle = 0
	if player and player.is_player and player:is_player() then
		player:set_detach()
		set_rider_pose(player, false)
		local pos = self.object:get_pos()
		if pos then
			local yaw = self.object:get_yaw() or 0
			-- Off to the left of the bike, standing.
			player:set_pos({x = pos.x - math.cos(yaw) * 0.8, y = pos.y + 0.6,
				z = pos.z - math.sin(yaw) * 0.8})
		end
		chat(player, message)
	end
end

function lw_cascade.break_down(self, player, reason)
	self.broken = true
	self.wreck = 0
	if self.rack then
		wrecked[self.rack] = now()
	end
	lw_cascade.dismount(self, player, lw_cascade.breakdown_message(self.seed or 0, reason))
	local v = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	self.object:set_velocity({x = 0, y = v.y, z = 0})
	self.object:set_properties({
		textures = {"lw_bicycle.png^[multiply:#707070"},
		infotext = "Broken bicycle\nFind another at a bike rack (/bike)",
	})
	-- On its side, where it fell.
	self.object:set_rotation({x = 0, y = self.object:get_yaw() or 0, z = 1.35})
	sparkle(self.object:get_pos(), "#ffd27a", 20)
end

core.register_entity("lw_cascade:bicycle", {
	initial_properties = {
		physical = true,
		collide_with_objects = false,
		collisionbox = {-0.3, -0.5, -0.3, 0.3, 0.45, 0.3},
		selectionbox = {-0.25, -0.5, -0.6, 0.25, 0.45, 0.6, rotate = true},
		stepheight = 1.1,
		visual = "mesh",
		mesh = "lw_bicycle.obj",
		textures = {"lw_bicycle.png"},
		backface_culling = false,
		-- A rack puts out a new one; a saved bike would be a second one.
		static_save = false,
		infotext = "Bicycle\nRight click or punch to ride",
	},
	speed = 0,
	odometer = 0,
	ride_time = 0,
	idle = 0,
	on_activate = function(self, staticdata)
		local data = core.deserialize(staticdata or "")
		if type(data) ~= "table" then
			data = {}
		end
		self.rack = data.rack
		self.seed = data.seed or 0
		self.life = lw_cascade.bike_life(self.seed)
		self.object:set_yaw(data.yaw or 0)
		self.object:set_properties({textures = {"lw_bicycle.png^(lw_bicycle_paint.png^[multiply:" ..
			lw_cascade.bike_paint(self.seed) .. ")"}})
		self.object:set_armor_groups({immortal = 1})
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
	end,
	on_rightclick = function(self, clicker)
		if self.driver and clicker and clicker:get_player_name() == self.driver then
			lw_cascade.dismount(self, clicker, "You get off.")
		else
			lw_cascade.mount(self, clicker)
		end
	end,
	on_punch = function(self, puncher)
		if not self.driver then
			lw_cascade.mount(self, puncher)
		end
		return true
	end,
	on_deactivate = function(self)
		local player = self.driver and core.get_player_by_name(self.driver)
		if player then
			lw_cascade.dismount(self, player, "Your bike is gone.")
		end
	end,
	on_step = function(self, dtime, moveresult)
		if self.broken then
			self.wreck = self.wreck + dtime
			if self.wreck > BIKE.wreck_time then
				self.object:remove()
			end
			return
		end
		local driver = self.driver and core.get_player_by_name(self.driver)
		if self.driver and not (driver and driver:get_attach() == self.object) then
			-- They left the game, or something else (a seat) took them.
			riding[self.driver] = nil
			self.driver, driver = nil, nil
		end
		local v = self.object:get_velocity()
		local on_ground = moveresult and moveresult.touching_ground
		if driver then
			local control = driver:get_player_control()
			if control.sneak then
				lw_cascade.dismount(self, driver, "You hop off.")
				return
			end
			local yaw = driver:get_look_horizontal()
			self.object:set_yaw(yaw)
			self.speed = lw_cascade.bike_speed(self.speed, control, dtime)
			local vy = v.y
			if control.jump and on_ground then
				vy = BIKE.hop
			end
			self.object:set_velocity({x = -math.sin(yaw) * self.speed, y = vy,
				z = math.cos(yaw) * self.speed})
			local pos = self.object:get_pos()
			local last = self.last_pos
			if last then
				local moved = math.sqrt((pos.x - last.x) ^ 2 + (pos.z - last.z) ^ 2)
				-- A jump of more than a few nodes is a teleport, not a ride.
				if moved < 4 then
					self.odometer = self.odometer + moved
				end
			end
			self.last_pos = pos
			self.ride_time = self.ride_time + dtime
			local reason = lw_cascade.bike_worn_out(self)
			if reason then
				lw_cascade.break_down(self, driver, reason)
			end
			return
		end
		self.last_pos = nil
		self.speed = 0
		if (v.x ~= 0 or v.z ~= 0) and on_ground then
			local keep = math.max(0, 1 - 3 * dtime)
			self.object:set_velocity({x = v.x * keep, y = v.y, z = v.z * keep})
		end
		if self.taken then
			self.idle = self.idle + dtime
			if self.idle > BIKE.idle_limit then
				-- Left somewhere: its rack puts out a fresh one.
				self.object:remove()
			end
		end
	end,
})

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	local bike = riding[name]
	local entity = alive(bike) and bike:get_luaentity()
	if entity then
		entity.driver = nil
	end
	riding[name] = nil
end)

-- Where the nearest rack is from `pos`, as a direction and a distance.
local function compass(from, to)
	local dx, dz = to.x - from.x, to.z - from.z
	local words = {}
	if math.abs(dz) >= 2 then
		words[#words + 1] = dz > 0 and "north" or "south"
	end
	if math.abs(dx) >= 2 then
		words[#words + 1] = dx > 0 and "east" or "west"
	end
	local way = #words > 0 and table.concat(words, "-") or "right here"
	return ("%d nodes %s"):format(math.floor(math.sqrt(dx * dx + dz * dz) + 0.5), way)
end

function lw_cascade.bike_status(player)
	local name = player:get_player_name()
	local lines = {}
	local bike = riding[name]
	local entity = alive(bike) and bike:get_luaentity()
	if entity then
		lines[#lines + 1] = ("You have ridden %d nodes. %s"):format(
			math.floor(entity.odometer), lw_cascade.bike_condition(entity))
	end
	local pos = player:get_pos()
	local best, best_d
	for _, rack in pairs(lw_cascade.racks) do
		local d = vector.distance(pos, rack)
		if not best_d or d < best_d then
			best, best_d = rack, d
		end
	end
	if best then
		local text = core.get_meta(best):get_string("infotext"):gsub("^Bike rack\n", "")
		lines[#lines + 1] = ("Nearest bike rack: %s. %s"):format(compass(pos, best), text)
	else
		lines[#lines + 1] = "The bike racks are beside the path up the waterfall " ..
			"cascade: /maps waterfall_cascade."
	end
	return table.concat(lines, "\n")
end

core.register_chatcommand("bike", {
	params = "",
	description = "How your bicycle is holding up, and where the nearest bike rack is",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You have to be in the world."
		end
		return true, lw_cascade.bike_status(player)
	end,
})

core.register_chatcommand("gems", {
	params = "",
	description = "What the cascade's gems fuse into",
	func = function()
		local lines = {"Dig a geode on the waterfall cascade for a red, yellow or blue " ..
			"gem. Right click with a gem to fuse it with one you carry, or drop " ..
			"two (Q) and push them together:"}
		for _, recipe in ipairs(lw_cascade.RECIPES) do
			lines[#lines + 1] = ("  %s + %s = %s"):format(recipe[1], recipe[2], recipe[3])
		end
		return true, table.concat(lines, "\n")
	end,
})

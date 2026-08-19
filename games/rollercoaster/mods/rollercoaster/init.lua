-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Rollercoaster Park: placeable track segments, rideable carts, ornate demo layout.

core.register_alias("mapgen_singlenode", "air")
core.register_alias("mapgen_stone", "rollercoaster:stone")
core.register_alias("mapgen_water_source", "rollercoaster:water")
core.register_alias("mapgen_river_water_source", "rollercoaster:water")
core.register_alias("mapgen_dirt", "rollercoaster:dirt")
core.register_alias("mapgen_dirt_with_grass", "rollercoaster:dirt_with_grass")
core.register_alias("mapgen_sand", "rollercoaster:sand")

--------------------------------------------------------------------
-- Terrain nodes
--------------------------------------------------------------------

core.register_node("rollercoaster:stone", {
	description = "Stone",
	tiles = {"default_stone.png"},
	groups = {cracky = 3},
})

core.register_node("rollercoaster:dirt", {
	description = "Dirt",
	tiles = {"default_dirt.png"},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("rollercoaster:dirt_with_grass", {
	description = "Dirt with Grass",
	tiles = {
		"default_grass.png",
		"default_dirt.png",
		{name = "default_grass_side.png", tileable_vertical = false},
	},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("rollercoaster:sand", {
	description = "Sand",
	tiles = {"default_sand.png"},
	groups = {crumbly = 3},
})

core.register_node("rollercoaster:cobble", {
	description = "Cobble",
	tiles = {"default_cobble.png"},
	groups = {cracky = 3},
})

core.register_node("rollercoaster:water", {
	description = "Water",
	drawtype = "liquid",
	waving = 3,
	tiles = {"default_water.png^[opacity:160"},
	special_tiles = {
		{name = "default_water.png^[opacity:160", backface_culling = false},
		{name = "default_water.png^[opacity:160", backface_culling = true},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drowning = 1,
	liquidtype = "source",
	liquid_alternative_source = "rollercoaster:water",
	liquid_alternative_flowing = "rollercoaster:water",
	liquid_viscosity = 1,
	liquid_renewable = false,
	liquid_range = 0,
	post_effect_color = {a = 64, r = 100, g = 100, b = 200},
	groups = {water = 3, liquid = 3},
})

--------------------------------------------------------------------
-- Track segments (placeable building pieces)
--------------------------------------------------------------------

local track_box = {
	type = "fixed",
	fixed = {
		{-0.5, -0.15, -0.5, 0.5, 0.05, 0.5}, -- deck
		{-0.45, 0.05, -0.5, -0.30, 0.22, 0.5}, -- left rail
		{0.30, 0.05, -0.5, 0.45, 0.22, 0.5}, -- right rail
	},
}

local track_groups = {
	cracky = 2,
	oddly_breakable_by_hand = 1,
	rc_track = 1,
}

core.register_node("rollercoaster:track_straight", {
	description = "Coaster Track (Straight)",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {
		"rc_track_top.png",
		"rc_track.png",
		"rc_rail.png",
		"rc_rail.png",
		"rc_track.png",
		"rc_track.png",
	},
	node_box = track_box,
	selection_box = track_box,
	groups = track_groups,
	is_ground_content = false,
	sunlight_propagates = true,
})

core.register_node("rollercoaster:track_curve", {
	description = "Coaster Track (Curve)",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {
		"rc_track_top.png",
		"rc_track.png",
		"rc_rail.png",
	},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.15, -0.5, 0.5, 0.05, 0.15},
			{-0.15, -0.15, -0.5, 0.5, 0.05, 0.5},
			{-0.45, 0.05, -0.5, -0.30, 0.22, 0.15},
			{0.30, 0.05, -0.5, 0.45, 0.22, 0.15},
			{-0.15, 0.05, 0.30, 0.5, 0.22, 0.45},
			{-0.15, 0.05, -0.45, 0.15, 0.22, -0.30},
		},
	},
	groups = track_groups,
	is_ground_content = false,
	sunlight_propagates = true,
})

core.register_node("rollercoaster:track_ramp", {
	description = "Coaster Track (Ramp)",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {
		"rc_track_top.png",
		"rc_track.png",
		"rc_rail.png",
	},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, -0.20, -0.15},
			{-0.5, -0.35, -0.15, 0.5, -0.05, 0.15},
			{-0.5, -0.15, 0.15, 0.5, 0.15, 0.5},
			{-0.45, -0.20, -0.5, -0.30, 0.0, -0.15},
			{0.30, -0.20, -0.5, 0.45, 0.0, -0.15},
			{-0.45, 0.15, 0.15, -0.30, 0.35, 0.5},
			{0.30, 0.15, 0.15, 0.45, 0.35, 0.5},
		},
	},
	groups = track_groups,
	is_ground_content = false,
	sunlight_propagates = true,
})

core.register_node("rollercoaster:track_support", {
	description = "Track Support",
	drawtype = "nodebox",
	paramtype = "light",
	tiles = {"rc_support.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.15, -0.5, -0.15, 0.15, 0.5, 0.15},
			{-0.35, 0.35, -0.35, 0.35, 0.5, 0.35},
		},
	},
	groups = {cracky = 2, oddly_breakable_by_hand = 1},
	is_ground_content = false,
	sunlight_propagates = true,
})

core.register_node("rollercoaster:track_ornament", {
	description = "Ornate Track Filigree",
	drawtype = "nodebox",
	paramtype = "light",
	light_source = 6,
	tiles = {"rc_ornament.png", "rc_gold.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.08, -0.5, -0.08, 0.08, 0.55, 0.08},
			{-0.35, 0.35, -0.08, 0.35, 0.5, 0.08},
			{-0.08, 0.35, -0.35, 0.08, 0.5, 0.35},
			{-0.2, 0.5, -0.2, 0.2, 0.7, 0.2},
		},
	},
	groups = {cracky = 2, oddly_breakable_by_hand = 1},
	is_ground_content = false,
	sunlight_propagates = true,
})

core.register_node("rollercoaster:station_brick", {
	description = "Station Brick",
	tiles = {"rc_brick.png"},
	groups = {cracky = 2},
})

core.register_node("rollercoaster:platform", {
	description = "Station Platform",
	tiles = {"rc_platform.png"},
	groups = {cracky = 2},
})

core.register_node("rollercoaster:station_block", {
	description = "Coaster Station (spawn cart on right-click)",
	tiles = {
		"rc_station.png",
		"rc_brick.png",
		"rc_gold.png",
		"rc_gold.png",
		"rc_station.png",
		"rc_station.png",
	},
	groups = {cracky = 2},
	on_rightclick = function(pos, _node, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local cart_pos = vector.add(pos, {x = 0, y = 1.2, z = 2})
		local obj = core.add_entity(cart_pos, "rollercoaster:cart")
		if obj then
			local ent = obj:get_luaentity()
			if ent then
				ent:set_path("grand_loop", 1)
			end
			core.chat_send_player(clicker:get_player_name(),
				"Cart ready! Right-click it to board.")
		end
	end,
})

--------------------------------------------------------------------
-- Path definitions (waypoints for carts)
--------------------------------------------------------------------

-- Build a dense polyline from control points (Catmull-Rom-ish linear densify).
local function densify(points, step)
	step = step or 0.75
	local out = {}
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local d = vector.distance(a, b)
		local n = math.max(1, math.floor(d / step))
		for k = 0, n - 1 do
			local t = k / n
			out[#out + 1] = {
				x = a.x + (b.x - a.x) * t,
				y = a.y + (b.y - a.y) * t,
				z = a.z + (b.z - a.z) * t,
			}
		end
	end
	out[#out + 1] = vector.copy(points[#points])
	return out
end

-- Ornate grand loop: station → climb → left loop → helix climb → drop → figure-S → home.
local function build_grand_loop()
	local controls = {
		-- Station platform (heading +Z)
		{x = 0, y = 10.5, z = 0},
		{x = 0, y = 10.5, z = 6},
		-- First climb
		{x = 0, y = 12, z = 12},
		{x = 0, y = 15, z = 18},
		{x = 0, y = 18, z = 24},
		-- High straight with ornament zone
		{x = 0, y = 20, z = 30},
		{x = 4, y = 20, z = 36},
		-- Left bank curve
		{x = 12, y = 19, z = 40},
		{x = 20, y = 18, z = 38},
		{x = 24, y = 17, z = 30},
		-- Small loop-ish vertical oval (stylized)
		{x = 24, y = 14, z = 24},
		{x = 24, y = 12, z = 20},
		{x = 24, y = 14, z = 16},
		{x = 24, y = 18, z = 14},
		{x = 24, y = 22, z = 16},
		{x = 24, y = 24, z = 20},
		{x = 24, y = 22, z = 24},
		{x = 24, y = 18, z = 26},
		-- Helix / spiral climb
		{x = 18, y = 16, z = 28},
		{x = 12, y = 17, z = 24},
		{x = 10, y = 19, z = 16},
		{x = 14, y = 21, z = 10},
		{x = 20, y = 23, z = 8},
		{x = 26, y = 24, z = 12},
		{x = 28, y = 25, z = 18},
		-- Peak and dramatic drop
		{x = 26, y = 26, z = 24},
		{x = 20, y = 22, z = 28},
		{x = 12, y = 16, z = 28},
		{x = 4, y = 12, z = 24},
		{x = -4, y = 11, z = 16},
		-- S-curve return over the park
		{x = -10, y = 12, z = 8},
		{x = -14, y = 14, z = 0},
		{x = -12, y = 16, z = -8},
		{x = -4, y = 14, z = -12},
		{x = 4, y = 12, z = -10},
		{x = 8, y = 11, z = -4},
		-- Final approach into station
		{x = 4, y = 10.5, z = 0},
		{x = 0, y = 10.5, z = 0},
	}
	return densify(controls, 0.7)
end

local PATHS = {
	grand_loop = build_grand_loop(),
}

--------------------------------------------------------------------
-- Cart entity
--------------------------------------------------------------------

local CART_SPEED = 8 -- nodes per second along path

local function yaw_from_dir(dir)
	return math.atan2(dir.z, dir.x) - math.pi / 2
end

local function pitch_from_dir(dir)
	local horiz = math.sqrt(dir.x * dir.x + dir.z * dir.z)
	if horiz < 1e-4 then
		return dir.y > 0 and -math.pi / 2 or math.pi / 2
	end
	return -math.atan2(dir.y, horiz)
end

core.register_entity("rollercoaster:cart", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		collisionbox = {-0.45, -0.2, -0.45, 0.45, 0.7, 0.45},
		selectionbox = {-0.45, -0.2, -0.45, 0.45, 0.7, 0.45},
		visual = "cube",
		visual_size = {x = 0.9, y = 0.55, z = 1.1},
		textures = {
			"rc_cart.png", -- top
			"rc_cart_side.png", -- bottom
			"rc_cart_side.png",
			"rc_cart_side.png",
			"rc_cart.png",
			"rc_cart.png",
		},
		static_save = true,
	},

	_path_name = "grand_loop",
	_index = 1,
	_progress = 0, -- 0..1 between index and index+1
	_rider = nil,

	set_path = function(self, name, index)
		if PATHS[name] then
			self._path_name = name
			self._index = index or 1
			self._progress = 0
		end
	end,

	get_staticdata = function(self)
		return core.write_json({
			path = self._path_name,
			index = self._index,
			progress = self._progress,
		}) or ""
	end,

	on_activate = function(self, staticdata, _dtime_s)
		self.object:set_armor_groups({immortal = 1})
		if staticdata and staticdata ~= "" then
			local data = core.parse_json(staticdata)
			if data then
				self._path_name = data.path or self._path_name
				self._index = data.index or 1
				self._progress = data.progress or 0
			end
		end
	end,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local name = clicker:get_player_name()
		local attached = clicker:get_attach()
		if attached and attached == self.object then
			clicker:set_detach()
			clicker:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
			local pos = self.object:get_pos()
			clicker:set_pos({x = pos.x + 1.2, y = pos.y + 0.5, z = pos.z})
			if self._rider == name then
				self._rider = nil
			end
			core.chat_send_player(name, "You left the cart.")
			return
		end
		if self._rider and self._rider ~= name then
			core.chat_send_player(name, "That cart is occupied.")
			return
		end
		clicker:set_attach(self.object, "", {x = 0, y = 2, z = 0}, {x = 0, y = 0, z = 0})
		clicker:set_eye_offset({x = 0, y = -4, z = 0}, {x = 0, y = -4, z = 0})
		self._rider = name
		core.chat_send_player(name, "Riding! Right-click again to get off.")
	end,

	on_step = function(self, dtime, _moveresult)
		local path = PATHS[self._path_name]
		if not path or #path < 2 then
			return
		end

		-- Drop rider reference if they disconnected or detached
		if self._rider then
			local player = core.get_player_by_name(self._rider)
			if not player or player:get_attach() ~= self.object then
				self._rider = nil
			end
		end

		local i = self._index
		if i >= #path then
			self._index = 1
			self._progress = 0
			i = 1
		end

		local a = path[i]
		local b = path[math.min(i + 1, #path)]
		local seg_len = math.max(0.05, vector.distance(a, b))
		self._progress = self._progress + (CART_SPEED * dtime) / seg_len

		while self._progress >= 1 do
			self._progress = self._progress - 1
			self._index = self._index + 1
			if self._index >= #path then
				self._index = 1
			end
			i = self._index
			a = path[i]
			b = path[math.min(i + 1, #path)]
			seg_len = math.max(0.05, vector.distance(a, b))
		end

		local t = self._progress
		local pos = {
			x = a.x + (b.x - a.x) * t,
			y = a.y + (b.y - a.y) * t,
			z = a.z + (b.z - a.z) * t,
		}
		local dir = vector.direction(a, b)
		if vector.length(dir) < 1e-4 then
			dir = {x = 0, y = 0, z = 1}
		end
		self.object:set_pos(pos)
		-- set_rotation uses radians (x=pitch, y=yaw, z=roll)
		self.object:set_rotation({
			x = pitch_from_dir(dir),
			y = yaw_from_dir(dir),
			z = 0,
		})
	end,

	on_punch = function(self, puncher)
		if not puncher or not puncher:is_player() then
			return
		end
		if self._rider then
			local player = core.get_player_by_name(self._rider)
			if player then
				player:set_detach()
				player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
			end
			self._rider = nil
		end
		self.object:remove()
		puncher:get_inventory():add_item("main", "rollercoaster:cart_item")
	end,
})

core.register_craftitem("rollercoaster:cart_item", {
	description = "Rollercoaster Cart",
	inventory_image = "rc_cart.png",
	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return itemstack
		end
		local pos = vector.offset(pointed_thing.above, 0, 0.3, 0)
		local obj = core.add_entity(pos, "rollercoaster:cart")
		if obj then
			local ent = obj:get_luaentity()
			if ent then
				-- Snap to nearest waypoint on grand_loop if nearby
				local path = PATHS.grand_loop
				local best_i, best_d = 1, math.huge
				for i, p in ipairs(path) do
					local d = vector.distance(pos, p)
					if d < best_d then
						best_d = d
						best_i = i
					end
				end
				if best_d < 8 then
					ent:set_path("grand_loop", best_i)
				else
					-- Free cart still rides grand_loop from start
					ent:set_path("grand_loop", 1)
				end
			end
			if not core.is_creative_enabled(placer:get_player_name()) then
				itemstack:take_item()
			end
		end
		return itemstack
	end,
})

--------------------------------------------------------------------
-- Mapgen: park + ornate track along grand_loop
--------------------------------------------------------------------

local GROUND_Y = 8
local WATER_Y = 6
local GEN_MIN = {x = -36, y = 0, z = -24}
local GEN_MAX = {x = 40, y = 32, z = 48}

local function overlaps(minp, maxp)
	return not (maxp.x < GEN_MIN.x or minp.x > GEN_MAX.x
		or maxp.y < GEN_MIN.y or minp.y > GEN_MAX.y
		or maxp.z < GEN_MIN.z or minp.z > GEN_MAX.z)
end

local function facedir_from_dir(dx, dz)
	-- 0 = +Z, 1 = +X, 2 = -Z, 3 = -X
	if math.abs(dx) > math.abs(dz) then
		return dx >= 0 and 1 or 3
	end
	return dz >= 0 and 0 or 2
end

-- Precompute track cell placements from path
local TRACK_CELLS = {}
do
	local path = PATHS.grand_loop
	local seen = {}
	for i = 1, #path - 1 do
		local p = path[i]
		local n = path[i + 1]
		local gx = math.floor(p.x + 0.5)
		local gy = math.floor(p.y + 0.5)
		local gz = math.floor(p.z + 0.5)
		local key = gx .. "," .. gy .. "," .. gz
		if not seen[key] then
			seen[key] = true
			local dx = n.x - p.x
			local dy = n.y - p.y
			local dz = n.z - p.z
			local kind = "straight"
			if math.abs(dy) > 0.35 then
				kind = "ramp"
			elseif i > 2 then
				local prev = path[i - 1]
				local d1x, d1z = p.x - prev.x, p.z - prev.z
				local d2x, d2z = n.x - p.x, n.z - p.z
				local cross = d1x * d2z - d1z * d2x
				if math.abs(cross) > 0.25 then
					kind = "curve"
				end
			end
			TRACK_CELLS[#TRACK_CELLS + 1] = {
				x = gx, y = gy, z = gz,
				kind = kind,
				param2 = facedir_from_dir(dx, dz),
			}
		end
	end
end

core.register_on_generated(function(minp, maxp, _seed)
	if not overlaps(minp, maxp) then
		return
	end

	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()

	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("rollercoaster:stone")
	local c_dirt = core.get_content_id("rollercoaster:dirt")
	local c_grass = core.get_content_id("rollercoaster:dirt_with_grass")
	local c_sand = core.get_content_id("rollercoaster:sand")
	local c_water = core.get_content_id("rollercoaster:water")
	local c_cobble = core.get_content_id("rollercoaster:cobble")
	local c_platform = core.get_content_id("rollercoaster:platform")
	local c_brick = core.get_content_id("rollercoaster:station_brick")
	local c_support = core.get_content_id("rollercoaster:track_support")
	local c_ornament = core.get_content_id("rollercoaster:track_ornament")
	local c_straight = core.get_content_id("rollercoaster:track_straight")
	local c_curve = core.get_content_id("rollercoaster:track_curve")
	local c_ramp = core.get_content_id("rollercoaster:track_ramp")
	local c_station = core.get_content_id("rollercoaster:station_block")

	-- Base park terrain + pond
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local in_park = x >= GEN_MIN.x and x <= GEN_MAX.x
				and z >= GEN_MIN.z and z <= GEN_MAX.z
			local pond = (x * x + (z - 8) * (z - 8)) <= 36
			for y = minp.y, maxp.y do
				local vi = area:index(x, y, z)
				if in_park then
					if y < GROUND_Y - 2 then
						data[vi] = c_stone
					elseif y < GROUND_Y then
						data[vi] = pond and c_sand or c_dirt
					elseif y == GROUND_Y then
						if pond then
							data[vi] = c_sand
						else
							data[vi] = c_grass
						end
					elseif pond and y <= WATER_Y + 1 and y > GROUND_Y then
						-- shallow decorative pond only if ground cut — skip
						data[vi] = c_air
					else
						data[vi] = c_air
					end
				else
					if y <= WATER_Y then
						data[vi] = c_water
					elseif y < GROUND_Y then
						data[vi] = c_stone
					else
						data[vi] = c_air
					end
				end
			end
			-- pond water on top of sand in a dip
			if in_park and pond then
				for y = math.max(minp.y, GROUND_Y - 1), math.min(maxp.y, GROUND_Y) do
					local vi = area:index(x, y, z)
					if y < GROUND_Y then
						data[vi] = c_water
					elseif y == GROUND_Y then
						data[vi] = c_water
					end
				end
			end
		end
	end

	-- Open-air station pavilion (no closed walls — room to walk and look around)
	-- Floor plaza
	for z = -8, 8 do
		for x = -8, 8 do
			local y = GROUND_Y
			if x >= minp.x and x <= maxp.x
				and y >= minp.y and y <= maxp.y
				and z >= minp.z and z <= maxp.z then
				local r2 = x * x + z * z
				if r2 <= 64 then
					data[area:index(x, y, z)] = (r2 <= 16) and c_platform or c_cobble
				end
			end
			-- Clear air above plaza so nothing boxes the player in
			for y = GROUND_Y + 1, GROUND_Y + 8 do
				if x >= minp.x and x <= maxp.x
					and y >= minp.y and y <= maxp.y
					and z >= minp.z and z <= maxp.z
					and (x * x + z * z) <= 64 then
					data[area:index(x, y, z)] = c_air
				end
			end
		end
	end

	-- Corner posts + light roof beams only (open sides)
	for _, p in ipairs({{-5, -5}, {-5, 5}, {5, -5}, {5, 5}}) do
		for y = GROUND_Y + 1, GROUND_Y + 4 do
			if p[1] >= minp.x and p[1] <= maxp.x
				and y >= minp.y and y <= maxp.y
				and p[2] >= minp.z and p[2] <= maxp.z then
				data[area:index(p[1], y, p[2])] = c_brick
			end
		end
	end
	-- Partial roof (cross beams, still open sky views)
	for x = -5, 5 do
		local y = GROUND_Y + 5
		if x >= minp.x and x <= maxp.x
			and y >= minp.y and y <= maxp.y then
			if -5 >= minp.z and -5 <= maxp.z then
				data[area:index(x, y, -5)] = c_platform
			end
			if 5 >= minp.z and 5 <= maxp.z then
				data[area:index(x, y, 5)] = c_platform
			end
		end
	end
	for z = -5, 5 do
		local y = GROUND_Y + 5
		if z >= minp.z and z <= maxp.z
			and y >= minp.y and y <= maxp.y then
			if -5 >= minp.x and -5 <= maxp.x then
				data[area:index(-5, y, z)] = c_platform
			end
			if 5 >= minp.x and 5 <= maxp.x then
				data[area:index(5, y, z)] = c_platform
			end
		end
	end

	-- Station control block on the plaza edge (not enclosing spawn)
	if 3 >= minp.x and 3 <= maxp.x
		and (GROUND_Y + 1) >= minp.y and (GROUND_Y + 1) <= maxp.y
		and (-4) >= minp.z and (-4) <= maxp.z then
		data[area:index(3, GROUND_Y + 1, -4)] = c_station
	end

	-- Wide approach path toward the track (+Z)
	for z = 0, 12 do
		for x = -2, 2 do
			local y = GROUND_Y
			if x >= minp.x and x <= maxp.x
				and y >= minp.y and y <= maxp.y
				and z >= minp.z and z <= maxp.z then
				data[area:index(x, y, z)] = c_cobble
			end
		end
	end

	-- Viewing berm south of plaza (spawn overlook)
	for z = -14, -9 do
		for x = -6, 6 do
			local y = GROUND_Y
			if x >= minp.x and x <= maxp.x
				and y >= minp.y and y <= maxp.y
				and z >= minp.z and z <= maxp.z then
				data[area:index(x, y, z)] = c_cobble
			end
			for y = GROUND_Y + 1, GROUND_Y + 6 do
				if x >= minp.x and x <= maxp.x
					and y >= minp.y and y <= maxp.y
					and z >= minp.z and z <= maxp.z then
					data[area:index(x, y, z)] = c_air
				end
			end
		end
	end

	-- Track + supports + ornaments
	for _, cell in ipairs(TRACK_CELLS) do
		local x, y, z = cell.x, cell.y, cell.z
		if x >= minp.x and x <= maxp.x
			and y >= minp.y and y <= maxp.y
			and z >= minp.z and z <= maxp.z then
			local vi = area:index(x, y, z)
			local cid = c_straight
			if cell.kind == "curve" then
				cid = c_curve
			elseif cell.kind == "ramp" then
				cid = c_ramp
			end
			data[vi] = cid
			param2_data[vi] = cell.param2
		end
		-- supports down to ground
		for sy = y - 1, GROUND_Y + 1, -1 do
			if x >= minp.x and x <= maxp.x
				and sy >= minp.y and sy <= maxp.y
				and z >= minp.z and z <= maxp.z then
				-- place support every other column for a lighter lattice
				if (x + z) % 2 == 0 then
					local vi = area:index(x, sy, z)
					if data[vi] == c_air then
						data[vi] = c_support
					end
				end
			end
		end
		-- ornaments on high peaks
		if y >= 22 and (x + z) % 3 == 0 then
			local oy = y + 1
			if x >= minp.x and x <= maxp.x
				and oy >= minp.y and oy <= maxp.y
				and z >= minp.z and z <= maxp.z then
				data[area:index(x, oy, z)] = c_ornament
			end
		end
	end

	vm:set_data(data)
	vm:set_param2_data(param2_data)
	vm:calc_lighting()
	vm:write_to_map()
	vm:update_liquids()
end)

--------------------------------------------------------------------
-- Player setup
--------------------------------------------------------------------

-- Open overlook south of the plaza so the whole coaster is in view
local SPAWN = {x = 0, y = GROUND_Y + 2, z = -12}

core.settings:set("static_spawnpoint",
	SPAWN.x .. "," .. SPAWN.y .. "," .. SPAWN.z)
if core.set_mapgen_setting then
	core.set_mapgen_setting("mg_name", "singlenode", true)
end

local starter_items = {
	"rollercoaster:cart_item 2",
	"rollercoaster:track_straight 64",
	"rollercoaster:track_curve 32",
	"rollercoaster:track_ramp 32",
	"rollercoaster:track_support 64",
	"rollercoaster:track_ornament 16",
	"rollercoaster:platform 32",
	"rollercoaster:station_block 1",
}

core.register_on_newplayer(function(player)
	player:set_pos(SPAWN)
	local inv = player:get_inventory()
	for _, stack in ipairs(starter_items) do
		inv:add_item("main", stack)
	end
	core.chat_send_player(player:get_player_name(),
		"Welcome to Rollercoaster Park! Right-click the gold station block "
		.. "to spawn a cart, then right-click the cart to ride the grand loop. "
		.. "Use track segments in your inventory to build more coasters.")
end)

core.register_on_joinplayer(function(player)
	-- Ensure a demo cart exists near the station once the area is loaded
	core.after(2, function()
		if not player or not player:is_player() then
			return
		end
		local p = {x = 0, y = 11, z = 2}
		local objs = core.get_objects_inside_radius(p, 40)
		for _, obj in ipairs(objs) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "rollercoaster:cart" then
				return
			end
		end
		local obj = core.add_entity(p, "rollercoaster:cart")
		if obj then
			local ent = obj:get_luaentity()
			if ent then
				ent:set_path("grand_loop", 1)
			end
		end
	end)
end)

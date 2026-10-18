-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Log Ride: wooden flume segments, rideable log boats, jungle waterslide map.

core.register_alias("mapgen_singlenode", "air")
core.register_alias("mapgen_stone", "log_ride:stone")
core.register_alias("mapgen_water_source", "log_ride:water")
core.register_alias("mapgen_river_water_source", "log_ride:water")
core.register_alias("mapgen_dirt", "log_ride:dirt")
core.register_alias("mapgen_dirt_with_grass", "log_ride:dirt_with_grass")
core.register_alias("mapgen_sand", "log_ride:sand")

--------------------------------------------------------------------
-- Terrain
--------------------------------------------------------------------

core.register_node("log_ride:stone", {
	description = "Stone",
	tiles = {"lr_stone.png"},
	groups = {cracky = 3},
})

core.register_node("log_ride:dirt", {
	description = "Dirt",
	tiles = {"lr_dirt.png"},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("log_ride:dirt_with_grass", {
	description = "Dirt with Grass",
	tiles = {
		"lr_grass.png",
		"lr_dirt.png",
		{name = "default_grass_side.png", tileable_vertical = false},
	},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("log_ride:sand", {
	description = "Sand",
	tiles = {"default_sand.png"},
	groups = {crumbly = 3},
})

core.register_node("log_ride:water", {
	description = "Water",
	drawtype = "liquid",
	waving = 3,
	tiles = {
		{name = "lr_water.png", animation = {
			type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 2.0,
		}},
	},
	special_tiles = {
		{name = "lr_water.png", backface_culling = false},
		{name = "lr_water.png", backface_culling = true},
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
	liquid_alternative_source = "log_ride:water",
	liquid_alternative_flowing = "log_ride:water",
	liquid_viscosity = 1,
	liquid_renewable = false,
	liquid_range = 0,
	post_effect_color = {a = 80, r = 40, g = 90, b = 160},
	groups = {water = 3, liquid = 3, cools_lava = 1},
})

-- Shallow channel water: no drowning so boats/players float safely
core.register_node("log_ride:channel_water", {
	description = "Channel Water",
	drawtype = "liquid",
	waving = 3,
	tiles = {
		{name = "lr_water.png", animation = {
			type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 1.5,
		}},
	},
	special_tiles = {
		{name = "lr_water.png", backface_culling = false},
		{name = "lr_water.png", backface_culling = true},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drowning = 0,
	liquidtype = "source",
	liquid_alternative_source = "log_ride:channel_water",
	liquid_alternative_flowing = "log_ride:channel_water",
	liquid_viscosity = 0,
	liquid_renewable = false,
	liquid_range = 0,
	post_effect_color = {a = 50, r = 50, g = 120, b = 180},
	groups = {water = 3, liquid = 3, cools_lava = 1},
})

core.register_node("log_ride:leaves", {
	description = "Jungle Leaves",
	drawtype = "allfaces_optional",
	tiles = {"lr_leaf.png"},
	paramtype = "light",
	is_ground_content = false,
	groups = {snappy = 3},
})

core.register_node("log_ride:tree", {
	description = "Jungle Tree",
	tiles = {"default_tree_top.png", "default_tree_top.png", "default_tree.png"},
	paramtype2 = "facedir",
	is_ground_content = false,
	groups = {choppy = 2, oddly_breakable_by_hand = 1, tree = 1},
})

--------------------------------------------------------------------
-- Flume / track segments
--------------------------------------------------------------------

local flume_groups = {
	choppy = 2,
	oddly_breakable_by_hand = 1,
	lr_flume = 1,
}

-- Wooden trough floor (water sits on top as a separate node in mapgen)
core.register_node("log_ride:flume_floor", {
	description = "Flume Floor",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {"lr_wood_dark.png", "lr_wood.png", "lr_flume.png"},
	node_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, -0.15, 0.5},
	},
	selection_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, -0.15, 0.5},
	},
	groups = flume_groups,
	is_ground_content = false,
})

-- Side wall for the channel
core.register_node("log_ride:flume_wall", {
	description = "Flume Wall",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {"lr_wood.png", "lr_wood_dark.png", "lr_flume.png"},
	node_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, 0.45, 0.5},
	},
	groups = flume_groups,
	is_ground_content = false,
})

-- Full U-shaped segment for player building (floor + walls; place water on top)
local flume_box = {
	type = "fixed",
	fixed = {
		{-0.5, -0.5, -0.5, 0.5, -0.2, 0.5}, -- floor
		{-0.5, -0.2, -0.5, -0.28, 0.4, 0.5}, -- left wall
		{0.28, -0.2, -0.5, 0.5, 0.4, 0.5}, -- right wall
	},
}

core.register_node("log_ride:flume_straight", {
	description = "Flume Segment (Straight) — place channel water on top",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {
		"lr_water.png",
		"lr_wood_dark.png",
		"lr_flume.png",
	},
	node_box = flume_box,
	selection_box = flume_box,
	groups = flume_groups,
	is_ground_content = false,
})

core.register_node("log_ride:flume_curve", {
	description = "Flume Segment (Curve)",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {"lr_water.png", "lr_wood_dark.png", "lr_flume.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, -0.2, 0.15},
			{-0.15, -0.5, -0.5, 0.5, -0.2, 0.5},
			{-0.5, -0.2, -0.5, -0.28, 0.4, 0.15},
			{0.28, -0.2, -0.5, 0.5, 0.4, 0.15},
			{-0.15, -0.2, 0.28, 0.5, 0.4, 0.5},
			{-0.15, -0.2, -0.5, 0.15, 0.4, -0.28},
		},
	},
	groups = flume_groups,
	is_ground_content = false,
})

core.register_node("log_ride:flume_ramp", {
	description = "Flume Segment (Ramp / Drop)",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {"lr_water.png", "lr_wood_dark.png", "lr_flume.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, -0.15, -0.1},
			{-0.5, -0.35, -0.1, 0.5, 0.0, 0.2},
			{-0.5, -0.2, 0.2, 0.5, 0.2, 0.5},
			{-0.5, -0.15, -0.5, -0.28, 0.3, -0.1},
			{0.28, -0.15, -0.5, 0.5, 0.3, -0.1},
			{-0.5, 0.2, 0.2, -0.28, 0.55, 0.5},
			{0.28, 0.2, 0.2, 0.5, 0.55, 0.5},
		},
	},
	groups = flume_groups,
	is_ground_content = false,
})

core.register_node("log_ride:splash", {
	description = "Splash Pad",
	drawtype = "nodebox",
	paramtype = "light",
	tiles = {"lr_splash.png", "lr_wood.png"},
	use_texture_alpha = "blend",
	walkable = false,
	node_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, -0.35, 0.5},
	},
	groups = {choppy = 3, oddly_breakable_by_hand = 1},
	is_ground_content = false,
})

core.register_node("log_ride:dock", {
	description = "Boarding Dock",
	tiles = {"lr_dock.png", "lr_wood_dark.png"},
	groups = {choppy = 2, oddly_breakable_by_hand = 1},
})

core.register_node("log_ride:support", {
	description = "Flume Support",
	drawtype = "nodebox",
	paramtype = "light",
	tiles = {"lr_wood_dark.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.12, -0.5, -0.12, 0.12, 0.5, 0.12},
			{-0.3, 0.35, -0.3, 0.3, 0.5, 0.3},
		},
	},
	groups = {choppy = 2, oddly_breakable_by_hand = 1},
	is_ground_content = false,
	sunlight_propagates = true,
})

core.register_node("log_ride:station", {
	description = "Log Ride Station (spawn boat on right-click)",
	tiles = {
		"lr_dock.png",
		"lr_wood_dark.png",
		"lr_wood.png",
	},
	groups = {choppy = 2},
	on_rightclick = function(pos, _node, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local boat_pos = vector.add(pos, {x = 0, y = 0.8, z = 2})
		local obj = core.add_entity(boat_pos, "log_ride:log_boat")
		if obj then
			local ent = obj:get_luaentity()
			if ent then
				ent:set_path("jungle_flume", 1)
			end
			core.chat_send_player(clicker:get_player_name(),
				"Log boat ready! Right-click it to ride the flume.")
		end
	end,
})

--------------------------------------------------------------------
-- Path: jungle flume waterslide
--------------------------------------------------------------------

local function densify(points, step)
	step = step or 0.65
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

-- Boarding dock → slow channel → climb chain-lift style (slow rise) →
-- big drop → winding canyon → splash pool → lazy river home.
local function build_jungle_flume()
	local controls = {
		-- Boarding
		{x = 0, y = 9.2, z = 0},
		{x = 0, y = 9.2, z = 5},
		{x = 0, y = 9.3, z = 10},
		-- Gentle meander
		{x = 3, y = 9.5, z = 14},
		{x = 7, y = 10, z = 16},
		{x = 10, y = 10.5, z = 14},
		-- Lift hill (slow rise)
		{x = 12, y = 12, z = 10},
		{x = 12, y = 14, z = 6},
		{x = 12, y = 16, z = 2},
		{x = 12, y = 18, z = -2},
		{x = 10, y = 19, z = -6},
		-- Crest
		{x = 6, y = 19.5, z = -8},
		{x = 2, y = 19, z = -8},
		-- Big drop
		{x = -2, y = 16, z = -7},
		{x = -6, y = 13, z = -5},
		{x = -8, y = 11, z = -1},
		{x = -8, y = 10, z = 4},
		-- Banked curve into canyon
		{x = -6, y = 9.5, z = 9},
		{x = -2, y = 9.2, z = 13},
		{x = 4, y = 9.0, z = 16},
		{x = 10, y = 8.8, z = 18},
		{x = 16, y = 8.6, z = 16},
		{x = 18, y = 8.5, z = 10},
		-- Twist through trees
		{x = 16, y = 8.5, z = 4},
		{x = 12, y = 8.4, z = 0},
		{x = 8, y = 8.3, z = -4},
		{x = 4, y = 8.2, z = -8},
		{x = -2, y = 8.2, z = -10},
		{x = -8, y = 8.3, z = -8},
		{x = -12, y = 8.5, z = -2},
		-- Splash pool approach
		{x = -14, y = 8.2, z = 4},
		{x = -12, y = 7.5, z = 10},
		{x = -8, y = 7.2, z = 14},
		{x = -2, y = 7.2, z = 16},
		-- Lazy river back toward dock
		{x = 4, y = 7.5, z = 14},
		{x = 8, y = 8.0, z = 10},
		{x = 6, y = 8.5, z = 5},
		{x = 2, y = 9.0, z = 2},
		{x = 0, y = 9.2, z = 0},
	}
	return densify(controls, 0.6)
end

local PATHS = {
	jungle_flume = build_jungle_flume(),
}

--------------------------------------------------------------------
-- Log boat entity
--------------------------------------------------------------------

-- Slightly slower than the coaster; "faster" on drops via pitch boost optional
local BOAT_SPEED = 5.5

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

core.register_entity("log_ride:log_boat", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		collisionbox = {-0.55, -0.25, -0.9, 0.55, 0.55, 0.9},
		selectionbox = {-0.55, -0.25, -0.9, 0.55, 0.55, 0.9},
		visual = "cube",
		visual_size = {x = 1.0, y = 0.5, z = 1.6},
		textures = {
			"lr_log.png",
			"lr_log.png",
			"lr_log_end.png",
			"lr_log_end.png",
			"lr_log.png",
			"lr_log.png",
		},
		static_save = true,
	},

	_path_name = "jungle_flume",
	_index = 1,
	_progress = 0,
	_rider = nil,
	_bob = 0,

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
			clicker:set_pos({x = pos.x + 1.4, y = pos.y + 0.6, z = pos.z})
			if self._rider == name then
				self._rider = nil
			end
			core.chat_send_player(name, "You hopped off the log.")
			return
		end
		if self._rider and self._rider ~= name then
			core.chat_send_player(name, "That log is full.")
			return
		end
		clicker:set_attach(self.object, "", {x = 0, y = 3, z = 0}, {x = 0, y = 0, z = 0})
		clicker:set_eye_offset({x = 0, y = -2, z = 0}, {x = 0, y = -2, z = 0})
		self._rider = name
		core.chat_send_player(name, "Hold on! Right-click again to get off.")
	end,

	on_step = function(self, dtime, _moveresult)
		local path = PATHS[self._path_name]
		if not path or #path < 2 then
			return
		end

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
		local dir = vector.direction(a, b)
		-- Speed up on drops, slow on climbs
		local speed = BOAT_SPEED
		if dir.y < -0.15 then
			speed = BOAT_SPEED * 1.7
		elseif dir.y > 0.15 then
			speed = BOAT_SPEED * 0.55
		end

		local seg_len = math.max(0.05, vector.distance(a, b))
		self._progress = self._progress + (speed * dtime) / seg_len

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
			dir = vector.direction(a, b)
		end

		local t = self._progress
		self._bob = (self._bob or 0) + dtime * 3.2
		local bob = math.sin(self._bob) * 0.08
		local pos = {
			x = a.x + (b.x - a.x) * t,
			-- Sit slightly above water surface and bob
			y = a.y + (b.y - a.y) * t + 0.35 + bob,
			z = a.z + (b.z - a.z) * t,
		}
		if vector.length(dir) < 1e-4 then
			dir = {x = 0, y = 0, z = 1}
		end
		-- Gentle roll while floating
		local roll = math.sin(self._bob * 0.7) * 0.06
		self.object:set_pos(pos)
		self.object:set_rotation({
			x = pitch_from_dir(dir) * 0.85,
			y = yaw_from_dir(dir),
			z = roll,
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
		puncher:get_inventory():add_item("main", "log_ride:log_boat_item")
	end,
})

core.register_craftitem("log_ride:log_boat_item", {
	description = "Log Boat",
	inventory_image = "lr_log.png",
	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return itemstack
		end
		local pos = vector.offset(pointed_thing.above, 0, 0.2, 0)
		local obj = core.add_entity(pos, "log_ride:log_boat")
		if obj then
			local ent = obj:get_luaentity()
			if ent then
				local path = PATHS.jungle_flume
				local best_i, best_d = 1, math.huge
				for i, p in ipairs(path) do
					local d = vector.distance(pos, p)
					if d < best_d then
						best_d = d
						best_i = i
					end
				end
				if best_d < 10 then
					ent:set_path("jungle_flume", best_i)
				else
					ent:set_path("jungle_flume", 1)
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
-- Mapgen
--------------------------------------------------------------------

local GROUND_Y = 7
local WATER_Y = 6
local GEN_MIN = {x = -28, y = 0, z = -18}
local GEN_MAX = {x = 28, y = 26, z = 28}

local function overlaps(minp, maxp)
	return not (maxp.x < GEN_MIN.x or minp.x > GEN_MAX.x
		or maxp.y < GEN_MIN.y or minp.y > GEN_MAX.y
		or maxp.z < GEN_MIN.z or minp.z > GEN_MAX.z)
end

local function facedir_from_dir(dx, dz)
	if math.abs(dx) > math.abs(dz) then
		return dx >= 0 and 1 or 3
	end
	return dz >= 0 and 0 or 2
end

local FLUME_CELLS = {}
do
	local path = PATHS.jungle_flume
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
			if math.abs(dy) > 0.3 then
				kind = "ramp"
			elseif i > 2 then
				local prev = path[i - 1]
				local d1x, d1z = p.x - prev.x, p.z - prev.z
				local d2x, d2z = n.x - p.x, n.z - p.z
				local cross = d1x * d2z - d1z * d2x
				if math.abs(cross) > 0.2 then
					kind = "curve"
				end
			end
			FLUME_CELLS[#FLUME_CELLS + 1] = {
				x = gx, y = gy, z = gz,
				kind = kind,
				param2 = facedir_from_dir(dx, dz),
			}
		end
	end
end

-- Splash pool center
local POOL_C = {x = -8, z = 12}
local POOL_R = 5

core.register_on_generated(function(minp, maxp, _seed)
	if not overlaps(minp, maxp) then
		return
	end

	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()

	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("log_ride:stone")
	local c_dirt = core.get_content_id("log_ride:dirt")
	local c_grass = core.get_content_id("log_ride:dirt_with_grass")
	local c_sand = core.get_content_id("log_ride:sand")
	local c_water = core.get_content_id("log_ride:water")
	local c_tree = core.get_content_id("log_ride:tree")
	local c_leaves = core.get_content_id("log_ride:leaves")
	local c_dock = core.get_content_id("log_ride:dock")
	local c_support = core.get_content_id("log_ride:support")
	local c_splash = core.get_content_id("log_ride:splash")
	local c_floor = core.get_content_id("log_ride:flume_floor")
	local c_wall = core.get_content_id("log_ride:flume_wall")
	local c_channel = core.get_content_id("log_ride:channel_water")
	local c_station = core.get_content_id("log_ride:station")

	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local in_park = x >= GEN_MIN.x and x <= GEN_MAX.x
				and z >= GEN_MIN.z and z <= GEN_MAX.z
			local pdx = x - POOL_C.x
			local pdz = z - POOL_C.z
			local in_pool = (pdx * pdx + pdz * pdz) <= (POOL_R * POOL_R)
			for y = minp.y, maxp.y do
				local vi = area:index(x, y, z)
				if in_park then
					if in_pool then
						-- Deeper splash pool so water is obvious
						if y < GROUND_Y - 3 then
							data[vi] = c_stone
						elseif y < GROUND_Y - 2 then
							data[vi] = c_sand
						elseif y <= GROUND_Y + 1 then
							data[vi] = c_water
						else
							data[vi] = c_air
						end
					else
						if y < GROUND_Y - 2 then
							data[vi] = c_stone
						elseif y < GROUND_Y then
							data[vi] = c_dirt
						elseif y == GROUND_Y then
							data[vi] = c_grass
						else
							data[vi] = c_air
						end
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
		end
	end

	-- Simple jungle trees (deterministic pseudo-random from position)
	local function hash2(x, z)
		return (x * 73856093 + z * 19349663) % 1000
	end

	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			if x >= GEN_MIN.x and x <= GEN_MAX.x
				and z >= GEN_MIN.z and z <= GEN_MAX.z then
				local h = hash2(x, z)
				local pdx = x - POOL_C.x
				local pdz = z - POOL_C.z
				local in_pool = (pdx * pdx + pdz * pdz) <= ((POOL_R + 2) * (POOL_R + 2))
				local near_dock = math.abs(x) <= 4 and math.abs(z) <= 4
				if h < 18 and not in_pool and not near_dock then
					local trunk_h = 4 + (h % 3)
					for ty = GROUND_Y + 1, GROUND_Y + trunk_h do
						if ty >= minp.y and ty <= maxp.y then
							data[area:index(x, ty, z)] = c_tree
						end
					end
					local top = GROUND_Y + trunk_h
					for ly = top - 1, top + 2 do
						for lx = x - 2, x + 2 do
							for lz = z - 2, z + 2 do
								if lx >= minp.x and lx <= maxp.x
									and ly >= minp.y and ly <= maxp.y
									and lz >= minp.z and lz <= maxp.z then
									local dx = lx - x
									local dy = ly - top
									local dz = lz - z
									if dx * dx + dy * dy + dz * dz <= 6 then
										local vi = area:index(lx, ly, lz)
										if data[vi] == c_air then
											data[vi] = c_leaves
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Boarding dock
	for z = -2, 3 do
		for x = -3, 3 do
			local y = GROUND_Y
			if x >= minp.x and x <= maxp.x
				and y >= minp.y and y <= maxp.y
				and z >= minp.z and z <= maxp.z then
				data[area:index(x, y, z)] = c_dock
			end
			if math.abs(x) == 3 or z == -2 then
				local wy = GROUND_Y + 1
				if x >= minp.x and x <= maxp.x
					and wy >= minp.y and wy <= maxp.y
					and z >= minp.z and z <= maxp.z
					and not (z == 3) then
					-- low railing posts
					if (x + z) % 2 == 0 then
						data[area:index(x, wy, z)] = c_support
					end
				end
			end
		end
	end

	if 0 >= minp.x and 0 <= maxp.x
		and (GROUND_Y + 1) >= minp.y and (GROUND_Y + 1) <= maxp.y
		and (-1) >= minp.z and (-1) <= maxp.z then
		data[area:index(0, GROUND_Y + 1, -1)] = c_station
	end

	-- Splash pads around pool edge
	for z = POOL_C.z - POOL_R - 1, POOL_C.z + POOL_R + 1 do
		for x = POOL_C.x - POOL_R - 1, POOL_C.x + POOL_R + 1 do
			local pdx = x - POOL_C.x
			local pdz = z - POOL_C.z
			local r2 = pdx * pdx + pdz * pdz
			if r2 >= (POOL_R * POOL_R) and r2 <= (POOL_R + 1) * (POOL_R + 1) then
				local y = GROUND_Y + 1
				if x >= minp.x and x <= maxp.x
					and y >= minp.y and y <= maxp.y
					and z >= minp.z and z <= maxp.z then
					data[area:index(x, y, z)] = c_splash
				end
			end
		end
	end

	-- Flume: wooden floor + side walls + real channel water on top
	-- Wall offsets relative to travel facedir (perpendicular)
	local function wall_offsets(param2)
		if param2 == 0 or param2 == 2 then
			return {{-1, 0}, {1, 0}} -- travel along Z → walls on ±X
		end
		return {{0, -1}, {0, 1}} -- travel along X → walls on ±Z
	end

	for _, cell in ipairs(FLUME_CELLS) do
		local x, y, z = cell.x, cell.y, cell.z
		local p2 = cell.param2

		-- Clear air above the channel so the boat can pass
		for dy = 0, 2 do
			local ay = y + dy
			if x >= minp.x and x <= maxp.x
				and ay >= minp.y and ay <= maxp.y
				and z >= minp.z and z <= maxp.z then
				data[area:index(x, ay, z)] = c_air
			end
		end

		-- Floor under the water line
		local fy = y
		if x >= minp.x and x <= maxp.x
			and fy >= minp.y and fy <= maxp.y
			and z >= minp.z and z <= maxp.z then
			local vi = area:index(x, fy, z)
			data[vi] = c_floor
			param2_data[vi] = p2
		end

		-- Real water sitting in the trough (boat floats here)
		local wy = y + 1
		if x >= minp.x and x <= maxp.x
			and wy >= minp.y and wy <= maxp.y
			and z >= minp.z and z <= maxp.z then
			data[area:index(x, wy, z)] = c_channel
		end

		-- Side walls
		for _, off in ipairs(wall_offsets(p2)) do
			local wx, wz = x + off[1], z + off[2]
			for dy = 0, 1 do
				local wy2 = y + dy
				if wx >= minp.x and wx <= maxp.x
					and wy2 >= minp.y and wy2 <= maxp.y
					and wz >= minp.z and wz <= maxp.z then
					local vi = area:index(wx, wy2, wz)
					data[vi] = c_wall
					param2_data[vi] = p2
				end
			end
		end

		-- Supports under elevated sections
		if y > GROUND_Y + 1 then
			for sy = y - 1, GROUND_Y + 1, -1 do
				if x >= minp.x and x <= maxp.x
					and sy >= minp.y and sy <= maxp.y
					and z >= minp.z and z <= maxp.z
					and (x + z + y) % 2 == 0 then
					local vi = area:index(x, sy, z)
					if data[vi] == c_air then
						data[vi] = c_support
					end
				end
			end
		end
	end

	-- Widen pool a bit more and ensure water surface is continuous at exit
	for z = POOL_C.z - POOL_R, POOL_C.z + POOL_R do
		for x = POOL_C.x - POOL_R, POOL_C.x + POOL_R do
			local pdx = x - POOL_C.x
			local pdz = z - POOL_C.z
			if pdx * pdx + pdz * pdz <= POOL_R * POOL_R then
				for y = GROUND_Y - 1, GROUND_Y + 1 do
					if x >= minp.x and x <= maxp.x
						and y >= minp.y and y <= maxp.y
						and z >= minp.z and z <= maxp.z then
						data[area:index(x, y, z)] = c_water
					end
				end
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

local SPAWN = {x = 0, y = GROUND_Y + 2, z = -4}

core.settings:set("static_spawnpoint",
	SPAWN.x .. "," .. SPAWN.y .. "," .. SPAWN.z)
if core.set_mapgen_setting then
	core.set_mapgen_setting("mg_name", "singlenode", true)
end

local starter_items = {
	"log_ride:log_boat_item 2",
	"log_ride:flume_straight 48",
	"log_ride:flume_curve 24",
	"log_ride:flume_ramp 24",
	"log_ride:flume_floor 48",
	"log_ride:flume_wall 48",
	"log_ride:channel_water 64",
	"log_ride:support 48",
	"log_ride:dock 24",
	"log_ride:splash 16",
	"log_ride:station 1",
	"log_ride:tree 16",
	"log_ride:leaves 32",
}

core.register_on_newplayer(function(player)
	player:set_pos(SPAWN)
	local inv = player:get_inventory()
	for _, stack in ipairs(starter_items) do
		inv:add_item("main", stack)
	end
	core.chat_send_player(player:get_player_name(),
		"Welcome to the Log Ride! Right-click the station block on the dock "
		.. "to spawn a log boat, then right-click the boat to ride the flume. "
		.. "Build your own channels with flume segments.")
end)

core.register_on_joinplayer(function(player)
	core.after(2, function()
		if not player or not player:is_player() then
			return
		end
		local p = {x = 0, y = 10.0, z = 2}
		local objs = core.get_objects_inside_radius(p, 50)
		for _, obj in ipairs(objs) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "log_ride:log_boat" then
				return
			end
		end
		local obj = core.add_entity(p, "log_ride:log_boat")
		if obj then
			local ent = obj:get_luaentity()
			if ent then
				ent:set_path("jungle_flume", 1)
			end
		end
	end)
end)

-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The themed map pack: the props the authored maps need, the registry that
-- says where each map is and how it should feel, and the `/maps` helper.
--
-- This mod owns *what a map is*. `lw_world/maps.lua` owns *where it goes* —
-- it reads the registry below and stamps each schematic onto its island in
-- the atlas, next to the plaza. Splitting it that way keeps the world file a
-- build order and keeps the per-map facts (footprint, spawn, time of day) in
-- one place that a menu or a test can read.
--
-- Node budget: every prop here is one the lw_nodes palette genuinely cannot
-- fake. The fruit garden adds no nodes at all — every giant fruit on it is
-- dyed wool — and the ones that do land are listed in docs/maps.md. Most of
-- the second three maps' props are existing tiles under `[multiply`.
--
-- These are deliberately *not* in the lw_palette group: that group builds the
-- material library's pedestals, which are full. They still show up in the
-- palette inventory (`i`), which is built from every described item.

lw_maps = {}

local function register(name, def)
	if def.is_ground_content == nil then
		def.is_ground_content = false
	end
	core.register_node("lw_maps:" .. name, def)
end

--------------------------------------------------------------------------
-- Halloween props
--------------------------------------------------------------------------

register("pumpkin", {
	description = "Pumpkin",
	tiles = {"lw_pumpkin_top.png", "lw_pumpkin_top.png", "lw_pumpkin_side.png"},
	groups = {crumbly = 2, choppy = 2, oddly_breakable_by_hand = 2},
})

-- Tile order is +Y, -Y, +X, -X, +Z, -Z, so the carved face goes on index 6 and
-- looks south at facedir 0 — the same convention lw_nodes:poster uses.
register("jack_o_lantern", {
	description = "Jack-o'-Lantern",
	tiles = {
		"lw_pumpkin_top.png", "lw_pumpkin_top.png",
		"lw_pumpkin_side.png", "lw_pumpkin_side.png",
		"lw_pumpkin_side.png", "lw_jack_face.png",
	},
	paramtype2 = "facedir",
	on_place = core.rotate_node,
	light_source = 13,
	groups = {crumbly = 2, choppy = 2, oddly_breakable_by_hand = 2},
})

register("hay", {
	description = "Hay Bale",
	tiles = {"lw_hay.png"},
	groups = {snappy = 2, oddly_breakable_by_hand = 2, flammable = 0},
})

-- plantlike is two crossed quads: cheap in GLES2 and exactly the shape a web
-- wants. Walkable would turn every decorated corner into a trap.
register("cobweb", {
	description = "Cobweb",
	drawtype = "plantlike",
	tiles = {"lw_cobweb.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = false,
	visual_scale = 1.1,
	groups = {snappy = 3, oddly_breakable_by_hand = 3},
})

register("bone", {
	description = "Bone-White Stone",
	tiles = {"lw_stone.png^[multiply:#ded8c4"},
	groups = {cracky = 2},
})

register("dead_wood", {
	description = "Dead Wood",
	tiles = {
		"lw_beam_end.png^[multiply:#9a938a",
		"lw_beam_end.png^[multiply:#9a938a",
		"lw_dead_wood.png",
	},
	paramtype2 = "facedir",
	on_place = core.rotate_node,
	groups = {choppy = 2},
})

--------------------------------------------------------------------------
-- Snow and ice
--------------------------------------------------------------------------

register("snow", {
	description = "Snow Block",
	tiles = {"lw_snow.png"},
	groups = {crumbly = 3},
	is_ground_content = true,
})

register("packed_snow", {
	description = "Packed Snow",
	tiles = {"lw_snow.png^[multiply:#dbe6f2"},
	groups = {crumbly = 2},
})

register("slab_packed_snow", {
	description = "Packed Snow Slab",
	drawtype = "nodebox",
	tiles = {"lw_snow.png^[multiply:#dbe6f2"},
	paramtype = "light",
	node_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.0, 0.5}},
	groups = {crumbly = 2},
})

register("stair_packed_snow", {
	description = "Packed Snow Stair",
	drawtype = "nodebox",
	tiles = {"lw_snow.png^[multiply:#dbe6f2"},
	paramtype = "light",
	paramtype2 = "facedir",
	on_place = core.rotate_node,
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, 0.0, 0.5},
			{-0.5, 0.0, 0.0, 0.5, 0.5, 0.5},
		},
	},
	groups = {crumbly = 2},
})

register("ice", {
	description = "Ice",
	drawtype = "glasslike",
	tiles = {"lw_glass.png^[multiply:#9fd8f0"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	groups = {cracky = 3},
})

register("packed_ice", {
	description = "Packed Ice",
	tiles = {"lw_snow.png^[multiply:#8fc3e6"},
	groups = {cracky = 2},
})

-- A dim point light. lw_nodes:lamp is 14 and floodlights a cave; a cave that
-- reads as a cave needs pools of light with dark between them.
register("torch", {
	description = "Torch",
	drawtype = "plantlike",
	tiles = {"lw_torch.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = false,
	light_source = 12,
	groups = {dig_immediate = 3},
})

--------------------------------------------------------------------------
-- Foliage
--------------------------------------------------------------------------

-- One greyscale weave, tinted per node, exactly like the sixteen wool cubes.
local function register_leaves(name, description, hex)
	register(name, {
		description = description,
		drawtype = "allfaces_optional",
		tiles = {"lw_leaves.png^[multiply:" .. hex},
		use_texture_alpha = "clip",
		paramtype = "light",
		groups = {snappy = 3, oddly_breakable_by_hand = 3, flammable = 0},
	})
end

register_leaves("leaves", "Oversized Leaves", "#4f9a3a")
register_leaves("pine_leaves", "Pine Needles", "#2e6b3a")

register("vine", {
	description = "Vine",
	drawtype = "nodebox",
	tiles = {"lw_vine.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = false,
	on_place = core.rotate_node,
	node_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, -0.4375}},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, -0.4375}},
	groups = {snappy = 3, oddly_breakable_by_hand = 3},
})

-- The juice "river". Translucent and not walkable, so it reads as liquid
-- without paying for a real liquid's flow simulation on the WASM worker.
local function register_juice(name, description, hex)
	register(name, {
		description = description,
		drawtype = "glasslike",
		tiles = {"lw_glass.png^[multiply:" .. hex},
		use_texture_alpha = "blend",
		paramtype = "light",
		sunlight_propagates = true,
		walkable = false,
		buildable_to = false,
		groups = {cracky = 3},
	})
end

register_juice("juice_red", "Watermelon Juice", "#d0323a")
register_juice("juice_green", "Lime Juice", "#5aa83c")

--------------------------------------------------------------------------
-- Lighthouse, bazaar and caldera props
--------------------------------------------------------------------------

-- Wet rock for the headland: the core stone, cooled blue-grey.
register("sea_rock", {
	description = "Sea Rock",
	tiles = {"lw_stone.png^[multiply:#6a7684"},
	groups = {cracky = 2},
})

-- The lamp-room window the beacon is currently shining through. A solid,
-- walkable glass so it can stand in the wall; the beacon controller swaps it
-- round the four faces.
register("beam", {
	description = "Lighthouse Beam",
	drawtype = "glasslike",
	tiles = {"lw_glass.png^[multiply:#ffe08a"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 14,
	groups = {cracky = 3},
})

register("mudbrick", {
	description = "Mudbrick",
	tiles = {"lw_stone_brick.png^[multiply:#d0ad7c"},
	groups = {cracky = 2},
})

-- One faceted greyscale tile, tinted per colour, like the wool cubes. Solid,
-- so a crystal is something a stall can sell and a floor can grow.
local CRYSTALS = {
	{name = "violet", desc = "Violet", hex = "#b48cff"},
	{name = "cyan", desc = "Cyan", hex = "#7fe6ff"},
	{name = "rose", desc = "Rose", hex = "#ff9ad5"},
	{name = "amber", desc = "Amber", hex = "#ffcf70"},
}
for _, tint in ipairs(CRYSTALS) do
	register("crystal_" .. tint.name, {
		description = tint.desc .. " Crystal",
		drawtype = "glasslike",
		tiles = {"lw_crystal.png^[multiply:" .. tint.hex},
		use_texture_alpha = "blend",
		paramtype = "light",
		sunlight_propagates = true,
		light_source = 10,
		groups = {cracky = 3},
	})
end

register("basalt", {
	description = "Basalt",
	tiles = {"lw_stone.png^[multiply:#4a464c"},
	groups = {cracky = 2},
})

register("ash", {
	description = "Volcanic Ash",
	tiles = {"lw_sand.png^[multiply:#8f8a86"},
	groups = {crumbly = 3},
	is_ground_content = true,
})

-- Lava the way the garden does juice: translucent, lit and not walkable, so
-- a lake reads as a lake with no liquid simulation and no damage. There is
-- no combat on the showcase and this is not the place to start.
register("lava", {
	description = "Lava",
	drawtype = "glasslike",
	tiles = {"lw_glass.png^[multiply:#ff6a1a"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = false,
	light_source = 14,
	post_effect_color = {a = 96, r = 255, g = 96, b = 16},
	groups = {cracky = 3},
})

-- A puff. Translucent cube rather than a particle spawner: particles are
-- exactly the kind of per-frame work the application worker cannot spare.
register("smoke", {
	description = "Smoke",
	drawtype = "glasslike",
	tiles = {"lw_smoke.png"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	buildable_to = true,
	groups = {dig_immediate = 3, not_in_creative_inventory = 1},
})

--------------------------------------------------------------------------
-- The beacon and the vent
--------------------------------------------------------------------------

-- Both are airlike node-timer controllers in the flicker's mould: they only
-- run while their block is loaded, and they only ever swap between the two
-- states they own, so a visitor's edit next to them is left alone.
local function register_controller(name, description, interval, on_timer)
	core.register_node("lw_maps:" .. name, {
		description = description,
		drawtype = "airlike",
		paramtype = "light",
		sunlight_propagates = true,
		walkable = false,
		pointable = false,
		diggable = false,
		buildable_to = false,
		groups = {not_in_creative_inventory = 1},
		on_construct = function(pos)
			core.get_node_timer(pos):start(interval)
		end,
		on_timer = on_timer,
	})
end

local function swap_between(at, target, a, b)
	local node = core.get_node(at)
	if node.name ~= target and (node.name == a or node.name == b) then
		core.swap_node(at, {name = target, param2 = node.param2})
	end
end

-- The beacon sits above the lamp; the four windows it sweeps are one node
-- down and three out, on the middle of each face of the lamp room.
local BEACON_WINDOWS = {
	{x = 3, y = -1, z = 0}, {x = 0, y = -1, z = -3},
	{x = -3, y = -1, z = 0}, {x = 0, y = -1, z = 3},
}

register_controller("beacon", "Lighthouse Beacon Controller", 0.6, function(pos)
	local meta = core.get_meta(pos)
	local step = (meta:get_int("step") + 1) % #BEACON_WINDOWS
	meta:set_int("step", step)
	for index, offset in ipairs(BEACON_WINDOWS) do
		local target = (index - 1 == step) and "lw_maps:beam" or "lw_nodes:glass"
		swap_between(vector.add(pos, offset), target, "lw_maps:beam", "lw_nodes:glass")
	end
	return true
end)

-- The vent drives the six cells above it: a puff every third node, rising.
local VENT_HEIGHT = 6

register_controller("vent", "Smoke Vent Controller", 0.5, function(pos)
	local meta = core.get_meta(pos)
	local step = (meta:get_int("step") + 1) % 3
	meta:set_int("step", step)
	for height = 1, VENT_HEIGHT do
		local target = ((height - step) % 3 == 0) and "lw_maps:smoke" or "air"
		swap_between({x = pos.x, y = pos.y + height, z = pos.z}, target,
			"lw_maps:smoke", "air")
	end
	return true
end)

--------------------------------------------------------------------------
-- Flickering lanterns
--------------------------------------------------------------------------

-- An airlike controller that guts the lantern one node below it. A node timer
-- runs only while the block is loaded, unlike an ABM, which is what keeps a
-- map nobody is standing on from costing anything (see the same argument in
-- lw_world's kinetic courtyard).
--
-- The pattern is a fixed string rather than a random roll so a reload does not
-- resynchronise every lantern on the lane into one big blink.
local FLICKER_PATTERN = "1110110111101110110011111011"
local FLICKER_INTERVAL = 0.45

core.register_node("lw_maps:flicker", {
	description = "Lantern Flicker Controller",
	drawtype = "airlike",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	groups = {not_in_creative_inventory = 1},
	on_construct = function(pos)
		-- Offset the phase by position so neighbouring lanterns gutter out of
		-- step with each other.
		core.get_meta(pos):set_int("step", (pos.x * 5 + pos.z * 3) % #FLICKER_PATTERN)
		core.get_node_timer(pos):start(FLICKER_INTERVAL)
	end,
	on_timer = function(pos)
		local meta = core.get_meta(pos)
		local step = (meta:get_int("step") + 1) % #FLICKER_PATTERN
		meta:set_int("step", step)
		local lit = FLICKER_PATTERN:sub(step + 1, step + 1) == "1"
		local target = lit and "lw_maps:jack_o_lantern" or "lw_maps:pumpkin"
		local at = {x = pos.x, y = pos.y - 1, z = pos.z}
		local node = core.get_node(at)
		-- Only ever swap between the two lantern states: if a visitor dug the
		-- lantern out, leave the hole alone instead of growing a pumpkin in it.
		if node.name ~= target
				and (node.name == "lw_maps:jack_o_lantern"
					or node.name == "lw_maps:pumpkin") then
			core.swap_node(at, {name = target, param2 = node.param2})
		end
		return true
	end,
})

--------------------------------------------------------------------------
-- The map registry
--------------------------------------------------------------------------

-- Local y 0 of every map schematic is stamped at this world height, so local
-- y 3 is the world's GROUND and local y 4 its FLOOR. Mirrors SURFACE/FLOOR in
-- util/content/generate_luanti_web_maps.py, which asserts the same numbers.
lw_maps.base_y = 5

lw_maps.maps = {}
lw_maps.by_id = {}

-- A map is: a committed schematic, an origin in the atlas, a spawn to send a
-- visitor to, and the atmosphere it should be seen in.
function lw_maps.register(def)
	assert(def.id and def.schem and def.origin and def.size and def.spawn,
		"lw_maps.register needs id, schem, origin, size and spawn")
	assert(not lw_maps.by_id[def.id], "lw_maps: duplicate map " .. def.id)
	def.min = vector.new(def.origin)
	def.max = vector.new(def.origin.x + def.size.x - 1,
		def.origin.y + def.size.y - 1, def.origin.z + def.size.z - 1)
	lw_maps.maps[#lw_maps.maps + 1] = def
	lw_maps.by_id[def.id] = def
	return def
end

function lw_maps.at(pos)
	for _, map in ipairs(lw_maps.maps) do
		-- Generous on y: a visitor flying over the mountain is still "on" it.
		if pos.x >= map.min.x and pos.x <= map.max.x
				and pos.z >= map.min.z and pos.z <= map.max.z
				and pos.y >= map.min.y - 4 and pos.y <= map.max.y + 24 then
			return map
		end
	end
	return nil
end

local BASE = lw_maps.base_y

lw_maps.register({
	id = "halloween",
	title = "Halloween lane",
	blurb = "Dusk lane of carved lanterns, a graveyard, a haunted house with " ..
		"a cellar and an attic, and a porch stage at the end.",
	schem = "map_halloween",
	size = {x = 36, y = 16, z = 36},
	origin = {x = -88, y = BASE, z = -26},
	spawn = {x = -55, y = BASE + 4, z = -9},
	-- Dusk, per player, so the hub's frozen midday is untouched. An honest
	-- view distance is part of the look: fog is the point, not a limitation.
	day_night_ratio = 0.16,
	sky = {
		type = "regular",
		clouds = true,
		sky_color = {
			day_sky = "#241a2e", day_horizon = "#4a2a22",
			dawn_sky = "#241a2e", dawn_horizon = "#4a2a22",
			night_sky = "#140f1c", night_horizon = "#2a1a18",
			indoors = "#1a1420",
			fog_sun_tint = "#c86a28", fog_moon_tint = "#5a4a78",
			fog_tint_type = "custom",
		},
		fog = {fog_distance = 72, fog_start = 0.35},
	},
	-- The kinetic beat: a vane that spins on the house ridge.
	vane = {x = -63, y = BASE + 19, z = 1},
})

lw_maps.register({
	id = "snow_mountain",
	title = "Snowy mountain",
	blurb = "A peak you can climb and also go through: switchback trail, ice " ..
		"cave, timbered mineshaft, and a tunnel out the far face.",
	schem = "map_snow_mountain",
	size = {x = 40, y = 28, z = 40},
	origin = {x = -20, y = BASE, z = -74},
	spawn = {x = 6, y = BASE + 4, z = -37},
	day_night_ratio = 0.85,
	sky = {
		type = "regular",
		clouds = true,
		sky_color = {
			day_sky = "#9fb8cf", day_horizon = "#cfdce8",
			dawn_sky = "#9fb8cf", dawn_horizon = "#cfdce8",
			night_sky = "#2a3a4a", night_horizon = "#3a4a5a",
			indoors = "#6a7a8a",
			fog_sun_tint = "#dfe8f2", fog_moon_tint = "#b0c0d0",
			fog_tint_type = "custom",
		},
		fog = {fog_distance = 110, fog_start = 0.5},
	},
})

lw_maps.register({
	id = "fruit_garden",
	title = "Giant fruit garden",
	blurb = "Oversized produce as architecture: a walk-in watermelon, a " ..
		"sliced-melon amphitheatre, and a juice channel between them.",
	schem = "map_fruit_garden",
	size = {x = 40, y = 20, z = 40},
	origin = {x = 53, y = BASE, z = -28},
	spawn = {x = 55, y = BASE + 4, z = -7},
})

lw_maps.register({
	id = "lighthouse",
	title = "Lighthouse tide",
	blurb = "A square lighthouse on a headland: spiral stair to a sweeping " ..
		"beacon, a gallery round the lamp, a keeper's cottage, a jetty and a " ..
		"sea cave under the rock.",
	schem = "map_lighthouse",
	size = {x = 36, y = 24, z = 36},
	origin = {x = -84, y = BASE, z = -63},
	spawn = {x = -51, y = BASE + 4, z = -30},
	-- Late afternoon on the water: warm, low, with a sea haze the beam has
	-- something to sweep through.
	day_night_ratio = 0.42,
	sky = {
		type = "regular",
		clouds = true,
		sky_color = {
			day_sky = "#5a6f8e", day_horizon = "#d9a26a",
			dawn_sky = "#5a6f8e", dawn_horizon = "#d9a26a",
			night_sky = "#1c2436", night_horizon = "#3c2e30",
			indoors = "#3a3c48",
			fog_sun_tint = "#f0b070", fog_moon_tint = "#9aa6c0",
			fog_tint_type = "custom",
		},
		fog = {fog_distance = 90, fog_start = 0.4},
	},
})

lw_maps.register({
	id = "bazaar",
	title = "Crystal night bazaar",
	blurb = "A walled night market: striped stalls selling lit crystals, a " ..
		"mudbrick dome over the crossing, a rooftop walk, and a crystal " ..
		"grotto under the stalls.",
	schem = "map_bazaar",
	size = {x = 36, y = 20, z = 36},
	origin = {x = 49, y = BASE, z = 20},
	spawn = {x = 50, y = BASE + 4, z = 21},
	-- Night. The crystals and lanterns are the light; the sky is there to
	-- be dark behind them.
	day_night_ratio = 0.1,
	sky = {
		type = "regular",
		clouds = false,
		sky_color = {
			day_sky = "#0e1230", day_horizon = "#2a1e4a",
			dawn_sky = "#0e1230", dawn_horizon = "#2a1e4a",
			night_sky = "#080a1c", night_horizon = "#1a1230",
			indoors = "#141024",
			fog_sun_tint = "#5a3e8a", fog_moon_tint = "#8a7ac0",
			fog_tint_type = "custom",
		},
		fog = {fog_distance = 80, fog_start = 0.45},
	},
})

lw_maps.register({
	id = "caldera",
	title = "Volcanic smoke caldera",
	blurb = "A cinder cone you climb and go under: a spiral trail to the " ..
		"crater rim, a lava lake, a lava tube into a magma chamber, and a " ..
		"timbered stair back out to the trail.",
	schem = "map_caldera",
	size = {x = 36, y = 24, z = 36},
	origin = {x = -84, y = BASE, z = 20},
	spawn = {x = -50, y = BASE + 4, z = 21},
	-- Ash haze: bright enough to climb by, orange at the edges, and short.
	day_night_ratio = 0.55,
	sky = {
		type = "regular",
		clouds = true,
		sky_color = {
			day_sky = "#6e5a4c", day_horizon = "#b8784a",
			dawn_sky = "#6e5a4c", dawn_horizon = "#b8784a",
			night_sky = "#2a1c18", night_horizon = "#4a2a1c",
			indoors = "#3a2c28",
			fog_sun_tint = "#e08a4a", fog_moon_tint = "#6a4a3a",
			fog_tint_type = "custom",
		},
		fog = {fog_distance = 64, fog_start = 0.3},
	},
})

--------------------------------------------------------------------------
-- Per-player atmosphere
--------------------------------------------------------------------------

-- Time of day is a property of the world, and the hub's clock is frozen at
-- midday on purpose (lw_world). Overriding the day/night ratio and the sky
-- per player is what lets one world hold a dusk lane and a bright garden at
-- the same time, and it costs nothing when nobody is on a map.
local current = {}

local function apply(player, map)
	local name = player:get_player_name()
	if current[name] == (map and map.id or nil) then
		return
	end
	current[name] = map and map.id or nil
	if map and map.sky then
		player:set_sky(map.sky)
	else
		player:set_sky({})
	end
	player:override_day_night_ratio(map and map.day_night_ratio or nil)
end

local ATMOSPHERE_INTERVAL = 0.5
local elapsed = 0

core.register_globalstep(function(dtime)
	elapsed = elapsed + dtime
	if elapsed < ATMOSPHERE_INTERVAL then
		return
	end
	elapsed = 0
	for _, player in ipairs(core.get_connected_players()) do
		apply(player, lw_maps.at(player:get_pos()))
	end
end)

core.register_on_leaveplayer(function(player)
	current[player:get_player_name()] = nil
end)

--------------------------------------------------------------------------
-- The weather vane
--------------------------------------------------------------------------

core.register_entity("lw_maps:weather_vane", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		visual = "upright_sprite",
		visual_size = {x = 1.4, y = 1.4},
		textures = {"lw_jack_face.png", "lw_pumpkin_side.png"},
		-- Respawned on join, so it must not accumulate in the map file.
		static_save = false,
		infotext = "Weather vane",
	},
	age = 0,
	on_step = function(self, dtime)
		self.age = self.age + dtime
		self.object:set_yaw(self.age * 0.9)
	end,
})

local function ensure_vane(pos)
	for _, object in ipairs(core.get_objects_inside_radius(pos, 6)) do
		local entity = object:get_luaentity()
		if entity and entity.name == "lw_maps:weather_vane" then
			return
		end
	end
	core.add_entity(pos, "lw_maps:weather_vane")
end

core.register_on_joinplayer(function()
	core.after(3, function()
		for _, map in ipairs(lw_maps.maps) do
			if map.vane then
				ensure_vane(map.vane)
			end
		end
	end)
end)

--------------------------------------------------------------------------
-- /maps
--------------------------------------------------------------------------

function lw_maps.teleport(player, id)
	local map = lw_maps.by_id[id]
	if not map then
		return false
	end
	local spawn = vector.new(map.spawn)
	-- The islands are far enough from the hub that a visitor can arrive before
	-- the chunk does; emerging first is the difference between landing on the
	-- lane and falling through it.
	core.emerge_area(vector.offset(spawn, -16, -8, -16),
		vector.offset(spawn, 16, 16, 16))
	player:set_pos(spawn)
	return true
end

local function listing()
	local lines = {"Themed maps (walk the causeways from the plaza, or /maps <name>):"}
	for _, map in ipairs(lw_maps.maps) do
		lines[#lines + 1] = ("  %-14s %s"):format(map.id, map.title)
		lines[#lines + 1] = ("                 %s"):format(map.blurb)
	end
	return table.concat(lines, "\n")
end

core.register_chatcommand("maps", {
	params = "[" .. table.concat((function()
		local ids = {}
		for _, map in ipairs(lw_maps.maps) do
			ids[#ids + 1] = map.id
		end
		return ids
	end)(), "|") .. "]",
	description = "List the themed maps, or travel to one",
	func = function(name, param)
		param = param:trim()
		if param == "" then
			return true, listing()
		end
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You have to be in the world to travel."
		end
		if not lw_maps.teleport(player, param) then
			return false, "No map called " .. param .. ".\n" .. listing()
		end
		local map = lw_maps.by_id[param]
		return true, map.title .. " — " .. map.blurb
	end,
})

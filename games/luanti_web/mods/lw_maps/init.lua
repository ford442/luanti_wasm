-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The themed map pack: the props the three authored maps need, the registry
-- that says where each map is and how it should feel, and the `/maps` helper.
--
-- This mod owns *what a map is*. `lw_world/maps.lua` owns *where it goes* —
-- it reads the registry below and stamps each schematic onto its island in
-- the atlas, next to the plaza. Splitting it that way keeps the world file a
-- build order and keeps the per-map facts (footprint, spawn, time of day) in
-- one place that a menu or a test can read.
--
-- Node budget: every prop here is one the lw_nodes palette genuinely cannot
-- fake. The fruit garden adds no nodes at all — every giant fruit on it is
-- dyed wool — and the ones that do land are listed in docs/maps.md.
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
-- Lamp controllers
--------------------------------------------------------------------------

-- Airlike controllers that switch the node one below them between a lit and
-- an unlit twin. A node timer runs only while the block is loaded, unlike an
-- ABM, which is what keeps a map nobody is standing on from costing anything
-- (see the same argument in lw_world's kinetic courtyard).
--
-- The pairs are data: a map that wants a new kind of lamp to gutter or chase
-- registers its two nodes here and reuses both controllers unchanged.
lw_maps.lamp_pairs = {}
local lit_of, unlit_of = {}, {}

function lw_maps.register_lamp_pair(lit, unlit)
	lw_maps.lamp_pairs[#lw_maps.lamp_pairs + 1] = {lit = lit, unlit = unlit}
	lit_of[lit], lit_of[unlit] = lit, lit
	unlit_of[lit], unlit_of[unlit] = unlit, unlit
end

lw_maps.register_lamp_pair("lw_maps:jack_o_lantern", "lw_maps:pumpkin")

-- Light or dim whatever lamp is one node below `pos`. Only ever swaps a lamp
-- for its own twin: if a visitor dug the lamp out, or built something else in
-- its place, the controller leaves it alone instead of growing a lamp there.
local function set_lamp(pos, lit)
	local at = {x = pos.x, y = pos.y - 1, z = pos.z}
	local node = core.get_node(at)
	local target = lit and lit_of[node.name] or unlit_of[node.name]
	if target and target ~= node.name then
		core.swap_node(at, {name = target, param2 = node.param2})
	end
end
lw_maps.set_lamp = set_lamp

local function controller(name, description, def)
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
		on_construct = def.on_construct,
		on_timer = def.on_timer,
	})
end

-- Flicker: a fixed string rather than a random roll, so a reload does not
-- resynchronise every lantern on the lane into one big blink.
local FLICKER_PATTERN = "1110110111101110110011111011"
local FLICKER_INTERVAL = 0.45

controller("flicker", "Lantern Flicker Controller", {
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
		set_lamp(pos, FLICKER_PATTERN:sub(step + 1, step + 1) == "1")
		return true
	end,
})

-- Chase: lamps that light one after another round a loop, like the
-- courtyard's chase-light cornice, but with no wiring between them. Each
-- controller carries its place in the loop in param2 (the schematic keeps
-- it), and every one of them reads the same clock, so lamps in different map
-- blocks — whose timers were started at different moments — still agree on
-- whose turn it is.
lw_maps.CHASE_PERIOD = 8
lw_maps.CHASE_WIDTH = 2
local CHASE_INTERVAL = 0.5

function lw_maps.chase_lit(index, tick)
	return (tick - index) % lw_maps.CHASE_PERIOD < lw_maps.CHASE_WIDTH
end

local function chase_tick()
	return math.floor(core.get_us_time() / (CHASE_INTERVAL * 1000000))
end

controller("chase", "Lantern Chase Controller", {
	on_construct = function(pos)
		core.get_node_timer(pos):start(CHASE_INTERVAL)
	end,
	on_timer = function(pos)
		local index = core.get_node(pos).param2
		set_lamp(pos, lw_maps.chase_lit(index, chase_tick()))
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
-- visitor to, and the atmosphere it should be seen in. Only `id`, `size`,
-- `origin` and `spawn` are required; the schematic defaults to map_<id>.mts,
-- and a map with no `sky` or `day_night_ratio` is seen in the hub's midday.
--
-- `entities` are props that move and so cannot live in a schematic: each is
-- `{name = <entity>, at = <map-local position>}`, respawned near whoever
-- joins, and must be registered with `static_save = false` so they do not
-- pile up in the map file.
function lw_maps.register(def)
	assert(def.id and def.origin and def.size and def.spawn,
		"lw_maps.register needs id, origin, size and spawn")
	assert(not lw_maps.by_id[def.id], "lw_maps: duplicate map " .. def.id)
	def.schem = def.schem or ("map_" .. def.id)
	def.title = def.title or def.id
	def.blurb = def.blurb or ""
	def.min = vector.new(def.origin)
	def.max = vector.new(def.origin.x + def.size.x - 1,
		def.origin.y + def.size.y - 1, def.origin.z + def.size.z - 1)
	def.entities = def.entities or {}
	for _, entity in ipairs(def.entities) do
		entity.pos = lw_maps.to_world(def, entity.at)
	end
	lw_maps.maps[#lw_maps.maps + 1] = def
	lw_maps.by_id[def.id] = def
	return def
end

-- A map-local position (what util/content/generate_luanti_web_maps.py
-- thinks in) as a world position.
function lw_maps.to_world(map, at)
	return vector.new(map.origin.x + at.x, map.origin.y + at.y, map.origin.z + at.z)
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

-- A set_sky table from the handful of colours a map actually chooses. Dawn
-- follows day and the night colours default to the day ones, because the
-- ratio override pins each map at one time of day anyway.
function lw_maps.sky(def)
	local sky = {
		type = "regular",
		clouds = def.clouds ~= false,
		sky_color = {
			day_sky = def.sky, day_horizon = def.horizon,
			dawn_sky = def.sky, dawn_horizon = def.horizon,
			night_sky = def.night_sky or def.sky,
			night_horizon = def.night_horizon or def.horizon,
			indoors = def.indoors or def.night_sky or def.sky,
			fog_sun_tint = def.sun_tint, fog_moon_tint = def.moon_tint,
			fog_tint_type = "custom",
		},
	}
	if def.fog then
		sky.fog = {fog_distance = def.fog, fog_start = def.fog_start}
	end
	return sky
end

local BASE = lw_maps.base_y

lw_maps.register({
	id = "halloween",
	title = "Halloween lane",
	blurb = "Dusk lane of carved lanterns, a graveyard, a haunted house with " ..
		"a cellar and an attic, and a porch stage at the end.",
	size = {x = 36, y = 20, z = 36},
	origin = {x = -88, y = BASE, z = -26},
	spawn = {x = -55, y = BASE + 4, z = -9},
	-- Dusk, per player, so the hub's frozen midday is untouched. An honest
	-- view distance is part of the look: fog is the point, not a limitation.
	day_night_ratio = 0.16,
	sky = lw_maps.sky({
		sky = "#241a2e", horizon = "#4a2a22",
		night_sky = "#140f1c", night_horizon = "#2a1a18", indoors = "#1a1420",
		sun_tint = "#c86a28", moon_tint = "#5a4a78",
		fog = 72, fog_start = 0.35,
	}),
	-- The kinetic beat: a vane that spins on the house ridge, one node above
	-- the mast the generator puts there.
	entities = {{name = "lw_maps:weather_vane", at = {x = 25, y = 19, z = 27}}},
})

lw_maps.register({
	id = "snow_mountain",
	title = "Snowy mountain",
	blurb = "A peak you can climb and also go through: switchback trail, ice " ..
		"cave, timbered mineshaft, and a tunnel out the far face.",
	size = {x = 40, y = 28, z = 40},
	origin = {x = -20, y = BASE, z = -74},
	spawn = {x = 6, y = BASE + 4, z = -37},
	day_night_ratio = 0.85,
	sky = lw_maps.sky({
		sky = "#9fb8cf", horizon = "#cfdce8",
		night_sky = "#2a3a4a", night_horizon = "#3a4a5a", indoors = "#6a7a8a",
		sun_tint = "#dfe8f2", moon_tint = "#b0c0d0",
		fog = 110, fog_start = 0.5,
	}),
})

lw_maps.register({
	id = "fruit_garden",
	title = "Giant fruit garden",
	blurb = "Oversized produce as architecture: a walk-in watermelon, a " ..
		"sliced-melon amphitheatre, and a juice channel between them.",
	size = {x = 40, y = 20, z = 40},
	origin = {x = 53, y = BASE, z = -28},
	spawn = {x = 55, y = BASE + 4, z = -7},
})

lw_maps.register({
	id = "lighthouse_tide",
	title = "Lighthouse tide",
	blurb = "Blue hour on a lagoon: a lighthouse you climb to the lamp, a " ..
		"jetty with glass-bottomed tide pools, and a glass tunnel along the " ..
		"bed underneath it.",
	size = {x = 36, y = 24, z = 36},
	origin = {x = -66, y = BASE, z = -80},
	spawn = {x = -39, y = BASE + 4, z = -46},
	-- Late blue hour: dark enough that the beam reads, light enough that the
	-- lagoon still has a colour. The fog is light, because the horizon is
	-- what a lighthouse is for.
	day_night_ratio = 0.28,
	sky = lw_maps.sky({
		sky = "#1d3a66", horizon = "#46679a",
		night_sky = "#0c1a33", night_horizon = "#1e3150", indoors = "#15243d",
		sun_tint = "#8fa8d8", moon_tint = "#5d7bb0",
		fog = 110, fog_start = 0.6,
	}),
	-- The lamp's beam sweeps from one node above the lamp itself.
	entities = {{name = "lw_maps:lighthouse_beam", at = {x = 8, y = 21, z = 8}}},
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
	-- set_sky() with no argument is the only call that resets the sky: an
	-- empty table leaves every field as it was, which would carry one map's
	-- fog back to the hub, or onto the next map a visitor travels to.
	player:set_sky()
	if map and map.sky then
		player:set_sky(map.sky)
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
-- Moving props
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

-- A lighthouse beam, the cheapest way there is: one long translucent sprite,
-- two quads, turning about the lamp. It glows so blue hour does not dim it.
core.register_entity("lw_maps:lighthouse_beam", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		visual = "upright_sprite",
		visual_size = {x = 24, y = 1.2},
		textures = {
			"lw_glass.png^[multiply:#fff1b0^[opacity:120",
			"lw_glass.png^[multiply:#fff1b0^[opacity:120",
		},
		use_texture_alpha = true,
		glow = 14,
		shaded = false,
		static_save = false,
		infotext = "Lighthouse beam",
	},
	age = 0,
	on_step = function(self, dtime)
		self.age = self.age + dtime
		self.object:set_yaw(self.age * 0.7)
	end,
})

local function ensure_entity(name, pos)
	for _, object in ipairs(core.get_objects_inside_radius(pos, 6)) do
		local entity = object:get_luaentity()
		if entity and entity.name == name then
			return
		end
	end
	core.add_entity(pos, name)
end

core.register_on_joinplayer(function()
	core.after(3, function()
		for _, map in ipairs(lw_maps.maps) do
			for _, entity in ipairs(map.entities) do
				ensure_entity(entity.name, entity.pos)
			end
		end
	end)
end)

--------------------------------------------------------------------------
-- /maps
--------------------------------------------------------------------------

-- How much of a map to have on hand before a visitor lands on it: the spawn's
-- own neighbourhood, not the island. A couple of map blocks either way is
-- what the first frame needs; the rest streams in as they walk.
local EMERGE_RADIUS = 16

-- Sends `player` to map `id` once the ground under its spawn exists. The
-- islands are far enough from the hub that a visitor moved straight away can
-- arrive before the chunk does and fall through the place it will be, so the
-- move waits for the emerge. `done(ok)` is called when the move happens, or
-- with false if the player left in the meantime.
function lw_maps.teleport(player, id, done)
	local map = lw_maps.by_id[id]
	if not map then
		return false
	end
	local name = player:get_player_name()
	local spawn = vector.new(map.spawn)
	core.emerge_area(vector.offset(spawn, -EMERGE_RADIUS, -8, -EMERGE_RADIUS),
		vector.offset(spawn, EMERGE_RADIUS, EMERGE_RADIUS, EMERGE_RADIUS),
		function(_, _, remaining)
			if remaining > 0 then
				return
			end
			local still_here = core.get_player_by_name(name)
			if still_here then
				still_here:set_pos(spawn)
			end
			if done then
				done(still_here ~= nil)
			end
		end)
	return true
end

local function listing()
	local lines = {"Themed maps (walk the causeways from the plaza, or /maps <name>):"}
	for _, map in ipairs(lw_maps.maps) do
		lines[#lines + 1] = ("  %-15s %s"):format(map.id, map.title)
		lines[#lines + 1] = ("                  %s"):format(map.blurb)
	end
	return table.concat(lines, "\n")
end

local function ids()
	local list = {}
	for _, map in ipairs(lw_maps.maps) do
		list[#list + 1] = map.id
	end
	return list
end

core.register_chatcommand("maps", {
	params = "[" .. table.concat(ids(), "|") .. "]",
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
		local map = lw_maps.by_id[param]
		if not map then
			return false, "No map called " .. param .. ".\n" .. listing()
		end
		lw_maps.teleport(player, param, function(arrived)
			if arrived then
				core.chat_send_player(name, map.title .. " — " .. map.blurb)
			end
		end)
		return true, "Travelling to " .. map.title .. "…"
	end,
})

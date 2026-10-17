-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The themed map pack: the props the authored maps need, the registry
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
-- Night bazaar
--------------------------------------------------------------------------

-- Stall lanterns: the palette's lamp tile, warmed, in a lit and an unlit
-- state for the chase controller to swap between. Everything else on the
-- bazaar — the crystal, the awnings, the vault — is glass and dyed wool.
register("lantern", {
	description = "Bazaar Lantern",
	tiles = {"lw_lamp.png^[multiply:#ffc46a"},
	paramtype = "light",
	light_source = 12,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

register("lantern_off", {
	description = "Bazaar Lantern (unlit)",
	tiles = {"lw_lamp.png^[multiply:#5c4634"},
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

--------------------------------------------------------------------------
-- Volcano
--------------------------------------------------------------------------

register("basalt", {
	description = "Basalt",
	tiles = {"lw_stone.png^[multiply:#4a4346"},
	groups = {cracky = 2},
	is_ground_content = true,
})

register("packed_basalt", {
	description = "Packed Basalt",
	tiles = {"lw_stone_brick.png^[multiply:#5a5054"},
	groups = {cracky = 2},
})

-- "Lava" is dyed wool that glows, in a bright and a crusted state for the
-- flicker controller: the look of a lava lake with none of a liquid's cost,
-- and nothing that hurts. It is solid, so the crater floor is a floor.
register("lava", {
	description = "Glowing Lava Rock",
	tiles = {"lw_wool.png^[multiply:#ff6a1a"},
	paramtype = "light",
	light_source = 11,
	groups = {cracky = 3},
})

register("lava_crust", {
	description = "Crusted Lava Rock",
	tiles = {"lw_wool.png^[multiply:#6e2410"},
	groups = {cracky = 3},
})

--------------------------------------------------------------------------
-- Around arena
--------------------------------------------------------------------------

-- Truss lights: the palette's lamp tile in the band's violet, lit and dark,
-- for the chase controller to race round the arena's truss.
register("stage_light", {
	description = "Truss Light",
	tiles = {"lw_lamp.png^[multiply:#c890ff"},
	paramtype = "light",
	light_source = 13,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

register("stage_light_off", {
	description = "Truss Light (dark)",
	tiles = {"lw_lamp.png^[multiply:#3a2450"},
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

-- A banner is one image cut into `cols` x `rows` full cubes with `[sheet`,
-- numbered in reading order from the top left: `lw_maps:<name>_1` and on.
-- The art is on the face that looks south at facedir 0 (tile 6, as on
-- lw_nodes:poster); the other five faces are black cloth. They glow a little,
-- because the arena is at night and a banner nobody can see is not one.
--
-- The cut cells are not in the inventory: a single cell of a portrait is not
-- something anyone would build with.
local BANNER_BACK = "lw_wool.png^[multiply:#1c1c1a"

function lw_maps.register_banner(name, def)
	local count = def.cols * def.rows
	for row = 0, def.rows - 1 do
		for col = 0, def.cols - 1 do
			local index = row * def.cols + col + 1
			local art = ("%s^[sheet:%dx%d:%d,%d"):format(def.texture,
				def.cols, def.rows, col, row)
			register(("%s_%d"):format(name, index), {
				description = count > 1
					and ("%s (%d of %d)"):format(def.description, index, count)
					or def.description,
				tiles = {BANNER_BACK, BANNER_BACK, BANNER_BACK, BANNER_BACK,
					BANNER_BACK, art},
				paramtype2 = "facedir",
				on_place = core.rotate_node,
				light_source = def.light,
				groups = {snappy = 2, oddly_breakable_by_hand = 3,
					not_in_creative_inventory = 1},
			})
		end
	end
end

lw_maps.register_banner("around_sign", {
	description = "\"Around!\" Sign", texture = "lw_around_sign.png",
	cols = 5, rows = 1, light = 9,
})
lw_maps.register_banner("lace_banner", {
	description = "Lace Waterfall Banner", texture = "lw_lace_banner.png",
	cols = 1, rows = 3, light = 4,
})
lw_maps.register_banner("portrait_rubella", {
	description = "Rubella Banner", texture = "lw_portrait_rubella.png",
	cols = 2, rows = 4, light = 5,
})
lw_maps.register_banner("portrait_lillith", {
	description = "Lillith Banner", texture = "lw_portrait_lillith.png",
	cols = 2, rows = 4, light = 5,
})

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
lw_maps.register_lamp_pair("lw_maps:lantern", "lw_maps:lantern_off")
lw_maps.register_lamp_pair("lw_maps:lava", "lw_maps:lava_crust")
lw_maps.register_lamp_pair("lw_maps:stage_light", "lw_maps:stage_light_off")

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
--
-- `storm = {rods = {<map-local position>, ...}}` gives a map rain and
-- lightning while someone is on it; each rod is a node the bolts land on top
-- of. See "Storms" below.
--
-- `amps = {left = <local>, right = <local>, song = <name>}` plays a song out
-- of the map's own amp cabs when someone walks onto it, and `lasers = {...}`
-- races lights and lasers round a track while anyone is there. See "Shows".
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

lw_maps.register({
	id = "crystal_bazaar",
	title = "Crystal night bazaar",
	blurb = "A vaulted glass arcade of lantern-lit stalls at night, a glass " ..
		"dome you can walk up onto, and a torchlit cistern underneath it.",
	size = {x = 36, y = 16, z = 36},
	origin = {x = 54, y = BASE, z = 24},
	spawn = {x = 55, y = BASE + 4, z = 42},
	-- Night, with a saturated sky and no fog of its own, so glass reads as
	-- glass against it and the lanterns are the brightest thing there.
	day_night_ratio = 0.08,
	sky = lw_maps.sky({
		sky = "#2a1466", horizon = "#6a1f8a",
		night_sky = "#1a0b45", night_horizon = "#4a1466", indoors = "#1f1040",
		sun_tint = "#c070ff", moon_tint = "#7050d0",
	}),
})

lw_maps.register({
	id = "smoke_caldera",
	title = "Smoke caldera",
	blurb = "A volcano you climb and go through: a ring trail to the rim, a " ..
		"glass lip over a glowing crater, a switchback down to it, and a " ..
		"basalt tube out the far face.",
	size = {x = 38, y = 22, z = 38},
	origin = {x = -94, y = BASE, z = 22},
	spawn = {x = -57, y = BASE + 4, z = 41},
	-- Overcast red hour: the fog is warm and close, so the cone is a
	-- silhouette from the causeway and the crater glows from inside it.
	day_night_ratio = 0.35,
	sky = lw_maps.sky({
		sky = "#5a2a22", horizon = "#b0482a",
		night_sky = "#2a1210", night_horizon = "#6a2418", indoors = "#3a1a14",
		sun_tint = "#ff7a3a", moon_tint = "#a04a3a",
		fog = 64, fog_start = 0.3,
	}),
})

lw_maps.register({
	id = "rainbow_storm",
	title = "Rainbow storm",
	blurb = "A walk over low rainbow arches under a thunderstorm: rain on " ..
		"the deck and lightning striking the rods on the crests.",
	size = {x = 64, y = 8, z = 24},
	origin = {x = 40, y = BASE, z = -120},
	spawn = {x = 41, y = BASE + 4, z = -109},
	-- Dim, not night: the wool has to still read as a rainbow. A little fog
	-- lets the sea fade while the arches stay in view.
	day_night_ratio = 0.45,
	sky = lw_maps.sky({
		sky = "#2a3344", horizon = "#6a7080",
		night_sky = "#1a2030", night_horizon = "#3a4050", indoors = "#2a3040",
		sun_tint = "#8a90a0", moon_tint = "#5a6070",
		fog = 90, fog_start = 0.5,
	}),
	-- Rain and lightning, run only while someone is on the island (see
	-- "Storms" below). The rods are the fence posts the generator puts on
	-- each crest, in map-local coordinates.
	storm = {rods = {{x = 20, y = 7, z = 7}, {x = 45, y = 7, z = 15}}},
})

lw_maps.register({
	id = "around_arena",
	title = "Around arena",
	blurb = "Lace Waterfall's stage at night: lights racing round the truss " ..
		"and lasers sweeping the floor. The concert itself is next door, in " ..
		"the concert arena.",
	size = {x = 25, y = 12, z = 25},
	origin = {x = 29, y = BASE, z = 76},
	spawn = {x = 41, y = BASE + 4, z = 76},
	-- Night with a violet cast and a little fog, so the truss lights and the
	-- lasers are the brightest things there and the sea fades out behind.
	day_night_ratio = 0.1,
	sky = lw_maps.sky({
		sky = "#1a0a2e", horizon = "#4a1a6a",
		night_sky = "#0e0618", night_horizon = "#2e0f44", indoors = "#140a22",
		sun_tint = "#b060ff", moon_tint = "#6a3cc0",
		fog = 120, fog_start = 0.6,
	}),
	-- No `amps`: the song lives only in the concert arena, so a visit here
	-- never pulls the song files in. Four emitters ride the top of the truss
	-- round the arena's edge, a lap every eight bars at Around's tempo, each
	-- with a laser down to a point that circles the dance floor the other way.
	lasers = {
		track = {x0 = 0, z0 = 0, x1 = 24, z1 = 24, y = 10},
		target = {x = 12, y = 4, z = 9, radius = 4},
		colors = {"#c070ff", "#ff40c8", "#f0e0ff", "#8f50ff"},
		lap_beats = 32,
		bpm = 175,
	},
})

lw_maps.register({
	id = "concert_arena",
	title = "Concert arena",
	blurb = "Lace Waterfall live: \"Around\" out of the stage amps as you walk " ..
		"in, the band on a wide stage, risers down both sides, lights racing " ..
		"round the truss and lasers over the floor.",
	-- 49 x 13 x 49, about twice the Around arena on each side. The only map
	-- with `amps`, so the only place the heavy song files are ever sent to a
	-- client (lw_amps/songs/README.md); keep any heavier audio experiment here.
	size = {x = 49, y = 13, z = 49},
	origin = {x = 35, y = BASE, z = 120},
	spawn = {x = 59, y = BASE + 4, z = 120},
	day_night_ratio = 0.08,
	sky = lw_maps.sky({
		sky = "#160828", horizon = "#5a1450",
		night_sky = "#0a0414", night_horizon = "#2e0a30", indoors = "#12081e",
		sun_tint = "#ff50c0", moon_tint = "#7040d0",
		fog = 140, fog_start = 0.6,
	}),
	-- The sound sources, one node above the cabs on the stage's front, twenty
	-- nodes apart, audience-left first. lw_dance puts the band between them.
	amps = {
		left = {x = 14, y = 6, z = 30},
		right = {x = 34, y = 6, z = 30},
		song = "around_happy_hard",
	},
	-- Six emitters on a truss twice as long, so a lap is sixteen bars and
	-- they move at the same speed as the Around arena's.
	lasers = {
		track = {x0 = 0, z0 = 0, x1 = 48, z1 = 48, y = 11},
		target = {x = 24, y = 4, z = 15, radius = 8},
		colors = {"#c070ff", "#ff40c8", "#f0e0ff", "#8f50ff", "#40e0ff", "#ff70a0"},
		lap_beats = 64,
		bpm = 175,
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
	-- set_sky() with no argument is the only call that resets the sky: an
	-- empty table leaves every field as it was, which would carry one map's
	-- fog back to the hub, or onto the next map a visitor travels to.
	player:set_sky()
	if map and map.sky then
		player:set_sky(map.sky)
	end
	player:override_day_night_ratio(map and map.day_night_ratio or nil)
end

--------------------------------------------------------------------------
-- Storms
--------------------------------------------------------------------------

-- A map with a `storm` gets rain and lightning, per player, only while that
-- player is on it: one particle spawner attached to them for the rain, and
-- on a fixed beat a flash of the sky and a bolt down onto one of the map's
-- rods. Nothing is saved and nothing ticks while nobody is there.
--
-- The beat comes from core.get_gametime(), so every visitor sees the same
-- flash on the same rod and a reload needs no saved state. Gaps of 6, 8 and
-- 7 seconds, so it is regular enough to wait for and not a metronome.
lw_maps.STORM_GAPS = {6, 8, 7}
local STORM_CYCLE = 0
local STORM_OFFSETS = {}
for _, gap in ipairs(lw_maps.STORM_GAPS) do
	STORM_OFFSETS[STORM_CYCLE] = #STORM_OFFSETS + 1
	STORM_CYCLE = STORM_CYCLE + gap
end
-- How long the sky stays white, and the bolt with it.
local FLASH_TIME = 0.12
-- The bolt: this many two-node particles stacked up from the rod's top.
local BOLT_SEGMENTS = 9

-- The number of the flash that happens at whole second `t`, or nil if no
-- flash happens then. Flash k strikes rod (k % #rods) + 1.
function lw_maps.storm_flash(t)
	local index = STORM_OFFSETS[t % STORM_CYCLE]
	if not index then
		return nil
	end
	return math.floor(t / STORM_CYCLE) * #lw_maps.STORM_GAPS + index - 1
end

local FLASH_SKY = (function()
	local white = {
		day_sky = "#e8ecff", day_horizon = "#ffffff",
		dawn_sky = "#e8ecff", dawn_horizon = "#ffffff",
		night_sky = "#e8ecff", night_horizon = "#ffffff",
		indoors = "#c8d0e0",
	}
	return {type = "regular", sky_color = white}
end)()

local rain = {}          -- player name -> {map = id, id = spawner id}
local last_flash = {}    -- player name -> gametime of the last flash they saw

local function start_rain(player, map)
	return core.add_particlespawner({
		amount = 40,
		time = 0,
		attached = player,
		-- A box over the visitor's head, not over the island: the worker
		-- only ever draws the rain one person can see.
		minpos = {x = -7, y = 5, z = -7},
		maxpos = {x = 7, y = 8, z = 7},
		minvel = {x = -0.6, y = -14, z = -0.3},
		maxvel = {x = 0.6, y = -12, z = 0.3},
		minexptime = 0.5,
		maxexptime = 0.75,
		minsize = 6,
		maxsize = 8,
		collisiondetection = true,
		collision_removal = true,
		vertical = true,
		texture = "lw_rain.png",
		playername = player:get_player_name(),
	})
end

local function update_rain(player, map)
	local name = player:get_player_name()
	local want = map and map.storm and map.id or nil
	local have = rain[name]
	if have and have.map == want then
		return
	end
	if have then
		core.delete_particlespawner(have.id)
		rain[name] = nil
	end
	if want then
		rain[name] = {map = want, id = start_rain(player, map)}
	end
end

-- A bolt from the sky down onto `top`, the top face of a rod, seen by one
-- player. Its zigzag comes from the flash number, so it is the same for
-- everyone watching.
local function bolt(name, top, k)
	local x, z = top.x, top.z
	for segment = 0, BOLT_SEGMENTS - 1 do
		if segment > 0 then
			x = top.x + ((k * 7 + segment * 5) % 5 - 2) * 0.15
			z = top.z + ((k * 3 + segment * 7) % 5 - 2) * 0.15
		end
		core.add_particle({
			pos = {x = x, y = top.y + 1 + segment * 2, z = z},
			expirationtime = FLASH_TIME + 0.05,
			size = 20,
			vertical = true,
			glow = 14,
			texture = "lw_rain.png^[brighten^[brighten",
			playername = name,
		})
	end
end

local function flash(player, map, k)
	local name = player:get_player_name()
	local rods = map.storm.rods
	local rod = rods[k % #rods + 1]
	bolt(name, vector.offset(lw_maps.to_world(map, rod), 0, 0.5, 0), k)
	-- Straight at the player, not through apply(): apply() does nothing when
	-- the map has not changed, and its reset would drop the storm's own sky.
	player:set_sky(FLASH_SKY)
	player:override_day_night_ratio(1)
	core.after(FLASH_TIME, function()
		local still = core.get_player_by_name(name)
		-- If they left in the last tenth of a second, apply() has already
		-- given them the hub's sky; putting the storm back would undo that.
		if still and current[name] == map.id then
			still:set_sky(map.sky)
			still:override_day_night_ratio(map.day_night_ratio)
		end
	end)
end

local function storm_step()
	local now = core.get_gametime and core.get_gametime()
	if not now then
		return
	end
	now = math.floor(now)
	local k = lw_maps.storm_flash(now)
	if not k then
		return
	end
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local map = lw_maps.by_id[current[name] or ""]
		if map and map.storm and last_flash[name] ~= now then
			last_flash[name] = now
			flash(player, map, k)
		end
	end
end

--------------------------------------------------------------------------
-- Shows
--------------------------------------------------------------------------

-- A map with `amps` is a stage. When someone walks onto it and nothing is
-- playing anywhere, lw_amps is pointed at its two cabs and the song starts;
-- lw_dance hears that and puts the band on the deck between them. When the
-- last visitor walks off, a song still coming out of those cabs stops. In
-- between, punching a cab stops and restarts it, as with any other pair.
--
-- lw_amps is optional, and so is sound: without the mod the stage is quiet,
-- and without OpenAL the song still "plays" and the band still dances.
local function amps_mod()
	return rawget(_G, "lw_amps")
end

local function same_pos(a, b)
	return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end

local function stage_sources(map)
	return lw_maps.to_world(map, map.amps.left), lw_maps.to_world(map, map.amps.right)
end

local function playing_here(map)
	local amps = amps_mod()
	if not (amps and amps.now_playing and amps.now_playing()) then
		return false
	end
	local left, right = amps.get_amps()
	local want_left, want_right = stage_sources(map)
	return same_pos(left, want_left) and same_pos(right, want_right)
end

local function start_song(map)
	local amps = amps_mod()
	if not (amps and amps.play) or amps.now_playing() then
		return
	end
	amps.set_amps(stage_sources(map))
	amps.play(map.amps.song)
end

local function stop_song(map)
	if playing_here(map) then
		amps_mod().stop()
	end
end

-- `lasers` races emitters round a rectangle in map-local coordinates — the
-- arena's truss — one per colour, evenly spaced, a lap every `lap_beats` at
-- `bpm`. Each one throws a beam down to a point that circles `target` on the
-- floor the other way, twice a lap, so the beams sweep the crowd while the
-- lights race round them.
--
-- They exist only while someone is on the map: spawned when the first visitor
-- arrives, removed when the last one leaves, never saved. The clock is server
-- time, so every visitor sees the same beams.
lw_maps.SHOW_INTERVAL = 0.1
-- How far above the truss row's own centre an emitter rides: on top of it.
local EMITTER_RISE = 0.8
local BEAM_WIDTH = 0.08

function lw_maps.track_length(track)
	return 2 * ((track.x1 - track.x0) + (track.z1 - track.z0))
end

-- The point `s` nodes round `track` from its (x0, z0) corner, going east
-- along the south side first — the order the generator numbers the truss
-- lights in, so emitters and the chase run the same way.
function lw_maps.track_point(track, s)
	local w, d = track.x1 - track.x0, track.z1 - track.z0
	s = s % lw_maps.track_length(track)
	if s < w then
		return track.x0 + s, track.z0
	end
	s = s - w
	if s < d then
		return track.x1, track.z0 + s
	end
	s = s - d
	if s < w then
		return track.x1 - s, track.z1
	end
	return track.x0, track.z1 - (s - w)
end

-- Emitter `index` at show time `t`: where it is and where its beam lands.
function lw_maps.laser_frame(map, t, index)
	local lasers = map.lasers
	local lap = lasers.lap_beats * 60 / lasers.bpm
	local phase = (index - 1) / #lasers.colors
	local x, z = lw_maps.track_point(lasers.track,
		(t / lap + phase) * lw_maps.track_length(lasers.track))
	local from = lw_maps.to_world(map, {x = x, y = lasers.track.y + EMITTER_RISE, z = z})
	local target = lasers.target
	local angle = (phase - 2 * t / lap) * 2 * math.pi
	-- On the floor's top face, a hair above it so it does not z-fight.
	local to = lw_maps.to_world(map, {
		x = target.x + target.radius * math.cos(angle),
		y = target.y - 0.48,
		z = target.z + target.radius * math.sin(angle),
	})
	return from, to
end

local shows = {}        -- map id -> {{emitter, beam, color, length}, ...}
local occupied = {}     -- map id -> true while someone is on a stage map
local show_time = 0
local show_elapsed = 0

local function alive(object)
	return object ~= nil and object:get_pos() ~= nil
end

local function spawn_emitter(pos, color)
	local object = core.add_entity(pos, "lw_maps:laser_emitter")
	if object then
		local face = "lw_lamp.png^[multiply:" .. color
		object:set_properties({textures = {face, face, face, face, face, face}})
	end
	return object
end

local function spawn_beam(pos, color)
	local object = core.add_entity(pos, "lw_maps:laser_beam")
	if object then
		local face = "lw_lamp.png^[multiply:" .. color
		object:set_properties({textures = {face, face}})
	end
	return object
end

-- A beam is a sprite whose height runs along its local +Y. That is pointed
-- along the beam, and its face turned side-on to the beam's heading, so the
-- floor sees it broadside rather than edge on.
local function pose_beam(slot, from, to)
	local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	local flat = math.sqrt(dx * dx + dz * dz)
	if length < 1e-3 or flat < 1e-3 then
		return
	end
	local dir = vector.new(dx / length, dy / length, dz / length)
	local side = vector.new(dz / flat, 0, -dx / flat)
	slot.beam:move_to(vector.new((from.x + to.x) / 2, (from.y + to.y) / 2,
		(from.z + to.z) / 2), true)
	slot.beam:set_rotation(vector.dir_to_rotation(side, dir))
	-- Properties are a whole packet; only resend them when the length has
	-- moved enough to see.
	if not slot.length or math.abs(slot.length - length) > 0.2 then
		slot.length = length
		slot.beam:set_properties({visual_size = {x = BEAM_WIDTH, y = length}})
	end
end

local function update_show(map)
	for index, slot in ipairs(shows[map.id]) do
		local from, to = lw_maps.laser_frame(map, show_time, index)
		if alive(slot.emitter) then
			slot.emitter:move_to(from, true)
		else
			slot.emitter = spawn_emitter(from, slot.color)
		end
		if not alive(slot.beam) then
			slot.beam, slot.length = spawn_beam(from, slot.color), nil
		end
		if slot.beam then
			pose_beam(slot, from, to)
		end
	end
end

local function start_show(map)
	local slots = {}
	for index, color in ipairs(map.lasers.colors) do
		slots[index] = {color = color}
	end
	shows[map.id] = slots
	update_show(map)
end

local function stop_show(id)
	for _, slot in ipairs(shows[id] or {}) do
		-- Either may be missing (an add_entity that failed), so not ipairs.
		if alive(slot.emitter) then
			slot.emitter:remove()
		end
		if alive(slot.beam) then
			slot.beam:remove()
		end
	end
	shows[id] = nil
end

function lw_maps.show_objects(id)
	return shows[id]
end

local function show_step(dtime)
	show_time = show_time + dtime
	show_elapsed = show_elapsed + dtime
	if show_elapsed < lw_maps.SHOW_INTERVAL then
		return
	end
	show_elapsed = 0
	for id in pairs(shows) do
		update_show(lw_maps.by_id[id])
	end
end

-- Once per atmosphere tick: `visitors` is map id -> how many are on it.
local function update_shows(visitors)
	for _, map in ipairs(lw_maps.maps) do
		local here = (visitors[map.id] or 0) > 0
		if map.lasers then
			if here and not shows[map.id] then
				start_show(map)
			elseif not here and shows[map.id] then
				stop_show(map.id)
			end
		end
		if map.amps then
			-- Only on the way out, so a song started by hand from elsewhere
			-- while nobody is on the stage is left alone.
			if occupied[map.id] and not here then
				stop_song(map)
			end
			occupied[map.id] = here or nil
		end
	end
end

local ATMOSPHERE_INTERVAL = 0.5
local elapsed = 0

core.register_globalstep(function(dtime)
	storm_step()
	show_step(dtime)
	elapsed = elapsed + dtime
	if elapsed < ATMOSPHERE_INTERVAL then
		return
	end
	elapsed = 0
	local visitors = {}
	for _, player in ipairs(core.get_connected_players()) do
		local was = current[player:get_player_name()]
		local map = lw_maps.at(player:get_pos())
		apply(player, map)
		update_rain(player, map)
		if map then
			visitors[map.id] = (visitors[map.id] or 0) + 1
			-- Arriving, by causeway, by /maps or by joining there, is what
			-- starts a stage's song: staying does not restart one a visitor
			-- stopped by punching a cab.
			if map.amps and map.id ~= was then
				start_song(map)
			end
		end
	end
	update_shows(visitors)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	current[name] = nil
	if rain[name] then
		core.delete_particlespawner(rain[name].id)
		rain[name] = nil
	end
	last_flash[name] = nil
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

-- The Around arena's racing lights and their lasers (see "Shows"). The
-- emitter is a small glowing cube; the beam a thin sprite the show driver
-- stretches and aims every tenth of a second. Both are spawned while someone
-- is on the arena and never saved.
core.register_entity("lw_maps:laser_emitter", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		visual = "cube",
		visual_size = {x = 0.45, y = 0.45, z = 0.45},
		textures = {"lw_lamp.png", "lw_lamp.png", "lw_lamp.png",
			"lw_lamp.png", "lw_lamp.png", "lw_lamp.png"},
		glow = 14,
		static_save = false,
	},
})

core.register_entity("lw_maps:laser_beam", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		visual = "upright_sprite",
		visual_size = {x = 0.08, y = 1},
		textures = {"lw_lamp.png", "lw_lamp.png"},
		glow = 14,
		shaded = false,
		static_save = false,
	},
})

-- Punching the lantern-room lamp plays a short horn. The beam entity sits one
-- node above that lamp, so the lamp's place is derived from the registry
-- rather than a second copy of the coordinate. Other lamps on the jetty and
-- the promenade are the same node and stay quiet. Sound is optional: a build
-- without OpenAL has no sound_play, and a missing file stays silent too.
local LIGHTHOUSE_SOUND = "lw_lighthouse"

local function lighthouse_lamp_pos()
	local map = lw_maps.by_id["lighthouse_tide"]
	if not map then
		return nil
	end
	for _, entity in ipairs(map.entities) do
		if entity.name == "lw_maps:lighthouse_beam" then
			return vector.offset(entity.pos, 0, -1, 0)
		end
	end
end

core.register_on_punchnode(function(pos, node)
	if node.name ~= "lw_nodes:lamp" then
		return
	end
	local lamp = lighthouse_lamp_pos()
	if not lamp or pos.x ~= lamp.x or pos.y ~= lamp.y or pos.z ~= lamp.z then
		return
	end
	if type(core.sound_play) ~= "function" then
		return
	end
	pcall(core.sound_play, LIGHTHOUSE_SOUND, {
		pos = pos, gain = 0.55, max_hear_distance = 48,
	}, true)
end)

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

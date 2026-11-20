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
-- Weeks on Fire: the laser serpent and the mirror hall
--------------------------------------------------------------------------

-- Everything here is a palette tile re-tinted, like the wool cubes: the
-- pack's two Weeks on Fire islands add no textures.

-- The serpent's scales, lit and dark, for the chase controllers that run
-- light up its coil from tail to neck.
register("serpent_scale", {
	description = "Serpent Scale",
	tiles = {"lw_wool.png^[multiply:#ff2a6a"},
	paramtype = "light",
	light_source = 10,
	groups = {snappy = 2, oddly_breakable_by_hand = 3},
})

register("serpent_scale_off", {
	description = "Serpent Scale (dark)",
	tiles = {"lw_wool.png^[multiply:#3a0a1c"},
	groups = {snappy = 2, oddly_breakable_by_hand = 3},
})

-- A static laser emitter: the serpent's eyes, the pylon caps, the crystal
-- skull's eyes. The moving emitters are lw_maps:laser_emitter entities.
register("laser_block", {
	description = "Laser Emitter Block",
	tiles = {"lw_lamp.png^[multiply:#ff2050"},
	paramtype = "light",
	light_source = 12,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

-- A neon tube lying on the floor along x (facedir turns it). Thin and not
-- walkable, so a walk edged with it can be stepped across.
local NEON_BOX = {type = "fixed", fixed = {-0.5, -0.5, -0.0625, 0.5, -0.375, 0.0625}}
register("neon_tube", {
	description = "Neon Tube",
	drawtype = "nodebox",
	tiles = {"lw_lamp.png^[multiply:#ff40c8"},
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = false,
	light_source = 9,
	on_place = core.rotate_node,
	node_box = NEON_BOX,
	selection_box = NEON_BOX,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

-- Embers, lit and ashen, for the flicker controller: the caldera's lava
-- trick at a campfire's size. Solid, cool, and harmless.
register("ember_block", {
	description = "Ember Block",
	tiles = {"lw_wool.png^[multiply:#ff4a18"},
	paramtype = "light",
	light_source = 9,
	groups = {cracky = 3},
})

register("ember_block_off", {
	description = "Ember Block (ash)",
	tiles = {"lw_wool.png^[multiply:#3a1610"},
	groups = {cracky = 3},
})

-- A silvered tile: polished stone gone blue-white under the glass tile's
-- highlights, with a faint glow so a twilight hall still reads as mirrors.
register("mirror", {
	description = "Mirror Tile",
	tiles = {"lw_polished_stone.png^[multiply:#a8bce0^lw_glass.png"},
	paramtype = "light",
	light_source = 3,
	groups = {cracky = 3},
})

-- Crystal, lit and dim: the mirror hall's glints, its skull and the parapet
-- crystals that chase round its gallery.
register("crystal", {
	description = "Glowing Crystal",
	drawtype = "glasslike",
	tiles = {"lw_glass.png^[multiply:#7ff0ff"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 9,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

register("crystal_dim", {
	description = "Glowing Crystal (dim)",
	drawtype = "glasslike",
	tiles = {"lw_glass.png^[multiply:#2a5a70"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 2,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
})

-- The HOA's notices. Punch one (or right click it) for the next memo: each
-- board starts at a different one and then goes round them all in order, so
-- two boards side by side do not repeat each other. Text only, on the
-- palette's poster tile.
lw_maps.HOA_MEMOS = {
	"HOA MEMO 41: Laser serpents must be leashed in all common areas.",
	"HOA MEMO 42: The mirror hall is not a portal. Please stop asking the front desk.",
	"HOA MEMO 43: Open flame is permitted on balconies during scheduled cabaret hours only.",
	"HOA MEMO 44: Neon signage may not exceed nine thousand lumens or one (1) aura.",
	"HOA MEMO 45: The arcology lift does not stop at floor 13. There is no floor 13. " ..
		"Please stop pressing it.",
	"HOA MEMO 46: Do not feed the serpent after midnight. It is a laser. It does not eat.",
	"HOA MEMO 47: Smoke from the caldera is a shared amenity, not a nuisance.",
	"HOA MEMO 48: Unscheduled dance numbers in the lobby require Form 7-B, in triplicate.",
	"HOA MEMO 49: The crystal skull is on loan. Do not ask it questions.",
	"HOA MEMO 50: Embers from the Ember Tool go out by themselves. Do not stamp on them.",
	"HOA MEMO 51: Riley, the roof is not a stage. Rubella and Lillith have the cabaret for that.",
	"HOA MEMO 52: Mirrors are to be polished on alternate Tuesdays. Reflections are not " ..
		"to be addressed directly.",
}

local MEMO_HINT = "HOA Memo (punch to read)"
local MEMO_BOX = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, -0.4375}}

-- The HOA's holiday notices, on the Christmas islands' boards (the red and
-- green bordered lw_maps:hoa_holiday_memo). Same rules, its own pile.
lw_maps.HOA_HOLIDAY_MEMOS = {
	"HOA HOLIDAY MEMO 1: Trees may be decorated, lit, or on fire. Not more than two of these at once.",
	"HOA HOLIDAY MEMO 2: Lasers are permitted as tinsel between 6 pm and the heat death of the " ..
		"universe.",
	"HOA HOLIDAY MEMO 3: Presents left under the burning tree are considered pre-wrapped " ..
		"in ash. No refunds.",
	"HOA HOLIDAY MEMO 4: The cabaret's Christmas revue requires Form 12-D (Dancing, Seasonal), " ..
		"in triplicate, in glitter.",
	"HOA HOLIDAY MEMO 5: Reindeer must be parked within the painted lines. The sleigh is not " ..
		"a compact.",
	"HOA HOLIDAY MEMO 6: Snow is a shared amenity. Do not take more than your allotted flakes.",
	"HOA HOLIDAY MEMO 7: Carolling is limited to four (4) verses and zero (0) key changes.",
	"HOA HOLIDAY MEMO 8: The crystal skull's Santa hat has been confiscated pending review.",
	"HOA HOLIDAY MEMO 9: Mistletoe in the mirror hall counts once per reflection. Please be " ..
		"reasonable.",
	"HOA HOLIDAY MEMO 10: Riley, the chimney is not a stage either.",
}

-- The next memo on the board at `pos`, which it now shows; told to `player`
-- too, when there is one. `memos` is the board's pile, the year-round one by
-- default.
function lw_maps.read_memo(pos, player, memos)
	memos = memos or lw_maps.HOA_MEMOS
	local meta = core.get_meta(pos)
	local index = meta:get_int("memo")
	if index == 0 then
		index = (pos.x * 3 + pos.z * 7) % #memos
	end
	index = index % #memos + 1
	meta:set_int("memo", index)
	local text = memos[index]
	meta:set_string("infotext", "HOA Memo\n" .. text)
	if player and player.is_player and player:is_player() then
		core.chat_send_player(player:get_player_name(), text)
	end
	return text
end

-- A notice board: `poster` is its face, `memos` the pile it reads from.
local function register_memo_board(name, description, poster, memos)
	register(name, {
		description = description .. "\nPunch or right click to read the next notice",
		drawtype = "nodebox",
		tiles = {"lw_frame.png", "lw_frame.png", "lw_frame.png", "lw_frame.png",
			"lw_frame.png", poster},
		paramtype = "light",
		paramtype2 = "facedir",
		sunlight_propagates = true,
		light_source = 3,
		on_place = core.rotate_node,
		node_box = MEMO_BOX,
		selection_box = MEMO_BOX,
		groups = {choppy = 2, oddly_breakable_by_hand = 2},
		on_construct = function(pos)
			core.get_meta(pos):set_string("infotext", MEMO_HINT)
		end,
		on_punch = function(pos, _, puncher)
			lw_maps.read_memo(pos, puncher, lw_maps[memos])
		end,
		on_rightclick = function(pos, _, clicker)
			lw_maps.read_memo(pos, clicker, lw_maps[memos])
		end,
	})
end

register_memo_board("hoa_memo", "HOA Memo", "lw_poster.png^[multiply:#f4ecd0", "HOA_MEMOS")
-- The holiday board: the same notice with a red and green border.
register_memo_board("hoa_holiday_memo", "HOA Holiday Memo",
	"lw_poster.png^[multiply:#f4ecd0^[fill:32x2:0,0:#c81e32^[fill:32x2:0,30:#c81e32" ..
		"^[fill:2x32:0,0:#1e8a3c^[fill:2x32:30,0:#1e8a3c", "HOA_HOLIDAY_MEMOS")

-- The serpent console, on the dais at the far end of the walk: punch it (or
-- right click it) and the laser show on its map changes pattern, for
-- everyone there. See "Shows" for the patterns.
register("serpent_switch", {
	description = "Serpent Console\nPunch or right click to change the laser pattern",
	tiles = {
		"lw_stone_brick.png^[multiply:#5a5054", "lw_stone_brick.png^[multiply:#5a5054",
		"lw_stone_brick.png^[multiply:#5a5054", "lw_stone_brick.png^[multiply:#5a5054",
		"lw_stone_brick.png^[multiply:#5a5054", "lw_lamp.png^[multiply:#ff2050",
	},
	paramtype = "light",
	paramtype2 = "facedir",
	light_source = 6,
	on_place = core.rotate_node,
	groups = {cracky = 2, oddly_breakable_by_hand = 2},
	on_construct = function(pos)
		core.get_meta(pos):set_string("infotext",
			"Serpent console: punch to change the laser pattern")
	end,
	on_punch = function(pos, _, puncher)
		lw_maps.punch_console(pos, puncher)
	end,
	on_rightclick = function(pos, _, clicker)
		lw_maps.punch_console(pos, clicker)
	end,
})

--------------------------------------------------------------------------
-- Waterfall cascade
--------------------------------------------------------------------------

-- A falling sheet of water that is not a liquid: an animated, glowing,
-- see-through node you can climb, so the cascade's five falls cost the WASM
-- worker no liquid simulation. The streams and pools it pours into are plain
-- lw_nodes:water, which never spreads. Not pointable, so a visitor reaching
-- for a geode behind the spray still gets the geode.
register("waterfall", {
	description = "Glowing Waterfall",
	drawtype = "glasslike",
	tiles = {{
		name = "lw_waterfall.png",
		backface_culling = false,
		animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 0.8},
	}},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 6,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	climbable = true,
	post_effect_color = {a = 90, r = 70, g = 200, b = 210},
	groups = {not_in_creative_inventory = 1},
})

-- Bioluminescent flora. Plantlike sprites are two quads each, the cheapest
-- thing there is to draw; the caps, stems, leaves and moss are palette tiles
-- re-tinted, like the wool cubes.
local function register_glow_plant(name, description, texture, light, box)
	register(name, {
		description = description,
		drawtype = "plantlike",
		tiles = {texture},
		inventory_image = texture,
		wield_image = texture,
		use_texture_alpha = "clip",
		paramtype = "light",
		sunlight_propagates = true,
		walkable = false,
		buildable_to = false,
		light_source = light,
		selection_box = {type = "fixed", fixed = box},
		groups = {snappy = 3, oddly_breakable_by_hand = 3},
	})
end

register_glow_plant("glow_shroom", "Glowing Toadstools", "lw_glow_shroom.png", 6,
	{-0.3, -0.5, -0.3, 0.3, 0.1, 0.3})
register_glow_plant("glow_fern", "Glowing Fern", "lw_glow_fern.png", 4,
	{-0.4, -0.5, -0.4, 0.4, 0.3, 0.4})
-- Morning glories hang from the clouds and the spring terrace's edge; the
-- petals that rain from under them are lw_maps' `showers`.
register_glow_plant("morning_glory", "Hanging Morning Glory", "lw_morning_glory.png", 5,
	{-0.35, -0.5, -0.35, 0.35, 0.5, 0.35})

register("glow_cap", {
	description = "Glowing Mushroom Cap",
	tiles = {"lw_wool.png^[multiply:#3ee8d0"},
	paramtype = "light",
	light_source = 11,
	groups = {snappy = 2, oddly_breakable_by_hand = 3},
})

register("glow_cap_violet", {
	description = "Glowing Mushroom Cap (violet)",
	tiles = {"lw_wool.png^[multiply:#b070ff"},
	paramtype = "light",
	light_source = 10,
	groups = {snappy = 2, oddly_breakable_by_hand = 3},
})

register("glow_stem", {
	description = "Mushroom Stem",
	tiles = {"lw_wool.png^[multiply:#e8e2f0"},
	paramtype = "light",
	light_source = 3,
	groups = {snappy = 2, oddly_breakable_by_hand = 3},
})

-- Glowing leaves, lit and dim, for the flicker controllers that make a few
-- of each canopy twinkle.
register("glow_leaves", {
	description = "Glowing Leaves",
	drawtype = "allfaces_optional",
	tiles = {"lw_leaves.png^[multiply:#46f0b0"},
	use_texture_alpha = "clip",
	paramtype = "light",
	light_source = 9,
	groups = {snappy = 3, oddly_breakable_by_hand = 3},
})

register("glow_leaves_dim", {
	description = "Glowing Leaves (dim)",
	drawtype = "allfaces_optional",
	tiles = {"lw_leaves.png^[multiply:#1c5a48"},
	use_texture_alpha = "clip",
	paramtype = "light",
	light_source = 3,
	groups = {snappy = 3, oddly_breakable_by_hand = 3},
})

-- The path's edging: moss that glows, lit and dim, under chase controllers
-- numbered from the causeway up, so pulses of light run up the path.
register("glow_moss", {
	description = "Glowing Moss",
	tiles = {"lw_grass_top.png^[multiply:#7affd8"},
	paramtype = "light",
	light_source = 8,
	groups = {crumbly = 3},
})

register("glow_moss_dim", {
	description = "Glowing Moss (dim)",
	tiles = {"lw_grass_top.png^[multiply:#2a6a58"},
	paramtype = "light",
	light_source = 2,
	groups = {crumbly = 3},
})

-- A soft cloud you can stand on, faintly lit from inside.
register("cloud", {
	description = "Cloud",
	tiles = {"lw_wool.png^[multiply:#f4f0ff"},
	paramtype = "light",
	light_source = 4,
	groups = {snappy = 3, oddly_breakable_by_hand = 3},
})

--------------------------------------------------------------------------
-- Christmas: the Christmas village and the Weeks on Fire Christmas
--------------------------------------------------------------------------

-- Palette tiles again, re-tinted, with ribbons and stripes painted on by
-- `[fill`, so the two Christmas islands add no textures either.

-- Wrapped presents: a box a little smaller than a node with a ribbon round
-- it both ways.
local PRESENT_BOX = {type = "fixed", fixed = {-0.4, -0.5, -0.4, 0.4, 0.25, 0.4}}
local RIBBON = "^[fill:2x16:7,0:%s^[fill:16x2:0,7:%s"
for _, present in ipairs({
	{"red", "Red", "#c81e32", "#ffd84a"},
	{"green", "Green", "#1e8a3c", "#f4f0e8"},
	{"blue", "Blue", "#2a4ec8", "#e8eef8"},
	{"gold", "Gold", "#e0b030", "#c81e32"},
	{"violet", "Violet", "#8a2ad8", "#7ff0ff"},
}) do
	local name, label, paper, ribbon = present[1], present[2], present[3], present[4]
	register("present_" .. name, {
		description = label .. " Present",
		drawtype = "nodebox",
		tiles = {"lw_wool.png^[multiply:" .. paper .. RIBBON:format(ribbon, ribbon)},
		paramtype = "light",
		node_box = PRESENT_BOX,
		selection_box = PRESENT_BOX,
		groups = {snappy = 3, oddly_breakable_by_hand = 3},
	})
end

-- Candy cane: white with red bands, for the arches and the path's posts.
register("candy_cane", {
	description = "Candy Cane Block",
	tiles = {"lw_wool.png^[multiply:#f8f4f0" ..
		"^[fill:16x3:0,0:#d01830^[fill:16x3:0,6:#d01830^[fill:16x3:0,12:#d01830"},
	groups = {snappy = 2, oddly_breakable_by_hand = 3},
})

-- Tree baubles, lit and dark, in three colours: a lamp pair per colour, so a
-- garland can chase round a tree and a scattering of them can twinkle under
-- `flicker`.
for _, bauble in ipairs({
	{"red", "Red", "#ff3040", "#4a0c12"},
	{"gold", "Gold", "#ffd040", "#4a3a10"},
	{"blue", "Blue", "#50a0ff", "#122a4a"},
}) do
	local name, label, lit, dark = bauble[1], bauble[2], bauble[3], bauble[4]
	register("bauble_" .. name, {
		description = label .. " Bauble",
		tiles = {"lw_lamp.png^[multiply:" .. lit},
		paramtype = "light",
		light_source = 11,
		groups = {cracky = 3, oddly_breakable_by_hand = 3},
	})
	register("bauble_" .. name .. "_off", {
		description = label .. " Bauble (dark)",
		tiles = {"lw_lamp.png^[multiply:" .. dark},
		groups = {cracky = 3, oddly_breakable_by_hand = 3},
	})
end

-- The star on top of a tree: the brightest light there is.
register("star", {
	description = "Tree Star",
	tiles = {"lw_gold.png^[multiply:#fff0a0"},
	paramtype = "light",
	light_source = 14,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
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
lw_maps.register_lamp_pair("lw_maps:serpent_scale", "lw_maps:serpent_scale_off")
lw_maps.register_lamp_pair("lw_maps:ember_block", "lw_maps:ember_block_off")
lw_maps.register_lamp_pair("lw_maps:crystal", "lw_maps:crystal_dim")
lw_maps.register_lamp_pair("lw_maps:glow_leaves", "lw_maps:glow_leaves_dim")
lw_maps.register_lamp_pair("lw_maps:glow_moss", "lw_maps:glow_moss_dim")
lw_maps.register_lamp_pair("lw_maps:bauble_red", "lw_maps:bauble_red_off")
lw_maps.register_lamp_pair("lw_maps:bauble_gold", "lw_maps:bauble_gold_off")
lw_maps.register_lamp_pair("lw_maps:bauble_blue", "lw_maps:bauble_blue_off")

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
-- of. Add `thunder = <sound>` and every strike is followed by that sound,
-- played at the rod. See "Storms" below.
--
-- `organ = {at = <local>, sound = <name>}` loops an optional soundtrack from
-- `at` for whoever is on the map, if its file has been dropped into
-- lw_maps/organ/. It is never part of the join-time media. See "Organ".
--
-- `amps = {left = <local>, right = <local>, song = <name>}` plays a song out
-- of the map's own amp cabs when someone walks onto it, and `lasers = {...}`
-- races lights and lasers round a track while anyone is there. See "Shows".
-- `playlist = <name>` in place of `song` plays the first song lw_amps has in
-- that playlist, and nothing while it has none.
--
-- `ambient = {{kind = "mist" | "spores" | "embers", min = <local>, max = <local>},
-- {kind = "snow"}, ...}` keeps a particle spawner going in each box for
-- whoever is on the map (snow needs no box: it falls round the visitor),
-- `showers = {period, length, colors, sources = {{min, max}, ...}}` rains
-- petals from each source in turn, and `eruption = {at, period, offset,
-- length, colors, rumble}` throws flowers out of `at` every `period` seconds.
-- All three are per player, on the storm's clock, and never saved. See
-- "Ambience".
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
	-- A stage tells lw_amps which cabs are its own, so punching one of them
	-- plays this map's song from this map, wherever the amps last pointed.
	local amps = rawget(_G, "lw_amps")
	if def.amps and amps and amps.register_stage then
		amps.register_stage({
			left = lw_maps.to_world(def, def.amps.left),
			right = lw_maps.to_world(def, def.amps.right),
			song = def.amps.song,
			playlist = def.amps.playlist,
			empty = def.amps.empty,
		})
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
	id = "halloween_storm",
	title = "Thunder chapel",
	blurb = "A roofless chapel with an organ loft, a graveyard and a " ..
		"mausoleum on a stormy Halloween night: lightning strikes the " ..
		"spire, the dead oak and the tomb, and thunder rolls after it.",
	size = {x = 36, y = 20, z = 36},
	origin = {x = -60, y = BASE, z = 77},
	spawn = {x = -41, y = BASE + 4, z = 77},
	-- Storm at night: darker than the lane's dusk, so a flash turns the whole
	-- island white, and fogged close, so the spire is a silhouette from the
	-- causeway until the lightning finds it.
	day_night_ratio = 0.1,
	sky = lw_maps.sky({
		sky = "#1c1626", horizon = "#3a2a3a",
		night_sky = "#0e0a16", night_horizon = "#241a26", indoors = "#140f1c",
		sun_tint = "#a05a2a", moon_tint = "#4a5a6a",
		fog = 64, fog_start = 0.3,
	}),
	-- The rainbow storm's rain and lightning, plus thunder. The rods are the
	-- fence posts on the spire, the dead oak in the graveyard and the
	-- mausoleum roof (STORM_CHAPEL_RODS in the generator), in that order.
	storm = {
		rods = {{x = 19, y = 19, z = 32}, {x = 5, y = 13, z = 26},
			{x = 30, y = 11, z = 21}},
		-- lw_thunder.1.ogg to .3.ogg in sounds/: a random group, so strikes
		-- do not all sound alike. Remove this line for a silent storm.
		thunder = "lw_thunder",
	},
	-- The soundtrack slot: a looping pipe-organ track out of the loft, over
	-- the console in front of the pipes. Ships empty: drop a mono Ogg Vorbis
	-- at lw_maps/organ/lw_maps_halloween_storm_organ.ogg and it plays; see
	-- organ/README.md. Nothing else in the pack knows the file exists.
	organ = {
		at = {x = 19, y = 12, z = 28},
		sound = "lw_maps_halloween_storm_organ",
		gain = 0.6,
		max_hear_distance = 48,
	},
})

lw_maps.register({
	id = "cabaret",
	title = "Cabaret club",
	blurb = "A dim, warm club at night: a velvet proscenium stage with " ..
		"chasing bulbs, where Rubella and Lillith perform, a dance floor, " ..
		"candlelit tables and a bar.",
	size = {x = 27, y = 11, z = 27},
	origin = {x = -100, y = BASE, z = -55},
	spawn = {x = -74, y = BASE + 4, z = -41},
	-- Late night under a deep red sky and close, warm fog: from the causeway
	-- the club is a dark box with a lit door, and inside it is its own lamps.
	day_night_ratio = 0.06,
	sky = lw_maps.sky({
		sky = "#2a0a12", horizon = "#5a1420",
		night_sky = "#16050a", night_horizon = "#3a0c14", indoors = "#1a0608",
		sun_tint = "#c0402a", moon_tint = "#7a2a3a",
		fog = 56, fog_start = 0.3,
	}),
	-- The sound sources, one node above the cabs on the stage's front
	-- corners, audience-left (south) first. There are no songs here yet: the
	-- cabaret plays whatever is in lw_amps' "cabaret" playlist, which is
	-- empty until songs are dropped into mods/lw_amps/cabaret/ (see the
	-- README there). Until then walking in plays nothing, and punching a cab
	-- says why.
	amps = {
		left = {x = 8, y = 6, z = 7},
		right = {x = 8, y = 6, z = 19},
		playlist = "cabaret",
		empty = "The cabaret has no songs yet: see " ..
			"games/luanti_web/mods/lw_amps/cabaret/README.md.",
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

lw_maps.register({
	id = "laser_serpent",
	title = "Laser serpent",
	blurb = "Weeks on Fire: a serpent of glowing scales coiled round an obelisk " ..
		"on a night ash field, lasers sweeping the neon walk past it, ember pits, " ..
		"and a console that changes the beams' pattern.",
	-- West of the smoke caldera, by a spur from the mouth of its basalt tube.
	size = {x = 35, y = 16, z = 35},
	origin = {x = -139, y = BASE, z = 23},
	spawn = {x = -105, y = BASE + 4, z = 40},
	-- Deep red and magenta night, light fog: the scales, the neon and the
	-- beams are the brightest things on the field.
	day_night_ratio = 0.1,
	sky = lw_maps.sky({
		sky = "#2a0620", horizon = "#7a1040",
		night_sky = "#160310", night_horizon = "#4a0a2a", indoors = "#1a0614",
		sun_tint = "#ff3080", moon_tint = "#a02060",
		fog = 96, fog_start = 0.5,
	}),
	-- The Around arena's show with three patterns, changed by punching the
	-- console: `coil` runs the emitters up the serpent's coil (the
	-- generator's COIL_* constants) with the beams slithering along the walk,
	-- `sweep` is the arena's race round the pylon caps, and `fan` throws every
	-- beam out of the serpent's mouth and swings them along the walk together.
	lasers = {
		patterns = {"coil", "sweep", "fan"},
		track = {x0 = 2, z0 = 2, x1 = 32, z1 = 32, y = 13},
		target = {x = 17, y = 4, z = 17, radius = 7},
		coil = {x = 17, z = 26, radius = 5, y0 = 4, rise = 9, turns = 2.25,
			start = -math.pi / 2},
		walk = {x0 = 7, x1 = 33, z = 17, y = 4, wave = 1.5},
		mouth = {x = 30, y = 11, z = 26},
		colors = {"#ff2050", "#ff40c8", "#ff8030", "#c070ff"},
		lap_beats = 32,
		bpm = 120,
	},
})

lw_maps.register({
	id = "mirror_hall",
	title = "Mirror hall",
	blurb = "Weeks on Fire: a vaulted hall of mirror tiles at twilight, a crystal " ..
		"skull under the vault, a gallery whose crystals chase round it, and " ..
		"lasers circling the skull.",
	-- East of the crystal bazaar, by a spur from the east end of its arcade.
	size = {x = 31, y = 18, z = 31},
	origin = {x = 100, y = BASE, z = 27},
	spawn = {x = 100, y = BASE + 4, z = 42},
	-- Twilight in violet and cyan: dark enough for the crystals, light enough
	-- that the reflecting pools still have a colour.
	day_night_ratio = 0.2,
	sky = lw_maps.sky({
		sky = "#2a1a5a", horizon = "#2a90a8",
		night_sky = "#140c34", night_horizon = "#145060", indoors = "#1a1240",
		sun_tint = "#60e0ff", moon_tint = "#a070ff",
		fog = 100, fog_start = 0.55,
	}),
	-- Three emitters circling under the vault, beams down round the skull.
	lasers = {
		track = {x0 = 10, z0 = 10, x1 = 24, z1 = 20, y = 11},
		target = {x = 17, y = 4, z = 15, radius = 5},
		colors = {"#40e0ff", "#c070ff", "#f0e0ff"},
		lap_beats = 32,
		bpm = 96,
	},
})

lw_maps.register({
	id = "waterfall_cascade",
	title = "Waterfall cascade",
	blurb = "A glowing river falling down five terraces under clouds hung with " ..
		"morning glories, bioluminescent mushrooms and trees, a volcano that " ..
		"erupts flowers, bikes to ride until they break and geodes full of gems.",
	-- South of the snowy mountain, by a spur from the south mouth of its tunnel.
	size = {x = 40, y = 28, z = 52},
	origin = {x = -20, y = BASE, z = -136},
	spawn = {x = -1, y = BASE + 4, z = -85},
	-- Soft violet twilight in a close, pale mist: light enough to see the
	-- falls from the causeway, dark enough that everything that glows does.
	day_night_ratio = 0.3,
	sky = lw_maps.sky({
		sky = "#4a4680", horizon = "#a088c0",
		night_sky = "#241f4a", night_horizon = "#5a4a80", indoors = "#2a2448",
		sun_tint = "#ffb0d8", moon_tint = "#90a8ff",
		fog = 72, fog_start = 0.25,
	}),
	-- Mist at the foot of each fall and the spring (CASCADE_TIERS and
	-- CASCADE_SPRING in the generator), spores over the mushroom grove.
	ambient = {
		{kind = "mist", min = {x = 17, y = 4, z = 38}, max = {x = 22, y = 5, z = 40}},
		{kind = "mist", min = {x = 17, y = 8, z = 31}, max = {x = 22, y = 9, z = 32}},
		{kind = "mist", min = {x = 17, y = 12, z = 24}, max = {x = 22, y = 13, z = 25}},
		{kind = "mist", min = {x = 17, y = 16, z = 17}, max = {x = 22, y = 17, z = 18}},
		{kind = "mist", min = {x = 18, y = 20, z = 11}, max = {x = 21, y = 21, z = 12}},
		{kind = "spores", min = {x = 1, y = 5, z = 44}, max = {x = 14, y = 10, z = 51}},
	},
	-- Petals from under each cloud's morning glories, and from the drape over
	-- the spring terrace's edge (CASCADE_CLOUDS, CASCADE_DRAPE), one after
	-- another round an 18-second cycle.
	showers = {
		period = 18,
		length = 5,
		colors = {"#c070ff", "#7a9aff", "#ff8ad0", "#f0e0ff"},
		sources = {
			{min = {x = 14, y = 11, z = 40}, max = {x = 24, y = 13, z = 46}},
			{min = {x = 13, y = 17, z = 28}, max = {x = 25, y = 19, z = 34}},
			{min = {x = 27, y = 20, z = 18}, max = {x = 35, y = 22, z = 22}},
			{min = {x = 25, y = 16, z = 17}, max = {x = 37, y = 18, z = 17}},
		},
	},
	-- Every half minute the volcano throws flowers out of its crater
	-- (CASCADE_CRATER), north over the falls, with a low rumble.
	eruption = {
		at = {x = 20, y = 26, z = 2},
		period = 30,
		offset = 7,
		length = 3,
		colors = {"#ff5ab0", "#ffd040", "#b070ff", "#60f0d0"},
		-- The thunder chapel's thunder, pitched down. Remove for a silent one.
		rumble = "lw_thunder",
	},
})

lw_maps.register({
	id = "christmas",
	title = "Christmas village",
	blurb = "A snowed-in square at twilight: a tall tree whose baubles chase round " ..
		"it in a garland, presents round its foot and a star on top, a workshop " ..
		"cabin with a fire, a sleigh and its reindeer, a frozen pond and snowmen.",
	-- East of the giant fruit garden, by a spur from the east end of its path.
	size = {x = 40, y = 24, z = 40},
	origin = {x = 103, y = BASE, z = -27},
	spawn = {x = 103, y = BASE + 4, z = -7},
	-- Blue twilight, a little fog: dark enough for the lights, light enough
	-- that the snow is still white.
	day_night_ratio = 0.24,
	sky = lw_maps.sky({
		sky = "#1e2c5e", horizon = "#8aa0d8",
		night_sky = "#0c1434", night_horizon = "#3a4a80", indoors = "#141c40",
		sun_tint = "#ffd0a0", moon_tint = "#a0b8ff",
		fog = 120, fog_start = 0.5,
	}),
	-- Snow falling round whoever is there.
	ambient = {{kind = "snow"}},
})

lw_maps.register({
	id = "wof_christmas",
	title = "Weeks on Fire Christmas",
	blurb = "Weeks on Fire: Christmas on a night of snow and ash. A tree on fire and " ..
		"festive anyway, lasers spiralling up it, a mirror colonnade, a cabaret " ..
		"stage with a holiday revue set, a mirror ball and the HOA's holiday memos.",
	-- South of the laser serpent, by a spur from the south side of its field.
	size = {x = 36, y = 22, z = 40},
	origin = {x = -141, y = BASE, z = -27},
	spawn = {x = -123, y = BASE + 4, z = 12},
	-- Magenta and red night in a light fog: the embers, the neon and the
	-- beams are the brightest things there.
	day_night_ratio = 0.12,
	sky = lw_maps.sky({
		sky = "#2a0830", horizon = "#b01c5c",
		night_sky = "#140418", night_horizon = "#5a0c3a", indoors = "#1a0620",
		sun_tint = "#ff4080", moon_tint = "#a040ff",
		fog = 88, fog_start = 0.45,
	}),
	-- Snow round the visitor; embers rising off the burning tree
	-- (WOF_XMAS_TREE in the generator).
	ambient = {
		{kind = "snow"},
		{kind = "embers", min = {x = 14, y = 8, z = 20}, max = {x = 22, y = 16, z = 28}},
	},
	-- The serpent's show, on a tree: `coil` runs the emitters up a helix
	-- round the tree (WOF_XMAS_COIL) with the beams on the dance floor, and
	-- `sweep` races them round the pylon caps. The console on the stage
	-- switches between them.
	lasers = {
		patterns = {"coil", "sweep"},
		track = {x0 = 2, z0 = 2, x1 = 33, z1 = 37, y = 15},
		target = {x = 18, y = 4, z = 24, radius = 8},
		coil = {x = 18, z = 24, radius = 7, y0 = 5, rise = 11, turns = 3,
			start = math.pi / 2},
		walk = {x0 = 9, x1 = 26, z = 11, y = 4, wave = 1.5},
		colors = {"#ff2050", "#40ff80", "#ff40c8", "#ffd040"},
		lap_beats = 32,
		bpm = 120,
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
-- Thunder lags the flash the way it does outdoors, by distance: this long at
-- the rod, a little more for every node between the visitor and the strike,
-- and never more than the cap, so it still belongs to its own flash.
local THUNDER_DELAY = 0.25
local THUNDER_LAG = 0.02
local THUNDER_DELAY_MAX = 1.5
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

function lw_maps.thunder_delay(distance)
	return math.min(THUNDER_DELAY + distance * THUNDER_LAG, THUNDER_DELAY_MAX)
end

-- One short, mono, positional sample at the strike, for the one player who
-- saw it. It is ephemeral (a couple of seconds, never stopped), so leaving
-- needs no cleanup beyond the check that they are still on the map when it is
-- due. Sound is optional, as everywhere in the pack: no sound_play, or a
-- missing file, is a silent storm.
local function thunder(player, map, top)
	if type(core.sound_play) ~= "function" then
		return
	end
	local name = player:get_player_name()
	local delay = lw_maps.thunder_delay(vector.distance(player:get_pos(), top))
	core.after(delay, function()
		if current[name] ~= map.id or type(core.sound_play) ~= "function" then
			return
		end
		pcall(core.sound_play, map.storm.thunder, {
			pos = top, to_player = name, gain = 0.7, max_hear_distance = 80,
		}, true)
	end)
end

local function flash(player, map, k)
	local name = player:get_player_name()
	local rods = map.storm.rods
	local rod = rods[k % #rods + 1]
	local top = vector.offset(lw_maps.to_world(map, rod), 0, 0.5, 0)
	bolt(name, top, k)
	if map.storm.thunder then
		thunder(player, map, top)
	end
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
-- Ambience
--------------------------------------------------------------------------

-- Particles a map wants while someone is on it, per player like the rain, so
-- the worker only ever draws what one visitor can see and nothing is saved.
--
-- `ambient` boxes keep a spawner running for as long as the visitor stays.
-- `showers` and `eruption` are bursts on the storm's clock, whole seconds of
-- core.get_gametime(), so every visitor sees the same shower from the same
-- cloud and the same eruption at the same moment, and a reload needs no state.
lw_maps.AMBIENT_KINDS = {
	-- Spray thrown up off a pool at the foot of a fall.
	mist = {
		amount = 5,
		minvel = {x = -0.3, y = 0.2, z = 0.1}, maxvel = {x = 0.3, y = 0.8, z = 0.9},
		minexptime = 1.5, maxexptime = 2.5,
		minsize = 5, maxsize = 9,
		texture = "lw_mist.png",
		glow = 7,
	},
	-- Glowing spores drifting up out of a grove.
	spores = {
		amount = 4,
		minvel = {x = -0.15, y = 0.15, z = -0.15}, maxvel = {x = 0.15, y = 0.45, z = 0.15},
		minexptime = 4, maxexptime = 7,
		minsize = 1, maxsize = 1.8,
		texture = "lw_mist.png^[multiply:#7affd8",
		glow = 13,
	},
	-- Snow, falling slowly round the visitor. Like the storm's rain it is
	-- attached to them, a box over their head rather than over the island, so
	-- the worker only draws the flakes one person can see; its box is the
	-- kind's own, relative to the visitor, and the registry entry names no
	-- box at all.
	snow = {
		attached = true,
		amount = 24,
		minpos = {x = -8, y = 3, z = -8}, maxpos = {x = 8, y = 7, z = 8},
		minvel = {x = -0.35, y = -1.4, z = -0.25}, maxvel = {x = 0.35, y = -0.9, z = 0.25},
		minexptime = 4, maxexptime = 6,
		minsize = 0.8, maxsize = 1.8,
		collisiondetection = true,
		collision_removal = true,
		texture = "lw_mist.png",
		glow = 6,
	},
	-- Embers rising off something that is on fire and does not burn.
	embers = {
		amount = 6,
		minvel = {x = -0.2, y = 0.8, z = -0.2}, maxvel = {x = 0.2, y = 1.6, z = 0.2},
		minacc = {x = -0.1, y = 0, z = -0.1}, maxacc = {x = 0.1, y = 0.2, z = 0.1},
		minexptime = 1.5, maxexptime = 3,
		minsize = 0.6, maxsize = 1.2,
		texture = "lw_mist.png^[multiply:#ff6a20",
		glow = 14,
	},
}

local ambience = {}      -- player name -> {map = id, ids = {spawner id, ...}}
local last_burst = {}    -- player name -> gametime second last handled

local function local_box(map, box)
	return lw_maps.to_world(map, box.min), lw_maps.to_world(map, box.max)
end

local function start_ambient(player, map)
	local ids = {}
	for _, box in ipairs(map.ambient) do
		local kind = lw_maps.AMBIENT_KINDS[box.kind]
		if kind then
			local def = table.copy(kind)
			def.time = 0
			if kind.attached then
				def.attached = player
			else
				def.minpos, def.maxpos = local_box(map, box)
			end
			def.playername = player:get_player_name()
			ids[#ids + 1] = core.add_particlespawner(def)
		end
	end
	return ids
end

local function stop_ambient(name)
	local have = ambience[name]
	if not have then
		return
	end
	for _, id in ipairs(have.ids) do
		core.delete_particlespawner(id)
	end
	ambience[name] = nil
end

local function update_ambient(player, map)
	local name = player:get_player_name()
	local want = map and map.ambient and map.id or nil
	local have = ambience[name]
	if have and have.map == want then
		return
	end
	stop_ambient(name)
	if want then
		ambience[name] = {map = want, ids = start_ambient(player, map)}
	end
end

function lw_maps.ambient_spawners(name)
	return ambience[name] and ambience[name].ids or nil
end

-- Which shower sources shed their petals at whole second `t`: source i (from
-- 1) starts at (i - 1) / #sources of the way round the cycle.
function lw_maps.showers_due(showers, t)
	local due = {}
	local count = #showers.sources
	for index = 1, count do
		if t % showers.period == math.floor((index - 1) * showers.period / count) then
			due[#due + 1] = index
		end
	end
	return due
end

function lw_maps.eruption_due(eruption, t)
	return t % eruption.period == (eruption.offset or 0) % eruption.period
end

local function shower(name, map, index, t)
	local showers = map.showers
	local source = showers.sources[index]
	local minpos, maxpos = local_box(map, source)
	local color = showers.colors[(index + math.floor(t / showers.period)) %
		#showers.colors + 1]
	core.add_particlespawner({
		amount = 36,
		time = showers.length,
		minpos = minpos, maxpos = maxpos,
		minvel = {x = -0.4, y = -1.2, z = -0.4}, maxvel = {x = 0.4, y = -0.6, z = 0.4},
		minacc = {x = -0.3, y = -0.2, z = -0.3}, maxacc = {x = 0.3, y = 0, z = 0.3},
		minexptime = 5, maxexptime = 7,
		minsize = 1.5, maxsize = 2.5,
		collisiondetection = true,
		collision_removal = true,
		texture = "lw_petal.png^[multiply:" .. color,
		glow = 5,
		playername = name,
	})
end

-- One eruption, seen by one player: a spray of flowers per colour out of the
-- crater, thrown up and north over the falls, falling back slowly enough to
-- drift down over the whole island, gone when they land.
local function erupt(player, map)
	local eruption = map.eruption
	local name = player:get_player_name()
	local at = lw_maps.to_world(map, eruption.at)
	for _, color in ipairs(eruption.colors) do
		core.add_particlespawner({
			amount = 30,
			time = eruption.length,
			minpos = vector.offset(at, -0.6, 0, -0.6),
			maxpos = vector.offset(at, 0.6, 0.5, 0.6),
			minvel = {x = -3, y = 9, z = -1}, maxvel = {x = 3, y = 14, z = 6},
			minacc = {x = 0, y = -4, z = 0}, maxacc = {x = 0, y = -3.5, z = 0},
			minexptime = 8, maxexptime = 11,
			minsize = 3, maxsize = 5,
			collisiondetection = true,
			collision_removal = true,
			texture = "lw_bloom.png^[multiply:" .. color,
			glow = 10,
			playername = name,
		})
	end
	if eruption.rumble and type(core.sound_play) == "function" then
		pcall(core.sound_play, eruption.rumble, {
			pos = at, to_player = name, gain = 0.5, pitch = 0.55,
			max_hear_distance = 96,
		}, true)
	end
end

local function burst_step()
	local now = core.get_gametime and core.get_gametime()
	if not now then
		return
	end
	now = math.floor(now)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local map = lw_maps.by_id[current[name] or ""]
		if map and (map.showers or map.eruption) and last_burst[name] ~= now then
			last_burst[name] = now
			if map.showers then
				for _, index in ipairs(lw_maps.showers_due(map.showers, now)) do
					shower(name, map, index, now)
				end
			end
			if map.eruption and lw_maps.eruption_due(map.eruption, now) then
				erupt(player, map)
			end
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

-- What a stage plays: its song, or the first in its playlist; nil when a
-- playlist has nothing in it yet, and then the stage stays quiet.
local function stage_song(map)
	local amps = amps_mod()
	if amps and amps.stage_song then
		return amps.stage_song(map.amps)
	end
	return map.amps.song
end

local function start_song(map)
	local amps = amps_mod()
	if not (amps and amps.play) or amps.now_playing() then
		return
	end
	local song = stage_song(map)
	if not song then
		return
	end
	amps.set_amps(stage_sources(map))
	amps.play(song)
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

-- Patterns. A map whose `lasers` has `patterns = {...}` cycles through them
-- when its console (lw_maps:serpent_switch) is punched; a map without starts
-- and stays on `sweep`, the arenas' race round the truss.
--
--  * `sweep`: round `track`, beams onto a point circling `target`.
--  * `coil`: up the helix `coil = {x, z, radius, y0, rise, turns, start}`,
--    tail to neck, a lap each, beams onto points slithering along
--    `walk = {x0, x1, z, y, wave}` the other way.
--  * `fan`: every emitter in `mouth`, beams swinging along `walk` together.
--
-- The pattern is the server's, not a player's: everyone on the map sees the
-- same beams, as with the clock. It is not saved; a restart starts again on
-- the first pattern.
local pattern_turns = {}    -- map id -> how many times its console was punched

function lw_maps.laser_pattern(map)
	local patterns = map.lasers and map.lasers.patterns
	if not patterns or #patterns == 0 then
		return "sweep"
	end
	return patterns[(pattern_turns[map.id] or 0) % #patterns + 1]
end

function lw_maps.next_laser_pattern(map)
	pattern_turns[map.id] = (pattern_turns[map.id] or 0) + 1
	return lw_maps.laser_pattern(map)
end

-- How far above the coil's centre line an emitter climbs: clear of the scale
-- and the chase controller on it. The generator's coil_point is the same line.
local COIL_RIDE = 1.3

function lw_maps.coil_point(coil, s)
	local angle = coil.start + s * coil.turns * 2 * math.pi
	return coil.x + coil.radius * math.cos(angle), coil.y0 + s * coil.rise,
		coil.z + coil.radius * math.sin(angle)
end

-- On a floor's top face, a hair above it so the spot does not z-fight.
local function on_floor(map, x, y, z)
	return lw_maps.to_world(map, {x = x, y = y - 0.48, z = z})
end

-- Emitter `index` at show time `t`: where it is and where its beam lands.
function lw_maps.laser_frame(map, t, index)
	local lasers = map.lasers
	local lap = lasers.lap_beats * 60 / lasers.bpm
	local count = #lasers.colors
	local phase = (index - 1) / count
	local pattern = lw_maps.laser_pattern(map)
	if pattern == "coil" then
		local s = (t / lap + phase) % 1
		local x, y, z = lw_maps.coil_point(lasers.coil, s)
		local walk = lasers.walk
		local u = (phase - 2 * t / lap) % 1
		return lw_maps.to_world(map, {x = x, y = y + COIL_RIDE, z = z}),
			on_floor(map, walk.x0 + (walk.x1 - walk.x0) * u, walk.y,
				walk.z + walk.wave * math.sin(2 * math.pi * (3 * u + t / lap)))
	elseif pattern == "fan" then
		local mouth, walk = lasers.mouth, lasers.walk
		local spread = index - (count + 1) / 2
		local swing = math.sin(2 * math.pi * 2 * t / lap + phase * math.pi)
		return lw_maps.to_world(map, {x = mouth.x, y = mouth.y, z = mouth.z + spread * 0.3}),
			on_floor(map, (walk.x0 + walk.x1) / 2 + (walk.x1 - walk.x0) / 2 * swing,
				walk.y, walk.z + spread * 0.6)
	end
	local x, z = lw_maps.track_point(lasers.track,
		(t / lap + phase) * lw_maps.track_length(lasers.track))
	local from = lw_maps.to_world(map, {x = x, y = lasers.track.y + EMITTER_RISE, z = z})
	local target = lasers.target
	local angle = (phase - 2 * t / lap) * 2 * math.pi
	return from, on_floor(map, target.x + target.radius * math.cos(angle), target.y,
		target.z + target.radius * math.sin(angle))
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
-- floor sees it broadside rather than edge on. Returns the sprite's centre,
-- its rotation and its length, or nil for a beam too short to draw. Public:
-- lw_tools' Laser Wand poses its beams with it.
function lw_maps.beam_pose(from, to)
	local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-3 then
		return nil
	end
	local flat = math.sqrt(dx * dx + dz * dz)
	local dir = vector.new(dx / length, dy / length, dz / length)
	-- Straight up or down there is no heading to be side-on to; any
	-- horizontal face will do.
	local side = flat < 1e-3 and vector.new(1, 0, 0) or vector.new(dz / flat, 0, -dx / flat)
	return vector.new((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2),
		vector.dir_to_rotation(side, dir), length
end

local function pose_beam(slot, from, to)
	local centre, rotation, length = lw_maps.beam_pose(from, to)
	if not centre then
		return
	end
	slot.beam:move_to(centre, true)
	slot.beam:set_rotation(rotation)
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

-- The serpent console: the next pattern for the show on the map it stands on,
-- told to everyone there. Returns the pattern, or nil off a map with patterns.
local PATTERN_NAMES = {
	coil = "the lasers climb the coil and slither along the walk",
	sweep = "the lasers race round the pylons and sweep the field",
	fan = "the serpent breathes every laser at once, along the walk",
}

function lw_maps.punch_console(pos, player)
	local map = lw_maps.at(pos)
	if not (map and map.lasers and map.lasers.patterns) then
		if player and player.is_player and player:is_player() then
			core.chat_send_player(player:get_player_name(),
				"The console is dead: it only works on a map with a laser show.")
		end
		return nil
	end
	local pattern = lw_maps.next_laser_pattern(map)
	local text = "The serpent turns: " .. (PATTERN_NAMES[pattern] or pattern) .. "."
	for _, other in ipairs(core.get_connected_players()) do
		if current[other:get_player_name()] == map.id or other == player then
			core.chat_send_player(other:get_player_name(), text)
		end
	end
	return pattern
end

--------------------------------------------------------------------------
-- Organ
--------------------------------------------------------------------------

-- A map with `organ` loops one optional track from one place while a visitor
-- is on it: the thunder chapel's slot for a pipe-organ soundtrack. The pack
-- ships the slot, not the music.
--
-- The file lives in lw_maps/organ/, not lw_maps/sounds/. The engine only
-- collects media from a mod's textures, sounds, models and media folders, so
-- a track in organ/ is not in the media every client downloads and checksums
-- when it joins. Instead it is pushed to one visitor with
-- core.dynamic_add_media the first time they walk onto the map, and played
-- once their client says it has it. Nobody who never visits pays for it.
--
-- Per player, like the storm: each visitor gets their own looping handle,
-- started on arrival and faded out when they leave. No file, no sound_play,
-- or no dynamic_add_media, and the chapel is simply quiet.
local ORGAN_DIR = core.get_modpath("lw_maps") .. "/organ/"

local organ_files = {}   -- sound -> path, or false when it is not there
local organ_sent = {}    -- player name -> {[sound] = "pending" | true}
local organ_playing = {} -- player name -> {map = id, handle = sound handle}

-- The track's path, or nil. Looked for once: a file dropped in later is
-- picked up on the next server start, the same as any other media.
function lw_maps.organ_file(map)
	local sound = map.organ.sound
	if organ_files[sound] == nil then
		local path = ORGAN_DIR .. sound .. ".ogg"
		local file = io.open(path, "rb")
		if file then
			file:close()
		end
		organ_files[sound] = file and path or false
	end
	return organ_files[sound] or nil
end

local function play_organ(name, map)
	if current[name] ~= map.id or organ_playing[name]
			or type(core.sound_play) ~= "function" then
		return
	end
	local organ = map.organ
	local ok, handle = pcall(core.sound_play, organ.sound, {
		pos = lw_maps.to_world(map, organ.at),
		to_player = name,
		gain = organ.gain or 0.6,
		max_hear_distance = organ.max_hear_distance or 48,
		loop = true,
	})
	if ok and handle then
		organ_playing[name] = {map = map.id, handle = handle}
	end
end

local function start_organ(player, map)
	if type(core.dynamic_add_media) ~= "function" then
		return
	end
	local name, sound = player:get_player_name(), map.organ.sound
	local sent = organ_sent[name] or {}
	organ_sent[name] = sent
	if sent[sound] == true then
		play_organ(name, map)
		return
	end
	if sent[sound] == "pending" then
		return
	end
	local path = lw_maps.organ_file(map)
	if not path then
		return
	end
	sent[sound] = "pending"
	-- Not ephemeral, so the same file can go to every visitor in turn; not
	-- cached, so a browser does not write a second copy of it to IndexedDB.
	local ok, accepted = pcall(core.dynamic_add_media, {
		filepath = path, to_player = name, client_cache = false,
	}, function(who)
		if organ_sent[who] then
			organ_sent[who][sound] = true
			play_organ(who, map)
		end
	end)
	if not (ok and accepted) then
		sent[sound] = nil
	end
end

local function stop_organ(name)
	local playing = organ_playing[name]
	if not playing then
		return
	end
	organ_playing[name] = nil
	if type(core.sound_fade) == "function" then
		pcall(core.sound_fade, playing.handle, 1.5, 0)
	elseif type(core.sound_stop) == "function" then
		pcall(core.sound_stop, playing.handle)
	end
end

local function update_organ(player, map)
	local name = player:get_player_name()
	local playing = organ_playing[name]
	if playing and not (map and map.id == playing.map) then
		stop_organ(name)
	end
	if map and map.organ and not organ_playing[name] then
		start_organ(player, map)
	end
end

local ATMOSPHERE_INTERVAL = 0.5
local elapsed = 0

core.register_globalstep(function(dtime)
	storm_step()
	burst_step()
	show_step(dtime)
	elapsed = elapsed + dtime
	if elapsed < ATMOSPHERE_INTERVAL then
		return
	end
	elapsed = 0
	local visitors = {}
	local arrived = {}
	for _, player in ipairs(core.get_connected_players()) do
		local was = current[player:get_player_name()]
		local map = lw_maps.at(player:get_pos())
		apply(player, map)
		update_rain(player, map)
		update_ambient(player, map)
		update_organ(player, map)
		if map then
			visitors[map.id] = (visitors[map.id] or 0) + 1
			-- Arriving, by causeway, by /maps or by joining there, is what
			-- starts a stage's song: staying does not restart one a visitor
			-- stopped by punching a cab.
			if map.amps and map.id ~= was then
				arrived[#arrived + 1] = map
			end
		end
	end
	-- Songs on stages nobody is on any more stop first, so a visitor who
	-- goes straight from one stage to another (by /maps) hears the new one.
	update_shows(visitors)
	for _, map in ipairs(arrived) do
		start_song(map)
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	current[name] = nil
	if rain[name] then
		core.delete_particlespawner(rain[name].id)
		rain[name] = nil
	end
	last_flash[name] = nil
	stop_ambient(name)
	last_burst[name] = nil
	stop_organ(name)
	organ_sent[name] = nil
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

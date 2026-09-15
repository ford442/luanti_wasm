-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The showcase world.
--
-- The map is *authored*, not procedural, but it is not a committed map
-- database either: the layout below is the source of truth and the world is
-- stamped out of it on a singlenode mapgen the first time each chunk is
-- generated. That keeps the repository small, keeps the build reproducible,
-- and means editing this file changes the landing world on the next fresh
-- world instead of requiring a map blob to be regenerated and committed.
--
-- Walking tour, south to north:
--
--             [ theater ]                z = 34..62
--                  |
--   [ library ]--[ courtyard ]--[ gallery ]    z = 4..32
--                  |
--             [ plaza ]                   z = -18..4   (spawn)
--
-- Everything fits in x = -36..36, z = -22..66, y = 0..30 — small enough to
-- walk in about a minute and small enough for the WASM heap budget documented
-- in wasm_porting.md.

lw_world = {}

local FONT = dofile(core.get_modpath("lw_world") .. DIR_DELIM .. "font.lua")

--------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------

local GROUND = 8            -- topmost solid ground node
local FLOOR = GROUND + 1    -- first walkable layer
local WATER = GROUND - 1    -- moat surface

local ISLAND = {x0 = -36, z0 = -22, x1 = 36, z1 = 66}
local BOUNDS = {
	min = {x = ISLAND.x0 - 8, y = 0, z = ISLAND.z0 - 8},
	max = {x = ISLAND.x1 + 8, y = 34, z = ISLAND.z1 + 8},
}

local SPAWN = {x = 0, y = FLOOR + 1, z = -14}

-- Theater screen: 6 columns x 4 rows of cells on the north wall. The audience
-- looks north (+z), so from their point of view east (+x) is to the right and
-- the top-left cell is the westmost one on the top row.
local SCREEN_Z = 60
local SCREEN_TOP = FLOOR + 8
local SCREEN_X0 = -3

--------------------------------------------------------------------------
-- Build op list
--------------------------------------------------------------------------

-- Ops are axis-aligned boxes resolved against whatever chunk is being
-- generated, so a chunk only pays for the ops that actually touch it. The
-- alternative — scanning every node of every chunk and asking "what goes
-- here?" — costs the same work whether or not the chunk has anything in it.
--
-- Later ops overwrite earlier ones, so the list reads like a build order:
-- ground, then shell, then openings, then fittings.
local ops = {}
local labels = {}

local function fill(x0, y0, z0, x1, y1, z1, name, param2)
	ops[#ops + 1] = {
		x0 = math.min(x0, x1), y0 = math.min(y0, y1), z0 = math.min(z0, z1),
		x1 = math.max(x0, x1), y1 = math.max(y0, y1), z1 = math.max(z0, z1),
		name = name, param2 = param2,
	}
end

local function put(x, y, z, name, param2)
	fill(x, y, z, x, y, z, name, param2)
end

-- Four vertical walls of a room: no floor, no ceiling.
local function walls(x0, y0, z0, x1, y1, z1, name)
	fill(x0, y0, z0, x1, y1, z0, name)
	fill(x0, y0, z1, x1, y1, z1, name)
	fill(x0, y0, z0, x0, y1, z1, name)
	fill(x1, y0, z0, x1, y1, z1, name)
end

-- Rectangular outline drawn *inside* a single wall plane (constant z). walls()
-- cannot do this: with z0 == z1 its four boxes collapse into one filled slab.
local function outline_z(x0, y0, x1, y1, z, name)
	fill(x0, y0, z, x1, y0, z, name)
	fill(x0, y1, z, x1, y1, z, name)
	fill(x0, y0, z, x0, y1, z, name)
	fill(x1, y0, z, x1, y1, z, name)
end

local function label(x, y, z, text)
	labels[#labels + 1] = {pos = {x = x, y = y, z = z}, text = text}
end

local function text_width(text, scale)
	return (#text * (FONT.glyph_width + 1) - 1) * (scale or 1)
end

-- Spell `text` into wool nodes on a wall plane.
--
-- `axis` is the direction letters advance in ("x" or "z") and `dir` is +1 or
-- -1 along it. Which combination reads correctly depends on where the reader
-- stands: Luanti is left-handed with +x east and +z north, so a viewer facing
-- north reads +x, facing south reads -x, facing west reads +z, facing east
-- reads -z.
local function write_text(x, y, z, text, color, axis, dir, scale)
	scale = scale or 1
	dir = dir or 1
	local node = "lw_nodes:wool_" .. color
	local cursor = 0
	for index = 1, #text do
		local glyph = FONT.glyphs[text:sub(index, index):upper()]
		if glyph then
			for row = 1, FONT.glyph_height do
				local bits = glyph[row]
				for col = 1, FONT.glyph_width do
					if bits:sub(col, col) == "1" then
						for sy = 0, scale - 1 do
							for sx = 0, scale - 1 do
								local offset = ((cursor + col - 1) * scale + sx) * dir
								local oy = y - (row - 1) * scale - sy
								if axis == "x" then
									put(x + offset, oy, z, node)
								else
									put(x, oy, z + offset, node)
								end
							end
						end
					end
				end
			end
		end
		cursor = cursor + FONT.glyph_width + 1
	end
end

--------------------------------------------------------------------------
-- The island
--------------------------------------------------------------------------

local function build_island()
	-- Moat first, so the island overwrites it where they overlap.
	fill(BOUNDS.min.x, 0, BOUNDS.min.z, BOUNDS.max.x, WATER, BOUNDS.max.z,
		"lw_nodes:water")
	-- Sand shelf, then the plateau on top of it.
	fill(ISLAND.x0 - 3, 0, ISLAND.z0 - 3, ISLAND.x1 + 3, GROUND - 1, ISLAND.z1 + 3,
		"lw_nodes:stone")
	fill(ISLAND.x0 - 3, GROUND, ISLAND.z0 - 3, ISLAND.x1 + 3, GROUND, ISLAND.z1 + 3,
		"lw_nodes:sand")
	fill(ISLAND.x0, 0, ISLAND.z0, ISLAND.x1, GROUND - 2, ISLAND.z1, "lw_nodes:stone")
	fill(ISLAND.x0, GROUND - 1, ISLAND.z0, ISLAND.x1, GROUND - 1, ISLAND.z1,
		"lw_nodes:dirt")
	fill(ISLAND.x0, GROUND, ISLAND.z0, ISLAND.x1, GROUND, ISLAND.z1,
		"lw_nodes:dirt_with_grass")
end

--------------------------------------------------------------------------
-- 1. Spawn plaza
--------------------------------------------------------------------------

local PLAZA = {x0 = -12, x1 = 12, z0 = -18, z1 = 4}

local function build_plaza()
	local x0, x1, z0, z1 = PLAZA.x0, PLAZA.x1, PLAZA.z0, PLAZA.z1

	fill(x0, GROUND, z0, x1, GROUND, z1, "lw_nodes:paving")
	-- A shallow lip so the plaza reads as a built surface, not mown grass.
	walls(x0 - 1, GROUND, z0 - 1, x1 + 1, GROUND, z1 + 1, "lw_nodes:polished_stone")

	-- Colonnade down both sides.
	for z = z0 + 2, z1 - 6, 4 do
		for _, x in ipairs({x0 + 1, x1 - 1}) do
			fill(x, FLOOR, z, x, FLOOR + 3, z, "lw_nodes:column")
			put(x, FLOOR + 4, z, "lw_nodes:gold_trim")
			put(x, FLOOR + 5, z, "lw_nodes:lamp")
		end
	end

	-- Fountain: a ring of polished stone around still water, with a lip so a
	-- visitor walks around it instead of straight into it.
	walls(-3, GROUND, -8, 3, FLOOR, -2, "lw_nodes:polished_stone")
	fill(-2, GROUND, -7, 2, GROUND, -3, "lw_nodes:water")

	-- Welcome sign just north of the spawn point, where a visitor already
	-- looking up the plaza will see its face. Poster panels face south at
	-- facedir 0, so it has to stand in front of the player, not behind.
	put(4, FLOOR, -13, "lw_nodes:pedestal")
	put(4, FLOOR + 1, -13, "lw_nodes:poster")
	label(4, FLOOR + 1, -13,
		"Welcome to the Luanti web showcase. Walk north through the arch: " ..
		"library to the west, gallery to the east, then the theater. " ..
		"Press i for the palette, /stuff for the starter kit.")

	-- North gate and banner. This is the first thing a visitor sees from the
	-- spawn point, so the title goes on the wall above the arch rather than
	-- painted on the floor where nobody would read it.
	local top = FLOOR + 16
	fill(x0, FLOOR, z1, x1, top, z1, "lw_nodes:stone_brick")
	fill(x0 + 1, FLOOR + 6, z1 - 1, x1 - 1, top, z1 - 1, "lw_nodes:stone_brick")
	fill(-3, FLOOR, z1, 3, FLOOR + 4, z1, "air")             -- archway
	fill(-4, FLOOR + 5, z1, 4, FLOOR + 5, z1, "lw_nodes:gold_trim")
	-- Two lines, read from the plaza side (facing north, so letters run +x).
	write_text(-math.floor(text_width("LUANTI") / 2), top, z1 - 1, "LUANTI",
		"white", "x", 1)
	write_text(-math.floor(text_width("WEB") / 2), top - 6, z1 - 1, "WEB",
		"cyan", "x", 1)
	for _, x in ipairs({x0, x1}) do
		fill(x, FLOOR, z1, x, top + 1, z1, "lw_nodes:column")
		put(x, top + 2, z1, "lw_nodes:lamp")
	end
end

--------------------------------------------------------------------------
-- 2. Material library
--------------------------------------------------------------------------

local LIBRARY = {x0 = -32, x1 = -16, z0 = 4, z1 = 32}

-- Filled at load time from every node carrying the lw_palette group, so a new
-- palette node appears in the library without anyone editing this file.
local function palette_names()
	local names = {}
	for name, def in pairs(core.registered_nodes) do
		if def.groups and def.groups.lw_palette then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

local function build_library()
	local x0, x1, z0, z1 = LIBRARY.x0, LIBRARY.x1, LIBRARY.z0, LIBRARY.z1

	fill(x0, GROUND, z0, x1, GROUND, z1, "lw_nodes:polished_stone")
	fill(x0, FLOOR, z0, x1, FLOOR + 5, z1, "air")
	walls(x0, FLOOR, z0, x1, FLOOR + 5, z1, "lw_nodes:stone_brick")
	-- Clerestory glass: daylight without a floodlit ceiling.
	walls(x0, FLOOR + 4, z0, x1, FLOOR + 4, z1, "lw_nodes:glass")
	fill(x0, FLOOR + 6, z0, x1, FLOOR + 6, z1, "lw_nodes:slab_stone_brick")
	-- Door on the east wall, facing the courtyard.
	fill(x1, FLOOR, 17, x1, FLOOR + 2, 19, "air")
	-- Title over the door, read from the courtyard (facing west, letters +z).
	write_text(x1, FLOOR + 5, z0 + 1, "LIBRARY", "yellow", "z", 1)

	local names = palette_names()
	local index = 1
	-- Two banks of three pedestals with an aisle down the middle.
	for row = 0, 7 do
		for col = 0, 5 do
			local name = names[index]
			if not name then
				break
			end
			local x = x0 + 2 + col * 2 + (col > 2 and 2 or 0)
			local z = z0 + 3 + row * 3
			if x <= x1 - 1 and z <= z1 - 1 then
				put(x, FLOOR, z, "lw_nodes:pedestal")
				put(x, FLOOR + 1, z, name)
				local def = core.registered_nodes[name]
				label(x, FLOOR, z, (def and def.description or name) .. "\n" .. name)
				index = index + 1
			end
		end
	end
	if names[index] then
		core.log("warning", "[lw_world] the material library has " ..
			(#names - index + 1) .. " more palette nodes than pedestals")
	end

	for z = z0 + 4, z1 - 2, 8 do
		put(x0 + 1, FLOOR + 3, z, "lw_nodes:lamp")
		put(x1 - 1, FLOOR + 3, z, "lw_nodes:lamp")
	end
end

--------------------------------------------------------------------------
-- 3. Pixel-art gallery
--------------------------------------------------------------------------

-- Pixel art as node art: "." is empty, every other character indexes the
-- artwork's own palette. Rows run top down and must all be the same length.
local ARTWORKS = {
	{
		title = "Heart",
		note = "Wool pixel art, 13x9 — two tones and a highlight, no texture pack.",
		palette = {r = "red", w = "white"},
		rows = {
			"..rrr...rrr..",
			".rrrrr.rrrrr.",
			"rrrrrrrrrrrrr",
			"rrwrrrrrrrrrr",
			"rrrrrrrrrrrrr",
			".rrrrrrrrrrr.",
			"...rrrrrrr...",
			".....rrr.....",
			"......r......",
		},
	},
	{
		title = "Sunrise",
		note = "Five colours from the 16-cube palette, arranged as a landscape.",
		palette = {y = "yellow", o = "orange", b = "blue", c = "cyan",
			g = "dark_green", d = "green"},
		rows = {
			"bbbbbbbbbbbbb",
			"bbbbbcccbbbbb",
			"bbbbcyyycbbbb",
			"bbbcyyyyycbbb",
			"bbbbcyyycbbbb",
			"bbbbbooobbbbb",
			"ooooooooooooo",
			"ggggggggggggg",
			"gdgdgdgdgdgdg",
		},
	},
	{
		title = "Cube",
		note = "An isometric cube: the trick a 2D icon uses, drawn at node scale.",
		palette = {w = "white", g = "grey", d = "dark_grey", k = "black"},
		rows = {
			"......w......",
			"....wwwww....",
			"..wwwwwwwww..",
			"wwwwwwwwwwwww",
			"gggwwwwwwwddd",
			"ggggggwdddddd",
			"gggggggdddddd",
			".ggggggddddd.",
			"...kkkkkkk...",
		},
	},
}

-- Fail loudly at load time rather than silently building a ragged wall.
for _, art in ipairs(ARTWORKS) do
	local width = #art.rows[1]
	for row, line in ipairs(art.rows) do
		assert(#line == width, ("lw_world artwork %q row %d is %d wide, expected %d")
			:format(art.title, row, #line, width))
	end
end

-- `front` is -1 when the viewer stands south of the piece and +1 when north:
-- it only decides which side the uplights and stanchions go on.
local function build_artwork(art, x, y, z, front)
	for row, line in ipairs(art.rows) do
		for col = 1, #line do
			local color = art.palette[line:sub(col, col)]
			if color then
				put(x + col - 1, y - row + 1, z, "lw_nodes:wool_" .. color)
			end
		end
	end
	local width = #art.rows[1]
	local height = #art.rows
	outline_z(x - 1, y - height, x + width, y + 1, z, "lw_nodes:frame")

	local centre = x + math.floor(width / 2)
	local apron = z + 2 * front
	put(centre, FLOOR, apron, "lw_nodes:uplight")
	put(centre - 3, FLOOR, apron, "lw_nodes:stanchion")
	put(centre + 3, FLOOR, apron, "lw_nodes:stanchion")
	label(centre, FLOOR, apron, art.title .. "\n" .. art.note)
end

local GALLERY = {x0 = 16, x1 = 32, z0 = 4, z1 = 32}

-- The artworks are nine nodes tall and the frames wrap them, so the room has
-- to be tall enough to hang a piece clear of the doorways underneath it.
local ART_TOP = FLOOR + 11
local GALLERY_CEILING = FLOOR + 12

local function build_gallery()
	local x0, x1, z0, z1 = GALLERY.x0, GALLERY.x1, GALLERY.z0, GALLERY.z1

	fill(x0, GROUND - 1, z0, x1, GROUND - 1, z1, "lw_nodes:polished_stone")
	fill(x0, GROUND, z0, x1, GROUND, z1, "lw_nodes:carpet")
	fill(x0, FLOOR, z0, x1, GALLERY_CEILING, z1, "air")
	walls(x0, FLOOR, z0, x1, GALLERY_CEILING, z1, "lw_nodes:polished_stone")
	fill(x0, GALLERY_CEILING + 1, z0, x1, GALLERY_CEILING + 1, z1,
		"lw_nodes:slab_stone_brick")
	-- Door on the west wall, facing the courtyard.
	fill(x0, FLOOR, 17, x0, FLOOR + 2, 19, "air")
	-- Title over the door, read from the courtyard (facing east, letters -z).
	write_text(x0, FLOOR + 5, z1 - 1, "GALLERY", "magenta", "z", -1)

	-- A partition gives the third piece its own wall. Its doorway is two nodes
	-- high, which is exactly what clears the hanging frame above it.
	fill(x0 + 1, FLOOR, 24, x1 - 1, GALLERY_CEILING, 24, "lw_nodes:polished_stone")
	fill(x1 - 3, FLOOR, 24, x1 - 1, FLOOR + 1, 24, "air")

	build_artwork(ARTWORKS[1], x0 + 2, ART_TOP, z1 - 1, -1)   -- north wall
	build_artwork(ARTWORKS[2], x0 + 2, ART_TOP, 23, -1)       -- partition
	build_artwork(ARTWORKS[3], x0 + 2, ART_TOP, z0 + 1, 1)    -- south wall

	for z = z0 + 5, z1 - 3, 9 do
		put(x0 + 1, GALLERY_CEILING - 1, z, "lw_nodes:lamp")
		put(x1 - 1, GALLERY_CEILING - 1, z, "lw_nodes:lamp")
	end
end

--------------------------------------------------------------------------
-- 4. Kinetic courtyard
--------------------------------------------------------------------------

-- Chasing lights are driven by one node timer on an invisible controller. An
-- ABM would fire per node per interval whether or not anyone is watching; a
-- single timer that re-arms itself only runs while the block is loaded, which
-- matters when the server shares a core with the browser's compositor.
local CHASE_LENGTH = 16
local CHASE_COLORS = {"cyan", "blue", "violet", "magenta"}
local CHASE_ORIGIN = {x = -8, y = FLOOR + 5, z = 9}

core.register_node("lw_world:chaser", {
	description = "Chase Light Controller",
	drawtype = "airlike",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	groups = {not_in_creative_inventory = 1},
	on_construct = function(pos)
		core.get_node_timer(pos):start(0.4)
	end,
	on_timer = function(pos)
		local meta = core.get_meta(pos)
		local step = (meta:get_int("step") + 1) % CHASE_LENGTH
		meta:set_int("step", step)
		for i = 1, CHASE_LENGTH - 1 do
			local lit = (i - step) % CHASE_LENGTH < 3
			local color = lit and "white" or CHASE_COLORS[(i % #CHASE_COLORS) + 1]
			local target = "lw_nodes:wool_" .. color
			local at = {x = pos.x + i, y = pos.y, z = pos.z}
			if core.get_node(at).name ~= target then
				core.swap_node(at, {name = target})
			end
		end
		return true
	end,
})

local COURTYARD = {x0 = -12, x1 = 12, z0 = 4, z1 = 32}

local function build_courtyard()
	local x0, x1, z0, z1 = COURTYARD.x0, COURTYARD.x1, COURTYARD.z0, COURTYARD.z1

	fill(x0, GROUND, z0 + 2, x1, GROUND, z1, "lw_nodes:paving")

	-- Water channel down the middle, crossed by two plank bridges.
	fill(-2, GROUND, z0 + 4, 2, GROUND, z1 - 3, "lw_nodes:stone_brick")
	fill(-1, GROUND, z0 + 5, 1, GROUND, z1 - 4, "lw_nodes:water")
	for _, z in ipairs({14, 24}) do
		fill(-1, GROUND, z, 1, GROUND, z + 1, "lw_nodes:slab_planks")
	end

	-- LED ticker wall on the west side with a chase-light cornice above it.
	fill(x0 + 1, FLOOR, 8, x0 + 1, FLOOR + 4, 22, "lw_nodes:polished_stone")
	fill(x0 + 2, FLOOR + 1, 9, x0 + 2, FLOOR + 3, 21, "lw_nodes:ticker")
	fill(CHASE_ORIGIN.x, CHASE_ORIGIN.y, CHASE_ORIGIN.z,
		CHASE_ORIGIN.x + CHASE_LENGTH - 1, CHASE_ORIGIN.y, CHASE_ORIGIN.z,
		"lw_nodes:wool_cyan")
	put(CHASE_ORIGIN.x, CHASE_ORIGIN.y, CHASE_ORIGIN.z, "lw_world:chaser")

	-- Plank loop on the east side for the cart to run.
	fill(4, GROUND, 8, 9, GROUND, 8, "lw_nodes:planks")
	fill(4, GROUND, 28, 9, GROUND, 28, "lw_nodes:planks")
	fill(4, GROUND, 8, 4, GROUND, 28, "lw_nodes:planks")
	fill(9, GROUND, 8, 9, GROUND, 28, "lw_nodes:planks")

	for _, x in ipairs({x0 + 4, x1 - 4}) do
		for z = z0 + 6, z1 - 4, 8 do
			fill(x, FLOOR, z, x, FLOOR + 2, z, "lw_nodes:beam")
			put(x, FLOOR + 3, z, "lw_nodes:lamp")
		end
	end

	put(6, FLOOR, 12, "lw_nodes:pedestal")
	put(6, FLOOR + 1, 12, "lw_nodes:poster")
	label(6, FLOOR + 1, 12,
		"Kinetic courtyard: animated tiles (ticker wall, water), a node-timer " ..
		"light chase, and a cart entity. Engine-native — no shaders, no video.")
end

--------------------------------------------------------------------------
-- 5. Theater
--------------------------------------------------------------------------

local THEATER = {x0 = -16, x1 = 16, z0 = 34, z1 = SCREEN_Z + 2}

local function build_theater()
	local x0, x1, z0, z1 = THEATER.x0, THEATER.x1, THEATER.z0, THEATER.z1

	fill(x0, GROUND - 1, z0, x1, GROUND - 1, z1, "lw_nodes:stone_brick")
	fill(x0, GROUND, z0, x1, GROUND, z1, "lw_nodes:carpet")
	fill(x0, FLOOR, z0, x1, FLOOR + 11, z1, "air")
	walls(x0, FLOOR, z0, x1, FLOOR + 11, z1, "lw_nodes:stone_brick")
	fill(x0, FLOOR + 12, z0, x1, FLOOR + 12, z1, "lw_nodes:stone_brick")

	-- Entrance, marquee and title on the south face.
	fill(x0, FLOOR + 6, z0 - 1, x1, FLOOR + 11, z0 - 1, "lw_nodes:stone_brick")
	fill(-3, FLOOR, z0, 3, FLOOR + 3, z0, "air")
	fill(-5, FLOOR + 4, z0, 5, FLOOR + 4, z0, "lw_theater:marquee")
	fill(-6, FLOOR + 5, z0, 6, FLOOR + 5, z0, "lw_nodes:gold_trim")
	write_text(-math.floor(text_width("CINEMA") / 2), FLOOR + 11, z0 - 1, "CINEMA",
		"red", "x", 1)

	-- Auditorium floor. The house steps *down* towards the screen, so the
	-- entrance ramp climbs to the back row and each row in front of it sits a
	-- little lower — the back of the house can see over the front without the
	-- entrance opening onto a wall of seating.
	local BANDS = {
		{z0 = 37, z1 = 38, level = 1},
		{z0 = 39, z1 = 43, level = 2},          -- back row, z = 42
		{z0 = 44, z1 = 49, level = 1},          -- rows z = 45 and 48
	}
	for _, band in ipairs(BANDS) do
		fill(x0 + 1, GROUND + 1, band.z0, x1 - 1, GROUND + band.level, band.z1,
			"lw_nodes:stone_brick")
		fill(x0 + 1, GROUND + band.level, band.z0, x1 - 1, GROUND + band.level,
			band.z1, "lw_nodes:carpet")
	end

	-- Five rows of seats, an aisle down the middle, aisle lights at both ends.
	local ROW_LEVEL = {[42] = 2, [45] = 1, [48] = 1, [51] = 0, [54] = 0}
	for _, z in ipairs({42, 45, 48, 51, 54}) do
		local y = GROUND + ROW_LEVEL[z] + 1
		for x = x0 + 3, x1 - 3 do
			if x < -2 or x > 2 then
				-- facedir 2 is a half turn, putting the seat back to the south
				-- so a seated visitor faces the screen.
				put(x, y, z, "lw_theater:seat", 2)
			end
		end
		put(x0 + 2, y, z, "lw_theater:aisle_light")
		put(x1 - 2, y, z, "lw_theater:aisle_light")
	end

	-- Curtain wall, then the screen and its proscenium arch on top of it.
	fill(x0 + 1, FLOOR, SCREEN_Z, x1 - 1, FLOOR + 10, SCREEN_Z, "lw_nodes:curtain")
	fill(SCREEN_X0, SCREEN_TOP - 3, SCREEN_Z,
		SCREEN_X0 + lw_theater.screen_cols - 1, SCREEN_TOP, SCREEN_Z,
		"lw_theater:screen_off")
	outline_z(SCREEN_X0 - 1, SCREEN_TOP - 4,
		SCREEN_X0 + lw_theater.screen_cols, SCREEN_TOP + 1, SCREEN_Z,
		"lw_nodes:gold_trim")

	-- House lights, kept sparse: the screen is meant to be the bright thing.
	for x = x0 + 5, x1 - 5, 10 do
		for z = z0 + 6, SCREEN_Z - 6, 8 do
			put(x, FLOOR + 11, z, "lw_nodes:lamp")
		end
	end

	put(-6, FLOOR, 38, "lw_nodes:pedestal")
	put(-6, FLOOR + 1, 38, "lw_nodes:poster")
	label(-6, FLOOR + 1, 38,
		"Theater: left click the Screen Remote for the next reel, right click " ..
		"for the browser video overlay. Right click a seat to sit down. " ..
		"/reel off brings the house lights back up.")
end

--------------------------------------------------------------------------
-- Paths and railings
--------------------------------------------------------------------------

local function build_paths()
	fill(-3, GROUND, PLAZA.z1, 3, GROUND, COURTYARD.z0 + 2, "lw_nodes:paving")
	fill(-3, GROUND, COURTYARD.z1, 3, GROUND, THEATER.z0, "lw_nodes:paving")
	fill(LIBRARY.x1, GROUND, 17, COURTYARD.x0, GROUND, 19, "lw_nodes:paving")
	fill(COURTYARD.x1, GROUND, 17, GALLERY.x0, GROUND, 19, "lw_nodes:paving")

	-- A rail along the moat edge so a walking visitor does not fall in.
	for x = ISLAND.x0, ISLAND.x1, 2 do
		put(x, FLOOR, ISLAND.z0, "lw_nodes:fence")
		put(x, FLOOR, ISLAND.z1, "lw_nodes:fence")
	end
	for z = ISLAND.z0, ISLAND.z1, 2 do
		put(ISLAND.x0, FLOOR, z, "lw_nodes:fence")
		put(ISLAND.x1, FLOOR, z, "lw_nodes:fence")
	end
end

build_island()
build_plaza()
build_library()
build_gallery()
build_courtyard()
build_theater()
build_paths()

--------------------------------------------------------------------------
-- Stamping the ops into generated chunks
--------------------------------------------------------------------------

local content_cache = {}

local function content_id(name)
	local id = content_cache[name]
	if not id then
		id = core.get_content_id(name)
		content_cache[name] = id
	end
	return id
end

local function overlaps(minp, maxp)
	return not (maxp.x < BOUNDS.min.x or minp.x > BOUNDS.max.x
		or maxp.y < BOUNDS.min.y or minp.y > BOUNDS.max.y
		or maxp.z < BOUNDS.min.z or minp.z > BOUNDS.max.z)
end

core.register_on_generated(function(minp, maxp, _seed)
	if not overlaps(minp, maxp) then
		return
	end

	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local param2 = vm:get_param2_data()
	local touched = false

	for _, op in ipairs(ops) do
		local x0 = math.max(op.x0, minp.x)
		local x1 = math.min(op.x1, maxp.x)
		local y0 = math.max(op.y0, minp.y)
		local y1 = math.min(op.y1, maxp.y)
		local z0 = math.max(op.z0, minp.z)
		local z1 = math.min(op.z1, maxp.z)
		if x0 <= x1 and y0 <= y1 and z0 <= z1 then
			local id = content_id(op.name)
			local p2 = op.param2 or 0
			for z = z0, z1 do
				for y = y0, y1 do
					local index = area:index(x0, y, z)
					for _ = x0, x1 do
						data[index] = id
						param2[index] = p2
						index = index + 1
					end
				end
			end
			touched = true
		end
	end

	if not touched then
		return
	end

	vm:set_data(data)
	vm:set_param2_data(param2)
	vm:calc_lighting()
	vm:write_to_map()
	vm:update_liquids()

	-- Metadata cannot ride along in a voxel manipulator, so infotext labels are
	-- applied once the chunk is on the map.
	for _, entry in ipairs(labels) do
		local pos = entry.pos
		if pos.x >= minp.x and pos.x <= maxp.x
				and pos.y >= minp.y and pos.y <= maxp.y
				and pos.z >= minp.z and pos.z <= maxp.z then
			core.get_meta(pos):set_string("infotext", entry.text)
		end
	end
end)

--------------------------------------------------------------------------
-- World setup
--------------------------------------------------------------------------

core.settings:set("static_spawnpoint",
	("%d,%d,%d"):format(SPAWN.x, SPAWN.y, SPAWN.z))
if core.set_mapgen_setting then
	core.set_mapgen_setting("mg_name", "singlenode", true)
end

lw_theater.register_screen(
	{x = SCREEN_X0, y = SCREEN_TOP, z = SCREEN_Z}, {x = 1, y = 0, z = 0})

core.after(0, function()
	-- Midday, with the clock frozen (time_speed = 0 in the game's
	-- minetest.conf) so the galleries look the same on every visit. The
	-- theater remote is the only thing that moves it.
	core.set_timeofday(0.45)
end)

--------------------------------------------------------------------------
-- The courtyard cart
--------------------------------------------------------------------------

local CART_PATH = {
	{x = 4, z = 8}, {x = 9, z = 8}, {x = 9, z = 28}, {x = 4, z = 28},
}
local CART_SPEED = 2.0

core.register_entity("lw_world:cart", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		visual = "cube",
		visual_size = {x = 0.8, y = 0.6, z = 0.8},
		textures = {
			"lw_planks.png", "lw_planks.png", "lw_beam_side.png",
			"lw_beam_side.png", "lw_beam_side.png", "lw_beam_side.png",
		},
		-- Respawned on join, so it must not accumulate in the map file.
		static_save = false,
		infotext = "Courtyard cart",
	},
	leg = 1,
	on_activate = function(self)
		self.leg = 1
	end,
	on_step = function(self, dtime)
		local pos = self.object:get_pos()
		if not pos then
			return
		end
		local target = CART_PATH[self.leg % #CART_PATH + 1]
		local dx = target.x - pos.x
		local dz = target.z - pos.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < 0.2 then
			self.leg = self.leg % #CART_PATH + 1
			return
		end
		local step = math.min(CART_SPEED * dtime, distance)
		self.object:set_pos({
			x = pos.x + dx / distance * step,
			y = FLOOR + 0.3,
			z = pos.z + dz / distance * step,
		})
		self.object:set_yaw(math.atan2(-dx, dz))
	end,
})

local function ensure_cart()
	local centre = {x = 6, y = FLOOR, z = 18}
	for _, object in ipairs(core.get_objects_inside_radius(centre, 24)) do
		local entity = object:get_luaentity()
		if entity and entity.name == "lw_world:cart" then
			return
		end
	end
	core.add_entity({x = CART_PATH[1].x, y = FLOOR + 0.3, z = CART_PATH[1].z},
		"lw_world:cart")
end

core.register_on_joinplayer(function()
	-- Give the courtyard a moment to load before looking for the cart.
	core.after(3, ensure_cart)
end)

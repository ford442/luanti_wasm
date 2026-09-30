-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Where the themed maps go: the atlas.
--
-- `lw_maps` owns what each map *is* — its schematic, footprint, spawn and the
-- atmosphere it wants. This file owns where it sits relative to the plaza and
-- how a visitor walks there:
--
--                      [ hub plaza ]
--                     /   /  |    \
--         Halloween lane /  snow    giant fruit
--              (west)   / mountain     garden
--                      /  (south)     (east)
--          lighthouse tide
--            (southwest)
--
-- Each map is one island with its own beach, in one sea, joined to the plaza
-- by a paved causeway with a themed gate at the hub end. Fly is on for
-- everyone, but every causeway is walkable, which is the point of the
-- acceptance test: a visitor with no privileges can still get to all of them.
--
-- Each island is a single schematic op. That is deliberate: the maps together
-- are tens of thousands of authored nodes, and expressing them as box ops
-- would put that many entries in the build list that every chunk in the atlas
-- then has to be tested against.

local maps = {}

-- Beach around each map's footprint, then open water around that.
local RIM = 2
local MOAT = 7

maps.RIM = RIM
maps.MOAT = MOAT

local function expand(box, amount)
	return {
		x0 = box.x0 - amount, z0 = box.z0 - amount,
		x1 = box.x1 + amount, z1 = box.z1 + amount,
	}
end

local function footprint(map)
	return {x0 = map.min.x, z0 = map.min.z, x1 = map.max.x, z1 = map.max.z}
end
maps.footprint = footprint

-- `box` minus `hole`, as up to four boxes. Used to lay water everywhere the
-- showcase island is not: a fill wide enough to be convenient would otherwise
-- punch a channel through the island the ops before it built.
local function subtract(box, hole)
	if hole.x1 < box.x0 or hole.x0 > box.x1 or hole.z1 < box.z0 or hole.z0 > box.z1 then
		return {box}
	end
	local out = {}
	local function add(x0, z0, x1, z1)
		if x0 <= x1 and z0 <= z1 then
			out[#out + 1] = {x0 = x0, z0 = z0, x1 = x1, z1 = z1}
		end
	end
	add(box.x0, box.z0, hole.x0 - 1, box.z1)
	add(hole.x1 + 1, box.z0, box.x1, box.z1)
	local x0, x1 = math.max(box.x0, hole.x0), math.min(box.x1, hole.x1)
	add(x0, box.z0, x1, hole.z0 - 1)
	add(x0, hole.z1 + 1, x1, box.z1)
	return out
end
maps.subtract = subtract

-- The causeways, one per map, each a list of legs from the plaza outward.
--
-- A leg is a paved strip one node above the water, three or four nodes wide,
-- axis-aligned so it is one box op. Consecutive legs overlap by their width,
-- which is what makes the corner. The first leg starts on the plaza's edge
-- and crosses the showcase island's open lawn; the last one ends on the map's
-- own edge, level with its spawn. The north side of the plaza is the hub tour
-- (library, courtyard, gallery, theater), so the three diagonal maps leave by
-- the plaza's sides and turn in the open water instead.
--
-- `gate` is where the themed posts and the poster stand, beside the first leg
-- inside the plaza. util/content/test_luanti_web_maps.lua walks every leg and
-- checks it reaches the spawn without crossing another island, another
-- causeway or a hub building.
function maps.causeways(api)
	local PLAZA = api.PLAZA
	return {
		{
			map = "halloween",
			legs = {
				{x0 = -52, z0 = -9, x1 = PLAZA.x0, z1 = -7},
			},
			gate = {x = PLAZA.x0 + 1, z = -11},
			post = "lw_maps:pumpkin",
			sign = "West: the Halloween lane. Carved lanterns, a graveyard, a " ..
				"haunted house you can walk through from cellar to attic, and " ..
				"a porch stage. It is dusk over there and only over there.",
		},
		{
			map = "fruit_garden",
			legs = {
				{x0 = PLAZA.x1, z0 = -9, x1 = 52, z1 = -7},
			},
			gate = {x = PLAZA.x1 - 1, z = -11},
			post = "lw_maps:leaves",
			sign = "East: the giant fruit garden. A watermelon you walk into, " ..
				"a sliced melon used as an amphitheatre, and a juice channel " ..
				"between them. Every fruit on it is dyed wool.",
		},
		{
			map = "snow_mountain",
			legs = {
				{x0 = 5, z0 = -34, x1 = 8, z1 = PLAZA.z0},
			},
			gate = {x = 10, z = PLAZA.z0 + 1},
			post = "lw_maps:packed_snow",
			sign = "South: the snowy mountain. A switchback trail to the " ..
				"overlook, an ice cave, a timbered mineshaft, and a tunnel " ..
				"that comes out on the far face.",
		},
		{
			-- Out of the plaza's south side west of the snow causeway, west
			-- along the gap between the showcase island and the mountain's
			-- beach, then south onto the lighthouse's shore.
			map = "lighthouse_tide",
			legs = {
				{x0 = -8, z0 = -30, x1 = -5, z1 = PLAZA.z0},
				{x0 = -40, z0 = -30, x1 = -5, z1 = -28},
				{x0 = -40, z0 = -45, x1 = -38, z1 = -28},
			},
			gate = {x = -10, z = PLAZA.z0 + 1},
			post = "lw_nodes:lamp",
			sign = "Southwest: the lighthouse tide. Climb the spiral stair to " ..
				"the lamp, walk the jetty over its glass-bottomed tide pools, " ..
				"then take the tunnel along the lagoon bed underneath it. " ..
				"It is blue hour over there.",
		},
		{
			-- Out of the plaza's east side north of the garden causeway, north
			-- up the channel between the showcase island and the garden, then
			-- east into the bazaar's arcade.
			map = "crystal_bazaar",
			legs = {
				{x0 = PLAZA.x1, z0 = -3, x1 = 47, z1 = -1},
				{x0 = 45, z0 = -3, x1 = 47, z1 = 43},
				{x0 = 45, z0 = 41, x1 = 54, z1 = 43},
			},
			gate = {x = PLAZA.x1 - 1, z = 1},
			post = "lw_maps:lantern",
			sign = "Northeast: the crystal night bazaar. A glass-vaulted " ..
				"arcade of stalls whose lanterns chase each other round it, a " ..
				"dome you can walk up onto, and a cistern under it lit only by " ..
				"torches. It is night over there.",
		},
	}
end

-- Is the leg's long axis x? Decides which way its rails and gate run.
local function along_x(box)
	return box.x1 - box.x0 > box.z1 - box.z0
end
maps.along_x = along_x

-- `api` is lw_world's build vocabulary: see init.lua. Returns the bounding box
-- the atlas adds, so init.lua can widen the box it generates into.
function maps.build(api)
	local fill, put, schem, label = api.fill, api.put, api.schem, api.label
	local GROUND, FLOOR, WATER = api.GROUND, api.FLOOR, api.WATER
	local HUB = api.HUB

	local causeways = maps.causeways(api)

	-- The atlas is one sea: everything from the showcase island's own moat out
	-- to the far side of the farthest island's moat. Measured first, because
	-- the islands are then built on top of it.
	local sea = nil
	local function cover(box)
		if not sea then
			sea = {x0 = box.x0, z0 = box.z0, x1 = box.x1, z1 = box.z1}
			return
		end
		sea.x0 = math.min(sea.x0, box.x0)
		sea.z0 = math.min(sea.z0, box.z0)
		sea.x1 = math.max(sea.x1, box.x1)
		sea.z1 = math.max(sea.z1, box.z1)
	end
	local top = FLOOR + 4
	for _, map in ipairs(lw_maps.maps) do
		cover(expand(footprint(map), RIM + MOAT))
		top = math.max(top, map.max.y)
	end
	for _, way in ipairs(causeways) do
		for _, leg in ipairs(way.legs) do
			cover(expand(leg, 2))
		end
	end

	-- 1. Water first, everywhere but the showcase island's own box (which
	-- build_island() has already flooded and built on), so the land below
	-- overwrites it and the sea has no holes between the islands.
	for _, box in ipairs(subtract(sea, HUB)) do
		fill(box.x0, 0, box.z0, box.x1, WATER, box.z1, "lw_nodes:water")
	end

	-- 2. Each island's shelf and beach, and solid rock under the schematic.
	for _, map in ipairs(lw_maps.maps) do
		local box = expand(footprint(map), RIM)
		fill(box.x0, 0, box.z0, box.x1, GROUND - 1, box.z1, "lw_nodes:stone")
		fill(box.x0, GROUND, box.z0, box.x1, GROUND, box.z1, "lw_nodes:sand")
		-- The schematic carries its own three ground layers from map.min.y up,
		-- so everything below that is plain rock.
		fill(map.min.x, 0, map.min.z, map.max.x, map.min.y - 1, map.max.z,
			"lw_nodes:stone")
	end

	-- 3. Causeway decks, their rails, and the gate they leave the hub by.
	for _, way in ipairs(causeways) do
		for _, deck in ipairs(way.legs) do
			fill(deck.x0, GROUND, deck.z0, deck.x1, GROUND, deck.z1, "lw_nodes:paving")
			-- Clear the moat rail where the deck crosses the showcase island's
			-- edge: build_paths() fences that line, and a fence in the middle
			-- of a causeway is exactly the sort of thing nobody notices until
			-- a visitor walks into it.
			fill(deck.x0, FLOOR, deck.z0, deck.x1, FLOOR + 3, deck.z1, "air")
		end
		-- Rails go on after every leg is cleared, and only where they would
		-- not stand on another leg: that is what leaves the corners open.
		local function on_deck(x, z)
			for _, leg in ipairs(way.legs) do
				if x >= leg.x0 and x <= leg.x1 and z >= leg.z0 and z <= leg.z1 then
					return true
				end
			end
			return false
		end
		local function rail(x, z)
			if not on_deck(x, z) then
				put(x, FLOOR, z, "lw_nodes:fence")
			end
		end
		for _, deck in ipairs(way.legs) do
			if along_x(deck) then
				for x = deck.x0, deck.x1, 2 do
					rail(x, deck.z0 - 1)
					rail(x, deck.z1 + 1)
				end
			else
				for z = deck.z0, deck.z1, 2 do
					rail(deck.x0 - 1, z)
					rail(deck.x1 + 1, z)
				end
			end
		end

		-- The gate: two posts topped with something from the map they point
		-- at, so the exits read apart at a glance from the fountain.
		local map = lw_maps.by_id[way.map]
		local gx, gz = way.gate.x, way.gate.z
		local across = along_x(way.legs[1])
		for _, offset in ipairs({-2, 2}) do
			local px = across and gx or gx + offset
			local pz = across and gz + offset or gz
			fill(px, FLOOR, pz, px, FLOOR + 2, pz, "lw_nodes:column")
			put(px, FLOOR + 3, pz, way.post)
		end
		put(gx, FLOOR, gz, "lw_nodes:pedestal")
		put(gx, FLOOR + 1, gz, "lw_nodes:poster")
		label(gx, FLOOR + 1, gz, map.title .. "\n" .. way.sign ..
			"\n/maps " .. map.id .. " goes straight there.")
	end

	-- 4. The maps themselves, last, so each one owns its whole footprint.
	for _, map in ipairs(lw_maps.maps) do
		local piece = schem(map.min.x, map.min.y, map.min.z, map.schem)
		assert(piece.size.x == map.size.x and piece.size.y == map.size.y
			and piece.size.z == map.size.z,
			("lw_world: %s.mts is %dx%dx%d but lw_maps says %dx%dx%d; " ..
				"rerun util/content/generate_luanti_web_maps.py")
				:format(map.schem, piece.size.x, piece.size.y, piece.size.z,
					map.size.x, map.size.y, map.size.z))
	end

	-- 5. Dance stages. Marks and a director node per themed map, stamped after
	-- the schematic so they sit on the build rather than inside it, plus the
	-- stage registration that tells lw_dance which routine belongs where.
	-- Local coordinates are the map schematic's own, checked against what
	-- util/content/generate_luanti_web_maps.py puts there.
	--
	-- The snow mountain has no stage: the routines are all people and there is
	-- no penguin rig in the tree. A line of recoloured humans on an overlook
	-- would be a worse demo than an empty overlook, so it waits for a mesh.
	local STAGES = {
		{
			routine = "porch_haunt",
			map = "halloween",
			-- The porch deck, with the audience east of it on the two rows of
			-- seats. The lead stands a node forward of the other two.
			pos = {5, 6, 8},
			node = {3, 6, 9},
			facing = {x = 1, y = 0, z = 0},
			marks = {
				{5, 6, 8, "mark_lead"},
				{4, 6, 6, "mark_1"},
				{4, 6, 10, "mark_2"},
			},
			sign = "Porch director: punch to raise the haunt, punch again to " ..
				"send it back. /routine join dances along with it.",
		},
		{
			routine = "fruit_stomp",
			map = "fruit_garden",
			-- The floor of the melon bowl, with the audience on the path to
			-- the north. Only the mascot gets a mark: the berry is on a raft.
			pos = {28, 2, 11},
			node = {26, 4, 20},
			facing = {x = 0, y = 0, z = 1},
			marks = {{28, 2, 11, "mark_lead"}},
			sign = "Garden director: punch to start the fruit stomp. The melon " ..
				"has no skeleton and dances anyway; the berry rides the juice.",
		},
		{
			-- The crown of the glass dome, with the audience on the rim and the
			-- stair up from the north souk. The theater's own chorus line: a
			-- second stage for an existing routine, not a new one.
			id = "bazaar_dome",
			routine = "chorus_line_v1",
			map = "crystal_bazaar",
			pos = {18, 12, 18},
			node = {23, 9, 23},
			facing = {x = 0, y = 0, z = 1},
			marks = {
				{18, 12, 18, "mark_lead"},
				{16, 12, 18, "mark_1"},
				{20, 12, 18, "mark_2"},
			},
			sign = "Dome director: punch for the theater's chorus line, up on " ..
				"the glass. It is the theater's own routine, so one of the two " ..
				"stages dances it at a time. /routine join dances along.",
		},
	}

	for _, stage in ipairs(STAGES) do
		local map = lw_maps.by_id[stage.map]
		local function world(local_pos)
			return {
				x = map.min.x + local_pos[1],
				y = map.min.y + local_pos[2],
				z = map.min.z + local_pos[3],
			}
		end
		for _, mark in ipairs(stage.marks) do
			local at = world(mark)
			put(at.x, at.y, at.z, "lw_dance:" .. mark[4])
		end
		local node = world(stage.node)
		put(node.x, node.y, node.z, "lw_dance:director")
		label(node.x, node.y, node.z, stage.sign)
		lw_dance.register_stage({
			id = stage.id,
			routine = stage.routine,
			pos = world(stage.pos),
			node = node,
			facing = stage.facing,
		})
	end

	return {
		min = {x = sea.x0, y = 0, z = sea.z0},
		max = {x = sea.x1, y = top + 2, z = sea.z1},
	}
end

return maps

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
--                       /    |    \
--         Halloween lane   snow    giant fruit
--              (west)    mountain     garden
--                         (south)     (east)
--
-- Each map is one island with its own beach and moat, joined to the plaza by
-- a paved causeway with a themed gate at the hub end. Fly is on for everyone,
-- but every causeway is walkable, which is the point of the acceptance test:
-- a visitor with no privileges can still get to all three.
--
-- Each island is a single schematic op. That is deliberate: the three maps
-- together are about 98k authored nodes, and expressing them as box ops would
-- put tens of thousands of entries in the build list that every chunk in the
-- atlas then has to be tested against.

local maps = {}

-- Beach around each map's footprint, then water around that. The moat is wide
-- enough that each island's water meets the showcase island's own moat
-- (x -44..44, z -30..74), so the atlas reads as one sea rather than as three
-- ponds with voids between them.
local RIM = 2
local MOAT = 7

local function expand(box, amount)
	return {
		x0 = box.x0 - amount, z0 = box.z0 - amount,
		x1 = box.x1 + amount, z1 = box.z1 + amount,
	}
end

-- `api` is lw_world's build vocabulary: see init.lua. Returns the bounding box
-- the atlas adds, so init.lua can widen the box it generates into.
function maps.build(api)
	local fill, put, schem, label = api.fill, api.put, api.schem, api.label
	local GROUND, FLOOR, WATER = api.GROUND, api.FLOOR, api.WATER
	local ISLAND, PLAZA = api.ISLAND, api.PLAZA

	local bounds = nil
	local function cover(x0, z0, x1, z1, y1)
		if not bounds then
			bounds = {x0 = x0, z0 = z0, x1 = x1, z1 = z1, y1 = y1}
			return
		end
		bounds.x0 = math.min(bounds.x0, x0)
		bounds.z0 = math.min(bounds.z0, z0)
		bounds.x1 = math.max(bounds.x1, x1)
		bounds.z1 = math.max(bounds.z1, z1)
		bounds.y1 = math.max(bounds.y1, y1)
	end

	-- A causeway is described by the gap it has to cross; the water under it
	-- fills only that gap, because a fill wide enough to be convenient would
	-- punch a channel through the showcase island the ops before it built.
	local CAUSEWAYS = {
		{
			map = "halloween",
			deck = {x0 = -52, z0 = -9, x1 = PLAZA.x0, z1 = -7},
			-- The gap stops at the showcase island's sand shelf, three nodes
			-- outside ISLAND: a channel dug any closer would undercut it.
			gap = {x0 = -52, z0 = -9, x1 = ISLAND.x0 - 4, z1 = -7},
			gate = {x = PLAZA.x0 + 1, z = -11},
			post = "lw_maps:pumpkin",
			sign = "West: the Halloween lane. Carved lanterns, a graveyard, a " ..
				"haunted house you can walk through from cellar to attic, and " ..
				"a porch stage. It is dusk over there and only over there.",
		},
		{
			map = "fruit_garden",
			deck = {x0 = PLAZA.x1, z0 = -9, x1 = 52, z1 = -7},
			gap = {x0 = ISLAND.x1 + 4, z0 = -9, x1 = 52, z1 = -7},
			gate = {x = PLAZA.x1 - 1, z = -11},
			post = "lw_maps:leaves",
			sign = "East: the giant fruit garden. A watermelon you walk into, " ..
				"a sliced melon used as an amphitheatre, and a juice channel " ..
				"between them. Every fruit on it is dyed wool.",
		},
		{
			map = "snow_mountain",
			deck = {x0 = 5, z0 = -34, x1 = 8, z1 = PLAZA.z0},
			gap = {x0 = 5, z0 = -34, x1 = 8, z1 = ISLAND.z0 - 4},
			gate = {x = 10, z = PLAZA.z0 + 1},
			post = "lw_maps:packed_snow",
			sign = "South: the snowy mountain. A switchback trail to the " ..
				"overlook, an ice cave, a timbered mineshaft, and a tunnel " ..
				"that comes out on the far face.",
		},
	}

	-- 1. Water first, everywhere, so the land below overwrites it.
	for _, map in ipairs(lw_maps.maps) do
		local box = expand({x0 = map.min.x, z0 = map.min.z,
			x1 = map.max.x, z1 = map.max.z}, RIM + MOAT)
		fill(box.x0, 0, box.z0, box.x1, WATER, box.z1, "lw_nodes:water")
		cover(box.x0, box.z0, box.x1, box.z1, map.max.y)
	end
	for _, way in ipairs(CAUSEWAYS) do
		-- Widen the channel sideways only. Widening it along its own axis
		-- would push the water past the ends the gap was measured to.
		local gap = way.gap
		if gap.x1 - gap.x0 > gap.z1 - gap.z0 then
			fill(gap.x0, 0, gap.z0 - 2, gap.x1, WATER, gap.z1 + 2, "lw_nodes:water")
		else
			fill(gap.x0 - 2, 0, gap.z0, gap.x1 + 2, WATER, gap.z1, "lw_nodes:water")
		end
		cover(gap.x0 - 2, gap.z0 - 2, gap.x1 + 2, gap.z1 + 2, FLOOR + 4)
	end

	-- 2. Each island's shelf and beach, and solid rock under the schematic.
	for _, map in ipairs(lw_maps.maps) do
		local box = expand({x0 = map.min.x, z0 = map.min.z,
			x1 = map.max.x, z1 = map.max.z}, RIM)
		fill(box.x0, 0, box.z0, box.x1, GROUND - 1, box.z1, "lw_nodes:stone")
		fill(box.x0, GROUND, box.z0, box.x1, GROUND, box.z1, "lw_nodes:sand")
		-- The schematic carries its own three ground layers from map.min.y up,
		-- so everything below that is plain rock.
		fill(map.min.x, 0, map.min.z, map.max.x, map.min.y - 1, map.max.z,
			"lw_nodes:stone")
	end

	-- 3. Causeway decks, their rails, and the gate they leave the hub by.
	for _, way in ipairs(CAUSEWAYS) do
		local deck = way.deck
		fill(deck.x0, GROUND, deck.z0, deck.x1, GROUND, deck.z1, "lw_nodes:paving")
		-- Clear the moat rail where the deck crosses the showcase island's
		-- edge: build_paths() fences that line, and a fence in the middle of
		-- a causeway is exactly the sort of thing nobody notices until a
		-- visitor walks into it.
		fill(deck.x0, FLOOR, deck.z0, deck.x1, FLOOR + 3, deck.z1, "air")
		if deck.x1 - deck.x0 > deck.z1 - deck.z0 then
			for x = deck.x0, deck.x1, 2 do
				put(x, FLOOR, deck.z0 - 1, "lw_nodes:fence")
				put(x, FLOOR, deck.z1 + 1, "lw_nodes:fence")
			end
		else
			for z = deck.z0, deck.z1, 2 do
				put(deck.x0 - 1, FLOOR, z, "lw_nodes:fence")
				put(deck.x1 + 1, FLOOR, z, "lw_nodes:fence")
			end
		end

		-- The gate: two posts topped with something from the map they point
		-- at, so the three exits read apart at a glance from the fountain.
		local map = lw_maps.by_id[way.map]
		local gx, gz = way.gate.x, way.gate.z
		local across = (deck.x1 - deck.x0 > deck.z1 - deck.z0)
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
			routine = stage.routine,
			pos = world(stage.pos),
			node = node,
			facing = stage.facing,
		})
	end

	return {
		min = {x = bounds.x0, y = 0, z = bounds.z0},
		max = {x = bounds.x1, y = bounds.y1 + 2, z = bounds.z1},
	}
end

return maps

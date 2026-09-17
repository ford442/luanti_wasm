-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Pure-ish helpers for the visitor toolkit. init.lua registers the items;
-- this file is also loaded by util/content/test_luanti_web_tools.lua against
-- a stubbed `core`, so it must not register anything and must not assume a
-- player object beyond what the tests pass in.

lw_tools = lw_tools or {}

-- 32³ = 32768 nodes. A browser tab running the WASM worker will hitch on a
-- naive WorldEdit-sized copy; this is the whole point of not shipping
-- WorldEdit. A 33-long line is fine — the cap is volume, not a cube.
lw_tools.MAX_CLONE_SIDE = 32
lw_tools.MAX_CLONE_VOLUME = 32 * 32 * 32

lw_tools.SEAT_ROW_LENGTH = 5
lw_tools.FRAME_SIZE = 5
lw_tools.COLUMN_HEIGHT = 6

lw_tools.STAMPS = { "seat_row", "column", "frame" }

-- Horizontal facedir → unit vector, matching core.facedir_to_dir for 0..3.
-- facedir 0 faces +Z; 1 faces +X; 2 faces -Z; 3 faces -X.
local FACEDIR_DIR = {
	[0] = {x = 0, y = 0, z = 1},
	[1] = {x = 1, y = 0, z = 0},
	[2] = {x = 0, y = 0, z = -1},
	[3] = {x = -1, y = 0, z = 0},
}

--------------------------------------------------------------------------
-- Small utilities
--------------------------------------------------------------------------

function lw_tools.player_sneaking(player)
	if not player or not player.get_player_control then
		return false
	end
	local ctrl = player:get_player_control()
	return ctrl and ctrl.sneak == true
end

function lw_tools.sorted_box(a, b)
	return {
		x = math.min(a.x, b.x),
		y = math.min(a.y, b.y),
		z = math.min(a.z, b.z),
	}, {
		x = math.max(a.x, b.x),
		y = math.max(a.y, b.y),
		z = math.max(a.z, b.z),
	}
end

function lw_tools.box_extent(minp, maxp)
	local size = {
		x = maxp.x - minp.x + 1,
		y = maxp.y - minp.y + 1,
		z = maxp.z - minp.z + 1,
	}
	return size, size.x * size.y * size.z
end

function lw_tools.check_clone_volume(p1, p2)
	local minp, maxp = lw_tools.sorted_box(p1, p2)
	local size, volume = lw_tools.box_extent(minp, maxp)
	if volume > lw_tools.MAX_CLONE_VOLUME then
		return nil, ("Clone volume is %d nodes (max %d = 32³). Shrink the selection.")
			:format(volume, lw_tools.MAX_CLONE_VOLUME)
	end
	return minp, maxp, size, volume
end

function lw_tools.facedir_from_dir(dir)
	if not dir then
		return 0
	end
	-- Same rule as the engine's horizontal dir_to_facedir: the dominant X/Z
	-- component, ties broken toward +Z / +X.
	if math.abs(dir.x) > math.abs(dir.z) then
		return dir.x > 0 and 1 or 3
	end
	return dir.z < 0 and 2 or 0
end

function lw_tools.facedir_to_dir(facedir)
	return FACEDIR_DIR[facedir % 4]
end

-- Right vector of a horizontal facedir: up × facing, so a seat row runs
-- left-to-right as the visitor looking that way would read it.
function lw_tools.right_of(facedir)
	local facing = lw_tools.facedir_to_dir(facedir)
	return {x = facing.z, y = 0, z = -facing.x}
end

function lw_tools.wool_names()
	local names = {}
	if lw_nodes and lw_nodes.wool_colors then
		for _, color in ipairs(lw_nodes.wool_colors) do
			names[#names + 1] = "lw_nodes:wool_" .. color.name
		end
		return names
	end
	-- Fallback so the unit test does not have to load lw_nodes.
	for _, name in ipairs({
		"white", "grey", "dark_grey", "black", "red", "orange", "yellow",
		"green", "dark_green", "cyan", "blue", "violet", "magenta", "pink",
		"brown", "tan",
	}) do
		names[#names + 1] = "lw_nodes:wool_" .. name
	end
	return names
end

--------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------

function lw_tools.get_paint_node(itemstack)
	local meta = itemstack:get_meta()
	local name = meta:get_string("node")
	if name == "" then
		name = "lw_nodes:wool_white"
	end
	return name, meta:get_int("param2")
end

function lw_tools.set_paint_node(itemstack, name, param2)
	local meta = itemstack:get_meta()
	meta:set_string("node", name)
	meta:set_int("param2", param2 or 0)
	local short = name:gsub("^lw_nodes:", ""):gsub("^lw_theater:", "")
	meta:set_string("description",
		"Paint Tool\nSneak+use: sample\nUse: stamp onto pointed node\n" ..
		"Right click: cycle wool palette\nStamping: " .. short)
	return itemstack
end

function lw_tools.sample_node(itemstack, pos)
	local node = core.get_node(pos)
	if node.name == "ignore" or node.name == "air" then
		return nil, "Nothing to sample."
	end
	lw_tools.set_paint_node(itemstack, node.name, node.param2)
	return itemstack, ("Sampled %s (param2=%d)"):format(node.name, node.param2)
end

function lw_tools.paint_node(itemstack, pos)
	local name, param2 = lw_tools.get_paint_node(itemstack)
	if not core.registered_nodes[name] then
		return nil, "Unknown node: " .. name
	end
	local current = core.get_node(pos)
	if current.name == "ignore" then
		return nil, "That node is not loaded."
	end
	if current.name == "air" then
		return nil, "Point at a node to stamp. Sneak+use samples."
	end
	if current.name == name and current.param2 == param2 then
		return itemstack
	end
	core.set_node(pos, {name = name, param2 = param2})
	return itemstack
end

function lw_tools.cycle_wool(itemstack, step)
	local names = lw_tools.wool_names()
	local current = lw_tools.get_paint_node(itemstack)
	local index = 1
	for i, name in ipairs(names) do
		if name == current then
			index = i
			break
		end
	end
	local next_index = (index - 1 + (step or 1)) % #names + 1
	lw_tools.set_paint_node(itemstack, names[next_index], 0)
	return itemstack, "Paint: " .. names[next_index]
end

--------------------------------------------------------------------------
-- Param2
--------------------------------------------------------------------------

function lw_tools.nudge_param2(pos, delta)
	local node = core.get_node(pos)
	if node.name == "ignore" or node.name == "air" then
		return nil, "Point at a node."
	end
	node.param2 = (node.param2 + delta) % 256
	core.swap_node(pos, node)
	return node.param2
end

--------------------------------------------------------------------------
-- Clone
--------------------------------------------------------------------------

function lw_tools.copy_region(p1, p2)
	local minp, maxp, size, volume = lw_tools.check_clone_volume(p1, p2)
	if not minp then
		return nil, maxp
	end
	local nodes = {}
	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				local node = core.get_node({x = x, y = y, z = z})
				if node.name == "ignore" then
					return nil, "That region is not fully loaded."
				end
				nodes[#nodes + 1] = {
					x = x - minp.x,
					y = y - minp.y,
					z = z - minp.z,
					name = node.name,
					param1 = node.param1 or 0,
					param2 = node.param2 or 0,
				}
			end
		end
	end
	return {
		size = size,
		volume = volume,
		nodes = nodes,
	}, ("Copied %dx%dx%d (%d nodes). Sneak+right click pastes.")
		:format(size.x, size.y, size.z, volume)
end

function lw_tools.paste_region(clipboard, origin)
	if not clipboard or not clipboard.nodes then
		return nil, "Copy a region first (sneak+left click)."
	end
	origin = {
		x = math.floor(origin.x + 0.5),
		y = math.floor(origin.y + 0.5),
		z = math.floor(origin.z + 0.5),
	}
	for _, node in ipairs(clipboard.nodes) do
		core.set_node({
			x = origin.x + node.x,
			y = origin.y + node.y,
			z = origin.z + node.z,
		}, {
			name = node.name,
			param1 = node.param1,
			param2 = node.param2,
		})
	end
	local size = clipboard.size
	return clipboard.volume, ("Pasted %dx%dx%d at %s.")
		:format(size.x, size.y, size.z, core.pos_to_string(origin))
end

--------------------------------------------------------------------------
-- Light
--------------------------------------------------------------------------

local HIDDEN = "lw_nodes:hidden_light"

function lw_tools.place_light(pos)
	local node = core.get_node(pos)
	if node.name == "ignore" then
		return nil, "That spot is not loaded."
	end
	if node.name == HIDDEN then
		return true, "Already a hidden light."
	end
	if node.name ~= "air" then
		local def = core.registered_nodes[node.name]
		if not (def and def.buildable_to) then
			return nil, "That spot is occupied."
		end
	end
	core.set_node(pos, {name = HIDDEN})
	return true, "Hidden light placed."
end

function lw_tools.remove_light(pos)
	local node = core.get_node(pos)
	if node.name ~= HIDDEN then
		return nil, "No hidden light there."
	end
	core.remove_node(pos)
	return true, "Hidden light removed."
end

--------------------------------------------------------------------------
-- Schematic stamp
--------------------------------------------------------------------------

function lw_tools.stamp_index(itemstack)
	local meta = itemstack:get_meta()
	local index = meta:get_int("stamp")
	if index < 1 or index > #lw_tools.STAMPS then
		index = 1
	end
	return index
end

function lw_tools.cycle_stamp(itemstack, step)
	local index = lw_tools.stamp_index(itemstack)
	local next_index = (index - 1 + (step or 1)) % #lw_tools.STAMPS + 1
	local meta = itemstack:get_meta()
	meta:set_int("stamp", next_index)
	local kind = lw_tools.STAMPS[next_index]
	meta:set_string("description",
		"Schematic Stamp\nUse: place " .. kind:gsub("_", " ") .. "\n" ..
		"Sneak+use: next stamp\nRight click: previous stamp")
	return itemstack, "Stamp: " .. kind:gsub("_", " ")
end

function lw_tools.current_stamp(itemstack)
	return lw_tools.STAMPS[lw_tools.stamp_index(itemstack)]
end

-- Nodes the stamp writes. Interior of a frame is omitted so hanging it over
-- pixel art does not erase the picture — the same trick gallery_frame.mts uses.
function lw_tools.stamp_nodes(kind, origin, facedir)
	facedir = facedir or 0
	local nodes = {}
	local function put(x, y, z, name, param2)
		nodes[#nodes + 1] = {
			pos = {x = origin.x + x, y = origin.y + y, z = origin.z + z},
			node = {name = name, param2 = param2 or 0},
		}
	end

	if kind == "column" then
		-- Matches plaza_column.mts: four column shafts, a gold capital, a lamp.
		for y = 0, 3 do
			put(0, y, 0, "lw_nodes:column")
		end
		put(0, 4, 0, "lw_nodes:gold_trim")
		put(0, 5, 0, "lw_nodes:lamp")
	elseif kind == "seat_row" then
		local right = lw_tools.right_of(facedir)
		for i = 0, lw_tools.SEAT_ROW_LENGTH - 1 do
			put(right.x * i, 0, right.z * i, "lw_theater:seat", facedir)
		end
	elseif kind == "frame" then
		local right = lw_tools.right_of(facedir)
		local n = lw_tools.FRAME_SIZE
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				if i == 0 or i == n - 1 or j == 0 or j == n - 1 then
					put(right.x * i, j, right.z * i, "lw_nodes:frame")
				end
			end
		end
	else
		return nil, "Unknown stamp: " .. tostring(kind)
	end
	return nodes
end

function lw_tools.place_stamp(kind, origin, facedir)
	local nodes, err = lw_tools.stamp_nodes(kind, origin, facedir)
	if not nodes then
		return nil, err
	end
	for _, entry in ipairs(nodes) do
		local current = core.get_node(entry.pos)
		if current.name == "ignore" then
			return nil, "That area is not fully loaded."
		end
	end
	for _, entry in ipairs(nodes) do
		core.set_node(entry.pos, entry.node)
	end
	return #nodes, ("Placed %s (%d nodes)."):format(kind:gsub("_", " "), #nodes)
end

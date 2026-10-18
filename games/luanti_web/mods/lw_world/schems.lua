-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Committed schematics and the in-game tools that author them.
--
-- Buildings live in lw_world/schems/*.mts, in git, next to the code that says
-- where they go. init.lua declares each placement with schem(), and those
-- placements are stamped into chunks exactly like the box ops, so a fresh world
-- gets them on first generation and an existing world is never overwritten.
--
-- The authoring loop needs no WorldEdit:
--
--   /lw_schem wand              get the selection wand (punch = pos1, place = pos2)
--   /lw_schem save <name>       write <world>/schems/<name>.mts
--   cp <world>/schems/<name>.mts games/luanti_web/mods/lw_world/schems/
--
-- For a piece init.lua already places, `/lw_schem save <name>` with no
-- selection re-exports its own footprint, and `/lw_schem place <name>` stamps
-- the committed file back over an existing world. See the game README.

local schems = {}

local MODPATH = core.get_modpath("lw_world")
schems.dir = MODPATH .. DIR_DELIM .. "schems"

local function world_dir()
	return core.get_worldpath() .. DIR_DELIM .. "schems"
end

local function valid_name(name)
	return type(name) == "string" and name:match("^[%w_]+$") ~= nil
end

--------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------

local loaded = {}

-- Reads <modpath>/schems/<name>.mts into a compact form the stamper can index
-- without allocating per node: `nodes[i]` is an index into `names`, or 0 for a
-- node the schematic never places. Probabilities other than "never" are treated
-- as "always" — the showcase is authored, so it must come out the same on every
-- world.
--
-- read_schematic is used rather than place_schematic because a file loaded by
-- name is cached by the engine for the life of the server, and because the
-- stamper has to clip a piece to whichever chunk is being generated.
function schems.load(name)
	assert(valid_name(name), ("lw_world: bad schematic name %q"):format(tostring(name)))
	if loaded[name] then
		return loaded[name]
	end
	local path = schems.dir .. DIR_DELIM .. name .. ".mts"
	local schem = core.read_schematic(path, {write_yslice_prob = "none"})
	-- Fail at load time: a missing piece would otherwise be a silent hole in
	-- the world that nobody notices until a visitor walks into it.
	assert(schem, "lw_world: cannot read schematic " .. path)

	local names, index_of = {}, {}
	local nodes, param2 = {}, {}
	for i, entry in ipairs(schem.data) do
		if entry.prob == 0 or entry.name == "ignore" then
			nodes[i] = 0
		else
			local n = index_of[entry.name]
			if not n then
				n = #names + 1
				names[n] = entry.name
				index_of[entry.name] = n
			end
			nodes[i] = n
		end
		param2[i] = entry.param2 or 0
	end

	local piece = {
		name = name,
		path = path,
		size = schem.size,
		names = names,
		nodes = nodes,
		param2 = param2,
	}
	loaded[name] = piece
	return piece
end

-- The node at a piece-local offset (0-based), or nil when the piece leaves that
-- node alone. Used by init.lua to check that a piece still lines up with the
-- code that depends on it.
function schems.node_at(piece, x, y, z)
	local sx, sy = piece.size.x, piece.size.y
	local n = piece.nodes[z * sy * sx + y * sx + x + 1]
	return n and n ~= 0 and piece.names[n] or nil
end

-- Swap only the nodes that differ from a loaded piece. Used by the living
-- building so a frame change is a handful of swap_node calls rather than a
-- VoxelManip of the whole footprint. Returns the number of swaps, or nil if
-- any cell is still `ignore` (mapblock not loaded) — in that case nothing is
-- written, so a half-applied frame cannot stall the WASM worker.
function schems.apply_diff(piece, origin)
	local sx, sy, sz = piece.size.x, piece.size.y, piece.size.z
	local changes = {}
	for z = 0, sz - 1 do
		for y = 0, sy - 1 do
			for x = 0, sx - 1 do
				local n = piece.nodes[z * sy * sx + y * sx + x + 1]
				if n ~= 0 then
					local pos = {x = origin.x + x, y = origin.y + y, z = origin.z + z}
					local current = core.get_node(pos)
					if current.name == "ignore" then
						return nil
					end
					local target = piece.names[n]
					local param2 = piece.param2[z * sy * sx + y * sx + x + 1]
					if current.name ~= target or current.param2 ~= param2 then
						changes[#changes + 1] = {
							pos = pos,
							node = {name = target, param2 = param2},
						}
					end
				end
			end
		end
	end
	for _, change in ipairs(changes) do
		core.swap_node(change.pos, change.node)
	end
	return #changes
end

--------------------------------------------------------------------------
-- Authoring
--------------------------------------------------------------------------

-- Everything below needs the `server` privilege, which only the singleplayer
-- host has; a visitor walking the demo never sees any of it.

local selections = {}

local function sorted_box(a, b)
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

local function describe_selection(name)
	local sel = selections[name] or {}
	if sel.pos1 and sel.pos2 then
		local p1, p2 = sorted_box(sel.pos1, sel.pos2)
		local size = vector.add(vector.subtract(p2, p1), 1)
		return ("Selection %s..%s (%dx%dx%d)"):format(core.pos_to_string(p1),
			core.pos_to_string(p2), size.x, size.y, size.z)
	end
	return ("pos1 = %s, pos2 = %s"):format(
		sel.pos1 and core.pos_to_string(sel.pos1) or "unset",
		sel.pos2 and core.pos_to_string(sel.pos2) or "unset")
end

function schems.set_pos(name, which, pos)
	selections[name] = selections[name] or {}
	selections[name][which] = vector.round(pos)
	return describe_selection(name)
end

core.register_on_leaveplayer(function(player)
	selections[player:get_player_name()] = nil
end)

-- A thin selection tool instead of WorldEdit: two clicks and a chat command.
core.register_tool("lw_world:schem_wand", {
	description = "Schematic Wand\n" ..
		"Left click a node: pos1\n" ..
		"Right click a node: pos2\n" ..
		"Then /lw_schem save <name>",
	inventory_image = "lw_fence.png^[colorize:#e0b000:140",
	stack_max = 1,
	groups = {not_in_creative_inventory = 1},
	on_use = function(itemstack, user, pointed)
		if user and user:is_player() and pointed.type == "node" then
			local name = user:get_player_name()
			if core.check_player_privs(name, "server") then
				core.chat_send_player(name, schems.set_pos(name, "pos1", pointed.under))
			end
		end
		return itemstack
	end,
	on_place = function(itemstack, placer, pointed)
		if placer and placer:is_player() and pointed.type == "node" then
			local name = placer:get_player_name()
			if core.check_player_privs(name, "server") then
				core.chat_send_player(name, schems.set_pos(name, "pos2", pointed.under))
			end
		end
		return itemstack
	end,
})

-- Save p1..p2 (any order) as <world>/schems/<name>.mts and call
-- done(ok, path, nodes_with_meta) once it is written. The area is generated
-- first, because create_schematic only sees blocks that exist.
--
-- `skip` is a node list in find_nodes_in_area form ("air", "group:lw_wool").
-- Those nodes are written with probability 0, so placing the piece leaves
-- whatever is already there: a frame that does not erase the art inside it, a
-- doorway that does not fill the room behind it.
function schems.save(p1, p2, name, skip, done)
	assert(valid_name(name), ("lw_world: bad schematic name %q"):format(tostring(name)))
	p1, p2 = sorted_box(p1, p2)
	local path = world_dir() .. DIR_DELIM .. name .. ".mts"
	core.mkdir(world_dir())
	core.emerge_area(p1, p2, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		local probabilities
		if skip and #skip > 0 then
			probabilities = {}
			for _, pos in ipairs(core.find_nodes_in_area(p1, p2, skip)) do
				probabilities[#probabilities + 1] = {pos = pos, prob = 0}
			end
		end
		local ok = core.create_schematic(p1, p2, probabilities, path)
		if done then
			done(ok, path, #core.find_nodes_with_meta(p1, p2))
		end
	end)
end

local function parse_skip(args)
	for _, word in ipairs(args) do
		local list = word:match("^skip=(.+)$")
		if list then
			return list:split(",")
		end
	end
end

-- `hooks` comes from init.lua, which owns the placements:
--   pieces        name -> {instances = {{x0, y0, z0, x1, y1, z1}, ...}, skip = {...}}
--   restamp(name, done)   re-apply that piece's placements to the live map
function schems.register_commands(hooks)
	local function cmd_save(name, args)
		local piece_name = args[2]
		if not valid_name(piece_name) then
			return false, "Usage: /lw_schem save <name> [skip=node,group:x] " ..
				"(letters, digits and _ only)"
		end
		local sel = selections[name] or {}
		local declared = hooks.pieces[piece_name]
		local skip = parse_skip(args)
		local p1, p2
		if sel.pos1 and sel.pos2 then
			p1, p2 = sorted_box(sel.pos1, sel.pos2)
		elseif declared then
			-- Re-exporting a committed piece: take its own footprint, and its
			-- own skip list, so a round trip does not change what it touches.
			local box = declared.instances[1]
			p1 = vector.new(box.x0, box.y0, box.z0)
			p2 = vector.new(box.x1, box.y1, box.z1)
			skip = skip or declared.skip
		else
			return false, "Nothing selected. Use /lw_schem pos1 and pos2, or the wand " ..
				"(/lw_schem wand)."
		end

		schems.save(p1, p2, piece_name, skip, function(ok, path, with_meta)
			if not ok then
				core.chat_send_player(name, "Could not write " .. path)
				return
			end
			local message = ("Saved %s..%s to %s — commit it with: cp %s " ..
				"games/luanti_web/mods/lw_world/schems/"):format(core.pos_to_string(p1),
				core.pos_to_string(p2), path, path)
			if with_meta > 0 then
				message = message .. (" (%d nodes carry metadata such as infotext; " ..
					".mts does not store it, so keep those as label() calls in " ..
					"lw_world/init.lua)"):format(with_meta)
			end
			core.chat_send_player(name, message)
		end)
		return true, "Saving " .. piece_name .. "…"
	end

	local function cmd_place(name, args)
		local piece_name = args[2]
		if not hooks.pieces[piece_name] then
			return false, "Not a piece lw_world places: " .. tostring(piece_name) ..
				". See /lw_schem list."
		end
		hooks.restamp(piece_name, function(count)
			core.chat_send_player(name, ("Stamped %d placement(s) of %s from %s")
				:format(count, piece_name, schems.dir))
		end)
		return true, "Placing " .. piece_name .. "…"
	end

	local function cmd_list()
		local lines = {"Pieces lw_world places (from " .. schems.dir .. "):"}
		local names = {}
		for piece_name in pairs(hooks.pieces) do
			names[#names + 1] = piece_name
		end
		table.sort(names)
		for _, piece_name in ipairs(names) do
			local piece = loaded[piece_name]
			lines[#lines + 1] = ("  %s  %dx%dx%d  x%d"):format(piece_name,
				piece.size.x, piece.size.y, piece.size.z,
				#hooks.pieces[piece_name].instances)
		end
		local exported = core.get_dir_list(world_dir(), false) or {}
		table.sort(exported)
		if #exported > 0 then
			lines[#lines + 1] = "Exported in this world (" .. world_dir() .. "):"
			for _, file in ipairs(exported) do
				lines[#lines + 1] = "  " .. file
			end
		end
		return true, table.concat(lines, "\n")
	end

	core.register_chatcommand("lw_schem", {
		params = "pos1 | pos2 | wand | list | save <name> [skip=node,group:x] | place <name>",
		description = "Author the showcase's committed schematics",
		privs = {server = true},
		func = function(name, param)
			local args = param:split(" ")
			local sub = args[1]
			if sub == "pos1" or sub == "pos2" then
				local player = core.get_player_by_name(name)
				if not player then
					return false, "You have to be in the world."
				end
				return true, schems.set_pos(name, sub, player:get_pos())
			elseif sub == "wand" then
				local player = core.get_player_by_name(name)
				if not player then
					return false, "You have to be in the world."
				end
				player:get_inventory():add_item("main", "lw_world:schem_wand")
				return true, "Left click a node for pos1, right click for pos2."
			elseif sub == "save" then
				return cmd_save(name, args)
			elseif sub == "place" then
				return cmd_place(name, args)
			elseif sub == "list" then
				return cmd_list()
			end
			return false, "Usage: /lw_schem " .. core.registered_chatcommands.lw_schem.params
		end,
	})
end

return schems

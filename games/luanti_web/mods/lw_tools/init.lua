-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Visitor-facing creative toolkit for the web showcase. These are the items
-- a first-time guest gets instead of picks and swords: paint, clone, lights,
-- a Param2 nudger, a one-click schematic stamp, and (in lw_theater) the
-- Screen Remote. Nothing here has durability or a crafting recipe.

lw_tools = {}

local MP = core.get_modpath("lw_tools")
dofile(MP .. DIR_DELIM .. "logic.lua")

local function chat(player, message)
	if player and player:is_player() and message then
		core.chat_send_player(player:get_player_name(), message)
	end
end

local function pointed_under(pointed)
	if pointed and pointed.type == "node" then
		return pointed.under
	end
end

local function pointed_above(pointed)
	if pointed and pointed.type == "node" then
		return pointed.above
	end
end

local function look_facedir(player)
	if not player or not player.get_look_dir then
		return 0
	end
	return lw_tools.facedir_from_dir(player:get_look_dir())
end

-- Craftitems, not tools: no wear bar, no groupcaps, no combat. stack_max 1
-- so /stuff and the join restock can see "already have one".
local function register_kit_item(name, def)
	def.stack_max = 1
	def.range = def.range or 10
	core.register_craftitem("lw_tools:" .. name, def)
end

--------------------------------------------------------------------------
-- Param2 tool
--------------------------------------------------------------------------
-- Same gestures as devtest's testtools:param2tool, which stays in that game
-- as the engine QA counterpart. F5 shows the pointed node's param2.

register_kit_item("param2", {
	description = "Param2 Tool\n" ..
		"Punch: +1    Sneak+punch: +8\n" ..
		"Place: -1    Sneak+place: -8",
	inventory_image = "lw_param2.png",
	on_use = function(itemstack, user, pointed)
		local pos = pointed_under(pointed)
		if not pos then
			return itemstack
		end
		local delta = lw_tools.player_sneaking(user) and 8 or 1
		lw_tools.nudge_param2(pos, delta)
		return itemstack
	end,
	on_place = function(itemstack, user, pointed)
		local pos = pointed_under(pointed)
		if not pos then
			return itemstack
		end
		local delta = lw_tools.player_sneaking(user) and -8 or -1
		lw_tools.nudge_param2(pos, delta)
		return itemstack
	end,
})

--------------------------------------------------------------------------
-- Paint tool
--------------------------------------------------------------------------

register_kit_item("paint", {
	description = "Paint Tool\n" ..
		"Sneak+use: sample\n" ..
		"Use: stamp onto pointed node\n" ..
		"Right click: cycle wool palette",
	inventory_image = "lw_paint.png",
	on_use = function(itemstack, user, pointed)
		local pos = pointed_under(pointed)
		if not pos then
			return itemstack
		end
		local stack, message
		if lw_tools.player_sneaking(user) then
			stack, message = lw_tools.sample_node(itemstack, pos)
		else
			stack, message = lw_tools.paint_node(itemstack, pos)
		end
		chat(user, message)
		return stack or itemstack
	end,
	on_place = function(itemstack, user, pointed)
		local stack, message = lw_tools.cycle_wool(itemstack,
			lw_tools.player_sneaking(user) and -1 or 1)
		chat(user, message)
		return stack or itemstack
	end,
	on_secondary_use = function(itemstack, user)
		local stack, message = lw_tools.cycle_wool(itemstack,
			lw_tools.player_sneaking(user) and -1 or 1)
		chat(user, message)
		return stack or itemstack
	end,
})

--------------------------------------------------------------------------
-- Clone stick
--------------------------------------------------------------------------

local clones = {}

local function clone_state(player)
	local name = player:get_player_name()
	clones[name] = clones[name] or {}
	return clones[name], name
end

register_kit_item("clone", {
	description = "Clone Stick\n" ..
		"Left click: pos1    Right click: pos2\n" ..
		"Sneak+left: copy    Sneak+right: paste\n" ..
		"Volume cap 32³",
	inventory_image = "lw_clone.png",
	on_use = function(itemstack, user, pointed)
		if not (user and user:is_player()) then
			return itemstack
		end
		local state = clone_state(user)
		if lw_tools.player_sneaking(user) then
			if not (state.pos1 and state.pos2) then
				chat(user, "Set pos1 (left click) and pos2 (right click) first.")
				return itemstack
			end
			local clip, message = lw_tools.copy_region(state.pos1, state.pos2)
			if clip then
				state.clipboard = clip
			end
			chat(user, message)
			return itemstack
		end
		local pos = pointed_under(pointed)
		if not pos then
			return itemstack
		end
		state.pos1 = pos
		chat(user, "pos1 = " .. core.pos_to_string(pos))
		return itemstack
	end,
	on_place = function(itemstack, user, pointed)
		if not (user and user:is_player()) then
			return itemstack
		end
		local state = clone_state(user)
		if lw_tools.player_sneaking(user) then
			local origin = pointed_above(pointed) or pointed_under(pointed)
			if not origin then
				return itemstack
			end
			local _, message = lw_tools.paste_region(state.clipboard, origin)
			chat(user, message)
			return itemstack
		end
		local pos = pointed_under(pointed)
		if not pos then
			return itemstack
		end
		state.pos2 = pos
		chat(user, "pos2 = " .. core.pos_to_string(pos))
		return itemstack
	end,
	on_secondary_use = function(itemstack, user, pointed)
		if not (user and user:is_player() and lw_tools.player_sneaking(user)) then
			return itemstack
		end
		local state = clone_state(user)
		local origin = user:get_pos()
		if pointed and pointed.type == "node" then
			origin = pointed_above(pointed) or pointed_under(pointed)
		end
		local _, message = lw_tools.paste_region(state.clipboard, origin)
		chat(user, message)
		return itemstack
	end,
})

core.register_on_leaveplayer(function(player)
	clones[player:get_player_name()] = nil
end)

--------------------------------------------------------------------------
-- Light wand
--------------------------------------------------------------------------

local function remove_hidden_light(under, above)
	local ok, message = lw_tools.remove_light(under)
	if ok or not above then
		return message
	end
	return select(2, lw_tools.remove_light(above))
end

register_kit_item("light_wand", {
	description = "Light Wand\n" ..
		"Use: place a hidden light in front of the pointed node\n" ..
		"Sneak+use or right click: remove a hidden light",
	inventory_image = "lw_light_wand.png",
	on_use = function(itemstack, user, pointed)
		local under = pointed_under(pointed)
		local above = pointed_above(pointed)
		if not under then
			return itemstack
		end
		local message
		if lw_tools.player_sneaking(user) then
			message = remove_hidden_light(under, above)
		elseif core.get_node(under).name == "lw_nodes:hidden_light" then
			message = select(2, lw_tools.remove_light(under))
		else
			message = select(2, lw_tools.place_light(above or under))
		end
		chat(user, message)
		return itemstack
	end,
	on_place = function(itemstack, user, pointed)
		local under = pointed_under(pointed)
		local above = pointed_above(pointed)
		if not under then
			return itemstack
		end
		chat(user, remove_hidden_light(under, above))
		return itemstack
	end,
})

--------------------------------------------------------------------------
-- Schematic stamp
--------------------------------------------------------------------------

register_kit_item("stamp", {
	description = "Schematic Stamp\n" ..
		"Use: place seat row\n" ..
		"Sneak+use: next stamp (seat row / column / frame)\n" ..
		"Right click: previous stamp",
	inventory_image = "lw_stamp.png",
	on_use = function(itemstack, user, pointed)
		if lw_tools.player_sneaking(user) then
			local stack, message = lw_tools.cycle_stamp(itemstack, 1)
			chat(user, message)
			return stack or itemstack
		end
		local origin = pointed_above(pointed)
		if not origin then
			chat(user, "Point at a surface to stamp.")
			return itemstack
		end
		local _, message = lw_tools.place_stamp(
			lw_tools.current_stamp(itemstack), origin, look_facedir(user))
		chat(user, message)
		return itemstack
	end,
	on_place = function(itemstack, user, pointed)
		local stack, message = lw_tools.cycle_stamp(itemstack, -1)
		chat(user, message)
		return stack or itemstack
	end,
	on_secondary_use = function(itemstack, user)
		local stack, message = lw_tools.cycle_stamp(itemstack, -1)
		chat(user, message)
		return stack or itemstack
	end,
})

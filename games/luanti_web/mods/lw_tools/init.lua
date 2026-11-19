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

--------------------------------------------------------------------------
-- Laser wand
--------------------------------------------------------------------------
-- The Around arena's laser beam, in a visitor's hand: the same thin glowing
-- upright_sprite, posed with lw_maps.beam_pose, that puts itself away after a
-- few seconds. Nothing is saved and nothing is placed in the map.

core.register_entity("lw_tools:laser", {
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
	_life = lw_tools.LASER_LIFETIME,
	on_activate = function(self, staticdata)
		self._life = tonumber(staticdata) or lw_tools.LASER_LIFETIME
	end,
	on_step = function(self, dtime)
		self._life = self._life - dtime
		if self._life <= 0 then
			self.object:remove()
		end
	end,
})

local lasers = {}   -- player name -> {beams = {...}, fired = n, mark = pos}

local function laser_state(player)
	local name = player:get_player_name()
	lasers[name] = lasers[name] or {beams = {}, fired = 0}
	return lasers[name]
end

local function alive(object)
	return object ~= nil and object:get_pos() ~= nil
end

local function fire_laser(player, from, to, lifetime)
	local centre, rotation, length = lw_maps.beam_pose(from, to)
	if not centre then
		return nil
	end
	local state = laser_state(player)
	local object = core.add_entity(centre, "lw_tools:laser", tostring(lifetime))
	if not object then
		return nil
	end
	state.fired = state.fired + 1
	local face = "lw_lamp.png^[multiply:" .. lw_tools.laser_color(state.fired)
	object:set_properties({
		textures = {face, face},
		visual_size = {x = 0.08, y = length},
	})
	object:set_rotation(rotation)
	for _, old in ipairs(lw_tools.keep_laser(state.beams, object, alive)) do
		if alive(old) then
			old:remove()
		end
	end
	return object
end

local function clear_lasers(player)
	local state = laser_state(player)
	local count = 0
	for _, object in ipairs(state.beams) do
		if alive(object) then
			object:remove()
			count = count + 1
		end
	end
	state.beams = {}
	state.mark = nil
	return count
end

-- From just under the visitor's eye, a little way out, so the beam starts
-- below the crosshair instead of on top of it.
local function wand_tip(player)
	local props = player:get_properties()
	local eye = vector.offset(player:get_pos(), 0, (props and props.eye_height) or 1.625, 0)
	return vector.add(vector.offset(eye, 0, -0.25, 0),
		vector.multiply(player:get_look_dir(), 0.6))
end

register_kit_item("laser_wand", {
	description = "Laser Wand\n" ..
		"Use: fire a laser at the pointed node (a few seconds)\n" ..
		"Right click two nodes: string a laser between them\n" ..
		"Sneak+use: put all your lasers out",
	inventory_image = "lw_light_wand.png^[multiply:#ff4070",
	range = 24,
	on_use = function(itemstack, user, pointed)
		if not (user and user:is_player()) then
			return itemstack
		end
		if lw_tools.player_sneaking(user) then
			chat(user, ("%d laser(s) put out."):format(clear_lasers(user)))
			return itemstack
		end
		local under = pointed_under(pointed)
		if not under then
			return itemstack
		end
		fire_laser(user, wand_tip(user), lw_tools.face_point(under, pointed_above(pointed)),
			lw_tools.LASER_LIFETIME)
		return itemstack
	end,
	on_place = function(itemstack, user, pointed)
		if not (user and user:is_player()) then
			return itemstack
		end
		local under = pointed_under(pointed)
		if not under then
			return itemstack
		end
		local state = laser_state(user)
		local a, b = lw_tools.laser_mark(state, lw_tools.face_point(under, pointed_above(pointed)))
		if type(a) == "string" or a == nil then
			chat(user, b)
			return itemstack
		end
		fire_laser(user, a, b, lw_tools.LASER_PAIR_LIFETIME)
		chat(user, "Laser strung.")
		return itemstack
	end,
	on_secondary_use = function(itemstack, user)
		if user and user:is_player() and laser_state(user).mark then
			laser_state(user).mark = nil
			chat(user, "Mark cleared.")
		end
		return itemstack
	end,
})

core.register_on_leaveplayer(function(player)
	clear_lasers(player)
	lasers[player:get_player_name()] = nil
end)

--------------------------------------------------------------------------
-- Ember tool
--------------------------------------------------------------------------
-- A glowing ember that sputters and goes out by itself (logic.lua has the
-- pattern), with a puff of sparks when it is lit. The campfire's animated
-- tile, warmer. No damage, no drop, no spread.

local function register_ember(name, tint, light)
	core.register_node(name, {
		description = "Ember",
		drawtype = "plantlike",
		tiles = {{
			name = "lw_fire.png^[multiply:" .. tint,
			animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 0.8},
		}},
		use_texture_alpha = "blend",
		paramtype = "light",
		sunlight_propagates = true,
		walkable = false,
		buildable_to = true,
		floodable = true,
		light_source = light,
		damage_per_second = 0,
		drop = "",
		is_ground_content = false,
		groups = {dig_immediate = 3, not_in_creative_inventory = 1},
		on_construct = function(pos)
			core.get_node_timer(pos):start(lw_tools.EMBER_TICK)
		end,
		on_timer = function(pos)
			return lw_tools.ember_tick(pos)
		end,
	})
end

register_ember(lw_tools.EMBER, "#ff8a50", 11)
register_ember(lw_tools.EMBER_LOW, "#a0402a", 5)

local function sparks(pos)
	core.add_particlespawner({
		amount = 10,
		time = 0.6,
		minpos = vector.offset(pos, -0.2, -0.3, -0.2),
		maxpos = vector.offset(pos, 0.2, 0.1, 0.2),
		minvel = {x = -0.4, y = 1.0, z = -0.4},
		maxvel = {x = 0.4, y = 2.2, z = 0.4},
		minexptime = 0.4,
		maxexptime = 0.9,
		minsize = 0.6,
		maxsize = 1.4,
		glow = 14,
		texture = "lw_lamp.png^[multiply:#ff8030",
	})
end

register_kit_item("ember_tool", {
	description = "Ember Tool\n" ..
		"Use: light an ember on the pointed face (goes out by itself)\n" ..
		"Use on an ember, or sneak+use: put it out",
	inventory_image = "lw_fire.png^[verticalframe:8:0",
	on_use = function(itemstack, user, pointed)
		local under = pointed_under(pointed)
		if not under then
			return itemstack
		end
		local above = pointed_above(pointed)
		local message
		if lw_tools.is_ember(core.get_node(under).name) then
			message = select(2, lw_tools.remove_ember(under))
		elseif lw_tools.player_sneaking(user) then
			message = select(2, lw_tools.remove_ember(above or under))
		else
			local ok
			ok, message = lw_tools.place_ember(above or under)
			if ok then
				sparks(above or under)
			end
		end
		chat(user, message)
		return itemstack
	end,
})

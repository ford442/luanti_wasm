-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Everything the visitor sees or types: the bind list on the HUD, the touch
-- dance pad, `/dance`, and the stage hint.

local F = core.formspec_escape

local PAD_FORMNAME = "lw_dance:pad"

-- name -> hud element id / whether the pad is open / last stage hint time
local huds = {}
local pads = {}
local hinted = {}

--------------------------------------------------------------------------
-- Feedback
--------------------------------------------------------------------------

-- Successful moves announce themselves on the HUD, which is already on
-- screen; only refusals and mode changes are worth a chat line.
function lw_dance.feedback(player, ok, message)
	if not message then
		return
	end
	if ok then
		lw_dance.update_hud(player)
	else
		core.chat_send_player(player:get_player_name(), message)
	end
end

--------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------

local function bind_line()
	local parts = {}
	for slot = 1, 8 do
		local action = lw_dance.slots[slot]
		if action then
			local label
			if action == "@random" then
				label = "random"
			elseif action == "@stop" then
				label = "stop"
			else
				local def = lw_dance.get_move(action)
				label = (def and def.label or action):lower()
			end
			parts[#parts + 1] = ("%d %s"):format(slot, label)
		end
	end
	return table.concat(parts, "   ")
end

local function hud_text(player)
	local move = lw_dance.current_move(player)
	local def = lw_dance.get_move(move)
	local title = def and def.description or "Dance mode - stance (press a number)"
	return table.concat({
		"DANCE MODE: " .. title,
		bind_line(),
		"sneak+zoom or /dance to stop   /dance pad for buttons   /dance help",
	}, "\n")
end

function lw_dance.show_hud(player)
	local name = player:get_player_name()
	if huds[name] then
		lw_dance.update_hud(player)
		return
	end
	huds[name] = player:hud_add({
		type = "text",
		position = {x = 0.5, y = 1},
		offset = {x = 0, y = -120},
		alignment = {x = 0, y = 0},
		scale = {x = 100, y = 100},
		text = hud_text(player),
		number = 0xE9E9E4,
		z_index = 100,
		style = 0,
	})
end

function lw_dance.update_hud(player)
	local name = player:get_player_name()
	if not huds[name] then
		return
	end
	player:hud_change(huds[name], "text", hud_text(player))
	if pads[name] then
		lw_dance.show_pad(player)
	end
end

function lw_dance.hide_hud(player)
	local name = player:get_player_name()
	if huds[name] then
		player:hud_remove(huds[name])
		huds[name] = nil
	end
end

--------------------------------------------------------------------------
-- The dance pad
--------------------------------------------------------------------------

-- Six move buttons plus random and stop, in the same order as the number
-- keys, so the pad teaches the binds rather than replacing them.
local function pad_formspec(player)
	local current = lw_dance.current_move(player)
	local rows = {
		"formspec_version[4]",
		"size[9.5,4.4]",
		"label[0.4,0.55;", F("Dance pad"), "]",
		"label[0.4,1.0;", F(lw_dance.get_move(current) and
				lw_dance.get_move(current).description or "Stance"), "]",
	}
	local x, y = 0.4, 1.5
	for slot = 1, 8 do
		local action = lw_dance.slots[slot]
		if action then
			local label, field
			if action == "@random" then
				label, field = "Random", "lw_dance_random"
			elseif action == "@stop" then
				label, field = "Stop", "lw_dance_stop"
			else
				local def = lw_dance.get_move(action)
				label = def and def.label or action
				field = "lw_dance_move_" .. action
			end
			rows[#rows + 1] = ("button[%.2f,%.2f;2.05,0.9;%s;%d %s]")
					:format(x, y, field, slot, F(label))
			x = x + 2.25
			if slot % 4 == 0 then
				x = 0.4
				y = y + 1.1
			end
		end
	end
	return table.concat(rows)
end

function lw_dance.show_pad(player)
	local name = player:get_player_name()
	pads[name] = true
	core.show_formspec(name, PAD_FORMNAME, pad_formspec(player))
end

function lw_dance.hide_pad(player)
	local name = player:get_player_name()
	if pads[name] then
		pads[name] = nil
		core.close_formspec(name, PAD_FORMNAME)
	end
end

-- Touch clients get the pad without asking, because they have no number
-- keys. On a keyboard client the pad stays opt-in: a formspec takes pointer
-- lock off the canvas in the browser, and the toggle must not do that.
function lw_dance.maybe_show_pad(player)
	local info = core.get_player_window_information
			and core.get_player_window_information(player:get_player_name())
	if info and info.touch_controls then
		lw_dance.show_pad(player)
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= PAD_FORMNAME then
		return
	end
	local name = player:get_player_name()
	if fields.quit then
		pads[name] = nil
		return true
	end
	if fields.lw_dance_stop then
		local ok, message = lw_dance.exit(player)
		lw_dance.feedback(player, ok, message)
		return true
	end
	if fields.lw_dance_random then
		local pick = lw_dance.random_move()
		if pick then
			local ok, message = lw_dance.play(player, pick)
			lw_dance.feedback(player, ok, message)
		end
		return true
	end
	for field in pairs(fields) do
		local move = field:match("^lw_dance_move_(.+)$")
		if move then
			local ok, message = lw_dance.play(player, move)
			lw_dance.feedback(player, ok, message)
			-- Keep the highlighted hotbar slot honest about the move that is
			-- now playing, so the pad and the number keys agree.
			for slot, action in pairs(lw_dance.slots) do
				if action == move then
					lw_dance.select_slot(player, slot)
				end
			end
			return true
		end
	end
	return true
end)

--------------------------------------------------------------------------
-- /dance
--------------------------------------------------------------------------

local function help_text()
	local lines = {
		"Dance mode. Toggle it with /dance, or by holding sneak and zoom together.",
		"While dance mode is on, the number keys are the moves:",
	}
	for slot = 1, 8 do
		local action = lw_dance.slots[slot]
		if action == "@random" then
			lines[#lines + 1] = ("  %d  random move from the pool (/dance random)"):format(slot)
		elseif action == "@stop" then
			lines[#lines + 1] = ("  %d  leave dance mode (/dance stop)"):format(slot)
		elseif action then
			local def = lw_dance.get_move(action)
			lines[#lines + 1] = ("  %d  %s (/dance %s)"):format(slot,
					def and def.description or action, action)
		end
	end
	lines[#lines + 1] = "Your wielded item and hotbar slot come back when you stop."
	lines[#lines + 1] = "Walking keeps the dance on your upper body and walks the legs;"
	lines[#lines + 1] = "one-shot moves like the bow hand back to the groove when they end."
	lines[#lines + 1] = "/dance pad opens a tap-friendly pad (touch clients get it on their own)."
	lines[#lines + 1] = "Third person (F7) or a mirror of a friend is how you watch yourself."
	return table.concat(lines, "\n")
end

core.register_chatcommand("dance", {
	params = "[<move> | stop | random | pad | help]",
	description = "Toggle dance mode, or play a named move",
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You have to be in the world."
		end
		param = (param or ""):trim()

		if param == "help" then
			return true, help_text()
		end

		if param == "" then
			local ok, message = lw_dance.toggle(player)
			return ok, message
		end

		if param == "stop" or param == "off" then
			return lw_dance.exit(player)
		end

		if param == "pad" then
			if not lw_dance.is_dancing(player) then
				local ok, message = lw_dance.enter(player)
				if not ok then
					return false, message
				end
			end
			lw_dance.show_pad(player)
			return true, "Dance pad open."
		end

		if param == "random" then
			param = lw_dance.random_move()
			if not param then
				return false, "No moves are registered."
			end
		end

		if not lw_dance.get_move(param) then
			return false, ("No such move: %s. /dance help lists them."):format(param)
		end

		-- `/dance <move>` is also a way in: a visitor who types a move name
		-- means the move, not the mode.
		if not lw_dance.is_dancing(player) then
			local ok, message = lw_dance.enter(player)
			if not ok then
				return false, message
			end
		end
		local ok, message = lw_dance.play(player, param)
		for slot, action in pairs(lw_dance.slots) do
			if action == param then
				lw_dance.select_slot(player, slot)
			end
		end
		return ok, message
	end,
})

--------------------------------------------------------------------------
-- The stage
--------------------------------------------------------------------------

-- Any node in the `lw_dance_stage` group suggests dance mode when a visitor
-- stands on it. The group is the hook, not a node name, so the theater stage
-- from #27 only has to join the group to light up here.
core.register_node("lw_dance:stage", {
	description = "Dance Stage",
	tiles = {
		"lw_paving.png^[colorize:#6c3fb8:80",
		"lw_polished_stone.png",
		"lw_polished_stone.png^[colorize:#6c3fb8:45",
	},
	groups = {cracky = 3, lw_palette = 1, lw_dance_stage = 1},
	is_ground_content = false,
})

local HINT_INTERVAL = 90
local stage_acc = 0

core.register_globalstep(function(dtime)
	stage_acc = stage_acc + dtime
	if stage_acc < 1 then
		return
	end
	stage_acc = 0

	local now = core.get_gametime()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if not lw_dance.is_dancing(player) and (now - (hinted[name] or -math.huge)) > HINT_INTERVAL then
			local pos = player:get_pos()
			-- The floor under the visitor, and the node their feet are in: a
			-- dance mark is a flat plate they stand *in*, not on.
			local under = core.get_node({x = pos.x, y = pos.y - 0.5, z = pos.z})
			local feet = core.get_node(pos)
			if core.get_item_group(under.name, "lw_dance_stage") > 0
					or core.get_item_group(feet.name, "lw_dance_stage") > 0 then
				hinted[name] = now
				-- Standing on a mark while the routine is running is the one
				-- case worth a different line: the answer there is to join in,
				-- not to start something of your own.
				local running = nil
				for id, director in pairs(lw_dance.running or {}) do
					if director.active then
						running = id
					end
				end
				if running and lw_dance.mark_slot and lw_dance.mark_slot[feet.name] then
					core.chat_send_player(name, ("You are on a dance mark and %s " ..
							"is running. /routine join falls in step with it, " ..
							"/dance dances on your own."):format(running))
				else
					core.chat_send_player(name,
							"You are on a stage. /dance (or hold sneak+zoom) to dance on it.")
				end
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	huds[name] = nil
	pads[name] = nil
	hinted[name] = nil
end)

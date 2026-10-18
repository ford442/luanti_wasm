-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The showcase theater.
--
-- Tier A (this file, everywhere): the screen is a wall of nodes, each owning
-- one cell of a picture that animates through a vertical filmstrip. Because
-- every cell carries a *different* crop, the wall shows one large moving image
-- instead of a tiled thumbnail. This is engine-native and works identically on
-- a native desktop build and in the browser.
--
-- Tier B (browser only): if the engine exposes core.set_web_video — it only
-- does under Emscripten — the remote can also raise an HTML5 <video> overlay
-- owned by the page, which is the one thing a web port can do that desktop
-- Luanti cannot. When that API is missing, or when the page has no clip to
-- play, Tier A keeps running and nothing else changes.

lw_theater = {}

local storage = core.get_mod_storage()

-- Must match SCREEN_COLS / SCREEN_ROWS / REEL_FRAMES / CELL in
-- util/content/generate_luanti_web_textures.py. Filmstrip authoring
-- (ffmpeg → vertical PNG) is documented in games/luanti_web/docs/filmstrips.md.
local COLS = 6
local ROWS = 4
local FRAMES = 24
local CELL = 32
local FPS = 12

lw_theater.screen_cols = COLS
lw_theater.screen_rows = ROWS
lw_theater.reel_frames = FRAMES

-- Reel order the remote and the wall button cycle through. "off" is a dark
-- screen, not a reel. Title card first so a fresh world can start on motion
-- that reads as "the show is about to begin".
lw_theater.reels = {"title", "show", "bars"}

local REEL_TITLES = {
	title = "Reel 1 — Now showing",
	show = "Reel 2 — Luanti in your browser",
	bars = "Reel 3 — Test pattern",
}

-- Optional projector sting. Sound (#8) is not required: a missing OpenAL
-- backend, a missing .ogg, or a browser autoplay block all degrade to a
-- silent animated wall.
local REEL_SOUNDS = {
	title = "lw_reel",
	show = "lw_reel",
	bars = "lw_reel",
}

--------------------------------------------------------------------------
-- Screen nodes
--------------------------------------------------------------------------

local function cell_name(reel, row, col)
	return ("lw_theater:screen_%s_%d_%d"):format(reel, row, col)
end

core.register_node("lw_theater:screen_off", {
	description = "Cinema Screen",
	tiles = {"lw_screen_off.png"},
	groups = {cracky = 2, lw_screen = 1, lw_palette = 1},
	is_ground_content = false,
})

for _, reel in ipairs(lw_theater.reels) do
	for row = 0, ROWS - 1 do
		for col = 0, COLS - 1 do
			core.register_node(cell_name(reel, row, col), {
				description = ("Cinema Screen (%s %d/%d)"):format(reel, row + 1, col + 1),
				tiles = {{
					name = ("lw_screen_%s_%d_%d.png"):format(reel, row, col),
					animation = {
						type = "vertical_frames",
						aspect_w = CELL,
						aspect_h = CELL,
						length = FRAMES / FPS,
					},
				}},
				-- A lit screen washes the room; that is most of the cinema feel.
				light_source = 9,
				drop = "lw_theater:screen_off",
				groups = {cracky = 2, lw_screen = 1, not_in_creative_inventory = 1},
				is_ground_content = false,
			})
		end
	end
end

--------------------------------------------------------------------------
-- Screen placement registry
--------------------------------------------------------------------------

-- The world mod registers where the screen wall is, so the remote never has to
-- scan the map for it. `origin` is the top-left cell as the audience sees it;
-- columns advance along +x (or +z) and rows advance downwards.
function lw_theater.register_screen(origin, right)
	storage:set_string("screen", core.serialize({
		origin = origin,
		right = right or {x = 1, y = 0, z = 0},
	}))
end

local function screen_layout()
	local raw = storage:get_string("screen")
	if raw == "" then
		return nil
	end
	local data = core.deserialize(raw)
	if not data or not data.origin then
		return nil
	end
	return data
end

local function cell_pos(layout, row, col)
	local right = layout.right
	return {
		x = layout.origin.x + right.x * col,
		y = layout.origin.y - row,
		z = layout.origin.z + right.z * col,
	}
end

function lw_theater.has_saved_reel()
	return storage:get_string("reel") ~= ""
end

function lw_theater.current_reel()
	local reel = storage:get_string("reel")
	return reel ~= "" and reel or "off"
end

--------------------------------------------------------------------------
-- House lights
--------------------------------------------------------------------------

-- The game pins time_speed to 0, so the clock only moves when the remote or
-- a chandelier moves it. Dimming for a reel and raising the lights afterwards
-- is therefore deterministic rather than a race with the day cycle.
local DAY = 0.45
local NIGHT = 0.83
local lights_up = true

lw_theater.DAY = DAY
lw_theater.NIGHT = NIGHT

function lw_theater.house_lights_are_up()
	return lights_up
end

function lw_theater.set_house_lights(up)
	lights_up = not not up
	core.set_timeofday(lights_up and DAY or NIGHT)
	return lights_up
end

function lw_theater.toggle_house_lights()
	return lw_theater.set_house_lights(not lights_up)
end

--------------------------------------------------------------------------
-- Optional reel audio
--------------------------------------------------------------------------

local reel_sound_handle = nil

local function stop_reel_audio()
	if reel_sound_handle and type(core.sound_stop) == "function" then
		pcall(core.sound_stop, reel_sound_handle)
	end
	reel_sound_handle = nil
end

local function play_reel_audio(reel)
	stop_reel_audio()
	if reel == "off" then
		return
	end
	-- Feature-detect rather than assume OpenAL: WASM sound (#8) may not be
	-- ready, and a native build can be compiled with ENABLE_SOUND=FALSE.
	if type(core.sound_play) ~= "function" then
		return
	end
	local spec = REEL_SOUNDS[reel]
	if not spec then
		return
	end
	local ok, handle = pcall(core.sound_play, spec, {gain = 0.45}, true)
	if ok then
		reel_sound_handle = handle
	end
end

-- Swap every cell in place. 24 swap_node calls is cheap enough to run on the
-- WASM application worker without a visible hitch; do not turn this into an
-- ABM.
function lw_theater.set_reel(reel)
	local layout = screen_layout()
	if not layout then
		return false, "The theater screen has not been built yet."
	end
	for row = 0, ROWS - 1 do
		for col = 0, COLS - 1 do
			local pos = cell_pos(layout, row, col)
			local node = core.get_node(pos)
			local target = reel == "off" and "lw_theater:screen_off"
				or cell_name(reel, row, col)
			-- "ignore" means the mapblock is not loaded. Leave those alone:
			-- whatever is on disk is already a screen cell, and the next
			-- switch catches it once the block comes back.
			if node.name ~= "ignore" then
				if node.name == "air" then
					-- Somebody dug a hole in the screen. Put the cell back.
					core.set_node(pos, {name = target})
				elseif core.get_item_group(node.name, "lw_screen") == 0 then
					return false, "The screen wall is obstructed at " ..
						core.pos_to_string(pos) .. "."
				elseif node.name ~= target then
					core.swap_node(pos, {name = target})
				end
			end
		end
	end
	storage:set_string("reel", reel)
	play_reel_audio(reel)
	return true
end

function lw_theater.next_reel()
	local current = lw_theater.current_reel()
	if current == "off" then
		return lw_theater.reels[1]
	end
	for index, reel in ipairs(lw_theater.reels) do
		if reel == current then
			return lw_theater.reels[index + 1] or "off"
		end
	end
	return lw_theater.reels[1]
end

--------------------------------------------------------------------------
-- Tier B: browser video overlay
--------------------------------------------------------------------------

-- Same-origin clip served next to luanti.html in media/. It is deliberately
-- NOT preloaded into luanti.data: see client/web/media/README.md.
lw_theater.web_clip = "showcase-reel.webm"

function lw_theater.web_video_available()
	return type(core.set_web_video) == "function"
end

function lw_theater.show_web_video(player)
	if not lw_theater.web_video_available() then
		return false
	end
	local ok = core.set_web_video({
		clip = lw_theater.web_clip,
		title = "Showcase reel",
		loop = true,
		-- Autoplay policy: the page starts muted and offers an unmute control.
		muted = true,
	})
	if ok and player then
		core.chat_send_player(player:get_player_name(),
			"Browser cinema: press Escape or use the overlay's Close button to return.")
	end
	return ok
end

function lw_theater.hide_web_video()
	if not lw_theater.web_video_available() then
		return false
	end
	return core.clear_web_video()
end

--------------------------------------------------------------------------
-- Seats
--------------------------------------------------------------------------

-- Sit pose is cheap: the default character.b3d already has a sit range
-- (frames 81–160, same as minetest_game's player_api). No seat entity, so a
-- reconnect cannot leak attachments. Jump or /sit stands you back up.
local SIT_FRAMES = {x = 81, y = 160}
local seated = {}

local function is_player(obj)
	return obj and obj:is_player()
end

function lw_theater.unsit_player(player)
	if not is_player(player) then
		return
	end
	local name = player:get_player_name()
	if not seated[name] then
		return
	end
	seated[name] = nil
	if player.set_animation then
		player:set_animation({x = 0, y = 79}, 15, 0, true)
	end
	if player.set_eye_offset then
		player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
	end
	if player.set_physics_override then
		player:set_physics_override({speed = 1, jump = 1})
	end
end

function lw_theater.sit_player(player)
	if not is_player(player) then
		return false
	end
	local name = player:get_player_name()
	seated[name] = true
	if player.set_animation then
		player:set_animation(SIT_FRAMES, 15, 0, true)
	end
	if player.set_eye_offset then
		player:set_eye_offset({x = 0, y = -5, z = 2}, {x = 0, y = -5, z = 0})
	end
	if player.set_physics_override then
		player:set_physics_override({speed = 0, jump = 0})
	end
	return true
end

function lw_theater.is_seated(player)
	return is_player(player) and seated[player:get_player_name()] == true
end

-- Place the visitor on the seat, point them at the screen, and fold them
-- into the sit pose. Doubles as the calibrated camera Tier B wants.
function lw_theater.seat_player(player, pos)
	local layout = screen_layout()
	player:set_pos({x = pos.x, y = pos.y + 0.6, z = pos.z})
	if layout then
		local centre = cell_pos(layout, ROWS / 2, (COLS - 1) / 2)
		local dx = centre.x - pos.x
		local dz = centre.z - pos.z
		player:set_look_horizontal((math.atan2(-dx, dz) + math.pi * 2) % (math.pi * 2))
		player:set_look_vertical(0)
	end
	lw_theater.sit_player(player)
end

core.register_globalstep(function()
	for name in pairs(seated) do
		local player = core.get_player_by_name(name)
		if not player then
			seated[name] = nil
		else
			local ctrl = player:get_player_control()
			-- Jump is the "stand up" gesture. Walking keys also release so a
			-- visitor is never stuck in a seat after they decide to leave.
			if ctrl and (ctrl.jump or ctrl.up or ctrl.down or ctrl.left or ctrl.right) then
				lw_theater.unsit_player(player)
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	if player then
		seated[player:get_player_name()] = nil
	end
end)

core.register_node("lw_theater:seat", {
	description = "Theater Seat",
	drawtype = "nodebox",
	tiles = {"lw_seat_top.png", "lw_seat_side.png", "lw_seat_side.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	on_place = core.rotate_node,
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, -0.125, 0.5},
			{-0.5, -0.125, 0.25, 0.5, 0.5, 0.5},
		},
	},
	groups = {snappy = 2, oddly_breakable_by_hand = 2, lw_palette = 1},
	is_ground_content = false,
	on_rightclick = function(pos, _, clicker)
		if is_player(clicker) then
			lw_theater.seat_player(clicker, pos)
		end
	end,
})

core.register_node("lw_theater:aisle_light", {
	description = "Aisle Light",
	drawtype = "nodebox",
	tiles = {"lw_aisle_light.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	on_place = core.rotate_node,
	light_source = 7,
	node_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.25, 0.5}},
	groups = {cracky = 3, lw_palette = 1},
	is_ground_content = false,
})

core.register_node("lw_theater:marquee", {
	description = "Marquee Block",
	tiles = {{
		name = "lw_marquee.png",
		animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 1.2},
	}},
	light_source = 12,
	groups = {cracky = 2, lw_palette = 1},
	is_ground_content = false,
})

-- Punch to dim the house. Diggable is false so a creative visitor cannot
-- accidentally take the fixture down while reaching for the dimmer.
core.register_node("lw_theater:chandelier", {
	description = "Theater Chandelier\nPunch to dim or raise the house lights",
	drawtype = "nodebox",
	tiles = {"lw_chandelier.png"},
	paramtype = "light",
	light_source = 12,
	diggable = false,
	node_box = {
		type = "fixed",
		fixed = {
			{-0.0625, 0.25, -0.0625, 0.0625, 0.5, 0.0625},
			{-0.375, -0.125, -0.375, 0.375, 0.25, 0.375},
			{-0.4375, -0.25, -0.4375, 0.4375, -0.0625, 0.4375},
		},
	},
	groups = {lw_palette = 1},
	is_ground_content = false,
	on_punch = function(_, _, puncher)
		local up = lw_theater.toggle_house_lights()
		if is_player(puncher) then
			core.chat_send_player(puncher:get_player_name(),
				up and "House lights up." or "House lights down.")
		end
	end,
})

--------------------------------------------------------------------------
-- The remote and the wall button
--------------------------------------------------------------------------

-- The Screen Remote is the only *item* that talks to the theater. Paint, clone
-- and the schematic stamp must not call set_reel / show_web_video themselves:
-- they go through lw_theater.on_remote so a later playback backend can land
-- without hunting for every item callback. If this hook is missing (a world
-- running without the theater mod), the item itself prints a chat hint.
--
-- The wall button is the in-world counterpart: punch it for the next reel so
-- a visitor who has not opened the inventory still sees motion change.

lw_theater.REMOTE_ACTIONS = { "next", "pause", "play" }

local function announce_reel(player, reel)
	local name = player:get_player_name()
	if reel == "off" then
		core.chat_send_player(name, "Screen off. House lights up.")
	else
		core.chat_send_player(name, REEL_TITLES[reel] or reel)
	end
end

local function cycle(player)
	local reel = lw_theater.next_reel()
	local ok, err = lw_theater.set_reel(reel)
	if not ok then
		core.chat_send_player(player:get_player_name(), err)
		return
	end
	lw_theater.set_house_lights(reel == "off")
	if reel == "off" then
		lw_theater.hide_web_video()
	end
	announce_reel(player, reel)
end

local function pause(player)
	local name = player:get_player_name()
	local ok, err = lw_theater.set_reel("off")
	if not ok then
		core.chat_send_player(name, err)
		return
	end
	lw_theater.hide_web_video()
	lw_theater.overlay_on = false
	lw_theater.set_house_lights(true)
	core.chat_send_player(name, "Screen off. House lights up.")
end

local function toggle_overlay(player)
	local name = player:get_player_name()
	if not lw_theater.web_video_available() then
		-- Tier A still works: "play" turns the animated wall on when it is
		-- dark, otherwise points at the next-reel gesture.
		if lw_theater.current_reel() == "off" then
			local ok, err = lw_theater.set_reel(lw_theater.reels[1])
			if not ok then
				core.chat_send_player(name, err)
				return
			end
			lw_theater.set_house_lights(false)
			core.chat_send_player(name, REEL_TITLES[lw_theater.reels[1]]
				or lw_theater.reels[1])
			return
		end
		core.chat_send_player(name,
			"Video overlay is a browser-only feature. The animated screen " ..
			"(left click with the remote) works everywhere.")
		return
	end
	if lw_theater.overlay_on then
		lw_theater.hide_web_video()
		lw_theater.overlay_on = false
		core.chat_send_player(name, "Overlay closed.")
	else
		if lw_theater.show_web_video(player) then
			lw_theater.overlay_on = true
			lw_theater.set_house_lights(false)
		else
			core.chat_send_player(name, "The browser could not start the clip.")
		end
	end
end

-- action: "next" | "pause" | "play". Returns true when the action ran.
function lw_theater.on_remote(player, action)
	if not is_player(player) then
		return false
	end
	if action == "next" then
		cycle(player)
		return true
	elseif action == "pause" then
		pause(player)
		return true
	elseif action == "play" then
		toggle_overlay(player)
		return true
	end
	core.chat_send_player(player:get_player_name(),
		"Unknown remote action: " .. tostring(action))
	return false
end

local function fire_remote(player, action)
	local handler = lw_theater.on_remote
	if type(handler) ~= "function" then
		if is_player(player) then
			core.chat_send_player(player:get_player_name(),
				"The Screen Remote does nothing until the theater is loaded.")
		end
		return
	end
	handler(player, action)
end

core.register_node("lw_theater:button", {
	description = "Reel Button\nPunch: next reel",
	drawtype = "nodebox",
	tiles = {"lw_reel_button.png"},
	paramtype = "light",
	light_source = 4,
	node_box = {
		type = "fixed",
		fixed = {
			{-0.3125, -0.5, -0.3125, 0.3125, -0.25, 0.3125},
			{-0.1875, -0.25, -0.1875, 0.1875, 0.0, 0.1875},
		},
	},
	groups = {cracky = 3, lw_palette = 1},
	is_ground_content = false,
	on_punch = function(_, _, puncher)
		if is_player(puncher) then
			fire_remote(puncher, "next")
		end
	end,
	on_rightclick = function(_, _, clicker)
		if is_player(clicker) then
			fire_remote(clicker, "next")
		end
	end,
})

core.register_craftitem("lw_theater:remote", {
	description = "Screen Remote\n" ..
		"Left click: next reel\n" ..
		"Sneak+left: pause (screen off)\n" ..
		"Right click: play (browser overlay, or the animated wall)",
	inventory_image = "lw_remote.png",
	stack_max = 1,
	on_use = function(itemstack, user)
		if is_player(user) then
			local ctrl = user:get_player_control()
			fire_remote(user, (ctrl and ctrl.sneak) and "pause" or "next")
		end
		return itemstack
	end,
	on_place = function(itemstack, placer)
		if is_player(placer) then
			fire_remote(placer, "play")
		end
		return itemstack
	end,
	on_secondary_use = function(itemstack, user)
		if is_player(user) then
			fire_remote(user, "play")
		end
		return itemstack
	end,
})

core.register_chatcommand("reel", {
	params = "[off|" .. table.concat(lw_theater.reels, "|") .. "]",
	description = "Switch the theater screen to a reel",
	func = function(name, param)
		param = param:trim()
		if param == "" then
			return true, "Now showing: " .. lw_theater.current_reel()
		end
		local known = param == "off"
		for _, reel in ipairs(lw_theater.reels) do
			known = known or reel == param
		end
		if not known then
			return false, "Unknown reel. Try: off, " ..
				table.concat(lw_theater.reels, ", ")
		end
		local ok, err = lw_theater.set_reel(param)
		if not ok then
			return false, err
		end
		lw_theater.set_house_lights(param == "off")
		return true, REEL_TITLES[param] or "Screen off."
	end,
})

core.register_chatcommand("sit", {
	params = "",
	description = "Sit down where you stand, or stand up",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You have to be in the world."
		end
		if lw_theater.is_seated(player) then
			lw_theater.unsit_player(player)
			return true, "Standing."
		end
		lw_theater.sit_player(player)
		return true, "Sitting. Jump to stand up."
	end,
})

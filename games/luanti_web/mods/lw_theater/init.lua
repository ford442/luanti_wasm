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
-- util/content/generate_luanti_web_textures.py.
local COLS = 6
local ROWS = 4
local FRAMES = 16
local CELL = 32
local FPS = 12

lw_theater.screen_cols = COLS
lw_theater.screen_rows = ROWS

-- Reel order the remote cycles through. "off" is a dark screen, not a reel.
lw_theater.reels = {"bars", "show"}

local REEL_TITLES = {
	bars = "Reel 1 — Test Pattern",
	show = "Reel 2 — Luanti in your browser",
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

function lw_theater.current_reel()
	local reel = storage:get_string("reel")
	return reel ~= "" and reel or "off"
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
-- House lights
--------------------------------------------------------------------------

-- The game pins time_speed to 0, so the clock only moves when the remote moves
-- it. Dimming for a reel and raising the lights afterwards is therefore
-- deterministic rather than a race with the day cycle.
local DAY = 0.45
local NIGHT = 0.83

local function set_house_lights(up)
	core.set_timeofday(up and DAY or NIGHT)
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

-- Not a real sit pose — attaching the player to an entity costs an entity per
-- seat and a pile of edge cases on reconnect. Placing the visitor on the seat
-- and pointing them at the screen gives the same "take your seat" beat, and
-- doubles as the calibrated camera Tier B wants.
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
end

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
		if clicker and clicker:is_player() then
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

--------------------------------------------------------------------------
-- The remote
--------------------------------------------------------------------------

local function cycle(player)
	local reel = lw_theater.next_reel()
	local ok, err = lw_theater.set_reel(reel)
	local name = player:get_player_name()
	if not ok then
		core.chat_send_player(name, err)
		return
	end
	set_house_lights(reel == "off")
	if reel == "off" then
		lw_theater.hide_web_video()
		core.chat_send_player(name, "Screen off. House lights up.")
	else
		core.chat_send_player(name, REEL_TITLES[reel] or reel)
	end
end

local function toggle_overlay(player)
	local name = player:get_player_name()
	if not lw_theater.web_video_available() then
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
			set_house_lights(false)
		else
			core.chat_send_player(name, "The browser could not start the clip.")
		end
	end
end

core.register_craftitem("lw_theater:remote", {
	description = "Screen Remote\n" ..
		"Left click: next reel\n" ..
		"Right click: browser video overlay (web client only)",
	inventory_image = "lw_remote.png",
	stack_max = 1,
	on_use = function(itemstack, user)
		if user and user:is_player() then
			cycle(user)
		end
		return itemstack
	end,
	on_place = function(itemstack, placer)
		if placer and placer:is_player() then
			toggle_overlay(placer)
		end
		return itemstack
	end,
	on_secondary_use = function(itemstack, user)
		if user and user:is_player() then
			toggle_overlay(user)
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
		set_house_lights(param == "off")
		return true, REEL_TITLES[param] or "Screen off."
	end,
})

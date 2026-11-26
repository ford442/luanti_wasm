#!/usr/bin/env lua
-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Headless checks for theater Tier A. Stubs `core` and loads lw_theater so
-- reel cycling, house lights, sit pose and the optional sound path can be
-- exercised without a running engine.
--
--   lua util/content/test_luanti_web_theater.lua
--   (also invoked by util/content/test_luanti_web_theater.py)

local SCRIPT = arg[0]
local ROOT = SCRIPT:match("^(.*)/util/content/") or "."
local INIT = ROOT .. "/games/luanti_web/mods/lw_theater/init.lua"

local failures = 0

local function fail(message)
	failures = failures + 1
	io.stderr:write("FAIL: " .. message .. "\n")
end

local function assert_true(cond, message)
	if not cond then
		fail(message)
	end
end

local function assert_eq(got, expected, message)
	if got ~= expected then
		fail(("%s: got %s, expected %s"):format(message, tostring(got), tostring(expected)))
	end
end

function string.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

DIR_DELIM = "/"

--------------------------------------------------------------------------
-- Stub engine
--------------------------------------------------------------------------

local world = {}
local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local kv = {}
local ser = {}
local ser_id = 0
local tod = 0.45
local sounds = {}
local chat = {}
local players = {}
local commands = {}
local globalsteps = {}

core = {
	registered_nodes = {},
	registered_items = {},
	registered_chatcommands = commands,
	pos_to_string = function(pos)
		return ("(%d,%d,%d)"):format(pos.x, pos.y, pos.z)
	end,
	get_node = function(pos)
		return world[key(pos)] or {name = "air", param1 = 0, param2 = 0}
	end,
	set_node = function(pos, node)
		world[key(pos)] = {
			name = node.name,
			param1 = node.param1 or 0,
			param2 = node.param2 or 0,
		}
	end,
	swap_node = function(pos, node)
		core.set_node(pos, node)
	end,
	serialize = function(value)
		ser_id = ser_id + 1
		ser[ser_id] = value
		return tostring(ser_id)
	end,
	deserialize = function(s)
		return ser[tonumber(s)]
	end,
	get_mod_storage = function()
		return {
			get_string = function(_, k) return kv[k] or "" end,
			set_string = function(_, k, v) kv[k] = v end,
		}
	end,
	set_timeofday = function(value)
		tod = value
	end,
	get_timeofday = function()
		return tod
	end,
	sound_play = function(spec)
		sounds[#sounds + 1] = spec
		return #sounds
	end,
	sound_stop = function()
	end,
	chat_send_player = function(name, message)
		chat[#chat + 1] = name .. ": " .. message
	end,
	get_player_by_name = function(name)
		return players[name]
	end,
	get_item_group = function(name, group)
		local def = core.registered_nodes[name]
		return def and def.groups and def.groups[group] or 0
	end,
	register_node = function(name, def)
		def = def or {}
		def.name = name
		core.registered_nodes[name] = def
		core.registered_items[name] = def
	end,
	register_craftitem = function(name, def)
		def = def or {}
		def.name = name
		core.registered_items[name] = def
	end,
	register_chatcommand = function(name, def)
		commands[name] = def
	end,
	register_globalstep = function(fn)
		globalsteps[#globalsteps + 1] = fn
	end,
	register_on_leaveplayer = function()
	end,
	rotate_node = function()
	end,
}

dofile(INIT)

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function FakePlayer(name)
	local pos = {x = 0, y = 10, z = 40}
	local ctrl = {}
	local anim, eye, physics
	local player
	player = {
		is_player = function() return true end,
		get_player_name = function() return name end,
		get_pos = function() return pos end,
		set_pos = function(_, p) pos = p end,
		set_look_horizontal = function() end,
		set_look_vertical = function() end,
		get_player_control = function() return ctrl end,
		set_animation = function(_, range) anim = range end,
		set_eye_offset = function(_, first) eye = first end,
		set_physics_override = function(_, override) physics = override end,
		ctrl = ctrl,
		anim = function() return anim end,
		eye = function() return eye end,
		physics = function() return physics end,
		pos = function() return pos end,
	}
	players[name] = player
	return player
end

local function build_screen()
	lw_theater.register_screen({x = 0, y = 10, z = 0}, {x = 1, y = 0, z = 0})
	for row = 0, lw_theater.screen_rows - 1 do
		for col = 0, lw_theater.screen_cols - 1 do
			core.set_node({x = col, y = 10 - row, z = 0}, {name = "lw_theater:screen_off"})
		end
	end
end

--------------------------------------------------------------------------
-- Contract
--------------------------------------------------------------------------

assert_eq(lw_theater.screen_cols, 6, "screen cols")
assert_eq(lw_theater.screen_rows, 4, "screen rows")
assert_eq(lw_theater.reel_frames, 24, "reel frames")
assert_eq(lw_theater.reels[1], "title", "title reel first")
assert_eq(lw_theater.reels[2], "show", "show reel")
assert_eq(lw_theater.reels[3], "bars", "bars reel")
assert_true(core.registered_nodes["lw_theater:screen_title_0_0"] ~= nil, "title cell missing")
assert_true(core.registered_nodes["lw_theater:screen_show_3_5"] ~= nil, "show cell missing")
assert_true(core.registered_nodes["lw_theater:screen_bars_1_2"] ~= nil, "bars cell missing")
assert_true(core.registered_nodes["lw_theater:chandelier"] ~= nil, "chandelier missing")
assert_true(core.registered_nodes["lw_theater:button"] ~= nil, "button missing")
assert_true(core.registered_nodes["lw_theater:chandelier"].diggable == false,
	"chandelier must not be dug by a dimmer punch")

local title_tile = core.registered_nodes["lw_theater:screen_title_0_0"].tiles[1]
assert_eq(title_tile.animation.type, "vertical_frames", "animation type")
assert_eq(title_tile.animation.aspect_w, 32, "aspect_w")
assert_eq(title_tile.animation.aspect_h, 32, "aspect_h")
assert_eq(title_tile.animation.length, 24 / 12, "animation length")

--------------------------------------------------------------------------
-- Reel cycling
--------------------------------------------------------------------------

build_screen()
assert_eq(lw_theater.current_reel(), "off", "fresh storage is off")
assert_true(not lw_theater.has_saved_reel(), "fresh storage has no saved reel")

local ok, err = lw_theater.set_reel("title")
assert_true(ok, "set_reel title failed: " .. tostring(err))
assert_eq(lw_theater.current_reel(), "title", "current after title")
assert_true(lw_theater.has_saved_reel(), "title should persist")
assert_eq(core.get_node({x = 0, y = 10, z = 0}).name, "lw_theater:screen_title_0_0",
	"top-left cell")
assert_eq(core.get_node({x = 5, y = 7, z = 0}).name, "lw_theater:screen_title_3_5",
	"bottom-right cell")
assert_true(#sounds >= 1, "title reel should attempt the projector sting")

assert_eq(lw_theater.next_reel(), "show", "title -> show")
ok = lw_theater.set_reel("show")
assert_true(ok, "set_reel show")
assert_eq(core.get_node({x = 2, y = 8, z = 0}).name, "lw_theater:screen_show_2_2",
	"show cell mid-wall")
assert_eq(lw_theater.next_reel(), "bars", "show -> bars")
ok = lw_theater.set_reel("bars")
assert_true(ok, "set_reel bars")
assert_eq(lw_theater.next_reel(), "off", "bars -> off")
ok = lw_theater.set_reel("off")
assert_true(ok, "set_reel off")
assert_eq(core.get_node({x = 0, y = 10, z = 0}).name, "lw_theater:screen_off",
	"off restores dark cells")
assert_eq(lw_theater.next_reel(), "title", "off -> title")

--------------------------------------------------------------------------
-- House lights / chandelier
--------------------------------------------------------------------------

lw_theater.set_house_lights(true)
assert_true(lw_theater.house_lights_are_up(), "lights start up")
assert_eq(tod, lw_theater.DAY, "day time")
lw_theater.toggle_house_lights()
assert_true(not lw_theater.house_lights_are_up(), "toggle dims")
assert_eq(tod, lw_theater.NIGHT, "night time")

local puncher = FakePlayer("dimmer")
core.registered_nodes["lw_theater:chandelier"].on_punch(nil, nil, puncher)
assert_true(lw_theater.house_lights_are_up(), "chandelier punch raises")
core.registered_nodes["lw_theater:chandelier"].on_punch(nil, nil, puncher)
assert_true(not lw_theater.house_lights_are_up(), "chandelier punch dims")

--------------------------------------------------------------------------
-- Remote + wall button
--------------------------------------------------------------------------

local user = FakePlayer("usher")
local before = #chat
lw_theater.on_remote(user, "next")
assert_eq(lw_theater.current_reel(), "title", "remote next from off")
assert_true(not lw_theater.house_lights_are_up(), "reel dims the house")
assert_true(#chat > before, "remote announces the reel")

core.registered_nodes["lw_theater:button"].on_punch(nil, nil, user)
assert_eq(lw_theater.current_reel(), "show", "button cycles to show")

lw_theater.on_remote(user, "pause")
assert_eq(lw_theater.current_reel(), "off", "pause")
assert_true(lw_theater.house_lights_are_up(), "pause raises lights")

--------------------------------------------------------------------------
-- Sound degrades if the backend is missing
--------------------------------------------------------------------------

core.sound_play = nil
ok = lw_theater.set_reel("title")
assert_true(ok, "set_reel must succeed without sound_play")
core.sound_play = function(spec)
	sounds[#sounds + 1] = spec
	error("backend refused")
end
ok = lw_theater.set_reel("show")
assert_true(ok, "set_reel must succeed when sound_play throws")

--------------------------------------------------------------------------
-- Sit pose
--------------------------------------------------------------------------

local sitter = FakePlayer("patron")
lw_theater.seat_player(sitter, {x = 1, y = 9, z = 20})
assert_true(lw_theater.is_seated(sitter), "seated after seat_player")
assert_eq(sitter.pos().y, 9.6, "seat height")
assert_eq(sitter.anim().x, 81, "sit start frame")
assert_eq(sitter.physics().speed, 0, "seated players do not walk")

commands.sit.func("patron")
assert_true(not lw_theater.is_seated(sitter), "/sit toggles stand")
commands.sit.func("patron")
assert_true(lw_theater.is_seated(sitter), "/sit toggles sit")

sitter.ctrl.jump = true
for _, step in ipairs(globalsteps) do
	step()
end
assert_true(not lw_theater.is_seated(sitter), "jump stands you up")

--------------------------------------------------------------------------
-- /reel
--------------------------------------------------------------------------

local reel_ok, reel_msg = commands.reel.func("usher", "")
assert_true(reel_ok, "/reel status")
assert_true(reel_msg:find("show", 1, true) or reel_msg:find("title", 1, true)
	or reel_msg:find("off", 1, true) or reel_msg:find("bars", 1, true),
	"/reel status mentions the current reel")
reel_ok, reel_msg = commands.reel.func("usher", "nope")
assert_true(not reel_ok, "unknown reel rejected")

if failures > 0 then
	io.stderr:write(failures .. " theater checks failed\n")
	os.exit(1)
end
print("theater Tier A checks ok")

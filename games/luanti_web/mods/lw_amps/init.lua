-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Stage amps: a song played out of two cabinets.
--
-- Luanti only places a sound in the world if it is a single-channel Ogg. A
-- stereo file is played with no position at all (and the engine warns about
-- it), so a stereo mix cannot come out of a pair of cabs. Each song therefore
-- ships as two mono files cut from the original left and right channels:
--
--   lw_amps_<song>_l.ogg   the original left channel  -> audience-left cab
--   lw_amps_<song>_r.ogg   the original right channel -> audience-right cab
--
-- `_l` / `_r` rather than `.1` / `.2`, because `<name>.<digit>.ogg` is a random
-- sound group and the engine would play only one of the two.
--
-- The pair is started together, in the same server step, with the same
-- `start_time`, so the stereo image survives: a visitor standing between the
-- cabs hears the mix the way it was recorded. A visitor who walks in later is
-- given the pair at `start_time = elapsed % length` and lands in time with
-- everyone else. That clock is also what the dance director (lw_dance) reads,
-- which is how the band on stage stays on the beat of the song coming out of
-- the cabs.

lw_amps = {}

local storage = core.get_mod_storage()

--------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------

-- `max_hear_distance` only admits players who are inside it when a playback
-- *starts*; a player outside it then hears nothing until a new playback is
-- started for them. That is why the sweep below starts the pair per player as
-- they come into range rather than once for everybody.
lw_amps.DEFAULT_HEAR = 80

-- Positional gain is the level at three nodes from the source. It does not get
-- louder inside one node, and OpenAL clamps the final gain at 1, so a gain
-- above 1 does not make the cab louder close up — it carries full volume
-- further out. 3 keeps the floor in front of the stage at full level.
lw_amps.DEFAULT_GAIN = 3

-- How often listeners are checked: who has walked into range and needs the
-- pair, who has walked well out of it and can give their sources back.
local SWEEP_INTERVAL = 1.0

-- A listener is released this far past the hearing distance, not at it, so a
-- visitor pacing along the edge does not restart the song every second.
local RELEASE_MARGIN = 16

-- How far `/amp left` / `/amp right` look for the cab being pointed at.
local POINT_RANGE = 10

--------------------------------------------------------------------------
-- Songs
--------------------------------------------------------------------------

-- name -> {name, title, length, bpm, sounds = {left, right}}
lw_amps.songs = {}
lw_amps.song_order = {}
lw_amps.default_song = nil

-- `length` is the duration of the files in seconds, measured from the files
-- themselves (ffprobe) — it is what `start_time` wraps on, so a guess would
-- drift a late arriver out of time by the error on every loop.
function lw_amps.register_song(name, def)
	assert(type(name) == "string" and name:match("^[a-z0-9_]+$"),
			"lw_amps.register_song: name has to be lowercase letters, digits and _")
	assert(type(def) == "table" and type(def.length) == "number" and def.length > 0,
			"lw_amps.register_song: " .. name .. " needs a positive length")
	def = table.copy(def)
	def.name = name
	def.title = def.title or name
	def.sounds = {
		left = "lw_amps_" .. name .. "_l",
		right = "lw_amps_" .. name .. "_r",
	}
	if not lw_amps.songs[name] then
		lw_amps.song_order[#lw_amps.song_order + 1] = name
	end
	lw_amps.songs[name] = def
	lw_amps.default_song = lw_amps.default_song or name
	return def
end

function lw_amps.get_song(name)
	return name and lw_amps.songs[name] or nil
end

-- Lace Waterfall, "Around": the happy-hard mix and its six alternate takes.
-- Every pair was checked to have the same duration on both channels.
local AROUND = {
	{"around_happy_hard",   159.021474, "Around (happy hard)"},
	{"around_happy_hard_1", 199.328413, "Around (happy hard, take 1)"},
	{"around_happy_hard_2", 152.229637, "Around (happy hard, take 2)"},
	{"around_happy_hard_3", 162.835351, "Around (happy hard, take 3)"},
	{"around_happy_hard_4", 152.934943, "Around (happy hard, take 4)"},
	{"around_happy_hard_5", 155.521066, "Around (happy hard, take 5)"},
	{"around_happy_hard_6", 160.458209, "Around (happy hard, take 6)"},
}
for _, take in ipairs(AROUND) do
	lw_amps.register_song(take[1], {
		title = take[3],
		artist = "Lace Waterfall",
		length = take[2],
		bpm = 175,
	})
end

--------------------------------------------------------------------------
-- The cabs
--------------------------------------------------------------------------

-- Where each side's sound comes from: one node above the cab, so the source is
-- at ear height for the floor rather than inside the box.
local amps = {left = nil, right = nil}

local settings = {
	hear = lw_amps.DEFAULT_HEAR,
	gain = lw_amps.DEFAULT_GAIN,
}

local function load_state()
	for _, side in ipairs({"left", "right"}) do
		local stored = storage:get_string(side)
		if stored ~= "" then
			amps[side] = core.string_to_pos(stored)
		end
	end
	local hear = tonumber(storage:get_string("hear"))
	if hear and hear > 0 then
		settings.hear = hear
	end
	local gain = tonumber(storage:get_string("gain"))
	if gain and gain > 0 then
		settings.gain = gain
	end
end
load_state()

function lw_amps.get_amps()
	return amps.left and vector.copy(amps.left) or nil,
			amps.right and vector.copy(amps.right) or nil
end

-- `pos` is the sound source itself. Code that builds a stage (the companion
-- arena) calls this directly; a visitor uses /amp left and /amp right.
function lw_amps.set_amp(side, pos)
	assert(side == "left" or side == "right", "lw_amps.set_amp: side is left or right")
	amps[side] = pos and vector.copy(pos) or nil
	storage:set_string(side, pos and core.pos_to_string(amps[side]) or "")
end

function lw_amps.set_amps(left, right)
	lw_amps.set_amp("left", left)
	lw_amps.set_amp("right", right)
end

function lw_amps.get_settings()
	return {hear = settings.hear, gain = settings.gain}
end

function lw_amps.set_hear(distance)
	if type(distance) ~= "number" or distance <= 0 then
		return false
	end
	settings.hear = distance
	storage:set_string("hear", tostring(distance))
	return true
end

function lw_amps.set_gain(gain)
	if type(gain) ~= "number" or gain <= 0 then
		return false
	end
	settings.gain = gain
	storage:set_string("gain", tostring(gain))
	return true
end

--------------------------------------------------------------------------
-- Listeners
--------------------------------------------------------------------------

-- fn(event, song_name, info), event "start" or "stop". `info` carries the
-- song's def, how far into it the clock is, and the two source positions,
-- which is everything a stage needs to dance to it.
local on_song = {}

function lw_amps.register_on_song(fn)
	on_song[#on_song + 1] = fn
end

local function notify(event, name, info)
	for _, fn in ipairs(on_song) do
		local ok, err = pcall(fn, event, name, info)
		if not ok then
			core.log("error", ("lw_amps: a %s listener for %s failed: %s")
					:format(event, name, tostring(err)))
		end
	end
end

--------------------------------------------------------------------------
-- Playback
--------------------------------------------------------------------------

-- The one song that is playing, or nil. `elapsed` is accumulated from server
-- steps rather than read off the wall clock: in singleplayer the pause menu
-- stops the server and pauses every sound, and a wall-clock song would come
-- back from the menu ahead of what is actually coming out of the cabs.
local playing = nil

function lw_amps.now_playing()
	if not playing then
		return nil
	end
	return playing.name, playing.elapsed, playing.def
end

local function info_for(state)
	return {
		song = state.def,
		elapsed = state.elapsed,
		length = state.def.length,
		bpm = state.def.bpm,
		left = vector.copy(state.left),
		right = vector.copy(state.right),
	}
end

local function nearest_cab(state, pos)
	return math.min(vector.distance(pos, state.left), vector.distance(pos, state.right))
end

local function stop_for(state, name)
	local handles = state.listeners[name]
	state.listeners[name] = nil
	if not handles or type(core.sound_stop) ~= "function" then
		return
	end
	for _, handle in ipairs(handles) do
		pcall(core.sound_stop, handle)
	end
end

-- Both cabs, one player, one step. Silence is a normal outcome — no OpenAL in
-- this build, a file that is missing, a sound_play that throws — and nothing
-- else here depends on the sound having started: the clock and the dancers
-- run either way.
local function start_for(state, name)
	if state.listeners[name] or type(core.sound_play) ~= "function" then
		return false
	end
	local offset = state.elapsed % state.def.length
	local handles = {}
	for _, side in ipairs({"left", "right"}) do
		local ok, handle = pcall(core.sound_play, {name = state.def.sounds[side]}, {
			pos = state[side],
			gain = settings.gain,
			max_hear_distance = settings.hear,
			loop = true,
			start_time = offset,
			to_player = name,
		}, false)
		if ok and handle then
			handles[#handles + 1] = handle
		end
	end
	state.listeners[name] = handles
	return true
end

function lw_amps.play(name)
	name = name or lw_amps.default_song
	local def = lw_amps.get_song(name)
	if not def then
		return false, ("No such song: %s. /amp list shows them."):format(tostring(name))
	end
	if not (amps.left and amps.right) then
		return false, "Point at the audience-left cab and use /amp left, then " ..
				"the audience-right one and /amp right."
	end
	if playing then
		lw_amps.stop()
	end

	playing = {
		name = name,
		def = def,
		elapsed = 0,
		sweep = 0,
		left = vector.copy(amps.left),
		right = vector.copy(amps.right),
		listeners = {},
	}
	for _, player in ipairs(core.get_connected_players()) do
		if nearest_cab(playing, player:get_pos()) <= settings.hear then
			start_for(playing, player:get_player_name())
		end
	end
	notify("start", name, info_for(playing))
	return true, ("Playing %s."):format(def.title)
end

function lw_amps.stop()
	local state = playing
	if not state then
		return false, "Nothing is playing."
	end
	playing = nil
	for listener in pairs(state.listeners) do
		stop_for(state, listener)
	end
	notify("stop", state.name, info_for(state))
	return true, ("Stopped %s."):format(state.def.title)
end

function lw_amps.toggle(name)
	if playing then
		return lw_amps.stop()
	end
	return lw_amps.play(name)
end

function lw_amps.status()
	local left, right = lw_amps.get_amps()
	local lines = {
		("Left cab: %s · right cab: %s · hear %d · gain %.2f"):format(
			left and core.pos_to_string(left) or "not set",
			right and core.pos_to_string(right) or "not set",
			settings.hear, settings.gain),
	}
	if playing then
		local count = 0
		for _ in pairs(playing.listeners) do
			count = count + 1
		end
		lines[#lines + 1] = ("Playing %s: %.1fs of %.1fs, %d listener(s)."):format(
			playing.def.title, playing.elapsed % playing.def.length,
			playing.def.length, count)
	else
		lines[#lines + 1] = "Nothing is playing."
	end
	return table.concat(lines, "\n")
end

core.register_globalstep(function(dtime)
	local state = playing
	if not state then
		return
	end
	state.elapsed = state.elapsed + dtime
	state.sweep = state.sweep + dtime
	if state.sweep < SWEEP_INTERVAL then
		return
	end
	state.sweep = 0

	local online = {}
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		online[name] = true
		local away = nearest_cab(state, player:get_pos())
		if not state.listeners[name] and away <= settings.hear then
			start_for(state, name)
		elseif state.listeners[name] and away > settings.hear + RELEASE_MARGIN then
			-- Out of earshot: give the two sources back. A browser tab has a
			-- small OpenAL budget, and walking back in restarts the pair in
			-- time anyway.
			stop_for(state, name)
		end
	end
	for name in pairs(state.listeners) do
		if not online[name] then
			state.listeners[name] = nil
		end
	end
end)

core.register_on_leaveplayer(function(player)
	if playing then
		-- The client's sounds went with it; only the handles are left to drop.
		playing.listeners[player:get_player_name()] = nil
	end
end)

core.register_on_shutdown(function()
	if playing then
		lw_amps.stop()
	end
end)

--------------------------------------------------------------------------
-- The cab node
--------------------------------------------------------------------------

core.register_node("lw_amps:cab", {
	description = "Amp Cabinet (punch to play / stop the song)",
	tiles = {
		"lw_amps_cab_top.png", "lw_amps_cab_side.png",
		"lw_amps_cab_side.png", "lw_amps_cab_side.png",
		"lw_amps_cab_side.png", "lw_amps_cab_front.png",
	},
	paramtype = "light",
	paramtype2 = "facedir",
	is_ground_content = false,
	-- Not in lw_palette: that group fills the material library's pedestals,
	-- which are full. The cab is in the inventory like every described node.
	groups = {cracky = 2, oddly_breakable_by_hand = 2, lw_amp = 1},
	-- The in-world trigger: the song starts when a cab is punched, and the
	-- director starts the band on that same event.
	on_punch = function(pos, node, puncher)
		if not puncher or not puncher:is_player() then
			return
		end
		local _, message = lw_amps.toggle()
		core.chat_send_player(puncher:get_player_name(), message)
	end,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local _, message = lw_amps.toggle()
		core.chat_send_player(clicker:get_player_name(), message)
	end,
})

--------------------------------------------------------------------------
-- /amp
--------------------------------------------------------------------------

-- The node the player is looking at, if it is an amp.
local function pointed_amp(player)
	local props = player:get_properties()
	local eye = vector.add(player:get_pos(),
		vector.new(0, (props and props.eye_height) or 1.625, 0))
	local reach = vector.add(eye, vector.multiply(player:get_look_dir(), POINT_RANGE))
	for pointed in core.raycast(eye, reach, false, false) do
		if pointed.type == "node" then
			local name = core.get_node(pointed.under).name
			if core.get_item_group(name, "lw_amp") > 0 then
				return pointed.under
			end
			return nil, name
		end
	end
	return nil
end

local function set_from_look(player, side)
	local cab, other = pointed_amp(player)
	if not cab then
		return false, other and ("That is %s, not an amp cab."):format(other)
				or "Look at an amp cab first."
	end
	local source = vector.new(cab.x, cab.y + 1, cab.z)
	lw_amps.set_amp(side, source)
	return true, ("%s cab set: the %s channel plays from %s."):format(
		side == "left" and "Audience-left" or "Audience-right", side,
		core.pos_to_string(source))
end

local function list_songs()
	local lines = {"Songs:"}
	for _, name in ipairs(lw_amps.song_order) do
		local def = lw_amps.songs[name]
		lines[#lines + 1] = ("  %s — %s, %.0fs%s%s"):format(name, def.title,
			def.length, def.bpm and (", " .. def.bpm .. " bpm") or "",
			(playing and playing.name == name) and " [playing]" or "")
	end
	lines[#lines + 1] = "/amp left · right · play [<song>] · stop · hear <n> · gain <g> · status"
	return table.concat(lines, "\n")
end

core.register_chatcommand("amp", {
	params = "[left | right | play [<song>] | stop | hear <nodes> | gain <g> | list | status]",
	description = "Set up the stage amps and play a song through them",
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You have to be in the world."
		end
		local words = (param or ""):trim():split(" ")
		local verb = words[1] or ""

		-- Moving the cabs or changing how far they carry changes the show for
		-- everybody on the server; starting and stopping a song does not.
		local function can_configure()
			return core.check_player_privs(name, {server = true})
		end

		if verb == "" or verb == "status" then
			return true, lw_amps.status()
		elseif verb == "list" then
			return true, list_songs()
		elseif verb == "left" or verb == "right" then
			if not can_configure() then
				return false, "Setting the cabs needs the server privilege."
			end
			return set_from_look(player, verb)
		elseif verb == "hear" then
			if not can_configure() then
				return false, "Changing the hearing distance needs the server privilege."
			end
			if not lw_amps.set_hear(tonumber(words[2])) then
				return false, "Usage: /amp hear <nodes>, a positive number."
			end
			return true, ("The cabs carry %d nodes from the next play."):format(settings.hear)
		elseif verb == "gain" then
			if not can_configure() then
				return false, "Changing the gain needs the server privilege."
			end
			if not lw_amps.set_gain(tonumber(words[2])) then
				return false, "Usage: /amp gain <g>, a positive number."
			end
			return true, ("Gain is %.2f from the next play."):format(settings.gain)
		elseif verb == "play" then
			return lw_amps.play(words[2])
		elseif verb == "stop" then
			return lw_amps.stop()
		end
		return false, ("I do not know /amp %s. Try /amp list."):format(verb)
	end,
})

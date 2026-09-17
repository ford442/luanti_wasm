-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Routines: choreography as data.
--
-- A routine is a cast and a list of timed steps. It holds no entity logic and
-- no positions in the world — a routine describes *a dance*, and a stage
-- (director.lua) says where that dance happens. The same chorus line can run
-- on the theater stage, on the Halloween porch, or wherever a visitor points
-- the director, and the file below is all there is to it:
--
--   {
--     id = "chorus_line_v1",
--     loop = true,
--     bpm = 120,
--     dancers = {
--       {role = "lead",  model = "person"},
--       {role = "left",  model = "person"},
--       {role = "right", model = "person"},
--     },
--     formation = {kind = "line", spacing = 2},
--     steps = {
--       {t = 0.0,  role = "*",     move = "groove"},
--       {t = 4.0,  role = "lead",  move = "spin"},
--       {t = 8.0,  role = "left",  move = "wave", facing = "audience"},
--       {t = 12.0, role = "*",     move = "bow"},
--     },
--   }
--
-- Times are seconds, which is the timebase that always works. When a routine
-- names a `bpm`, every time is *also* kept as a beat count, and playback reads
-- the beats — which is what makes `/routine bpm <id> <n>` a real speed control
-- instead of a relabelling.

--------------------------------------------------------------------------
-- Limits
--------------------------------------------------------------------------

-- Eight dancers, and no more. Every dancer is a mesh with a skeleton the
-- server poses ten times a second, and the browser worker animates all of them
-- in the same frame as the world it is already drawing. Eight is what the
-- WASM tab holds a 16-beat loop at; the cap is enforced when a routine starts
-- rather than when it is registered, so a too-big routine still runs, just
-- short-handed and loudly.
lw_dance.MAX_DANCERS = 8

--------------------------------------------------------------------------
-- Formations
--------------------------------------------------------------------------

-- A formation returns one {right, back} offset per dancer, in the stage's own
-- frame: `right` runs along the front of the stage as the audience sees it and
-- `back` runs away from them. director.lua turns those into world positions
-- with the stage's yaw, so a formation never has to know which way north is.
--
-- Index 1 is the lead in every formation, because that is the slot the shapes
-- are built around: the point of the wedge, the middle of the line, the front
-- of the circle.
lw_dance.formations = {}

function lw_dance.register_formation(kind, fn)
	lw_dance.formations[kind] = fn
end

-- A row across the stage, lead in the middle: lead, then out to either side.
lw_dance.register_formation("line", function(count, spacing)
	local out = {}
	for index = 1, count do
		local step = math.floor(index / 2)
		local side = (index % 2 == 0) and -1 or 1
		out[index] = {right = side * step * spacing, back = 0}
	end
	return out
end)

-- A V with the lead at its point, opening away from the audience.
lw_dance.register_formation("wedge", function(count, spacing)
	local out = {}
	for index = 1, count do
		local rank = math.floor(index / 2)
		local side = (index % 2 == 0) and -1 or 1
		out[index] = {right = side * rank * spacing, back = rank * spacing * 0.8}
	end
	return out
end)

-- A ring centred on the stage, lead at the front of it.
lw_dance.register_formation("circle", function(count, spacing)
	local out = {}
	-- Keep the gap between neighbours at `spacing`, so a circle of three is
	-- small and a circle of eight is wide rather than crowded.
	local radius = count > 1 and (spacing / (2 * math.sin(math.pi / count))) or 0
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		out[index] = {
			right = math.sin(angle) * radius,
			back = radius - math.cos(angle) * radius,
		}
	end
	return out
end)

function lw_dance.formation_offsets(formation, count)
	formation = formation or {}
	local fn = lw_dance.formations[formation.kind or "line"]
			or lw_dance.formations.line
	return fn(count, formation.spacing or 2)
end

--------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------

lw_dance.routines = {}
lw_dance.routine_order = {}

local function fail(id, message)
	error(("lw_dance: routine %s: %s"):format(tostring(id), message), 0)
end

-- Seconds and beats are two views of one number. Whichever the author wrote,
-- the other is filled in here, so nothing downstream has to ask.
local function timebase(def, entry, what)
	local seconds, beats = entry.t, entry.beat
	if seconds == nil and beats == nil then
		fail(def.id, what .. " needs t (seconds) or beat")
	end
	if def.bpm then
		local per_beat = 60 / def.bpm
		seconds = seconds or beats * per_beat
		beats = beats or seconds / per_beat
	elseif seconds == nil then
		fail(def.id, what .. " is in beats but the routine has no bpm")
	end
	return seconds, beats
end

function lw_dance.register_routine(def)
	def = table.copy(def)
	if type(def.id) ~= "string" or def.id == "" then
		fail(def.id, "needs an id")
	end
	if type(def.dancers) ~= "table" or #def.dancers == 0 then
		fail(def.id, "needs at least one dancer")
	end
	if type(def.steps) ~= "table" or #def.steps == 0 then
		fail(def.id, "needs at least one step")
	end
	if def.bpm ~= nil and (type(def.bpm) ~= "number" or def.bpm <= 0) then
		fail(def.id, "bpm has to be a positive number")
	end

	def.title = def.title or def.id
	if def.loop == nil then
		def.loop = true
	end

	-- Roles are how a step finds its dancer, so they have to be unique. An
	-- unnamed dancer gets its index, which keeps a quick routine short.
	def.roles = {}
	for index, dancer in ipairs(def.dancers) do
		dancer.role = dancer.role or tostring(index)
		dancer.model = dancer.model or "person"
		if def.roles[dancer.role] then
			fail(def.id, ("two dancers both named %q"):format(dancer.role))
		end
		def.roles[dancer.role] = index
	end

	local last = 0
	for index, step in ipairs(def.steps) do
		step.t, step.beat = timebase(def, step, ("step %d"):format(index))
		if step.role == nil then
			step.role = "*"
		end
		if step.move and not lw_dance.get_move(step.move) then
			-- Not fatal: a routine that names a move some later version adds
			-- should still play the steps it can, rather than take the game
			-- down at load.
			core.log("warning", ("lw_dance: routine %s step %d wants move %q, " ..
					"which is not registered; that step will be skipped")
					:format(def.id, index, tostring(step.move)))
		end
		if step.role ~= "*" and not def.roles[step.role] then
			core.log("warning", ("lw_dance: routine %s step %d is for role %q, " ..
					"which no dancer has"):format(def.id, index, tostring(step.role)))
		end
		last = math.max(last, step.t)
	end
	table.sort(def.steps, function(a, b)
		return a.t < b.t
	end)

	-- How long one pass is. Without an explicit length a looping routine
	-- would snap back the instant its last step fired, so the default leaves
	-- that step a bar (or four seconds) to be seen in.
	if def.length or def.length_beats then
		def.length, def.length_beats = timebase(def,
			{t = def.length, beat = def.length_beats}, "length")
	else
		def.length = last + (def.bpm and (4 * 60 / def.bpm) or 4)
		def.length_beats = def.bpm and (def.length * def.bpm / 60) or nil
	end
	if def.length <= 0 then
		fail(def.id, "length has to be positive")
	end

	if not lw_dance.routines[def.id] then
		lw_dance.routine_order[#lw_dance.routine_order + 1] = def.id
	end
	lw_dance.routines[def.id] = def
	return def
end

function lw_dance.get_routine(id)
	return id and lw_dance.routines[id] or nil
end

--------------------------------------------------------------------------
-- Routine files
--------------------------------------------------------------------------

-- Routines live in the *game*, not in this mod: `games/luanti_web/routines/`.
-- That is deliberate — a map ships its dance next to the schematic it was
-- choreographed for, and adding one is dropping in a file, with no Lua to edit
-- anywhere. The game directory is readable to mods under mod security, so this
-- needs no insecure environment.
--
-- A routine file returns one routine table, or a list of them.
function lw_dance.load_routine_file(path)
	local ok, result = pcall(dofile, path)
	if not ok then
		core.log("error", ("lw_dance: cannot load routine file %s: %s")
				:format(path, tostring(result)))
		return 0
	end
	if type(result) ~= "table" then
		core.log("error", ("lw_dance: routine file %s returned %s, not a table")
				:format(path, type(result)))
		return 0
	end

	local list = result.id and {result} or result
	local count = 0
	for _, def in ipairs(list) do
		local registered, err = pcall(lw_dance.register_routine, def)
		if registered then
			count = count + 1
		else
			core.log("error", ("lw_dance: %s: %s"):format(path, tostring(err)))
		end
	end
	return count
end

function lw_dance.load_routines(dir)
	-- A game with no routines/ directory at all is not an error: the mod is
	-- perfectly usable with nothing but the moves.
	local ok, entries = pcall(core.get_dir_list, dir, false)
	if not ok or not entries then
		return 0
	end
	table.sort(entries)
	local count = 0
	for _, entry in ipairs(entries) do
		if entry:sub(-4) == ".lua" then
			count = count + lw_dance.load_routine_file(dir .. DIR_DELIM .. entry)
		end
	end
	return count
end

do
	local game = core.get_game_info and core.get_game_info()
	local dir = game and game.path and (game.path .. DIR_DELIM .. "routines")
	if dir then
		local count = lw_dance.load_routines(dir)
		core.log("action", ("lw_dance: loaded %d routine(s) from %s")
				:format(count, dir))
	end
end

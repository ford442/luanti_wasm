-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The cabaret revue: Rubella and Lillith on the cabaret club's stage, with
-- four fans on the dance floor in front of them.
--
-- Like the Around dance (lace_waterfall_around.lua) this is a dance map for
-- songs on the stage amps, but it does not name its songs: it takes every song
-- in lw_amps' "cabaret" playlist, which is whatever has been added in
-- mods/lw_amps/cabaret/songs.lua by the time the server starts. With none
-- added yet it is an ordinary routine on its own clock, so the Stage Director
-- by the cabaret's stage still puts the two of them on it.
--
-- The moves are a placeholder: a slow, swaying revue on eight-bar lines at a
-- nominal 112 bpm, written before there was a song to time it against. When
-- a song plays, its length sets the loop, but the steps keep this bpm: retime
-- the `beat` of each section (or the bpm) against the real track, or copy
-- this file per song if their tempos differ a lot.

local amps = rawget(_G, "lw_amps")
local songs = amps and amps.playlist and amps.playlist("cabaret") or {}

local SECTIONS = {
	-- beat, name, what the band does, what the fans do
	{0,  "vamp",     "sway",   "sway"},
	{16, "verse",    "groove", "sway"},
	{48, "chorus",   "wave",   "clap"},
	{64, "dance",    "groove", "groove"},
	{96, "chorus",   "wave",   "clap"},
	{112, "tag",     "sway",   "sway"},
}

local steps = {}
local function add(step)
	steps[#steps + 1] = step
end

for _, section in ipairs(SECTIONS) do
	add({beat = section[1], role = "band", move = section[3]})
	add({beat = section[1], role = "fans", move = section[4]})
end

-- A turn each in the dance break, a look at each other, and a bow to close.
add({beat = 72, role = "rubella", move = "spin"})
add({beat = 80, role = "lillith", move = "spin"})
add({beat = 88, role = "band", facing = "partner"})
add({beat = 96, role = "band", facing = "audience"})
add({beat = 124, role = "band", move = "bow"})

return {
	id = "cabaret_revue",
	title = "Cabaret revue",
	loop = true,
	bpm = 112,
	length_beats = 128,
	songs = #songs > 0 and songs or nil,
	-- Off the stage when the song ends: the cabaret is a club, not a stage
	-- set, and the director by the stage brings them back.
	on_song_stop = "stop",
	-- Rubella by the audience-left cab, Lillith by the audience-right one, as
	-- at the Around arena; the fans settle onto the dance floor below the
	-- stage. Four, not six, so the tables behind them stay clear.
	dancers = {
		{role = "rubella", model = "rubella", group = "band",
			at = {right = 1.5, back = 0}, facing = "audience"},
		{role = "lillith", model = "lillith", group = "band",
			at = {right = -1.5, back = 0}, facing = "audience"},
		{role = "fan_1", model = "crowd_1", group = "fans",
			at = {right = 3, back = -5}, facing = "away", settle = true},
		{role = "fan_2", model = "crowd_2", group = "fans",
			at = {right = 1, back = -5}, facing = "away", settle = true},
		{role = "fan_3", model = "crowd_3", group = "fans",
			at = {right = -1, back = -5}, facing = "away", settle = true},
		{role = "fan_4", model = "crowd_4", group = "fans",
			at = {right = -3, back = -5}, facing = "away", settle = true},
	},
	formation = {kind = "line", spacing = 2},
	steps = steps,
}

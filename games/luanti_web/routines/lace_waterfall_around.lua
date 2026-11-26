-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Lace Waterfall, "Around": the band and six fans, danced to the song.
--
-- This is a dance map, not a show on its own clock. `songs` names the lw_amps
-- pairs it belongs to, so the moment a cab is punched (or `/amp play`), the
-- director puts Rubella and Lillith on stage and the crowd in front of them,
-- and reads its time off the song — the band is on the same beat as the music
-- coming out of the cabs, and stays there. When the song stops they stand idle
-- in the stance until it starts again.
--
-- 175 bpm, so a bar is 1.37 s and eight bars are 32 beats (≈11 s). The
-- sections below are a placeholder structure on eight-bar lines, written
-- before anyone sat down with the track: retime them against the song (the
-- `beat` of each section is all that has to change) and the steps follow.
-- The six alternate takes share this map; the ones longer than the main mix
-- hold the outro until they loop.

local SECTIONS = {
	-- beat, name, what the band does, what the crowd does
	{0,   "intro",          "sway",     "sway"},
	{32,  "verse 1",        "groove",   "groove"},
	{80,  "pre-chorus 1",   "wave",     "clap"},
	{96,  "chorus 1",       "headbang", "pogo"},
	{160, "verse 2",        "groove",   "groove"},
	{208, "pre-chorus 2",   "wave",     "clap"},
	{224, "chorus 2",       "headbang", "pogo"},
	{288, "bridge",         "sway",     "sway"},
	{336, "build",          "stomp",    "clap"},
	{352, "final chorus",   "headbang", "pogo"},
	{432, "outro",          "groove",   "clap"},
}

local steps = {}
local function add(step)
	steps[#steps + 1] = step
end

for _, section in ipairs(SECTIONS) do
	add({beat = section[1], role = "band", move = section[3]})
	add({beat = section[1], role = "crowd", move = section[4]})
end

-- Accents on top of the sections: one member at a time takes a spin in the
-- middle of a chorus, the two face each other through the bridge, and the
-- song ends on a bow.
add({beat = 128, role = "rubella", move = "spin"})
add({beat = 144, role = "rubella", move = "headbang"})
add({beat = 256, role = "lillith", move = "spin"})
add({beat = 272, role = "lillith", move = "headbang"})
add({beat = 288, role = "band", facing = "partner"})
add({beat = 320, role = "band", move = "spin"})
add({beat = 336, role = "band", facing = "audience"})
add({beat = 456, role = "band", move = "bow"})

return {
	id = "lace_waterfall_around",
	title = "Lace Waterfall — Around",
	loop = true,
	bpm = 175,
	-- The main mix is 159.02 s, which is 463.8 beats. When the song is playing
	-- its own length is used instead; this is for `/routine start` with no
	-- amps set up, where the routine keeps its own time.
	length_beats = 464,
	songs = {
		"around_happy_hard",
		"around_happy_hard_1",
		"around_happy_hard_2",
		"around_happy_hard_3",
		"around_happy_hard_4",
		"around_happy_hard_5",
		"around_happy_hard_6",
	},
	on_song_stop = "idle",
	-- Eight is the cap (lw_dance.MAX_DANCERS): two on stage, six on the floor.
	-- `right` is stage right — the band's right as they face out, so the
	-- audience's left — and a negative `back` is toward the audience, off the
	-- front of the stage. Rubella stands by the audience-left cab, Lillith by
	-- the audience-right one.
	dancers = {
		{role = "rubella", model = "rubella", group = "band",
			at = {right = 1.5, back = 0}, facing = "audience"},
		{role = "lillith", model = "lillith", group = "band",
			at = {right = -1.5, back = 0}, facing = "audience"},
		{role = "fan_1", model = "crowd_1", group = "crowd",
			at = {right = -3, back = -5}, facing = "away", settle = true},
		{role = "fan_2", model = "crowd_2", group = "crowd",
			at = {right = 0, back = -5}, facing = "away", settle = true},
		{role = "fan_3", model = "crowd_3", group = "crowd",
			at = {right = 3, back = -5}, facing = "away", settle = true},
		{role = "fan_4", model = "crowd_4", group = "crowd",
			at = {right = -4.5, back = -7}, facing = "away", settle = true},
		{role = "fan_5", model = "crowd_5", group = "crowd",
			at = {right = -1.5, back = -7}, facing = "away", settle = true},
		{role = "fan_6", model = "crowd_6", group = "crowd",
			at = {right = 1.5, back = -7}, facing = "away", settle = true},
	},
	formation = {kind = "line", spacing = 2},
	steps = steps,
}

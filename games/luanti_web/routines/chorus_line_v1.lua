-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The house routine, on the theater stage in front of the screen.
--
-- Three people, sixteen beats, and nothing in it that a visitor cannot do from
-- the dance pad: every move here is one of the six the number keys play, which
-- is the point. Stand on a mark, `/routine join`, and the stage is dancing the
-- same bar you are.
return {
	id = "chorus_line_v1",
	title = "Chorus line",
	loop = true,
	bpm = 120,
	-- Sixteen beats at 120: eight seconds of build, then the bow, then round
	-- again. Written in beats so the bar lines survive a bpm change.
	length_beats = 32,
	dancers = {
		{role = "lead",  model = "person"},
		{role = "left",  model = "person"},
		{role = "right", model = "person"},
	},
	formation = {kind = "line", spacing = 2},
	steps = {
		{beat = 0,  role = "*",     move = "groove", facing = "audience"},
		{beat = 8,  role = "lead",  move = "spin"},
		{beat = 16, role = "left",  move = "wave",   facing = "audience"},
		{beat = 16, role = "right", move = "wave"},
		{beat = 20, role = "lead",  move = "robot"},
		{beat = 24, role = "*",     move = "bow",    facing = "audience"},
		{beat = 28, role = "*",     move = "groove"},
	},
}

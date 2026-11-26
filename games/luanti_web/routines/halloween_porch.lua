-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The porch at the end of the Halloween lane.
--
-- Slow on purpose: 72 bpm against the theater's 120, so the two stages read as
-- different places rather than as the same dance in different hats. The
-- lanterns were already flickering on their own pattern (lw_maps); nothing
-- here tries to sync to them, because a haunting that keeps perfect time is
-- not a haunting.
return {
	id = "porch_haunt",
	title = "Porch haunt",
	loop = true,
	bpm = 72,
	length_beats = 32,
	dancers = {
		-- The scarecrow leads, planted in the middle, because it is the one
		-- thing on the porch that is supposed to stand still.
		{role = "lead",  model = "scarecrow"},
		{role = "left",  model = "ghost"},
		{role = "right", model = "ghost"},
	},
	formation = {kind = "wedge", spacing = 2},
	steps = {
		{beat = 0,  role = "*",     move = "groove", facing = "audience"},
		{beat = 8,  role = "left",  move = "wave",   facing = "partner"},
		{beat = 8,  role = "right", move = "wave",   facing = "partner"},
		{beat = 16, role = "lead",  move = "robot"},
		{beat = 16, role = "left",  move = "spin",   facing = "audience"},
		{beat = 16, role = "right", move = "spin"},
		{beat = 24, role = "*",     move = "groove", facing = "audience"},
		{beat = 28, role = "lead",  move = "bow"},
	},
}

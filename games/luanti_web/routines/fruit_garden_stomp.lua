-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The giant fruit garden: one mascot in the melon bowl, one berry on the river.
--
-- Two things are being proved here, and both of them are meant to be silly.
--
-- The mascot is a cube of the same wool the garden is built from. It has no
-- skeleton, so the poses in moves.lua cannot be put on it at all — and it
-- still dances, because the director reduces each pose to the body's turn and
-- bounce and applies that to the whole entity. That is the fail-soft path: a
-- rig with no bones keeps the beat and keeps its place in the formation.
--
-- The berry rides a raft down the juice channel. It is attached to something
-- that moves on its own, and it keeps playing its clip the whole way: the
-- carrier owns where the dancer is, the routine owns what it is doing, and
-- neither one has to know about the other.
return {
	id = "fruit_stomp",
	title = "Fruit stomp",
	loop = true,
	bpm = 96,
	length_beats = 24,
	dancers = {
		{role = "lead", model = "mascot_melon"},
		{
			role = "berry",
			model = "berry",
			ride = "lw_dance:float",
			-- Relative to the stage, which is the middle of the melon bowl:
			-- twelve nodes west onto the juice channel, then five along it.
			-- y is chosen so the raft's underside sits on the surface of
			-- the juice rather than in it or over it.
			path = {
				from = {x = -12, y = 1.65, z = 0},
				to = {x = -7, y = 1.65, z = 0},
				speed = 0.8,
			},
		},
	},
	formation = {kind = "circle", spacing = 3},
	steps = {
		{beat = 0,  role = "*",     move = "stomp", facing = "audience"},
		{beat = 8,  role = "lead",  move = "spin"},
		{beat = 8,  role = "berry", move = "wave"},
		{beat = 16, role = "lead",  move = "stomp"},
		{beat = 16, role = "berry", move = "groove"},
		{beat = 20, role = "lead",  move = "robot"},
	},
}

-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The Lace Waterfall cast: Rubella and Lillith, and the six fans in front of
-- them.
--
-- They are rigs like any other (director.lua): the shared character mesh and
-- skeleton, so every move in the catalog plays on them, dressed in skins that
-- util/content/generate_luanti_web_textures.py paints from the band's stills —
-- black lace, sheer sleeves and tights, red lips, a purple choker and cuffs.
-- Rubella wears her hair with a centre part and Lillith has blunt bangs, which
-- is how the two read apart from the back of the floor.
--
-- No mouths, no lipsync: the first pass is a picture that dances. A routine
-- that wants them just names the rig (`model = "rubella"`), so any song can
-- put the same band on stage with its own dance map.

local S = lw_dance

S.register_model("rubella", S.character_rig("lw_dance_rubella.png"))
S.register_model("lillith", S.character_rig("lw_dance_lillith.png"))

-- Six fans from three skins. The second three are the same people in a
-- slightly different light and size, so the crowd is not obviously three pairs
-- of twins: one texture string per rig, no extra files in the web pack.
local CROWD = {
	{"crowd_1", "lw_dance_crowd_a.png", 1.0},
	{"crowd_2", "lw_dance_crowd_b.png", 0.97},
	{"crowd_3", "lw_dance_crowd_c.png", 0.95},
	{"crowd_4", "lw_dance_crowd_a.png^[multiply:#e4dcf2", 1.03},
	{"crowd_5", "lw_dance_crowd_b.png^[multiply:#f2e6dc", 1.01},
	{"crowd_6", "lw_dance_crowd_c.png^[multiply:#dce6f2", 0.98},
}

for _, fan in ipairs(CROWD) do
	S.register_model(fan[1], S.character_rig(fan[2], {
		visual_size = {x = fan[3], y = fan[3]},
	}))
end

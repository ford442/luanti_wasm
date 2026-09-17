-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The starter move set.
--
-- None of these are authored clips. The mesh the showcase ships
-- (character.b3d) has five frame ranges — stand, sit, lay, walk, mine — and
-- none of them is a dance, so every move here is built the way the issue
-- asks for as the fallback: a base frame range for the legs plus a
-- procedural pose on the skeleton, sent as interpolated bone-override keys.
--
-- That fallback turned out to be the better v1 anyway: bone overrides are
-- server-side, so a move replicates to every observer with no extra work,
-- and a move stays legible while the visitor walks, because the pose sits on
-- top of whatever the legs are doing.
--
-- When a multi-track glTF character lands, add `track = "dance_groove"` (and
-- the track names to the model table) and the same move plays as a real clip
-- with the pose left as the fallback for older meshes.

local register = lw_dance.register_move

-- A note on the skeleton, read straight out of the .b3d, because it explains
-- why a sign here may look backwards from what it reads as:
--
--   Player
--     Body        rest y 6.3    rest rotation: 180 degrees about Z
--       Head      rest y +6.3   rest rotation: none
--       Arm_Left  rest x +3.15  rest rotation: 180 degrees about X
--       Arm_Right rest x -3.15  rest rotation: 180 degrees about X
--       Leg_Left  rest x +1.05  rest rotation: 180 degrees about X
--       Leg_Right rest x -1.05  rest rotation: 180 degrees about X
--
-- Overrides are relative, so they compose with those rest rotations and act
-- in the *bone's* frame: on the limbs, local X and Y point the opposite way
-- from model space, and on the Body so do X and Y. Paired limbs are
-- therefore always given equal and opposite angles, which stays symmetric
-- whichever way the axis ends up pointing. If a move reads as leaning back
-- where it should lean forward, flip the sign of that one axis — the shape
-- of the move does not change.
--
-- Positions are in model units, and the character is about 12.6 units tall
-- for 1.77 nodes: roughly 7 units to the node. A 1.0 offset is a visible but
-- modest dip, which is what the bounces below are for.
--
-- Degrees and model units throughout; the driver converts.
local sin = math.sin
local cos = math.cos
local abs = math.abs
local floor = math.floor
local pi = math.pi

--------------------------------------------------------------------------
-- 1 — Groove
--------------------------------------------------------------------------

-- The home move. A two-beat bounce: hips swing one way, shoulders the other,
-- arms pump out of phase, head keeps the beat.
register("groove", {
	label = "Groove",
	description = "Groove — the idle bounce",
	anim = "stand",
	loop = true,
	track = "dance_groove",
	pose = function(t)
		local beat = t * 2.6
		local bounce = abs(sin(beat))
		return {
			Body = {
				rot = {y = sin(beat) * 14, z = sin(beat) * 5},
				pos = {y = -bounce * 0.9},
			},
			Head = {rot = {y = sin(beat) * -10, z = sin(beat) * 8}},
			Arm_Right = {rot = {x = -30 + sin(beat) * 30, z = -18}},
			Arm_Left = {rot = {x = -30 - sin(beat) * 30, z = 18}},
			Leg_Right = {rot = {x = bounce * 12}},
			Leg_Left = {rot = {x = (1 - bounce) * 12}},
		}
	end,
})

--------------------------------------------------------------------------
-- 2 — Spin
--------------------------------------------------------------------------

-- The body yaw is spun on the *Body bone*, not with set_look_horizontal:
-- wrenching the camera around in first person is unpleasant and, under
-- pointer lock, fights the mouse. Spinning the bone turns the mesh everyone
-- else can see and leaves the dancer's view where they pointed it.
register("spin", {
	label = "Spin",
	description = "Spin — body turns, arms out",
	anim = "stand",
	loop = true,
	track = "dance_spin",
	pose = function(t)
		local turn = (t * 400) % 360
		return {
			Body = {rot = {y = turn, z = sin(t * 6) * 4}},
			Head = {rot = {y = -turn * 0.2}},
			Arm_Right = {rot = {z = -78, x = -10}},
			Arm_Left = {rot = {z = 78, x = -10}},
			Leg_Right = {rot = {x = -12}},
			Leg_Left = {rot = {x = 8}},
		}
	end,
})

--------------------------------------------------------------------------
-- 3 — Wave
--------------------------------------------------------------------------

register("wave", {
	label = "Wave",
	description = "Wave — both arms up, hands swaying",
	anim = "stand",
	loop = true,
	track = "dance_wave",
	pose = function(t)
		local sway = sin(t * 4.2)
		return {
			Body = {rot = {y = sway * 8}},
			Head = {rot = {x = -12, z = sway * 10}},
			Arm_Right = {rot = {z = -150 + sway * 18, x = -20}},
			Arm_Left = {rot = {z = 150 + sway * 18, x = -20}},
			Leg_Right = {rot = {x = 4}},
			Leg_Left = {rot = {x = -4}},
		}
	end,
})

--------------------------------------------------------------------------
-- 4 — Stomp
--------------------------------------------------------------------------

-- Alternating legs on a short cycle, with the body dropping into each
-- landing. `mine` is the base range because its arm swing already reads as
-- effort; the pose then takes the arms the rest of the way.
register("stomp", {
	label = "Stomp",
	description = "Stomp — alternating kicks",
	anim = "mine",
	speed = 20,
	loop = true,
	track = "dance_stomp",
	pose = function(t)
		local beat = t * 3.4
		local right = sin(beat)
		local drop = abs(cos(beat))
		return {
			Body = {rot = {x = 6, y = right * 10}, pos = {y = -drop * 1.4}},
			Head = {rot = {x = 8}},
			Arm_Right = {rot = {x = -20 - right * 25, z = -25}},
			Arm_Left = {rot = {x = -20 + right * 25, z = 25}},
			Leg_Right = {rot = {x = right > 0 and -55 * right or 0}},
			Leg_Left = {rot = {x = right < 0 and 55 * right or 0}},
		}
	end,
})

--------------------------------------------------------------------------
-- 5 — The Robot
--------------------------------------------------------------------------

-- `snap = true` sends each key with zero interpolation, so the skeleton
-- jumps between four held poses instead of easing between them. That
-- stepping is the whole move.
local ROBOT = {
	{
		Body = {rot = {y = -14}},
		Head = {rot = {y = -22}},
		Arm_Right = {rot = {x = -90, z = -10}},
		Arm_Left = {rot = {x = 0, z = 12}},
	},
	{
		Body = {rot = {y = 0}},
		Head = {rot = {y = 0, x = -10}},
		Arm_Right = {rot = {x = -90, z = -70}},
		Arm_Left = {rot = {x = -90, z = 70}},
	},
	{
		Body = {rot = {y = 14}},
		Head = {rot = {y = 22}},
		Arm_Right = {rot = {x = 0, z = -12}},
		Arm_Left = {rot = {x = -90, z = 10}},
	},
	{
		Body = {rot = {y = 0}, pos = {y = -0.8}},
		Head = {rot = {y = 0, x = 10}},
		Arm_Right = {rot = {x = -45, z = -45}},
		Arm_Left = {rot = {x = -45, z = 45}},
	},
}

register("robot", {
	label = "Robot",
	description = "The Robot — held poses, stepwise",
	anim = "stand",
	loop = true,
	snap = true,
	track = "dance_robot",
	pose = function(t)
		return ROBOT[floor(t / 0.34) % #ROBOT + 1]
	end,
})

--------------------------------------------------------------------------
-- 6 — Bow
--------------------------------------------------------------------------

-- The one one-shot in the set: it runs once, it cannot be cut short, and it
-- hands back to the groove. Anything with a `duration` and a `next` behaves
-- this way without further code.
local BOW_DOWN = 0.5
local BOW_HOLD = 1.15

register("bow", {
	label = "Bow",
	description = "Bow — a flourish, then back to the groove",
	anim = "stand",
	loop = true,
	duration = 2.0,
	next = "groove",
	interruptible = false,
	track = "dance_bow",
	pose = function(t)
		-- Fold down, hold, unfold. `depth` is 0..1 through the bend.
		local depth
		if t < BOW_DOWN then
			depth = t / BOW_DOWN
		elseif t < BOW_HOLD then
			depth = 1
		else
			depth = math.max(0, 1 - (t - BOW_HOLD) / 0.55)
		end
		local flourish = sin(math.min(t, BOW_DOWN) / BOW_DOWN * pi)
		return {
			Body = {rot = {x = 52 * depth}, pos = {y = -1.2 * depth}},
			Head = {rot = {x = 18 * depth}},
			Arm_Right = {rot = {x = 25 * depth, z = -60 * flourish - 20 * depth}},
			Arm_Left = {rot = {x = 25 * depth, z = 30 * depth}},
			Leg_Right = {rot = {x = -14 * depth}},
			Leg_Left = {rot = {x = 10 * depth}},
		}
	end,
})

--------------------------------------------------------------------------
-- Hotbar bindings
--------------------------------------------------------------------------

-- Number keys are not readable from Lua, but hotbar *selection* is, and the
-- number keys are how a hotbar slot gets selected. So in dance mode slots
-- 1..8 are the dance keys, which costs the visitor nothing: their wielded
-- item and slot are restored the moment they leave dance mode.
--
-- The issue asked for `R` (random) and `0` (exit); neither key reaches the
-- server, so they live on slots 7 and 8 and in `/dance help`.
lw_dance.bind_slot(1, "groove")
lw_dance.bind_slot(2, "spin")
lw_dance.bind_slot(3, "wave")
lw_dance.bind_slot(4, "stomp")
lw_dance.bind_slot(5, "robot")
lw_dance.bind_slot(6, "bow")
lw_dance.bind_slot(7, "@random")
lw_dance.bind_slot(8, "@stop")

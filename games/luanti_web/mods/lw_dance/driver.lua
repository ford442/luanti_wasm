-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Playing a move on *an object*.
--
-- Dance mode (init.lua) drives one player from their keys. The director
-- (director.lua) drives a crowd of entities from a clock. Neither knows
-- anything the other does not: both go through the functions here, which take
-- an ObjectRef and a model table and never ask which kind of object it is.
-- That is what makes the catalog in moves.lua genuinely shared — a visitor
-- pressing 3 and a scarecrow on the Halloween porch are running the same
-- `wave`, from the same table, at the same phase if the director says so.
--
-- A *clip* is the little bit of state a move needs while it plays: which move,
-- how far into it, and what was last sent per bone. The caller owns the clip
-- (dance mode keeps one per player, the director keeps one per dancer), so
-- there is no registry here keyed on objects that come and go.

--------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------

-- Procedural poses are sent as sparse keys and interpolated on the client over
-- exactly one step, so a smooth dance costs ten object messages a second
-- instead of one per server step.
lw_dance.POSE_STEP = 0.1

-- The character is about 12.6 model units tall for 1.77 nodes (see moves.lua),
-- so this converts a pose's `pos` offsets into nodes for rigs that have no
-- skeleton to put them on.
local UNITS_PER_NODE = 7.1

--------------------------------------------------------------------------
-- Frame ranges and named tracks
--------------------------------------------------------------------------

function lw_dance.frame_range(model, anim)
	if type(anim) == "table" then
		return anim
	end
	return model and model.animations and model.animations[anim] or nil
end

-- The base animation: the legs. `walking` swaps in the walk cycle so a dancer
-- who moves does not skate.
function lw_dance.apply_base_animation(obj, model, def, walking)
	if not model then
		return
	end

	if model.tracks and def and def.track then
		-- Multi-track glTF path: the legs keep their own track and the move
		-- plays over it at a higher priority.
		local legs = walking and model.tracks.walk or model.tracks.idle
		if legs then
			obj:play_animation(legs, {speed = 1, loop = true, blend = 0.2})
		end
		obj:play_animation(def.track, {
			speed = def.speed or 1,
			loop = def.loop,
			blend = def.blend or 0.2,
			priority = def.priority or 1,
		})
		return
	end

	local key = walking and "walk" or (def and def.anim or "stand")
	local range = lw_dance.frame_range(model, key) or lw_dance.frame_range(model, "stand")
	if not range then
		-- A rig with no frame ranges at all (a cube mascot) is not an error:
		-- the pose fallback below is what makes it move.
		return
	end
	local speed = def and def.speed or nil
	if walking then
		speed = nil
	end
	obj:set_animation(range, speed or model.animation_speed or 30,
			def and def.blend or 0.1, def and def.loop ~= false)
end

--------------------------------------------------------------------------
-- Poses
--------------------------------------------------------------------------

local function vec_from_degrees(t)
	if not t then
		return nil
	end
	return vector.new(math.rad(t.x or 0), math.rad(t.y or 0), math.rad(t.z or 0))
end

local function vec_from_units(t)
	if not t then
		return nil
	end
	return vector.new(t.x or 0, t.y or 0, t.z or 0)
end

-- One pose keyframe. `interpolation` is the step length, so the client walks
-- from this key to the next one and the motion is continuous even though the
-- server only speaks ten times a second.
--
-- `cache` holds what was last sent per bone, so an unchanged bone costs
-- nothing: a held pose (the Robot) or a move that only uses the arms then
-- sends a handful of messages a second instead of sixty. With eight dancers on
-- one stage that dedupe is the difference between a full frame budget and a
-- stalled worker.
function lw_dance.apply_pose(obj, pose, interpolation, cache, bones)
	for _, bone in ipairs(bones or lw_dance.bones) do
		local entry = pose and pose[bone]
		local rot = vec_from_degrees(entry and entry.rot) or vector.zero()
		local pos = vec_from_units(entry and entry.pos) or vector.zero()
		local key = ("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.3f")
				:format(rot.x, rot.y, rot.z, pos.x, pos.y, pos.z, interpolation)
		if not cache or cache[bone] ~= key then
			if cache then
				cache[bone] = key
			end
			obj:set_bone_override(bone, {
				rotation = {vec = rot, interpolation = interpolation, absolute = false},
				position = {vec = pos, interpolation = interpolation, absolute = false},
			})
		end
	end
end

function lw_dance.clear_bones(obj, bones)
	for _, bone in ipairs(bones or lw_dance.bones) do
		obj:set_bone_override(bone, nil)
	end
end

-- What a pose reduces to on a rig with no skeleton: how far the body has
-- turned and how far it has dropped. A cube mascot cannot lift an arm, but it
-- can still turn and bounce on the beat, which is what "fail soft" means here
-- — the formation and the timing stay readable even when the pose does not.
function lw_dance.pose_summary(pose)
	local body = pose and pose.Body
	local rot = body and body.rot
	local pos = body and body.pos
	return {
		yaw = (rot and rot.y or 0),
		lift = (pos and pos.y or 0) / UNITS_PER_NODE,
	}
end

--------------------------------------------------------------------------
-- Clips
--------------------------------------------------------------------------

-- `model` is a table from lw_dance.models. `bones` defaults to the character
-- rig's six; a model may name its own.
function lw_dance.new_clip(model)
	return {
		model = model,
		bones = model and model.bones or nil,
		move = nil,
		def = nil,
		t = 0,
		acc = 0,
		sent = {},
		walking = false,
	}
end

-- Start `name` on `obj`. This is the entry point an NPC uses:
--
--   lw_dance.play_move(self.object, "groove", {model = model, clip = self.clip})
--
-- `opts.clip` reuses an existing clip (and its per-bone cache); without one a
-- fresh clip is made and returned. A nil `name` is the neutral stance.
-- Returns clip, ok, message.
function lw_dance.play_move(obj, name, opts)
	opts = opts or {}
	local clip = opts.clip or lw_dance.new_clip(opts.model
			or lw_dance.models[lw_dance.player_model])
	if opts.model then
		clip.model = opts.model
		clip.bones = opts.model.bones or clip.bones
	end
	if opts.walking ~= nil then
		clip.walking = opts.walking
	end

	local def = name and lw_dance.get_move(name) or nil
	if name and not def then
		return clip, false, ("No such move: %s."):format(tostring(name))
	end

	clip.move = name
	clip.def = def
	clip.t = 0
	clip.acc = 0
	clip.sent = {}

	lw_dance.apply_base_animation(obj, clip.model, def, clip.walking)
	if clip.model and clip.model.boned == false then
		return clip, true, def and (def.description or name) or "Stance."
	end
	if def and def.pose then
		lw_dance.apply_pose(obj, def.pose(0), def.snap and 0 or lw_dance.POSE_STEP,
				clip.sent, clip.bones)
	else
		lw_dance.apply_pose(obj, nil, 0.2, clip.sent, clip.bones)
	end
	return clip, true, def and (def.description or name) or "Stance."
end

-- Advance a clip by one server step and send a pose key when one is due.
--
-- Returns the pose that was sent this step (nil when none was), and false as a
-- second result when a one-shot move ran out with nowhere to hand over to:
-- the caller decides what idle means, because a player drops to the dance
-- stance and a dancer drops to whatever the routine says next.
function lw_dance.step_move(obj, clip, dtime)
	local def = clip.def
	clip.t = clip.t + dtime

	local pose = nil
	if def and def.pose then
		clip.acc = clip.acc + dtime
		if clip.acc >= lw_dance.POSE_STEP then
			clip.acc = 0
			pose = def.pose(clip.t)
			if not (clip.model and clip.model.boned == false) then
				lw_dance.apply_pose(obj, pose, def.snap and 0 or lw_dance.POSE_STEP,
						clip.sent, clip.bones)
			end
		end
	end

	if def and def.duration and clip.t >= def.duration then
		local follow = def.next
		if follow and lw_dance.get_move(follow) then
			lw_dance.play_move(obj, follow, {clip = clip})
			return pose, true
		end
		return pose, false
	end
	return pose, true
end

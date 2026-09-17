-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Dance mode for the showcase visitor.
--
-- Two things live here that the game did not have before:
--
-- 1. A player *mesh*. The engine default for a player is an upright sprite,
--    which has no skeleton and no animation tracks, so `set_animation` and
--    `set_bone_override` are silent no-ops on it. `lw_theater` already drove
--    the character.b3d frame ranges (stand 0..79, sit 81..160) on the
--    assumption that a mesh was there, so shipping one fixes the seats too.
-- 2. A modal dance state machine. Dance mode is a mode, not a set of
--    always-live emote keys: nothing here reads a key until the visitor has
--    opted in, so building the plaza never triggers a dance.
--
-- Moves are described as data (see moves.lua) and driven from one globalstep.
-- Everything a move does — frame ranges, named glTF tracks, bone overrides,
-- body yaw — is server-side, so observers in singleplayer and (later) in
-- multiplayer see the same dance the dancer sees. There is no WASM-only path.

lw_dance = {}

local MODPATH = core.get_modpath("lw_dance")

--------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------

-- How long sneak+zoom must be held together to toggle dance mode. Long
-- enough that holding zoom while sneaking up on something does not dance.
-- Once it fires it latches until both keys come up, so leaning on the two
-- keys toggles once instead of flickering in and out of dance mode.
local GESTURE_HOLD = 0.35

-- Bones the poses are allowed to touch. Exit clears exactly this set.
lw_dance.bones = {"Head", "Body", "Arm_Left", "Arm_Right", "Leg_Left", "Leg_Right"}

--------------------------------------------------------------------------
-- The player model table
--------------------------------------------------------------------------

-- `luanti_web` ships its own model table rather than depending on
-- minetest_game's `player_api`, but the shape is deliberately the same so a
-- minetest_game character drops in unchanged.
--
-- `animations` are frame ranges for a single-track mesh (`.b3d` / `.x`).
-- `tracks` names the glTF animation tracks of a multi-track mesh; when it is
-- set, moves are played with `play_animation` instead and the legs can keep
-- their own track while the arms dance (Luanti 5.17+). Nothing in the tree
-- has those tracks yet — the field is what a hand-authored glTF fills in.
lw_dance.models = {}

function lw_dance.register_model(name, def)
	lw_dance.models[name] = def
end

lw_dance.register_model("lw_dance_character.b3d", {
	mesh = "lw_dance_character.b3d",
	textures = {"lw_dance_character.png"},
	visual = "mesh",
	visual_size = {x = 1, y = 1},
	animation_speed = 30,
	-- The classic character.b3d ranges, the same ones lw_theater sits on.
	animations = {
		stand     = {x = 0,   y = 79},
		sit       = {x = 81,  y = 160},
		lay       = {x = 162, y = 166},
		walk      = {x = 168, y = 187},
		mine      = {x = 189, y = 198},
		walk_mine = {x = 200, y = 219},
	},
	tracks = nil,
})

-- Which model a visitor wears. One entry today; a second model only has to
-- be registered and named here.
lw_dance.player_model = "lw_dance_character.b3d"

function lw_dance.model_of(player)
	return lw_dance.models[lw_dance.player_model]
end

-- Eye height is deliberately left at the engine default. The character is
-- 1.77 nodes tall, so the default 1.625 already lands in the head, and the
-- theater's seated camera offsets are calibrated against that number.
function lw_dance.set_model(player, name)
	local model = lw_dance.models[name or lw_dance.player_model]
	if not model then
		return false
	end
	player:set_properties({
		visual = model.visual or "mesh",
		mesh = model.mesh,
		textures = model.textures,
		visual_size = model.visual_size,
	})
	return true
end

--------------------------------------------------------------------------
-- The move table
--------------------------------------------------------------------------

-- A move is data:
--   name          registry key, also the `/dance <name>` argument
--   label         short name for the HUD bind list and the pad buttons
--   description   one line for `/dance help` and the HUD
--   anim          frame-range key into the model's `animations`, or a
--                 `{x = , y = }` range of its own
--   speed         frame speed override (default: the model's)
--   loop          whether the frame range loops (default true)
--   duration      seconds before the move ends; nil means "until told"
--   next          move to fall into when `duration` runs out (default:
--                 back to the dance stance)
--   interruptible whether another move may cut this one short (default true)
--   track         named glTF track, used instead of `anim` on a model that
--                 has `tracks`
--   priority      glTF track priority, so an arm track wins over the legs
--   snap          true for stepwise poses: keys are sent with no
--                 interpolation, which is what makes the Robot read as a robot
--   pose          function(t) -> {Bone = {rot = {x=,y=,z=}, pos = {...}}}
--                 called every POSE_STEP with the seconds since the move
--                 started; degrees in, radians out. This is the placeholder
--                 path the issue asks for: a move with no authored clip
--                 still moves the mesh, visibly, on the mesh we ship.
lw_dance.moves = {}
lw_dance.move_order = {}

function lw_dance.register_move(name, def)
	def = table.copy(def)
	def.name = name
	def.label = def.label or name
	if def.loop == nil then
		def.loop = true
	end
	if def.interruptible == nil then
		def.interruptible = true
	end
	if not lw_dance.moves[name] then
		lw_dance.move_order[#lw_dance.move_order + 1] = name
	end
	lw_dance.moves[name] = def
	return def
end

function lw_dance.get_move(name)
	return name and lw_dance.moves[name] or nil
end

-- Slot 1..8 of the hotbar, which is how the number keys reach the server.
lw_dance.slots = {}

function lw_dance.bind_slot(slot, action)
	lw_dance.slots[slot] = action
end

function lw_dance.random_move()
	local pool = {}
	for _, name in ipairs(lw_dance.move_order) do
		if lw_dance.moves[name].in_random_pool ~= false then
			pool[#pool + 1] = name
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(#pool)]
end

--------------------------------------------------------------------------
-- The shared driver
--------------------------------------------------------------------------

-- Everything below this line drives a *player*. How a move actually reaches an
-- object — frame ranges, named tracks, bone keys, the per-bone dedupe — lives
-- in driver.lua, because the director drives its dancers through exactly the
-- same functions.
dofile(MODPATH .. DIR_DELIM .. "driver.lua")

local POSE_STEP = lw_dance.POSE_STEP

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

-- name -> {move, t, pose_acc, wield, expect, moving, sent}
local dancers = {}

-- How long the toggle gesture has been held, and whether it has already
-- fired for this hold. Kept out of `dancers` because the gesture is read for
-- everyone, dancing or not.
local gesture_held = {}
local gesture_latched = {}

function lw_dance.is_dancing(player)
	return player ~= nil and dancers[player:get_player_name()] ~= nil
end

function lw_dance.current_move(player)
	local state = player and dancers[player:get_player_name()]
	return state and state.move or nil
end

-- lw_theater folds the visitor into the sit pose and zeroes their speed. Two
-- things driving the same skeleton would fight, so a seated visitor cannot
-- dance and a dancer who sits down stops dancing.
local function is_seated(player)
	return lw_theater and lw_theater.is_seated and lw_theater.is_seated(player)
end

--------------------------------------------------------------------------
-- Animation and pose driver
--------------------------------------------------------------------------

-- The player's own model, and then straight into the shared driver. The
-- wrappers exist so the rest of this file reads as it did before the director
-- arrived: everything they add is "the model is whatever this visitor wears".
local function apply_base_animation(player, def, walking)
	lw_dance.apply_base_animation(player, lw_dance.model_of(player), def, walking)
end

local function apply_pose(player, pose, interpolation, cache)
	lw_dance.apply_pose(player, pose, interpolation, cache)
end

local function clear_pose(player)
	-- Ease back to the neutral skeleton, then drop the overrides entirely so
	-- no dance state outlives dance mode.
	apply_pose(player, nil, 0.25)
	local name = player:get_player_name()
	core.after(0.3, function()
		local who = core.get_player_by_name(name)
		if who and not dancers[name] then
			lw_dance.clear_bones(who)
		end
	end)
end

--------------------------------------------------------------------------
-- Entering, playing, leaving
--------------------------------------------------------------------------

local function stance(player, state)
	state.move = nil
	state.t = 0
	state.pose_acc = 0
	state.sent = {}
	apply_base_animation(player, nil, false)
	apply_pose(player, nil, 0.2, state.sent)
	lw_dance.update_hud(player)
end

function lw_dance.play(player, name)
	local state = dancers[player:get_player_name()]
	if not state then
		return false, "You are not in dance mode. Try /dance."
	end

	-- A move that refuses to be cut short only holds the floor for as long as
	-- its `duration`; one with no duration would otherwise never let go.
	local current = lw_dance.get_move(state.move)
	if current and not current.interruptible and state.move ~= name then
		local left = (current.duration or 0) - state.t
		if left > 0 then
			return false, ("The %s has to finish first."):format(current.description
					or current.name)
		end
	end

	if not name then
		stance(player, state)
		return true, "Dance stance."
	end

	local def = lw_dance.get_move(name)
	if not def then
		return false, ("No such move: %s. /dance help lists them."):format(name)
	end

	state.move = name
	state.t = 0
	state.pose_acc = 0
	state.sent = {}
	apply_base_animation(player, def, state.moving == true)
	if def.pose then
		apply_pose(player, def.pose(0), def.snap and 0 or POSE_STEP, state.sent)
	else
		apply_pose(player, nil, 0.2, state.sent)
	end
	lw_dance.update_hud(player)
	return true, def.description or name
end

function lw_dance.enter(player)
	local name = player:get_player_name()
	if dancers[name] then
		return false, "Already in dance mode."
	end
	if is_seated(player) then
		return false, "Stand up first — jump to leave the seat."
	end

	local wield = player:get_wield_index()
	dancers[name] = {
		t = 0,
		pose_acc = 0,
		sent = {},
		wield = wield,
		expect = wield,
		moving = false,
	}
	-- Park the hotbar on slot 1 and start slot 1's move. The highlighted
	-- slot has to *be* the move that is playing: the server only hears about
	-- a number key as a change of hotbar slot, so if dance mode started in a
	-- neutral stance with slot 1 highlighted, pressing 1 would be a dead key.
	-- The old slot is remembered so the visitor's tool comes back on exit.
	lw_dance.select_slot(player, 1)
	local opener = lw_dance.slots[1]
	if opener and lw_dance.get_move(opener) then
		lw_dance.play(player, opener)
	else
		stance(player, dancers[name])
	end
	lw_dance.show_hud(player)
	lw_dance.maybe_show_pad(player)
	return true, "Dance mode on."
end

function lw_dance.exit(player)
	local name = player:get_player_name()
	local state = dancers[name]
	if not state then
		return false, "Not in dance mode."
	end
	dancers[name] = nil
	if lw_dance.leave_routine then
		lw_dance.leave_routine(player, true)
	end

	clear_pose(player)
	apply_base_animation(player, nil, false)
	if state.wield and state.wield ~= player:get_wield_index() then
		player:set_wield_index(state.wield)
	end
	lw_dance.hide_hud(player)
	lw_dance.hide_pad(player)
	return true, "Dance mode off."
end

function lw_dance.toggle(player)
	if lw_dance.is_dancing(player) then
		return lw_dance.exit(player)
	end
	return lw_dance.enter(player)
end

-- Selecting a hotbar slot without treating our own change as a keypress.
function lw_dance.select_slot(player, slot)
	local state = dancers[player:get_player_name()]
	if state then
		state.expect = slot
	end
	player:set_wield_index(slot)
end

-- What slot 1..8 does. Named moves are bound in moves.lua; these two are
-- the controls that are not moves.
function lw_dance.run_slot(player, slot)
	local action = lw_dance.slots[slot]
	if not action then
		return
	end
	-- A visitor dancing along with a routine (director.lua) has just pressed a
	-- move key, which means they want the floor back. The director never fights
	-- a player for their own body.
	if lw_dance.leave_routine then
		lw_dance.leave_routine(player, true)
	end
	if action == "@random" then
		local pick = lw_dance.random_move()
		if pick then
			lw_dance.feedback(player, lw_dance.play(player, pick))
		end
	elseif action == "@stop" then
		lw_dance.feedback(player, lw_dance.exit(player))
	else
		lw_dance.feedback(player, lw_dance.play(player, action))
	end
end

--------------------------------------------------------------------------
-- The one globalstep
--------------------------------------------------------------------------

core.register_globalstep(function(dtime)
	for name, state in pairs(dancers) do
		local player = core.get_player_by_name(name)
		if not player then
			dancers[name] = nil
		elseif is_seated(player) then
			lw_dance.exit(player)
		else
			local control = player:get_player_control()
			local def = lw_dance.get_move(state.move)

			-- Number keys 1..8 reach the server as hotbar selection. Any
			-- change the visitor made (key or mouse wheel) fires a move.
			local index = player:get_wield_index()
			if index ~= state.expect then
				state.expect = index
				lw_dance.run_slot(player, index)
				def = lw_dance.get_move(state.move)
				if not dancers[name] then
					-- Slot 8 left dance mode.
					def = nil
				end
			end

			if dancers[name] then
				-- Walking layers: the legs take the walk cycle, the pose
				-- keeps running on the upper body.
				local moving = (math.abs(control.movement_x or 0) > 0.1
						or math.abs(control.movement_y or 0) > 0.1)
				if moving ~= state.moving then
					state.moving = moving
					apply_base_animation(player, def, moving)
				end

				state.t = state.t + dtime
				if def and def.pose then
					state.pose_acc = state.pose_acc + dtime
					if state.pose_acc >= POSE_STEP then
						state.pose_acc = 0
						apply_pose(player, def.pose(state.t),
								def.snap and 0 or POSE_STEP, state.sent)
					end
				end

				-- One-shot moves hand back to `next`, or to the stance.
				if def and def.duration and state.t >= def.duration then
					local follow = def.next
					if follow and lw_dance.get_move(follow) then
						lw_dance.play(player, follow)
					else
						stance(player, state)
					end
				end
			end
		end
	end

	-- The toggle gesture. Read for everyone, because it is how a visitor who
	-- has never opened chat gets into dance mode in the first place.
	for _, player in ipairs(core.get_connected_players()) do
		local pname = player:get_player_name()
		local control = player:get_player_control()
		if not (control.sneak and control.zoom) then
			gesture_held[pname] = 0
			gesture_latched[pname] = nil
		elseif not gesture_latched[pname] then
			local held = (gesture_held[pname] or 0) + dtime
			gesture_held[pname] = held
			if held >= GESTURE_HOLD then
				gesture_held[pname] = 0
				gesture_latched[pname] = true
				local _, message = lw_dance.toggle(player)
				core.chat_send_player(pname, message)
			end
		end
	end
end)

--------------------------------------------------------------------------
-- Player setup and teardown
--------------------------------------------------------------------------

core.register_on_joinplayer(function(player)
	lw_dance.set_model(player)
	-- Whatever the visitor's last session left on the skeleton, the fresh
	-- one starts neutral and standing.
	lw_dance.clear_bones(player)
	apply_base_animation(player, nil, false)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	dancers[name] = nil
	gesture_held[name] = nil
	gesture_latched[name] = nil
end)

core.register_on_dieplayer(function(player)
	if lw_dance.is_dancing(player) then
		lw_dance.exit(player)
	end
end)

dofile(MODPATH .. DIR_DELIM .. "moves.lua")
dofile(MODPATH .. DIR_DELIM .. "ui.lua")
dofile(MODPATH .. DIR_DELIM .. "routine.lua")
dofile(MODPATH .. DIR_DELIM .. "director.lua")

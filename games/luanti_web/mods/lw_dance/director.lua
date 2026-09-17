-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The director: scripted dancers.
--
-- Dance mode is a visitor pressing keys. This is the other half — the cast
-- that is already dancing when they walk in. A director owns one clock, spawns
-- the routine's dancers onto marker nodes (or into a formation), and plays the
-- routine's steps on them through exactly the move catalog the visitor's keys
-- use. A chorus line and a visitor pressing 1 are running the same `groove`
-- out of the same table, so the visitor can fall in step with the stage.
--
-- Nothing here is per-entity choreography. The dancers are puppets: they carry
-- a model, a clip and a home position, and the director is the only thing that
-- ever tells them what to do.

local S = lw_dance

--------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------

-- How far a routine looks for its marker nodes, from the director outwards.
-- Comfortably more than a stage is wide, well short of scanning a map.
local MARK_RANGE = 12

-- Past this, with nobody nearer, the clock keeps running but no poses are
-- sent: an empty theater costs the WASM worker nothing, and a visitor who
-- walks back in finds the routine where it should be rather than restarted.
local ACTIVE_RANGE = 48

-- Dancers are re-checked (still alive? still in a loaded block?) on this
-- interval rather than every step.
local SWEEP_INTERVAL = 2.0

-- How high a rider sits above its carrier. Attachment offsets are tenths of a
-- node, so this is 20cm: feet on the deck of the raft.
local RIDE_LIFT = 2

--------------------------------------------------------------------------
-- Dancer rigs
--------------------------------------------------------------------------

-- Every rig the routines ship with. `boned` says whether the move's pose can
-- be put on a skeleton; a rig without one still dances, because the driver
-- reduces the pose to the body's turn and bounce and the director applies that
-- to the whole entity (see `pose_summary`). That is the fail-soft path, and
-- the melon mascot is the proof that it reads.
local CHARACTER = S.models[S.player_model]

local function character_rig(texture, extra)
	local rig = table.copy(CHARACTER)
	rig.textures = {texture}
	rig.boned = true
	for key, value in pairs(extra or {}) do
		rig[key] = value
	end
	return rig
end

-- People first: the same mesh, skeleton and frame ranges the visitor wears, so
-- a dancer and a visitor standing next to each other are visibly the same kind
-- of thing.
S.register_model("person", character_rig("lw_dance_character.png"))

-- One creature per themed map, all on the character rig except the mascot.
-- Recolouring the one texture the pack already ships is deliberate: the web
-- build has a content budget, and a ghost is a silhouette and a colour.
S.register_model("ghost", character_rig(
	-- The opacity is baked into the texture string rather than applied as a
	-- texture modifier later: one string, one upload, and it survives the
	-- entity being respawned after a block unload.
	"lw_dance_character.png^[colorize:#bfe8f5:190^[opacity:150", {
		glow = 7,
		use_texture_alpha = true,
		visual_size = {x = 1.05, y = 1.05},
	}))

S.register_model("scarecrow", character_rig(
	"lw_dance_character.png^[colorize:#b58b3a:160", {
		visual_size = {x = 1.1, y = 1.15},
	}))

-- A berry on a raft: small, rigged, and the one that proves a dancer keeps
-- playing its clip while something else moves it around.
S.register_model("berry", character_rig(
	"lw_dance_character.png^[colorize:#b43196:170", {
		visual_size = {x = 0.7, y = 0.7},
	}))

-- The melon mascot has no skeleton at all — it is a cube of the same wool the
-- garden is built from. Keep it in the cast anyway: a routine that quietly
-- drops the dancers it cannot pose is worse than one that bounces a melon.
S.register_model("mascot_melon", {
	visual = "cube",
	textures = {
		lw_nodes.wool_texture("#2d6b2d"), lw_nodes.wool_texture("#2d6b2d"),
		lw_nodes.wool_texture("#5aa83c"), lw_nodes.wool_texture("#5aa83c"),
		lw_nodes.wool_texture("#5aa83c"), lw_nodes.wool_texture("#5aa83c"),
	},
	visual_size = {x = 1.6, y = 1.6, z = 1.6},
	boned = false,
	-- A mesh hangs off its feet; a cube hangs off its middle. `lift` is how
	-- far up from the floor this rig's origin belongs, so a mascot stands on
	-- the mark instead of sinking halfway into it.
	lift = 0.8,
})

S.register_model("raft", {
	visual = "cube",
	textures = {
		"lw_planks.png", "lw_planks.png", "lw_planks.png",
		"lw_planks.png", "lw_planks.png", "lw_planks.png",
	},
	visual_size = {x = 1.4, y = 0.3, z = 1.4},
	boned = false,
})

--------------------------------------------------------------------------
-- Marker nodes
--------------------------------------------------------------------------

-- Marks are where dancers stand. They are nodes, not coordinates in a Lua
-- file, so a stage can be choreographed in game and then saved into the
-- schematic with the rest of the build: /lw_schem keeps param2 and node names,
-- which means the marks travel with the map they belong to.
--
-- `lw_dance:mark_lead` is slot 0 and takes the lead; `mark_1`..`mark_8` are
-- handed to the rest of the cast in order.
S.mark_slot = {}

local function register_mark(name, slot, description, hex)
	core.register_node("lw_dance:" .. name, {
		description = description,
		drawtype = "nodebox",
		node_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5}},
		tiles = {
			"lw_paving.png^[colorize:" .. hex .. ":120",
			"lw_paving.png^[colorize:" .. hex .. ":120",
		},
		paramtype = "light",
		sunlight_propagates = true,
		walkable = false,
		floodable = false,
		is_ground_content = false,
		-- Standing on a mark should say so: the stage hint in ui.lua fires for
		-- anything in this group, and a mark is exactly the place to offer.
		groups = {cracky = 3, oddly_breakable_by_hand = 3, lw_dance_mark = 1,
			lw_dance_stage = 1},
	})
	S.mark_slot["lw_dance:" .. name] = slot
end

register_mark("mark_lead", 0, "Dance Mark (lead)", "#e6c22f")
for slot = 1, S.MAX_DANCERS do
	register_mark("mark_" .. slot, slot, ("Dance Mark %d"):format(slot), "#6c3fb8")
end

--------------------------------------------------------------------------
-- Stages
--------------------------------------------------------------------------

-- A stage is a place a routine can run: where the director stands, which way
-- the audience is, and which routine belongs there. The world mod registers
-- one per venue exactly as it registers the theater screen, so no node has to
-- carry metadata through world generation and `/routine start <id>` can find
-- its own stage without a visitor standing on it.
S.stages = {}

-- `pos` is where the dance happens (the middle of the formation, in the node
-- the dancers stand *in*). `node` is the director node that toggles it, which
-- is usually off to one side — nobody wants a lectern in the middle of a
-- chorus line — and defaults to `pos` when there is only one of them.
function S.register_stage(def)
	assert(def.pos and def.routine, "lw_dance.register_stage needs pos and routine")
	def.pos = vector.new(def.pos)
	def.node = def.node and vector.new(def.node) or def.pos
	if def.yaw == nil then
		def.yaw = def.facing and core.dir_to_yaw(vector.new(def.facing)) or 0
	else
		def.yaw = math.rad(def.yaw)
	end
	def.id = def.id or def.routine
	S.stages[#S.stages + 1] = def
	return def
end

function S.stage_for(routine_id)
	for _, stage in ipairs(S.stages) do
		if stage.routine == routine_id then
			return stage
		end
	end
	return nil
end

local function stage_at(pos)
	for _, stage in ipairs(S.stages) do
		if vector.equals(stage.node or stage.pos, pos) then
			return stage
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- Entities
--------------------------------------------------------------------------

-- Dancers and rafts are never saved. A routine is something that is *running*,
-- and a world reloaded a week later should come back to an empty stage rather
-- than to a cast frozen mid-bow with no clock behind it.
local function apply_rig(obj, rig)
	obj:set_properties({
		visual = rig.visual or "mesh",
		mesh = rig.mesh,
		textures = rig.textures,
		visual_size = rig.visual_size or {x = 1, y = 1},
		glow = rig.glow,
		use_texture_alpha = rig.use_texture_alpha,
	})
end

core.register_entity("lw_dance:dancer", {
	initial_properties = {
		visual = "mesh",
		mesh = CHARACTER.mesh,
		textures = CHARACTER.textures,
		physical = false,
		pointable = false,
		collide_with_objects = false,
		collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.77, 0.3},
		selectionbox = {-0.3, 0.0, -0.3, 0.3, 1.77, 0.3},
		static_save = false,
		makes_footstep_sound = false,
		backface_culling = false,
	},
	on_activate = function(self)
		-- A dancer with no director is debris from an unload: the director
		-- respawns its own cast, so anything orphaned goes away.
		self.object:set_armor_groups({immortal = 1})
		core.after(0, function()
			if self.object:get_pos() and not self.owned then
				self.object:remove()
			end
		end)
	end,
})

-- The raft: a carrier that moves on its own so a dancer attached to it proves
-- the attach path. It knows nothing about dancing.
core.register_entity("lw_dance:float", {
	initial_properties = {
		visual = "cube",
		textures = {"lw_planks.png", "lw_planks.png", "lw_planks.png",
			"lw_planks.png", "lw_planks.png", "lw_planks.png"},
		visual_size = {x = 1.4, y = 0.3, z = 1.4},
		physical = false,
		pointable = false,
		collide_with_objects = false,
		static_save = false,
	},
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
	-- `from`/`to`/`speed` are set by the director. Ping-pong, because a river
	-- that runs one way needs somewhere to put the raft afterwards.
	on_step = function(self, dtime)
		if not self.from then
			return
		end
		self.travelled = (self.travelled or 0) + dtime * (self.speed or 1)
		local length = vector.distance(self.from, self.to)
		if length <= 0 then
			return
		end
		local phase = (self.travelled % (length * 2)) / length
		local fraction = phase <= 1 and phase or (2 - phase)
		self.object:set_pos(vector.new(
			self.from.x + (self.to.x - self.from.x) * fraction,
			self.from.y + (self.to.y - self.from.y) * fraction,
			self.from.z + (self.to.z - self.from.z) * fraction))
	end,
})

--------------------------------------------------------------------------
-- Placing the cast
--------------------------------------------------------------------------

local function stage_frame(yaw)
	local forward = core.yaw_to_dir(yaw)
	return forward, vector.new(forward.z, 0, -forward.x)
end

-- Marker nodes near the director, newest scan each time a routine starts: a
-- stage that was rebuilt in game is picked up without a restart.
local function find_marks(pos)
	local min = vector.subtract(pos, MARK_RANGE)
	local max = vector.add(pos, MARK_RANGE)
	local found = core.find_nodes_in_area(min, max, "group:lw_dance_mark")
	local lead, numbered = nil, {}
	for _, at in ipairs(found or {}) do
		local slot = S.mark_slot[core.get_node(at).name]
		if slot == 0 then
			lead = at
		elseif slot then
			numbered[#numbered + 1] = {slot = slot, pos = at}
		end
	end
	table.sort(numbered, function(a, b)
		return a.slot < b.slot
	end)
	return lead, numbered
end

-- Where each dancer stands. Marks win; whatever they do not cover falls back
-- to the routine's formation, so a stage with no marks at all still comes out
-- in a line rather than in a heap on the director's head.
local function place_cast(routine, stage)
	local count = math.min(#routine.dancers, S.MAX_DANCERS)
	local offsets = S.formation_offsets(routine.formation, count)
	local forward, right = stage_frame(stage.yaw)
	local lead_mark, marks = find_marks(stage.pos)

	local places, taken = {}, 0
	for index = 1, count do
		local dancer = routine.dancers[index]
		local mark = nil
		if dancer.role == "lead" or index == 1 then
			mark = lead_mark
		end
		if not mark then
			taken = taken + 1
			local entry = marks[taken]
			mark = entry and entry.pos or nil
		end
		if mark then
			-- A mark is the node the dancer stands *in*: its own bottom face
			-- is the floor, so the feet go there and not half a node down.
			-- The node itself is remembered so a visitor who steps onto it can
			-- be given that dancer's part.
			places[index] = vector.new(mark.x, mark.y - 0.5, mark.z)
			places[index].mark = vector.new(mark)
		else
			local offset = offsets[index] or {right = 0, back = 0}
			places[index] = vector.new(
				stage.pos.x + right.x * offset.right - forward.x * offset.back,
				-- Same convention as a mark: the stage names the node the
				-- dancers stand in, and their feet are on its bottom face.
				stage.pos.y - 0.5,
				stage.pos.z + right.z * offset.right - forward.z * offset.back)
		end
	end
	return places
end

--------------------------------------------------------------------------
-- Facing
--------------------------------------------------------------------------

local function nearest_partner(director, index)
	local me = director.cast[index]
	local best, distance = nil, math.huge
	for other, dancer in pairs(director.cast) do
		if other ~= index and dancer.obj and dancer.obj:get_pos() then
			local away = vector.distance(me.home, dancer.home)
			if away < distance then
				best, distance = dancer, away
			end
		end
	end
	return best
end

-- `audience` is the direction the stage points, which is the whole reason a
-- stage carries a yaw: a routine written for the theater reads "face the
-- seats" and plays unchanged on a porch where the seats are east.
local function resolve_facing(director, index, facing)
	if facing == nil then
		return nil
	end
	if type(facing) == "number" then
		return math.rad(facing)
	end
	local dancer = director.cast[index]
	if facing == "audience" then
		return director.stage.yaw
	elseif facing == "away" then
		return director.stage.yaw + math.pi
	elseif facing == "director" or facing == "centre" or facing == "center" then
		return core.dir_to_yaw(vector.direction(dancer.home, director.stage.pos))
	elseif facing == "partner" then
		local partner = nearest_partner(director, index)
		if partner then
			return core.dir_to_yaw(vector.direction(dancer.home, partner.home))
		end
		return director.stage.yaw
	end
	core.log("warning", ("lw_dance: routine %s does not know the facing %q")
			:format(director.id, tostring(facing)))
	return nil
end

--------------------------------------------------------------------------
-- Running a routine
--------------------------------------------------------------------------

-- id -> director. One instance per routine, which is what makes `/routine stop
-- chorus_line_v1` unambiguous and keeps two visitors from starting the same
-- dance twice on the same stage.
S.running = {}

local function spawn_dancer(director, index)
	local dancer = director.cast[index]
	local rig = S.models[dancer.def.model]
	if not rig then
		core.log("warning", ("lw_dance: routine %s wants the rig %q, which is " ..
				"not registered; %s sits this one out")
				:format(director.id, tostring(dancer.def.model), dancer.role))
		return false
	end

	dancer.stand = vector.new(dancer.home.x, dancer.home.y + (rig.lift or 0),
		dancer.home.z)
	local obj = core.add_entity(dancer.stand, "lw_dance:dancer")
	if not obj then
		return false
	end
	local entity = obj:get_luaentity()
	entity.owned = true
	entity.role = dancer.role
	apply_rig(obj, rig)
	obj:set_yaw(dancer.yaw + math.rad(rig.yaw_offset or 0))

	dancer.obj = obj
	dancer.rig = rig
	dancer.clip = S.new_clip(rig)
	-- Stagger the pose keys across the cast so eight dancers never all send on
	-- the same server step.
	dancer.clip.acc = (index - 1) / math.max(#director.routine.dancers, 1) * S.POSE_STEP

	-- A dancer that rides something is attached to it and never moved again:
	-- the carrier owns where it is, and the clip plays on top of that. A
	-- respawn after a block unload brings a fresh carrier, so the old one goes
	-- with the old dancer rather than drifting down the river forever.
	if dancer.carrier and dancer.carrier:get_pos() then
		dancer.carrier:remove()
		dancer.carrier = nil
	end
	if dancer.def.ride then
		local carrier = core.add_entity(dancer.stand, dancer.def.ride)
		if carrier then
			local path = dancer.def.path
			local entity_carrier = carrier:get_luaentity()
			if path and entity_carrier then
				entity_carrier.from = vector.add(director.stage.pos, path.from)
				entity_carrier.to = vector.add(director.stage.pos, path.to)
				entity_carrier.speed = path.speed or 1
			end
			dancer.carrier = carrier
			obj:set_attach(carrier, "", {x = 0, y = RIDE_LIFT, z = 0},
				{x = 0, y = 0, z = 0})
		end
	end

	S.play_move(obj, dancer.move, {clip = dancer.clip})
	return true
end

local function clear_dancer(dancer)
	if dancer.obj and dancer.obj:get_pos() then
		dancer.obj:remove()
	end
	if dancer.carrier and dancer.carrier:get_pos() then
		dancer.carrier:remove()
	end
	dancer.obj, dancer.carrier, dancer.clip = nil, nil, nil
end

-- One step, on one dancer. `offset` is how far into the move the clock already
-- is, which is what makes a seek land on a pose rather than on a restart.
local function fire_on(director, index, step, offset)
	local dancer = director.cast[index]
	if not dancer then
		return
	end

	local yaw = resolve_facing(director, index, step.facing)
	if yaw then
		dancer.yaw = yaw
		if dancer.obj and not dancer.carrier then
			dancer.obj:set_yaw(yaw + math.rad((dancer.rig and dancer.rig.yaw_offset) or 0))
		end
	end

	if step.move then
		if not S.get_move(step.move) then
			return
		end
		dancer.move = step.move
		if dancer.obj and dancer.clip then
			S.play_move(dancer.obj, step.move, {clip = dancer.clip})
			if offset and offset > 0 then
				-- Wind the clip forward so every dancer is at the same point
				-- of the same move, whoever was told about it when.
				S.step_move(dancer.obj, dancer.clip, offset)
			end
		end
	end
end

local function fire_step(director, step, offset)
	if step.role == "*" then
		for index in pairs(director.cast) do
			fire_on(director, index, step, offset)
		end
	else
		local index = director.routine.roles[step.role]
		if index then
			fire_on(director, index, step, offset)
		end
	end

	-- Followers are players who asked to dance along. They are told the step
	-- and nothing else: the director never moves a player, never turns one,
	-- and never takes a key away from one.
	for name, role in pairs(director.followers) do
		if step.move and (step.role == "*" or step.role == role) then
			local player = core.get_player_by_name(name)
			if player and S.is_dancing(player) then
				S.play(player, step.move)
			else
				director.followers[name] = nil
			end
		end
	end
end

-- Replay everything up to `t` so the cast is in the state the clock says it
-- should be. Used by seek, and by a loop wrapping round to the top.
local function apply_from_start(director, t)
	director.cursor = 1
	local steps = director.routine.steps
	while director.cursor <= #steps and steps[director.cursor].t <= t do
		local step = steps[director.cursor]
		fire_step(director, step, t - step.t)
		director.cursor = director.cursor + 1
	end
end

function S.start_routine(id, opts)
	opts = opts or {}
	local routine = S.get_routine(id)
	if not routine then
		return nil, ("No such routine: %s. /routine list shows them."):format(
				tostring(id))
	end

	if S.running[id] then
		S.stop_routine(id)
	end

	local stage = opts.stage or S.stage_for(id)
	if not stage then
		if not opts.pos then
			return nil, ("%s has no stage in the world. Stand where it should " ..
					"happen and use /routine start %s here."):format(id, id)
		end
		stage = {pos = vector.new(opts.pos), yaw = opts.yaw or 0, routine = id}
	end

	local director = {
		id = id,
		routine = routine,
		stage = stage,
		bpm = opts.bpm or routine.bpm,
		rate = 1,
		t = 0,
		cursor = 1,
		cast = {},
		followers = {},
		sweep = 0,
		active = true,
	}
	if routine.bpm and director.bpm then
		director.rate = director.bpm / routine.bpm
	end

	local count = math.min(#routine.dancers, S.MAX_DANCERS)
	if #routine.dancers > count then
		core.log("warning", ("lw_dance: routine %s has %d dancers; the cap is " ..
				"%d, so the rest stay off stage"):format(id, #routine.dancers,
				S.MAX_DANCERS))
	end

	local places = place_cast(routine, stage)
	for index = 1, count do
		director.cast[index] = {
			role = routine.dancers[index].role,
			def = routine.dancers[index],
			home = places[index],
			mark = places[index].mark,
			yaw = stage.yaw,
			move = nil,
		}
	end

	S.running[id] = director
	for index = 1, count do
		if not spawn_dancer(director, index) then
			director.cast[index] = nil
		end
	end
	if not next(director.cast) then
		S.running[id] = nil
		return nil, ("%s could not put anybody on stage."):format(id)
	end

	apply_from_start(director, 0)
	return director, ("%s is running: %d dancer(s) at %s."):format(routine.title,
			count, core.pos_to_string(vector.round(stage.pos)))
end

function S.stop_routine(id)
	local director = S.running[id]
	if not director then
		return false, ("%s is not running."):format(tostring(id))
	end
	S.running[id] = nil
	for _, dancer in pairs(director.cast) do
		clear_dancer(dancer)
	end
	for name in pairs(director.followers) do
		local player = core.get_player_by_name(name)
		if player then
			core.chat_send_player(name, ("%s has stopped; you are dancing on " ..
					"your own now."):format(director.routine.title))
		end
	end
	return true, ("%s stopped."):format(director.routine.title)
end

function S.seek_routine(id, seconds)
	local director = S.running[id]
	if not director then
		return false, ("%s is not running."):format(tostring(id))
	end
	director.t = math.max(0, math.min(seconds, director.routine.length))
	apply_from_start(director, director.t)
	return true, ("%s is at %.1fs of %.1fs."):format(director.routine.title,
			director.t, director.routine.length)
end

function S.set_routine_bpm(id, bpm)
	local director = S.running[id]
	if not director then
		return false, ("%s is not running."):format(tostring(id))
	end
	if not director.routine.bpm then
		return false, ("%s is written in seconds, not beats, so it has no bpm " ..
				"to change."):format(director.routine.title)
	end
	if type(bpm) ~= "number" or bpm <= 0 then
		return false, "The bpm has to be a positive number."
	end
	director.bpm = bpm
	director.rate = bpm / director.routine.bpm
	return true, ("%s is now at %d bpm."):format(director.routine.title, bpm)
end

function S.routine_status(id)
	local director = S.running[id]
	if not director then
		return ("%s: stopped."):format(tostring(id))
	end
	local cast = 0
	for _ in pairs(director.cast) do
		cast = cast + 1
	end
	return ("%s: %.1fs of %.1fs, %d dancer(s)%s%s."):format(
		director.routine.title, director.t, director.routine.length, cast,
		director.bpm and (", " .. math.floor(director.bpm + 0.5) .. " bpm") or "",
		director.active and "" or ", idle (nobody is watching)")
end

--------------------------------------------------------------------------
-- Dancing along
--------------------------------------------------------------------------

-- The player and the director never drive the same body. A follower keeps
-- every key they had; the director only hands them the same move it hands the
-- cast, and the first key they press takes the routine's hand off the wheel.
function S.join_routine(player, id)
	if not S.is_dancing(player) then
		local ok, message = S.enter(player)
		if not ok then
			return false, message
		end
	end

	local director = id and S.running[id] or nil
	if not director then
		for _, running in pairs(S.running) do
			director = running
			break
		end
	end
	if not director then
		return false, "No routine is running. /routine start <id> first."
	end

	-- Which part: whichever dancer was given the mark they are standing on.
	-- Marks are matched by position rather than by their number, because
	-- `mark_3` is only the third mark on the stage, not the third dancer in
	-- the cast — the routine decides who ends up where.
	local pos = vector.round(player:get_pos())
	local role = nil
	if S.mark_slot[core.get_node(pos).name] then
		for _, dancer in pairs(director.cast) do
			if dancer.mark and vector.equals(dancer.mark, pos) then
				role = dancer.role
				break
			end
		end
	end
	role = role or "*"

	S.leave_routine(player, true)
	director.followers[player:get_player_name()] = role
	return true, ("Dancing along with %s%s. Any dance key takes you back off " ..
			"the routine."):format(director.routine.title,
			role ~= "*" and (" as " .. role) or "")
end

-- `by_key` is the quiet case: the visitor pressed a move key, so they meant to
-- take over, and there is nothing to announce.
function S.leave_routine(player, by_key)
	local name = player:get_player_name()
	local left = false
	for _, director in pairs(S.running) do
		if director.followers[name] then
			director.followers[name] = nil
			left = true
		end
	end
	if left and not by_key then
		core.chat_send_player(name, "You are dancing on your own again.")
	end
	return left
end

--------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------

local function anybody_near(pos)
	for _, player in ipairs(core.get_connected_players()) do
		if vector.distance(player:get_pos(), pos) < ACTIVE_RANGE then
			return true
		end
	end
	return false
end

local function sweep(director)
	for index, dancer in pairs(director.cast) do
		if not (dancer.obj and dancer.obj:get_pos()) then
			-- The block was unloaded, or something else removed the entity.
			-- Put it back where the routine says it stands, on the move the
			-- routine says it is doing.
			dancer.obj = nil
			if not spawn_dancer(director, index) then
				director.cast[index] = nil
			end
		end
	end
end

core.register_globalstep(function(dtime)
	for id, director in pairs(S.running) do
		local routine = director.routine
		director.t = director.t + dtime * director.rate

		director.sweep = director.sweep + dtime
		local was_active = director.active
		director.active = anybody_near(director.stage.pos)
		if director.active and director.sweep >= SWEEP_INTERVAL then
			director.sweep = 0
			sweep(director)
		end
		if director.active and not was_active then
			-- Back in the room: put the cast where the clock has got to rather
			-- than where it was when everyone left.
			apply_from_start(director, director.t % routine.length)
		end

		local steps = routine.steps
		while director.cursor <= #steps and steps[director.cursor].t <= director.t do
			fire_step(director, steps[director.cursor], 0)
			director.cursor = director.cursor + 1
		end

		if director.t >= routine.length then
			if routine.loop then
				director.t = director.t - routine.length
				apply_from_start(director, director.t)
			else
				S.stop_routine(id)
			end
		end

		if director.active then
			for _, dancer in pairs(director.cast) do
				if dancer.obj and dancer.clip and dancer.obj:get_pos() then
					local pose, alive = S.step_move(dancer.obj, dancer.clip, dtime)
					if pose and dancer.rig and dancer.rig.boned == false then
						-- No skeleton: the pose becomes the whole body's turn
						-- and bounce, so the beat and the formation still read.
						local summary = S.pose_summary(pose)
						local yaw = dancer.yaw + math.rad(summary.yaw)
						if dancer.carrier then
							dancer.obj:set_attach(dancer.carrier, "",
								{x = 0, y = RIDE_LIFT + summary.lift * 10, z = 0},
								{x = 0, y = math.deg(yaw), z = 0})
						else
							dancer.obj:set_yaw(yaw)
							dancer.obj:set_pos(vector.new(dancer.stand.x,
								dancer.stand.y + summary.lift, dancer.stand.z))
						end
					end
					if alive == false and dancer.move then
						-- A one-shot with nowhere to go: hold the stance until
						-- the next step says otherwise.
						S.play_move(dancer.obj, nil, {clip = dancer.clip})
						dancer.move = nil
					end
				end
			end
		end
	end
end)

--------------------------------------------------------------------------
-- The director node
--------------------------------------------------------------------------

-- The in-world trigger. A stage registered at this node's position knows which
-- routine belongs here, so punching it is the button the issue asks for and
-- nothing has to be typed.
local function toggle_at(pos, player)
	local stage = stage_at(pos)
	if not stage then
		return false, "This director has no routine yet. Stand where the dance " ..
				"should happen and use /routine start <id> here."
	end
	if S.running[stage.routine] then
		return S.stop_routine(stage.routine)
	end
	local director, message = S.start_routine(stage.routine, {stage = stage})
	return director ~= nil, message
end

core.register_node("lw_dance:director", {
	description = "Stage Director",
	tiles = {
		"lw_pedestal_top.png^[colorize:#6c3fb8:90",
		"lw_pedestal_top.png^[colorize:#6c3fb8:90",
		"lw_pedestal_side.png^[colorize:#6c3fb8:70",
	},
	drawtype = "nodebox",
	node_box = {type = "fixed", fixed = {-0.375, -0.5, -0.375, 0.375, 0.25, 0.375}},
	paramtype = "light",
	sunlight_propagates = true,
	groups = {cracky = 2, lw_palette = 1},
	is_ground_content = false,
	on_punch = function(pos, node, puncher)
		if not puncher or not puncher:is_player() then
			return
		end
		local _, message = toggle_at(pos, puncher)
		core.chat_send_player(puncher:get_player_name(), message)
	end,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local _, message = toggle_at(pos, clicker)
		core.chat_send_player(clicker:get_player_name(), message)
	end,
})

--------------------------------------------------------------------------
-- /routine
--------------------------------------------------------------------------

local function listing()
	local lines = {"Routines:"}
	for _, id in ipairs(S.routine_order) do
		local routine = S.routines[id]
		local stage = S.stage_for(id)
		lines[#lines + 1] = ("  %s — %s, %d dancer(s), %.0fs%s%s"):format(id,
			routine.title, #routine.dancers, routine.length,
			stage and (", at " .. core.pos_to_string(vector.round(stage.pos))) or "",
			S.running[id] and " [running]" or "")
	end
	lines[#lines + 1] = "/routine start <id> [here] · stop [<id>] · seek <id> <s>"
	lines[#lines + 1] = "/routine bpm <id> <n> · status [<id>] · join [<id>] · leave"
	return table.concat(lines, "\n")
end

core.register_chatcommand("routine", {
	params = "[list | start <id> [here] | stop [<id>] | seek <id> <seconds> | " ..
			"bpm <id> <n> | status [<id>] | join [<id>] | leave]",
	description = "Run a scripted dance routine",
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You have to be in the world."
		end

		local words = (param or ""):trim():split(" ")
		local verb = words[1] or ""
		local id = words[2]

		if verb == "" or verb == "list" then
			return true, listing()
		end

		if verb == "start" then
			if not id then
				return false, "Which routine? /routine list shows them."
			end
			local opts = {}
			if words[3] == "here" then
				-- Start it where the visitor stands, facing back at them: they
				-- are looking at the stage, so they are the audience.
				local at = player:get_pos()
				opts.stage = {
					pos = vector.new(math.floor(at.x + 0.5), math.floor(at.y + 0.5),
						math.floor(at.z + 0.5)),
					yaw = player:get_look_horizontal() + math.pi,
					routine = id,
				}
			end
			local director, message = S.start_routine(id, opts)
			return director ~= nil, message
		end

		if verb == "stop" then
			if id then
				return S.stop_routine(id)
			end
			local stopped = false
			for running in pairs(S.running) do
				S.stop_routine(running)
				stopped = true
			end
			return stopped, stopped and "Every routine stopped."
					or "Nothing is running."
		end

		if verb == "seek" then
			return S.seek_routine(id, tonumber(words[3]) or 0)
		end

		if verb == "bpm" then
			return S.set_routine_bpm(id, tonumber(words[3]))
		end

		if verb == "status" then
			if id then
				return true, S.routine_status(id)
			end
			local lines = {}
			for running in pairs(S.running) do
				lines[#lines + 1] = S.routine_status(running)
			end
			return true, #lines > 0 and table.concat(lines, "\n")
					or "Nothing is running."
		end

		if verb == "join" then
			return S.join_routine(player, id)
		end

		if verb == "leave" then
			if S.leave_routine(player) then
				return true, "Off the routine. Your keys are your own."
			end
			return false, "You were not dancing along with anything."
		end

		return false, ("I do not know /routine %s. Try /routine list."):format(verb)
	end,
})

core.register_on_leaveplayer(function(player)
	S.leave_routine(player, true)
end)

core.register_on_shutdown(function()
	for id in pairs(S.running) do
		S.stop_routine(id)
	end
end)

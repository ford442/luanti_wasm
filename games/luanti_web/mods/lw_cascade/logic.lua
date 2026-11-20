-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The rules of the cascade's bicycles and gems, with no engine calls in them,
-- so util/content/test_luanti_web_cascade.lua can check them headless.

--------------------------------------------------------------------------
-- Gems
--------------------------------------------------------------------------

-- Seven gems: the three a geode gives, the three they fuse into, and a
-- prism, which is where fusing ends.
lw_cascade.GEMS = {
	{name = "red", desc = "Red", hex = "#ff4a5a"},
	{name = "yellow", desc = "Yellow", hex = "#ffd23a"},
	{name = "blue", desc = "Blue", hex = "#3a7aff"},
	{name = "orange", desc = "Orange", hex = "#ff8a2a"},
	{name = "green", desc = "Green", hex = "#3ae070"},
	{name = "violet", desc = "Violet", hex = "#a858ff"},
	{name = "prism", desc = "Prism", hex = "#ffffff"},
}

lw_cascade.gem_by_name = {}
for _, gem in ipairs(lw_cascade.GEMS) do
	lw_cascade.gem_by_name[gem.name] = gem
end

-- The colours a geode can be, and so the only gems anyone digs.
lw_cascade.PRIMARY = {"red", "yellow", "blue"}

-- Fusing mixes like paint: two primaries make the secondary between them, and
-- a secondary with the one primary it has none of makes a prism. Order never
-- matters, and a gem does not fuse with its own colour.
lw_cascade.RECIPES = {
	{"red", "yellow", "orange"},
	{"yellow", "blue", "green"},
	{"blue", "red", "violet"},
	{"orange", "blue", "prism"},
	{"green", "red", "prism"},
	{"violet", "yellow", "prism"},
}

local fuse_table = {}
for _, recipe in ipairs(lw_cascade.RECIPES) do
	local a, b, made = recipe[1], recipe[2], recipe[3]
	fuse_table[a] = fuse_table[a] or {}
	fuse_table[b] = fuse_table[b] or {}
	fuse_table[a][b] = made
	fuse_table[b][a] = made
end

-- What gems `a` and `b` fuse into, or nil.
function lw_cascade.fuse(a, b)
	return fuse_table[a] and fuse_table[a][b] or nil
end

-- What `color` fuses with, in recipe order: {{with = <color>, makes = <color>}}.
function lw_cascade.partners(color)
	local out = {}
	for _, recipe in ipairs(lw_cascade.RECIPES) do
		if recipe[1] == color then
			out[#out + 1] = {with = recipe[2], makes = recipe[3]}
		elseif recipe[2] == color then
			out[#out + 1] = {with = recipe[1], makes = recipe[3]}
		end
	end
	return out
end

function lw_cascade.gem_item(color)
	return "lw_cascade:gem_" .. color
end

-- The gem colour of an item name, or nil when it is not a gem.
function lw_cascade.gem_color(item)
	local color = type(item) == "string" and item:match("^lw_cascade:gem_([a-z]+)$")
	return color and lw_cascade.gem_by_name[color] and color or nil
end

function lw_cascade.gem_title(color)
	local gem = lw_cascade.gem_by_name[color]
	return gem and gem.desc or color
end

-- What a visitor is told about a gem that has nothing in their pockets to
-- fuse with.
function lw_cascade.fuse_hint(color)
	local partners = lw_cascade.partners(color)
	if #partners == 0 then
		return ("A %s gem is as far as fusing goes. Drop it (Q) and push it " ..
			"around, or keep it."):format(lw_cascade.gem_title(color))
	end
	local parts = {}
	for _, p in ipairs(partners) do
		parts[#parts + 1] = ("%s (makes %s)"):format(p.with, p.makes)
	end
	return ("A %s gem fuses with %s. You have none of those yet: dig a geode, " ..
		"or drop two gems (Q) so they roll into each other."):format(
		lw_cascade.gem_title(color), table.concat(parts, ", "))
end

-- A gem on the ground slows down by itself, faster on the ground than in
-- the air, and stops dead once it is barely moving.
lw_cascade.GEM = {
	push = 5.0,          -- horizontal speed a punch gives it
	pop = 2.0,           -- and the hop up with it
	bump = 2.5,          -- the least a walker's shove gives it
	bump_radius = 0.8,   -- how close a walker has to come to shove it
	fuse_radius = 0.75,  -- how close two gems have to roll to fuse
	friction = 3.0,      -- per second, on the ground
	lifetime = 900,      -- seconds on the ground before it fades, as an item does
}

-- A push away from `from` towards `to`, flat, at `speed`: what a punch (from
-- the puncher's eye, along its look) or a walker's shove gives a gem.
function lw_cascade.push_velocity(from, to, speed)
	local dx, dz = to.x - from.x, to.z - from.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-3 then
		return {x = 0, y = 0, z = 0}
	end
	return {x = dx / length * speed, y = 0, z = dz / length * speed}
end

function lw_cascade.gem_friction(velocity, dtime, on_ground)
	if not on_ground then
		return velocity
	end
	local keep = math.max(0, 1 - lw_cascade.GEM.friction * dtime)
	local x, z = velocity.x * keep, velocity.z * keep
	if x * x + z * z < 0.0025 then
		x, z = 0, 0
	end
	return {x = x, y = velocity.y, z = z}
end

--------------------------------------------------------------------------
-- Bicycles
--------------------------------------------------------------------------

-- Pedalling gets a bike to `max_speed` (a sprint is 4 and fast-move 20, so
-- this is a brisk ride, not a teleport) in a couple of seconds; braking stops
-- it in under one, and coasting in a few. Each bike lasts `life_min` to
-- `life_min + life_spread` nodes of riding, or `max_ride` seconds in the
-- saddle, whichever comes first. A rack gets its next bike `respawn` seconds
-- after its last one broke; a wreck lies where it fell for `wreck_time`; a
-- bike somebody rode off and left is taken back after `idle_limit`.
lw_cascade.BIKE = {
	max_speed = 7.0,
	accel = 4.0,
	brake = 10.0,
	coast = 1.5,
	reverse = 1.5,
	hop = 5.5,
	life_min = 60,
	life_spread = 80,
	max_ride = 150,
	respawn = 45,
	wreck_time = 12,
	idle_limit = 120,
}

-- A small deterministic hash of a rack position and how many bikes it has
-- had, so each bike's life and paint are fixed by where and when it appeared.
function lw_cascade.bike_seed(pos, count)
	local h = (pos.x * 73856093 + pos.y * 19349663 + pos.z * 83492791 + count * 2654435761) % 2147483647
	if h < 0 then
		h = h + 2147483647
	end
	return h
end

function lw_cascade.bike_life(seed)
	local bike = lw_cascade.BIKE
	return bike.life_min + seed % (bike.life_spread + 1)
end

lw_cascade.BIKE_PAINT = {"#e84a6a", "#3ab0ff", "#ffcc3a", "#5ad888", "#b070ff", "#ff8a3a"}

function lw_cascade.bike_paint(seed)
	local paint = lw_cascade.BIKE_PAINT
	return paint[math.floor(seed / 7) % #paint + 1]
end

-- The bike's speed after `dtime` with `control` held: forward pedals, back
-- brakes and then backs up slowly, nothing coasts.
function lw_cascade.bike_speed(speed, control, dtime)
	local bike = lw_cascade.BIKE
	if control.up then
		speed = math.min(bike.max_speed, speed + bike.accel * dtime)
	elseif control.down then
		if speed > 0 then
			speed = math.max(0, speed - bike.brake * dtime)
		else
			speed = math.max(-bike.reverse, speed - bike.accel * dtime)
		end
	elseif speed > 0 then
		speed = math.max(0, speed - bike.coast * dtime)
	elseif speed < 0 then
		speed = math.min(0, speed + bike.coast * dtime)
	end
	return speed
end

-- Why a bike gives out now, or nil: it has done its distance or its time.
function lw_cascade.bike_worn_out(state)
	if state.odometer >= state.life then
		return "distance"
	end
	if state.ride_time >= lw_cascade.BIKE.max_ride then
		return "time"
	end
	return nil
end

-- Roughly how much riding is left, for /bike: never exact, so the breakdown
-- is still a small surprise.
function lw_cascade.bike_condition(state)
	local left = state.life - state.odometer
	local share = left / state.life
	if share > 0.66 then
		return "It runs like new."
	elseif share > 0.33 then
		return "The chain has started to squeak."
	elseif share > 0.1 then
		return "Something is rattling. It will not last much longer."
	end
	return "It is about to fall apart."
end

lw_cascade.BREAKDOWNS = {
	distance = {
		"The chain snaps and the pedals spin free.",
		"A tyre bursts with a bang.",
		"The front wheel buckles into a taco.",
		"A pedal falls off and rolls away.",
	},
	time = {
		"The saddle gives way with a sad creak.",
		"The brakes seize up and will not let go.",
	},
}

function lw_cascade.breakdown_message(seed, reason)
	local list = lw_cascade.BREAKDOWNS[reason] or lw_cascade.BREAKDOWNS.distance
	return list[seed % #list + 1] .. " This bike is done: find another at a bike " ..
		"rack (/bike says where)."
end

-- Whether a rack whose last bike broke at gametime `broken_at` (nil if none
-- has) may put out a new one at `now`.
function lw_cascade.rack_ready(broken_at, now)
	return broken_at == nil or now - broken_at >= lw_cascade.BIKE.respawn
end

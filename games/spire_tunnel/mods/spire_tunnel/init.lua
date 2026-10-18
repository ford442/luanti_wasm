-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Spire Tunnel: a mountain spire with a spiral walkway tunnel and
-- decorative tile set for beautifying chambers and galleries.

core.register_alias("mapgen_singlenode", "air")
core.register_alias("mapgen_stone", "spire_tunnel:stone")
core.register_alias("mapgen_water_source", "spire_tunnel:water")
core.register_alias("mapgen_river_water_source", "spire_tunnel:water")
core.register_alias("mapgen_dirt", "spire_tunnel:dirt")
core.register_alias("mapgen_dirt_with_grass", "spire_tunnel:dirt_with_grass")
core.register_alias("mapgen_sand", "spire_tunnel:sand")

--------------------------------------------------------------------
-- Terrain
--------------------------------------------------------------------

core.register_node("spire_tunnel:stone", {
	description = "Mountain Stone",
	tiles = {"st_stone.png"},
	groups = {cracky = 3},
})

core.register_node("spire_tunnel:stone_dark", {
	description = "Dark Mountain Stone",
	tiles = {"st_stone_dark.png"},
	groups = {cracky = 3},
})

core.register_node("spire_tunnel:basalt", {
	description = "Basalt Column",
	tiles = {"st_basalt.png"},
	groups = {cracky = 2},
})

core.register_node("spire_tunnel:dirt", {
	description = "Dirt",
	tiles = {"st_dirt.png"},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("spire_tunnel:dirt_with_grass", {
	description = "Dirt with Grass",
	tiles = {
		"st_grass.png",
		"st_dirt.png",
		{name = "default_grass_side.png", tileable_vertical = false},
	},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("spire_tunnel:sand", {
	description = "Sand",
	tiles = {"default_sand.png"},
	groups = {crumbly = 3},
})

core.register_node("spire_tunnel:snow", {
	description = "Snow Cap",
	tiles = {"st_snow.png"},
	groups = {crumbly = 3},
})

core.register_node("spire_tunnel:water", {
	description = "Water",
	drawtype = "liquid",
	waving = 3,
	tiles = {"st_water.png"},
	special_tiles = {
		{name = "st_water.png", backface_culling = false},
		{name = "st_water.png", backface_culling = true},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drowning = 1,
	liquidtype = "source",
	liquid_alternative_source = "spire_tunnel:water",
	liquid_alternative_flowing = "spire_tunnel:water",
	liquid_viscosity = 1,
	liquid_renewable = false,
	liquid_range = 0,
	post_effect_color = {a = 70, r = 40, g = 80, b = 150},
	groups = {water = 3, liquid = 3},
})

--------------------------------------------------------------------
-- Beautifying / decorative tiles
--------------------------------------------------------------------

core.register_node("spire_tunnel:moss_stone", {
	description = "Mossy Stone",
	tiles = {"st_moss.png"},
	groups = {cracky = 3},
})

core.register_node("spire_tunnel:carved_stone", {
	description = "Carved Stone",
	tiles = {"st_carved.png"},
	groups = {cracky = 2},
})

core.register_node("spire_tunnel:spire_brick", {
	description = "Spire Brick",
	tiles = {"st_brick.png"},
	groups = {cracky = 2},
})

core.register_node("spire_tunnel:marble", {
	description = "Marble",
	tiles = {"st_marble.png"},
	groups = {cracky = 2},
})

core.register_node("spire_tunnel:obsidian", {
	description = "Obsidian Panel",
	tiles = {"st_obsidian.png"},
	groups = {cracky = 1},
})

core.register_node("spire_tunnel:path", {
	description = "Tunnel Path Stone",
	tiles = {"st_path.png"},
	groups = {cracky = 3},
})

core.register_node("spire_tunnel:gold_trim", {
	description = "Gold Trim",
	tiles = {"st_gold_trim.png"},
	light_source = 3,
	groups = {cracky = 2},
})

core.register_node("spire_tunnel:rune_block", {
	description = "Rune Block",
	tiles = {"st_rune.png"},
	light_source = 5,
	groups = {cracky = 2},
	paramtype = "light",
})

-- Crystals (glowing plantlike / nodebox accents)
local function register_crystal(name, desc, tile, light)
	core.register_node("spire_tunnel:" .. name, {
		description = desc,
		drawtype = "nodebox",
		paramtype = "light",
		paramtype2 = "facedir",
		light_source = light,
		tiles = {tile},
		use_texture_alpha = "blend",
		node_box = {
			type = "fixed",
			fixed = {
				{-0.12, -0.5, -0.12, 0.12, 0.35, 0.12},
				{-0.22, -0.5, -0.06, -0.05, 0.1, 0.06},
				{0.05, -0.5, -0.06, 0.22, 0.05, 0.06},
				{-0.06, 0.2, -0.06, 0.06, 0.55, 0.06},
			},
		},
		selection_box = {
			type = "fixed",
			fixed = {-0.25, -0.5, -0.25, 0.25, 0.55, 0.25},
		},
		groups = {cracky = 3, oddly_breakable_by_hand = 2},
		is_ground_content = false,
		sunlight_propagates = true,
	})
end

register_crystal("crystal_blue", "Blue Crystal", "st_crystal_blue.png", 8)
register_crystal("crystal_purple", "Purple Crystal", "st_crystal_purple.png", 7)
register_crystal("crystal_cyan", "Cyan Crystal", "st_crystal_cyan.png", 9)

core.register_node("spire_tunnel:gem_floor", {
	description = "Gem-Inlaid Floor",
	tiles = {"st_gem_floor.png"},
	light_source = 2,
	groups = {cracky = 2},
})

core.register_node("spire_tunnel:stained_glass", {
	description = "Stained Glass",
	drawtype = "glasslike",
	tiles = {"st_glass.png"},
	paramtype = "light",
	sunlight_propagates = true,
	use_texture_alpha = "blend",
	light_source = 4,
	is_ground_content = false,
	groups = {cracky = 3, oddly_breakable_by_hand = 2},
})

core.register_node("spire_tunnel:lantern", {
	description = "Spire Lantern",
	drawtype = "nodebox",
	paramtype = "light",
	light_source = core.LIGHT_MAX - 2,
	tiles = {"st_lantern.png", "st_gold_trim.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.2, -0.5, -0.2, 0.2, -0.15, 0.2},
			{-0.15, -0.15, -0.15, 0.15, 0.25, 0.15},
			{-0.08, 0.25, -0.08, 0.08, 0.45, 0.08},
		},
	},
	groups = {cracky = 2, oddly_breakable_by_hand = 2},
	is_ground_content = false,
	sunlight_propagates = true,
})

core.register_node("spire_tunnel:vine", {
	description = "Hanging Vine",
	drawtype = "plantlike",
	waving = 1,
	tiles = {"st_vine.png"},
	inventory_image = "st_vine.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = true,
	climbable = true,
	groups = {snappy = 3, flora = 1, attached_node = 1},
	selection_box = {
		type = "fixed",
		fixed = {-0.3, -0.5, -0.3, 0.3, 0.5, 0.3},
	},
})

core.register_node("spire_tunnel:mountain_blossom", {
	description = "Mountain Blossom",
	drawtype = "plantlike",
	waving = 1,
	tiles = {"st_flower.png"},
	inventory_image = "st_flower.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = true,
	groups = {snappy = 3, flora = 1, attached_node = 1},
	selection_box = {
		type = "fixed",
		fixed = {-0.25, -0.5, -0.25, 0.25, 0.2, 0.25},
	},
})

core.register_node("spire_tunnel:pillar", {
	description = "Carved Pillar",
	drawtype = "nodebox",
	paramtype = "light",
	tiles = {"st_carved.png", "st_marble.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.3, -0.5, -0.3, 0.3, 0.5, 0.3},
			{-0.4, -0.5, -0.4, 0.4, -0.3, 0.4},
			{-0.4, 0.3, -0.4, 0.4, 0.5, 0.4},
		},
	},
	groups = {cracky = 2},
	is_ground_content = false,
})

core.register_node("spire_tunnel:arch_keystone", {
	description = "Arch Keystone",
	tiles = {"st_gold_trim.png", "st_carved.png"},
	groups = {cracky = 2},
})

core.register_node("spire_tunnel:window_frame", {
	description = "View Window Frame",
	drawtype = "nodebox",
	paramtype = "light",
	tiles = {"st_carved.png", "st_glass.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.1, 0.5, 0.5, 0.1},
		},
	},
	use_texture_alpha = "blend",
	groups = {cracky = 2},
	is_ground_content = false,
	sunlight_propagates = true,
})

--------------------------------------------------------------------
-- Spire + spiral tunnel geometry
--------------------------------------------------------------------

local GROUND_Y = 4
local WATER_Y = 3
local SPIRE_CX = 0
local SPIRE_CZ = 0
local SPIRE_BASE_R = 18
local SPIRE_TOP_Y = 42
local SPIRE_BASE_Y = GROUND_Y
local TUNNEL_R = 2 -- hollow radius of walkway tube
local LINING_R = 3 -- outer lining radius
local SPIRAL_CORE_R = 8 -- radius of spiral centerline from axis
local SPIRAL_TURNS = 3.5
local SPIRAL_START_Y = GROUND_Y + 2
local SPIRAL_END_Y = SPIRE_TOP_Y - 5

local GEN_PAD = 10
local GEN_MIN = {
	x = -SPIRE_BASE_R - GEN_PAD,
	y = 0,
	z = -SPIRE_BASE_R - GEN_PAD,
}
local GEN_MAX = {
	x = SPIRE_BASE_R + GEN_PAD,
	y = SPIRE_TOP_Y + 4,
	z = SPIRE_BASE_R + GEN_PAD,
}

local function overlaps(minp, maxp)
	return not (maxp.x < GEN_MIN.x or minp.x > GEN_MAX.x
		or maxp.y < GEN_MIN.y or minp.y > GEN_MAX.y
		or maxp.z < GEN_MIN.z or minp.z > GEN_MAX.z)
end

-- Spire radius at height y (tapers to a point)
local function spire_radius_at(y)
	if y < SPIRE_BASE_Y then
		return SPIRE_BASE_R
	end
	if y > SPIRE_TOP_Y then
		return 0
	end
	local t = (y - SPIRE_BASE_Y) / (SPIRE_TOP_Y - SPIRE_BASE_Y)
	local taper = (1 - t) ^ 0.85
	return SPIRE_BASE_R * taper
end

local function spiral_angle_at(y)
	local t = (y - SPIRAL_START_Y) / math.max(1, SPIRAL_END_Y - SPIRAL_START_Y)
	t = math.max(0, math.min(1, t))
	return t * SPIRAL_TURNS * 2 * math.pi
end

local function spiral_center(y)
	local ang = spiral_angle_at(y)
	local t = (y - SPIRAL_START_Y) / math.max(1, SPIRAL_END_Y - SPIRAL_START_Y)
	t = math.max(0, math.min(1, t))
	local r = SPIRAL_CORE_R * (1 - 0.2 * t)
	return {
		x = SPIRE_CX + math.cos(ang) * r,
		y = y,
		z = SPIRE_CZ + math.sin(ang) * r,
	}
end

-- Precompute spiral samples once; mapgen stamps spheres around these (fast).
local SPIRAL_SAMPLES = {}
do
	for y = SPIRAL_START_Y, SPIRAL_END_Y, 0.45 do
		local c = spiral_center(y)
		local ang = spiral_angle_at(y)
		SPIRAL_SAMPLES[#SPIRAL_SAMPLES + 1] = {
			x = c.x, y = c.y, z = c.z,
			ang = ang,
			step = math.floor(ang * 4),
		}
	end
end

local function set_if_in(data, area, minp, maxp, x, y, z, cid)
	if x >= minp.x and x <= maxp.x
		and y >= minp.y and y <= maxp.y
		and z >= minp.z and z <= maxp.z then
		data[area:index(x, y, z)] = cid
	end
end

core.register_on_generated(function(minp, maxp, _seed)
	if not overlaps(minp, maxp) then
		return
	end

	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()

	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("spire_tunnel:stone")
	local c_dark = core.get_content_id("spire_tunnel:stone_dark")
	local c_basalt = core.get_content_id("spire_tunnel:basalt")
	local c_dirt = core.get_content_id("spire_tunnel:dirt")
	local c_grass = core.get_content_id("spire_tunnel:dirt_with_grass")
	local c_sand = core.get_content_id("spire_tunnel:sand")
	local c_snow = core.get_content_id("spire_tunnel:snow")
	local c_water = core.get_content_id("spire_tunnel:water")
	local c_moss = core.get_content_id("spire_tunnel:moss_stone")
	local c_path = core.get_content_id("spire_tunnel:path")
	local c_gem = core.get_content_id("spire_tunnel:gem_floor")
	local c_carved = core.get_content_id("spire_tunnel:carved_stone")
	local c_brick = core.get_content_id("spire_tunnel:spire_brick")
	local c_marble = core.get_content_id("spire_tunnel:marble")
	local c_obs = core.get_content_id("spire_tunnel:obsidian")
	local c_gold = core.get_content_id("spire_tunnel:gold_trim")
	local c_rune = core.get_content_id("spire_tunnel:rune_block")
	local c_lantern = core.get_content_id("spire_tunnel:lantern")
	local c_crystal_b = core.get_content_id("spire_tunnel:crystal_blue")
	local c_crystal_p = core.get_content_id("spire_tunnel:crystal_purple")
	local c_crystal_c = core.get_content_id("spire_tunnel:crystal_cyan")
	local c_glass = core.get_content_id("spire_tunnel:stained_glass")
	local c_pillar = core.get_content_id("spire_tunnel:pillar")
	local c_vine = core.get_content_id("spire_tunnel:vine")
	local c_flower = core.get_content_id("spire_tunnel:mountain_blossom")

	-- 1) Base terrain + solid spire (single pass, cheap)
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local dx = x - SPIRE_CX
			local dz = z - SPIRE_CZ
			local dist_xz = math.sqrt(dx * dx + dz * dz)

			for y = minp.y, maxp.y do
				local vi = area:index(x, y, z)
				local r_spire = spire_radius_at(y)
				local in_spire = dist_xz <= r_spire + 0.2 and y >= SPIRE_BASE_Y
					and y <= SPIRE_TOP_Y

				if y < GROUND_Y - 2 then
					data[vi] = c_stone
				elseif y < GROUND_Y then
					data[vi] = c_dirt
				elseif y == GROUND_Y then
					if dist_xz > SPIRE_BASE_R + 3 then
						data[vi] = c_grass
					elseif dist_xz > SPIRE_BASE_R then
						data[vi] = c_sand
					else
						data[vi] = c_stone
					end
				elseif in_spire then
					local shell = (dist_xz > r_spire - 1.2)
					local core = dist_xz < 3.0
					if shell then
						data[vi] = (y > SPIRE_TOP_Y - 8) and c_snow or c_dark
					elseif core and y > GROUND_Y + 6 then
						data[vi] = c_basalt
					else
						data[vi] = c_stone
					end
					if y >= SPIRE_TOP_Y - 6 and dist_xz > r_spire - 2.2 then
						data[vi] = c_snow
					end
				elseif y <= WATER_Y and dist_xz > SPIRE_BASE_R + 4 then
					data[vi] = c_water
				else
					data[vi] = c_air
				end
			end
		end
	end

	-- 2) Stamp spiral tunnel from samples (lining shell then hollow)
	local lining_r = LINING_R
	local hollow_r = TUNNEL_R
	local lining_r2 = lining_r * lining_r
	local hollow_r2 = hollow_r * hollow_r

	for si, s in ipairs(SPIRAL_SAMPLES) do
		local cx = math.floor(s.x + 0.5)
		local cy = math.floor(s.y + 0.5)
		local cz = math.floor(s.z + 0.5)
		-- Skip samples far outside this chunk (with radius pad)
		if not (cx + lining_r < minp.x or cx - lining_r > maxp.x
			or cy + lining_r < minp.y or cy - lining_r > maxp.y
			or cz + lining_r < minp.z or cz - lining_r > maxp.z) then

			local step = s.step
			local low = s.y < SPIRAL_START_Y + 7

			for dy = -lining_r, lining_r do
				for dx = -lining_r, lining_r do
					for dz = -lining_r, lining_r do
						local d2 = dx * dx + dy * dy + dz * dz
						if d2 <= lining_r2 then
							local x, y, z = cx + dx, cy + dy, cz + dz
							if x >= minp.x and x <= maxp.x
								and y >= minp.y and y <= maxp.y
								and z >= minp.z and z <= maxp.z then
								local vi = area:index(x, y, z)
								if d2 <= hollow_r2 then
									-- Interior: floor band vs air
									if dy <= -hollow_r + 1 then
										if step % 7 == 0 then
											data[vi] = c_gem
										elseif step % 5 == 0 then
											data[vi] = c_marble
										else
											data[vi] = c_path
										end
									else
										data[vi] = c_air
									end
								else
									-- Lining ring
									if low then
										data[vi] = c_moss
									elseif step % 11 == 0 then
										data[vi] = c_carved
									elseif step % 9 == 0 then
										data[vi] = c_brick
									elseif step % 17 == 0 then
										data[vi] = c_rune
									elseif step % 20 == 0 and math.abs(dy) < 1 then
										data[vi] = c_gold
									else
										data[vi] = c_dark
									end
								end
							end
						end
					end
				end
			end

			-- Lantern every ~12 samples, hung from ceiling of tube
			if si % 12 == 0 then
				set_if_in(data, area, minp, maxp, cx, cy + 1, cz, c_lantern)
			end
		end
	end

	-- 3) Galleries at quarter-turns
	for turn = 0, math.floor(SPIRAL_TURNS) do
		local t = (turn + 0.25) / SPIRAL_TURNS
		local gy = math.floor(SPIRAL_START_Y + t * (SPIRAL_END_Y - SPIRAL_START_Y) + 0.5)
		local c = spiral_center(gy)
		local gx, gz = math.floor(c.x + 0.5), math.floor(c.z + 0.5)

		for dz = -3, 3 do
			for dx = -3, 3 do
				for dy = 0, 3 do
					local x, y, z = gx + dx, gy + dy, gz + dz
					if x >= minp.x and x <= maxp.x
						and y >= minp.y and y <= maxp.y
						and z >= minp.z and z <= maxp.z then
						local vi = area:index(x, y, z)
						local r2 = dx * dx + dz * dz
						if r2 <= 9 then
							if dy == 0 then
								data[vi] = (r2 <= 1) and c_obs or c_gem
							elseif dy <= 2 and r2 <= 6 then
								data[vi] = c_air
							elseif dy == 3 and r2 <= 8 then
								data[vi] = c_carved
							end
						end
					end
				end
			end
		end
		for _, off in ipairs({{-2, -2}, {-2, 2}, {2, -2}, {2, 2}}) do
			for dy = 0, 2 do
				set_if_in(data, area, minp, maxp, gx + off[1], gy + dy, gz + off[2], c_pillar)
			end
		end
		set_if_in(data, area, minp, maxp, gx + 1, gy + 1, gz + 1, c_crystal_b)
		set_if_in(data, area, minp, maxp, gx - 1, gy + 1, gz + 1, c_crystal_p)
		set_if_in(data, area, minp, maxp, gx + 1, gy + 1, gz - 1, c_crystal_c)
		set_if_in(data, area, minp, maxp, gx, gy + 1, gz, c_lantern)
	end

	-- 4) Summit shrine
	local peak_y = SPIRE_TOP_Y - 3
	for dz = -2, 2 do
		for dx = -2, 2 do
			for dy = 0, 3 do
				local x, y, z = SPIRE_CX + dx, peak_y + dy, SPIRE_CZ + dz
				if x >= minp.x and x <= maxp.x
					and y >= minp.y and y <= maxp.y
					and z >= minp.z and z <= maxp.z then
					local vi = area:index(x, y, z)
					local r2 = dx * dx + dz * dz
					if dy == 0 and r2 <= 4 then
						data[vi] = c_marble
					elseif dy > 0 and dy < 3 and r2 <= 1 then
						data[vi] = c_air
					elseif dy == 3 and r2 <= 2 then
						data[vi] = c_gold
					elseif dy > 0 and r2 == 4 then
						data[vi] = c_glass
					end
				end
			end
		end
	end
	set_if_in(data, area, minp, maxp, SPIRE_CX, peak_y + 1, SPIRE_CZ, c_lantern)

	-- 5) Approach plaza + entrance (outside the mountain, room to look around)
	local entrance = spiral_center(SPIRAL_START_Y)
	local ex = math.floor(entrance.x + 0.5)
	local ez = math.floor(entrance.z + 0.5)
	-- Clear a viewing terrace east of the entrance
	for z = ez - 4, ez + 4 do
		for x = ex, ex + 14 do
			for y = GROUND_Y + 1, GROUND_Y + 6 do
				set_if_in(data, area, minp, maxp, x, y, z, c_air)
			end
			local gy = GROUND_Y
			if x >= minp.x and x <= maxp.x
				and gy >= minp.y and gy <= maxp.y
				and z >= minp.z and z <= maxp.z then
				local vi = area:index(x, gy, z)
				if math.abs(z - ez) <= 1 or x <= ex + 2 then
					data[vi] = c_path
				elseif data[vi] == c_stone or data[vi] == c_sand then
					data[vi] = c_grass
				end
			end
		end
	end
	-- Entrance arch
	for dy = 1, 3 do
		set_if_in(data, area, minp, maxp, ex, GROUND_Y + dy, ez - 2, c_carved)
		set_if_in(data, area, minp, maxp, ex, GROUND_Y + dy, ez + 2, c_carved)
	end
	set_if_in(data, area, minp, maxp, ex, GROUND_Y + 4, ez, c_gold)
	set_if_in(data, area, minp, maxp, ex, GROUND_Y + 4, ez - 1, c_carved)
	set_if_in(data, area, minp, maxp, ex, GROUND_Y + 4, ez + 1, c_carved)

	-- 6) Base flora
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local dx = x - SPIRE_CX
			local dz = z - SPIRE_CZ
			local dist_xz = math.sqrt(dx * dx + dz * dz)
			if dist_xz > SPIRE_BASE_R - 0.5 and dist_xz < SPIRE_BASE_R + 5 then
				local h = (x * 73856093 + z * 19349663) % 1000
				local y = GROUND_Y + 1
				if y >= minp.y and y <= maxp.y then
					local vi = area:index(x, y, z)
					if data[vi] == c_air then
						if h < 35 then
							data[vi] = c_flower
						elseif h < 60 then
							data[vi] = c_vine
						end
					end
				end
			end
		end
	end

	vm:set_data(data)
	vm:calc_lighting()
	vm:write_to_map()
	vm:update_liquids()
end)

--------------------------------------------------------------------
-- Player setup
--------------------------------------------------------------------

-- Spawn on the open terrace looking at the mountain entrance
local entrance0 = spiral_center(SPIRAL_START_Y)
local SPAWN = {
	x = math.floor(entrance0.x + 10),
	y = GROUND_Y + 2,
	z = math.floor(entrance0.z + 0.5),
}

core.settings:set("static_spawnpoint",
	SPAWN.x .. "," .. SPAWN.y .. "," .. SPAWN.z)
if core.set_mapgen_setting then
	core.set_mapgen_setting("mg_name", "singlenode", true)
end

local starter_items = {
	"spire_tunnel:path 64",
	"spire_tunnel:moss_stone 64",
	"spire_tunnel:carved_stone 48",
	"spire_tunnel:spire_brick 48",
	"spire_tunnel:marble 32",
	"spire_tunnel:obsidian 16",
	"spire_tunnel:gem_floor 32",
	"spire_tunnel:gold_trim 24",
	"spire_tunnel:rune_block 16",
	"spire_tunnel:stained_glass 24",
	"spire_tunnel:lantern 16",
	"spire_tunnel:crystal_blue 12",
	"spire_tunnel:crystal_purple 12",
	"spire_tunnel:crystal_cyan 12",
	"spire_tunnel:pillar 16",
	"spire_tunnel:vine 24",
	"spire_tunnel:mountain_blossom 16",
	"spire_tunnel:window_frame 12",
	"spire_tunnel:arch_keystone 8",
	"spire_tunnel:basalt 32",
	"spire_tunnel:snow 16",
}

core.register_on_newplayer(function(player)
	player:set_pos(SPAWN)
	local inv = player:get_inventory()
	for _, stack in ipairs(starter_items) do
		inv:add_item("main", stack)
	end
	core.chat_send_player(player:get_player_name(),
		"Welcome to the Spire! Follow the stone path into the spiral tunnel. "
		.. "Galleries open at each turn; the summit shrine waits at the peak. "
		.. "Use crystals, runes, marble, and lanterns from your inventory to "
		.. "beautify the mountain.")
end)

core.register_on_joinplayer(function(player)
	-- Hint once per session via chat if they spawn mid-air / wrong game world
	core.after(1, function()
		if player and player:is_player() then
			local pos = player:get_pos()
			if pos and pos.y < GROUND_Y - 5 then
				player:set_pos(SPAWN)
			end
		end
	end)
end)

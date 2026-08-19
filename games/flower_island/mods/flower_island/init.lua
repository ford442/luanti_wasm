-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- A self-contained singlenode island. Surface plants are laid out as a
-- six-petal flower (center apples, petal grass, a short stem).

core.register_alias("mapgen_singlenode", "air")
core.register_alias("mapgen_stone", "flower_island:stone")
core.register_alias("mapgen_water_source", "flower_island:water")
core.register_alias("mapgen_river_water_source", "flower_island:water")
core.register_alias("mapgen_dirt", "flower_island:dirt")
core.register_alias("mapgen_dirt_with_grass", "flower_island:dirt_with_grass")
core.register_alias("mapgen_sand", "flower_island:sand")
core.register_node("flower_island:stone", {
	description = "Stone",
	tiles = {"default_stone.png"},
	groups = {cracky = 3},
})

core.register_node("flower_island:dirt", {
	description = "Dirt",
	tiles = {"default_dirt.png"},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("flower_island:dirt_with_grass", {
	description = "Dirt with Grass",
	tiles = {
		"default_grass.png",
		"default_dirt.png",
		{name = "default_grass_side.png", tileable_vertical = false},
	},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("flower_island:sand", {
	description = "Sand",
	tiles = {"default_sand.png"},
	groups = {crumbly = 3},
})

core.register_node("flower_island:water", {
	description = "Water",
	drawtype = "liquid",
	waving = 3,
	tiles = {"default_water.png^[opacity:160"},
	special_tiles = {
		{name = "default_water.png^[opacity:160", backface_culling = false},
		{name = "default_water.png^[opacity:160", backface_culling = true},
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
	liquid_alternative_source = "flower_island:water",
	liquid_alternative_flowing = "flower_island:water",
	liquid_viscosity = 1,
	liquid_renewable = false,
	liquid_range = 0,
	post_effect_color = {a = 64, r = 100, g = 100, b = 200},
	groups = {water = 3, liquid = 3},
})

core.register_node("flower_island:plant", {
	description = "Island Grass",
	drawtype = "plantlike",
	waving = 1,
	tiles = {"default_junglegrass.png"},
	inventory_image = "default_junglegrass.png",
	wield_image = "default_junglegrass.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = true,
	groups = {snappy = 3, attached_node = 1, flora = 1},
	selection_box = {
		type = "fixed",
		fixed = {-0.3, -0.5, -0.3, 0.3, 0.4, 0.3},
	},
})

core.register_node("flower_island:blossom", {
	description = "Island Blossom",
	drawtype = "plantlike",
	waving = 1,
	tiles = {"default_apple.png"},
	inventory_image = "default_apple.png",
	wield_image = "default_apple.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	buildable_to = true,
	groups = {snappy = 3, attached_node = 1, flora = 1},
	selection_box = {
		type = "fixed",
		fixed = {-0.2, -0.5, -0.2, 0.2, 0.2, 0.2},
	},
})

core.register_node("flower_island:leaves", {
	description = "Leaves",
	drawtype = "allfaces_optional",
	tiles = {"default_leaves.png"},
	paramtype = "light",
	is_ground_content = false,
	groups = {snappy = 3},
})

local SURFACE_Y = 8
local WATER_Y = 7
local ISLAND_R = 20
local BEACH_R = 16
local GEN_MIN = {x = -24, y = 0, z = -24}
local GEN_MAX = {x = 24, y = 12, z = 24}

local function overlaps(minp, maxp)
	return not (maxp.x < GEN_MIN.x or minp.x > GEN_MAX.x
		or maxp.y < GEN_MIN.y or minp.y > GEN_MAX.y
		or maxp.z < GEN_MIN.z or minp.z > GEN_MAX.z)
end

-- Six-petal flower in XZ, plus a short stem pointing -Z.
local function plant_at(x, z)
	local r2 = x * x + z * z
	if r2 <= 4 then
		return "center"
	end
	-- Stem
	if math.abs(x) <= 1 and z <= -3 and z >= -11 then
		return "stem"
	end
	local r = math.sqrt(r2)
	if r < 3 or r > 12 then
		return nil
	end
	local ang = math.atan2(z, x)
	-- Rose curve: petals where cos(6θ) is high
	local petal = 4 + 8 * math.max(0, math.cos(6 * ang))
	if r <= petal then
		return "petal"
	end
	return nil
end

core.register_on_generated(function(minp, maxp, _seed)
	if not overlaps(minp, maxp) then
		return
	end

	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()

	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("flower_island:stone")
	local c_dirt = core.get_content_id("flower_island:dirt")
	local c_grass = core.get_content_id("flower_island:dirt_with_grass")
	local c_sand = core.get_content_id("flower_island:sand")
	local c_water = core.get_content_id("flower_island:water")
	local c_plant = core.get_content_id("flower_island:plant")
	local c_blossom = core.get_content_id("flower_island:blossom")

	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local dist = math.sqrt(x * x + z * z)
			local on_island = dist <= ISLAND_R
			for y = minp.y, maxp.y do
				local vi = area:index(x, y, z)
				if on_island then
					if y < SURFACE_Y - 3 then
						data[vi] = c_stone
					elseif y < SURFACE_Y then
						data[vi] = (dist > BEACH_R) and c_sand or c_dirt
					elseif y == SURFACE_Y then
						data[vi] = (dist > BEACH_R) and c_sand or c_grass
					elseif y == SURFACE_Y + 1 and dist <= BEACH_R then
						local kind = plant_at(x, z)
						if kind == "center" then
							data[vi] = c_blossom
						elseif kind == "petal" or kind == "stem" then
							data[vi] = c_plant
						else
							data[vi] = c_air
						end
					elseif y <= WATER_Y then
						data[vi] = c_water
					else
						data[vi] = c_air
					end
				else
					if y <= WATER_Y then
						data[vi] = c_water
					else
						data[vi] = c_air
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

core.settings:set("static_spawnpoint", "0," .. (SURFACE_Y + 2) .. ",0")
if core.set_mapgen_setting then
	core.set_mapgen_setting("mg_name", "singlenode", true)
end

core.register_on_newplayer(function(player)
	player:set_pos({x = 0, y = SURFACE_Y + 2, z = 0})
	player:get_inventory():add_item("main", "flower_island:plant 32")
	player:get_inventory():add_item("main", "flower_island:blossom 16")
end)

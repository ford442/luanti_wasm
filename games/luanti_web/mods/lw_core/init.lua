-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Creative core for the web showcase: a fast hand, a palette inventory the
-- visitor can open with `i`, and a starter kit. No hunger, no HP, no combat,
-- no crafting tree — this game exists to be walked through and built in.

lw_core = {}

local F = core.formspec_escape

--------------------------------------------------------------------------
-- The hand
--------------------------------------------------------------------------

-- A visitor has a couple of minutes and no tools. Digging is quick but not
-- instantaneous, so the smoke test (#14) can still observe dig progress.
local QUICK = {times = {0.20, 0.30, 0.45}, uses = 0, maxlevel = 3}

core.register_item(":", {
	type = "none",
	wield_image = "wieldhand.png",
	wield_scale = {x = 1, y = 1, z = 2.5},
	range = 8,
	tool_capabilities = {
		full_punch_interval = 0.5,
		max_drop_level = 3,
		groupcaps = {
			cracky = QUICK,
			crumbly = QUICK,
			choppy = QUICK,
			snappy = QUICK,
			oddly_breakable_by_hand = QUICK,
			-- dig_immediate does not use index 1; 3 means "instantly".
			dig_immediate = {times = {[2] = 0.3, [3] = 0.0}, uses = 0, maxlevel = 3},
		},
		damage_groups = {fleshy = 1},
	},
})

--------------------------------------------------------------------------
-- Palette inventory
--------------------------------------------------------------------------

local SLOTS_W = 10
local SLOTS_H = 5
local SLOTS = SLOTS_W * SLOTS_H
local FORMNAME = "lw_core:palette"

local palette_items = nil
local pages = {}

-- Sort so the inventory reads like the material library: terrain, structure,
-- architecture, lighting, exhibition, then the dyed cubes, then the tools.
local GROUP_ORDER = {"lw_nodes:", "lw_theater:", "lw_maps:", "lw_tools:"}

local function catalogue()
	if palette_items then
		return palette_items
	end
	palette_items = {}
	for name, def in pairs(core.registered_items) do
		if name ~= "" and def.description and def.description ~= ""
				and core.get_item_group(name, "not_in_creative_inventory") == 0 then
			local rank = #GROUP_ORDER + 1
			for index, prefix in ipairs(GROUP_ORDER) do
				if name:sub(1, #prefix) == prefix then
					rank = index
					break
				end
			end
			table.insert(palette_items, {name = name, rank = rank})
		end
	end
	table.sort(palette_items, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.name < b.name
	end)
	return palette_items
end

local function max_page()
	return math.max(1, math.ceil(#catalogue() / SLOTS))
end

local function detached_name(name)
	return "lw_core:palette_" .. name
end

-- One detached inventory per player: the page a visitor is on must not change
-- what anybody else is looking at.
local function fill_detached(name, page)
	local inv = core.get_inventory({type = "detached", name = detached_name(name)})
	if not inv then
		return
	end
	local items = catalogue()
	local list = {}
	for slot = 1, SLOTS do
		local entry = items[(page - 1) * SLOTS + slot]
		list[slot] = entry and ItemStack(entry.name) or ItemStack("")
	end
	inv:set_list("main", list)
end

local function palette_formspec(name)
	local page = pages[name] or 1
	fill_detached(name, page)
	local list = "detached:" .. detached_name(name)
	return table.concat({
		"formspec_version[4]",
		"size[11.75,12.2]",
		"label[0.5,0.55;", F("Showcase palette — take what you like, it never runs out"), "]",
		"list[", list, ";main;0.5,0.9;", SLOTS_W, ",", SLOTS_H, ";]",
		"button[0.5,6.4;1,0.8;lw_prev;<]",
		"button[1.6,6.4;1,0.8;lw_next;>]",
		"label[2.9,6.8;", F(("Page %d/%d"):format(page, max_page())), "]",
		"button[9.15,6.4;2.1,0.8;lw_stuff;", F("Starter kit"), "]",
		"list[current_player;main;0.5,7.8;8,1;]",
		"list[current_player;main;0.5,9.0;8,3;8]",
		"listring[", list, ";main]",
		"listring[current_player;main]",
	})
end

local function refresh(name)
	core.show_formspec(name, FORMNAME, palette_formspec(name))
end

local function create_palette_inventory(name)
	local inv = core.create_detached_inventory(detached_name(name), {
		allow_move = function()
			return 0
		end,
		allow_put = function()
			return 0
		end,
		allow_take = function(_, _, _, stack)
			-- -1 means "take the whole stack and leave the source untouched".
			return -1
		end,
	}, name)
	inv:set_size("main", SLOTS)
	return inv
end

--------------------------------------------------------------------------
-- Starter kit
--------------------------------------------------------------------------

-- Blocks a new visitor can start building with. Restocked by /stuff, not on
-- every join — otherwise using a stack would refill it next login.
lw_core.starter_blocks = {
	"lw_nodes:wool_white 99",
	"lw_nodes:wool_red 99",
	"lw_nodes:wool_blue 99",
	"lw_nodes:stone_brick 99",
	"lw_nodes:planks 99",
	"lw_nodes:glass 99",
	"lw_nodes:lamp 32",
}

-- Authoring tools. Restocked on join if missing, so a returning visitor to a
-- saved world still gets paint/clone after this kit lands. stack_max is 1.
lw_core.starter_tools = {
	"lw_tools:param2",
	"lw_tools:paint",
	"lw_tools:clone",
	"lw_tools:light_wand",
	"lw_theater:remote",
	"lw_tools:stamp",
}

lw_core.starter_kit = {}
for _, list in ipairs({lw_core.starter_tools, lw_core.starter_blocks}) do
	for _, item in ipairs(list) do
		lw_core.starter_kit[#lw_core.starter_kit + 1] = item
	end
end

local function give_items(player, items)
	local inv = player:get_inventory()
	for _, item in ipairs(items) do
		local stack = ItemStack(item)
		local name = stack:get_name()
		if core.registered_items[name] and not inv:contains_item("main", name) then
			inv:add_item("main", stack)
		end
	end
end

function lw_core.give_kit(player)
	give_items(player, lw_core.starter_kit)
end

-- Name used by the issue / by analogy with devtest's give_initial_stuff.
lw_core.give_initial_stuff = lw_core.give_kit

function lw_core.give_tools(player)
	give_items(player, lw_core.starter_tools)
end

core.register_chatcommand("stuff", {
	params = "",
	description = "Give yourself the showcase starter kit",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You have to be in the world."
		end
		lw_core.give_kit(player)
		return true, "Starter kit added to your inventory."
	end,
})

core.register_chatcommand("palette", {
	params = "",
	description = "Open the showcase palette inventory",
	func = function(name)
		if not core.get_player_by_name(name) then
			return false, "You have to be in the world."
		end
		refresh(name)
		return true
	end,
})

--------------------------------------------------------------------------
-- Player setup
--------------------------------------------------------------------------

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	pages[name] = pages[name] or 1
	create_palette_inventory(name)

	local inv = player:get_inventory()
	inv:set_size("main", 32)
	inv:set_size("craft", 0)
	player:set_inventory_formspec(palette_formspec(name))

	-- A showcase visitor should never be able to die or starve out of the
	-- demo, whatever the world was created with.
	player:set_hp(player:get_properties().hp_max)
	player:set_breath(11)
	player:set_properties({zoom_fov = 15})

	local privs = core.get_player_privs(name)
	for _, priv in ipairs({"interact", "shout", "fly", "fast", "noclip", "give", "settime"}) do
		privs[priv] = true
	end
	core.set_player_privs(name, privs)

	-- Returning visitors of a saved world never fire on_newplayer. Restock
	-- the tools (not the wool stacks) so the authoring kit is not trapped
	-- behind `/stuff`.
	lw_core.give_tools(player)
end)

core.register_on_newplayer(function(player)
	lw_core.give_initial_stuff(player)
end)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME and formname ~= "" then
		return
	end
	local name = player:get_player_name()
	local page = pages[name] or 1
	local changed = false

	if fields.lw_next then
		page = page % max_page() + 1
		changed = true
	elseif fields.lw_prev then
		page = (page - 2) % max_page() + 1
		changed = true
	elseif fields.lw_stuff then
		lw_core.give_kit(player)
	else
		return
	end

	pages[name] = page
	if changed then
		-- The player inventory formspec is what `i` opens, so keep both the
		-- open window and the cached formspec on the same page.
		player:set_inventory_formspec(palette_formspec(name))
		if formname == FORMNAME then
			refresh(name)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	pages[name] = nil
	core.remove_detached_inventory(detached_name(name))
end)

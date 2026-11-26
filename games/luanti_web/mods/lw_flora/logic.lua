-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Engine-free half of the plant designer: the design schema, presets,
-- sanitising, flower layouts and the L-system tree definition. Everything
-- here is plain Lua 5.1 so util/content/test_luanti_web_flora.lua can run it
-- without an engine. init.lua owns nodes, items, formspecs and storage.

lw_flora = lw_flora or {}
local L = {}
lw_flora.logic = L

-- Same 16 names as lw_nodes.wool_colors; duplicated so the headless test
-- does not need lw_nodes. init.lua asserts the two lists agree.
L.COLORS = {
	"white", "grey", "dark_grey", "black", "red", "orange", "yellow", "green",
	"dark_green", "cyan", "blue", "violet", "magenta", "pink", "brown", "tan",
}
L.COLOR_SET = {}
for i, c in ipairs(L.COLORS) do
	L.COLOR_SET[c] = i
end

L.BARKS = {"oak", "birch", "dark", "palm"}
L.BARK_SET = {oak = true, birch = true, dark = true, palm = true}

L.HEADS = {"daisy", "tulip", "globe", "spike", "sunflower", "umbel", "tiny"}
L.HEAD_SET = {}
for _, h in ipairs(L.HEADS) do
	L.HEAD_SET[h] = true
end

L.TRUNK_TYPES = {"single", "double", "crossed"}
L.TRUNK_SET = {single = true, double = true, crossed = true}

-- Hard caps. A browser tab shares one heap with the whole engine, so a
-- runaway L-system must be refused before it reaches core.spawn_tree.
L.MAX_STEM = 8
L.MAX_ITERATIONS = 5
L.MAX_AXIOM = 48
L.MAX_RULE = 160
L.MAX_EXPANDED = 24000
L.MAX_NAME = 32
L.MAX_SAVED = 24

--------------------------------------------------------------------------
-- Presets
--------------------------------------------------------------------------

L.FLOWER_PRESETS = {
	{name = "Pink Daisy", head = "daisy", stem = 2, leaves = 1,
		petal = "pink", center = "yellow", foliage = "green"},
	{name = "Red Tulip", head = "tulip", stem = 3, leaves = 2,
		petal = "red", center = "black", foliage = "green"},
	{name = "Blue Globe", head = "globe", stem = 4, leaves = 2,
		petal = "blue", center = "violet", foliage = "dark_green"},
	{name = "Lupin", head = "spike", stem = 3, leaves = 2,
		petal = "violet", center = "magenta", foliage = "green"},
	{name = "Sunflower", head = "sunflower", stem = 6, leaves = 3,
		petal = "yellow", center = "brown", foliage = "green"},
	{name = "Cow Parsley", head = "umbel", stem = 4, leaves = 1,
		petal = "white", center = "tan", foliage = "dark_green"},
	{name = "Buttercup", head = "tiny", stem = 1, leaves = 0,
		petal = "yellow", center = "yellow", foliage = "green"},
}

L.TREE_PRESETS = {
	{name = "Apple", axiom = "FFFFFAFFBF",
		rules_a = "[&&&FFFFF&&FFFF][&&&++++FFFFF&&FFFF][&&&----FFFFF&&FFFF]",
		rules_b = "[&&&++FFFFF&&FFFF][&&&--FFFFF&&FFFF][&&&------FFFFF&&FFFF]",
		angle = 30, iterations = 2, random_level = 0, trunk_type = "single",
		thin = true, bark = "oak", foliage = "green", fruit = "red",
		fruit_chance = 10, blossom = "pink", blossom_chance = 0},
	{name = "Pine", axiom = "TTTTTTA",
		rules_a = "[&&&FF][&&&++++FF][&&&----FF][&&&++++++++FF]TTA",
		rules_b = "",
		angle = 22, iterations = 4, random_level = 1, trunk_type = "single",
		thin = true, bark = "dark", foliage = "dark_green", fruit = "brown",
		fruit_chance = 0, blossom = "green", blossom_chance = 0},
	{name = "Birch", axiom = "TTTTTFFA",
		rules_a = "[&FF][++&FF][----&FF]TFA",
		rules_b = "",
		angle = 30, iterations = 3, random_level = 1, trunk_type = "single",
		thin = true, bark = "birch", foliage = "yellow", fruit = "yellow",
		fruit_chance = 0, blossom = "green", blossom_chance = 30},
	{name = "Palm", axiom = "TTTTTTTA",
		rules_a = "[&&FF&F][++&&FF&F][----&&FF&F][++++++&&FF&F][------&&FF&F]",
		rules_b = "",
		angle = 36, iterations = 2, random_level = 0, trunk_type = "single",
		thin = true, bark = "palm", foliage = "green", fruit = "brown",
		fruit_chance = 8, blossom = "green", blossom_chance = 0},
	{name = "Cherry Blossom", axiom = "TTTTA",
		rules_a = "[&FFB][++&FFB][----&FFB]",
		rules_b = "[&ff^f][++ff][--ff]",
		angle = 35, iterations = 3, random_level = 0, trunk_type = "single",
		thin = true, bark = "dark", foliage = "pink", fruit = "red",
		fruit_chance = 2, blossom = "white", blossom_chance = 25},
	{name = "Weeping Willow", axiom = "TTTTTA",
		rules_a = "[&FF&&&fff][++&FF&&&fff][----&FF&&&fff][++++++&FF&&&fff]TA",
		rules_b = "",
		angle = 30, iterations = 2, random_level = 0, trunk_type = "double",
		thin = true, bark = "oak", foliage = "green", fruit = "green",
		fruit_chance = 0, blossom = "dark_green", blossom_chance = 40},
	{name = "Round Bush", axiom = "TA",
		rules_a = "[&FF][++&FF][----&FF][^F]",
		rules_b = "",
		angle = 45, iterations = 2, random_level = 0, trunk_type = "single",
		thin = true, bark = "oak", foliage = "dark_green", fruit = "blue",
		fruit_chance = 6, blossom = "green", blossom_chance = 30},
}

local function find_preset(list, name)
	for _, p in ipairs(list) do
		if p.name == name then
			return p
		end
	end
end
L.find_preset = find_preset

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end
L.copy = copy

function L.default_design(kind)
	local d
	if kind == "tree" then
		d = copy(L.TREE_PRESETS[1])
	else
		kind = "flower"
		d = copy(L.FLOWER_PRESETS[1])
	end
	d.kind = kind
	return d
end

--------------------------------------------------------------------------
-- Sanitising
--------------------------------------------------------------------------

local function clamp_int(v, lo, hi, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	v = math.floor(v + 0.5)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end
L.clamp_int = clamp_int

local function pick(v, set, default)
	if type(v) == "string" and set[v] then
		return v
	end
	return default
end

-- Only turtle symbols survive; everything else (spaces, typos, other
-- letters) is dropped rather than rejected, so typing stays forgiving.
local RULE_CHARS = "[^GFfTRABCDabcd%+%-&%^/%*%[%]]"

function L.clean_rule(s, max)
	s = tostring(s or ""):gsub(RULE_CHARS, "")
	return s:sub(1, max)
end

function L.clean_name(s)
	s = tostring(s or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return s:sub(1, L.MAX_NAME)
end

-- Brackets must balance or the engine's turtle stack underflows.
function L.brackets_balanced(s)
	local depth = 0
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "[" then
			depth = depth + 1
		elseif c == "]" then
			depth = depth - 1
			if depth < 0 then
				return false
			end
		end
	end
	return depth == 0
end

-- Upper bound on the expanded string length after `iterations` rewrites.
-- Probabilistic a-d are counted as always firing (worst case).
function L.expanded_length(axiom, rules, iterations)
	local function counts(s)
		local c = {other = 0, A = 0, B = 0, C = 0, D = 0}
		for i = 1, #s do
			local ch = s:sub(i, i):upper()
			if c[ch] and ch ~= "OTHER" then
				c[ch] = c[ch] + 1
			else
				c.other = c.other + 1
			end
		end
		return c
	end
	local rc = {}
	for _, k in ipairs({"A", "B", "C", "D"}) do
		rc[k] = counts(rules[k] or "")
	end
	local cur = counts(axiom)
	local total = #axiom
	for _ = 1, iterations do
		local nxt = {other = cur.other, A = 0, B = 0, C = 0, D = 0}
		for _, k in ipairs({"A", "B", "C", "D"}) do
			local n = cur[k]
			if n > 0 then
				local r = rc[k]
				nxt.other = nxt.other + n * r.other
				for _, j in ipairs({"A", "B", "C", "D"}) do
					nxt[j] = nxt[j] + n * r[j]
				end
			end
		end
		cur = nxt
		total = cur.other + cur.A + cur.B + cur.C + cur.D
		if total > L.MAX_EXPANDED * 4 then
			return total
		end
	end
	return total
end

-- Returns a clean copy and a list of human-readable problems. A design
-- with problems is still returned (clamped) so the editor can show it.
function L.sanitize(d)
	d = type(d) == "table" and d or {}
	local out = {}
	local problems = {}
	out.kind = d.kind == "tree" and "tree" or "flower"
	out.name = L.clean_name(d.name)
	if out.name == "" then
		out.name = out.kind == "tree" and "My Tree" or "My Flower"
	end
	if out.kind == "flower" then
		out.head = pick(d.head, L.HEAD_SET, "daisy")
		out.stem = clamp_int(d.stem, 1, L.MAX_STEM, 2)
		out.leaves = clamp_int(d.leaves, 0, math.max(0, out.stem - 1), 0)
		out.petal = pick(d.petal, L.COLOR_SET, "pink")
		out.center = pick(d.center, L.COLOR_SET, "yellow")
		out.foliage = pick(d.foliage, L.COLOR_SET, "green")
		if out.head == "sunflower" and out.stem < 3 then
			out.stem = 3
		end
	else
		out.axiom = L.clean_rule(d.axiom, L.MAX_AXIOM)
		out.rules_a = L.clean_rule(d.rules_a, L.MAX_RULE)
		out.rules_b = L.clean_rule(d.rules_b, L.MAX_RULE)
		out.angle = clamp_int(d.angle, 1, 180, 30)
		out.iterations = clamp_int(d.iterations, 2, L.MAX_ITERATIONS, 2)
		out.random_level = clamp_int(d.random_level, 0, 3, 0)
		out.trunk_type = pick(d.trunk_type, L.TRUNK_SET, "single")
		out.thin = d.thin ~= false and d.thin ~= "false"
		out.bark = pick(d.bark, L.BARK_SET, "oak")
		out.foliage = pick(d.foliage, L.COLOR_SET, "green")
		out.fruit = pick(d.fruit, L.COLOR_SET, "red")
		out.fruit_chance = clamp_int(d.fruit_chance, 0, 100, 0)
		out.blossom = pick(d.blossom, L.COLOR_SET, "pink")
		out.blossom_chance = clamp_int(d.blossom_chance, 0, 100, 0)
		if out.axiom == "" then
			problems[#problems + 1] = "Axiom is empty"
		end
		for _, key in ipairs({"axiom", "rules_a", "rules_b"}) do
			if not L.brackets_balanced(out[key]) then
				problems[#problems + 1] = "Unbalanced [ ] in " .. key
			end
		end
		local len = L.expanded_length(out.axiom,
			{A = out.rules_a, B = out.rules_b}, out.iterations)
		if len > L.MAX_EXPANDED then
			problems[#problems + 1] = ("Too big: ~%d steps (max %d) — " ..
				"lower iterations or shorten rules"):format(len, L.MAX_EXPANDED)
		end
	end
	return out, problems
end

--------------------------------------------------------------------------
-- Node naming (shared with init.lua)
--------------------------------------------------------------------------

function L.node(kind, variant)
	return "lw_flora:" .. kind .. "_" .. variant
end

--------------------------------------------------------------------------
-- Flower layout: list of {x, y, z, node} offsets from the base position
--------------------------------------------------------------------------

local function add(list, seen, x, y, z, node)
	local key = x .. "," .. y .. "," .. z
	if seen[key] then
		return
	end
	seen[key] = true
	list[#list + 1] = {x = x, y = y, z = z, node = node}
end

local SIDES = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}
local RING = {{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}}

local function head_at(list, seen, d, cx, cy, cz)
	local P = L.node("petal", d.petal)
	local C = L.node("petal", d.center)
	local h = d.head
	if h == "daisy" then
		add(list, seen, cx, cy, cz, C)
		for _, o in ipairs(RING) do
			add(list, seen, cx + o[1], cy, cz + o[2], P)
		end
	elseif h == "tulip" then
		add(list, seen, cx, cy, cz, C)
		for dy = 0, 1 do
			for _, o in ipairs(SIDES) do
				add(list, seen, cx + o[1], cy + dy, cz + o[2], P)
			end
		end
	elseif h == "globe" then
		for dx = -1, 1 do
			for dy = 0, 2 do
				for dz = -1, 1 do
					local corner = math.abs(dx) + math.abs(dy - 1) + math.abs(dz)
					if corner <= 2 then
						local n = (dx == 0 and dy == 1 and dz == 0) and C or P
						add(list, seen, cx + dx, cy + dy, cz + dz, n)
					end
				end
			end
		end
	elseif h == "spike" then
		for dy = 0, 3 do
			add(list, seen, cx, cy + dy, cz, dy == 3 and C or P)
			if dy < 3 then
				local o = SIDES[(dy % 4) + 1]
				local o2 = SIDES[((dy + 2) % 4) + 1]
				add(list, seen, cx + o[1], cy + dy, cz + o[2], P)
				add(list, seen, cx + o2[1], cy + dy, cz + o2[2], P)
			end
		end
	elseif h == "sunflower" then
		-- A 5x5 disc standing upright, facing +z, with a 3x3 seed centre.
		for dx = -2, 2 do
			for dy = -2, 2 do
				if math.abs(dx) + math.abs(dy) <= 3 then
					local inner = math.abs(dx) <= 1 and math.abs(dy) <= 1
					add(list, seen, cx + dx, cy + 2 + dy, cz + 1, inner and C or P)
				end
			end
		end
		add(list, seen, cx, cy, cz, L.node("stem", d.foliage))
		add(list, seen, cx, cy + 1, cz, L.node("stem", d.foliage))
		add(list, seen, cx, cy + 2, cz, L.node("stem", d.foliage))
	end
end

function L.flower_layout(d)
	local list, seen = {}, {}
	if d.head == "tiny" then
		add(list, seen, 0, 0, 0, L.node("tiny", d.petal))
		return list
	end
	local S = L.node("stem", d.foliage)
	local F = L.node("leaves", d.foliage)
	for y = 0, d.stem - 1 do
		add(list, seen, 0, y, 0, S)
	end
	for i = 1, d.leaves do
		local o = SIDES[((i - 1) % 4) + 1]
		add(list, seen, o[1], i, o[2], F)
	end
	if d.head == "umbel" then
		-- Three short stalks fan out from the top, each carrying a daisy-
		-- like cap one node across (centre only, no ring) plus a cross.
		local top = d.stem
		add(list, seen, 0, top, 0, S)
		for _, o in ipairs({{2, 0}, {-1, 2}, {-1, -2}}) do
			local sx, sz = o[1] > 0 and 1 or (o[1] < 0 and -1 or 0), o[2] > 0 and 1 or (o[2] < 0 and -1 or 0)
			add(list, seen, sx, top + 1, sz, S)
			local hx, hz = o[1], o[2]
			add(list, seen, hx, top + 2, hz, L.node("petal", d.center))
			for _, s in ipairs(SIDES) do
				add(list, seen, hx + s[1], top + 2, hz + s[2], L.node("petal", d.petal))
			end
		end
		add(list, seen, 0, top + 3, 0, L.node("petal", d.petal))
		return list
	end
	head_at(list, seen, d, 0, d.stem, 0)
	return list
end

--------------------------------------------------------------------------
-- Tree definition for core.spawn_tree
--------------------------------------------------------------------------

function L.tree_def(d, seed)
	local def = {
		axiom = d.axiom,
		rules_a = d.rules_a,
		rules_b = d.rules_b,
		trunk = L.node("bark", d.bark),
		leaves = L.node("leaves", d.foliage),
		angle = d.angle,
		iterations = d.iterations,
		random_level = d.random_level,
		trunk_type = d.trunk_type,
		thin_branches = d.thin,
		fruit = L.node("fruit", d.fruit),
		fruit_chance = d.fruit_chance,
		seed = seed,
	}
	if d.blossom_chance > 0 then
		def.leaves2 = L.node("leaves", d.blossom)
		def.leaves2_chance = d.blossom_chance
	end
	return def
end

--------------------------------------------------------------------------
-- Saved-design list helpers (pure; storage itself is in init.lua)
--------------------------------------------------------------------------

-- Insert or replace by name; newest first; capped.
function L.upsert(list, design)
	local out = {design}
	for _, d in ipairs(list or {}) do
		if d.name ~= design.name and #out < L.MAX_SAVED then
			out[#out + 1] = d
		end
	end
	return out
end

function L.remove(list, index)
	local out = {}
	for i, d in ipairs(list or {}) do
		if i ~= index then
			out[#out + 1] = d
		end
	end
	return out
end

return L

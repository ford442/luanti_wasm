#!/usr/bin/env lua
-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- Headless checks for the plant designer logic (lw_flora/logic.lua).
--
--   lua5.1 util/content/test_luanti_web_flora.lua

local SCRIPT = arg[0]
local ROOT = SCRIPT:match("^(.*)/util/content/") or "."
dofile(ROOT .. "/games/luanti_web/mods/lw_flora/logic.lua")
local L = lw_flora.logic

local failures = 0
local function check(cond, message)
	if not cond then
		failures = failures + 1
		io.stderr:write("FAIL: " .. message .. "\n")
	end
end

-- Every preset sanitises cleanly and survives a round trip unchanged.
for _, p in ipairs(L.FLOWER_PRESETS) do
	local d = L.copy(p)
	d.kind = "flower"
	local clean, problems = L.sanitize(d)
	check(#problems == 0, "flower preset has problems: " .. p.name)
	check(clean.head == p.head, "flower preset head kept: " .. p.name)
	local layout = L.flower_layout(clean)
	check(#layout > 0, "flower layout not empty: " .. p.name)
	local seen = {}
	for _, part in ipairs(layout) do
		local key = part.x .. "," .. part.y .. "," .. part.z
		check(not seen[key], "duplicate cell in " .. p.name .. " at " .. key)
		seen[key] = true
		check(part.node:match("^lw_flora:%a+_[%a_]+$") ~= nil, "bad node name " .. part.node)
		check(part.y >= 0, "flower part below base in " .. p.name)
	end
end

for _, p in ipairs(L.TREE_PRESETS) do
	local d = L.copy(p)
	d.kind = "tree"
	local clean, problems = L.sanitize(d)
	check(#problems == 0, "tree preset has problems: " .. p.name .. " " .. tostring(problems[1]))
	local def = L.tree_def(clean, 42)
	check(def.trunk == "lw_flora:bark_" .. p.bark, "trunk node for " .. p.name)
	check(def.iterations >= 2 and def.iterations <= L.MAX_ITERATIONS, "iterations clamp " .. p.name)
end

-- Clamping and cleaning.
local d = L.sanitize({kind = "flower", stem = 99, leaves = 99, petal = "chartreuse", head = "nope"})
check(d.stem == L.MAX_STEM, "stem clamped")
check(d.leaves == L.MAX_STEM - 1, "leaves clamped to stem-1")
check(d.petal == "pink", "unknown colour falls back")
check(d.head == "daisy", "unknown head falls back")

local t, problems = L.sanitize({kind = "tree", axiom = "FF x y [A", rules_a = "F", iterations = 9})
check(t.axiom == "FF[A", "rule text filtered to turtle symbols, got " .. t.axiom)
check(t.iterations == L.MAX_ITERATIONS, "iterations clamped")
check(#problems > 0, "unbalanced bracket reported")

-- Blow-up guard: AAAA -> AAAA... grows 4^n.
local big, bp = L.sanitize({kind = "tree", axiom = ("A"):rep(40),
	rules_a = ("FA"):rep(40), iterations = 5})
check(#bp > 0 and bp[#bp]:find("Too big"), "exponential rules refused")
check(L.expanded_length("FA", {A = "FA"}, 3) == 5, "linear growth counted, got "
	.. L.expanded_length("FA", {A = "FA"}, 3))

-- Name cleaning.
check(L.clean_name("  hi\n  ") == "hi", "name trimmed")
check(#L.clean_name(("x"):rep(100)) == L.MAX_NAME, "name capped")

-- Saved list helpers.
local list = {}
for i = 1, L.MAX_SAVED + 5 do
	list = L.upsert(list, {name = "d" .. i})
end
check(#list == L.MAX_SAVED, "saved list capped")
check(list[1].name == "d" .. (L.MAX_SAVED + 5), "newest first")
list = L.upsert(list, {name = "d10", v = 2})
check(list[1].v == 2, "upsert replaces by name")
local count = 0
for _, x in ipairs(list) do if x.name == "d10" then count = count + 1 end end
check(count == 1, "upsert dedupes")
check(#L.remove(list, 1) == #list - 1, "remove drops one")

if failures > 0 then
	io.stderr:write(failures .. " failure(s)\n")
	os.exit(1)
end
print("plant designer checks ok")

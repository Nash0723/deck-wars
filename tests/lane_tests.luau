-- Headless tests for the Deck Wars lane rules (two rows per lane).
-- Run from the repo root: luaurun tests/lane_tests.luau src/shared
-- Optional globals: SOAK_GAMES (bot games per mode, default 40).
local CardData = require("CardData")
local MatchEngine = require("MatchEngine")
local BotBrain = require("BotBrain")
local StarterDecks = require("StarterDecks")
local Rng = require("Rng")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. msg)
	end
end

local function filler(n)
	local d = {}
	for _ = 1, n do
		table.insert(d, "tin_can_tom")
	end
	return d
end

-- A 1v1 match wiped to a known state: empty board and hands, plain landscapes, 10 magic,
-- seat 1's turn (turn 3, so creatures from earlier turns may attack).
local function blank(seed)
	local m = MatchEngine.new({ { deck = filler(30), hero = "bonk", family = "Snack" }, { deck = filler(30), hero = "granny_bolt", family = "Snack" } }, seed or 1)
	for t = 1, 2 do
		for _, l in ipairs(m.lanes[t]) do
			l.creature, l.back, l.building, l.scrap = nil, nil, nil, 0
			l.landscape = "Spooky"
		end
	end
	for _, seat in ipairs(m.seats) do
		seat.hand = {}
		seat.magic = 10
		seat.maxMagic = 8
	end
	m.current = 1
	m.turn = 3
	m:takeEvents()
	return m
end

local function put(m, s, id, lane, row)
	local u = m:spawn(s, lane, id, { row = row })
	u.playedTurn = -1
	return u
end

local function give(m, s, id)
	return m:addToHand(s, id)
end

-- Plain test creatures: tin_can_tom is 2/2 Junk, couch_golem is big.
do -- Front creature hits the enemy Front creature, not the Back one
	local m = blank()
	local a = put(m, 1, "pretzel_guard", 1, 1) -- 2/5 Sturdy
	local f = put(m, 2, "couch_golem", 1, 1)
	local b = put(m, 2, "tin_can_tom", 1, 2)
	local fHp, bHp = m:healthOf(f), m:healthOf(b)
	m:attack(a, 2)
	check(m:healthOf(f) < fHp, "front attacker hits the enemy Front creature")
	check(m:healthOf(b) == bHp, "the Back creature is shielded while the Front stands")
end

do -- with an empty enemy Front tile the attack reaches the Back creature
	local m = blank()
	local a = put(m, 1, "pretzel_guard", 2, 1)
	local b = put(m, 2, "couch_golem", 2, 2)
	local hp0 = m.teams[2].hp
	local bHp = m:healthOf(b)
	m:attack(a, 2)
	check(m:healthOf(b) < bHp, "attack reaches the Back creature through an empty Front tile")
	check(m.teams[2].hp == hp0, "hero not hit while the lane has a creature")
end

do -- hero is hit only when both rows of the lane are empty
	local m = blank()
	local a = put(m, 1, "pretzel_guard", 3, 1)
	local hp0 = m.teams[2].hp
	m:attack(a, 2)
	check(m.teams[2].hp == hp0 - m:attackOf(a), "an empty lane lets the attack hit the hero")
end

do -- overkill rolls on to the Back creature, then the hero
	local m = blank()
	local big = put(m, 1, "couch_golem", 1, 1)
	big.atkBonus = 10 -- huge
	local f = put(m, 2, "tin_can_tom", 1, 1) -- 2 hp
	local b = put(m, 2, "pocket_mouse", 1, 2) -- small
	local hp0 = m.teams[2].hp
	local atk = m:attackOf(big)
	m:attack(big, 2)
	check(not m:findUnit(f.uid) and not m:findUnit(b.uid), "overkill pops the Front and then the Back creature")
	check(m.teams[2].hp < hp0, "what's left after both rolls on to the hero")
	check(m.teams[2].hp >= hp0 - atk, "overkill never deals more than the attack")
end

do -- a creature that survives stops the overkill
	local m = blank()
	local a = put(m, 1, "pretzel_guard", 4, 1)
	local f = put(m, 2, "couch_golem", 4, 1)
	local b = put(m, 2, "tin_can_tom", 4, 2)
	local bHp = m:healthOf(b)
	m:attack(a, 2)
	check(m:findUnit(f.uid) ~= nil and m:healthOf(b) == bHp, "no overkill when the Front creature holds")
end

do -- Back creatures without Ranged don't attack; they step up after the battle
	local m = blank()
	local back = put(m, 1, "pretzel_guard", 2, 2)
	local hp0 = m.teams[2].hp
	m:act(1, { kind = "battle" })
	check(m.teams[2].hp == hp0, "a Back creature without Ranged doesn't attack")
	check(back.row == 1 and m:unitAt(1, 2, 1) == back, "a Back creature steps up into an empty Front tile after its battle")
end

do -- Ranged from the Back row shoots the weakest enemy in reach, either row
	local m = blank()
	local r = put(m, 1, "microwave_mage", 2, 2)
	check(m:hasKeyword(r, "Ranged"), "microwave_mage has Ranged")
	put(m, 1, "couch_golem", 2, 1) -- keeps the mage in the back
	local strong = put(m, 2, "couch_golem", 2, 1)
	local weak = put(m, 2, "pocket_mouse", 3, 2)
	check(m:attackTarget(r) == weak, "Back Ranged picks the weakest enemy in its lane or the lanes next to it, in either row")
	local front = put(m, 1, "microwave_mage", 4, 1)
	local across = put(m, 2, "couch_golem", 4, 1)
	put(m, 2, "pocket_mouse", 3, 1)
	check(m:attackTarget(front) == across, "Front Ranged fights like melee (first enemy in its own lane)")
	local _ = strong
end

do -- Shift swaps rows, costs magic, skips the attack, once per turn
	local m = blank()
	local a = put(m, 1, "pretzel_guard", 1, 1)
	local b = put(m, 1, "tin_can_tom", 1, 2)
	local magic = m.seats[1].magic
	local ok = m:act(1, { kind = "shift", uid = a.uid })
	check(ok, "shift works")
	check(a.row == 2 and b.row == 1, "shift trades the two creatures' rows")
	check(m.seats[1].magic == magic - CardData.ShiftCost, "shift costs ShiftCost magic")
	local ok2 = m:act(1, { kind = "shift", uid = a.uid })
	check(not ok2, "shift only once per turn per creature")
	local hp0 = m.teams[2].hp
	m:act(1, { kind = "battle" })
	-- b (now Front, not shifted) attacks the empty lane; a (shifted, Back) doesn't
	check(m.teams[2].hp == hp0 - m:attackOf(b), "only the creature you Shift skips its attack")
end

do -- playing into a chosen row, and the default row
	local m = blank()
	local e = give(m, 1, "pretzel_guard")
	check(m:act(1, { kind = "play", handUid = e.uid, lane = 2, row = 2 }), "play a creature into the Back row")
	check(m:unitAt(1, 2, 2) ~= nil and m:unitAt(1, 2, 1) == nil, "it lands in the Back row")
	local e2 = give(m, 1, "tin_can_tom")
	check(m:act(1, { kind = "play", handUid = e2.uid, lane = 3 }), "play without a row")
	check(m:unitAt(1, 3, 1) ~= nil, "without a row it takes the Front tile")
	local e3 = give(m, 1, "tin_can_tom")
	check(not m:act(1, { kind = "play", handUid = e3.uid, lane = 3, row = 3 }), "row 3 is refused")
	local list = m:listActions(1)
	local tiles = nil
	for _, a in ipairs(list) do
		if a.kind == "play" and a.handUid == e3.uid then
			tiles = a.tiles
		end
	end
	check(tiles ~= nil and #tiles == 8, "a creature card lists all 8 of your tiles")
end

do -- Splash hits neighbours of the target: beside it and behind it
	local m = blank()
	local a = put(m, 1, "pretzel_guard", 2, 1)
	a.given.Splash = true
	local t = put(m, 2, "pancake_paladin", 2, 1)
	local side = put(m, 2, "pancake_paladin", 3, 1)
	local behind = put(m, 2, "pancake_paladin", 2, 2)
	local diag = put(m, 2, "pancake_paladin", 3, 2)
	local h1, h2, h3 = m:healthOf(side), m:healthOf(behind), m:healthOf(diag)
	m:attack(a, 2)
	check(m:healthOf(side) == h1 - 1 and m:healthOf(behind) == h2 - 1, "Splash hits beside and behind the target")
	check(m:healthOf(diag) == h3, "Splash doesn't hit diagonally")
	local _ = t
end

do -- Haunt ghost rises on the same tile
	local m = blank()
	local g = put(m, 2, "sheet_ghost", 3, 2)
	g.given.Haunt = true
	m:damageCreature(g, 99, { seat = 1 })
	m:resolvePops()
	local now = m:unitAt(2, 3, 2)
	check(now ~= nil and now.id == "ghost", "Haunt: a Ghost rises on the tile it fell on")
end

do -- Strike bowls through both rows
	local m = blank()
	m.seats[1].hero = "granny_bolt"
	m.seats[1].dealt = 99
	put(m, 2, "tin_can_tom", 1, 1) -- 2 hp
	put(m, 2, "pocket_mouse", 1, 2)
	local hp0 = m.teams[2].hp
	check(m:act(1, { kind = "bigmove", target = { team = 2, lane = 1 } }), "Strike works")
	check(m:unitAt(2, 1, 1) == nil, "Strike pops the Front creature")
	check(m.teams[2].hp <= hp0, "Strike doesn't heal the hero")
end

do -- lane buildings cover both tiles
	local m = blank()
	m:build(1, 2, "bouncy_castle")
	local f = put(m, 1, "pocket_mouse", 2, 1)
	local b = put(m, 1, "pocket_mouse", 2, 2)
	check(m:hasKeyword(f, "Sturdy") and m:hasKeyword(b, "Sturdy"), "a lane building covers both rows")
end

do -- deck lane terrains
	local m = MatchEngine.new({ { deck = filler(30), hero = "bonk", family = "Snack", lanes = { "Snack", "Critter", "Critter", "Snack" } }, { deck = filler(30), hero = "bonk", family = "Robo" } }, 5)
	check(m.lanes[1][2].landscape == "Critter" and m.lanes[1][4].landscape == "Snack", "a deck's lane terrains are used")
	check(m.lanes[2][1].landscape == "Robo", "without terrains the family is used")
	local v = m:viewFor(1)
	check(v.rows == 2 and v.lanes[1][1].back == nil, "view has rows and Back tiles")
end

-- Bot soak: whole matches, 1v1 and 2v2, every themed deck, no errors and sane length.
local GAMES = SOAK_GAMES or 40
local rng = Rng.new(99)
local order = StarterDecks.Order
local function setup(fam)
	local d = StarterDecks[fam]
	return { deck = table.clone(d.cards), hero = d.hero, family = d.family, name = d.name }
end
local wins = {}
local firstWins, decided, turns, overs = 0, 0, 0, 0
local diffs = { "Hard", "Medium" }
for g = 1, GAMES do
	local a, b = order[(g - 1) % 6 + 1], order[rng:int(1, 6)]
	local m = MatchEngine.new({ setup(a), setup(b) }, 1000 + g)
	local guard = 0
	local ok, err = pcall(function()
		while not m.over and guard < 400 do
			guard += 1
			BotBrain.playTurn(m, m.current, diffs[(g % 2) + 1], rng)
			m:takeEvents()
		end
	end)
	check(ok, "1v1 bot game " .. g .. " runs: " .. tostring(err))
	check(m.over, "1v1 bot game " .. g .. " ends")
	if m.over then
		overs += 1
		turns += m.turn
		if m.winner ~= 0 then
			decided += 1
			if m.winner == 1 then
				firstWins += 1
			end
			local fam = m.winner == 1 and a or b
			wins[fam] = (wins[fam] or 0) + 1
		end
	end
end
print(("1v1: %d games, average %.1f turns, first team won %d of %d decided"):format(GAMES, turns / math.max(1, overs), firstWins, decided))
local parts = {}
for _, fam in ipairs(order) do
	table.insert(parts, fam .. " " .. (wins[fam] or 0))
end
print("  wins by deck: " .. table.concat(parts, ", "))

for g = 1, math.max(4, GAMES // 8) do
	local m = MatchEngine.new({ setup(order[g % 6 + 1]), setup(order[(g + 1) % 6 + 1]), setup(order[(g + 2) % 6 + 1]), setup(order[(g + 3) % 6 + 1]) }, 5000 + g)
	local guard = 0
	local ok, err = pcall(function()
		while not m.over and guard < 600 do
			guard += 1
			BotBrain.playTurn(m, m.current, "Medium", rng)
			m:takeEvents()
		end
	end)
	check(ok, "2v2 bot game " .. g .. " runs: " .. tostring(err))
	check(m.over, "2v2 bot game " .. g .. " ends")
end

print(("lane tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("lane tests failed")
end

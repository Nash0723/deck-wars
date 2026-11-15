-- Headless tests for enchants: the rune list, the dice (odds, Lucky, bad luck protection), every
-- power in a match, duels (the rune only glows), the save (Enchanting Crystal, keep new or old)
-- and bot games with enchanted decks.
-- Run from the repo root: luaurun tests/enchant_tests.luau src/shared src/econ src/packbrawl
local CardData = require("CardData")
local Enchants = require("Enchants")
local MatchEngine = require("MatchEngine")
local BotBrain = require("BotBrain")
local StarterDecks = require("StarterDecks")
local Rng = require("Rng")
local ProfileStore = require("ProfileStore")
local EconomyManager = require("EconomyManager")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. msg)
	end
end

---------------------------------------------------------------------------
-- The runes
---------------------------------------------------------------------------
do
	local seen = {}
	for _, e in ipairs(Enchants.List) do
		check(not seen[e.id], "enchant ids are unique: " .. e.id)
		seen[e.id] = true
		check(Enchants.Rank[e.rarity] ~= nil, e.id .. " has a known rarity")
		check(e["for"] == "Creature" or e["for"] == "Spell", e.id .. " is for creatures or spells")
		check(type(e.text) == "string" and #e.text > 0 and type(e.name) == "string", e.id .. " has a name and text")
		check(Enchants.Palettes[e.rarity] and Enchants.Colors[e.rarity], e.id .. "'s rarity has colours")
	end
	for _, r in ipairs(Enchants.Rarities) do
		check(#Enchants.pool("pretzel_guard", r) > 0, "creatures have " .. r .. " enchants")
		check(#Enchants.pool("snack_break", r) > 0, "spells have " .. r .. " enchants")
	end
	local building = nil
	for _, id in ipairs(CardData.List) do
		if CardData.Cards[id].type == "Building" then
			building = id
			break
		end
	end
	check(building == nil or not Enchants.canEnchant(building), "buildings can't be enchanted")
	check(not Enchants.canEnchant("ghost"), "tokens can't be enchanted")
	check(Enchants.fits("thick_hide", "pretzel_guard") and not Enchants.fits("thick_hide", "snack_break"), "creature runes only fit creatures")
	local clean = Enchants.sanitize({ pretzel_guard = "thick_hide", snack_break = "thick_hide", nope = "fury", couch_golem = "nope" })
	check(clean.pretzel_guard == "thick_hide" and clean.snack_break == nil and clean.nope == nil and clean.couch_golem == nil, "sanitize keeps only fitting enchants")
end

---------------------------------------------------------------------------
-- The dice
---------------------------------------------------------------------------
do
	local rng = Rng.new(5)
	local function rand()
		return rng:next()
	end
	local counts, n = {}, 60000
	for _ = 1, n do
		local _, r = Enchants.roll("pretzel_guard", rand, false, 0)
		counts[r] = (counts[r] or 0) + 1
	end
	local total = 0
	for _, r in ipairs(Enchants.Rarities) do
		total += Enchants.Odds[r]
	end
	for _, r in ipairs(Enchants.Rarities) do
		local want = Enchants.Odds[r] / total
		local got = (counts[r] or 0) / n
		check(math.abs(got - want) < math.max(0.004, want * 0.15), string.format("%s comes up about %.1f%% of the time (got %.2f%%)", r, want * 100, got * 100))
	end
	local commons = 0
	for _ = 1, 5000 do
		local _, r = Enchants.roll("pretzel_guard", rand, true, 0)
		if r == "Common" then
			commons += 1
		end
	end
	check(commons == 0, "Lucky enchants never roll Common")
	-- bad luck protection: after PityRolls below Epic, the next one is Epic or better
	local lowRand = function()
		return 0.01 -- always the lowest rarity on offer
	end
	local pity = 0
	local seenLow = 0
	for _ = 1, Enchants.PityRolls do
		local _, r, p = Enchants.roll("pretzel_guard", lowRand, false, pity)
		if Enchants.Rank[r] < 3 then
			seenLow += 1
		end
		pity = p
	end
	check(seenLow == Enchants.PityRolls and pity == Enchants.PityRolls, "pity counts enchants below Epic")
	local _, r, p = Enchants.roll("pretzel_guard", lowRand, false, pity)
	check(Enchants.Rank[r] >= 3 and p == 0, "the protected roll is Epic or better and resets the count (got " .. tostring(r) .. ")")
	check(Enchants.untilPity(0) == Enchants.PityRolls + 1 and Enchants.untilPity(Enchants.PityRolls) == 1, "untilPity counts down to the sure Epic")
end

---------------------------------------------------------------------------
-- In a match
---------------------------------------------------------------------------

local function filler(n)
	local d = {}
	for _ = 1, n do
		table.insert(d, "tin_can_tom")
	end
	return d
end

-- A 1v1 match on a known board: seat 1 has `en1` enchants, seat 2 `en2`; levelStats as given.
local function blank(en1, en2, levelStats)
	local m = MatchEngine.new({
		{ deck = filler(30), hero = "bonk", family = "Snack", enchants = en1, levelStats = levelStats },
		{ deck = filler(30), hero = "granny_bolt", family = "Snack", enchants = en2, levelStats = levelStats },
	}, 3)
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

local function events(m, kind, what)
	local out = {}
	for _, e in ipairs(m:takeEvents()) do
		if e.type == kind and (what == nil or e.what == what) then
			table.insert(out, e)
		end
	end
	return out
end

do -- stats, Power, Bubble, keywords
	local m = blank({ couch_golem = "titan_blood", pretzel_guard = "head_start", tin_can_tom = "bubble_ward", drizzle_sprite = "swift" }, {}, true)
	local g = put(m, 1, "couch_golem", 1, 1)
	local base = CardData.Cards.couch_golem
	check(m:maxHpOf(g) == base.hp + 3 and m:snapshot(g).atk == base.atk + 2, "Titan Blood: +2 attack, +3 health")
	check(m:snapshot(g).enchant == "titan_blood" and m:snapshot(g).enchantLive == true, "the snapshot carries the enchant")
	local arrive = events(m, "enchant", "arrive")
	check(#arrive == 1 and arrive[1].uid == g.uid and arrive[1].live == true, "an enchanted creature's arrival is an event")
	local p = put(m, 1, "pretzel_guard", 2, 1)
	check(p.power == 1, "Head Start: arrives with 1 Power")
	local t = put(m, 1, "tin_can_tom", 3, 1)
	check(t.shield == true, "Bubble Ward: arrives with a Bubble")
	local d = m:spawn(1, 4, "drizzle_sprite", { row = 1 })
	check(m:hasKeyword(d, "Zoom") and not m:isNew(d), "Swift: Zoom, so it can attack on its first turn")
	-- washing keeps the enchant's numbers (like card levels)
	m:wash(g)
	check(m:maxHpOf(g) == base.hp + 3, "washing keeps the enchant's health")
	local plain = put(m, 2, "couch_golem", 1, 1)
	check(m:maxHpOf(plain) == base.hp and plain.enchant == nil, "the other seat's copies aren't enchanted")
end

do -- Thorns
	local m = blank({}, { couch_golem = "thorns" }, true)
	local a = put(m, 1, "pretzel_guard", 1, 1)
	local g = put(m, 2, "couch_golem", 1, 1)
	m:takeEvents()
	local hp = m:healthOf(a)
	m:attack(a, 2)
	local th = events(m, "enchant", "thorns")
	check(#th == 1 and th[1].target == a.uid, "Thorns fires when it's hit")
	check(m:hasKeyword(a, "Sturdy") and m:healthOf(a) == hp, "Sturdy still takes 1 less: a Sturdy attacker shrugs off 1 Thorns damage")
	local a2 = put(m, 1, "tin_can_tom", 2, 1)
	put(m, 2, "couch_golem", 2, 1)
	local hp2 = m:healthOf(a2)
	m:attack(a2, 2)
	check(m:healthOf(a2) == hp2 - 1, "Thorns: 1 damage back")
	check(m:maxHpOf(g) == CardData.Cards.couch_golem.hp + 1, "Thorns also gives +1 health")
end

do -- Leech and Vampire
	local m = blank({ tin_can_tom = "leech", couch_golem = "vampire" }, {}, true)
	m.teams[1].hp = 10
	local a = put(m, 1, "tin_can_tom", 1, 1)
	m:attack(a, 2) -- an empty lane: it hits the hero
	check(m.teams[1].hp == 11, "Leech heals your hero 1 when it hits")
	check(#events(m, "enchant", "leech") == 1, "Leech is an event")
	local v = put(m, 1, "couch_golem", 2, 1)
	v.damage = 2
	put(m, 2, "pretzel_guard", 2, 1)
	m:attack(v, 2)
	check(m.teams[1].hp == 13 and v.damage == 1, "Vampire heals the hero 2 and itself 1")
	-- a hit that does nothing (a Bubble) heals nothing
	local b = put(m, 2, "couch_golem", 3, 1)
	b.shield = true
	local a3 = put(m, 1, "tin_can_tom", 3, 1)
	local before = m.teams[1].hp
	m:attack(a3, 2)
	check(m.teams[1].hp == before, "no damage, no Leech")
end

do -- Phoenix and Crown of Ages
	local m = blank({ tin_can_tom = "phoenix", couch_golem = "crown_of_ages" }, {}, true)
	local t = put(m, 1, "tin_can_tom", 1, 1)
	m:damageCreature(t, 99, { seat = 2 })
	m:resolvePops()
	local back = m:unitAt(1, 1, 1)
	check(back ~= nil and back.uid ~= t.uid and back.id == "tin_can_tom", "Phoenix rises again on its tile")
	check(back and m:healthOf(back) == math.ceil(m:maxHpOf(back) * 0.5), "Phoenix comes back with half its health")
	local ev = events(m, "enchant", "rebirth")
	check(#ev == 1, "the rebirth is an event")
	local discards = 0
	for _, id in ipairs(m.seats[1].discard) do
		if id == "tin_can_tom" then
			discards += 1
		end
	end
	check(discards == 0, "a risen Phoenix isn't left in the discard pile too")
	m:damageCreature(back, 99, { seat = 2 })
	m:resolvePops()
	local again = m:unitAt(1, 1, 1)
	check(again == nil or again.id ~= "tin_can_tom", "Phoenix only rises once")
	local c = put(m, 1, "couch_golem", 2, 1)
	check(m:hasKeyword(c, "Sturdy"), "Crown of Ages: Sturdy")
	m:damageCreature(c, 99, { seat = 2 })
	m:resolvePops()
	local cb = m:unitAt(1, 2, 1)
	check(cb and cb.id == "couch_golem" and cb.damage == 0, "Crown of Ages rises at full health")
end

do -- spells: cheaper, heal, draw
	local m = blank({ sneeze_storm = "quick_cast", snack_break = "wellspring", spare_battery = "echo", pothole = "inkwell" }, {}, true)
	m.seats[1].deck = filler(10)
	local e1 = m:addToHand(1, "sneeze_storm")
	check(m:costOf(1, e1) == CardData.Cards.sneeze_storm.cost - 1, "Quick Cast: costs 1 less")
	local e2 = m:addToHand(1, "spare_battery")
	check(m:costOf(1, e2) == CardData.Cards.spare_battery.cost, "never below 1 (a 0-cost card stays as it is)")
	m.teams[1].hp = 10
	local hand0 = #m.seats[1].hand
	local e3 = m:addToHand(1, "snack_break")
	check(m:costOf(1, e3) == math.max(1, CardData.Cards.snack_break.cost - 1), "Wellspring costs 1 less")
	local ok = m:act(1, { kind = "play", handUid = e3.uid })
	check(ok, "the enchanted spell can be cast")
	check(m.teams[1].hp == math.min(m.teams[1].maxHp, 10 + 4 + 3), "Wellspring heals the hero 3 more")
	check(#m.seats[1].hand == hand0 + 1, "Wellspring draws a card (the spell left the hand, one came in)")
	local view = m:viewFor(1)
	local tagged = false
	for _, h in ipairs(view.hand) do
		if h.id == "sneeze_storm" and h.enchant == "quick_cast" then
			tagged = true
		end
	end
	check(tagged, "your hand shows which cards are enchanted")
end

do -- duels: the rune glows, the card plays at its printed numbers
	local m = blank({ couch_golem = "titan_blood", tin_can_tom = "phoenix", sneeze_storm = "quick_cast" }, {}, false)
	local g = put(m, 1, "couch_golem", 1, 1)
	check(m:maxHpOf(g) == CardData.Cards.couch_golem.hp and m:snapshot(g).atk == CardData.Cards.couch_golem.atk, "in a duel the numbers stay printed")
	check(m:snapshot(g).enchant == "titan_blood" and m:snapshot(g).enchantLive == false, "in a duel the enchant still shows")
	local ev = events(m, "enchant", "arrive")
	check(#ev == 1 and ev[1].live == false, "the arrival still glows (live = false)")
	local t = put(m, 1, "tin_can_tom", 2, 1)
	m:damageCreature(t, 99, { seat = 2 })
	m:resolvePops()
	check(m:unitAt(1, 2, 1) == nil, "no Phoenix in a duel")
	local e = m:addToHand(1, "sneeze_storm")
	check(m:costOf(1, e) == CardData.Cards.sneeze_storm.cost, "no cheaper spells in a duel")
end

do -- bots with enchanted decks play whole games without trouble
	local all = {}
	for _, id in ipairs(CardData.List) do
		if Enchants.canEnchant(id) then
			local c = CardData.Cards[id]
			local pool = {}
			for _, r in ipairs(Enchants.Rarities) do
				for _, eid in ipairs(Enchants.pool(id, r)) do
					table.insert(pool, eid)
				end
			end
			all[id] = pool[(#id % #pool) + 1]
			if c.type == "Creature" and #id % 3 == 0 then
				all[id] = (#id % 2 == 0) and "phoenix" or "crown_of_ages"
			end
		end
	end
	local games, errors, finished = tonumber(_G.ENCHANT_GAMES) or 30, 0, 0
	local order = StarterDecks.Order
	for g = 1, games do
		local d1, d2 = StarterDecks[order[(g - 1) % #order + 1]], StarterDecks[order[g % #order + 1]]
		local ok, err = pcall(function()
			local m = MatchEngine.new({
				{ deck = d1.cards, hero = d1.hero, family = d1.family, enchants = all },
				{ deck = d2.cards, hero = d2.hero, family = d2.family, enchants = (g % 2 == 0) and all or nil },
			}, 1000 + g)
			local rng = Rng.new(g)
			local guard = 0
			while not m.over and guard < 4000 do
				guard += 1
				local s = m.current
				local action = BotBrain.chooseAction(m, s, "Hard", rng)
				if not action or not m:act(s, action) then
					m:act(s, { kind = "battle" })
				end
				m:takeEvents()
			end
			if m.over then
				finished += 1
			end
		end)
		if not ok then
			errors += 1
			print("game error: " .. tostring(err))
		end
	end
	check(errors == 0, "no errors in " .. games .. " bot games with enchanted decks")
	check(finished == games, "every enchanted bot game finishes (" .. finished .. "/" .. games .. ")")
end

---------------------------------------------------------------------------
-- The save: the Enchanting Crystal
---------------------------------------------------------------------------
do
	local now = 1000000
	local nextRand = 0.01
	EconomyManager.init({
		dataStore = ProfileStore.memoryStore(),
		jobId = "enchant-test",
		clock = function()
			return now
		end,
		wait = function() end,
		warn = function() end,
		random = function()
			return nextRand
		end,
	})
	local p = { UserId = 777, Name = "nash" }
	check(EconomyManager.load(p) ~= nil, "the save loads")
	local ok, why = EconomyManager.enchantCard(p, "pretzel_guard", "coins")
	check(not ok and tostring(why):find("own") ~= nil, "you can't enchant a card you don't own")
	EconomyManager.grantCards(p, { "pretzel_guard", "snack_break" }, "test")
	local d = EconomyManager.waitForData(p)
	d.coins = 1000
	local c0 = d.coins
	local ok2, r = EconomyManager.enchantCard(p, "pretzel_guard", "coins")
	check(ok2 and r.rarity == "Common" and not r.pending, "the first enchant goes straight on")
	check(d.coins == c0 - Enchants.Cost.Coins, "it costs " .. Enchants.Cost.Coins .. " Coins")
	check(EconomyManager.getEnchants(p).enchants.pretzel_guard == r.enchant, "the enchant is saved on the card")
	-- a second roll on the same card waits for the choice
	nextRand = 0.999
	local ok3, r3 = EconomyManager.enchantCard(p, "pretzel_guard", "coins")
	check(ok3 and r3.pending and r3.old == r.enchant, "rolling an enchanted card asks keep new or old")
	check(EconomyManager.getEnchants(p).enchants.pretzel_guard == r.enchant, "until you choose, the old one stays")
	local ok4 = EconomyManager.enchantCard(p, "snack_break", "coins")
	check(not ok4, "no new roll until you choose")
	local okC, rc = EconomyManager.chooseEnchant(p, true)
	check(okC and rc.kept == "new" and EconomyManager.getEnchants(p).enchants.pretzel_guard == r3.enchant, "keep new puts the new rune on")
	check(EconomyManager.getEnchants(p).pending == nil, "the choice is settled")
	local okNone = EconomyManager.chooseEnchant(p, true)
	check(not okNone, "nothing to choose after that")
	-- keep old
	nextRand = 0.01
	EconomyManager.enchantCard(p, "pretzel_guard", "coins")
	EconomyManager.chooseEnchant(p, false)
	check(EconomyManager.getEnchants(p).enchants.pretzel_guard == r3.enchant, "keep old keeps the old rune")
	-- Lucky costs Gems; out of money
	d.gems = Enchants.LuckyCost.Gems
	local okL, rl = EconomyManager.enchantCard(p, "snack_break", "lucky")
	check(okL and rl.rarity ~= "Common" and d.gems == 0, "Lucky costs Gems and skips Common")
	d.coins = 0
	local okP, whyP = EconomyManager.enchantCard(p, "snack_break", "coins")
	check(not okP and tostring(whyP):find("Coins") ~= nil, "not enough Coins: no roll")
	check(EconomyManager.getEnchants(p).enchants.snack_break == rl.enchant, "a refused roll changes nothing")
	-- buildings can't be enchanted
	local building = nil
	for _, id in ipairs(CardData.List) do
		if CardData.Cards[id].type == "Building" then
			building = id
			break
		end
	end
	if building then
		EconomyManager.grantCards(p, { building }, "test")
		d.coins = 1000
		check(not EconomyManager.enchantCard(p, building, "coins"), "buildings can't be enchanted")
	end
end

print(string.format("enchant tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("enchant tests failed")
end

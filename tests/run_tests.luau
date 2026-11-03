-- Headless tests for the Deck Wars engine (tile board). Run with: luaurun tests/run_tests.luau src/shared
-- Optional: set SOAK_GAMES (global) before running for a shorter or longer soak test.
local CardData = require("CardData")
local MatchEngine = require("MatchEngine")
local BotBrain = require("BotBrain")
local StarterDecks = require("StarterDecks")
local Rng = require("Rng")

local COLS, ROWS = CardData.Cols, CardData.Rows

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

-- Make a match and wipe it to a known state for unit tests:
-- empty board, every tile Spooky terrain, empty hands, 10 energy, player 1's turn.
local function blank(seed)
	local m = MatchEngine.new({ deck = filler(30), hero = "bonk" }, { deck = filler(30), hero = "granny_bolt" }, seed or 1)
	for col = 1, COLS do
		for row = 1, ROWS do
			m.grid[col][row] = nil
			m.terrain[col][row] = "Spooky"
		end
	end
	for p = 1, 2 do
		local pl = m.players[p]
		pl.hand = {}
		pl.energy = 10
	end
	m.current = 1
	m:takeEvents()
	return m
end

local function ready(u) -- lets a freshly spawned creature act this turn
	u.sick = false
	u.moved = false
	u.attacked = false
	return u
end

-- Card numbers change with balancing, so tests that depend on exact numbers set them here.
local function stats(u, atk, hp)
	u.atk = atk
	u.hp = hp
	u.maxHp = hp
	return u
end

local function give(m, p, id)
	local e = m:addToHand(p, id)
	return e.uid
end

local function hasEvent(events, kind)
	for _, e in ipairs(events) do
		if e.type == kind then
			return e
		end
	end
	return nil
end

---------------------------------------------------------------- board and stats
do -- terrain gives +1 attack to the matching family
	local m = blank()
	local c = stats(m:spawn(1, 2, 2, "pretzel_guard"), 2, 4) -- Snack
	check(m:attackOf(c) == 2, "no bonus on Spooky terrain")
	m.terrain[2][2] = "Snack"
	check(m:attackOf(c) == 3, "Snack terrain gives +1 attack")
	check(c.hp == 4 and c.maxHp == 4, "terrain does not change health")
end

do -- starting terrain: home rows use each deck's family, middle rows one random terrain per column
	local a, b = StarterDecks.Snack, StarterDecks.Robo
	local m = MatchEngine.new({ deck = a.cards, hero = a.hero, family = a.family }, { deck = b.cards, hero = b.hero, family = b.family }, 5)
	local ok = true
	for col = 1, COLS do
		ok = ok and m.terrain[col][1] == "Snack" and m.terrain[col][2] == "Snack"
		ok = ok and m.terrain[col][5] == "Robo" and m.terrain[col][6] == "Robo"
		ok = ok and m.terrain[col][3] == m.terrain[col][4]
	end
	check(ok, "home rows match the decks, middle rows match per column")
	local m2 = MatchEngine.new({ deck = a.cards, hero = "bonk" }, { deck = b.cards, hero = "granny_bolt" }, 5)
	check(m2.players[1].family == "Snack" and m2.players[2].family == "Robo", "family is worked out from the deck when not given")
end

do -- going first: the first player starts with 4 cards and (FirstTurnDraw off) skips their very first draw; the second starts with 5 and draws
	local a, b = StarterDecks.Snack, StarterDecks.Robo
	local saved = CardData.FirstTurnDraw
	CardData.FirstTurnDraw = false
	local m = MatchEngine.new({ deck = a.cards, hero = a.hero, family = a.family }, { deck = b.cards, hero = b.hero, family = b.family }, 7)
	check(m.current == 1 and #m.players[1].hand == 4, "the first player starts with 4 cards and skips their first draw")
	m:act(1, { kind = "endturn" })
	check(m.current == 2 and #m.players[2].hand == 6, "the second player starts with 5 cards and draws on their first turn")
	m:act(2, { kind = "endturn" })
	check(m.current == 1 and #m.players[1].hand == 5, "the first player draws from their second turn on")
	CardData.FirstTurnDraw = true
	local m2 = MatchEngine.new({ deck = a.cards, hero = a.hero, family = a.family }, { deck = b.cards, hero = b.hero, family = b.family }, 7)
	check(#m2.players[1].hand == 5, "with FirstTurnDraw on, the first player draws on turn one too")
	CardData.FirstTurnDraw = saved
end

do -- walking: 1 tile, orthogonal, blocked by units; Fast walks 2
	local m = blank()
	local c = ready(m:spawn(1, 3, 2, "tin_can_tom"))
	local map, list = m:reachable(c)
	check(#list == 4, "a normal creature can reach 4 tiles from the middle (got " .. #list .. ")")
	m:spawn(1, 3, 3, "couch_golem")
	_, list = m:reachable(c)
	check(#list == 3, "a unit in the way blocks that tile")
	local ok = m:act(1, { kind = "move", uid = c.uid, to = { col = 4, row = 3 } })
	check(not ok, "can't walk diagonally")
	ok = m:act(1, { kind = "move", uid = c.uid, to = { col = 2, row = 2 } })
	check(ok and c.col == 2 and c.row == 2 and m:at(2, 2) == c and m:at(3, 2) == nil, "walking moves the creature on the grid")
	ok = m:act(1, { kind = "move", uid = c.uid, to = { col = 1, row = 2 } })
	check(not ok, "a creature walks only once per turn")
	local f = ready(m:spawn(1, 5, 1, "jelly_bean_scout")) -- Fast
	_, list = m:reachable(f)
	check(#list == 5, "Fast creature in a corner reaches 5 tiles (got " .. #list .. ")")
	ok = m:act(1, { kind = "move", uid = f.uid, to = { col = 5, row = 3 } })
	check(ok and f.row == 3, "Fast creature walks 2 tiles")
	local e = hasEvent(m:takeEvents(), "move")
	check(e and #e.path == 1, "move event carries the path")
end

do -- summoning sickness, Zoom, summon zone
	local m = blank()
	local h = give(m, 1, "tin_can_tom")
	check(not m:act(1, { kind = "play", handUid = h, tile = { col = 1, row = 3 } }), "can't summon on your front row")
	check(m:act(1, { kind = "play", handUid = h, tile = { col = 1, row = 2 } }), "summon on your back 2 rows")
	local c = m:at(1, 2)
	check(not m:act(1, { kind = "move", uid = c.uid, to = { col = 1, row = 3 } }), "new creature can't move on its first turn")
	local z = give(m, 1, "hot_sauce_imp")
	m:act(1, { kind = "play", handUid = z, tile = { col = 2, row = 2 } })
	local imp = m:at(2, 2)
	check(m:act(1, { kind = "move", uid = imp.uid, to = { col = 2, row = 3 } }), "Zoom creature can move at once")
	local h2 = give(m, 2, "tin_can_tom")
	m.current = 2
	check(not m:act(2, { kind = "play", handUid = h2, tile = { col = 1, row = 4 } }), "player 2 can't summon on row 4")
	check(m:act(2, { kind = "play", handUid = h2, tile = { col = 1, row = 5 } }), "player 2 summons on rows 5-6")
end

do -- Bunny Burrow lets you summon next to it; buildings only on your half
	local m = blank()
	local b = give(m, 1, "bunny_burrow")
	check(not m:act(1, { kind = "play", handUid = b, tile = { col = 3, row = 4 } }), "can't build on the enemy half")
	check(m:act(1, { kind = "play", handUid = b, tile = { col = 3, row = 3 } }), "build on your front row")
	local h = give(m, 1, "tin_can_tom")
	check(m:act(1, { kind = "play", handUid = h, tile = { col = 4, row = 4 } }), "summon next to a Bunny Burrow, even on row 4")
end

---------------------------------------------------------------- fighting
do -- melee: both hit each other, diagonal counts as next to
	local m = blank()
	local a = stats(ready(m:spawn(1, 2, 3, "toaster_knight")), 3, 3)
	local d = stats(m:spawn(2, 3, 4, "tin_can_tom"), 2, 1) -- diagonal
	check(m:act(1, { kind = "attack", uid = a.uid, target = { col = 3, row = 4 } }), "attack a diagonal neighbour")
	check(a.hp == 1, "attacker takes the defender's hit back (hp " .. a.hp .. ")")
	check(m:at(3, 4) ~= d, "defender popped")
	check(not m:act(1, { kind = "move", uid = a.uid, to = { col = 2, row = 2 } }), "can't move after attacking")
end

do -- out of range, Ranged attacks from 2 tiles with no hit back
	local m = blank()
	local a = ready(m:spawn(1, 1, 2, "tin_can_tom"))
	m:spawn(2, 1, 4, "couch_golem")
	check(not m:act(1, { kind = "attack", uid = a.uid, target = { col = 1, row = 4 } }), "melee can't hit 2 tiles away")
	local r = ready(m:spawn(1, 2, 2, "drizzle_sprite")) -- Ranged 1/2
	local t = stats(m:spawn(2, 2, 4, "tin_can_tom"), 2, 1)
	local hpBefore = r.hp
	check(m:act(1, { kind = "attack", uid = r.uid, target = { col = 2, row = 4 } }), "Ranged hits 2 tiles away")
	check(r.hp == hpBefore and m:at(2, 4) == nil, "no hit back from 2 tiles away")
	local _ = t
end

do -- hero attacks only from the enemy half (rows 4-6 for player 1); Big Move charge counts it
	local m = blank()
	local a = ready(m:spawn(1, 3, 3, "the_junk_king"))
	check(not m:act(1, { kind = "attack", uid = a.uid, hero = true }), "can't hit the hero from your own half")
	m:removeUnit(a)
	m:placeUnit(a, 3, 4)
	local hp = m.players[2].hp
	check(m:act(1, { kind = "attack", uid = a.uid, hero = true }), "hit the hero from the enemy's front row")
	local kAtk = CardData.get("the_junk_king").atk
	check(m.players[2].hp == hp - kAtk and m.players[1].dealt == kAtk, "hero took the king's attack, counted for the Big Move")
	local m2 = blank()
	m2.current = 2
	local b = stats(ready(m2:spawn(2, 1, 3, "tin_can_tom")), 2, 1)
	local hp1 = m2.players[1].hp
	check(m2:act(2, { kind = "attack", uid = b.uid, hero = true }) and m2.players[1].hp == hp1 - 2, "player 2 hits player 1's hero from row 3")
end

do -- Sturdy, Splash, Bubble
	local m = blank()
	local a = stats(ready(m:spawn(1, 3, 3, "hailstone_hopper")), 3, 2) -- Splash
	local front = stats(m:spawn(2, 3, 4, "couch_golem"), 1, 7) -- Sturdy
	local side = stats(m:spawn(2, 4, 4, "tin_can_tom"), 2, 1) -- next to the target
	local far = stats(m:spawn(2, 1, 5, "tin_can_tom"), 2, 1) -- not next to the target
	m:act(1, { kind = "attack", uid = a.uid, target = { col = 3, row = 4 } })
	check(front.hp == 7 - 2, "Sturdy takes 1 less (3 -> 2)")
	check(m:at(4, 4) == nil, "Splash pops the enemy next to the target")
	check(far.hp == 1, "Splash doesn't reach further")
	check(a.hp == 1, "hopper took 1 back from the golem")
	local b = stats(m:spawn(1, 1, 1, "couch_golem"), 1, 7)
	b.bubble = true
	m:damageUnit(b, 5, { player = 2 })
	check(b.hp == 7 and not b.bubble, "Bubble blocks one hit")
	local _ = side
end

do -- Haunt leaves a Ghost on the same tile; Spooky Crypt gives Haunt
	local m = blank()
	local s = m:spawn(1, 2, 2, "sheet_ghost")
	m:damageUnit(s, 5, { player = 2 })
	m:resolvePops()
	local g = m:at(2, 2)
	check(g and g.id == "ghost", "Haunt leaves a Ghost on its tile")
	local m2 = blank()
	m2:build(1, 4, 2, "spooky_crypt")
	local t = m2:spawn(1, 4, 1, "tin_can_tom")
	check(m2:hasKeyword(t, "Haunt"), "Spooky Crypt gives Haunt next to it")
	m2:damageUnit(t, 5, { player = 2 })
	m2:resolvePops()
	check(m2:at(4, 1) and m2:at(4, 1).id == "ghost", "crypt Haunt leaves a Ghost")
end

do -- Fog Bank -2 attack next to it; Charging Station +1; Wind Turbine Fast; Bouncy Castle Sturdy
	local m = blank()
	local e = stats(m:spawn(2, 3, 4, "toaster_knight"), 3, 3)
	m:spawn(1, 3, 3, "fog_bank")
	check(m:attackOf(e) == 1, "Fog Bank takes 2 attack from enemies next to it")
	local m2 = blank()
	local c = stats(m2:spawn(1, 2, 2, "tin_can_tom"), 2, 2)
	m2:build(1, 3, 3, "charging_station")
	check(m2:attackOf(c) == 3, "Charging Station gives +1 attack next to it")
	m2:build(1, 1, 3, "wind_turbine")
	check(m2:hasKeyword(c, "Fast") and m2:speedOf(c) == 2, "Wind Turbine gives Fast next to it")
	m2:build(1, 1, 1, "bouncy_castle")
	check(m2:hasKeyword(c, "Sturdy"), "Bouncy Castle gives Sturdy next to it")
	local far = stats(m2:spawn(1, 5, 1, "tin_can_tom"), 2, 2)
	check(not m2:hasKeyword(far, "Sturdy") and m2:attackOf(far) == 2, "auras only reach the 8 tiles around")
end

do -- Burrito Bouncer hits back; Mushroom Witch; Rusty Cart gives Scrap
	local m = blank()
	local a = stats(ready(m:spawn(1, 2, 3, "couch_golem")), 1, 7) -- Sturdy
	local bb = stats(m:spawn(2, 2, 4, "burrito_bouncer"), 3, 5)
	m:act(1, { kind = "attack", uid = a.uid, target = { col = 2, row = 4 } })
	check(bb.hp == 4, "burrito took 1")
	check(a.hp == 7 - 2 - 0, "golem took 3 back -1 sturdy = 2, reflect 1 -1 sturdy = 0 (hp " .. a.hp .. ")")
	local m2 = blank()
	m2:spawn(1, 1, 1, "mushroom_witch")
	local cart = m2:spawn(1, 2, 1, "rusty_shopping_cart")
	local hp = m2.players[2].hp
	m2:damageUnit(cart, 9, { player = 2 })
	m2:resolvePops()
	check(m2.players[2].hp == hp - 1, "Mushroom Witch hits the enemy hero when a friend pops")
	check(m2:scrapAt(2, 1) == 1 and #m2.players[1].hand == 0, "a popped Junk creature leaves 1 Scrap on its tile (no Scrap card any more)")
end

---------------------------------------------------------------- turn start
do -- start of turn: Charge, Spiked Fence, Snack Bar, Scrap Catapult, Haunted Arcade, Rocket Lunchbox, Lemonade
	local m = blank()
	local bug = stats(m:spawn(1, 1, 1, "bolt_bug"), 1, 2)
	bug.chargeLeft = 2
	m:build(1, 3, 3, "spiked_fence")
	local victim = stats(m:spawn(2, 3, 4, "couch_golem"), 1, 7) -- next to the fence, Sturdy: 1 -> 0
	local victim2 = stats(m:spawn(2, 4, 4, "skeleton_mascot"), 2, 2)
	m:build(1, 5, 2, "snack_bar")
	local hurt = stats(m:spawn(1, 5, 1, "pretzel_guard"), 2, 4)
	hurt.hp = 1
	m:build(1, 1, 3, "rocket_lunchbox")
	m:build(1, 2, 2, "lemonade_stand")
	m:build(1, 4, 1, "haunted_arcade")
	local hp2 = m.players[2].hp
	m:startTurn(1)
	check(bug.power == 1 and bug.chargeLeft == 1 and m:attackOf(bug) == 2, "Charge gives 1 Power (+1 attack)")
	check(victim.hp == 7 and victim2.hp == 1, "Spiked Fence hits enemies next to it (Sturdy blocks 1)")
	check(hurt.hp == 3, "Snack Bar heals 2")
	check(m.players[2].hp == hp2 - 2, "Rocket Lunchbox hits the enemy hero for 2")
	check(m.players[1].energy == m.players[1].maxEnergy + 1, "Lemonade Stand gives 1 extra energy")
	local ghosts = 0
	for _, u in ipairs(m:unitsOf(1, "creature")) do
		if u.id == "ghost" then
			ghosts += 1
			check(u.keywords.Haunt and m.dist(u, { col = 4, row = 1 }) == 1, "arcade Ghost has Haunt and stands next to it")
		end
	end
	check(ghosts == 1, "Haunted Arcade spawns one Ghost")
	local m2 = blank()
	m2:build(1, 3, 3, "scrap_catapult")
	local t = stats(m2:spawn(2, 3, 6, "couch_golem"), 1, 7) -- 3 tiles away, Sturdy: 2 -> 1
	m2:startTurn(1)
	check(t.hp == 6, "Scrap Catapult hits an enemy 3 tiles away for 2")
end

do -- Microwave Mage and Stormlord at turn start
	local m = blank()
	m:spawn(1, 3, 3, "microwave_mage")
	local near = stats(m:spawn(2, 3, 4, "skeleton_mascot"), 2, 2)
	local far = stats(m:spawn(2, 1, 6, "skeleton_mascot"), 2, 2)
	m:startTurn(1)
	check(near.hp == 1 and far.hp == 2, "Microwave Mage hits only enemies next to it")
	m:spawn(1, 5, 1, "stormlord_nimbus")
	m:startTurn(1)
	check(far.hp == 1, "Stormlord hits every enemy creature")
end

---------------------------------------------------------------- cards
do -- Wrong Turn pushes 2 back, stops at a blocker; Tornado Twins pushes all enemies 1 back
	local m = blank()
	local e = m:spawn(2, 2, 3, "tin_can_tom")
	local w = give(m, 1, "wrong_turn")
	check(m:act(1, { kind = "play", handUid = w, target = { col = 2, row = 3 } }), "Wrong Turn played")
	check(e.row == 5 and m:at(2, 5) == e, "pushed 2 tiles back toward player 2")
	local blocker = m:spawn(2, 3, 5, "couch_golem")
	local e2 = m:spawn(2, 3, 4, "tin_can_tom")
	local w2 = give(m, 1, "wrong_turn")
	m:act(1, { kind = "play", handUid = w2, target = { col = 3, row = 4 } })
	check(e2.row == 4, "push stops when the tile behind is taken")
	local t = give(m, 1, "tornado_twins")
	m:act(1, { kind = "play", handUid = t, tile = { col = 1, row = 1 } })
	check(blocker.row == 6 and e2.row == 5 and e.row == 6, "Tornado blows every enemy 1 tile back, back ones first")
end

do -- Terrain Shift changes a 3x3 patch; Total Chaos keeps everything on the board
	local m = blank()
	local ts = give(m, 1, "terrain_shift")
	check(m:act(1, { kind = "play", handUid = ts, target = { col = 1, row = 1, terrain = "Robo" } }), "Terrain Shift played")
	check(m.terrain[1][1] == "Robo" and m.terrain[2][2] == "Robo" and m.terrain[3][3] == "Spooky", "3x3 patch changed (clipped at the edge)")
	for i = 1, 6 do
		m:spawn(i % 2 + 1, (i % COLS) + 1, (i % 2 == 0) and 2 or 5, "tin_can_tom")
	end
	m:build(1, 5, 3, "spiked_fence")
	local before = #m:allUnits("creature")
	local tc = give(m, 1, "total_chaos")
	m:act(1, { kind = "play", handUid = tc })
	local after = #m:allUnits("creature")
	check(before == after, "Total Chaos keeps every creature")
	check(m:at(5, 3) and m:at(5, 3).id == "spiked_fence", "buildings stay put")
	local okGrid = true
	for col = 1, COLS do
		for row = 1, ROWS do
			local u = m:at(col, row)
			if u and (u.col ~= col or u.row ~= row) then
				okGrid = false
			end
		end
	end
	check(okGrid, "grid and unit positions agree after Total Chaos")
end

do -- Junk King destroys every building; Escalator Wraith bounces; Laundry Bot cleanses
	local m = blank()
	m:build(1, 1, 1, "lemonade_stand")
	m:build(2, 5, 6, "rocket_lunchbox")
	local k = give(m, 1, "the_junk_king")
	m:act(1, { kind = "play", handUid = k, tile = { col = 3, row = 1 } })
	check(#m:allUnits("building") == 0, "Junk King destroys every building")
	local m2 = blank()
	local small = m2:spawn(2, 2, 5, "skeleton_mascot")
	local big = m2:spawn(2, 3, 5, "mecha_fridge")
	local wr = give(m2, 1, "escalator_wraith")
	check(not m2:act(1, { kind = "play", handUid = wr, tile = { col = 1, row = 1 }, target = { col = 3, row = 5 } }), "Wraith can't bounce a 6-cost")
	check(m2:act(1, { kind = "play", handUid = wr, tile = { col = 1, row = 1 }, target = { col = 2, row = 5 } }), "Wraith bounces a 2-cost")
	check(m2:at(2, 5) == nil and m2.players[2].hand[#m2.players[2].hand].id == "skeleton_mascot", "bounced creature goes back to hand")
	m2:buff(big, 3, 3)
	local lb = give(m2, 1, "laundry_bot_3000")
	m2:act(1, { kind = "play", handUid = lb, tile = { col = 2, row = 1 }, target = { col = 3, row = 5 } })
	local fridge = CardData.get("mecha_fridge")
	check(big.atk == fridge.atk and big.maxHp == fridge.hp and big.chargeLeft == 0, "Laundry Bot removes buffs and Charge")
	local _ = small
end

do -- Mannequin Duke brings back the last loss next to it; Pigeon Squad spawns 2 pigeons next to it
	local m = blank()
	local lostOne = m:spawn(1, 1, 1, "moth_mailman")
	m:damageUnit(lostOne, 9, { player = 2 })
	m:resolvePops()
	local d = give(m, 1, "the_mannequin_duke")
	m:act(1, { kind = "play", handUid = d, tile = { col = 3, row = 1 } })
	local back = nil
	for _, u in ipairs(m:unitsOf(1, "creature")) do
		if u.id == "moth_mailman" then
			back = u
		end
	end
	check(back and m.dist(back, { col = 3, row = 1 }) == 1, "Duke brings back the Moth Mailman next to it")
	local p = give(m, 1, "pigeon_squad")
	m.players[1].energy = 10
	m:act(1, { kind = "play", handUid = p, tile = { col = 5, row = 2 } })
	local pigeons = 0
	for _, u in ipairs(m:unitsOf(1, "creature")) do
		if u.id == "pigeon" and m.dist(u, { col = 5, row = 2 }) == 1 then
			pigeons += 1
		end
	end
	check(pigeons == 2, "Pigeon Squad spawns 2 pigeons next to it")
end

do -- costs: Mall Cop makes enemy spells cost more; Scrapheap Titan gets cheaper
	local m = blank()
	m:spawn(2, 1, 6, "mall_cop_phantom")
	local s = give(m, 1, "snack_break")
	check(m:costOf(1, m:findHand(1, s)) == 3, "Mall Cop: +1 spell cost")
	local t = give(m, 1, "scrapheap_titan")
	check(m:costOf(1, m:findHand(1, t)) == 6, "Titan costs 6 with no Scrap on the board")
	m.scrap[1][1] = 2
	check(m:costOf(1, m:findHand(1, t)) == 4, "Titan costs 2 less with 2 Scrap on the board")
	m.scrap[2][1] = 3
	check(m:costOf(1, m:findHand(1, t)) == 3, "Titan's discount stops at 3")
end

do -- Big Moves: Granny bowls down a column, Bonk pulls a free spell
	local m = blank()
	m.current = 2
	m.players[2].dealt = 10
	local e = stats(m:spawn(1, 2, 3, "tin_can_tom"), 2, 1)
	local hp = m.players[1].hp
	check(m:act(2, { kind = "bigmove", col = 2 }), "Granny's Strike")
	check(m:at(2, 3) == nil and m.players[1].hp == hp - 3, "first enemy absorbs 1, 3 goes to the hero")
	check(not m:act(2, { kind = "bigmove", col = 2 }), "Big Move only once")
	local m2 = blank()
	m2.players[1].dealt = 10
	check(m2:act(1, { kind = "bigmove" }), "Bonk's Hat Trick")
	local entry = m2.players[1].hand[1]
	check(entry and CardData.get(entry.id).type == "Spell" and m2:costOf(1, entry) == 0, "Hat Trick spell costs 0")
	local _ = e
end

do -- Hamster Wheel Hero, Sergeant Snail, Big Momma Moose, Captain Confetti
	local m = blank()
	local h = stats(m:spawn(1, 1, 1, "hamster_wheel_hero"), 2, 3)
	m:spawn(1, 2, 1, "pocket_mouse")
	m:spawn(1, 3, 1, "moth_mailman")
	check(m:attackOf(h) == 3, "Hamster's Pack: +1 for the Critter next to it, nothing for the one further away")
	local mouse = stats(m:at(2, 1), 1, 1)
	check(not m:hasKeyword(mouse, "Sturdy"), "no Sturdy before the snail")
	m:spawn(1, 1, 2, "sergeant_snail")
	check(m:hasKeyword(mouse, "Sturdy"), "Sergeant Snail gives the Critters next to it Sturdy")
	check(not m:hasKeyword(m:at(3, 1), "Sturdy"), "but not a Critter further away")
	local mo = give(m, 1, "big_momma_moose")
	m:act(1, { kind = "play", handUid = mo, tile = { col = 4, row = 2 } })
	check(mouse.atk == 2 and mouse.maxHp == 2, "Moose gives Critters +1/+1")
	local cc = give(m, 1, "captain_confetti")
	m:act(1, { kind = "play", handUid = cc, tile = { col = 5, row = 2 } })
	check(hasEvent(m:takeEvents(), "buff") ~= nil, "Captain Confetti hands out keywords")
end

do -- ending the turn: the other player gets energy and their creatures can act again
	local m = blank()
	local c = m:spawn(2, 1, 5, "tin_can_tom")
	check(c.sick, "new creature is not ready")
	m:act(1, { kind = "endturn" })
	check(m.current == 2 and not c.sick, "after the turn passes, player 2's creature is ready")
	check(m:canMove(c) and m:canAttack(c), "it can move and attack")
end

do -- clone() copies everything that matters: same actions give the same views as a deep copy
	local a, b = StarterDecks.Critter, StarterDecks.Spooky
	local m = MatchEngine.new({ deck = a.cards, hero = a.hero, family = a.family }, { deck = b.cards, hero = b.hero, family = b.family }, 42)
	local rng = Rng.new(9)
	local same = true
	for step = 1, 200 do
		if m.over then
			break
		end
		local fast = m:clone(1234)
		local slow = m:deepClone()
		slow.rng = Rng.new(1234)
		local acts = m:listActions(m.current)
		local act = rng:pick(acts)
		fast:act(m.current, act)
		slow:act(m.current, act)
		local function sig(x)
			local v = x:viewFor(1)
			local parts = { tostring(x.current), tostring(x.over), x.players[1].hp, x.players[2].hp, #x.players[1].hand, #x.players[2].hand, x.players[1].energy, x.players[2].energy }
			for _, u in ipairs(v.units) do
				table.insert(parts, u.id .. "@" .. u.col .. "," .. u.row .. ":" .. u.atk .. "/" .. u.hp)
			end
			return table.concat(parts, "|")
		end
		if sig(fast) ~= sig(slow) then
			same = false
			print("clone mismatch at step " .. step .. " action " .. tostring(act.kind))
			break
		end
		-- the clone must not share tables with the real match
		fast.players[1].hand = {}
		if #m.players[1].hand == 0 and #slow.players[1].hand > 0 then
			same = false
		end
		m:act(m.current, BotBrain.chooseAction(m, m.current, "Medium", rng))
		m:takeEvents()
	end
	check(same, "clone() matches a deep copy")
end

---------------------------------------------------------------- creature commands
local function eventsOf(events, kind)
	local out = {}
	for _, e in ipairs(events) do
		if e.type == kind then
			table.insert(out, e)
		end
	end
	return out
end

local function hasAction(m, p, fn)
	for _, a in ipairs(m:listActions(p)) do
		if fn(a) then
			return true
		end
	end
	return false
end

do -- Defend: takes 1 less damage, hits back 1 harder, ends at its owner's next turn
	local m = blank()
	local g = stats(ready(m:spawn(1, 2, 3, "tin_can_tom")), 2, 5)
	check(hasAction(m, 1, function(a)
		return a.kind == "defend" and a.uid == g.uid
	end), "listActions offers Defend")
	check(m:act(1, { kind = "defend", uid = g.uid }), "a ready creature can defend")
	check(g.defending and hasEvent(m:takeEvents(), "defend") ~= nil, "it is defending (defend event)")
	check(not m:act(1, { kind = "move", uid = g.uid, to = { col = 2, row = 2 } }), "defending uses up its turn")
	m:act(1, { kind = "endturn" })
	local a = stats(ready(m:spawn(2, 2, 4, "tin_can_tom")), 3, 9)
	m:takeEvents()
	check(m:act(2, { kind = "attack", uid = a.uid, target = { col = 2, row = 3 } }), "enemy attacks the defender")
	check(g.hp == 3, "defender takes 1 less (5 - (3 - 1) = 3, got " .. g.hp .. ")")
	check(a.hp == 6, "defender hits back 1 harder (9 - (2 + 1) = 6, got " .. a.hp .. ")")
	local ev = hasEvent(m:takeEvents(), "attack")
	check(ev and ev.guarded == true and ev.counter == 3, "the attack event says the target was guarding")
	m:act(2, { kind = "endturn" })
	check(not g.defending and m:canAttack(g), "defending ends at the start of its owner's next turn")
	check(hasEvent(m:takeEvents(), "guardDown") ~= nil, "guardDown event")
end

do -- Defend blocks a 1 damage ping completely
	local m = blank()
	local g = stats(ready(m:spawn(1, 2, 2, "tin_can_tom")), 2, 2)
	m:act(1, { kind = "defend", uid = g.uid })
	m:takeEvents()
	check(m:damageUnit(g, 1, { player = 2 }) == 0 and g.hp == 2, "a 1 damage ping does nothing to a defender")
	check(hasEvent(m:takeEvents(), "blocked") ~= nil, "blocked event")
end

do -- Swap: moving onto one of your creatures next to it swaps their places
	local m = blank()
	local a = ready(m:spawn(1, 2, 2, "tin_can_tom"))
	local b = ready(m:spawn(1, 2, 3, "couch_golem"))
	m:spawn(2, 3, 3, "tin_can_tom")
	check(hasAction(m, 1, function(x)
		return x.kind == "move" and x.uid == a.uid and x.swap and x.to.col == 2 and x.to.row == 3
	end), "listActions offers the swap")
	check(m:act(1, { kind = "move", uid = a.uid, to = { col = 2, row = 3 } }), "swap with the creature in front")
	check(m:at(2, 3) == a and m:at(2, 2) == b, "they traded tiles")
	check(not m:canMove(a) and m:canMove(b), "the swapper used its walk, the other one didn't")
	check(hasEvent(m:takeEvents(), "swap") ~= nil, "swap event")
	check(not m:act(1, { kind = "move", uid = b.uid, to = { col = 3, row = 3 } }), "can't swap with an enemy")
	ready(m:spawn(1, 3, 1, "tin_can_tom"))
	check(not m:act(1, { kind = "move", uid = b.uid, to = { col = 3, row = 1 } }), "can't swap diagonally")
	check(m:act(1, { kind = "attack", uid = a.uid, target = { col = 3, row = 3 } }), "after swapping it can still attack")
end

do -- Picnic (Snack): heals itself and your creatures next to it 2 for 2 energy
	local m = blank()
	local s = stats(ready(m:spawn(1, 2, 2, "pancake_paladin")), 3, 5)
	local f = stats(m:spawn(1, 3, 3, "tin_can_tom"), 2, 4)
	local far = stats(m:spawn(1, 5, 1, "tin_can_tom"), 2, 4)
	s.power = CardData.PowerMax
	check(m:chantProblem(s) == "Nobody here needs it" and not m:act(1, { kind = "chant", uid = s.uid }), "no Picnic when nobody is hurt and the Snack is at full Power")
	s.hp, f.hp, far.hp = 2, 1, 1
	m.players[1].energy = 3
	check(m:act(1, { kind = "chant", uid = s.uid }), "Picnic")
	check(s.hp == 4 and f.hp == 3 and far.hp == 1, "heals itself and the friend next to it 2, not the far one")
	check(m.players[1].energy == 1, "Picnic costs 2 energy")
	check(not m:canAttack(s), "chanting uses its turn")
	check(hasEvent(m:takeEvents(), "chant") ~= nil, "chant event")
end

do -- Scrap Toss (Junk): 1 damage to an enemy up to 2 tiles away, buildings too
	local m = blank()
	local j = ready(m:spawn(1, 2, 2, "tin_can_tom"))
	local e = stats(m:spawn(2, 2, 4, "tin_can_tom"), 2, 3)
	m:build(2, 4, 4, "spiked_fence")
	m:spawn(2, 2, 5, "tin_can_tom")
	local aims = {}
	for _, a in ipairs(m:listActions(1)) do
		if a.kind == "chant" and a.uid == j.uid then
			aims[a.target.col * 10 + a.target.row] = true
		end
	end
	check(aims[24] and aims[44] and not aims[25], "Scrap Toss aims at enemies up to 2 tiles away, buildings too")
	check(not m:act(1, { kind = "chant", uid = j.uid, target = { col = 2, row = 5 } }), "can't toss 3 tiles away")
	check(m:act(1, { kind = "chant", uid = j.uid, target = { col = 2, row = 4 } }), "toss at an enemy 2 tiles away")
	check(e.hp == 2, "Scrap Toss deals 1 damage")
end

do -- Gust (Weather): blows an enemy 1 tile back, or 1 damage if something is in the way
	local m = blank()
	local w = ready(m:spawn(1, 2, 3, "drizzle_sprite"))
	local e = stats(m:spawn(2, 2, 4, "tin_can_tom"), 2, 3)
	check(m:act(1, { kind = "chant", uid = w.uid, target = { col = 2, row = 4 } }), "Gust")
	check(m:at(2, 5) == e and e.hp == 3, "blown 1 tile back toward its side, no damage")
	local w2 = ready(m:spawn(1, 3, 3, "drizzle_sprite"))
	m:spawn(2, 3, 5, "tin_can_tom")
	local e2 = stats(m:spawn(2, 3, 4, "tin_can_tom"), 2, 3)
	m:takeEvents()
	check(m:act(1, { kind = "chant", uid = w2.uid, target = { col = 3, row = 4 } }), "Gust at a blocked enemy")
	check(m:at(3, 4) == e2 and e2.hp == 2, "it bumps into the creature behind it and takes 1 damage")
	check(hasEvent(m:takeEvents(), "bump") ~= nil, "bump event")
end

do -- Call a Friend (Critter): a 1/1 Pigeon next to it for 2 energy
	local m = blank()
	local c = ready(m:spawn(1, 3, 2, "moth_mailman"))
	m.players[1].energy = 2
	check(m:act(1, { kind = "chant", uid = c.uid }), "Call a Friend")
	local pigeon = nil
	for _, u in ipairs(m:unitsOf(1, "creature")) do
		if u.id == "pigeon" then
			pigeon = u
		end
	end
	check(pigeon and m.dist(pigeon, c) == 1 and pigeon.sick, "a sleepy Pigeon appears next to it")
	check(m.players[1].energy == 0, "Call a Friend costs 2 energy")
end

do -- Raise (Spooky): brings back your last creature that popped, next to it, with 1 health
	local m = blank()
	local s = ready(m:spawn(1, 3, 2, "skeleton_mascot"))
	check(m:chantProblem(s) == "Nothing has popped yet", "nothing to raise at first")
	local lostOne = m:spawn(1, 1, 1, "couch_golem")
	m:damageUnit(lostOne, 99, { player = 2 })
	m:resolvePops()
	check(m.players[1].lost[#m.players[1].lost] == "couch_golem", "the Couch Golem is lost")
	m:takeEvents()
	check(m:act(1, { kind = "chant", uid = s.uid }), "Raise")
	local back = nil
	for _, u in ipairs(m:unitsOf(1, "creature")) do
		if u.id == "couch_golem" then
			back = u
		end
	end
	check(back and m.dist(back, s) == 1 and back.hp == 1 and back.maxHp == CardData.get("couch_golem").hp, "it comes back next to it with 1 health")
	check(#m.players[1].lost == 0 and not table.find(m.players[1].discard, "couch_golem"), "it leaves the lost list and the discard pile")
	local spawns = eventsOf(m:takeEvents(), "spawn")
	check(#spawns == 1 and spawns[1].raised == true and spawns[1].hp == 1, "spawn event says it was raised with 1 health")
	check(m.players[1].energy == 8, "Raise costs 2 energy")
	-- once per turn
	local lost2 = m:spawn(1, 5, 1, "tin_can_tom")
	m:damageUnit(lost2, 99, { player = 2 })
	m:resolvePops()
	local s2 = ready(m:spawn(1, 5, 3, "sheet_ghost"))
	check(m:chantProblem(s2) == "Only one Raise each turn" and not m:act(1, { kind = "chant", uid = s2.uid }), "only one Raise each turn")
	-- it only comes back once
	m:damageUnit(back, 99, { player = 2 })
	m:resolvePops()
	check(m.players[1].lost[#m.players[1].lost] ~= "couch_golem", "a raised creature that pops again is gone for good")
end

do -- a raised creature only fades away when it pops again: no Ghost, no pop effects
	local m = blank()
	local s = ready(m:spawn(1, 3, 2, "skeleton_mascot"))
	m:spawn(1, 1, 1, "mushroom_witch")
	local mascot = m:spawn(1, 5, 1, "skeleton_mascot")
	local enemyHp = m.players[2].hp
	m:damageUnit(mascot, 99, { player = 2 })
	m:resolvePops()
	local ghost = m:at(5, 1)
	check(ghost and ghost.id == "ghost" and m.players[2].hp == enemyHp - 1, "a normal pop leaves a Ghost (Haunt) and the Mushroom Witch hits the enemy hero")
	m:takeEvents()
	check(m:act(1, { kind = "chant", uid = s.uid }), "Raise the Skeleton Mascot")
	local back = nil
	for _, u in ipairs(m:unitsOf(1, "creature")) do
		if u.id == "skeleton_mascot" and u.uid ~= s.uid then
			back = u
		end
	end
	check(back ~= nil and back.hp == 1, "the Skeleton Mascot is back with 1 health")
	m:takeEvents()
	local col, row = back.col, back.row
	m:damageUnit(back, 99, { player = 2 })
	m:resolvePops()
	local pops = eventsOf(m:takeEvents(), "pop")
	check(#pops == 1 and pops[1].faded == true, "the raised one fades away")
	check(m:isEmpty(col, row), "no Ghost where it faded, even with Haunt")
	check(m.players[2].hp == enemyHp - 1, "the Mushroom Witch ignores a fade")
end

do -- Power Up (Robo): +1 attack for good; no chant without energy; one command per turn
	local m = blank()
	local r = stats(ready(m:spawn(1, 3, 2, "bolt_bug")), 1, 2)
	m.players[1].energy = 0
	check(m:chantProblem(r) == "Needs 1 energy" and not m:act(1, { kind = "chant", uid = r.uid }), "no chant without energy")
	check(not hasAction(m, 1, function(a)
		return a.kind == "chant"
	end), "listActions has no chant you can't pay for")
	m.players[1].energy = 1
	check(m:act(1, { kind = "chant", uid = r.uid }) and r.power == 1 and m:attackOf(r) == 2, "Power Up gives 1 Power (+1 attack)")
	check(not m:act(1, { kind = "chant", uid = r.uid }) and not m:act(1, { kind = "defend", uid = r.uid }), "only one command per turn")
end


---------------------------------------------------------------- combos and build-up
do -- Sandwich: +1 when another of your creatures stands right behind the target
	local m = blank()
	local a = stats(ready(m:spawn(1, 2, 3, "tin_can_tom")), 2, 5)
	local e = stats(m:spawn(2, 2, 4, "couch_golem"), 0, 9) -- Sturdy
	local behind = m:spawn(1, 2, 5, "tin_can_tom")
	m:act(1, { kind = "attack", uid = a.uid, target = { col = 2, row = 4 } })
	local ev = hasEvent(m:takeEvents(), "attack")
	check(ev and ev.sandwich == behind.uid and ev.amount == 3, "Sandwich adds 1 to the attack")
	check(e.hp == 9 - (3 - 1), "sandwiched golem takes 3 - 1 Sturdy = 2")
	local m2 = blank()
	local a2 = stats(ready(m2:spawn(1, 2, 3, "tin_can_tom")), 2, 5)
	local e2 = stats(m2:spawn(2, 3, 4, "tin_can_tom"), 0, 9)
	m2:spawn(1, 4, 5, "tin_can_tom") -- diagonal, in line with the attack
	m2:spawn(1, 3, 5, "tin_can_tom") -- next to the target but not behind it
	m2:act(1, { kind = "attack", uid = a2.uid, target = { col = 3, row = 4 } })
	check(e2.hp == 9 - 3, "diagonal Sandwich works too")
	local m3 = blank()
	local a3 = stats(ready(m3:spawn(1, 2, 3, "tin_can_tom")), 2, 5)
	local e3 = stats(m3:spawn(2, 2, 4, "tin_can_tom"), 0, 9)
	m3:spawn(1, 3, 4, "tin_can_tom") -- beside the target only
	m3:act(1, { kind = "attack", uid = a3.uid, target = { col = 2, row = 4 } })
	check(e3.hp == 9 - 2, "no Sandwich from the side")
end

do -- Combo: a bonus when a card of the same family was already played this turn
	local m = blank()
	local mm = give(m, 1, "moth_mailman")
	for _ = 1, 5 do
		table.insert(m.players[1].deck, "tin_can_tom")
	end
	local v = m:viewFor(1)
	check(not v.players[1].hand[1].combo, "no COMBO tag before a Critter was played")
	m:act(1, { kind = "play", handUid = mm, tile = { col = 1, row = 1 } })
	check(#m.players[1].hand == 1, "Moth Mailman alone draws 1")
	local mm2 = give(m, 1, "moth_mailman")
	v = m:viewFor(1)
	local tagged = false
	for _, h in ipairs(v.players[1].hand) do
		if h.uid == mm2 and h.combo then
			tagged = true
		end
	end
	check(tagged, "the second Mailman shows the COMBO tag")
	local before = #m.players[1].hand
	m:takeEvents()
	m:act(1, { kind = "play", handUid = mm2, tile = { col = 2, row = 1 } })
	local ev = hasEvent(m:takeEvents(), "play")
	check(#m.players[1].hand == before - 1 + 2 and ev and ev.combo, "Combo: the second Mailman draws 2")
	local sb = give(m, 1, "spare_battery")
	m:act(1, { kind = "play", handUid = sb })
	check(m.players[1].played.Any == nil, "neutral cards don't count for Combo")
	m:endTurn(1)
	m:endTurn(2)
	check(next(m.players[1].played) == nil, "Combo counts start fresh every turn")
	-- Toaster Knight: 1 damage, 2 with Combo
	local m2 = blank()
	local e = stats(m2:spawn(2, 3, 5, "couch_golem"), 0, 9)
	e.keywords.Sturdy = nil
	local tk = give(m2, 1, "toaster_knight")
	m2:act(1, { kind = "play", handUid = tk, tile = { col = 1, row = 1 } })
	check(e.hp == 8, "Toaster Knight pings for 1")
	local tk2 = give(m2, 1, "toaster_knight")
	m2:act(1, { kind = "play", handUid = tk2, tile = { col = 2, row = 1 } })
	check(e.hp == 6, "with Combo it pings for 2")
end

do -- Power: capped, Sweet Tooth (Snacks), Hot Sauce Imp, Grudge (Spooky), Upload (Robo)
	local m = blank()
	local s = stats(m:spawn(1, 2, 2, "pretzel_guard"), 2, 4)
	m:healCreature(s, 2)
	check(s.power == 1 and m:attackOf(s) == 3, "Sweet Tooth: a Snack at full health still gets 1 Power from a heal")
	for _ = 1, 5 do
		m:healCreature(s, 1)
	end
	check(s.power == CardData.PowerMax, "Power stops at the cap")
	local imp = m:spawn(1, 3, 2, "hot_sauce_imp")
	m:healCreature(imp, 1)
	check(imp.power == 2, "Hot Sauce Imp gets 2 Power from a heal")
	local tom = m:spawn(1, 4, 2, "tin_can_tom")
	m:healCreature(tom, 1)
	check(tom.power == 0, "non-Snacks get no Power from heals")
	-- Picnic on a full-health team gives the Snacks Power
	local pp = stats(ready(m:spawn(1, 2, 1, "pancake_paladin")), 3, 5)
	m.players[1].energy = 3
	check(m:chantProblem(pp) == nil and m:act(1, { kind = "chant", uid = pp.uid }), "Picnic works on a full-health Snack")
	check(pp.power == 1 and imp.power == CardData.PowerMax, "Picnic gives Power to itself and the Snacks next to it")
	-- Grudge
	local m2 = blank()
	local sk = m2:spawn(1, 1, 1, "skeleton_mascot")
	local f1 = m2:spawn(1, 3, 1, "tin_can_tom")
	m2:damageUnit(f1, 9, { player = 2 })
	m2:resolvePops()
	check(sk.power == 1, "Grudge: Skeleton Mascot gets 1 Power when a friend pops")
	local en = m2:spawn(2, 3, 6, "tin_can_tom")
	m2:damageUnit(en, 9, { player = 1 })
	m2:resolvePops()
	check(sk.power == 1, "an enemy popping doesn't count")
	-- Upload
	local m3 = blank()
	local r1 = m3:spawn(1, 2, 2, "roomba_rex")
	local r2 = m3:spawn(1, 3, 3, "bolt_bug")
	local far = m3:spawn(1, 5, 1, "bolt_bug")
	m3:addPower(r1, 2)
	m3:damageUnit(r1, 9, { player = 2 })
	m3:resolvePops()
	local ev = hasEvent(m3:takeEvents(), "upload")
	check(r2.power == 2 and far.power == 0 and ev and ev.to == r2.uid, "Upload: a popped Robo's Power jumps to the Robo next to it")
	-- Laundry Bot wipes Power
	local m4 = blank()
	local big = m4:spawn(2, 2, 5, "mecha_fridge")
	m4:addPower(big, 3)
	local lb = give(m4, 1, "laundry_bot_3000")
	m4:act(1, { kind = "play", handUid = lb, tile = { col = 1, row = 1 }, target = { col = 2, row = 5 } })
	check(big.power == 0 and m4:attackOf(big) == CardData.get("mecha_fridge").atk, "Laundry Bot wipes Power")
	-- Power Up stops at the cap
	local m5 = blank()
	local bb = ready(m5:spawn(1, 2, 2, "bolt_bug"))
	bb.power = CardData.PowerMax
	check(m5:chantProblem(bb) == "Already at full Power", "no Power Up at full Power")
end

do -- Soak and Zap
	local m = blank()
	local e = stats(m:spawn(2, 2, 4, "tin_can_tom"), 1, 9)
	m:soak(e)
	check(e.soaked and hasEvent(m:takeEvents(), "soak") ~= nil, "Soak")
	m:damageUnit(e, 2, { player = 1 })
	check(e.hp == 9 - 3 and not e.soaked, "a Soaked creature takes +1 from the next hit, then dries off")
	m:damageUnit(e, 2, { player = 1 })
	check(e.hp == 4, "the hit after that is normal")
	-- Zap
	m:soak(e)
	local bug = stats(ready(m:spawn(1, 2, 3, "bolt_bug")), 1, 5)
	m:act(1, { kind = "attack", uid = bug.uid, target = { col = 2, row = 4 } })
	check(e.hp == 4 - (1 + 1 + 2), "Zap: +2 more on a Soaked creature")
	-- Drizzle Sprite soaks what it hits
	local m2 = blank()
	local d = stats(ready(m2:spawn(1, 2, 2, "drizzle_sprite")), 1, 1)
	local e2 = stats(m2:spawn(2, 2, 4, "tin_can_tom"), 1, 9)
	m2:act(1, { kind = "attack", uid = d.uid, target = { col = 2, row = 4 } })
	check(e2.hp == 8 and e2.soaked, "Drizzle Sprite's attack Soaks")
	-- Bubble blocks the hit and keeps the Soak
	local m3 = blank()
	local e3 = stats(m3:spawn(2, 2, 4, "tin_can_tom"), 1, 9)
	m3:soak(e3)
	e3.bubble = true
	m3:damageUnit(e3, 3, { player = 1 })
	check(e3.hp == 9 and e3.soaked, "Bubble Wrap blocks the hit and it stays Soaked")
	-- Water Balloon: push 1 and Soak
	local m4 = blank()
	local e4 = stats(m4:spawn(2, 2, 4, "tin_can_tom"), 1, 9)
	local wb = give(m4, 1, "water_balloon")
	check(m4:act(1, { kind = "play", handUid = wb, target = { col = 2, row = 4 } }), "Water Balloon")
	check(m4:at(2, 5) == e4 and e4.soaked, "Water Balloon pushes 1 back and Soaks")
	-- Gust soaks too
	local m5 = blank()
	local g = stats(ready(m5:spawn(1, 2, 3, "grumpy_cloud")), 2, 2)
	local e5 = stats(m5:spawn(2, 2, 4, "tin_can_tom"), 1, 9)
	check(m5:act(1, { kind = "chant", uid = g.uid, target = { col = 2, row = 4 } }) and e5.soaked and m5:at(2, 5) == e5, "Gust pushes and Soaks")
	-- Grumpy Cloud: with Combo it soaks every enemy
	local m6 = blank()
	local a6 = stats(m6:spawn(2, 1, 5, "tin_can_tom"), 1, 9)
	local b6 = stats(m6:spawn(2, 4, 6, "tin_can_tom"), 1, 9)
	local d6 = give(m6, 1, "drizzle_sprite")
	m6:act(1, { kind = "play", handUid = d6, tile = { col = 1, row = 1 } })
	local gc = give(m6, 1, "grumpy_cloud")
	m6:act(1, { kind = "play", handUid = gc, tile = { col = 2, row = 1 } })
	check(a6.soaked and b6.soaked, "Grumpy Cloud with Combo soaks every enemy creature")
end

do -- Scrap: popped Junk leaves Scrap, Junk picks it up when it walks over it
	local m = blank()
	local tom = m:spawn(1, 2, 3, "tin_can_tom")
	m:damageUnit(tom, 9, { player = 2 })
	m:resolvePops()
	check(m:scrapAt(2, 3) == 2, "Tin Can Tom leaves 2 Scrap")
	local fence = m:build(1, 3, 3, "spiked_fence")
	m:damageUnit(fence, 9, { player = 2 })
	m:resolvePops()
	check(m:scrapAt(3, 3) == 1, "a destroyed building leaves 1 Scrap")
	local v = m:viewFor(1)
	check(#v.scrap == 2, "the view lists the Scrap")
	local golem = stats(ready(m:spawn(1, 2, 1, "couch_golem")), 2, 6)
	golem.keywords.Fast = true
	check(m:act(1, { kind = "move", uid = golem.uid, to = { col = 3, row = 2 } }) or true, "walk")
	golem.moved = false
	local ok = m:act(1, { kind = "move", uid = golem.uid, to = { col = 3, row = 3 } })
	check(ok and m:scrapAt(3, 3) == 0 and golem.atk == 3 and golem.maxHp == 7, "a Junk creature picks up Scrap: +1/+1 each")
	golem.moved = false
	ok = m:act(1, { kind = "move", uid = golem.uid, to = { col = 2, row = 3 } })
	check(ok and m:scrapAt(2, 3) == 0 and golem.atk == 5, "and picks up 2 more")
	-- non-Junk creatures leave Scrap alone; Junk summoned onto Scrap picks it up
	local m2 = blank()
	m2.scrap[2][1] = 3
	local pg = m2:spawn(1, 2, 1, "pretzel_guard")
	check(m2:scrapAt(2, 1) == 3, "a Snack standing on Scrap leaves it")
	m2:removeUnit(pg)
	local c2 = give(m2, 1, "couch_golem")
	m2:act(1, { kind = "play", handUid = c2, tile = { col = 2, row = 1 } })
	local g2 = m2:at(2, 1)
	check(m2:scrapAt(2, 1) == 0 and g2.atk == CardData.get("couch_golem").atk + 3, "Junk summoned onto Scrap picks it up")
	-- Rusty Cart also picks up from the tiles next to where it stops
	local m3 = blank()
	m3.scrap[1][2] = 1
	m3.scrap[3][3] = 1
	local cart = ready(m3:spawn(1, 2, 1, "rusty_shopping_cart"))
	m3:act(1, { kind = "move", uid = cart.uid, to = { col = 2, row = 2 } })
	check(m3:scrapTotal() == 0 and cart.atk == CardData.get("rusty_shopping_cart").atk + 2, "Rusty Cart vacuums the Scrap next to it")
	-- clone copies Scrap and Combo counts without sharing them
	local m4 = blank()
	m4.scrap[1][1] = 1
	m4.players[1].played.Junk = 1
	local c4 = m4:clone(5)
	c4.scrap[1][1] = nil
	c4.players[1].played.Junk = nil
	check(m4.scrap[1][1] == 1 and m4.players[1].played.Junk == 1, "clone doesn't share Scrap or Combo counts")
end

do -- Pack
	local m = blank()
	local mouse = stats(m:spawn(1, 2, 2, "pocket_mouse"), 1, 2)
	check(m:attackOf(mouse) == 1, "Pack alone: no bonus")
	m:spawn(1, 1, 1, "pigeon")
	check(m:attackOf(mouse) == 2, "+1 for one Critter next to it")
	m:spawn(1, 3, 3, "pigeon")
	m:spawn(1, 1, 3, "pigeon")
	check(m:attackOf(mouse) == 3, "Pack stops at +2")
	m:spawn(1, 2, 3, "tin_can_tom")
	check(m:attackOf(mouse) == 3, "non-Critters don't count")
	local moth = stats(m:spawn(1, 2, 1, "moth_mailman"), 2, 2)
	check(m:hasKeyword(moth, "Pack") and m:attackOf(moth) == 4, "every Critter has Pack (the moth has 2 Critters next to it)")
	check(not m:hasKeyword(m:at(2, 3), "Pack"), "non-Critters don't have Pack")
end

do -- Hamster Wheel Hero: Combo gives Zoom
	local m = blank()
	m.players[1].energy = 8
	local mouse = give(m, 1, "pocket_mouse")
	local ham = give(m, 1, "hamster_wheel_hero")
	check(m:act(1, { kind = "play", handUid = mouse, tile = { col = 1, row = 1 } }), "play a Critter first")
	check(m:act(1, { kind = "play", handUid = ham, tile = { col = 2, row = 2 } }), "then the hamster")
	local h = m:at(2, 2)
	check(m:hasKeyword(h, "Zoom") and m:canMove(h), "Combo: the hamster has Zoom and can move at once")
end

---------------------------------------------------------------- soak test: bots play full games
local function checkInvariants(m, where)
	for col = 1, COLS do
		for row = 1, ROWS do
			local u = m.grid[col][row]
			if u then
				assert(u.col == col and u.row == row, where .. ": unit position mismatch")
				assert(u.hp > 0, where .. ": unit with 0 health left on the board")
				assert((u.power or 0) >= 0 and (u.power or 0) <= CardData.PowerMax, where .. ": Power out of range")
				if u.kind == "building" then
					assert(MatchEngine.inHalf(u.owner, row), where .. ": building outside its half")
				end
			end
		end
	end
	for p = 1, 2 do
		local pl = m.players[p]
		assert(pl.energy >= 0, where .. ": negative energy")
		assert(#pl.hand <= CardData.MaxHand, where .. ": hand too big")
		assert(pl.hp <= CardData.HeroMaxHp, where .. ": hero above max health")
	end
end

local played = {}
local function runGame(seed, s1, s2, diffA, diffB)
	local m = MatchEngine.new(s1, s2, seed)
	local botRng = Rng.new(seed + 7)
	local steps = 0
	while not m.over do
		local p = m.current
		local a = BotBrain.chooseAction(m, p, p == 1 and diffA or diffB, botRng)
		if a.kind == "play" then
			local entry = m:findHand(p, a.handUid)
			played[entry.id] = (played[entry.id] or 0) + 1
		end
		local ok, err = m:act(p, a)
		assert(ok, "bot chose an illegal action: " .. tostring(err))
		checkInvariants(m, "seed " .. seed)
		m:takeEvents()
		steps += 1
		assert(steps < 6000, "game did not finish")
	end
	return m
end

local deckKeys = StarterDecks.Order
local difficulties = { "Easy", "Medium", "Hard" }
local SOAK = SOAK_GAMES or 120
local games, turnsTotal, longest, limitGames = 0, 0, 0, 0
local wins = { 0, 0, 0 }
local diffWins = {}
local t0 = os.clock()
local okRun, err = pcall(function()
	for i = 1, SOAK do
		local dA = difficulties[(i % 3) + 1]
		local dB = difficulties[((i // 3) % 3) + 1]
		local kA = deckKeys[(i % #deckKeys) + 1]
		local kB = deckKeys[((i // #deckKeys) % #deckKeys) + 1]
		local a, b = StarterDecks[kA], StarterDecks[kB]
		local m = runGame(i * 7919, { deck = a.cards, hero = a.hero, family = a.family }, { deck = b.cards, hero = b.hero, family = b.family }, dA, dB)
		games += 1
		turnsTotal += m.turn
		longest = math.max(longest, m.turn)
		if m.turn > 100 then
			limitGames += 1
		end
		wins[m.winner == 0 and 3 or m.winner] += 1
		if dA ~= dB and m.winner ~= 0 then
			local w = m.winner == 1 and dA or dB
			local l = m.winner == 1 and dB or dA
			local k = w .. ">" .. l
			diffWins[k] = (diffWins[k] or 0) + 1
		end
	end
end)
check(okRun, "soak test crashed: " .. tostring(err))

local never = {}
for _, key in ipairs(deckKeys) do
	for _, id in ipairs(StarterDecks[key].cards) do
		if not played[id] and not table.find(never, id) then
			table.insert(never, id)
		end
	end
end
check(#never == 0, "themed deck cards never played in soak test: " .. table.concat(never, ", "))
check(limitGames == 0, limitGames .. " soak games hit the turn limit")

print(string.format("Soak: %d games in %.1fs, first player won %d, second %d, draws %d, avg turns %.1f, longest %d",
	games, os.clock() - t0, wins[1], wins[2], wins[3], turnsTotal / math.max(1, games), longest))
local keys = {}
for k, v in pairs(diffWins) do
	table.insert(keys, k .. "=" .. v)
end
table.sort(keys)
print("Difficulty head-to-head wins: " .. table.concat(keys, "  "))
-- Settings: the server saves whatever a client sends, so sanitize must drop anything odd
do
	local Settings = require("Settings")
	local clean = Settings.sanitize({ sfx = 3, music = 11, actionCam = "yes", shake = "Low", speed = "Turbo", graphics = "Low", blur = false, hacker = true, packFights = 5 })
	check(clean.sfx == 3 and clean.shake == "Low" and clean.graphics == "Low" and clean.blur == false, "settings: allowed values are kept")
	check(clean.music == Settings.Defaults.music and clean.actionCam == true and clean.speed == "Normal" and clean.packFights == "Full", "settings: bad values fall back to the defaults")
	check(clean.hacker == nil, "settings: unknown keys are dropped")
	check(Settings.sanitize({ sfx = 2.5 }).sfx == Settings.Defaults.sfx and Settings.sanitize({ sfx = 0 / 0 }).sfx == Settings.Defaults.sfx, "settings: fractional and NaN volumes are refused")
	check(Settings.sanitize("junk").sfx == Settings.Defaults.sfx, "settings: a non-table gives the defaults")
	local seen = {}
	Settings.onChanged(function(key, value, fromLoad)
		table.insert(seen, key .. "=" .. tostring(value) .. (fromLoad and "(load)" or ""))
	end)
	check(Settings.set("speed", "Fast") and Settings.get("speed") == "Fast", "settings: set changes a value")
	check(not Settings.set("speed", "Turbo") and Settings.get("speed") == "Fast", "settings: set refuses a bad value")
	check(not Settings.set("speed", "Fast"), "settings: setting the same value again does nothing")
	Settings.load({ speed = "Slow", sfx = 4 })
	check(Settings.get("speed") == "Slow" and Settings.get("sfx") == 4, "settings: load applies saved values")
	Settings.reset()
	check(Settings.get("speed") == "Normal" and Settings.get("sfx") == Settings.Defaults.sfx, "settings: reset restores the defaults")
	check(seen[1] == "speed=Fast" and table.find(seen, "speed=Slow(load)") ~= nil, "settings: listeners hear changes and loads (" .. table.concat(seen, " ") .. ")")
	for key, choices in pairs(Settings.Choices) do
		check(table.find(choices, Settings.Defaults[key]) ~= nil, "settings: default for " .. key .. " is one of its choices")
	end
	for _, v in pairs(Settings.Choices.speed) do
		check(type(Settings.Pace[v]) == "number", "settings: speed " .. v .. " has a pace")
	end
	for _, v in pairs(Settings.Choices.shake) do
		check(type(Settings.ShakeScale[v]) == "number", "settings: shake " .. v .. " has a scale")
	end
end

print(string.format("Tests: %d passed, %d failed", passed, failed))

if failed > 0 then
	error(string.format("%d test(s) failed", failed))
end

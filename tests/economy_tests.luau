-- Headless tests for the economy: session-locked saving (ProfileStore), Gems/Coins spending,
-- daily login, the Shop, match rewards, Luck/XP boosters and Robux receipts.
-- Run with: luaurun tests/economy_tests.luau src/econ src/shared src/packbrawl

-- Roblox globals the server modules use (a fake clock instead of real waiting)
local now = 1_800_000_000 -- a Unix time
local warnings = {}
_G.warn = function(...)
	local parts = {}
	for _, v in ipairs({ ... }) do
		table.insert(parts, tostring(v))
	end
	table.insert(warnings, table.concat(parts, " "))
end
_G.task = {
	spawn = function(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			error(err)
		end
	end,
	wait = function(t)
		now += t or 0
	end,
}
local function clock()
	return now
end
local function fakeWait(t)
	now += t or 0
end

local ProfileStore = require("ProfileStore")
local EconomyManager = require("EconomyManager")
local ShopCatalog = require("ShopCatalog")
local CardData = require("CardData")
local PullRates = require("PullRates")

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
-- ProfileStore: session locks
---------------------------------------------------------------------------
do
	local backend = ProfileStore.memoryStore()
	local template = { coins = 10, inv = {}, nested = { a = 1 } }
	local function server(job)
		return ProfileStore.new(backend, { template = template, jobId = job, clock = clock, wait = fakeWait, warn = _G.warn, loadAttempts = 3, retryDelay = 4 })
	end
	local A, B, C = server("A"), server("B"), server("C")

	local pa = A:load("u1")
	check(pa ~= nil and pa.Data.coins == 10, "new save starts from the template")
	check(pa.Meta.loads == 1, "first load counted")
	pa.Data.coins = 50
	check(pa:save() == true, "save works while holding the lock")

	local t0 = now
	local pb, why = B:load("u1")
	check(pb == nil and why == "locked", "another server can't load a locked save (" .. tostring(why) .. ")")
	check(now - t0 >= 8, "it retried before giving up")
	check(backend.data.u1.meta.lock.job == "A", "the failed load didn't take the lock")

	check(pa:release() == true, "release works")
	check(backend.data.u1.meta.lock == nil, "release clears the lock")
	pb = B:load("u1")
	check(pb ~= nil and pb.Data.coins == 50, "after release the next server sees the saved coins")
	check(pb.Meta.loads == 2, "second load counted")

	-- B crashes (never releases). C waits out the stale time and takes over.
	pb.Data.coins = 70
	pb:save()
	now += ProfileStore.StaleSeconds + 5
	local stolen = false
	pb:onStolen(function()
		stolen = true
	end)
	local pc = C:load("u1")
	check(pc ~= nil and pc.Data.coins == 70, "a stale lock (crashed server) is taken over")
	pb.Data.coins = 999999
	local ok, reason = pb:save()
	check(ok == false and reason == "stolen", "the old server can't write after the takeover (" .. tostring(reason) .. ")")
	check(stolen, "the old server is told its profile was stolen")
	check(not pb:isActive(), "the stolen profile is no longer active")
	check(backend.data.u1.data.coins == 70, "the old server's late write never landed")
	check(B.active.u1 == nil, "the old server forgot the stolen profile")

	-- DataStore errors
	backend.failNext = 1
	ok, reason = pc:save()
	check(ok == false and reason == "error" and pc:isActive(), "a failed save keeps the profile active")
	check(pc:save() == true, "the next save works")
	backend.failNext = 1
	check(pc:release() == true, "release retries after an error")

	-- loads that keep erroring give up with "error"
	backend.failNext = 10
	local pd, why2 = A:load("u2")
	check(pd == nil and why2 == "error", "a save that can't be read isn't treated as new (" .. tostring(why2) .. ")")
	backend.failNext = 0

	-- the same server, same player rejoining before the old profile let go
	local p1 = A:load("u3")
	local p2, why3 = A:load("u3")
	check(p2 == nil and why3 == "locked", "a second load in the same server waits for the first to release")
	p1:release()
	p2 = A:load("u3")
	check(p2 ~= nil, "after release the same server can load it again")
	p2:release()

	-- reconcile: fields added to the template later are filled in
	backend.data.u4 = { data = { coins = 3 }, meta = { created = 1, loads = 1 } }
	local p4 = A:load("u4")
	check(p4.Data.coins == 3 and type(p4.Data.inv) == "table" and p4.Data.nested.a == 1, "old saves get new template fields")
	p4:release()
	-- an old record that was only the data table
	backend.data.u5 = { coins = 8 }
	local p5 = A:load("u5")
	check(p5 ~= nil and p5.Data.coins == 8, "a plain old data table is kept")
	p5:release()

	-- releaseAll
	local q1, q2 = C:load("r1"), C:load("r2")
	check(q1 and q2, "two profiles loaded")
	check(C:releaseAll(5) == true, "releaseAll finishes")
	check(backend.data.r1.meta.lock == nil and backend.data.r2.meta.lock == nil, "releaseAll unlocks everything")
end

---------------------------------------------------------------------------
-- EconomyManager
---------------------------------------------------------------------------
local backend = ProfileStore.memoryStore()
local changes = 0
EconomyManager.init({
	dataStore = backend,
	jobId = "test",
	clock = clock,
	wait = fakeWait,
	warn = _G.warn,
	onChanged = function()
		changes += 1
	end,
	loadAttempts = 2,
	retryDelay = 1,
})
local alice = { UserId = 101, Name = "alice" }
local bob = { UserId = 202, Name = "bob" }

local profile = EconomyManager.load(alice)
check(profile ~= nil, "alice's save loads")
check(EconomyManager.getBalance(alice, "Gems") == ShopCatalog.StartingGems, "new players start with the starting Gems")
check(EconomyManager.getBalance(alice, "Coins") == ShopCatalog.StartingCoins, "new players start with the starting Coins")
check(EconomyManager.getBalance(alice, "Robux") == 0, "unknown currency reads as 0")

-- spending
local g0 = EconomyManager.getBalance(alice, "Gems")
for _, bad in ipairs({ 0, -5, 1.5, 0 / 0, math.huge, 2e9 }) do
	check(EconomyManager.trySpend(alice, "Gems", bad) == false, "trySpend refuses " .. tostring(bad))
end
check(EconomyManager.trySpend(alice, "Gems", "10" :: any) == false, "trySpend refuses a string")
check(EconomyManager.trySpend(alice, "Gold", 10) == false, "trySpend refuses an unknown currency")
check(EconomyManager.getBalance(alice, "Gems") == g0, "refused spends change nothing")
check(EconomyManager.trySpend(alice, "Gems", 100, "pack") == true, "trySpend pays 100 Gems")
check(EconomyManager.getBalance(alice, "Gems") == g0 - 100, "100 Gems gone")
check(EconomyManager.trySpend(alice, "Gems", g0) == false, "can't spend more than you have")
check(EconomyManager.getBalance(alice, "Gems") == g0 - 100, "overspend changed nothing")
check(EconomyManager.grant(alice, "Gems", 100) == true and EconomyManager.getBalance(alice, "Gems") == g0, "grant gives Gems back")
check(EconomyManager.grant(alice, "Coins", -1) == false, "grant refuses negatives")
check(changes > 0, "changes are reported to the server script")

-- a player whose save never loads: everything fails safely
check(EconomyManager.trySpend(bob, "Gems", 1) == false, "no save, no spending")
check(EconomyManager.getBalance(bob, "Coins") == 0, "no save reads as 0")

-- cards
local isNew, counts, unique = EconomyManager.grantCards(alice, { "jelly_bean_scout", "jelly_bean_scout", "not_a_card" })
check(isNew[1] == true and isNew[2] == false and counts[2] == 2, "grantCards counts copies and new cards")
check(isNew[3] == false and counts[3] == 0 and unique == 1, "grantCards skips unknown cards")
check(EconomyManager.ownsCard(alice, "jelly_bean_scout") == 2, "ownsCard")
local coll = EconomyManager.getCollection(alice)
coll.jelly_bean_scout = 99
check(EconomyManager.ownsCard(alice, "jelly_bean_scout") == 2, "getCollection returns a copy")
check(EconomyManager.getDeckSlots(alice) == ShopCatalog.DeckSlots.start, "deck slots start at " .. ShopCatalog.DeckSlots.start)

-- daily login and streaks
local function day()
	return ShopCatalog.dayNumber(now)
end
local r = EconomyManager.claimDaily(alice)
check(r ~= nil and r.streak == 1 and r.coins == ShopCatalog.Daily.coins and r.gems == ShopCatalog.Daily.gems, "first daily login reward")
check(EconomyManager.claimDaily(alice) == nil, "only once a day")
now += 86400
r = EconomyManager.claimDaily(alice)
check(r and r.streak == 2 and r.coins == ShopCatalog.Daily.coins + ShopCatalog.Daily.coinsPerStreakDay, "next day: streak 2")
now += 2 * 86400
r = EconomyManager.claimDaily(alice)
check(r and r.streak == 1, "skipping a day resets the streak")
for _ = 1, 6 do
	now += 86400
	r = EconomyManager.claimDaily(alice)
end
check(r and r.streak == 7 and r.gems == ShopCatalog.Daily.gems + ShopCatalog.Daily.streakBonusGems, "day 7 gives the streak bonus")

-- daily card rotation
local rot = ShopCatalog.dailyCards(day())
local rot2 = ShopCatalog.dailyCards(day())
check(#rot == #ShopCatalog.DailySlots, "6 daily cards")
local seen, same = {}, true
for i, o in ipairs(rot) do
	check(not seen[o.id], "daily card " .. o.id .. " shows once")
	seen[o.id] = true
	check(CardData.Cards[o.id].rarity == o.rarity and o.price == ShopCatalog.CardPrice[o.rarity], "daily card " .. i .. " has its rarity's price")
	check(not CardData.Cards[o.id].token, "no tokens in the shop")
	same = same and rot2[i].id == o.id
end
check(same, "the same day gives the same rotation")
local differs = false
for d = 1, 5 do
	local other = ShopCatalog.dailyCards(day() + d)
	for i, o in ipairs(other) do
		if o.id ~= rot[i].id then
			differs = true
		end
	end
end
check(differs, "the rotation changes from day to day")

-- buying a daily card
EconomyManager.grant(alice, "Coins", 100000)
local c0 = EconomyManager.getBalance(alice, "Coins")
local ok, msg, extra = EconomyManager.buy(alice, "card", 1)
check(ok and extra and extra.id == rot[1].id, "buy daily card 1 (" .. tostring(msg) .. ")")
check(EconomyManager.getBalance(alice, "Coins") == c0 - rot[1].price, "the card's price was paid")
check(EconomyManager.ownsCard(alice, rot[1].id) >= 1, "the card is in the collection")
ok = EconomyManager.buy(alice, "card", 1)
check(not ok, "each daily card only once a day")
check(not EconomyManager.buy(alice, "card", 99), "unknown slot refused")
check(not EconomyManager.buy(alice, "card", "1; drop" :: any), "junk slot refused")
check(EconomyManager.getBalance(alice, "Coins") == c0 - rot[1].price, "refused buys cost nothing")
now += 86400
ok = EconomyManager.buy(alice, "card", 1)
check(ok, "next day the slot can be bought again")

-- cosmetics
ok = EconomyManager.buy(alice, "cosmetic", "board_midnight")
local snap = EconomyManager.snapshot(alice)
check(ok and snap.owned.board_midnight and snap.equipped.board == "board_midnight", "buying a board theme owns and equips it")
check(not EconomyManager.buy(alice, "cosmetic", "board_midnight"), "can't buy a theme twice")
check(not EconomyManager.buy(alice, "cosmetic", "board_walnut"), "default items aren't for sale")
check(EconomyManager.equip(alice, "board", "board_walnut"), "equip the default theme")
check(not EconomyManager.equip(alice, "board", "board_ember"), "can't equip a theme you don't own")
check(not EconomyManager.equip(alice, "cardback", "board_midnight"), "can't equip a board as a card back")
check(not EconomyManager.equip(alice, "emote", "emote_hello"), "emotes aren't equipped")
local gems = EconomyManager.getBalance(alice, "Gems")
EconomyManager.trySpend(alice, "Gems", gems)
check(not EconomyManager.buy(alice, "cosmetic", "board_starlight"), "a Gem theme needs Gems")
check(not EconomyManager.snapshot(alice).owned.board_starlight, "a refused purchase doesn't unlock anything")
EconomyManager.grant(alice, "Gems", 5000)
check(EconomyManager.buy(alice, "cosmetic", "emote_gg"), "buy an emote with Gems")
check(EconomyManager.ownsCosmetic(alice, "emote_gg") and EconomyManager.ownsCosmetic(alice, "emote_hello"), "owned and default emotes")

-- match backgrounds (kind "backdrop"): free ones, Shop ones, Trophy Road ones
snap = EconomyManager.snapshot(alice)
check(snap.equipped.backdrop == "bg_room", "a new player wears the Card Den")
check(snap.owned.bg_room and snap.owned.bg_random, "Card Den and Surprise me are free")
check(EconomyManager.equip(alice, "backdrop", "bg_random"), "wear Surprise me")
check(not EconomyManager.equip(alice, "backdrop", "bg_candy"), "can't wear a background you don't own")
check(not EconomyManager.equip(alice, "board", "bg_candy"), "a background isn't a board theme")
EconomyManager.grant(alice, "Coins", 5000)
ok = EconomyManager.buy(alice, "cosmetic", "bg_candy")
snap = EconomyManager.snapshot(alice)
check(ok and snap.owned.bg_candy and snap.equipped.backdrop == "bg_candy", "buying a background owns and wears it")
local coinsBefore = EconomyManager.getBalance(alice, "Coins")
local roadOk, roadMsg = EconomyManager.buy(alice, "cosmetic", "bg_fire")
check(not roadOk and string.find(roadMsg, "Trophy Road", 1, true) ~= nil, "Trophy Road backgrounds can't be bought")
check(EconomyManager.getBalance(alice, "Coins") == coinsBefore and not EconomyManager.snapshot(alice).owned.bg_fire, "the refused road buy cost nothing")
check(EconomyManager.grantCosmetic(alice, "bg_fire"), "the road can give a background")
check(not EconomyManager.grantCosmetic(alice, "bg_fire"), "only once")
check(EconomyManager.equip(alice, "backdrop", "bg_fire"), "wear the road background")
check(EconomyManager.snapshot(alice).equipped.backdrop == "bg_fire", "the snapshot says so")
check(EconomyManager.equip(alice, "backdrop", "bg_room"), "back to the Card Den")

-- deck slots
for _ = ShopCatalog.DeckSlots.start + 1, ShopCatalog.DeckSlots.max do
	check(EconomyManager.buy(alice, "deckslot"), "buy a deck slot")
end
check(EconomyManager.getDeckSlots(alice) == ShopCatalog.DeckSlots.max, "deck slots at max")
check(not EconomyManager.buy(alice, "deckslot"), "no more deck slots past the max")

-- exchanges
local ex = ShopCatalog.ExchangeById.coins_to_gems
local g1 = EconomyManager.getBalance(alice, "Gems")
for i = 1, ex.perDay do
	check(EconomyManager.buy(alice, "exchange", "coins_to_gems"), "coins to gems #" .. i)
end
check(not EconomyManager.buy(alice, "exchange", "coins_to_gems"), "coins to gems limited per day")
check(EconomyManager.getBalance(alice, "Gems") == g1 + ex.perDay * ex.get.Gems, "the exchange gave the Gems")
check(EconomyManager.buy(alice, "exchange", "gems_to_coins"), "gems to coins (no daily limit)")

-- luck
check(EconomyManager.takePullLuck(alice) == 1, "no luck without a booster")
check(EconomyManager.buy(alice, "boost", "luck_small"), "buy a Lucky Charm")
local lucks = {}
for i = 1, 4 do
	lucks[i] = EconomyManager.takePullLuck(alice)
end
check(lucks[1] == ShopCatalog.LuckMultiplier and lucks[3] == ShopCatalog.LuckMultiplier and lucks[4] == 1, "3 lucky openings, then normal")
EconomyManager.devLuck(alice, ShopCatalog.MaxLuckCharges)
check(not EconomyManager.buy(alice, "boost", "luck_big"), "luck charges are capped")
EconomyManager.devLuck(alice, 0)

-- lucky odds
local o = PullRates.luckyOdds(1.5)
local sum = 0
for _, t in ipairs(PullRates.Tiers) do
	sum += o[t]
end
check(math.abs(sum - 100) < 1e-9, "lucky odds still add up to 100 (" .. sum .. ")")
check(o.Secret > PullRates.Odds.Secret and o.Epic > PullRates.Odds.Epic and o.Rare == PullRates.Odds.Rare and o.Common < PullRates.Odds.Common, "lucky odds favour Epic and better")
check(PullRates.luckyOdds(0 / 0).Common == PullRates.Odds.Common, "bad multipliers mean normal odds")
do
	local function counter(odds)
		local seed = 12345
		local rand = function()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local epicPlus = 0
		for _ = 1, 20000 do
			local tier = PullRates.rollTier(rand, odds)
			if PullRates.Rank[tier] >= PullRates.Rank.Epic then
				epicPlus += 1
			end
		end
		return epicPlus / 20000
	end
	local base, lucky = counter(nil), counter(o)
	check(math.abs(base - 0.18) < 0.015, "normal Epic+ rate is about 18% (" .. base .. ")")
	check(math.abs(lucky - 0.27) < 0.015, "lucky Epic+ rate is about 27% (" .. lucky .. ")")
end

-- match rewards
local function play(result, diff, seconds, turns)
	return EconomyManager.matchReward(alice, { result = result, difficulty = diff, seconds = seconds or 300, turns = turns or 8 })
end
now += 86400 -- a fresh day for the first-win bonus
local before = EconomyManager.snapshot(alice)
local rw = play("win", "Medium", 20, 1)
check(rw.coins == 0 and rw.note == "too short", "a too-short match pays nothing")
rw = play("win", "Medium")
check(rw.coins == ShopCatalog.Match.winCoins.Medium and rw.xp == ShopCatalog.Match.winXp.Medium, "a Medium win pays its coins and XP")
check(rw.gems == ShopCatalog.Match.firstWinGems, "the first win today gives Gems")
rw = play("win", "Medium")
check(rw.gems == 0, "only the first win gives Gems")
rw = play("loss", "Hard")
check(rw.coins == ShopCatalog.Match.lossCoins.Hard, "a loss still pays a little")
rw = play("left" :: any, "Hard")
check(rw.coins == 0 and rw.note == "no result", "leaving pays nothing")
rw = play("win", "Impossible" :: any)
check(rw.coins == ShopCatalog.Match.winCoins.Easy, "an unknown difficulty pays like Easy")
local after = EconomyManager.snapshot(alice)
check(after.level > before.level or after.xp > before.xp, "XP went up")
-- level up
do
	local d = EconomyManager.waitForData(alice)
	d.level, d.xp = 1, ShopCatalog.xpForLevel(1) - 1
	local gb = d.gems
	rw = play("loss", "Easy")
	check(rw.levels == 1 and d.level == 2, "crossing the XP line levels up")
	check(d.gems == gb + ShopCatalog.LevelUpGems, "a level up gives Gems")
end
-- XP boost doubles, then runs out
check(EconomyManager.buy(alice, "boost", "xp_small"), "buy an XP Snack")
rw = play("loss", "Easy")
check(rw.boosted and rw.xp == 2 * ShopCatalog.Match.lossXp.Easy, "XP boost doubles match XP")
now += 31 * 60
rw = play("loss", "Easy")
check(not rw.boosted and rw.xp == ShopCatalog.Match.lossXp.Easy, "the XP boost runs out")
check(EconomyManager.buy(alice, "boost", "xp_big"), "stack a 2 hour boost")
local stacked = 0
while EconomyManager.buy(alice, "boost", "xp_big") do
	stacked += 1
	if stacked > 20 then
		break
	end
end
check(stacked < 20 and EconomyManager.snapshot(alice).xpBoostLeft <= ShopCatalog.MaxXpBoostMinutes * 60, "XP boost stacking is capped at 24 hours")
-- daily paid-match limit
local paidLeft = EconomyManager.snapshot(alice).paidMatchesLeft
for _ = 1, paidLeft do
	play("loss", "Easy")
end
rw = play("win", "Hard")
check(rw.coins == 0 and rw.note == "daily limit", "matches stop paying after the daily limit")

-- snapshot
snap = EconomyManager.snapshot(alice)
check(type(snap.gems) == "number" and type(snap.owned) == "table" and type(snap.bought) == "table" and type(snap.dailyOwned) == "table", "snapshot has the shop fields")
check(snap.resetIn > 0 and snap.resetIn <= 86400, "snapshot reset timer")

-- Robux receipts
local decisions = { PurchaseGranted = "Granted", NotProcessedYet = "NotYet" }
local bundle = ShopCatalog.GemBundles[2]
bundle.productId = 55501
local function getPlayer(id)
	return (id == alice.UserId) and alice or nil
end
local gB = EconomyManager.getBalance(alice, "Gems")
local receipt = { PlayerId = alice.UserId, ProductId = 55501, PurchaseId = "p-1", CurrencySpent = bundle.robux }
check(EconomyManager.processReceipt(receipt, getPlayer, decisions) == "Granted", "a Gem bundle receipt is granted")
check(EconomyManager.getBalance(alice, "Gems") == gB + bundle.gems + bundle.bonus, "the bundle's Gems and bonus arrived")
check(EconomyManager.processReceipt(receipt, getPlayer, decisions) == "Granted", "the same receipt again is still granted")
check(EconomyManager.getBalance(alice, "Gems") == gB + bundle.gems + bundle.bonus, "but its Gems aren't given twice")
check(EconomyManager.processReceipt({ PlayerId = alice.UserId, ProductId = 999, PurchaseId = "p-2" }, getPlayer, decisions) == "NotYet", "an unknown product isn't granted")
check(EconomyManager.processReceipt({ PlayerId = 77, ProductId = 55501, PurchaseId = "p-3" }, getPlayer, decisions) == "NotYet", "a player who left isn't granted yet")
backend.failNext = 1
local gC = EconomyManager.getBalance(alice, "Gems")
check(EconomyManager.processReceipt({ PlayerId = alice.UserId, ProductId = 55501, PurchaseId = "p-4" }, getPlayer, decisions) == "NotYet", "if the save fails the purchase isn't confirmed")
check(EconomyManager.processReceipt({ PlayerId = alice.UserId, ProductId = 55501, PurchaseId = "p-4" }, getPlayer, decisions) == "Granted", "Roblox's retry is confirmed")
check(EconomyManager.getBalance(alice, "Gems") == gC + bundle.gems + bundle.bonus, "and the Gems came exactly once")
check(backend.data["u101"].data.receipts[#backend.data["u101"].data.receipts] == "p-4", "the receipt id is in the save")
bundle.productId = 0

-- leaving saves; joining again loads the same numbers
local final = EconomyManager.snapshot(alice)
check(EconomyManager.unload(alice) == true, "leaving saves and unlocks")
check(not EconomyManager.isLoaded(alice), "unloaded")
check(backend.data.u101.meta.lock == nil, "the lock is gone after leaving")
EconomyManager.load(alice)
local again = EconomyManager.snapshot(alice)
check(again.gems == final.gems and again.coins == final.coins and again.level == final.level and again.deckSlots == final.deckSlots, "rejoining loads the same wallet")
check(again.owned.board_midnight == true, "rejoining keeps bought cosmetics")

-- dev tools
check(EconomyManager.devGive(alice, "Coins", 1000), "devGive")
check(EconomyManager.devNewDay(alice) and EconomyManager.claimDaily(alice) ~= nil, "devNewDay resets the daily login")
check(EconomyManager.devResetSave(alice), "devResetSave")
snap = EconomyManager.snapshot(alice)
check(snap.gems == ShopCatalog.StartingGems and snap.coins == ShopCatalog.StartingCoins and snap.deckSlots == ShopCatalog.DeckSlots.start, "reset save is a new player's")
check(#EconomyManager.waitForData(alice).receipts >= 2, "reset save keeps the receipt list")
EconomyManager.unload(alice)

-- a save that's locked by another server can't be loaded
do
	local other = ProfileStore.new(backend, { template = EconomyManager.Template, jobId = "other", clock = clock, wait = fakeWait, warn = _G.warn })
	local held = other:load("u202")
	check(held ~= nil, "another server holds bob's save")
	local p, why = EconomyManager.load(bob)
	check(p == nil and why == "locked", "bob can't load while another server holds his save")
	check(EconomyManager.trySpend(bob, "Gems", 1) == false, "and can't spend")
	held:release()
	p = EconomyManager.load(bob)
	check(p ~= nil, "after the other server lets go, bob loads")
	EconomyManager.unload(bob)
end

-- every price is a whole positive number and every id is unique
local ids = {}
local function priced(item)
	local cur, n = ShopCatalog.priceOf(item.price or item.give)
	return cur ~= nil and EconomyManager.validAmount(n)
end
for _, c in ipairs(ShopCatalog.Cosmetics) do
	check(not ids[c.id], "unique id " .. c.id)
	ids[c.id] = true
	check(c.default or c.road or priced(c), c.id .. " has a price")
	if c.kind == "backdrop" then
		local WORLDS = { Room = true, Random = true, Candy = true, Meadow = true, Ice = true, Fire = true, Space = true, Mall = true } -- (Backdrops.List)
		check(WORLDS[c.backdrop or ""] == true, c.id .. " is a real world")
	end
	if c.road then
		local onRoad = false
		for _, stop in ipairs(require("Progression").TrophyRoad) do
			onRoad = onRoad or stop.cosmetic == c.id
		end
		check(onRoad and not c.price, c.id .. " is on the Trophy Road and not for sale")
	end
end
-- the road goes up, and every stop pays something real
do
	local Progression = require("Progression")
	local last = 0
	for i, stop in ipairs(Progression.TrophyRoad) do
		check(stop.at > last, "Trophy Road stop " .. i .. " comes after the one before")
		last = stop.at
		check((stop.gems or 0) > 0 or (stop.coins or 0) > 0 or (stop.cosmetic and ShopCatalog.CosmeticById[stop.cosmetic] ~= nil), "Trophy Road stop " .. i .. " has a reward")
	end
	check(Progression.trophiesFor({ result = "win", difficulty = "Hard" }) > Progression.trophiesFor({ result = "win", difficulty = "Easy" }), "a Hard win earns more trophies than an Easy one")
	check(Progression.trophiesFor({ result = "win", pvp = true }) == Progression.Trophies.pvpWin, "a win against people")
	check(Progression.trophiesFor({ result = "loss" }) == Progression.Trophies.finish, "a loss still earns a trophy")
end
for _, b in ipairs(ShopCatalog.Boosts) do
	check(priced(b), b.id .. " has a price")
end
for _, e in ipairs(ShopCatalog.Exchanges) do
	check(priced(e), e.id .. " has a price")
end
check(ShopCatalog.format(1234567) == "1,234,567" and ShopCatalog.format(12) == "12", "number formatting")

print(string.format("economy tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("economy tests failed")
end

-- Headless tests for card levels (fusing, selling, storage, what a level gives) and for trading at
-- the Park's Trading Post (what can be offered, room, daily limits, the swap itself).
-- Run with: luaurun tests/levels_trade_tests.luau src/shared

local CardData = require("CardData")
local CardLevels = require("CardLevels")
local Trade = require("Trade")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. msg)
	end
end

-- one card of each rarity and kind to test with
local byRarity, creatureOf, cheapSpell, dearSpell, token = {}, {}, nil, nil, nil
local ids = {}
for id in pairs(CardData.Cards) do
	table.insert(ids, id)
end
table.sort(ids)
for _, id in ipairs(ids) do
	local c = CardData.Cards[id]
	if c.token then
		token = token or id
	else
		byRarity[c.rarity] = byRarity[c.rarity] or id
		if c.type == "Creature" then
			creatureOf[c.rarity] = creatureOf[c.rarity] or id
		elseif (c.cost or 0) >= 2 then
			dearSpell = dearSpell or id
		elseif (c.cost or 0) <= 1 then
			cheapSpell = cheapSpell or id
		end
	end
end
for _, r in ipairs(CardData.Rarities) do
	check(byRarity[r] ~= nil, "there is a " .. r .. " card to test with")
	check(CardLevels.MaxLevel[r] ~= nil and CardLevels.SellCoins[r] ~= nil, r .. " has a max level and a sell price")
end

---------------------------------------------------------------------------
-- Max levels, bonuses, sell values
---------------------------------------------------------------------------
-- rarer cards never have more levels, and sell for more
for i = 2, #CardData.Rarities do
	local a, b = CardData.Rarities[i - 1], CardData.Rarities[i]
	check(CardLevels.MaxLevel[b] <= CardLevels.MaxLevel[a], b .. " has no more levels than " .. a)
	check(CardLevels.SellCoins[b] > CardLevels.SellCoins[a], b .. " sells for more than " .. a)
end
check(CardLevels.maxLevel("no such card") == 1, "an unknown card has one level")
for _, id in ipairs(ids) do
	local c = CardData.Cards[id]
	local max = CardLevels.maxLevel(id)
	local b1 = CardLevels.bonus(id, 1)
	check(b1.atk == 0 and b1.hp == 0 and b1.cost == 0, id .. ": level 1 gives nothing")
	local last = b1
	for l = 2, max do
		local b = CardLevels.bonus(id, l)
		check(b.atk >= last.atk and b.hp >= last.hp and b.cost <= last.cost, id .. ": level " .. l .. " is never worse than the one before")
		last = b
	end
	local top = CardLevels.bonus(id, max)
	if not c.token and max > 1 then
		if c.type == "Creature" then
			check(top.atk == 1 and top.hp == 1 and top.cost == 0, id .. ": a maxed creature has +1 attack and +1 health")
		else
			check(top.atk == 0 and top.hp == 0, id .. ": spells and buildings get no attack or health")
			check(top.cost == (((c.cost or 0) >= 2) and -1 or 0), id .. ": costs 1 less at the max, never less than 1")
			check((c.cost or 0) + top.cost >= math.min(1, c.cost or 0), id .. ": never becomes free")
		end
	end
	local over = CardLevels.bonus(id, max + 5)
	check(over.atk == top.atk and over.hp == top.hp and over.cost == top.cost, id .. ": levels past the max count as the max")
	check(CardLevels.sellValue(id, 1) == (CardLevels.SellCoins[c.rarity] or 0), id .. ": a level 1 copy sells for its rarity's price")
	check(CardLevels.sellValue(id, 3) == 4 * CardLevels.sellValue(id, 1), id .. ": a level 3 copy sells like the 4 copies in it")
end
check(CardLevels.sellValue("no such card", 1) == 0, "an unknown card sells for nothing")
do
	local id = creatureOf.Common
	local step, text = CardLevels.nextStep(id, 1)
	check(step ~= nil and step > 1 and type(text) == "string" and #text > 0, "the shelf knows a Common's next step")
	check(CardLevels.nextStep(id, CardLevels.maxLevel(id)) == nil, "nothing left after the max")
	check(CardLevels.bonusText(id, 1) == "no bonus" and CardLevels.bonusText(id, CardLevels.maxLevel(id)) ~= "no bonus", "bonus text")
end

---------------------------------------------------------------------------
-- Counts by level
---------------------------------------------------------------------------
do
	local id = creatureOf.Common -- max level 5
	check(CardLevels.total({ [1] = 3, [2] = 1 }) == 4 and CardLevels.total(nil) == 0, "total counts every copy")
	local n = CardLevels.normalize(id, nil, 3)
	check(n[1] == 3 and CardLevels.total(n) == 3, "an old save's copies all start at level 1")
	n = CardLevels.normalize(id, { [1] = 1, [3] = 1 }, 4)
	check(n[1] == 3 and n[3] == 1, "missing copies are added at level 1")
	n = CardLevels.normalize(id, { [1] = 2, [2] = 2, [4] = 1 }, 2)
	check(n[1] == nil and n[2] == 1 and n[4] == 1, "extra copies are taken from the lowest levels")
	n = CardLevels.normalize(id, { [9] = 1, [0] = 4, [2] = -3, ["x"] = 2 }, 1)
	check(n[5] == 1 and CardLevels.total(n) == 1, "levels past the max fold down, junk is dropped")
	n = CardLevels.normalize(id, { [1] = 2 }, 0)
	check(next(n) == nil, "no copies left means an empty table")
	local list = CardLevels.toList({ [1] = 2, [3] = 1 })
	check(#list == 3 and list[1] == 2 and list[2] == 0 and list[3] == 1, "toList has no gaps")
	local back = CardLevels.fromList(list)
	check(back[1] == 2 and back[2] == nil and back[3] == 1, "fromList gives the counts back")
	check(next(CardLevels.fromList("junk" :: any)) == nil and #CardLevels.toList(nil) == 0, "junk lists are empty")
	check(CardLevels.best({ [1] = 2, [3] = 1 }) == 3 and CardLevels.best({}) == 0, "best level")
	local top = CardLevels.top({ [1] = 2, [3] = 1, [2] = 1 }, 3)
	check(#top == 3 and top[1] == 3 and top[2] == 2 and top[3] == 1, "a deck plays the highest copies first")
	check(#CardLevels.top({ [1] = 1 }, 3) == 1, "top never invents copies")
	local decks = { { cards = { id, id, "x" } }, { cards = { id } }, "junk", { cards = 5 } }
	check(CardLevels.reserved(decks, id) == 2 and CardLevels.reserved(decks, "y") == 0 and CardLevels.reserved(nil, id) == 0, "decks reserve the most copies any one deck uses")
end

---------------------------------------------------------------------------
-- Fusing and selling
---------------------------------------------------------------------------
do
	local id = creatureOf.Common
	local max = CardLevels.maxLevel(id)
	local levels = { [1] = 2 }
	check(CardLevels.canFuse(id, levels, 1, 0) == true, "two level 1 copies fuse")
	check(not CardLevels.canFuse(id, { [1] = 1 }, 1, 0), "one copy doesn't")
	check(not CardLevels.canFuse(id, { [1] = 1, [2] = 1 }, 1, 0), "copies at different levels don't")
	check(not CardLevels.canFuse(id, { [max] = 2 }, max, 0), "nothing fuses past the max")
	check(not CardLevels.canFuse(id, levels, 0, 0) and not CardLevels.canFuse(id, levels, 0 / 0, 0) and not CardLevels.canFuse(id, levels, "1; drop" :: any, 0), "junk levels are refused")
	check(not CardLevels.canFuse("no such card", levels, 1, 0), "unknown cards are refused")
	check(not CardLevels.canFuse(id, levels, 1, 2), "a fuse can't leave fewer copies than the decks use")
	check(CardLevels.canFuse(id, { [1] = 3 }, 1, 2) == true, "with a spare copy it can")
	CardLevels.fuse(levels, 1)
	check(levels[1] == nil and levels[2] == 1, "2 x Lv1 become 1 x Lv2")

	-- 2^(max-1) copies make exactly one maxed copy
	local many = { [1] = 2 ^ (max - 1) }
	local n, made = CardLevels.fuseAll(id, many, 0)
	check(n == 2 ^ (max - 1) - 1 and many[max] == 1 and CardLevels.total(many) == 1, "fuseAll: " .. 2 ^ (max - 1) .. " copies become one maxed copy")
	check(made[#made] == max, "the last fuse reaches the max level")
	local kept = { [1] = 4 }
	n = CardLevels.fuseAll(id, kept, 3)
	check(n == 1 and CardLevels.total(kept) == 3, "fuseAll keeps the copies the decks use")
	n = CardLevels.fuseAll(id, { [1] = 1, [2] = 1 }, 0)
	check(n == 0, "fuseAll with nothing to fuse does nothing")
	-- every fuse keeps the worth (in level 1 copies) the same
	local function worth(t)
		local w = 0
		for l, c in pairs(t) do
			w += c * 2 ^ (l - 1)
		end
		return w
	end
	local mix = { [1] = 7, [2] = 3, [3] = 1 }
	local before = worth(mix)
	CardLevels.fuseAll(id, mix, 0)
	check(worth(mix) == before, "fusing never makes or loses copies' worth")

	-- selling
	check(CardLevels.canSell(id, { [1] = 1 }, 1, 0) == true, "a spare copy can be sold")
	check(not CardLevels.canSell(id, { [1] = 1 }, 2, 0), "not a copy you don't have")
	check(not CardLevels.canSell(id, { [1] = 2 }, 1, 2), "not a copy the decks need")
	check(not CardLevels.canSell(id, { [1] = 2, [3] = 1 }, 3, 1), "not the best copy while a deck plays it")
	check(CardLevels.canSell(id, { [1] = 2, [3] = 1 }, 1, 1) == true, "the spare low copy can go")
	check(not CardLevels.canSell(id, { [1] = 2 }, 0 / 0, 0) and not CardLevels.canSell("no such card", { [1] = 2 }, 1, 0), "junk is refused")
	local s = { [1] = 1, [2] = 2 }
	CardLevels.sell(s, 1)
	CardLevels.sell(s, 2)
	check(s[1] == nil and s[2] == 1, "selling takes one copy")
end

---------------------------------------------------------------------------
-- Trading
---------------------------------------------------------------------------
local NOW = 1_800_000_000
local function save(level, cards)
	local d = { level = level, collection = {}, cardLevels = {}, decks = {}, stats = {} }
	for id, list in pairs(cards or {}) do
		d.cardLevels[id] = list
		local n = 0
		for _, c in ipairs(list) do
			n += c
		end
		d.collection[id] = n
	end
	return d
end
local function copies(d)
	local n = 0
	for _, c in pairs(d.collection) do
		n += c
	end
	return n
end
local A, B, C = creatureOf.Common, creatureOf.Rare, creatureOf.Epic
do
	-- who can trade
	check(Trade.eligible(save(Trade.MinLevel), NOW) == true, "level " .. Trade.MinLevel .. " can trade")
	local ok, why = Trade.eligible(save(Trade.MinLevel - 1), NOW)
	check(not ok and why == "level", "a lower level can't")
	local busy = save(10)
	busy.trades = { day = Trade.day(NOW), count = Trade.MaxPerDay }
	ok, why = Trade.eligible(busy, NOW)
	check(not ok and why == "daily", "the daily limit stops trading")
	check(Trade.eligible(busy, NOW + 86400) == true and Trade.today(busy, NOW + 86400) == 0, "and is over the next day")

	-- offers from the network
	check(Trade.cleanOffer("junk" :: any) == nil and Trade.cleanOffer({ "x" }) == nil, "junk offers are refused")
	check(Trade.cleanOffer({ { id = "no such card", level = 1 } }) == nil, "unknown cards are refused")
	check(token == nil or Trade.cleanOffer({ { id = token, level = 1 } }) == nil, "tokens can't be traded")
	for _, lvl in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, CardLevels.maxLevel(A) + 1, "1" }) do
		check(Trade.cleanOffer({ { id = A, level = lvl } }) == nil, "level " .. tostring(lvl) .. " is refused")
	end
	local tooMany = {}
	for i = 1, Trade.MaxOffer + 1 do
		tooMany[i] = { id = A, level = 1 }
	end
	check(Trade.cleanOffer(tooMany) == nil, "more than " .. Trade.MaxOffer .. " cards is refused")
	local clean = Trade.cleanOffer({ { id = A, level = 1, extra = "x" }, { id = B, level = 2 } })
	check(clean ~= nil and #clean == 2 and clean[1].extra == nil and clean[2].level == 2, "a good offer is copied clean")
	check(Trade.sameOffer(clean, { { id = A, level = 1 }, { id = B, level = 2 } }) and not Trade.sameOffer(clean, { { id = A, level = 1 } }) and not Trade.sameOffer(clean, { { id = A, level = 1 }, { id = B, level = 1 } }), "sameOffer compares cards and levels")
	check(Trade.cleanOffer({}) ~= nil, "an empty offer (a gift from the other side) is fine")
end
do
	-- what can be offered: not the copies the decks play
	local d = save(5, { [A] = { 2, 1 }, [B] = { 1 } })
	d.decks = { { cards = { A, A } } }
	check(Trade.checkOffer(d, { { id = A, level = 1 } }) == true, "a spare copy can be offered")
	check(not Trade.checkOffer(d, { { id = A, level = 2 } }), "not the best copy a deck plays")
	check(not Trade.checkOffer(d, { { id = A, level = 1 }, { id = A, level = 1 } }), "not more copies than are spare")
	check(not Trade.checkOffer(d, { { id = C, level = 1 } }), "not a card you don't own")
	local list = Trade.tradable(d)
	local seen = {}
	for _, t in ipairs(list) do
		seen[t.id .. ":" .. t.level] = t.count
	end
	check(seen[A .. ":1"] == 1 and seen[A .. ":2"] == nil and seen[B .. ":1"] == 1, "tradable lists only the spare copies")
	check(list[1].id == B, "rarest first")
	check(d.collection[A] == 3 and d.cardLevels[A][1] == 2, "checking an offer changes nothing")
end
do
	-- the swap
	local a = save(5, { [A] = { 2 }, [B] = { 0, 1 } })
	local b = save(5, { [C] = { 1 } })
	local offerA = { { id = A, level = 1 }, { id = B, level = 2 } }
	local offerB = { { id = C, level = 1 } }
	local totalBefore = copies(a) + copies(b)
	check(not Trade.canSwap(a, {}, b, {}), "two empty offers aren't a trade")
	local ok, _, side = Trade.canSwap(a, { { id = C, level = 1 } }, b, offerB)
	check(not ok and side == "a", "a bad offer names its side (a)")
	ok, _, side = Trade.canSwap(a, offerA, b, { { id = A, level = 1 } })
	check(not ok and side == "b", "a bad offer names its side (b)")
	check(Trade.swap(a, offerA, b, offerB, NOW) == true, "the swap goes through")
	check(a.collection[A] == 1 and a.collection[B] == nil and a.cardLevels[B] == nil and a.collection[C] == 1, "A gave two cards and got one")
	check(b.collection[C] == nil and b.collection[A] == 1 and b.collection[B] == 1 and b.cardLevels[B][2] == 1, "B got them at the same levels")
	check(copies(a) + copies(b) == totalBefore, "no card is made or lost")
	check(Trade.today(a, NOW) == 1 and Trade.today(b, NOW) == 1 and a.stats.trades == 1 and b.stats.trades == 1, "both count the trade")
	-- a failed swap changes nothing
	local snapA, snapB = copies(a), copies(b)
	check(not Trade.swap(a, { { id = B, level = 1 } }, b, {}, NOW), "a swap with a card A no longer has is refused")
	check(copies(a) == snapA and copies(b) == snapB and Trade.today(a, NOW) == 1, "and nothing changes")
	-- a gift
	check(Trade.swap(a, { { id = C, level = 1 } }, b, {}, NOW) == true and b.collection[C] == 1 and a.collection[C] == nil, "one side may give for nothing")
	check(Trade.describe({ { id = A, level = 1 }, { id = A, level = 1 }, { id = B, level = 2 } }) == "2 × " .. CardData.Cards[A].name .. ", " .. CardData.Cards[B].name .. " (Lv 2)", "an offer in words")
end
do
	-- storage: a trade that adds cards has to fit; one that doesn't always fits
	local full = save(5, { [A] = { CardLevels.StorageLimit } })
	local giver = save(5, { [B] = { 2 } })
	check(Trade.kept(full) == CardLevels.StorageLimit and Trade.limit(full) == CardLevels.StorageLimit, "kept and limit")
	local ok, why, side = Trade.canSwap(giver, { { id = B, level = 1 } }, full, {})
	check(not ok and side == "b" and string.find(why, "no room", 1, true) ~= nil, "a full collection can't take a gift")
	check(Trade.canSwap(giver, { { id = B, level = 1 } }, full, { { id = A, level = 1 } }) == true, "a one for one swap always fits")
	full.storageBonus = 1
	check(Trade.limit(full) == CardLevels.StorageLimit + 1 and Trade.canSwap(giver, { { id = B, level = 1 } }, full, {}) == true, "bought storage makes room")
end

print(string.format("levels and trade tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("levels and trade tests failed")
end

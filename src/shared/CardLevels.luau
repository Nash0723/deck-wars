-- Card levels: owning several copies of a card, fusing them, selling them, and what a level does.
-- Pure Luau (no Roblox parts): the server, the Deck Shelf and the match engine all use these rules.
--
-- Copies and levels
--   Every card you pull is one copy at level 1. Two copies of the same card at the same level fuse
--   into one copy a level higher: 2 x Lv1 -> Lv2, 2 x Lv2 -> Lv3, and so on. So a level L copy is
--   worth 2^(L-1) level 1 copies.
--   A player's copies of one card are kept as counts per level: { [1] = 3, [2] = 1 } means three
--   level 1 copies and one level 2 copy (four copies in all, for decks).
--
-- Max level by rarity (fair across rarities)
--   Rarer cards are already much stronger, and their copies are much harder to find. So the rarer
--   the card, the fewer levels it has: reaching the max takes about the same number of pack pulls
--   for every rarity (roughly 550-1,300 cards pulled), and the rarest cards can't snowball.
--     Common 5 (16 copies)  Rare 4 (8)  Epic 4 (8)  Mythic 3 (4)  Legendary 2 (2)  Secret 2 (2)
--
-- What a level does (small on purpose: a maxed deck is a little stronger, never a different game)
--   Creatures get two steps at most, +1 health halfway and +1 attack at the max level:
--     Common  Lv3 +1 health, Lv5 +1 attack      Rare / Epic  Lv3 +1 health, Lv4 +1 attack
--     Mythic  Lv2 +1 health, Lv3 +1 attack      Legendary / Secret  Lv2 +1 attack +1 health
--   The other levels are progress towards the next step (the pips fill up).
--   Spells and buildings: at their max level they cost 1 less, but never less than 1 (so a
--   1-cost card has no cost bonus and no card ever becomes free).
--   Practice decks and bots are always level 1.
--
-- Where levels count (InDuels)
--   Against bots (the Campaign, practice) your levels make your creatures tougher: that's the
--   progress you feel. In a duel against another player every card plays at its printed numbers,
--   so nobody can buy a win; there the level is shown (pips, the gold rim, the played-card
--   showcase) as a badge of how far you've taken that card.
--   Why: 300 headless bot matches, the same deck against the same opponent. At level 1 it won 53%.
--   With every copy maxed it won 89% with these +1/+1 steps (79% even with +1 health alone), far
--   too much for matches between players. Set InDuels to true to let levels count there too.
--
-- Selling
--   Any copy can be sold for Coins: SellCoins[rarity] for a level 1 copy, and a level L copy sells
--   for 2^(L-1) times that (the copies that went into it). Low enough that pulling to sell never
--   pays: a pack (100 Gems) is worth far more than any common sells for.
--
-- Storage
--   You can keep StorageLimit copies (a fused card counts as one). While you're at the limit you
--   can't open packs: fuse or sell first. (A pack you open just under the limit always fits.)
--
-- Copies in decks are kept
--   Fusing or selling never takes you below the number of copies your saved decks use, so a deck
--   that was ready to play stays ready. Decks always play your highest level copies.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")

local CardLevels = {}

CardLevels.MaxLevel = { Common = 5, Rare = 4, Epic = 4, Mythic = 3, Legendary = 2, Secret = 2 }
CardLevels.SellCoins = { Common = 15, Rare = 40, Epic = 100, Mythic = 250, Legendary = 600, Secret = 1500 }
CardLevels.StorageLimit = 60 -- copies you can keep (fused cards count once)
CardLevels.InDuels = false -- do levels change the numbers in matches against other players?

-- The level where a creature gets +1 health (halfway to its max; +1 attack comes at the max).
local function healthLevel(max)
	return math.max(2, math.ceil((max + 1) / 2))
end

local function def(id)
	return CardData.Cards[id]
end

function CardLevels.maxLevel(id)
	local d = def(id)
	return (d and CardLevels.MaxLevel[d.rarity]) or 1
end

-- What a copy at `level` gets in a match: { atk, hp, cost } (cost is 0 or negative).
function CardLevels.bonus(id, level)
	local out = { atk = 0, hp = 0, cost = 0 }
	local d = def(id)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, CardLevels.maxLevel(id))
	if not d or level <= 1 then
		return out
	end
	local max = CardLevels.maxLevel(id)
	if d.type == "Creature" then
		if level >= healthLevel(max) then
			out.hp = 1
		end
		if level >= max then
			out.atk = 1
		end
	elseif level >= max and (d.cost or 0) >= 2 then
		out.cost = -1
	end
	return out
end

-- The next level that adds something, and what (nil when there's nothing left): for the shelf.
function CardLevels.nextStep(id, level)
	local now = CardLevels.bonus(id, level)
	for l = (level or 1) + 1, CardLevels.maxLevel(id) do
		local b = CardLevels.bonus(id, l)
		if b.atk ~= now.atk or b.hp ~= now.hp or b.cost ~= now.cost then
			local diff = { atk = b.atk - now.atk, hp = b.hp - now.hp, cost = b.cost - now.cost }
			local bits = {}
			if diff.atk > 0 then
				table.insert(bits, "+" .. diff.atk .. " ⚔")
			end
			if diff.hp > 0 then
				table.insert(bits, "+" .. diff.hp .. " ❤")
			end
			if diff.cost < 0 then
				table.insert(bits, "costs " .. -diff.cost .. " less")
			end
			return l, table.concat(bits, " ")
		end
	end
	return nil
end

-- "+1 ❤" / "+1 ⚔ +1 ❤" / "costs 1 less": what a level gives, in words (for the shelf).
function CardLevels.bonusText(id, level)
	local b = CardLevels.bonus(id, level)
	local bits = {}
	if b.atk > 0 then
		table.insert(bits, "+" .. b.atk .. " ⚔")
	end
	if b.hp > 0 then
		table.insert(bits, "+" .. b.hp .. " ❤")
	end
	if b.cost < 0 then
		table.insert(bits, "costs " .. -b.cost .. " less")
	end
	return #bits > 0 and table.concat(bits, " ") or "no bonus"
end

-- Coins for selling one copy at `level`.
function CardLevels.sellValue(id, level)
	local d = def(id)
	local base = (d and CardLevels.SellCoins[d.rarity]) or 0
	return base * 2 ^ (math.max(1, level or 1) - 1)
end

---------------------------------------------------------------------------
-- Level counts: { [level] = copies }
---------------------------------------------------------------------------

function CardLevels.total(levels)
	local n = 0
	for _, c in pairs(levels or {}) do
		n += c
	end
	return n
end

-- A clean copy of a counts table for card `id` that holds exactly `total` copies: levels above the
-- card's max are folded down, and copies are added at level 1 (or taken from the lowest levels)
-- until the total matches. Used when a save's two tables disagree (old saves had only totals).
function CardLevels.normalize(id, levels, total)
	local max = CardLevels.maxLevel(id)
	local out = {}
	if type(levels) == "table" then
		for k, v in pairs(levels) do
			local l = math.floor(tonumber(k) or 0)
			local c = math.floor(tonumber(v) or 0)
			if l >= 1 and c > 0 then
				l = math.min(l, max)
				out[l] = (out[l] or 0) + c
			end
		end
	end
	total = math.max(0, math.floor(tonumber(total) or 0))
	local have = CardLevels.total(out)
	if have < total then
		out[1] = (out[1] or 0) + (total - have)
	elseif have > total then
		local extra = have - total
		for l = 1, max do
			while extra > 0 and (out[l] or 0) > 0 do
				out[l] -= 1
				extra -= 1
			end
		end
	end
	for l = 1, max do
		if out[l] == 0 then
			out[l] = nil
		end
	end
	return out
end

-- Saves and network messages can't hold tables with gaps, so a counts table travels as a plain
-- list: { copies at Lv1, copies at Lv2, ... } (zeros in between, nothing after the best level).
function CardLevels.toList(levels)
	local best = 0
	for l, c in pairs(levels or {}) do
		if type(l) == "number" and c > 0 and l > best then
			best = l
		end
	end
	local out = {}
	for l = 1, best do
		out[l] = (levels[l] or 0)
	end
	return out
end

function CardLevels.fromList(list)
	local out = {}
	if type(list) == "table" then
		for l, c in pairs(list) do
			l = tonumber(l)
			c = math.floor(tonumber(c) or 0)
			if l and l >= 1 and c > 0 then
				out[math.floor(l)] = c
			end
		end
	end
	return out
end

-- The highest level among the copies (0 if none).
function CardLevels.best(levels)
	local best = 0
	for l, c in pairs(levels or {}) do
		if c > 0 and l > best then
			best = l
		end
	end
	return best
end

-- The levels of the `k` best copies, highest first: what a deck with k copies plays.
function CardLevels.top(levels, k)
	local out = {}
	local ls = {}
	for l, c in pairs(levels or {}) do
		if c > 0 then
			table.insert(ls, l)
		end
	end
	table.sort(ls, function(a, b)
		return a > b
	end)
	for _, l in ipairs(ls) do
		for _ = 1, levels[l] do
			if #out >= k then
				return out
			end
			table.insert(out, l)
		end
	end
	return out
end

-- How many copies of `id` the saved decks use (the most any one deck uses).
function CardLevels.reserved(decks, id)
	local most = 0
	for _, deck in pairs(decks or {}) do
		if type(deck) == "table" and type(deck.cards) == "table" then
			local n = 0
			for _, c in ipairs(deck.cards) do
				if c == id then
					n += 1
				end
			end
			most = math.max(most, n)
		end
	end
	return most
end

-- Can two copies at `level` fuse? Returns ok, why-not.
function CardLevels.canFuse(id, levels, level, reserved)
	level = math.floor(tonumber(level) or 0)
	if level ~= level then
		level = 0 -- (NaN)
	end
	if not def(id) then
		return false, "Unknown card"
	end
	if level < 1 or level >= CardLevels.maxLevel(id) then
		return false, "That's its highest level"
	end
	if (levels[level] or 0) < 2 then
		return false, "You need 2 copies at level " .. level
	end
	if CardLevels.total(levels) - 1 < (reserved or 0) then
		return false, "Your decks use " .. reserved .. " copies of it: open more to fuse"
	end
	return true
end

-- Fuses two copies at `level` into one a level higher (changes `levels`).
function CardLevels.fuse(levels, level)
	levels[level] -= 2
	if levels[level] == 0 then
		levels[level] = nil
	end
	levels[level + 1] = (levels[level + 1] or 0) + 1
end

-- Can one copy at `level` be sold? Returns ok, why-not.
function CardLevels.canSell(id, levels, level, reserved)
	level = math.floor(tonumber(level) or 0)
	if level ~= level then
		level = 0 -- (NaN)
	end
	if not def(id) then
		return false, "Unknown card"
	end
	if (levels[level] or 0) < 1 then
		return false, "You have no copy at level " .. level
	end
	if CardLevels.total(levels) - 1 < (reserved or 0) then
		return false, "Your decks use " .. reserved .. " copies of it"
	end
	-- the copies a deck plays are the best ones: don't sell one of those
	local keep = CardLevels.top(levels, reserved or 0)
	local inDecks = 0
	for _, l in ipairs(keep) do
		if l == level then
			inDecks += 1
		end
	end
	if levels[level] - inDecks < 1 then
		return false, "That copy plays in your decks"
	end
	return true
end

function CardLevels.sell(levels, level)
	levels[level] -= 1
	if levels[level] == 0 then
		levels[level] = nil
	end
end

-- Fuses everything it can, lowest levels first, keeping `reserved` copies. Changes `levels` and
-- returns how many fuses happened and the levels reached, in order (for the animation).
function CardLevels.fuseAll(id, levels, reserved)
	local made = {}
	local max = CardLevels.maxLevel(id)
	local changed = true
	while changed do
		changed = false
		for l = 1, max - 1 do
			if CardLevels.canFuse(id, levels, l, reserved) then
				CardLevels.fuse(levels, l)
				table.insert(made, l + 1)
				changed = true
				break
			end
		end
	end
	return #made, made
end

return CardLevels

-- Trade: the rules for trading cards with another player at the Park's Trading Post. Cards only:
-- no Gems, no Coins. Pure Luau (no Roblox parts): the server (TradeDesk), the trade window
-- (TradeUI) and the tests all use these rules.
--
-- An offer is a list of copies: { { id = cardId, level = n }, ... }, at most MaxOffer of them.
--
-- What you can offer
--   Any copy you own, except the ones your saved decks play. This is the same rule as selling
--   (CardLevels.canSell): a deck with k copies of a card plays your k best copies, and those stay
--   with you, so a deck that was ready to play is still ready after a trade.
--
-- What you can take
--   A trade that leaves you with more cards than before has to fit in your storage
--   (CardLevels.StorageLimit, plus the save's storageBonus). A trade that doesn't add cards always
--   fits, even when you're over the limit.
--
-- Who can trade
--   Both players are level MinLevel or more, and each has made fewer than MaxPerDay trades today
--   (UTC). Both make it slow to feed one account from many new ones.
--
-- One side may offer nothing (a gift). Both sides empty isn't a trade.
--
-- Save: d.trades = { day = utc day, count = trades made that day }, and d.stats.trades (all time).

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")
local CardLevels = req("CardLevels")

local Trade = {}

Trade.MaxOffer = 6 -- cards each player can put in one trade
Trade.MinLevel = 3 -- the level you need to trade
Trade.MaxPerDay = 10 -- trades one player can make in a UTC day
Trade.ConfirmDelay = 3 -- seconds both offers stay on show before "Confirm" works
Trade.InviteSeconds = 20 -- how long a request to trade waits for an answer
Trade.DeclineCooldown = 30 -- seconds before you can ask someone again who said no
Trade.IdleSeconds = 300 -- a trade nobody touches for this long is called off
Trade.Radius = 30 -- studs from the Trading Post's desk: both players stay this close

local RANK = {}
for i, r in ipairs(CardData.Rarities) do
	RANK[r] = i
end

function Trade.day(now)
	return math.floor((now or os.time()) / 86400)
end

local function def(id)
	return type(id) == "string" and CardData.Cards[id] or nil
end

local function nameOf(id)
	local c = def(id)
	return c and c.name or tostring(id)
end

-- A card's copies by level, from the save (like EconomyManager's levelsOf, without changing d).
local function levelsOf(d, id)
	local saved = type(d.cardLevels) == "table" and d.cardLevels[id] or nil
	return CardLevels.normalize(id, CardLevels.fromList(saved), (type(d.collection) == "table" and d.collection[id]) or 0)
end

local function setLevels(d, id, levels)
	local total = CardLevels.total(levels)
	d.collection = type(d.collection) == "table" and d.collection or {}
	d.cardLevels = type(d.cardLevels) == "table" and d.cardLevels or {}
	if total > 0 then
		d.collection[id] = total
		d.cardLevels[id] = CardLevels.toList(levels)
	else
		d.collection[id] = nil
		d.cardLevels[id] = nil
	end
end

-- Copies kept (every card, every level) and the storage limit.
function Trade.kept(d)
	local n = 0
	for _, c in pairs(type(d.collection) == "table" and d.collection or {}) do
		n += c
	end
	return n
end

function Trade.limit(d)
	return CardLevels.StorageLimit + math.max(0, math.floor(tonumber(d.storageBonus) or 0))
end

-- Trades made today.
function Trade.today(d, now)
	local t = type(d.trades) == "table" and d.trades or nil
	if t and t.day == Trade.day(now) then
		return math.max(0, math.floor(tonumber(t.count) or 0))
	end
	return 0
end

-- May this save trade at all right now? Returns true, or false and "level" / "daily".
function Trade.eligible(d, now)
	if (tonumber(d.level) or 1) < Trade.MinLevel then
		return false, "level"
	end
	if Trade.today(d, now) >= Trade.MaxPerDay then
		return false, "daily"
	end
	return true
end

-- A clean copy of an offer that came over the network: { { id, level }, ... }, or nil and why.
function Trade.cleanOffer(raw)
	if type(raw) ~= "table" then
		return nil, "That isn't an offer."
	end
	if #raw > Trade.MaxOffer then
		return nil, "You can offer up to " .. Trade.MaxOffer .. " cards."
	end
	local out = {}
	for i = 1, #raw do
		local o = raw[i]
		local c = type(o) == "table" and def(o.id) or nil
		local level = type(o) == "table" and o.level or nil
		if not c or c.token then
			return nil, "That card can't be traded."
		end
		if type(level) ~= "number" or level ~= level or level % 1 ~= 0 or level < 1 or level > CardLevels.maxLevel(o.id) then
			return nil, "That card can't be traded."
		end
		out[i] = { id = o.id, level = level }
	end
	return out
end

-- Are two clean offers the same cards in the same order?
function Trade.sameOffer(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i].id ~= b[i].id or a[i].level ~= b[i].level then
			return false
		end
	end
	return true
end

-- Can this save give every copy in the (clean) offer? Returns true, or false and why.
function Trade.checkOffer(d, offer)
	local sims = {}
	for _, o in ipairs(offer) do
		local levels = sims[o.id]
		if not levels then
			levels = levelsOf(d, o.id)
			sims[o.id] = levels
		end
		local ok, why = CardLevels.canSell(o.id, levels, o.level, CardLevels.reserved(d.decks, o.id))
		if not ok then
			return false, nameOf(o.id) .. ": " .. tostring(why)
		end
		CardLevels.sell(levels, o.level)
	end
	return true
end

-- Every copy this save could offer: { { id, level, count }, ... }, rarest first (then by name,
-- then the highest level first).
function Trade.tradable(d)
	local out = {}
	for id, n in pairs(type(d.collection) == "table" and d.collection or {}) do
		local c = def(id)
		if c and not c.token and n > 0 then
			local levels = levelsOf(d, id)
			local inDecks = {}
			for _, l in ipairs(CardLevels.top(levels, CardLevels.reserved(d.decks, id))) do
				inDecks[l] = (inDecks[l] or 0) + 1
			end
			for l, copies in pairs(levels) do
				local free = copies - (inDecks[l] or 0)
				if free > 0 then
					table.insert(out, { id = id, level = l, count = free })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = RANK[def(a.id).rarity] or 0, RANK[def(b.id).rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		if a.id ~= b.id then
			local na, nb = nameOf(a.id), nameOf(b.id)
			if na ~= nb then
				return na < nb
			end
			return a.id < b.id
		end
		return a.level > b.level
	end)
	return out
end

-- Would the swap work right now? A gives offerA and gets offerB; B the other way round.
-- Returns true, or false, why, and whose side the problem is on ("a", "b" or nil for both).
function Trade.canSwap(dA, offerA, dB, offerB)
	if #offerA + #offerB == 0 then
		return false, "Nobody has put a card in yet.", nil
	end
	local ok, why = Trade.checkOffer(dA, offerA)
	if not ok then
		return false, why, "a"
	end
	ok, why = Trade.checkOffer(dB, offerB)
	if not ok then
		return false, why, "b"
	end
	if #offerB > #offerA and Trade.kept(dA) - #offerA + #offerB > Trade.limit(dA) then
		return false, "no room for " .. (#offerB - #offerA) .. " more card" .. (#offerB - #offerA == 1 and "" or "s"), "a"
	end
	if #offerA > #offerB and Trade.kept(dB) - #offerB + #offerA > Trade.limit(dB) then
		return false, "no room for " .. (#offerA - #offerB) .. " more card" .. (#offerA - #offerB == 1 and "" or "s"), "b"
	end
	return true
end

local function take(d, offer)
	for _, o in ipairs(offer) do
		local levels = levelsOf(d, o.id)
		CardLevels.sell(levels, o.level)
		setLevels(d, o.id, levels)
	end
end

local function give(d, offer)
	for _, o in ipairs(offer) do
		local levels = levelsOf(d, o.id)
		levels[o.level] = (levels[o.level] or 0) + 1
		setLevels(d, o.id, levels)
	end
end

local function note(d, now)
	local day = Trade.day(now)
	local t = type(d.trades) == "table" and d.trades or {}
	if t.day ~= day then
		t.day = day
		t.count = 0
	end
	t.count = math.max(0, math.floor(tonumber(t.count) or 0)) + 1
	d.trades = t
	if type(d.stats) == "table" then
		d.stats.trades = (tonumber(d.stats.trades) or 0) + 1
	end
end

-- Does the swap (checks it first; nothing changes unless all of it can). Both saves are changed
-- in one go, with no waiting in between. Returns true, or false, why, side (see canSwap).
function Trade.swap(dA, offerA, dB, offerB, now)
	local ok, why, side = Trade.canSwap(dA, offerA, dB, offerB)
	if not ok then
		return false, why, side
	end
	take(dA, offerA)
	take(dB, offerB)
	give(dA, offerB)
	give(dB, offerA)
	note(dA, now)
	note(dB, now)
	return true
end

-- "Bonk, 2 × Jelly Knight (Lv 2)": an offer in words (for toasts).
function Trade.describe(offer)
	local order, count = {}, {}
	for _, o in ipairs(offer) do
		local key = nameOf(o.id) .. (o.level > 1 and (" (Lv " .. o.level .. ")") or "")
		if not count[key] then
			count[key] = 0
			table.insert(order, key)
		end
		count[key] += 1
	end
	local bits = {}
	for _, key in ipairs(order) do
		table.insert(bits, (count[key] > 1 and (count[key] .. " × ") or "") .. key)
	end
	return table.concat(bits, ", ")
end

return Trade

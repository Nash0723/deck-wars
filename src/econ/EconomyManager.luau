-- EconomyManager: the player's saved profile and everything that changes it. Server only.
--
--   Gems  (premium, for packs)   Coins (earned by playing, for the Shop)
--
-- Other server scripts find it with ServerStorage:FindFirstChild("EconomyManager", true) and use:
--   EconomyManager.getBalance(player, "Gems" | "Coins") -> number
--   EconomyManager.trySpend(player, currency, amount, reason) -> boolean  (checks and pays in one go)
--   EconomyManager.grant(player, currency, amount, reason) -> boolean
--   EconomyManager.grantCards(player, { cardId, ... }) -> isNew { bool }, counts { number }, uniqueOwned
--   EconomyManager.getCollection(player) -> { [cardId] = count } (a copy)
--   EconomyManager.ownsCard(player, cardId) -> count
--   EconomyManager.takePullLuck(player) -> multiplier (1 = no Luck booster; uses one charge)
--   EconomyManager.getDeckSlots(player) -> number
--   EconomyManager.waitForData(player) -> the live saved table (or nil); then markDirty(player)
--   EconomyManager.matchReward(player, { result, difficulty, seconds, turns }) -> reward summary
-- Every function that needs the save yields (up to LoadTimeout seconds) until it has loaded.
-- Balances are also mirrored as Player attributes "Gems", "Coins" and "Level" for client UIs.
--
-- EconomyServer.server.luau calls EconomyManager.init(...) and handles joining/leaving, the Shop
-- remote and Robux receipts. The tests call init with a fake clock and a memory store.

local function req(name)
	if script then
		local rs = game:GetService("ReplicatedStorage")
		local own = script.Parent:FindFirstChild(name)
		if own then
			return require(own)
		end
		return require(rs:WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")
local ShopCatalog = req("ShopCatalog")
local ProfileStore = req("ProfileStore")

local EconomyManager = {}

EconomyManager.LoadTimeout = 15
EconomyManager.MaxCardCopies = 999
EconomyManager.ReceiptHistory = 100 -- PurchaseIds kept to make Robux purchases idempotent

local FIELD = { Gems = "gems", Coins = "coins" }

-- The save of a brand new player. New fields can be added here at any time: older saves get
-- them filled in on load (ProfileStore.reconcile).
EconomyManager.Template = {
	version = 1,
	gems = ShopCatalog.StartingGems,
	coins = ShopCatalog.StartingCoins,
	xp = 0,
	level = 1,
	collection = {}, -- [cardId] = copies owned
	decks = {}, -- saved decks (filled by the deck builder)
	deckSlots = ShopCatalog.DeckSlots.start,
	flags = {}, -- one-off flags, e.g. starterGranted
	cosmetics = {
		owned = {}, -- [cosmeticId] = true (default items are always owned)
		equipped = { board = ShopCatalog.DefaultEquipped.board, cardback = ShopCatalog.DefaultEquipped.cardback, backdrop = ShopCatalog.DefaultEquipped.backdrop },
	},
	boosts = { luckCharges = 0, xpUntil = 0 },
	daily = {
		loginDay = -1, -- UTC day of the last daily login reward
		streak = 0,
		day = -1, -- UTC day the counters below belong to
		bought = {}, -- ["s<slot>"] = true for daily cards bought today
		exchanges = {}, -- [exchangeId] = times today
		paidMatches = 0,
		firstWin = false,
	},
	stats = { wins = 0, losses = 0, draws = 0, packsOpened = 0, cardsPulled = 0, gemsSpent = 0, coinsSpent = 0, coinsEarned = 0, robuxSpent = 0 },
	receipts = {}, -- recent Robux PurchaseIds, oldest first
	created = 0,
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local deps = {
	clock = os.time,
	wait = function(t)
		return task.wait(t)
	end,
	warn = function(...)
		warn(...)
	end,
	onChanged = nil, -- function(player, reason) after any change (EconomyServer pushes a snapshot)
	isDev = function()
		return false
	end,
}
local store = nil -- ProfileStore
local profiles = {} -- [player] = profile
local loading = {} -- [player] = true while loading
local failed = {} -- [player] = reason when loading failed

function EconomyManager.init(opts)
	opts = opts or {}
	for k, v in pairs(opts) do
		if k ~= "dataStore" then
			deps[k] = v
		end
	end
	store = ProfileStore.new(opts.dataStore or ProfileStore.memoryStore(), {
		template = EconomyManager.Template,
		jobId = opts.jobId,
		clock = deps.clock,
		wait = deps.wait,
		warn = deps.warn,
		memoryOnly = opts.memoryOnly,
		staleSeconds = opts.staleSeconds,
		loadAttempts = opts.loadAttempts,
		retryDelay = opts.retryDelay,
	})
	EconomyManager.memoryOnly = opts.memoryOnly or false
	return store
end

function EconomyManager.store()
	return store
end

local function today()
	return ShopCatalog.dayNumber(deps.clock())
end

-- A whole number from 1 to 1e9 (no NaN, no infinity, no fractions, no negatives).
local function validAmount(n)
	return type(n) == "number" and n == n and n >= 1 and n <= 1e9 and n % 1 == 0
end
EconomyManager.validAmount = validAmount

local function keyFor(player)
	return "u" .. tostring(player.UserId)
end

local function data(player)
	local p = profiles[player]
	return p and p:isActive() and p.Data or nil
end

local function mirror(player)
	local d = data(player)
	if d and typeof(player) == "Instance" then
		pcall(function()
			player:SetAttribute("Gems", d.gems)
			player:SetAttribute("Coins", d.coins)
			player:SetAttribute("Level", d.level)
		end)
	end
end

local function changed(player, reason)
	mirror(player)
	if deps.onChanged then
		deps.onChanged(player, reason)
	end
end

-- New UTC day: the daily shop, exchange limits and match counters start over.
local function rollDay(d)
	local t = today()
	if d.daily.day ~= t then
		d.daily.day = t
		d.daily.bought = {}
		d.daily.exchanges = {}
		d.daily.paidMatches = 0
		d.daily.firstWin = false
	end
end

---------------------------------------------------------------------------
-- Loading and leaving
---------------------------------------------------------------------------

-- Loads the player's save (yields). Returns the profile, or nil and "locked" / "error".
function EconomyManager.load(player)
	assert(store, "EconomyManager.init first")
	if profiles[player] then
		return profiles[player]
	end
	loading[player] = true
	failed[player] = nil
	local profile, why = store:load(keyFor(player))
	loading[player] = nil
	if not profile then
		failed[player] = why or "error"
		return nil, failed[player]
	end
	if typeof(player) == "Instance" and player.Parent == nil then
		-- left while we were loading
		profile:release()
		failed[player] = "left"
		return nil, "left"
	end
	local d = profile.Data
	if (d.created or 0) == 0 then
		d.created = deps.clock()
	end
	-- keep the numbers sane even if a save was edited by hand
	for _, f in pairs(FIELD) do
		if type(d[f]) ~= "number" or d[f] ~= d[f] or d[f] < 0 then
			d[f] = 0
		end
		d[f] = math.min(math.floor(d[f]), ShopCatalog.MaxBalance)
	end
	rollDay(d)
	profiles[player] = profile
	profile:onStolen(function()
		if profiles[player] == profile then
			profiles[player] = nil
			if deps.onStolen then
				deps.onStolen(player)
			end
		end
	end)
	mirror(player)
	return profile
end

-- Last save and unlock (when the player leaves).
function EconomyManager.unload(player)
	local p = profiles[player]
	profiles[player] = nil
	failed[player] = nil
	if p then
		return p:release()
	end
	return true
end

function EconomyManager.isLoaded(player)
	return data(player) ~= nil
end

-- The live saved table (yields until loaded). Change it, then call markDirty(player).
function EconomyManager.waitForData(player, timeout)
	local limit = timeout or EconomyManager.LoadTimeout
	local waited = 0
	while not data(player) and waited < limit do
		if not loading[player] and failed[player] then
			return nil
		end
		deps.wait(0.1)
		waited += 0.1
	end
	return data(player)
end

-- Tells clients something in the save changed (saving itself happens on the autosave).
function EconomyManager.markDirty(player, reason)
	if data(player) then
		changed(player, reason or "data")
	end
end

-- Saves this player's profile right now (yields). Used after Robux purchases.
function EconomyManager.saveNow(player)
	local p = profiles[player]
	if not p then
		return false, "not loaded"
	end
	return p:save()
end

---------------------------------------------------------------------------
-- Currencies
---------------------------------------------------------------------------

function EconomyManager.getBalance(player, currency)
	local f = FIELD[currency]
	if not f then
		return 0
	end
	local d = EconomyManager.waitForData(player)
	return d and d[f] or 0
end

-- Pays `amount` of `currency` if the player has it. Returns true when paid.
-- The check and the payment happen together without yielding, so two requests at the same
-- time can't both spend the same Gems.
function EconomyManager.trySpend(player, currency, amount, reason)
	local f = FIELD[currency]
	if not f or not validAmount(amount) then
		return false
	end
	local d = EconomyManager.waitForData(player)
	if not d or d[f] < amount then
		return false
	end
	d[f] -= amount
	if currency == "Gems" then
		d.stats.gemsSpent += amount
	else
		d.stats.coinsSpent += amount
	end
	changed(player, reason or "spend")
	return true
end

-- Gives `amount` of `currency` (capped at ShopCatalog.MaxBalance). Returns true when given.
function EconomyManager.grant(player, currency, amount, reason)
	local f = FIELD[currency]
	if not f or not validAmount(amount) then
		return false
	end
	local d = EconomyManager.waitForData(player)
	if not d then
		return false
	end
	d[f] = math.min(ShopCatalog.MaxBalance, d[f] + amount)
	if currency == "Coins" then
		d.stats.coinsEarned += amount
	end
	changed(player, reason or "grant")
	return true
end

-- Pays a price table like { Coins = 600 } (no yielding: call after waitForData).
local function payPrice(d, price)
	local cur, amount = ShopCatalog.priceOf(price)
	if not cur or not validAmount(amount) then
		return false, "This item has no price."
	end
	local f = FIELD[cur]
	if d[f] < amount then
		return false, "Not enough " .. cur .. "."
	end
	d[f] -= amount
	if cur == "Gems" then
		d.stats.gemsSpent += amount
	else
		d.stats.coinsSpent += amount
	end
	return true
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------

local function addCards(d, ids)
	local isNew, counts = {}, {}
	for i, id in ipairs(ids) do
		if type(id) == "string" and CardData.Cards[id] then
			local had = d.collection[id] or 0
			isNew[i] = had == 0
			d.collection[id] = math.min(EconomyManager.MaxCardCopies, had + 1)
			counts[i] = d.collection[id]
		else
			isNew[i] = false
			counts[i] = 0
		end
	end
	local unique = 0
	for _ in pairs(d.collection) do
		unique += 1
	end
	return isNew, counts, unique
end

-- Adds cards to the saved collection. Returns isNew, counts (new totals) and how many
-- different cards the player owns. Unknown ids are skipped (isNew false, count 0).
function EconomyManager.grantCards(player, ids, reason)
	if type(ids) ~= "table" then
		return {}, {}, 0
	end
	local d = EconomyManager.waitForData(player)
	if not d then
		return {}, {}, 0
	end
	local isNew, counts, unique = addCards(d, ids)
	if reason == "pull" or reason == nil then
		d.stats.cardsPulled += #ids
		d.stats.packsOpened += 1
	end
	changed(player, "cards")
	return isNew, counts, unique
end

function EconomyManager.getCollection(player)
	local d = EconomyManager.waitForData(player)
	return d and ProfileStore.deepCopy(d.collection) or {}
end

function EconomyManager.ownsCard(player, id)
	local d = EconomyManager.waitForData(player)
	return d and (d.collection[id] or 0) or 0
end

function EconomyManager.getDeckSlots(player)
	local d = EconomyManager.waitForData(player)
	return d and d.deckSlots or ShopCatalog.DeckSlots.start
end

-- Call once per PAID pack opening (a 10-pack counts as one). Returns the luck multiplier to
-- use for that opening (PullRates.luckyOdds(mult)), and uses up one Luck charge if there is one.
function EconomyManager.takePullLuck(player)
	local d = EconomyManager.waitForData(player)
	if not d or (d.boosts.luckCharges or 0) <= 0 then
		return 1
	end
	d.boosts.luckCharges -= 1
	changed(player, "luck")
	return ShopCatalog.LuckMultiplier
end

---------------------------------------------------------------------------
-- XP, levels, daily login, match rewards
---------------------------------------------------------------------------

-- Adds XP and handles level ups. Returns the levels gained.
local function addXp(d, amount)
	local gained = 0
	d.xp += amount
	while d.level < ShopCatalog.MaxLevel and d.xp >= ShopCatalog.xpForLevel(d.level) do
		d.xp -= ShopCatalog.xpForLevel(d.level)
		d.level += 1
		gained += 1
		d.gems = math.min(ShopCatalog.MaxBalance, d.gems + ShopCatalog.LevelUpGems)
		d.coins = math.min(ShopCatalog.MaxBalance, d.coins + ShopCatalog.LevelUpCoins)
	end
	if d.level >= ShopCatalog.MaxLevel then
		d.xp = 0
	end
	return gained
end

-- The daily login reward, once per UTC day. Returns { coins, gems, streak } or nil if already
-- claimed today. EconomyServer calls it when the player joins.
function EconomyManager.claimDaily(player)
	local d = EconomyManager.waitForData(player)
	if not d then
		return nil
	end
	rollDay(d)
	local t = today()
	if d.daily.loginDay == t then
		return nil
	end
	local D = ShopCatalog.Daily
	if d.daily.loginDay == t - 1 then
		d.daily.streak = math.min(D.maxStreak, d.daily.streak + 1)
	else
		d.daily.streak = 1
	end
	d.daily.loginDay = t
	local coins = D.coins + D.coinsPerStreakDay * (d.daily.streak - 1)
	local gems = D.gems + ((d.daily.streak >= D.maxStreak) and D.streakBonusGems or 0)
	d.coins = math.min(ShopCatalog.MaxBalance, d.coins + coins)
	d.gems = math.min(ShopCatalog.MaxBalance, d.gems + gems)
	d.stats.coinsEarned += coins
	changed(player, "daily")
	return { coins = coins, gems = gems, streak = d.daily.streak }
end

local function xpBoostActive(d)
	return (d.boosts.xpUntil or 0) > deps.clock()
end

-- Pays for a finished bot match. info = { result = "win" | "loss" | "draw", difficulty,
-- seconds = how long it lasted, turns = how many turns the player took }.
-- Returns { coins, xp, gems, levels, boosted, note } (all zero with a note when it doesn't pay).
function EconomyManager.matchReward(player, info)
	local out = { coins = 0, xp = 0, gems = 0, levels = 0, boosted = false, note = nil }
	local d = EconomyManager.waitForData(player)
	if not d or type(info) ~= "table" then
		out.note = "not loaded"
		return out
	end
	rollDay(d)
	local M = ShopCatalog.Match
	local diff = M.winCoins[info.difficulty] and info.difficulty or "Easy"
	local result = info.result
	if result == "win" then
		d.stats.wins += 1
	elseif result == "loss" then
		d.stats.losses += 1
	elseif result == "draw" then
		d.stats.draws += 1
	else
		out.note = "no result"
		return out
	end
	if (tonumber(info.seconds) or 0) < M.minSeconds or (tonumber(info.turns) or 0) < M.minTurns then
		out.note = "too short"
		changed(player, "match")
		return out
	end
	if d.daily.paidMatches >= M.maxPaidPerDay then
		out.note = "daily limit"
		changed(player, "match")
		return out
	end
	d.daily.paidMatches += 1
	local win = result == "win"
	out.coins = win and M.winCoins[diff] or M.lossCoins[diff]
	out.xp = win and M.winXp[diff] or M.lossXp[diff]
	if xpBoostActive(d) then
		out.xp *= 2
		out.boosted = true
	end
	if win and not d.daily.firstWin then
		d.daily.firstWin = true
		out.gems = M.firstWinGems
		out.firstWin = true
	end
	d.coins = math.min(ShopCatalog.MaxBalance, d.coins + out.coins)
	d.gems = math.min(ShopCatalog.MaxBalance, d.gems + out.gems)
	d.stats.coinsEarned += out.coins
	out.levels = addXp(d, out.xp)
	if out.levels > 0 then
		out.levelGems = ShopCatalog.LevelUpGems * out.levels
		out.levelCoins = ShopCatalog.LevelUpCoins * out.levels
	end
	changed(player, "match")
	return out
end

---------------------------------------------------------------------------
-- The Shop
---------------------------------------------------------------------------

local function ownsCosmetic(d, id)
	local c = ShopCatalog.CosmeticById[id]
	return c ~= nil and (c.default or d.cosmetics.owned[id] == true)
end

-- Buys something. kind / id:
--   "card", slot number        a card from today's rotation (once per slot per day)
--   "cosmetic", cosmeticId     a board theme, card back or emote (board/card back get equipped)
--   "deckslot", nil            one more deck slot
--   "exchange", exchangeId     Coins <-> Gems (some are limited per day)
--   "boost", boostId           Luck / XP boosters
-- Returns ok, message, extra (for cards: { id, isNew, count }).
function EconomyManager.buy(player, kind, id)
	local d = EconomyManager.waitForData(player)
	if not d then
		return false, "Your save hasn't loaded yet."
	end
	rollDay(d)
	if kind == "card" then
		local slot = tonumber(id)
		local offer = nil
		for _, o in ipairs(ShopCatalog.dailyCards(today())) do
			if o.slot == slot then
				offer = o
			end
		end
		if not offer then
			return false, "That card isn't in today's shop."
		end
		local key = "s" .. offer.slot
		if d.daily.bought[key] then
			return false, "You already bought that one today."
		end
		local ok, why = payPrice(d, { Coins = offer.price })
		if not ok then
			return false, why
		end
		d.daily.bought[key] = true
		local isNew, counts = addCards(d, { offer.id })
		changed(player, "buy")
		return true, "Bought " .. CardData.Cards[offer.id].name .. "!", { id = offer.id, isNew = isNew[1], count = counts[1] }
	elseif kind == "cosmetic" then
		local c = type(id) == "string" and ShopCatalog.CosmeticById[id]
		if not c then
			return false, "Unknown item."
		end
		if ownsCosmetic(d, c.id) then
			return false, "You already own " .. c.name .. "."
		end
		if c.road or not c.price then
			return false, c.name .. " is a Trophy Road reward. Win matches to earn it!"
		end
		local ok, why = payPrice(d, c.price)
		if not ok then
			return false, why
		end
		d.cosmetics.owned[c.id] = true
		if ShopCatalog.EquipKinds[c.kind] then
			d.cosmetics.equipped[c.kind] = c.id
		end
		changed(player, "buy")
		return true, "Unlocked " .. c.name .. "!"
	elseif kind == "deckslot" then
		local S = ShopCatalog.DeckSlots
		if d.deckSlots >= S.max then
			return false, "You have the most deck slots already (" .. S.max .. ")."
		end
		local ok, why = payPrice(d, S.price)
		if not ok then
			return false, why
		end
		d.deckSlots += 1
		changed(player, "buy")
		return true, "You now have " .. d.deckSlots .. " deck slots."
	elseif kind == "exchange" then
		local e = type(id) == "string" and ShopCatalog.ExchangeById[id]
		if not e then
			return false, "Unknown exchange."
		end
		local used = d.daily.exchanges[e.id] or 0
		if e.perDay and used >= e.perDay then
			return false, "No more of these today. Come back tomorrow!"
		end
		local ok, why = payPrice(d, e.give)
		if not ok then
			return false, why
		end
		local cur, amount = ShopCatalog.priceOf(e.get)
		d[FIELD[cur]] = math.min(ShopCatalog.MaxBalance, d[FIELD[cur]] + amount)
		d.daily.exchanges[e.id] = used + 1
		changed(player, "buy")
		return true, "+" .. ShopCatalog.format(amount) .. " " .. cur
	elseif kind == "boost" then
		local b = type(id) == "string" and ShopCatalog.BoostById[id]
		if not b then
			return false, "Unknown booster."
		end
		if b.kind == "luck" and d.boosts.luckCharges + b.charges > ShopCatalog.MaxLuckCharges then
			return false, "You can hold at most " .. ShopCatalog.MaxLuckCharges .. " lucky pulls."
		end
		local now = deps.clock()
		local xpFrom = math.max(now, d.boosts.xpUntil or 0)
		if b.kind == "xp" and xpFrom + b.minutes * 60 - now > ShopCatalog.MaxXpBoostMinutes * 60 then
			return false, "That's more XP boost than you can stack (24 hours)."
		end
		local ok, why = payPrice(d, b.price)
		if not ok then
			return false, why
		end
		if b.kind == "luck" then
			d.boosts.luckCharges += b.charges
		else
			d.boosts.xpUntil = xpFrom + b.minutes * 60
		end
		changed(player, "buy")
		return true, b.name .. " is on!"
	end
	return false, "Unknown purchase."
end

-- Gives a cosmetic for free (Trophy Road rewards). Returns true if it was new.
function EconomyManager.grantCosmetic(player, id)
	local d = EconomyManager.waitForData(player)
	local c = type(id) == "string" and ShopCatalog.CosmeticById[id]
	if not d or not c then
		return false
	end
	if ownsCosmetic(d, id) then
		return false
	end
	d.cosmetics.owned[id] = true
	changed(player, "grant")
	return true
end

-- Equips an owned board theme, card back or match background.
function EconomyManager.equip(player, kind, id)
	local d = EconomyManager.waitForData(player)
	if not d then
		return false, "Your save hasn't loaded yet."
	end
	local c = type(id) == "string" and ShopCatalog.CosmeticById[id]
	if not c or c.kind ~= kind or not ShopCatalog.EquipKinds[kind] then
		return false, "You can't equip that."
	end
	if not ownsCosmetic(d, id) then
		return false, "You don't own " .. c.name .. " yet."
	end
	d.cosmetics.equipped[kind] = id
	changed(player, "equip")
	return true, c.name .. " equipped."
end

function EconomyManager.ownsCosmetic(player, id)
	local d = EconomyManager.waitForData(player)
	return d ~= nil and ownsCosmetic(d, id)
end

-- What the client's Shop and HUD need (no other player's data, nothing secret).
function EconomyManager.snapshot(player)
	local d = data(player)
	if not d then
		return nil
	end
	rollDay(d)
	local now = deps.clock()
	local owned = {}
	for _, c in ipairs(ShopCatalog.Cosmetics) do
		if ownsCosmetic(d, c.id) then
			owned[c.id] = true
		end
	end
	local unique = 0
	for _ in pairs(d.collection) do
		unique += 1
	end
	local bought = {}
	for k, v in pairs(d.daily.bought) do
		bought[k] = v
	end
	local exchanges = {}
	for k, v in pairs(d.daily.exchanges) do
		exchanges[k] = v
	end
	local dailyOwned = {} -- how many of each of today's shop cards the player has
	for _, o in ipairs(ShopCatalog.dailyCards(d.daily.day)) do
		dailyOwned[o.id] = d.collection[o.id] or 0
	end
	return {
		gems = d.gems,
		coins = d.coins,
		xp = d.xp,
		level = d.level,
		xpNeed = ShopCatalog.xpForLevel(d.level),
		uniqueCards = unique,
		deckSlots = d.deckSlots,
		owned = owned,
		equipped = { board = d.cosmetics.equipped.board, cardback = d.cosmetics.equipped.cardback, backdrop = ownsCosmetic(d, d.cosmetics.equipped.backdrop or "") and d.cosmetics.equipped.backdrop or ShopCatalog.DefaultEquipped.backdrop },
		luckCharges = d.boosts.luckCharges,
		xpBoostLeft = math.max(0, (d.boosts.xpUntil or 0) - now),
		day = d.daily.day,
		bought = bought,
		dailyOwned = dailyOwned,
		exchanges = exchanges,
		paidMatchesLeft = math.max(0, ShopCatalog.Match.maxPaidPerDay - d.daily.paidMatches),
		firstWinLeft = not d.daily.firstWin,
		streak = d.daily.streak,
		resetIn = ShopCatalog.secondsToReset(now),
		serverTime = now,
		memoryOnly = EconomyManager.memoryOnly,
		dev = deps.isDev(player) == true,
	}
end

---------------------------------------------------------------------------
-- Robux: Gem bundles (MarketplaceService.ProcessReceipt)
---------------------------------------------------------------------------

-- Returns the ProductPurchaseDecision. Gems are only granted once per PurchaseId, and the
-- purchase is only confirmed to Roblox after the save with the new Gems went through, so a
-- crash in between makes Roblox ask again instead of losing the Gems.
function EconomyManager.processReceipt(receipt, getPlayer, decisions)
	local granted, notYet = decisions.PurchaseGranted, decisions.NotProcessedYet
	local player = getPlayer(receipt.PlayerId)
	if not player then
		return notYet -- they left; Roblox asks again next time they join
	end
	local bundle = nil
	for _, b in ipairs(ShopCatalog.GemBundles) do
		if b.productId ~= 0 and b.productId == receipt.ProductId then
			bundle = b
		end
	end
	if not bundle then
		deps.warn("EconomyManager: unknown developer product " .. tostring(receipt.ProductId))
		return notYet
	end
	local d = EconomyManager.waitForData(player)
	if not d then
		return notYet
	end
	local pid = tostring(receipt.PurchaseId)
	local seen = false
	for _, r in ipairs(d.receipts) do
		if r == pid then
			seen = true
		end
	end
	if not seen then
		d.gems = math.min(ShopCatalog.MaxBalance, d.gems + bundle.gems + bundle.bonus)
		d.stats.robuxSpent += tonumber(receipt.CurrencySpent) or 0
		table.insert(d.receipts, pid)
		while #d.receipts > EconomyManager.ReceiptHistory do
			table.remove(d.receipts, 1)
		end
		changed(player, "robux")
	end
	local ok = EconomyManager.saveNow(player)
	if not ok then
		return notYet
	end
	return granted
end

---------------------------------------------------------------------------
-- Developer tools (EconomyServer only calls these after DevAccess.isDev said yes)
---------------------------------------------------------------------------

function EconomyManager.devGive(player, currency, amount)
	return EconomyManager.grant(player, currency, amount, "dev")
end

-- Pretend it's a new day: daily cards, exchanges, match limit and the login reward reset.
function EconomyManager.devNewDay(player)
	local d = EconomyManager.waitForData(player)
	if not d then
		return false
	end
	d.daily.day = -1
	d.daily.loginDay = -1
	rollDay(d)
	changed(player, "dev")
	return true
end

function EconomyManager.devLuck(player, charges)
	local d = EconomyManager.waitForData(player)
	if not d then
		return false
	end
	d.boosts.luckCharges = math.clamp(math.floor(tonumber(charges) or 0), 0, ShopCatalog.MaxLuckCharges)
	changed(player, "dev")
	return true
end

-- Wipes the save back to a new player's (keeps the Robux receipt list so old purchases
-- can't be granted twice).
function EconomyManager.devResetSave(player)
	local p = profiles[player]
	if not p or not p:isActive() then
		return false
	end
	local receipts = p.Data.receipts
	local fresh = ProfileStore.deepCopy(EconomyManager.Template)
	for k in pairs(p.Data) do
		p.Data[k] = nil
	end
	for k, v in pairs(fresh) do
		p.Data[k] = v
	end
	p.Data.receipts = receipts
	p.Data.created = deps.clock()
	rollDay(p.Data)
	changed(player, "dev")
	return true
end

return EconomyManager

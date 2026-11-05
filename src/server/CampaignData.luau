-- Campaign progress on the one save (ServerStorage.DeckWarsServer.EconomyManager):
--   d.campaign = {
--     clears = { [stageId] = { stars = 0..7 (one bit per star), wins = n } },
--     chests = { ["<world>:<n>"] = true },          -- star chests already given
--     drops = { day = utc day, count = n },         -- replay drops today
--     challenge = { hour = n },                     -- the last Challenge hour you won
--   }
-- MatchServer asks canPlay before a campaign match and calls record after it. The rules and
-- numbers are in ReplicatedStorage.DeckWars.Campaign.
--
-- CampaignData.apply is the whole reward logic on a plain save table, so the tests can run it
-- without Roblox; record() wraps it with the real save, card grants and the screen update.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local Campaign = require(Shared:WaitForChild("Campaign"))
local CardData = require(Shared:WaitForChild("CardData"))

local CampaignData = {}

local MAX_BALANCE = 1e9
do
	local ok, ShopCatalog = pcall(function()
		return require(Shared:WaitForChild("ShopCatalog", 5))
	end)
	if ok and ShopCatalog and ShopCatalog.MaxBalance then
		MAX_BALANCE = ShopCatalog.MaxBalance
	end
end

local function utcDay(now)
	return math.floor((now or os.time()) / 86400)
end

-- Fills in the campaign table on a save (old saves don't have it).
function CampaignData.ensure(d)
	local c = type(d.campaign) == "table" and d.campaign or {}
	d.campaign = c
	c.clears = type(c.clears) == "table" and c.clears or {}
	c.chests = type(c.chests) == "table" and c.chests or {}
	c.drops = type(c.drops) == "table" and c.drops or { day = -1, count = 0 }
	c.challenge = type(c.challenge) == "table" and c.challenge or { hour = -1 }
	return c
end

-- A random card of a rarity from a weighted list like { { "Rare", 70 }, { "Epic", 25 } }.
local function rollRarity(odds, roll)
	local total = 0
	for _, o in ipairs(odds) do
		total += o[2]
	end
	local x = roll() * total
	for _, o in ipairs(odds) do
		x -= o[2]
		if x < 0 then
			return o[1]
		end
	end
	return odds[#odds][1]
end

-- Any collectible card of a rarity (for the Challenge), picked with `roll`.
local function anyCard(rarity, roll)
	local list = {}
	for _, id in ipairs(CardData.List) do
		local c = CardData.Cards[id]
		if c.rarity == rarity and not c.token then
			table.insert(list, id)
		end
	end
	table.sort(list)
	if #list == 0 then
		return nil
	end
	return list[math.floor(roll() * #list) + 1] or list[#list]
end

-- The rewards for one finished campaign match, applied to save `d`.
--   stage = Campaign.stage(...)
--   r = { result, hp, maxHp, turns }
--   roll = function() -> a number in [0, 1)
--   now = os.time()
-- Returns { stars = {b,b,b}, starsBefore = mask, starsAfter = mask, newStars = n, firstClear,
--   gems = { { label, amount } }, totalGems, cards = { { id, why } }, chests = { { stars, gems, card, title } },
--   titles = { names }, unlocked = { text } }. The caller grants the cards (they're only listed here).
function CampaignData.apply(d, stage, r, roll, now)
	local c = CampaignData.ensure(d)
	local out = { stars = Campaign.starsFor(stage, r), gems = {}, totalGems = 0, cards = {}, chests = {}, titles = {}, unlocked = {}, newStars = 0 }
	local function pay(label, amount)
		amount = math.floor(amount or 0)
		if amount > 0 then
			d.gems = math.min(MAX_BALANCE, (d.gems or 0) + amount)
			out.totalGems += amount
			table.insert(out.gems, { label = label, amount = amount })
		end
	end
	if r.result ~= "win" then
		out.starsBefore = (c.clears[stage.id] and c.clears[stage.id].stars) or 0
		out.starsAfter = out.starsBefore
		return out
	end

	if stage.challenge then
		-- The Challenge pays once per hour.
		out.firstClear = c.challenge.hour ~= stage.hour
		out.starsBefore, out.starsAfter = 0, Campaign.maskOf(out.stars)
		if out.firstClear then
			c.challenge.hour = stage.hour
			pay("Challenge won", stage.firstGems)
			local rarity = rollRarity(Campaign.Challenge.cardOdds, roll)
			local id = anyCard(rarity, roll)
			if id then
				table.insert(out.cards, { id = id, why = "Challenge prize" })
			end
		end
		return out
	end

	local entry = c.clears[stage.id]
	local first = entry == nil or (entry.wins or 0) == 0
	entry = entry or { stars = 0, wins = 0 }
	c.clears[stage.id] = entry
	out.firstClear = first
	out.starsBefore = entry.stars or 0
	local worldStarsBefore = Campaign.worldStars({ clears = c.clears }, stage.world)
	entry.stars = bit32.bor(entry.stars or 0, Campaign.maskOf(out.stars))
	entry.wins = (entry.wins or 0) + 1
	out.starsAfter = entry.stars
	out.newStars = Campaign.countStars(entry.stars) - Campaign.countStars(out.starsBefore)

	if first then
		pay("First clear", stage.firstGems)
		if stage.firstCard then
			table.insert(out.cards, { id = stage.firstCard, why = "First clear" })
		end
		-- what this win opens
		local world = Campaign.WorldByKey[stage.world]
		if stage.boss and not stage.hard then
			local nextWorld = Campaign.Worlds[world.index + 1]
			if nextWorld then
				table.insert(out.unlocked, nextWorld.emoji .. " " .. nextWorld.name .. " is open!")
			end
			table.insert(out.unlocked, "Hard mode in " .. world.name .. " is open!")
			if stage.id == Campaign.Challenge.unlockAfter then
				table.insert(out.unlocked, "The hourly Challenge is open!")
			end
		end
	else
		-- a replay: a chance at a family card, at most DropsPerDay a day
		local today = utcDay(now)
		if c.drops.day ~= today then
			c.drops.day = today
			c.drops.count = 0
		end
		if c.drops.count < Campaign.DropsPerDay then
			local id, why = nil, nil
			if stage.boss and stage.bossCard and not stage.hard and roll() < Campaign.BossLegendaryChance then
				id, why = stage.bossCard, "Boss drop!"
			elseif roll() < Campaign.ReplayDropChance then
				local rarity = roll() < Campaign.ReplayRareShare and "Rare" or "Common"
				local list = Campaign.cardsOf(stage.family, rarity)
				if #list > 0 then
					id, why = list[math.floor(roll() * #list) + 1] or list[1], "Lucky drop"
				end
			end
			if id then
				c.drops.count += 1
				table.insert(out.cards, { id = id, why = why })
			end
		end
	end

	-- star chests: stars from both modes count
	local worldStarsAfter = Campaign.worldStars({ clears = c.clears }, stage.world)
	for n, def in ipairs(Campaign.Chests) do
		local key = stage.world .. ":" .. n
		if worldStarsAfter >= def.stars and not c.chests[key] then
			c.chests[key] = true
			local chest = Campaign.chest(stage.world, n)
			table.insert(out.chests, chest)
			pay(def.stars .. "★ chest", chest.gems)
			if chest.card then
				table.insert(out.cards, { id = chest.card, why = def.stars .. "★ chest" })
			end
			if chest.title then
				table.insert(out.titles, chest.title)
			end
		end
	end
	out.worldStarsBefore, out.worldStarsAfter = worldStarsBefore, worldStarsAfter
	return out
end

-- What the Campaign screen needs: per stage the stars and wins, chests taken, the Challenge.
function CampaignData.snapshotOf(d, now)
	local c = CampaignData.ensure(d)
	local clears = {}
	for id, e in pairs(c.clears) do
		clears[id] = { stars = e.stars or 0, wins = e.wins or 0 }
	end
	local chests = {}
	for k in pairs(c.chests) do
		chests[k] = true
	end
	local hour = Campaign.challengeHour(now)
	return {
		clears = clears,
		chests = chests,
		totalStars = Campaign.totalStars(c),
		challengeHour = hour,
		challengeWon = c.challenge.hour == hour,
		challengeOpen = Campaign.cleared(c, Campaign.Challenge.unlockAfter),
		dropsLeft = math.max(0, Campaign.DropsPerDay - ((c.drops.day == utcDay(now)) and c.drops.count or 0)),
		titles = Campaign.titles(c),
	}
end

---------------------------------------------------------------------------
-- With the real save
---------------------------------------------------------------------------

local Economy = nil
local function economy()
	if Economy == nil then
		local folder = ServerStorage:FindFirstChild("DeckWarsServer")
		local m = folder and folder:FindFirstChild("EconomyManager")
		Economy = m and require(m) or false
	end
	return Economy or nil
end

local function saveOf(player)
	local econ = economy()
	if not econ or not econ.isLoaded(player) then
		return nil
	end
	return econ.waitForData(player, 0)
end

-- Test saves for when there is no EconomyManager in the place (like the Pack Brawl test place).
local memory = {}
local function data(player)
	local d = saveOf(player)
	if d then
		return d
	end
	if economy() then
		return nil -- the real save is still loading
	end
	memory[player] = memory[player] or { gems = 0, coins = 0, collection = {} }
	return memory[player]
end
CampaignData.dataOf = data

function CampaignData.snapshot(player)
	local d = data(player)
	if not d then
		return nil
	end
	return CampaignData.snapshotOf(d)
end

function CampaignData.canPlay(player, id)
	local d = data(player)
	if not d then
		return false, "Your save is still loading."
	end
	return Campaign.canPlay(CampaignData.ensure(d), id)
end

-- Stars in the whole Campaign (for the leaderboard and nameplates).
function CampaignData.totalStars(player)
	local d = data(player)
	return d and Campaign.totalStars(CampaignData.ensure(d)) or 0
end

function CampaignData.titles(player)
	local d = data(player)
	return d and Campaign.titles(CampaignData.ensure(d)) or {}
end

local rng = Random.new(os.time() % 100000 + 7)

-- After a campaign match. Returns the result for the result screen (see apply), with each card's
-- isNew filled in, or nil when the save isn't there.
function CampaignData.record(player, stage, r)
	local d = data(player)
	if not d then
		return nil
	end
	local out = CampaignData.apply(d, stage, r, function()
		return rng:NextNumber()
	end, os.time())
	local ids = {}
	for _, card in ipairs(out.cards) do
		table.insert(ids, card.id)
	end
	local econ = economy()
	if #ids > 0 then
		if econ then
			local ok, isNew = pcall(econ.grantCards, player, ids, "campaign")
			if ok and type(isNew) == "table" then
				for i, card in ipairs(out.cards) do
					card.isNew = isNew[i] == true
				end
			end
		else
			d.collection = d.collection or {}
			for _, card in ipairs(out.cards) do
				card.isNew = (d.collection[card.id] or 0) == 0
				d.collection[card.id] = (d.collection[card.id] or 0) + 1
			end
		end
	end
	if econ then
		econ.markDirty(player, "campaign")
	end
	pcall(function()
		player:SetAttribute("CampaignStars", Campaign.totalStars(CampaignData.ensure(d)))
		if econ == nil then
			player:SetAttribute("Gems", d.gems)
		end
	end)
	out.snapshot = CampaignData.snapshotOf(d)
	return out
end

function CampaignData.forget(player)
	memory[player] = nil
end

return CampaignData

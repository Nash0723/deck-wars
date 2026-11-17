-- QuestBook: the Quest Hall's quests on the one save (ServerStorage.DeckWarsServer.EconomyManager).
-- Plain logic on the save table (no Roblox calls), so every server script uses it the same way:
-- PlayerData moves quests along after every match and for packs, enchants and fusions, and pays
-- what QuestServer claims at the hall. The quests themselves, their rewards and the chests are in
-- ReplicatedStorage.DeckWars.Quests.
--
--   d.questBook = {
--     v = 1,
--     day = utc day, daily = { { id, p = progress, c = claimed } x3 }, dailySwaps = swaps used today
--     week = n, weekly = { { id, p, c, t = { [theme] = true } } x5 }, weeklySwaps = swaps used
--     waiting = { { n, id, from = "daily" | "weekly" } }  -- finished but not claimed before
--                                                          -- the day or week ended: still yours
--     serial = n,                  -- (numbers the waiting quests)
--     journey = { [id] = true },   -- Journey quests claimed
--     renown = n,                  -- this week's Renown (fills the Quest Chests)
--     chests = { ["1"] = true },   -- this week's Quest Chests opened
--     dailyDone = n, claimed = n,  -- daily quests / all quests claimed, ever
--     rev = n,                     -- goes up with every change (the hall asks for a fresh copy)
--   }
--
-- Claims are named by key: "d1".."d3" today's daily quests, "w1".."w5" this week's, "j:<id>" a
-- Journey quest, "x<n>" a finished quest waiting from an earlier day or week.

local function req(name)
	if script then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end
local Quests = req("Quests")
local Campaign = req("Campaign")
local CardData = req("CardData")
local ShopCatalog = req("ShopCatalog")

local QuestBook = {}

local MAX = ShopCatalog.MaxBalance or 1e9
QuestBook.WaitingMax = 12 -- finished quests kept waiting at most (the oldest go first)

local function whole(n)
	return math.max(0, math.floor(tonumber(n) or 0))
end

---------------------------------------------------------------------------
-- The Campaign save, read only (CampaignData owns it)
---------------------------------------------------------------------------

local function campaignOf(d)
	local c = type(d.campaign) == "table" and d.campaign or nil
	return { clears = (c and type(c.clears) == "table") and c.clears or {} }
end
QuestBook.campaignOf = campaignOf

-- The Campaign save as it will be once this match is in (CampaignData records it right after
-- PlayerData.recordMatch): the stage won once more, with this match's stars added.
local function campaignAfter(before, stageId, mask)
	local clears = table.clone(before.clears)
	local old = clears[stageId]
	clears[stageId] = {
		stars = bit32.bor(old and whole(old.stars) or 0, mask),
		wins = (old and whole(old.wins) or 0) + 1,
	}
	return { clears = clears }
end

-- Which quests a player can be given (Quests `need`).
local function eligible(d)
	local camp = campaignOf(d)
	local stars = Campaign.totalStars(camp)
	local challenge = Campaign.cleared(camp, Campaign.Challenge.unlockAfter)
	return function(q)
		if q.need == "stars" then
			return stars + q.target <= Campaign.MaxStars
		elseif q.need == "challenge" then
			return challenge
		end
		return true
	end
end

---------------------------------------------------------------------------
-- The book: new day, new week
---------------------------------------------------------------------------

local function freshList(ids)
	local list = {}
	for _, id in ipairs(ids) do
		table.insert(list, { id = id, p = 0, c = false })
	end
	return list
end

-- Finished quests that weren't claimed in time move to the waiting list (they stay yours).
local function keepFinished(b, list, from)
	for _, e in ipairs(type(list) == "table" and list or {}) do
		local def = Quests.ById[e.id]
		if def and not e.c and whole(e.p) >= def.target then
			b.serial = whole(b.serial) + 1
			table.insert(b.waiting, { n = b.serial, id = e.id, from = from })
		end
	end
	while #b.waiting > QuestBook.WaitingMax do
		table.remove(b.waiting, 1)
	end
end

-- Old saves had today's three quests on the Trophy Wall (d.progress.quests = { day, list }):
-- if they're today's, they carry over once with their progress.
local function fromLegacy(legacy, day)
	if type(legacy) ~= "table" or legacy.day ~= day or type(legacy.list) ~= "table" then
		return nil
	end
	local list = {}
	for _, q in ipairs(legacy.list) do
		local def = type(q) == "table" and Quests.ById[q.id]
		if def and def.type == "daily" then
			table.insert(list, { id = q.id, p = math.min(def.target, whole(q.progress)), c = q.claimed == true })
		end
	end
	return #list == Quests.DailyCount and list or nil
end

-- The player's quest book, with today's and this week's quests rolled when the day or the week
-- changed. legacy = the old Trophy Wall quests (once, from PlayerData).
function QuestBook.ensure(d, userId, now, legacy)
	now = now or os.time()
	local b = type(d.questBook) == "table" and d.questBook or nil
	local fresh = b == nil
	if fresh then
		b = {}
		d.questBook = b
	end
	b.v = 1
	b.waiting = type(b.waiting) == "table" and b.waiting or {}
	b.journey = type(b.journey) == "table" and b.journey or {}
	b.chests = type(b.chests) == "table" and b.chests or {}
	b.renown = whole(b.renown)
	b.rev = whole(b.rev)
	b.dailySwaps = whole(b.dailySwaps)
	b.weeklySwaps = whole(b.weeklySwaps)
	local day, week = Quests.day(now), Quests.week(now)
	if b.day ~= day or type(b.daily) ~= "table" or #b.daily == 0 then
		if b.day ~= nil then
			keepFinished(b, b.daily, "daily")
		end
		b.daily = (fresh and fromLegacy(legacy, day)) or freshList(Quests.rollDaily(userId, day, eligible(d)))
		b.day = day
		b.dailySwaps = 0
		b.rev += 1
	end
	if b.week ~= week or type(b.weekly) ~= "table" or #b.weekly == 0 then
		if b.week ~= nil then
			keepFinished(b, b.weekly, "weekly")
		end
		b.weekly = freshList(Quests.rollWeekly(userId, week, eligible(d)))
		b.week = week
		b.weeklySwaps = 0
		b.renown = 0
		b.chests = {}
		b.rev += 1
	end
	return b
end

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------

local TYPE_ORDER = { daily = 1, weekly = 2, journey = 3 }

-- The rows for the result screen: finished ones first, then daily, weekly, Journey; at most `max`.
local function sortMoved(moved, max)
	table.sort(moved, function(a, b)
		local da, db = a.progress >= a.target, b.progress >= b.target
		if da ~= db then
			return da
		end
		return (TYPE_ORDER[a.type] or 9) < (TYPE_ORDER[b.type] or 9)
	end)
	while max and #moved > max do
		table.remove(moved)
	end
	return moved
end
QuestBook.sortMoved = sortMoved

local function bump(moved, e, def, gain)
	gain = whole(gain)
	if gain <= 0 or e.c or whole(e.p) >= def.target then
		return
	end
	local before = whole(e.p)
	e.p = math.min(def.target, before + gain)
	table.insert(moved, { id = def.id, type = def.type, before = before, progress = e.p, target = def.target })
end

-- The themes a match was played with: the deck's themes, or a practice deck's own theme.
local function themesOf(m)
	local out = {}
	local list = (type(m.themes) == "table" and #m.themes > 0) and m.themes or { m.deck }
	for _, fam in ipairs(list) do
		if type(fam) == "string" and fam ~= "Any" and CardData.FamilyColors and CardData.FamilyColors[fam] then
			table.insert(out, fam)
		end
	end
	return out
end

-- After a finished match. m is what PlayerData.recordMatch gets: result, stats, beatHard, deck,
-- themes, campaign (the Campaign stage, or nil), heroHp, heroMaxHp, turns.
-- Returns the quests it moved: { { id, type, before, progress, target } } (daily and weekly
-- quests, and Journey quests this match will finish or move once the Campaign has recorded it).
function QuestBook.noteMatch(d, userId, m, now)
	local b = QuestBook.ensure(d, userId, now)
	local won = m.result == "win"
	local stage = type(m.campaign) == "table" and m.campaign or nil
	local hp, maxHp = tonumber(m.heroHp), tonumber(m.heroMaxHp)
	local ev = {
		result = m.result,
		stats = m.stats,
		beatHard = m.beatHard,
		deck = m.deck,
		themes = m.themes,
		campaign = stage ~= nil,
		healthy = won and hp ~= nil and maxHp ~= nil and maxHp > 0 and hp >= math.ceil(maxHp * (Campaign.HealthyShare or 0.5)),
	}
	local campBefore, campAfter = nil, nil
	if stage then
		ev.challengeWin = won and stage.challenge == true
		ev.bossWin = won and stage.boss == true and not stage.challenge
		if won and not stage.challenge and type(stage.id) == "string" and Campaign.parseId(stage.id) then
			local stars = Campaign.starsFor(stage, { result = m.result, hp = hp, maxHp = maxHp, turns = m.turns })
			local mask = Campaign.maskOf(stars)
			campBefore = campaignOf(d)
			local old = campBefore.clears[stage.id]
			local oldMask = old and whole(old.stars) or 0
			ev.newStars = Campaign.countStars(bit32.bor(oldMask, mask)) - Campaign.countStars(oldMask)
			campAfter = campaignAfter(campBefore, stage.id, mask)
		end
	end
	local moved = {}
	local themes = won and themesOf(m) or {}
	for _, list in ipairs({ b.daily, b.weekly }) do
		for _, e in ipairs(list) do
			local def = Quests.ById[e.id]
			if def then
				if def.kind == "themes" then
					-- each theme counts once a week
					e.t = type(e.t) == "table" and e.t or {}
					local gain = 0
					for _, fam in ipairs(themes) do
						if not e.t[fam] and not e.c and whole(e.p) + gain < def.target then
							e.t[fam] = true
							gain += 1
						end
					end
					bump(moved, e, def, gain)
				else
					bump(moved, e, def, Quests.gain(def, ev))
				end
			end
		end
	end
	if campAfter then
		for _, def in ipairs(Quests.Journey) do
			if not b.journey[def.id] then
				local before = Quests.journeyProgress(def, campBefore)
				local after = Quests.journeyProgress(def, campAfter)
				if after > before then
					table.insert(moved, { id = def.id, type = "journey", before = before, progress = after, target = def.target })
				end
			end
		end
	end
	if #moved > 0 then
		b.rev += 1
	end
	return moved
end

-- Something done outside a match: kind = "pack" (packs opened), "enchant", "fuse" or
-- "dailyDone". Returns the quests it moved.
function QuestBook.note(d, userId, kind, n, now)
	local b = QuestBook.ensure(d, userId, now)
	n = whole(n)
	local moved = {}
	if n <= 0 then
		return moved
	end
	for _, list in ipairs({ b.daily, b.weekly }) do
		for _, e in ipairs(list) do
			local def = Quests.ById[e.id]
			if def and def.kind == kind then
				bump(moved, e, def, n)
			end
		end
	end
	if #moved > 0 then
		b.rev += 1
	end
	return moved
end

---------------------------------------------------------------------------
-- Claiming, swapping and the chests
---------------------------------------------------------------------------

local function journeyDone(d, b, def)
	return not b.journey[def.id] and Quests.journeyProgress(def, campaignOf(d)) >= def.target
end

-- How many things are waiting to be claimed at the hall (quests and chests).
function QuestBook.readyCount(d, userId, now)
	local b = QuestBook.ensure(d, userId, now)
	local n = #b.waiting
	for _, list in ipairs({ b.daily, b.weekly }) do
		for _, e in ipairs(list) do
			local def = Quests.ById[e.id]
			if def and not e.c and whole(e.p) >= def.target then
				n += 1
			end
		end
	end
	local camp = campaignOf(d)
	for _, def in ipairs(Quests.Journey) do
		if not b.journey[def.id] and Quests.journeyProgress(def, camp) >= def.target then
			n += 1
		end
	end
	for i, chest in ipairs(Quests.Chests) do
		if not b.chests[tostring(i)] and b.renown >= chest.at then
			n += 1
		end
	end
	return n
end

-- The quest behind a key, and where it is: returns def, entry, list, index (entry/list/index
-- for daily, weekly and waiting quests).
local function find(b, key)
	if type(key) ~= "string" or #key > 64 then
		return nil
	end
	local head = string.sub(key, 1, 1)
	if head == "d" or head == "w" then
		local list = head == "d" and b.daily or b.weekly
		local i = tonumber(string.sub(key, 2))
		local e = i and list[i]
		return e and Quests.ById[e.id], e, list, i
	elseif head == "x" then
		local n = tonumber(string.sub(key, 2))
		for i, w in ipairs(b.waiting) do
			if w.n == n then
				return Quests.ById[w.id], w, b.waiting, i
			end
		end
	elseif string.sub(key, 1, 2) == "j:" then
		local def = Quests.ById[string.sub(key, 3)]
		if def and def.type == "journey" then
			return def
		end
	end
	return nil
end

-- (keeps the lifetime totals EconomyManager.grant keeps too: stats.coinsEarned, stats.shardsEarned)
local function pay(d, gems, coins, shards)
	local stats = type(d.stats) == "table" and d.stats or nil
	if gems > 0 then
		d.gems = math.min(MAX, whole(d.gems) + gems)
	end
	if coins > 0 then
		d.coins = math.min(MAX, whole(d.coins) + coins)
		if stats then
			stats.coinsEarned = whole(stats.coinsEarned) + coins
		end
	end
	if shards > 0 then
		d.shards = math.min(MAX, whole(d.shards) + shards)
		if stats then
			stats.shardsEarned = whole(stats.shardsEarned) + shards
		end
	end
end

-- Claims a finished quest: pays its Gems, Shards and Coins into the save and adds its Renown.
-- Returns { id, type, gems, shards, coins, xp, renown, renownBefore, renownAfter,
-- chestsReady = { chest indexes that just became ready } } (the caller adds the XP), or nil and why.
function QuestBook.claim(d, userId, key, now)
	local b = QuestBook.ensure(d, userId, now)
	local def, e, list, i = find(b, key)
	if not def then
		return nil, "That quest isn't here any more."
	end
	if def.type == "journey" then
		if b.journey[def.id] then
			return nil, "Already claimed."
		end
		if not journeyDone(d, b, def) then
			return nil, "Not finished yet."
		end
		b.journey[def.id] = true
	elseif list == b.waiting then
		table.remove(b.waiting, i)
	else
		if e.c then
			return nil, "Already claimed."
		end
		if whole(e.p) < def.target then
			return nil, "Not finished yet."
		end
		e.c = true
	end
	local out = {
		id = def.id,
		type = def.type,
		gems = whole(def.gems),
		shards = whole(def.shards),
		coins = whole(def.coins),
		xp = whole(def.xp),
		renown = whole(def.renown),
		renownBefore = b.renown,
		chestsReady = {},
	}
	pay(d, out.gems, out.coins, out.shards)
	b.renown += out.renown
	out.renownAfter = b.renown
	for n, chest in ipairs(Quests.Chests) do
		if not b.chests[tostring(n)] and out.renownBefore < chest.at and b.renown >= chest.at then
			table.insert(out.chestsReady, n)
		end
	end
	b.claimed = whole(b.claimed) + 1
	if def.type == "daily" then
		b.dailyDone = whole(b.dailyDone) + 1
		-- ("claim 9 daily quests" this week)
		out.moved = QuestBook.note(d, userId, "dailyDone", 1, now)
	end
	b.rev += 1
	return out
end

-- Swaps a daily ("d1".."d3") or weekly ("w1".."w5") quest you haven't finished for another
-- one of the same tier or group. Returns { key, old, new } or nil and why.
function QuestBook.swap(d, userId, key, now)
	local b = QuestBook.ensure(d, userId, now)
	local def, e, list, i = find(b, key)
	if not def or (list ~= b.daily and list ~= b.weekly) then
		return nil, "Only daily and weekly quests can be swapped."
	end
	if e.c then
		return nil, "Already claimed."
	end
	if whole(e.p) >= def.target then
		return nil, "It's finished: claim it instead!"
	end
	local daily = list == b.daily
	local used = daily and b.dailySwaps or b.weeklySwaps
	local free = daily and Quests.DailySwaps or Quests.WeeklySwaps
	if used >= free then
		return nil, daily and "No swaps left today." or "No swaps left this week."
	end
	local avoid = {}
	for _, other in ipairs(list) do
		avoid[other.id] = true
	end
	local period = daily and b.day or b.week
	local new = Quests.swapFor(def.id, userId, period, used, avoid, eligible(d))
	if not new then
		return nil, "There's no other quest to swap to."
	end
	list[i] = { id = new, p = 0, c = false }
	if daily then
		b.dailySwaps += 1
	else
		b.weeklySwaps += 1
	end
	b.rev += 1
	return { key = key, old = def.id, new = new }
end

-- A random card of a rarity (not a token), picked with roll() in [0, 1).
local function anyCard(rarity, roll)
	local list = {}
	for _, id in ipairs(CardData.List) do
		local c = CardData.Cards[id]
		if c and c.rarity == rarity and not c.token then
			table.insert(list, id)
		end
	end
	table.sort(list)
	if #list == 0 then
		return nil
	end
	return list[math.floor(roll() * #list) + 1] or list[#list]
end

-- Opens Quest Chest `index` (once this week's Renown has reached it). Pays its Gems, Coins and
-- Shards and adds its Luck Potion's lucky pulls into the save. Returns { index, name, gems,
-- coins, shards, potion (name), charges, card (id, for the caller to grant) } or nil and why.
function QuestBook.openChest(d, userId, index, now, roll)
	local b = QuestBook.ensure(d, userId, now)
	local chest = type(index) == "number" and Quests.Chests[index]
	if not chest then
		return nil, "There's no such chest."
	end
	if b.chests[tostring(index)] then
		return nil, "You've opened that chest this week."
	end
	if b.renown < chest.at then
		return nil, "Earn " .. (chest.at - b.renown) .. " more Renown to open it."
	end
	b.chests[tostring(index)] = true
	local out = {
		index = index,
		name = chest.name,
		gems = whole(chest.gems),
		coins = whole(chest.coins),
		shards = whole(chest.shards),
	}
	pay(d, out.gems, out.coins, out.shards)
	local potion = chest.potion and ShopCatalog.PotionById and ShopCatalog.PotionById[chest.potion]
	if potion then
		d.boosts = type(d.boosts) == "table" and d.boosts or { luckCharges = 0, xpUntil = 0 }
		local cap = ShopCatalog.MaxLuckCharges or math.huge
		d.boosts.luckCharges = math.min(cap, whole(d.boosts.luckCharges) + potion.charges)
		out.potion, out.charges = potion.name, potion.charges
	end
	if chest.card then
		out.card = anyCard(chest.card, roll or math.random)
		out.rarity = chest.card
	end
	b.rev += 1
	return out
end

---------------------------------------------------------------------------
-- What the hall shows
---------------------------------------------------------------------------

function QuestBook.snapshot(d, userId, now)
	now = now or os.time()
	local b = QuestBook.ensure(d, userId, now)
	local camp = campaignOf(d)
	local out = {
		day = b.day,
		week = b.week,
		resetDaily = Quests.secondsToDaily(now),
		resetWeekly = Quests.secondsToWeekly(now),
		daily = {},
		weekly = {},
		waiting = {},
		journey = {},
		chests = {},
		renown = b.renown,
		dailySwaps = math.max(0, Quests.DailySwaps - b.dailySwaps),
		weeklySwaps = math.max(0, Quests.WeeklySwaps - b.weeklySwaps),
		dailyDone = whole(b.dailyDone),
		claimed = whole(b.claimed),
		rev = b.rev,
		gems = whole(d.gems),
		coins = whole(d.coins),
		shards = whole(d.shards),
	}
	for i, e in ipairs(b.daily) do
		local def = Quests.ById[e.id]
		if def then
			table.insert(out.daily, { key = "d" .. i, id = e.id, progress = math.min(def.target, whole(e.p)), target = def.target, claimed = e.c == true })
		end
	end
	for i, e in ipairs(b.weekly) do
		local def = Quests.ById[e.id]
		if def then
			local themes = nil
			if type(e.t) == "table" then
				themes = {}
				for fam in pairs(e.t) do
					table.insert(themes, fam)
				end
				table.sort(themes)
			end
			table.insert(out.weekly, { key = "w" .. i, id = e.id, progress = math.min(def.target, whole(e.p)), target = def.target, claimed = e.c == true, themes = themes })
		end
	end
	for _, w in ipairs(b.waiting) do
		local def = Quests.ById[w.id]
		if def then
			table.insert(out.waiting, { key = "x" .. tostring(w.n), id = w.id, from = w.from, progress = def.target, target = def.target, claimed = false })
		end
	end
	for _, def in ipairs(Quests.Journey) do
		table.insert(out.journey, {
			key = "j:" .. def.id,
			id = def.id,
			progress = Quests.journeyProgress(def, camp),
			target = def.target,
			claimed = b.journey[def.id] == true,
			open = Quests.journeyOpen(def, camp),
		})
	end
	for i, chest in ipairs(Quests.Chests) do
		local opened = b.chests[tostring(i)] == true
		table.insert(out.chests, { index = i, at = chest.at, opened = opened, ready = not opened and b.renown >= chest.at })
	end
	out.ready = QuestBook.readyCount(d, userId, now)
	return out
end

---------------------------------------------------------------------------
-- Developer tools (the dev panel's quest buttons, and the hall's for developers)
---------------------------------------------------------------------------

-- Fresh daily quests now (a different roll than today's), finished ones kept waiting.
function QuestBook.debugNewDay(d, userId, now)
	local b = QuestBook.ensure(d, userId, now)
	keepFinished(b, b.daily, "daily")
	b.daily = freshList(Quests.rollDaily(whole(userId) + math.random(1, 100000), b.day, eligible(d)))
	b.dailySwaps = 0
	b.rev += 1
	return b
end

-- Every daily and weekly quest you have finished now (not claimed: claim them at the hall), to
-- try the claim scene without playing for it.
function QuestBook.debugFinish(d, userId, now)
	local b = QuestBook.ensure(d, userId, now)
	for _, list in ipairs({ b.daily, b.weekly }) do
		for _, e in ipairs(list) do
			local def = Quests.ById[e.id]
			if def and not e.c then
				e.p = def.target
			end
		end
	end
	b.rev += 1
	return b
end

-- A fresh week now: new weekly quests, Renown back to 0, the chests closed again.
function QuestBook.debugNewWeek(d, userId, now)
	local b = QuestBook.ensure(d, userId, now)
	keepFinished(b, b.weekly, "weekly")
	b.weekly = freshList(Quests.rollWeekly(whole(userId) + math.random(1, 100000), b.week, eligible(d)))
	b.weeklySwaps = 0
	b.renown = 0
	b.chests = {}
	b.rev += 1
	return b
end

return QuestBook

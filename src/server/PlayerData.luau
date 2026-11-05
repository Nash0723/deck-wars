-- Player progress for the merged game: level and XP, the daily reward, three daily quests,
-- achievements, the first win of the day and win streaks.
--
-- There is ONE save: Nash's profile (ServerStorage.DeckWarsServer.EconomyManager, ProfileStore
-- "DeckWarsPlayer_v1") with Gems, Coins, the card collection and saved decks. This module keeps
-- the friend's progress rules (Progression in ReplicatedStorage.DeckWars) on that same save:
--   d.level, d.xp           the level (the friend's curve: 80 XP, +20 per level, up to 400)
--   d.progress              win streak, quests, daily claim, achievements, counters
-- and shows them to the player's screen as attributes (Level, XP, XPNeeded, WinStreak,
-- FirstWinReady, DailyReady, DailyDay, Quest1Id..., QuestsReady, Ach_<id>...).
--
-- MatchServer calls recordMatch after every match. The Trophy Wall claims the daily reward,
-- quests and achievements through MenuAction (ClaimDaily, ClaimQuest, ClaimAchievement).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local CardData = require(Shared:WaitForChild("CardData"))
local Progression = require(Shared:WaitForChild("Progression"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local EconomyManager = require(ServerStorage:WaitForChild("DeckWarsServer"):WaitForChild("EconomyManager"))

local PlayerData = {}

local MAX = ShopCatalog.MaxBalance or 1e9

local function data(player)
	if not EconomyManager.isLoaded(player) then
		return nil
	end
	return EconomyManager.waitForData(player, 0)
end

local function newProgress()
	return {
		winStreak = 0,
		bestStreak = 0,
		wins = 0,
		matches = 0,
		cupsWon = 0,
		firstWinDay = nil, -- the day the first-win bonus was last paid
		daily = { lastClaimDay = nil, streak = 0 },
		quests = { day = nil, list = {} },
		achievements = {}, -- [id] = { progress = n, claimed = bool }
		themesWon = {}, -- [family] = true once you've won with a deck using it
		luckyPulls = 0,
		prefs = {},
		trophies = 0, -- the Trophy Road (Progression.TrophyRoad); never goes down
		road = {}, -- ["<stop index>"] = true once claimed
	}
end

-- Fills in anything missing and rolls today's quests when the day changed.
local function ensure(d, userId)
	d.progress = type(d.progress) == "table" and d.progress or newProgress()
	local p = d.progress
	for k, v in pairs(newProgress()) do
		if p[k] == nil then
			p[k] = v
		end
	end
	d.level = math.max(1, math.floor(tonumber(d.level) or 1))
	d.xp = math.max(0, math.floor(tonumber(d.xp) or 0))
	local today = Progression.today()
	if p.quests.day ~= today then
		local list = {}
		for _, id in ipairs(Progression.questsFor(userId, today)) do
			table.insert(list, { id = id, progress = 0, claimed = false })
		end
		p.quests = { day = today, list = list }
	end
	return p
end

local function dailyState(p)
	local today = Progression.today()
	local dd = p.daily
	if dd.lastClaimDay == today then
		return false, dd.streak
	end
	local nextDay = (dd.lastClaimDay == today - 1) and (dd.streak + 1) or 1
	return true, nextDay
end

-- Achievement progress, worked out from the save.
local function ownsFullSet(d)
	local owned = d.collection or {}
	for _, fam in ipairs(CardData.Families) do
		local all = true
		local any = false
		for _, id in ipairs(CardData.List) do
			local c = CardData.Cards[id]
			if c.family == fam and not c.token then
				any = true
				if (owned[id] or 0) <= 0 then
					all = false
					break
				end
			end
		end
		if any and all then
			return true
		end
	end
	return false
end

local function achievementProgress(d, p, a)
	if a.kind == "win" then
		return p.wins
	elseif a.kind == "level" then
		return d.level
	elseif a.kind == "luckyPull" then
		return p.luckyPulls
	elseif a.kind == "themes" then
		local n = 0
		for _ in pairs(p.themesWon) do
			n += 1
		end
		return n
	elseif a.kind == "cup" then
		return p.cupsWon
	elseif a.kind == "fullSet" then
		return ownsFullSet(d) and 1 or 0
	end
	return 0
end

local function publish(player)
	local d = data(player)
	if not d then
		return
	end
	local p = ensure(d, player.UserId)
	pcall(function()
		player:SetAttribute("Gems", d.gems)
		player:SetAttribute("Coins", d.coins)
		player:SetAttribute("Level", d.level)
		player:SetAttribute("XP", d.xp)
		player:SetAttribute("XPNeeded", Progression.xpForLevel(d.level))
		player:SetAttribute("WinStreak", p.winStreak)
		player:SetAttribute("MatchesPlayed", p.matches)
		player:SetAttribute("FirstWinReady", p.firstWinDay ~= Progression.today())
		local ready, day = dailyState(p)
		player:SetAttribute("DailyReady", ready)
		player:SetAttribute("DailyDay", day)
		local claimable = 0
		for i = 1, Progression.QuestsPerDay do
			local q = p.quests.list[i]
			player:SetAttribute("Quest" .. i .. "Id", q and q.id or nil)
			player:SetAttribute("Quest" .. i .. "Progress", q and q.progress or nil)
			player:SetAttribute("Quest" .. i .. "Claimed", if q then q.claimed else nil)
			local def = q and Progression.QuestById[q.id]
			if def and not q.claimed and q.progress >= def.target then
				claimable += 1
			end
		end
		for _, a in ipairs(Progression.Achievements) do
			local entry = p.achievements[a.id]
			local progress = math.min(a.target, achievementProgress(d, p, a))
			player:SetAttribute("Ach_" .. a.id, progress)
			player:SetAttribute("Ach_" .. a.id .. "_Claimed", entry ~= nil and entry.claimed == true)
			if progress >= a.target and not (entry and entry.claimed) then
				claimable += 1
			end
		end
		-- the Trophy Road: trophies, which stops are claimed ("1,2,5") and how many are ready
		local claimed = {}
		for i, stop in ipairs(Progression.TrophyRoad) do
			if p.road[tostring(i)] then
				table.insert(claimed, tostring(i))
			elseif p.trophies >= stop.at then
				claimable += 1
			end
		end
		player:SetAttribute("Trophies", p.trophies)
		player:SetAttribute("RoadClaimed", table.concat(claimed, ","))
		player:SetAttribute("QuestsReady", claimable)
		for key, value in pairs(p.prefs or {}) do
			player:SetAttribute("Pref" .. key, value)
		end
		player:SetAttribute("ProgressLoaded", true)
	end)
end
PlayerData.publish = publish

local function changed(player, reason)
	EconomyManager.markDirty(player, reason or "progress")
	publish(player)
end

-- Adds XP and pays the Gems for every level reached. Returns a list of { level, gems }.
local function addXP(d, amount)
	local ups = {}
	d.xp += math.max(0, math.floor(amount))
	while d.xp >= Progression.xpForLevel(d.level) do
		d.xp -= Progression.xpForLevel(d.level)
		d.level += 1
		local gems = Progression.levelReward(d.level)
		d.gems = math.min(MAX, d.gems + gems)
		table.insert(ups, { level = d.level, gems = gems })
	end
	return ups
end

---------------------------------------------------------------------------
-- The friend's PlayerData API, on Nash's save
---------------------------------------------------------------------------

function PlayerData.waitForData(player, timeout)
	return EconomyManager.waitForData(player, timeout or 20) ~= nil
end

function PlayerData.addGems(player, amount)
	local d = data(player)
	if not d or type(amount) ~= "number" or amount <= 0 then
		return nil
	end
	d.gems = math.min(MAX, d.gems + math.floor(amount))
	changed(player, "gems")
	return d.gems
end

function PlayerData.getGems(player)
	local d = data(player)
	return d and d.gems or 0
end

function PlayerData.getCount(player, cardId)
	local d = data(player)
	return d and (d.collection or {})[cardId] or 0
end

function PlayerData.getCards(player)
	local d = data(player)
	return d and table.clone(d.collection or {}) or nil
end

function PlayerData.setPrefs(player, prefs)
	local d = data(player)
	if not d or type(prefs) ~= "table" then
		return false
	end
	local p = ensure(d, player.UserId)
	for key, value in pairs(prefs) do
		p.prefs[key] = value
	end
	EconomyManager.markDirty(player, "prefs")
	return true
end

-- A pull result (PullServer): counts Lucky Pull. forced = a dev forced-tier roll (doesn't count).
function PlayerData.notePull(player, rarity, forced)
	local d = data(player)
	if not d then
		return
	end
	local p = ensure(d, player.UserId)
	if not forced and (rarity == "Legendary" or rarity == "Secret") then
		p.luckyPulls += 1
	end
	changed(player, "pull")
end

-- Coins for a match (Nash's rates), with Nash's anti-farming rules for every mode: the match
-- must last ShopCatalog.Match.minSeconds and minTurns, and only maxPaidPerDay matches pay.
local function matchCoins(d, m)
	local M = ShopCatalog.Match
	if not M then
		return 0, nil
	end
	if (tonumber(m.seconds) or M.minSeconds) < M.minSeconds or (tonumber(m.turns) or M.minTurns) < M.minTurns then
		return 0, "too short"
	end
	d.daily = d.daily or {}
	local today = ShopCatalog.dayNumber and ShopCatalog.dayNumber(os.time()) or Progression.today()
	if d.daily.day ~= today then
		d.daily.day = today
		d.daily.paidMatches = 0
	end
	if (d.daily.paidMatches or 0) >= M.maxPaidPerDay then
		return 0, "daily limit"
	end
	d.daily.paidMatches = (d.daily.paidMatches or 0) + 1
	local diff = M.winCoins[m.difficulty or ""] and m.difficulty or "Medium"
	return (m.result == "win" and M.winCoins[diff] or M.lossCoins[diff]) or 0, nil
end

-- After a match. m = { result = "win" | "loss" | "draw", winGems, deck, themes, beatHard, mode,
-- difficulty, seconds, turns, cupWon, stats = { creature, spell, building, spark, damage, pop } }.
-- Returns what the result screen shows:
--   { gems = { { label, amount }... }, totalGems, coins, xp, levelBefore, xpBefore, levelAfter,
--     xpAfter, levelUps, streak, quests = { { id, before, progress, target } }, note }
function PlayerData.recordMatch(player, m)
	local d = data(player)
	if not d or type(m) ~= "table" then
		return nil
	end
	local p = ensure(d, player.UserId)
	local today = Progression.today()
	local out = { gems = {}, totalGems = 0, coins = 0, quests = {}, levelBefore = d.level, xpBefore = d.xp }
	local coins, note = matchCoins(d, m)
	out.note = note
	local paying = note == nil
	local function pay(label, amount)
		amount = math.floor(amount or 0)
		if amount > 0 and paying then
			d.gems = math.min(MAX, d.gems + amount)
			out.totalGems += amount
			table.insert(out.gems, { label = label, amount = amount })
		end
	end
	p.matches += 1
	d.stats = d.stats or {}
	if m.result == "win" then
		p.wins += 1
		d.stats.wins = (d.stats.wins or 0) + 1
		p.winStreak += 1
		p.bestStreak = math.max(p.bestStreak, p.winStreak)
		pay("Win", m.winGems)
		if paying and p.firstWinDay ~= today then
			p.firstWinDay = today
			pay("First win of the day", Progression.FirstWinBonus)
		end
		pay(p.winStreak .. " wins in a row", Progression.streakBonus(p.winStreak))
		for _, fam in ipairs(type(m.themes) == "table" and m.themes or {}) do
			if CardData.FamilyColors[fam] and fam ~= "Any" then
				p.themesWon[fam] = true
			end
		end
		if m.cupWon then
			p.cupsWon += 1
		end
	elseif m.result == "loss" then
		p.winStreak = 0
		d.stats.losses = (d.stats.losses or 0) + 1
	else
		d.stats.draws = (d.stats.draws or 0) + 1
	end
	out.streak = p.winStreak
	-- Trophy Road: a match that went the distance earns trophies (a too-short one doesn't).
	if note ~= "too short" then
		local t = Progression.trophiesFor(m)
		if t > 0 then
			p.trophies += t
			out.trophies = t
		end
	end
	if coins > 0 then
		d.coins = math.min(MAX, d.coins + coins)
		d.stats.coinsEarned = (d.stats.coinsEarned or 0) + coins
		out.coins = coins
	end
	for _, q in ipairs(p.quests.list) do
		local def = Progression.QuestById[q.id]
		if def and not q.claimed and q.progress < def.target then
			local gain = Progression.questGain(def, m)
			if gain > 0 then
				local before = q.progress
				q.progress = math.min(def.target, q.progress + gain)
				table.insert(out.quests, { id = q.id, before = before, progress = q.progress, target = def.target })
			end
		end
	end
	out.xp = paying and (Progression.MatchXP[m.result] or 0) or 0
	local before = d.gems
	out.levelUps = addXP(d, out.xp)
	out.totalGems += d.gems - before
	out.levelAfter, out.xpAfter = d.level, d.xp
	changed(player, "match")
	return out
end

-- A Cup won by this player (counts for Cup Champion even without a final match reward).
function PlayerData.noteCupWin(player)
	local d = data(player)
	if not d then
		return
	end
	local p = ensure(d, player.UserId)
	p.cupsWon += 1
	changed(player, "cup")
end

-- Today's daily reward: the friend's Gems for the streak day plus Nash's daily Coins.
-- Returns gems, day, coins; or nil and a reason.
function PlayerData.claimDaily(player)
	local d = data(player)
	if not d then
		return nil, "data not loaded"
	end
	local p = ensure(d, player.UserId)
	local ready, day = dailyState(p)
	if not ready then
		return nil, "already claimed today"
	end
	p.daily.lastClaimDay = Progression.today()
	p.daily.streak = day
	local gems = Progression.dailyReward(day)
	local D = ShopCatalog.Daily
	local coins = D and (D.coins + D.coinsPerStreakDay * (math.min(day, D.maxStreak) - 1)) or 0
	d.gems = math.min(MAX, d.gems + gems)
	d.coins = math.min(MAX, d.coins + coins)
	changed(player, "daily")
	return gems, day, coins
end

function PlayerData.claimQuest(player, index)
	local d = data(player)
	if not d then
		return nil, "data not loaded"
	end
	local p = ensure(d, player.UserId)
	local q = type(index) == "number" and p.quests.list[index]
	local def = q and Progression.QuestById[q.id]
	if not def then
		return nil, "no such quest"
	end
	if q.claimed then
		return nil, "already claimed"
	end
	if q.progress < def.target then
		return nil, "not done yet"
	end
	q.claimed = true
	d.gems = math.min(MAX, d.gems + def.gems)
	local ups = addXP(d, Progression.QuestXP)
	changed(player, "quest")
	return { gems = def.gems, xp = Progression.QuestXP, levelUps = ups }
end

function PlayerData.claimAchievement(player, id)
	local d = data(player)
	local a = type(id) == "string" and Progression.AchievementById[id]
	if not d or not a then
		return nil, "no such achievement"
	end
	local p = ensure(d, player.UserId)
	local entry = p.achievements[id] or { claimed = false }
	if entry.claimed then
		return nil, "already claimed"
	end
	if achievementProgress(d, p, a) < a.target then
		return nil, "not done yet"
	end
	entry.claimed = true
	p.achievements[id] = entry
	d.gems = math.min(MAX, d.gems + a.gems)
	changed(player, "achievement")
	return { gems = a.gems }
end

-- Claims stop `index` of the Trophy Road. Returns { gems, coins, cosmetic } or nil and a reason.
function PlayerData.claimRoad(player, index)
	local d = data(player)
	local stop = type(index) == "number" and Progression.TrophyRoad[index]
	if not d or not stop then
		return nil, "no such stop"
	end
	local p = ensure(d, player.UserId)
	local key = tostring(index)
	if p.road[key] then
		return nil, "already claimed"
	end
	if p.trophies < stop.at then
		return nil, "not there yet"
	end
	p.road[key] = true
	local out = { gems = stop.gems or 0, coins = stop.coins or 0, cosmetic = stop.cosmetic }
	d.gems = math.min(MAX, d.gems + out.gems)
	d.coins = math.min(MAX, d.coins + out.coins)
	if stop.cosmetic and EconomyManager.grantCosmetic then
		EconomyManager.grantCosmetic(player, stop.cosmetic)
	end
	changed(player, "road")
	return out
end

-- Developer tools (Nash's dev panel "New day"): the daily reward, quests and the first-win
-- bonus come back.
function PlayerData.debugNewDay(player)
	local d = data(player)
	if not d then
		return false
	end
	local p = ensure(d, player.UserId)
	local today = Progression.today()
	if p.daily.lastClaimDay then
		p.daily.lastClaimDay = today - 1
	end
	p.firstWinDay = nil
	p.quests = { day = today, list = {} }
	for _, qid in ipairs(Progression.questsFor(player.UserId + math.random(1, 100000), today)) do
		table.insert(p.quests.list, { id = qid, progress = 0, claimed = false })
	end
	changed(player, "newday")
	return true
end

function PlayerData.debugAddXP(player, amount)
	local d = data(player)
	if not d then
		return nil
	end
	ensure(d, player.UserId)
	local ups = addXP(d, amount)
	changed(player, "xp")
	return ups
end

---------------------------------------------------------------------------
-- Start: publish once each player's save has loaded, and again at midnight UTC.
---------------------------------------------------------------------------

local function watch(player)
	task.spawn(function()
		if EconomyManager.waitForData(player, 60) then
			publish(player)
		end
	end)
end
Players.PlayerAdded:Connect(watch)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end

task.spawn(function()
	local day = Progression.today()
	while true do
		task.wait(30)
		if Progression.today() ~= day then
			day = Progression.today()
			for _, pl in ipairs(Players:GetPlayers()) do
				publish(pl)
			end
		end
	end
end)

return PlayerData

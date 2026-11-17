-- Quests: everything the Quest Hall in the Park hands out. Shared by the server (QuestBook keeps
-- them on the save, PlayerData moves them along after every match) and the screens (QuestHallUI,
-- the match result screen and the Trophy Wall's summary).
--
-- Quests are finished anywhere (a match, the Campaign, the Pack Party, the crystal...) and
-- claimed at the Quest Hall on the north lawn of the Park, from Quill the Quest Keeper. The
-- trophies, achievements and the Trophy Road stay on the Trophy Wall in your room.
--
--   Daily    three a day: an Easy one, a Medium one and a Hard one. New at 00:00 UTC.
--   Weekly   five a week: "claim 9 daily quests", two battle goals, a Campaign goal and a
--            collection goal (packs, enchants, fusing). New on Monday 00:00 UTC.
--   Journey  the Campaign's quests: four in every world (clear acts 1 to 3, beat the boss, earn
--            12 stars there, beat the boss on Hard). Once each, they never reset, and they're
--            counted from your Campaign progress, so worlds you cleared before count too.
--
-- Every quest pays Gems, Shards (the enchanting currency) and XP, and adds Renown. Renown fills
-- the week's four Quest Chests (it starts again from 0 every Monday).
--
-- Swaps: one free swap a day for a daily quest and one a week for a weekly quest you haven't
-- finished yet: you get another quest of the same kind (the same tier, the same group).
--
-- Change the numbers here and the server, the hall and the result screen all follow.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end
local Campaign = req("Campaign")

local Quests = {}

Quests.DailyCount = 3
Quests.WeeklyCount = 5
Quests.DailySwaps = 1 -- free swaps a day (daily quests)
Quests.WeeklySwaps = 1 -- free swaps a week (weekly quests)
Quests.ClaimDistance = 30 -- how close to Quill's counter you have to be to claim (studs)

-- XP and Renown for a quest of each kind (on top of its Gems and Shards).
Quests.XP = { daily = 30, weekly = 80, journey = 50 }
Quests.Renown = { daily = 10, weekly = 25, journey = 15 }

-- The colours of the three kinds (and the tiers of the daily ones), as { r, g, b }.
Quests.Colors = {
	daily = { 120, 206, 150 },
	weekly = { 110, 176, 255 },
	journey = { 214, 150, 255 },
	renown = { 255, 200, 90 },
	shards = { 236, 140, 255 }, -- (the enchanting currency's own colour)
}

-- The daily tiers: every day has one quest of each.
Quests.Tiers = {
	{ key = "Easy", gems = 50, shards = 6, color = { 214, 150, 96 } }, -- bronze
	{ key = "Medium", gems = 80, shards = 8, color = { 204, 214, 230 } }, -- silver
	{ key = "Hard", gems = 110, shards = 10, color = { 255, 206, 84 } }, -- gold
}

-- What a quest counts (`kind`; see Quests.gain):
--   win, match (any finished match), creature / spell / building (cards played), spark,
--   damage (to enemy heroes), pop (enemy creatures popped), winHard (beat a Hard bot),
--   winDeck (win with a deck that uses the theme in `deck`), campaignWin (win a Campaign act or
--   the hourly Challenge), campaignStars (new Campaign stars), healthyWin (win with at least half
--   your hit points left), bossWin (beat a Campaign boss), challengeWin (win an hourly
--   Challenge), themes (win with different themes; each theme counts once), pack (packs
--   opened), enchant (cards enchanted at the crystal), fuse (cards fused), dailyDone (daily
--   quests claimed at the hall).
-- need: "stars" = only offered while you still have that many Campaign stars to earn;
--       "challenge" = only once the hourly Challenge is open for you.
-- hint: a short line under the quest on where to do it.
Quests.Daily = {
	-- Easy
	{ id = "play3", tier = 1, text = "Play 3 matches", kind = "match", target = 3, hint = "Campaign battles and Duel Table matches both count." },
	{ id = "creatures10", tier = 1, text = "Play 10 creatures", kind = "creature", target = 10 },
	{ id = "spells4", tier = 1, text = "Cast 4 spells", kind = "spell", target = 4 },
	{ id = "buildings3", tier = 1, text = "Build 3 buildings", kind = "building", target = 3 },
	{ id = "sparks6", tier = 1, text = "Spark 6 times", kind = "spark", target = 6, hint = "Click your creature, then 🌀 Spark." },
	{ id = "pops8", tier = 1, text = "Pop 8 enemy creatures", kind = "pop", target = 8 },
	-- Medium
	{ id = "win2", tier = 2, text = "Win 2 matches", kind = "win", target = 2 },
	{ id = "damage30", tier = 2, text = "Deal 30 damage to enemy heroes", kind = "damage", target = 30 },
	{ id = "campaign2", tier = 2, text = "Win 2 Campaign battles", kind = "campaignWin", target = 2, hint = "Replays count too." },
	{ id = "healthy1", tier = 2, text = "Win with half your hit points left", kind = "healthyWin", target = 1 },
	-- Hard
	{ id = "hard1", tier = 3, text = "Beat a Hard bot", kind = "winHard", target = 1, hint = "Campaign acts 5 and 6 and the hourly Challenge play Hard." },
	{ id = "win4", tier = 3, text = "Win 4 matches", kind = "win", target = 4 },
	{ id = "stars3", tier = 3, text = "Earn 3 new Campaign stars", kind = "campaignStars", target = 3, need = "stars", hint = "★ win · ★ half your hit points left · ★ inside the turn limit." },
	{ id = "deckSnack", tier = 3, text = "Win with a Snack deck", kind = "winDeck", deck = "Snack", target = 1, hint = "Any deck that uses the theme counts." },
	{ id = "deckJunk", tier = 3, text = "Win with a Junk deck", kind = "winDeck", deck = "Junk", target = 1, hint = "Any deck that uses the theme counts." },
	{ id = "deckWeather", tier = 3, text = "Win with a Weather deck", kind = "winDeck", deck = "Weather", target = 1, hint = "Any deck that uses the theme counts." },
	{ id = "deckCritter", tier = 3, text = "Win with a Critter deck", kind = "winDeck", deck = "Critter", target = 1, hint = "Any deck that uses the theme counts." },
	{ id = "deckSpooky", tier = 3, text = "Win with a Spooky deck", kind = "winDeck", deck = "Spooky", target = 1, hint = "Any deck that uses the theme counts." },
	{ id = "deckRobo", tier = 3, text = "Win with a Robo deck", kind = "winDeck", deck = "Robo", target = 1, hint = "Any deck that uses the theme counts." },
}
for _, q in ipairs(Quests.Daily) do
	local tier = Quests.Tiers[q.tier]
	q.type = "daily"
	q.gems = q.gems or tier.gems
	q.shards = q.shards or tier.shards
end

-- The week's five: one of each group in this list.
Quests.WeeklyPlan = { "core", "battle", "battle", "campaign", "collection" }
Quests.Weekly = {
	{ id = "w_dailies9", group = "core", text = "Claim 9 daily quests", kind = "dailyDone", target = 9, gems = 250, shards = 50, hint = "Claim them here at the Quest Hall." },
	-- battle
	{ id = "w_win10", group = "battle", text = "Win 10 matches", kind = "win", target = 10, gems = 220, shards = 40 },
	{ id = "w_play20", group = "battle", text = "Play 20 matches", kind = "match", target = 20, gems = 180, shards = 30 },
	{ id = "w_pops60", group = "battle", text = "Pop 60 enemy creatures", kind = "pop", target = 60, gems = 180, shards = 30 },
	{ id = "w_damage200", group = "battle", text = "Deal 200 damage to enemy heroes", kind = "damage", target = 200, gems = 180, shards = 30 },
	{ id = "w_spells25", group = "battle", text = "Cast 25 spells", kind = "spell", target = 25, gems = 160, shards = 30 },
	{ id = "w_creatures50", group = "battle", text = "Play 50 creatures", kind = "creature", target = 50, gems = 160, shards = 30 },
	{ id = "w_sparks30", group = "battle", text = "Spark 30 times", kind = "spark", target = 30, gems = 160, shards = 30 },
	{ id = "w_hard5", group = "battle", text = "Beat 5 Hard bots", kind = "winHard", target = 5, gems = 220, shards = 45, hint = "Campaign acts 5 and 6 and the hourly Challenge play Hard." },
	{ id = "w_healthy5", group = "battle", text = "Win 5 matches with half your hit points left", kind = "healthyWin", target = 5, gems = 220, shards = 40 },
	{ id = "w_themes3", group = "battle", text = "Win with 3 different themes", kind = "themes", target = 3, gems = 220, shards = 40, hint = "A two-theme deck counts for both of its themes." },
	-- campaign
	{ id = "w_campaign8", group = "campaign", text = "Win 8 Campaign battles", kind = "campaignWin", target = 8, gems = 200, shards = 40, hint = "Replays count too." },
	{ id = "w_stars9", group = "campaign", text = "Earn 9 new Campaign stars", kind = "campaignStars", target = 9, gems = 220, shards = 40, need = "stars" },
	{ id = "w_bosses2", group = "campaign", text = "Beat 2 Campaign bosses", kind = "bossWin", target = 2, gems = 200, shards = 40, hint = "Act 6 of any world. Replays count too." },
	{ id = "w_challenge3", group = "campaign", text = "Win 3 hourly Challenges", kind = "challengeWin", target = 3, gems = 250, shards = 50, need = "challenge", hint = "A new Challenge opens every hour on the Campaign map." },
	-- collection
	{ id = "w_packs10", group = "collection", text = "Open 10 packs", kind = "pack", target = 10, gems = 150, shards = 35, hint = "At the Pack Party or the Pull Altar. A 10-pack counts as 10." },
	{ id = "w_enchant5", group = "collection", text = "Enchant 5 cards", kind = "enchant", target = 5, gems = 150, shards = 40, hint = "At the Enchanting Crystal on the island." },
	{ id = "w_fuse3", group = "collection", text = "Fuse 3 cards", kind = "fuse", target = 3, gems = 150, shards = 30, hint = "At the Deck Shelf: two copies at the same level fuse into one." },
}
for _, q in ipairs(Quests.Weekly) do
	q.type = "weekly"
end

-- Journey quests: four in every Campaign world, in this order.
--   act3   clear acts 1 to 3 (Normal)        progress: acts 1-3 cleared
--   boss   beat the world's boss (Normal)     progress: 1 once act 6 is cleared
--   stars  earn 12 stars in the world         progress: the world's stars (Normal and Hard)
--   hard   beat the boss on Hard              progress: 1 once act 6 on Hard is cleared
Quests.JourneySteps = {
	{ key = "act3", gems = 50, shards = 15 },
	{ key = "boss", gems = 100, shards = 20 },
	{ key = "stars", gems = 80, shards = 20, stars = 12 },
	{ key = "hard", gems = 150, shards = 25 },
}
Quests.Journey = {}
Quests.JourneyByWorld = {} -- [world key] = { def, def, def, def }
for _, w in ipairs(Campaign.Worlds) do
	local list = {}
	for i, step in ipairs(Quests.JourneySteps) do
		local q = {
			id = "j_" .. w.key .. "_" .. step.key,
			type = "journey",
			world = w.key,
			step = step.key,
			order = i,
			gems = step.gems,
			shards = step.shards,
		}
		if step.key == "act3" then
			q.text = "Clear acts 1 to 3 of " .. w.name
			q.target = 3
			q.hint = w.opponents[1] .. ", " .. w.opponents[2] .. " and " .. w.opponents[3] .. "."
		elseif step.key == "boss" then
			q.text = "Beat " .. w.boss.name
			q.target = 1
			q.hint = "The boss of " .. w.name .. ", in act 6."
		elseif step.key == "stars" then
			q.text = "Earn " .. step.stars .. " ★ in " .. w.name
			q.target = step.stars
			q.hint = "Normal and Hard stars both count."
		else
			q.text = "Beat " .. w.boss.name .. " on Hard"
			q.target = 1
			q.hint = "Hard mode opens once you've beaten the boss."
		end
		table.insert(list, q)
		table.insert(Quests.Journey, q)
	end
	Quests.JourneyByWorld[w.key] = list
end

-- Every quest by id (daily, weekly and journey).
Quests.ById = {}
for _, list in ipairs({ Quests.Daily, Quests.Weekly, Quests.Journey }) do
	for _, q in ipairs(list) do
		q.xp = q.xp or Quests.XP[q.type]
		q.renown = q.renown or Quests.Renown[q.type]
		Quests.ById[q.id] = q
	end
end

-- The week's Quest Chests: Renown needed and what each holds (card = a random card of that
-- rarity; potion = a Luck Potion id from ShopCatalog.LuckPotions).
Quests.Chests = {
	{ at = 40, name = "Wooden Chest", coins = 200, shards = 5, color = { 196, 140, 86 } },
	{ at = 100, name = "Silver Chest", gems = 100, shards = 10, color = { 204, 214, 230 } },
	{ at = 180, name = "Gold Chest", coins = 300, shards = 15, card = "Rare", color = { 255, 206, 84 } },
	{ at = 280, name = "Crystal Chest", gems = 200, shards = 25, card = "Epic", potion = "potion_small", color = { 236, 140, 255 } },
}
Quests.RenownMax = Quests.Chests[#Quests.Chests].at

---------------------------------------------------------------------------
-- Days and weeks (UTC)
---------------------------------------------------------------------------

-- Today's number: days since 1 January 1970 (UTC). Daily quests change with it.
function Quests.day(now)
	return math.floor((now or os.time()) / 86400)
end

-- This week's number (weeks start on Monday 00:00 UTC; 1 January 1970 was a Thursday).
function Quests.week(now)
	return math.floor((Quests.day(now) + 3) / 7)
end

function Quests.secondsToDaily(now)
	now = now or os.time()
	return (Quests.day(now) + 1) * 86400 - now
end

function Quests.secondsToWeekly(now)
	now = now or os.time()
	return ((Quests.week(now) + 1) * 7 - 3) * 86400 - now
end

-- "5h 12m", "3d 4h", "42s"
function Quests.timeText(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds >= 86400 then
		return string.format("%dd %dh", math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600))
	elseif seconds >= 3600 then
		return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	elseif seconds >= 60 then
		return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
	end
	return seconds .. "s"
end

---------------------------------------------------------------------------
-- Rolling the quests
---------------------------------------------------------------------------

-- A small LCG seeded from the player, the day (or week) and a salt: the same player gets the
-- same quests on every server.
local function lcg(seed)
	local state = math.abs(math.floor(seed)) % 2147483647
	if state == 0 then
		state = 12345
	end
	return function(n)
		state = (state * 48271) % 2147483647
		return state % n + 1
	end
end

local function seedOf(userId, n, salt)
	return (math.abs(math.floor(tonumber(userId) or 0)) % 1000003) * 7919 + n * 104729 + (salt or 0) * 15485863
end

-- One quest id from `pool` (a list of defs) that isn't in `avoid` (a set of ids) and passes ok(def).
-- Falls back to any quest not in `avoid`, then to the first one.
function Quests.pick(pool, seed, avoid, ok)
	local roll = lcg(seed)
	avoid = avoid or {}
	local good = {}
	for _, q in ipairs(pool) do
		if not avoid[q.id] and (ok == nil or ok(q)) then
			table.insert(good, q)
		end
	end
	if #good == 0 then
		for _, q in ipairs(pool) do
			if not avoid[q.id] then
				table.insert(good, q)
			end
		end
	end
	if #good == 0 then
		return pool[1] and pool[1].id or nil
	end
	-- (a few throws first, so the first quests of neighbouring days don't follow each other)
	roll(7)
	roll(11)
	return good[roll(#good)].id
end

local function tierPool(tier)
	local list = {}
	for _, q in ipairs(Quests.Daily) do
		if q.tier == tier then
			table.insert(list, q)
		end
	end
	return list
end
Quests.TierPools = { tierPool(1), tierPool(2), tierPool(3) }

local function groupPool(group)
	local list = {}
	for _, q in ipairs(Quests.Weekly) do
		if q.group == group then
			table.insert(list, q)
		end
	end
	return list
end
Quests.GroupPools = {}
for _, g in ipairs(Quests.WeeklyPlan) do
	Quests.GroupPools[g] = Quests.GroupPools[g] or groupPool(g)
end

-- The three daily quest ids for a player on a day (Easy, Medium, Hard). ok(def) leaves out
-- quests the player can't do yet (see `need`).
function Quests.rollDaily(userId, day, ok)
	local out, used = {}, {}
	for tier = 1, Quests.DailyCount do
		local id = Quests.pick(Quests.TierPools[tier] or Quests.Daily, seedOf(userId, day, tier), used, ok)
		used[id] = true
		table.insert(out, id)
	end
	return out
end

-- The five weekly quest ids for a player in a week.
function Quests.rollWeekly(userId, week, ok)
	local out, used = {}, {}
	for slot, group in ipairs(Quests.WeeklyPlan) do
		local id = Quests.pick(Quests.GroupPools[group], seedOf(userId, week, 100 + slot), used, ok)
		used[id] = true
		table.insert(out, id)
	end
	return out
end

-- The quest a swap gives instead of `id`: the same tier (daily) or group (weekly), not one of
-- `avoid` (the quests you already have). nth = how many swaps you've made in this period.
function Quests.swapFor(id, userId, period, nth, avoid, ok)
	local q = Quests.ById[id]
	if not q then
		return nil
	end
	local pool = q.type == "daily" and Quests.TierPools[q.tier] or Quests.GroupPools[q.group]
	if not pool then
		return nil
	end
	local new = Quests.pick(pool, seedOf(userId, period, 500 + (nth or 0) * 13), avoid, ok)
	if new == id or (avoid and avoid[new]) then
		return nil
	end
	return new
end

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------

-- How much one finished match moves a quest along. `ev` (QuestBook makes it from what
-- PlayerData.recordMatch gets): result, stats { creature, spell, building, spark, damage, pop },
-- beatHard, deck, themes, campaign (true for a Campaign battle), newStars, healthy, bossWin,
-- challengeWin. (The "themes" kind is counted by QuestBook: each theme once a week.)
function Quests.gain(q, ev)
	local k = q.kind
	local won = ev.result == "win"
	if k == "win" then
		return won and 1 or 0
	elseif k == "match" then
		return 1
	elseif k == "winHard" then
		return (won and ev.beatHard) and 1 or 0
	elseif k == "winDeck" then
		local themed = ev.deck == q.deck or (type(ev.themes) == "table" and table.find(ev.themes, q.deck) ~= nil)
		return (won and themed) and 1 or 0
	elseif k == "campaignWin" then
		return (won and ev.campaign) and 1 or 0
	elseif k == "campaignStars" then
		return math.max(0, math.floor(tonumber(ev.newStars) or 0))
	elseif k == "healthyWin" then
		return (won and ev.healthy) and 1 or 0
	elseif k == "bossWin" then
		return (won and ev.bossWin) and 1 or 0
	elseif k == "challengeWin" then
		return (won and ev.challengeWin) and 1 or 0
	elseif k == "themes" or k == "pack" or k == "enchant" or k == "fuse" or k == "dailyDone" then
		return 0
	end
	local stats = type(ev.stats) == "table" and ev.stats or {}
	return math.max(0, math.floor(tonumber(stats[k]) or 0))
end

-- A Journey quest's progress, from a Campaign save ({ clears = { [stageId] = { stars, wins } } }).
function Quests.journeyProgress(q, campaignSave)
	local w = q.world
	if q.step == "act3" then
		local n = 0
		for act = 1, 3 do
			if Campaign.cleared(campaignSave, Campaign.stageId(w, act, false)) then
				n += 1
			end
		end
		return n
	elseif q.step == "boss" then
		return Campaign.cleared(campaignSave, Campaign.stageId(w, Campaign.Acts, false)) and 1 or 0
	elseif q.step == "stars" then
		return math.min(q.target, Campaign.worldStars(campaignSave, w))
	elseif q.step == "hard" then
		return Campaign.cleared(campaignSave, Campaign.stageId(w, Campaign.Acts, true)) and 1 or 0
	end
	return 0
end

-- Is this Journey quest's world open yet?
function Quests.journeyOpen(q, campaignSave)
	return Campaign.worldUnlocked(campaignSave, q.world)
end

-- What a quest pays, as a list of { kind, amount } for the screens:
-- kind = "Gems", "Shards", "Coins", "XP", "Renown".
function Quests.rewardList(q)
	local out = {}
	if (q.gems or 0) > 0 then
		table.insert(out, { "Gems", q.gems })
	end
	if (q.shards or 0) > 0 then
		table.insert(out, { "Shards", q.shards })
	end
	if (q.coins or 0) > 0 then
		table.insert(out, { "Coins", q.coins })
	end
	if (q.xp or 0) > 0 then
		table.insert(out, { "XP", q.xp })
	end
	if (q.renown or 0) > 0 then
		table.insert(out, { "Renown", q.renown })
	end
	return out
end

return Quests

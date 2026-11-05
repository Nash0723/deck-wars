-- Headless tests for the Campaign: every stage builds a legal match, the opponents' decks follow
-- their tier, stars, unlocks, first-clear and replay rewards, the daily drop cap, star chests and
-- the hourly Challenge.
-- Run with: luaurun tests/campaign_tests.luau src/shared src/server

_G.warn = function() end

local CardData = require("CardData")
local Campaign = require("Campaign")
local MatchEngine = require("MatchEngine")
local BotBrain = require("BotBrain")
local DeckRules = require("DeckRules")
local Rng = require("Rng")

-- CampaignData looks for ReplicatedStorage.DeckWars and ServerStorage like the real server.
local function fakeFolder(map)
	return {
		WaitForChild = function(_, n)
			return { __module = map[n] }
		end,
		FindFirstChild = function()
			return nil
		end,
	}
end
local sharedObj = fakeFolder({ Campaign = Campaign, CardData = CardData, ShopCatalog = require("ShopCatalog") })
_G.game = { GetService = function(_, n)
	if n == "ReplicatedStorage" then
		return { WaitForChild = function()
			return sharedObj
		end }
	end
	return { FindFirstChild = function()
		return nil
	end }
end }
local origRequire = require
_G.require = function(x)
	if type(x) == "table" and x.__module then
		return x.__module
	end
	return origRequire(x)
end
_G.Random = { new = function(seed)
	local r = Rng.new(seed)
	return { NextNumber = function()
		return r:next()
	end }
end }
local CampaignData = require("CampaignData")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. msg)
	end
end

local RANK = Campaign.RarityRank

---------------------------------------------------------------------------
-- Every stage
---------------------------------------------------------------------------
local stages = {}
for _, w in ipairs(Campaign.Worlds) do
	for act = 1, Campaign.Acts do
		for _, hard in ipairs({ false, true }) do
			local id = Campaign.stageId(w.key, act, hard)
			local s = Campaign.stage(id)
			check(s ~= nil, id .. " builds")
			if s then
				table.insert(stages, s)
				check(s.id == id, id .. ": id round-trips")
				check(#s.cards == 30, id .. ": the opponent has 30 cards (" .. #s.cards .. ")")
				local counts = {}
				local maxRank = 0
				for _, cid in ipairs(s.cards) do
					local c = CardData.Cards[cid]
					check(c ~= nil and not c.token, id .. ": " .. tostring(cid) .. " is a real card")
					if c then
						maxRank = math.max(maxRank, RANK[c.rarity])
						counts[cid] = (counts[cid] or 0) + 1
						check(c.family == s.family or c.family == "Any", id .. ": " .. cid .. " fits the " .. s.family .. " deck")
					end
				end
				if s.tier == "basic" then
					check(maxRank <= RANK.Rare, id .. ": a basic deck holds nothing above Rare")
				elseif s.tier == "normal" then
					check(maxRank <= RANK.Mythic, id .. ": a normal deck holds no Legendary or Secret")
				end
				if s.boss and s.bossCard then
					check(counts[s.bossCard] == 2, id .. ": the boss deck holds " .. s.bossCard .. " twice")
					check(CardData.Cards[s.bossCard].rarity == "Legendary", id .. ": the boss card is a Legendary")
				end
				if w.key == "Den" then
					check(maxRank <= RANK.Mythic, id .. ": the Card Den never shows a Legendary")
				end
				check(s.difficulty == "Easy" or s.difficulty == "Medium" or s.difficulty == "Hard", id .. ": difficulty " .. tostring(s.difficulty))
				local hp = Campaign.HeroHp
				for _, r in ipairs(s.rules) do
					check(Campaign.Rules[r] ~= nil, id .. ": rule " .. r .. " exists")
					hp += Campaign.Rules[r] and Campaign.Rules[r].enemyHp or 0
				end
				check(s.enemyHp == hp, id .. ": enemy hit points follow the rules")
				check(CardData.Heroes[s.hero] ~= nil, id .. ": hero " .. tostring(s.hero))
				check(s.firstGems == (hard and math.floor(Campaign.FirstClearGems[act] * Campaign.HardGems + 0.5) or Campaign.FirstClearGems[act]), id .. ": first-clear Gems")
				check(s.firstCard and CardData.Cards[s.firstCard] and not CardData.Cards[s.firstCard].token, id .. ": the first-clear card is a real card")
				if hard and s.boss and s.bossCard then
					check(s.firstCard == s.bossCard, id .. ": a Hard boss's first clear gives its Legendary")
				elseif s.firstCard then
					check(CardData.Cards[s.firstCard].family == s.family, id .. ": the first-clear card is a " .. s.family .. " card")
				end
				check(s.turnLimit >= 8 and s.turnLimit <= 20, id .. ": a sensible turn limit")
			end
		end
	end
end
check(#stages == #Campaign.Worlds * Campaign.Acts * 2, "every world has 6 acts on both modes")
check(Campaign.MaxStars == 252, "252 stars in all")

-- Hard is harder than Normal on every act
for _, w in ipairs(Campaign.Worlds) do
	for act = 1, Campaign.Acts do
		local n = Campaign.stage(Campaign.stageId(w.key, act, false))
		local h = Campaign.stage(Campaign.stageId(w.key, act, true))
		local rank = { Easy = 1, Medium = 2, Hard = 3 }
		check(rank[h.difficulty] > rank[n.difficulty] or #h.rules > #n.rules, w.key .. " act " .. act .. ": Hard is harder")
	end
end

-- Every stage plays out on the real engine (one bot against the opponent; boss stages and a
-- sample of the rest, to keep the run short).
local starter = DeckRules.setupFor(DeckRules.starterDeck())
local played = 0
for i, s in ipairs(stages) do
	if s.boss or i % 5 == 0 then
		local enemy = { deck = s.cards, hero = s.hero, family = s.family, lanes = { s.family, s.family, s.family, s.family }, name = s.name }
		local ok, err = pcall(function()
			local m = MatchEngine.new({ starter, enemy }, 1000 + i)
			m.silent = true
			m.teams[2].hp = s.enemyHp
			m.teams[2].maxHp = s.enemyHp
			local rng = Rng.new(i)
			local guard = 0
			while not m.over and guard < 200 do
				guard += 1
				BotBrain.playTurn(m, m.current, m.current == 2 and s.difficulty or "Medium", rng)
			end
		end)
		check(ok, s.id .. " plays to the end: " .. tostring(err))
		played += 1
	end
end
check(played >= 20, "played " .. played .. " stages")

---------------------------------------------------------------------------
-- Opponent decks by tier
---------------------------------------------------------------------------
for _, fam in ipairs(CardData.Families) do
	for _, tier in ipairs({ "basic", "normal", "full" }) do
		local cards = Campaign.enemyCards(fam, tier)
		check(#cards == 30, fam .. " " .. tier .. ": 30 cards")
	end
end

---------------------------------------------------------------------------
-- Stars
---------------------------------------------------------------------------
local candy3 = Campaign.stage("Candy:3:N")
local st = Campaign.starsFor(candy3, { result = "win", hp = 25, maxHp = 25, turns = 5 })
check(st[1] and st[2] and st[3], "a quick healthy win earns 3 stars")
st = Campaign.starsFor(candy3, { result = "win", hp = 12, maxHp = 25, turns = 5 })
check(st[1] and not st[2] and st[3], "12 of 25 hit points misses the health star (needs 13)")
st = Campaign.starsFor(candy3, { result = "win", hp = 13, maxHp = 25, turns = candy3.turnLimit + 1 })
check(st[1] and st[2] and not st[3], "one turn over the limit misses the turn star")
st = Campaign.starsFor(candy3, { result = "loss", hp = 25, maxHp = 25, turns = 1 })
check(not st[1] and not st[2] and not st[3], "a loss earns no stars")
check(Campaign.countStars(Campaign.maskOf({ true, false, true })) == 2, "star masks count")

---------------------------------------------------------------------------
-- Unlocks
---------------------------------------------------------------------------
local save = { clears = {}, chests = {} }
check(Campaign.canPlay(save, "Den:1:N"), "Card Den act 1 is open from the start")
check(not Campaign.canPlay(save, "Den:2:N"), "act 2 waits for act 1")
check(not Campaign.canPlay(save, "Candy:1:N"), "Gumdrop Plaza waits for the Den boss")
check(not Campaign.canPlay(save, "Den:1:H"), "Hard waits for the Den boss")
check(not Campaign.canPlay(save, "Nope:1:N"), "unknown worlds are refused")
check(not Campaign.canPlay(save, "Den:7:N"), "act 7 doesn't exist")
check(not Campaign.canPlay(save, "Challenge:" .. Campaign.challengeHour(1e9), 1e9), "the Challenge waits for the Den boss")
for act = 1, 6 do
	save.clears["Den:" .. act .. ":N"] = { stars = 1, wins = 1 }
end
check(Campaign.canPlay(save, "Candy:1:N"), "beating the Den boss opens Gumdrop Plaza")
check(Campaign.canPlay(save, "Den:1:H"), "and the Den's Hard mode")
check(not Campaign.canPlay(save, "Candy:1:H"), "but not Gumdrop Plaza's Hard mode")
check(Campaign.canPlay(save, "Challenge:" .. Campaign.challengeHour(1e9), 1e9), "and the Challenge")
check(not Campaign.canPlay(save, "Challenge:" .. (Campaign.challengeHour(1e9) - 1), 1e9), "but not last hour's Challenge")

---------------------------------------------------------------------------
-- Rewards (CampaignData.apply on a plain save)
---------------------------------------------------------------------------
local function seq(values)
	local i = 0
	return function()
		i += 1
		return values[(i - 1) % #values + 1]
	end
end
local now = 1_800_000_000
local d = { gems = 0 }
local den1 = Campaign.stage("Den:1:N")
local r = CampaignData.apply(d, den1, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.99 }), now)
check(r.firstClear, "the first win is a first clear")
check(d.gems == den1.firstGems, "first clear pays " .. den1.firstGems .. " Gems (got " .. d.gems .. ")")
check(#r.cards == 1 and r.cards[1].id == den1.firstCard, "first clear gives the stage's card")
check(r.newStars == 3 and d.campaign.clears["Den:1:N"].stars == 7, "3 new stars")
r = CampaignData.apply(d, den1, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.99 }), now)
check(not r.firstClear and r.totalGems == 0 and #r.cards == 0, "a replay pays no first-clear Gems (and an unlucky roll drops nothing)")
check(d.campaign.clears["Den:1:N"].wins == 2, "wins are counted")
-- a loss changes nothing
local before = d.gems
r = CampaignData.apply(d, Campaign.stage("Den:2:N"), { result = "loss", hp = 0, maxHp = 25, turns = 9 }, seq({ 0.0 }), now)
check(d.gems == before and d.campaign.clears["Den:2:N"] == nil and #r.cards == 0, "a loss gives nothing and clears nothing")
-- stars add up over replays
local d2 = { gems = 0 }
local c3 = Campaign.stage("Candy:3:N")
CampaignData.apply(d2, c3, { result = "win", hp = 5, maxHp = 25, turns = 4 }, seq({ 0.99 }), now)
check(d2.campaign.clears["Candy:3:N"].stars == 5, "win + turn stars = mask 5")
r = CampaignData.apply(d2, c3, { result = "win", hp = 20, maxHp = 25, turns = 30 }, seq({ 0.99 }), now)
check(d2.campaign.clears["Candy:3:N"].stars == 7 and r.newStars == 1, "a later healthy win adds the missing star")
-- replay drops and the daily cap
local d3 = { gems = 0 }
CampaignData.apply(d3, c3, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.99 }), now)
local drops = 0
for _ = 1, 30 do
	local rr = CampaignData.apply(d3, c3, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.1 }), now)
	drops += #rr.cards
	for _, card in ipairs(rr.cards) do
		check(CardData.Cards[card.id].family == "Snack", "a Gumdrop Plaza drop is a Snack card")
		check(CardData.Cards[card.id].rarity == "Common" or CardData.Cards[card.id].rarity == "Rare", "replay drops are Common or Rare")
	end
end
check(drops == Campaign.DropsPerDay, "at most " .. Campaign.DropsPerDay .. " drops a day (got " .. drops .. ")")
local rr = CampaignData.apply(d3, c3, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.1 }), now + 86400)
check(#rr.cards == 1, "the cap resets the next day")
-- the boss Legendary on Normal replays
local d4 = { gems = 0 }
local boss = Campaign.stage("Candy:6:N")
CampaignData.apply(d4, boss, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.99 }), now)
rr = CampaignData.apply(d4, boss, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.001 }), now)
check(#rr.cards == 1 and rr.cards[1].id == "queen_parfait", "a lucky Normal boss replay drops Queen Parfait")
check(#rr.unlocked == 0, "a replay opens nothing new")
local d5 = { gems = 0 }
rr = CampaignData.apply(d5, boss, { result = "win", hp = 25, maxHp = 25, turns = 4 }, seq({ 0.99 }), now)
local opensMeadow = false
for _, t in ipairs(rr.unlocked) do
	opensMeadow = opensMeadow or string.find(t, "Sunset Grasslands", 1, true) ~= nil
end
check(opensMeadow, "beating Queen Parfait opens Sunset Grasslands")
-- star chests
local d6 = { gems = 0 }
local chestsSeen, titleSeen = 0, nil
for act = 1, 6 do
	local s = Campaign.stage("Ice:" .. act .. ":N")
	local res = CampaignData.apply(d6, s, { result = "win", hp = 25, maxHp = 25, turns = 1 }, seq({ 0.99 }), now)
	chestsSeen += #res.chests
	titleSeen = titleSeen or res.titles[1]
end
check(chestsSeen == 3, "18 stars in a world open all 3 chests (got " .. chestsSeen .. ")")
check(titleSeen == "Frostglass Warden", "the last chest gives the world's title")
check(d6.campaign.chests["Ice:1"] and d6.campaign.chests["Ice:2"] and d6.campaign.chests["Ice:3"], "chests are remembered")
local res = CampaignData.apply(d6, Campaign.stage("Ice:1:H"), { result = "win", hp = 25, maxHp = 25, turns = 1 }, seq({ 0.99 }), now)
check(#res.chests == 0, "a chest is given only once")
check(#Campaign.titles(d6.campaign) == 1, "the title is listed")
-- expected first-clear Gems for a whole world
local total = 0
for act = 1, 6 do
	total += Campaign.stage("Ice:" .. act .. ":N").firstGems
end
check(total == 335, "a world's Normal first clears pay 335 Gems (got " .. total .. ")")
-- the Challenge
local hour = Campaign.challengeHour(now)
local ch = Campaign.stage("Challenge:" .. hour)
check(ch and ch.challenge and #ch.rules == 2 and ch.rules[1] ~= ch.rules[2], "the Challenge has two different rules")
check(Campaign.stage("Challenge:" .. hour).world == ch.world, "the same hour gives the same Challenge")
local worldsSeen = {}
for h = hour, hour + 47 do
	worldsSeen[Campaign.challenge(h).world] = true
end
local nWorlds = 0
for _ in pairs(worldsSeen) do
	nWorlds += 1
end
check(nWorlds >= 4, "the Challenge visits different worlds over two days (" .. nWorlds .. ")")
local d7 = { gems = 0 }
local cr = CampaignData.apply(d7, ch, { result = "win", hp = 25, maxHp = 25, turns = 1 }, seq({ 0.5 }), now)
check(cr.firstClear and d7.gems == Campaign.Challenge.gems and #cr.cards == 1, "the Challenge pays Gems and a card once")
local rar = CardData.Cards[cr.cards[1].id].rarity
check(rar == "Rare" or rar == "Epic" or rar == "Mythic", "the Challenge card is Rare or better")
cr = CampaignData.apply(d7, ch, { result = "win", hp = 25, maxHp = 25, turns = 1 }, seq({ 0.5 }), now)
check(not cr.firstClear and #cr.cards == 0 and d7.gems == Campaign.Challenge.gems, "and only once an hour")
local snap = CampaignData.snapshotOf(d7, now)
check(snap.challengeWon == true and snap.challengeHour == hour, "the snapshot knows this hour's Challenge is won")

print(string.format("campaign tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("campaign tests failed")
end

-- Reasons to come back: your level and XP, the daily reward and its streak, the first win of the
-- day, win streaks, achievements and the Trophy Road. The server (PlayerData) keeps the real
-- numbers; the screens use this module for the names, the rewards and the level curve.
-- (Daily, weekly and Journey quests are in Quests: they're claimed at the Quest Hall in the Park.)
--
-- Change the numbers here and both sides follow.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end
local Quests = req("Quests")

local Progression = {}

-- XP for one match. Everyone gets some, the winner more.
Progression.MatchXP = { win = 40, loss = 15, draw = 20 }

-- XP you need to go from `level` to the next one: 80, 100, 120 ... up to 400.
function Progression.xpForLevel(level)
	return math.min(400, 80 + 20 * (math.max(1, level) - 1))
end

-- Gems for reaching `level`: 60, and 200 on every 5th level.
function Progression.levelReward(level)
	return (level % 5 == 0) and 200 or 60
end

-- The daily reward is a week: claim once a day, and coming back the next day moves you up a day
-- (a day missed starts you at day 1 again). After day 7 the next week starts at day 1, every
-- week, for good (your streak count keeps growing). Each day pays Gems and Coins; day 2 adds a
-- Small Luck Potion and day 7, the big one, a Big Luck Potion (ids from ShopCatalog.LuckPotions).
-- It starts at 200 Gems (two packs), climbs 100 a day to 700 on day 6, and day 7 pays 1,000:
-- 3,700 Gems a week.
Progression.DailyWeek = {
	{ gems = 200, coins = 150 },
	{ gems = 300, coins = 175, potion = "potion_small" },
	{ gems = 400, coins = 200 },
	{ gems = 500, coins = 225 },
	{ gems = 600, coins = 250 },
	{ gems = 700, coins = 275 },
	{ gems = 1000, coins = 300, potion = "potion_big" },
}
-- (just the Gems of each day, for the screens that only show those)
Progression.DailyRewards = {}
for i, day in ipairs(Progression.DailyWeek) do
	Progression.DailyRewards[i] = day.gems
end

-- Which day of the week (1 to 7) the streak day `streakDay` is, and which week (1, 2, ...).
function Progression.dailyWeekDay(streakDay)
	return ((math.max(1, math.floor(streakDay or 1)) - 1) % #Progression.DailyWeek) + 1
end

function Progression.dailyWeek(streakDay)
	return math.floor((math.max(1, math.floor(streakDay or 1)) - 1) / #Progression.DailyWeek) + 1
end

-- Everything the day pays: { gems, coins, potion = potion id or nil }.
function Progression.dailyPrize(streakDay)
	return Progression.DailyWeek[Progression.dailyWeekDay(streakDay)]
end

-- Just the Gems.
function Progression.dailyReward(streakDay)
	return Progression.dailyPrize(streakDay).gems
end

-- Your first win each day pays this much extra.
Progression.FirstWinBonus = 100

-- Wins in a row pay extra: 2 in a row +10, 3 in a row +20 ... up to +50.
function Progression.streakBonus(streak)
	if streak < 2 then
		return 0
	end
	return math.min(50, 10 * (streak - 1))
end

-- Quests (Quests.luau): daily, weekly and Journey quests, claimed at the Quest Hall in the Park.
-- These names stay for the screens that show a quest by its id (the result screen):
-- QuestById holds every quest (daily, weekly and Journey), each with .text and .target.
Progression.QuestXP = Quests.XP.daily
Progression.Quests = Quests.Daily
Progression.QuestById = Quests.ById
Progression.QuestsPerDay = Quests.DailyCount

-- Achievements: one-time goals on the Trophy Wall, claimed once each.
-- kind: win (matches won), level (level reached), luckyPull (a Legendary or Secret pulled),
-- themes (won with each of the 6 themes: a deck counts for every theme it uses), cup (Cups won),
-- fullSet (own every card of one theme).
-- Each pays Gems and rune Shards (the enchant currency, see ShopCatalog).
Progression.Achievements = {
	{ id = "first_win", name = "First Blood", text = "Win a match", kind = "win", target = 1, gems = 100, shards = 20 },
	{ id = "level_10", name = "Level Ten", text = "Reach level 10", kind = "level", target = 10, gems = 200, shards = 40 },
	{ id = "lucky_pull", name = "Lucky Pull", text = "Pull a Legendary or Secret card", kind = "luckyPull", target = 1, gems = 200, shards = 30 },
	{ id = "six_themes", name = "Six Flavours", text = "Win with a deck of each of the 6 themes", kind = "themes", target = 6, gems = 300, shards = 60 },
	{ id = "cup_champion", name = "Cup Champion", text = "Win a Cup", kind = "cup", target = 1, gems = 400, shards = 80 },
	{ id = "full_set", name = "Full Set", text = "Own every card of one theme", kind = "fullSet", target = 1, gems = 500, shards = 100 },
}
Progression.AchievementById = {}
for _, a in ipairs(Progression.Achievements) do
	Progression.AchievementById[a.id] = a
end

-- The Trophy Road: every match you finish earns trophies (more for a win, more against tougher
-- opponents); they never go down. Each stop on the road is claimed once at the Trophy Wall.
-- Three match backgrounds can only be earned here (ShopCatalog cosmetics with road = true), and
-- every other stop or so pays rune Shards for the Enchanting Crystal (770 along the whole road).
-- Wins: about 6 trophies a match, so the first background comes after 8-10 wins.
Progression.Trophies = {
	win = { Easy = 4, Medium = 6, Hard = 9 },
	pvpWin = 10, -- a win with only people on the other side
	finish = 1, -- a loss or a draw that went the distance
	cupWin = 25, -- on top of the final's win
}
-- Each stop: trophies needed, and the reward (gems / coins / shards / a cosmetic id), in order of
-- `at`. `key` is what the save remembers a claim by: never change or reuse one (a stop whose key
-- changed could be claimed twice). New stops get new keys, anywhere on the road.
Progression.TrophyRoad = {
	{ key = "s1", at = 5, shards = 20 },
	{ key = "1", at = 10, coins = 300 },
	{ key = "2", at = 25, gems = 200 },
	{ key = "s2", at = 35, shards = 30 },
	{ key = "3", at = 45, cosmetic = "bg_meadow" },
	{ key = "4", at = 70, coins = 600 },
	{ key = "s3", at = 85, shards = 40 },
	{ key = "5", at = 100, gems = 400 },
	{ key = "6", at = 140, cosmetic = "bg_fire" },
	{ key = "s4", at = 165, shards = 50 },
	{ key = "7", at = 190, coins = 1000 },
	{ key = "s5", at = 220, shards = 60 },
	{ key = "8", at = 250, gems = 600 },
	{ key = "s6", at = 285, shards = 70 },
	{ key = "9", at = 320, cosmetic = "bg_space" },
	{ key = "s7", at = 360, shards = 80 },
	{ key = "10", at = 400, gems = 1000 },
	{ key = "s8", at = 450, shards = 100 },
	{ key = "11", at = 500, coins = 2500 },
	{ key = "s9", at = 575, shards = 120 },
	{ key = "12", at = 650, gems = 1600 },
	{ key = "s10", at = 800, shards = 200 },
}

-- The key a claim of stop `index` is saved under.
function Progression.roadKey(index)
	local stop = Progression.TrophyRoad[index]
	return stop and (stop.key or tostring(index)) or nil
end

-- Trophies for one finished match. `m` is what PlayerData.recordMatch gets (plus m.pvp when no
-- bot sat on the other side).
function Progression.trophiesFor(m)
	local T = Progression.Trophies
	local n = 0
	if m.result == "win" then
		n = m.pvp and T.pvpWin or (T.win[m.difficulty] or T.win.Medium)
		if m.cupWon then
			n += T.cupWin
		end
	elseif m.result == "loss" or m.result == "draw" then
		n = T.finish
	end
	return n
end

-- Today's number (days since 1 January 1970, UTC). Daily things reset when it changes.
function Progression.today(now)
	return math.floor((now or os.time()) / 86400)
end

-- Seconds until the next daily reset.
function Progression.secondsToReset(now)
	now = now or os.time()
	return (Progression.today(now) + 1) * 86400 - now
end

-- The three daily quest ids for a player on a day (Easy, Medium, Hard): see Quests.rollDaily.
function Progression.questsFor(userId, day)
	return Quests.rollDaily(userId, day)
end

-- How much one match moves a quest along: see Quests.gain.
Progression.questGain = Quests.gain

return Progression

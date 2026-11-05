-- Reasons to come back: your level and XP, the daily reward and its streak, three daily quests,
-- the first win of the day and win streaks. The server (PlayerData) keeps the real numbers;
-- the screens use this module for the names, the rewards and the level curve.
--
-- Change the numbers here and both sides follow.

local Progression = {}

-- XP for one match. Everyone gets some, the winner more.
Progression.MatchXP = { win = 40, loss = 15, draw = 20 }

-- XP you need to go from `level` to the next one: 80, 100, 120 ... up to 400.
function Progression.xpForLevel(level)
	return math.min(400, 80 + 20 * (math.max(1, level) - 1))
end

-- Gems for reaching `level`: 30, and 100 on every 5th level.
function Progression.levelReward(level)
	return (level % 5 == 0) and 100 or 30
end

-- The daily reward: claim once a day. Coming back the next day moves you up a day; a day missed
-- starts you at day 1 again. After day 7 it starts over at day 1 (and keeps your streak count).
Progression.DailyRewards = { 20, 30, 40, 50, 60, 80, 150 }

function Progression.dailyReward(streakDay)
	local n = #Progression.DailyRewards
	return Progression.DailyRewards[((math.max(1, streakDay) - 1) % n) + 1]
end

-- Your first win each day pays this much extra.
Progression.FirstWinBonus = 50

-- Wins in a row pay extra: 2 in a row +5, 3 in a row +10 ... up to +25.
function Progression.streakBonus(streak)
	if streak < 2 then
		return 0
	end
	return math.min(25, 5 * (streak - 1))
end

-- Daily quests: three a day, picked from this list (at most one "win with a deck" quest).
-- kind: what counts. win, match (any match), creature / spell / building (cards played),
-- spark, damage (to enemy heroes), pop (enemy creatures popped), winHard (beat a Hard bot),
-- winDeck (win with the deck in `deck`).
Progression.QuestXP = 30
Progression.Quests = {
	{ id = "win2", text = "Win 2 matches", kind = "win", target = 2, gems = 40 },
	{ id = "play3", text = "Play 3 matches", kind = "match", target = 3, gems = 30 },
	{ id = "creatures10", text = "Play 10 creatures", kind = "creature", target = 10, gems = 30 },
	{ id = "spells4", text = "Cast 4 spells", kind = "spell", target = 4, gems = 30 },
	{ id = "buildings3", text = "Build 3 buildings", kind = "building", target = 3, gems = 30 },
	{ id = "sparks6", text = "Spark 6 times", kind = "spark", target = 6, gems = 30 },
	{ id = "damage30", text = "Deal 30 damage to enemy heroes", kind = "damage", target = 30, gems = 40 },
	{ id = "pops8", text = "Pop 8 enemy creatures", kind = "pop", target = 8, gems = 35 },
	{ id = "hard1", text = "Beat a Hard bot", kind = "winHard", target = 1, gems = 60 },
	{ id = "deckSnack", text = "Win with a Snack deck", kind = "winDeck", deck = "Snack", target = 1, gems = 45 },
	{ id = "deckJunk", text = "Win with a Junk deck", kind = "winDeck", deck = "Junk", target = 1, gems = 45 },
	{ id = "deckWeather", text = "Win with a Weather deck", kind = "winDeck", deck = "Weather", target = 1, gems = 45 },
	{ id = "deckCritter", text = "Win with a Critter deck", kind = "winDeck", deck = "Critter", target = 1, gems = 45 },
	{ id = "deckSpooky", text = "Win with a Spooky deck", kind = "winDeck", deck = "Spooky", target = 1, gems = 45 },
	{ id = "deckRobo", text = "Win with a Robo deck", kind = "winDeck", deck = "Robo", target = 1, gems = 45 },
}
Progression.QuestById = {}
for _, q in ipairs(Progression.Quests) do
	Progression.QuestById[q.id] = q
end
Progression.QuestsPerDay = 3

-- Achievements: one-time goals on the Trophy Wall, claimed once each.
-- kind: win (matches won), level (level reached), luckyPull (a Legendary or Secret pulled),
-- themes (won with each of the 6 themes: a deck counts for every theme it uses), cup (Cups won),
-- fullSet (own every card of one theme).
Progression.Achievements = {
	{ id = "first_win", name = "First Blood", text = "Win a match", kind = "win", target = 1, gems = 50 },
	{ id = "level_10", name = "Level Ten", text = "Reach level 10", kind = "level", target = 10, gems = 100 },
	{ id = "lucky_pull", name = "Lucky Pull", text = "Pull a Legendary or Secret card", kind = "luckyPull", target = 1, gems = 100 },
	{ id = "six_themes", name = "Six Flavours", text = "Win with a deck of each of the 6 themes", kind = "themes", target = 6, gems = 150 },
	{ id = "cup_champion", name = "Cup Champion", text = "Win a Cup", kind = "cup", target = 1, gems = 200 },
	{ id = "full_set", name = "Full Set", text = "Own every card of one theme", kind = "fullSet", target = 1, gems = 250 },
}
Progression.AchievementById = {}
for _, a in ipairs(Progression.Achievements) do
	Progression.AchievementById[a.id] = a
end

-- The Trophy Road: every match you finish earns trophies (more for a win, more against tougher
-- opponents); they never go down. Each stop on the road is claimed once at the Trophy Wall.
-- Three match backgrounds can only be earned here (ShopCatalog cosmetics with road = true).
-- Wins: about 6 trophies a match, so the first background comes after 8-10 wins.
Progression.Trophies = {
	win = { Easy = 4, Medium = 6, Hard = 9 },
	pvpWin = 10, -- a win with only people on the other side
	finish = 1, -- a loss or a draw that went the distance
	cupWin = 25, -- on top of the final's win
}
-- Each stop: trophies needed, and the reward (gems / coins / a cosmetic id).
Progression.TrophyRoad = {
	{ at = 10, coins = 300 },
	{ at = 25, gems = 50 },
	{ at = 45, cosmetic = "bg_meadow" },
	{ at = 70, coins = 600 },
	{ at = 100, gems = 100 },
	{ at = 140, cosmetic = "bg_fire" },
	{ at = 190, coins = 1000 },
	{ at = 250, gems = 150 },
	{ at = 320, cosmetic = "bg_space" },
	{ at = 400, gems = 250 },
	{ at = 500, coins = 2500 },
	{ at = 650, gems = 400 },
}

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

-- The three quest ids for a player on a day. The same player gets the same quests all day, on
-- every server.
function Progression.questsFor(userId, day)
	-- A small LCG seeded from the player and the day.
	local state = (math.abs(math.floor(tonumber(userId) or 0)) * 7919 + day * 104729) % 2147483647
	if state == 0 then
		state = 12345
	end
	local function nextInt(n)
		state = (state * 48271) % 2147483647
		return state % n + 1
	end
	local picked, used, deckQuest = {}, {}, false
	local guard = 0
	while #picked < Progression.QuestsPerDay and guard < 200 do
		guard += 1
		local q = Progression.Quests[nextInt(#Progression.Quests)]
		local isDeck = q.kind == "winDeck"
		if not used[q.id] and not (isDeck and deckQuest) then
			used[q.id] = true
			deckQuest = deckQuest or isDeck
			table.insert(picked, q.id)
		end
	end
	return picked
end

-- How much one match moves a quest along. `m` is what PlayerData.recordMatch gets.
function Progression.questGain(q, m)
	local stats = m.stats or {}
	local won = m.result == "win"
	if q.kind == "win" then
		return won and 1 or 0
	elseif q.kind == "match" then
		return 1
	elseif q.kind == "winHard" then
		return (won and m.beatHard) and 1 or 0
	elseif q.kind == "winDeck" then
		-- a practice deck by its key, or one of your own decks that uses this theme
		local themed = m.deck == q.deck or (type(m.themes) == "table" and table.find(m.themes, q.deck) ~= nil)
		return (won and themed) and 1 or 0
	end
	return stats[q.kind] or 0
end

return Progression

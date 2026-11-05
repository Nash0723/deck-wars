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
	{ id = "deckSnack", text = "Win with Sugar Rush", kind = "winDeck", deck = "Snack", target = 1, gems = 45 },
	{ id = "deckJunk", text = "Win with Scrap Heap", kind = "winDeck", deck = "Junk", target = 1, gems = 45 },
	{ id = "deckWeather", text = "Win with Storm Front", kind = "winDeck", deck = "Weather", target = 1, gems = 45 },
	{ id = "deckCritter", text = "Win with Critter Crew", kind = "winDeck", deck = "Critter", target = 1, gems = 45 },
	{ id = "deckSpooky", text = "Win with Haunted Mall", kind = "winDeck", deck = "Spooky", target = 1, gems = 45 },
	{ id = "deckRobo", text = "Win with Robo Rumble", kind = "winDeck", deck = "Robo", target = 1, gems = 45 },
}
Progression.QuestById = {}
for _, q in ipairs(Progression.Quests) do
	Progression.QuestById[q.id] = q
end
Progression.QuestsPerDay = 3

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
		return (won and m.deck == q.deck) and 1 or 0
	end
	return stats[q.kind] or 0
end

return Progression

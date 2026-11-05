-- Bot-vs-bot balance check for the six themed decks.
-- Run with: luaurun bal/balance.luau src/shared   (set BAL_GAMES before running to change the games per pairing)
local MatchEngine = require("MatchEngine")
local BotBrain = require("BotBrain")
local StarterDecks = require("StarterDecks")
local Rng = require("Rng")

local PER_PAIR = BAL_GAMES or 8 -- games per pairing, half with each deck going first
local DIFF = BAL_DIFF or "Hard"
local EXTRA = BAL_EXTRA -- true: give the second player a Spare Battery (nil: CardData.SecondPlayerCard decides)
local SEED = BAL_SEED or 0
local CardData = require("CardData")
if BAL_FIRSTDRAW ~= nil then -- try the game with or without the first player's first-turn draw
	CardData.FirstTurnDraw = BAL_FIRSTDRAW
end
local keys = StarterDecks.Order

-- Per card: in how many games each player played it, and how many of those they won
-- (BAL_CARDS = true prints one "CARD id games wins plays" line per card, for adding up runs).
local cardStats = {}
local function game(seed, a, b)
	local m = MatchEngine.new({ deck = a.cards, hero = a.hero, family = a.family }, { deck = b.cards, hero = b.hero, family = b.family, extraCard = EXTRA }, seed)
	local r = Rng.new(seed + 1)
	local played = { {}, {} }
	while not m.over do
		m:act(m.current, BotBrain.chooseAction(m, m.current, DIFF, r))
		for _, e in ipairs(m:takeEvents()) do
			if e.type == "play" and e.card and played[e.player] then
				played[e.player][e.card] = (played[e.player][e.card] or 0) + 1
			end
		end
	end
	for p = 1, 2 do
		for id, count in pairs(played[p]) do
			local s = cardStats[id] or { games = 0, wins = 0, plays = 0 }
			cardStats[id] = s
			s.games += 1
			s.plays += count
			if m.winner == p then
				s.wins += 1
			end
		end
	end
	return m.winner, m.turn
end

local wins, games = {}, {}
local pair = {}
local first, second, draws, turns, n = 0, 0, 0, 0, 0
local t0 = os.clock()
for i = 1, #keys do
	for j = i + 1, #keys do
		local A, B = keys[i], keys[j]
		local aw = 0
		for g = 1, PER_PAIR do
			local flip = g % 2 == 0
			local s1, s2 = StarterDecks[flip and B or A], StarterDecks[flip and A or B]
			local w, t = game(SEED + i * 1000 + j * 100 + g, s1, s2)
			n += 1
			turns += t
			if w == 0 then
				draws += 1
			else
				if w == 1 then
					first += 1
				else
					second += 1
				end
				local aWon = (w == 1) ~= flip
				local winner = aWon and A or B
				wins[winner] = (wins[winner] or 0) + 1
				if aWon then
					aw += 1
				end
			end
			games[A] = (games[A] or 0) + 1
			games[B] = (games[B] or 0) + 1
		end
		pair[A .. " vs " .. B] = aw .. "-" .. (PER_PAIR - aw)
	end
end
print(string.format("%d %s games%s in %.0fs, avg %.1f turns, first player %d, second %d, draws %d", n, DIFF, (EXTRA and " (second player gets a Spare Battery)" or "") .. (CardData.FirstTurnDraw and "" or " (first player skips the first draw)"), os.clock() - t0, turns / n, first, second, draws))
for _, k in ipairs(keys) do
	print(string.format("  %-8s %-13s %3d%%  (%d/%d)", k, StarterDecks[k].name, math.floor(100 * (wins[k] or 0) / games[k] + 0.5), wins[k] or 0, games[k]))
end
local lines = {}
for k, v in pairs(pair) do
	table.insert(lines, k .. " " .. v)
end
table.sort(lines)
print("  " .. table.concat(lines, ", "))
if BAL_CARDS then
	for _, id in ipairs(CardData.List) do
		local s = cardStats[id]
		if s then
			print(string.format("CARD %s %d %d %d", id, s.games, s.wins, s.plays))
		end
	end
end

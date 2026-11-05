-- Balance run for the Campaign: every stage, Normal and Hard, played many times by a bot standing
-- in for the player against the stage's opponent with all its rules (Campaign.applyRules, the same
-- code MatchServer uses). Prints the player's win rate, how often each star is earned and the
-- average length of a win, so the turn limits and boss numbers can be tuned.
--
-- The stand-in player: the Starter Deck with a Medium brain in the Card Den on Normal, then a full
-- themed deck (one of the practice decks, not the opponent's family) with a Medium brain on Normal
-- and a Hard brain on Hard (Hard opens after a world's boss: a player who has collected and
-- learned by then).
--
-- Run with: luaurun -D GAMES=40 bal/campaign_balance.luau src/shared

_G.warn = function() end
local Campaign = require("Campaign")
local CardData = require("CardData")
local MatchEngine = require("MatchEngine")
local BotBrain = require("BotBrain")
local DeckRules = require("DeckRules")
local StarterDecks = require("StarterDecks")
local Rng = require("Rng")

local GAMES = tonumber(GAMES) or 40

local function playerSetup(stage, i)
	if stage.world == "Den" and not stage.hard then
		return DeckRules.setupFor(DeckRules.starterDeck())
	end
	-- a themed deck that isn't the opponent's (cycled so no one family decides the numbers)
	local fams = {}
	for _, f in ipairs(CardData.Families) do
		if f ~= stage.family and StarterDecks[f] then
			table.insert(fams, f)
		end
	end
	local fam = fams[(i - 1) % #fams + 1]
	local deck = StarterDecks[fam]
	return { deck = table.clone(deck.cards), hero = deck.hero, family = deck.family, lanes = { deck.family, deck.family, deck.family, deck.family }, name = "You" }
end

local function run(stage)
	local wins, stars2, stars3, winTurns, all3 = 0, 0, 0, 0, 0
	for g = 1, GAMES do
		local me = playerSetup(stage, g)
		if stage.rules and table.find(stage.rules, "homeTurf") then
			me.lanes = { stage.family, stage.family, stage.family, stage.family }
		end
		local enemy = { deck = table.clone(stage.cards), hero = stage.hero, family = stage.family, lanes = { stage.family, stage.family, stage.family, stage.family }, name = stage.name }
		local youFirst = g % 2 == 1
		local setups = youFirst and { me, enemy } or { enemy, me }
		local mySeat = youFirst and 1 or 2
		local enemySeat = 3 - mySeat
		local m = MatchEngine.new(setups, 7000 + g * 31)
		m.silent = true
		Campaign.applyRules(m, stage, enemySeat)
		local rng = Rng.new(g * 97 + 5)
		local myBrain = stage.hard and "Hard" or "Medium"
		local guard = 0
		while not m.over and guard < 300 do
			guard += 1
			BotBrain.playTurn(m, m.current, m.current == enemySeat and stage.difficulty or myBrain, rng)
		end
		local myTeam = m.seats[mySeat].team
		if m.winner == myTeam then
			local t = m.teams[myTeam]
			local st = Campaign.starsFor(stage, { result = "win", hp = t.hp, maxHp = t.maxHp, turns = m.seats[mySeat].turns })
			wins += 1
			winTurns += m.seats[mySeat].turns
			if st[2] then
				stars2 += 1
			end
			if st[3] then
				stars3 += 1
			end
			if st[1] and st[2] and st[3] then
				all3 += 1
			end
		end
	end
	return {
		win = wins / GAMES,
		star2 = wins > 0 and stars2 / wins or 0,
		star3 = wins > 0 and stars3 / wins or 0,
		all3 = all3 / GAMES,
		turns = wins > 0 and winTurns / wins or 0,
	}
end

print(string.format("Campaign balance, %d games a stage", GAMES))
print("stage         opponent                 diff    hp  limit   win%  ♥star%  ⏱star%  3★%   turns")
for _, hard in ipairs({ false, true }) do
	for _, w in ipairs(Campaign.Worlds) do
		for act = 1, Campaign.Acts do
			local s = Campaign.stage(Campaign.stageId(w.key, act, hard))
			local r = run(s)
			print(string.format("%-12s  %-23s  %-6s  %3d  %5d  %5.0f  %6.0f  %6.0f  %4.0f  %5.1f", s.id, s.name, s.difficulty, s.enemyHp, s.turnLimit, r.win * 100, r.star2 * 100, r.star3 * 100, r.all3 * 100, r.turns))
		end
	end
end

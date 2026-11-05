-- Deck Wars match server: lobbies, matches and tournaments.
--
-- Every match runs on the server with the MatchEngine, so nobody can cheat from their own screen.
-- Ways to play (picked at the Duel Table):
--   Bot:        you against Bot Bonkers (Easy, Medium or Hard).
--   Duel:       1v1 against a friend.
--   Team:       2v2, two friends against two friends. Each team shares its hit points.
--   Tournament: 8 players, knockout: quarter-finals, semi-finals, final.
-- Duel, Team and Tournament start from a lobby: someone opens it, friends join and pick a deck,
-- the host can fill empty seats with bots, then presses Start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local MatchEngine = require(Shared:WaitForChild("MatchEngine"))
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local StarterDecks = require(Shared:WaitForChild("StarterDecks"))
local CardData = require(Shared:WaitForChild("CardData"))
local Rng = require(Shared:WaitForChild("Rng"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local DeckRules = require(Shared:WaitForChild("DeckRules"))
local PlayerDecks = require(script.Parent:WaitForChild("PlayerDecks"))
local Campaign = require(Shared:WaitForChild("Campaign"))
-- Match rewards in Gems (one table in ShopCatalog.Match, next to Nash's Coins and anti-farming rules).
local PullRates = {
	WinGems = (ShopCatalog.Match and ShopCatalog.Match.winGems) or { Easy = 20, Medium = 35, Hard = 50 },
	PvPWinGems = (ShopCatalog.Match and ShopCatalog.Match.pvpWinGems) or 40,
	CupWinGems = (ShopCatalog.Match and ShopCatalog.Match.cupWinGems) or 150,
	CupRunnerUpGems = (ShopCatalog.Match and ShopCatalog.Match.cupRunnerUpGems) or 50,
}

-- Wins pay through the save system (PlayerData on Nash's profile). It's optional, so this script
-- also runs without it (like in the simulated Studio the tests use).
local playerDataModule = script.Parent:FindFirstChild("PlayerData")
local PlayerData = playerDataModule and require(playerDataModule)
-- Campaign stars, unlocks and rewards (also optional, like PlayerData).
local campaignDataModule = script.Parent:FindFirstChild("CampaignData")
local CampaignData = campaignDataModule and require(campaignDataModule)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent") -- server -> client: board updates
local MatchAction = Remotes:WaitForChild("MatchAction") -- client -> server: play, spark, big move, battle
local MenuAction = Remotes:WaitForChild("MenuAction") -- client -> server: start / join / leave
local LobbyEvent = Remotes:WaitForChild("LobbyEvent") -- server -> client: open lobbies, tournament brackets, parties and invites

-- Pacing. Raise these numbers to make matches slower, lower them to speed up.
local TURN_SECONDS = 75 -- time you get for your turn (the clock pauses while animations play)
local BOT_TURN_START_PAUSE = 1.2 -- the bot "looks at the board" before its first move
-- Pause before each bot action, by kind.
local BOT_THINK_SECONDS = { play = 1.6, spark = 1.2, shift = 1.0, bigmove = 1.8, battle = 1.0 }
local BOT_MAX_ACTIONS = 40 -- safety: the bot battles after this many actions
-- The server waits for every player's screen to finish animating before it moves on, but never
-- longer than this (in case someone's game is lagging or closed).
local ANIMATION_WAIT_BASE = 6
local ANIMATION_WAIT_PER_EVENT = 0.6
local ANIMATION_WAIT_MAX = 60
local RESULT_SCREEN_SECONDS = 12 -- how long the result shows before players go back (they can leave sooner, or play again)
local FAST_BOT_PAUSES = 0.45 -- bots pause this much as long when everyone in the match has "⏩ Speed: Fast" on
local CUP_ROUND_PAUSE = 4 -- pause between tournament rounds
local BOT_ONLY_MATCH_SECONDS = 8 -- a tournament match between two bots "takes" this long

local DIFFICULTIES = { Easy = true, Medium = true, Hard = true }
local MODES = {
	Duel = { size = 2, label = "1v1 Duel" },
	Team = { size = 4, label = "2v2 Team Battle" },
	Cup = { size = 8, label = "Tournament (8 players)" },
}
local ROUND_NAMES = { "Quarter-finals", "Semi-finals", "Final" }
local PARTY_MAX = 8 -- a whole tournament's worth of friends
local INVITE_SECONDS = 60 -- how long a party invite stays open
local OUTSIDE_INVITE_SECONDS = 600 -- a friend who joins within this long after you opened Roblox's invite prompt gets a party invite

local matches = {} -- [player] = the match they're playing
local lobbies = {} -- [id] = lobby
local lobbyOf = {} -- [player] = lobby id
local nextLobbyId = 0
local partyOf = {} -- [player] = their party: { leader = player, members = { players } }
local invites = {} -- [invited player] = { [player who invited them] = when the invite runs out }
local lastDeck = {} -- [player] = the deck they picked last (they bring it when their party sits them down)
local outsideInvites = {} -- [player] = when they last opened Roblox's invite prompt
local bringParty -- defined with the parties, used by the lobbies
local startBotMatch, savePrefs -- defined next to the menu actions
local startCampaignMatch -- defined after the bot match
local reopenLobby -- defined with the lobbies

-- A whole number from the client, or nil (no NaN, no huge values). User ids are big, so the cap is
-- generous; it only keeps out NaN, infinity and nonsense.
local function whole(v)
	v = tonumber(v)
	if v == nil or v ~= v or math.abs(v) > 1e15 then
		return nil
	end
	return math.floor(v)
end

local function now()
	return workspace:GetServerTimeNow()
end

-- A deck is a practice deck's key ("Snack"...) or one of the player's saved decks: "s1", "s2"...
local function savedSlot(key)
	local n = type(key) == "string" and tonumber(string.match(key, "^s(%d+)$"))
	return n
end

local function deckOk(key, player)
	if type(key) ~= "string" then
		return false
	end
	if StarterDecks[key] ~= nil then
		return true
	end
	local slot = savedSlot(key)
	if slot and (player == nil or PlayerDecks.setupFor(player, slot) ~= nil) then
		return true
	end
	return false
end

-- The MatchEngine setup for a seat's deck: a saved deck (checked against what the player owns
-- right now) or a practice deck, with its lane terrains and themes.
local function setupForSeat(seat)
	if type(seat.setup) == "table" then
		-- a campaign opponent: its deck is made by the Campaign rules
		local s = seat.setup
		return { deck = table.clone(s.deck), hero = s.hero, family = s.family, themes = { s.family }, lanes = s.lanes and table.clone(s.lanes) }
	end
	local slot = savedSlot(seat.deck)
	if slot and seat.kind == "human" then
		local setup = PlayerDecks.setupFor(seat.player, slot)
		if setup then
			return setup
		end
	end
	local practice = StarterDecks[seat.deck] or StarterDecks.Snack
	local ok, setup = pcall(function()
		return DeckRules.setupFor(DeckRules.fromPractice(practice))
	end)
	if ok and setup then
		return setup
	end
	return { deck = table.clone(practice.cards), hero = practice.hero, family = practice.family, themes = { practice.family } }
end

-- Home Turf (a campaign rule): the human's lanes take the opponent's landscape.
do
	local plainSetup = setupForSeat
	setupForSeat = function(seat)
		local setup = plainSetup(seat)
		if seat.lanesOverride and setup then
			setup = table.clone(setup)
			setup.lanes = table.clone(seat.lanesOverride)
		end
		return setup
	end
end

local function randomDeck(rng)
	return rng:pick(StarterDecks.Order)
end

local function addGems(player, amount)
	if PlayerData and player and player.Parent and amount > 0 then
		return PlayerData.addGems(player, amount) ~= nil
	end
	return false
end

---------------------------------------------------------------------------
-- A match: any mix of humans and bots in 2 or 4 seats
---------------------------------------------------------------------------

local Match = {}
Match.__index = Match

-- Hide the cards other players draw.
local function filterEvents(events, viewer)
	local out = {}
	for _, e in ipairs(events) do
		if (e.type == "draw" or e.type == "burn") and e.seat ~= viewer then
			table.insert(out, { type = e.type, seat = e.seat })
		else
			table.insert(out, e)
		end
	end
	return out
end

-- seats: { { kind = "human", player = Player, deck = "Snack" } or { kind = "bot", difficulty = "Hard", deck = "Robo" } }
-- opts: { mode = "Bot" | "Duel" | "Team" | "Cup", label = "Quarter-final 2", onFinished = function(match, winnerTeam) }
function Match.new(seats, opts)
	local self = setmetatable({}, Match)
	self.opts = opts or {}
	self.mode = self.opts.mode or "Bot"
	local seed = math.floor(now() * 1000) % 2147483647
	self.rng = Rng.new(seed + 11)
	self.seats = seats
	local setups = {}
	for i, seat in ipairs(seats) do
		seat.name = seat.name or (seat.kind == "human" and seat.player.DisplayName) or ("Bot Bonkers (" .. (seat.difficulty or "Medium") .. ")")
		local setup = setupForSeat(seat)
		seat.themes = setup.themes
		setups[i] = { deck = setup.deck, hero = setup.hero, family = setup.family, lanes = setup.lanes, name = seat.name }
		if seat.kind == "human" then
			seat.seq = 0
			seat.ack = 0
			seat.busyUntil = 0
			seat.deadlines = {}
			seat.fast = seat.player:GetAttribute("PrefFast") == true
		else
			seat.botRng = Rng.new(seed + i * 97)
		end
	end
	self.engine = MatchEngine.new(setups, seed)
	self.turnSeconds = TURN_SECONDS
	if self.opts.campaign then
		self:applyCampaignRules(self.opts.campaign)
	end
	self.startedAt = now()
	-- What each seat did, for daily quests: cards played by type, Sparks, enemy creatures popped.
	self.stats = {}
	for i in ipairs(seats) do
		self.stats[i] = { creature = 0, spell = 0, building = 0, spark = 0, pop = 0, damage = 0 }
	end
	self.unitTeam = {} -- [uid] = team, to know whose creature popped
	self.turnToken = 0
	self.turnEndsAt = 0
	self.turnRemaining = self.turnSeconds
	self.ended = false
	self.botRunning = false
	for _, seat in ipairs(seats) do
		if seat.kind == "human" then
			matches[seat.player] = self
		end
	end
	return self
end

-- The rules of a campaign stage (Campaign.Rules), on the engine that was just made. The bot seats
-- are the stage's opponent; the humans play their own decks.
function Match:applyCampaignRules(stage)
	local m = self.engine
	local enemyTeam = nil
	for i, seat in ipairs(self.seats) do
		if seat.kind == "bot" then
			enemyTeam = m.seats[i].team
		end
	end
	if not enemyTeam then
		return
	end
	m.teams[enemyTeam].hp = stage.enemyHp
	m.teams[enemyTeam].maxHp = stage.enemyHp
	for _, ruleId in ipairs(stage.rules or {}) do
		local rule = Campaign.Rules[ruleId]
		if rule then
			for i, seat in ipairs(self.seats) do
				local es = m.seats[i]
				if seat.kind == "bot" and es.team == enemyTeam then
					for _ = 1, rule.extraCards or 0 do
						m:draw(i)
					end
					if rule.magicBonus then
						es.magicBonus = (es.magicBonus or 0) + rule.magicBonus
						if m.current == i then
							es.magic += rule.magicBonus -- its first turn already started
						end
					end
					if rule.bigStart then
						es.dealt = math.max(es.dealt or 0, CardData.BigMoveCharge or 10)
					end
				end
			end
			if rule.turnSeconds then
				self.turnSeconds = math.min(self.turnSeconds, rule.turnSeconds)
			end
		end
	end
end

function Match:humans()
	local out = {}
	for i, seat in ipairs(self.seats) do
		if seat.kind == "human" and seat.player.Parent and not seat.left then
			table.insert(out, i)
		end
	end
	return out
end

-- "⏩ Speed: Fast" on or off for one player.
function Match:setFast(player, on)
	local s = self:seatOf(player)
	if s then
		self.seats[s].fast = on == true
	end
end

-- A bot's pause, shorter when every human watching wants it fast.
function Match:pause(seconds)
	local humans = self:humans()
	if #humans == 0 then
		return seconds
	end
	for _, s in ipairs(humans) do
		if not self.seats[s].fast then
			return seconds
		end
	end
	return seconds * FAST_BOT_PAUSES
end

-- A player is done with this match after it ended (they pressed Play again or went back early).
-- They stop getting its updates, and its "ended" message, which would pull them out of whatever
-- they're doing next.
function Match:release(player)
	local s = self:seatOf(player)
	if not s then
		return
	end
	local seat = self.seats[s]
	seat.left = true
	seat.released = true
	if matches[player] == self then
		matches[player] = nil
	end
end

function Match:seatOf(player)
	for i, seat in ipairs(self.seats) do
		if seat.kind == "human" and seat.player == player then
			return i
		end
	end
	return nil
end

-- Counts what each seat did (for daily quests).
function Match:countEvents(events)
	local m = self.engine
	for _, e in ipairs(events) do
		if e.type == "summon" and e.unit then
			self.unitTeam[e.unit.uid] = e.unit.team
		elseif e.type == "play" and self.stats[e.seat] then
			local c = CardData.Cards[e.id]
			local kind = c and string.lower(c.type)
			if kind and self.stats[e.seat][kind] then
				self.stats[e.seat][kind] += 1
			end
		elseif e.type == "spark" and self.stats[e.seat] then
			self.stats[e.seat].spark += 1
		elseif e.type == "pop" then
			local team = self.unitTeam[e.uid]
			if team then
				for s, st in ipairs(self.stats) do
					if m.seats[s] and m.seats[s].team ~= team then
						st.pop += 1
					end
				end
			end
		end
	end
end

-- Sends the board to every player. Returns the latest update numbers, so the server can wait
-- for the screens to catch up.
function Match:sendUpdate(extra)
	local m = self.engine
	local events = m:takeEvents()
	self:countEvents(events)
	local names = {}
	for i, seat in ipairs(self.seats) do
		names[i] = { name = seat.name, bot = seat.kind == "bot", userId = seat.kind == "human" and seat.player.UserId or nil, boss = seat.bossCard }
	end
	for _, s in ipairs(self:humans()) do
		local seat = self.seats[s]
		local view = m:viewFor(s)
		view.legal = (m.current == s and not m.over) and m:listActions(s) or {}
		view.turnEndsAt = self.turnEndsAt
		view.names = names
		view.mode = self.mode
		view.label = self.opts.label
		local mine = filterEvents(events, s)
		seat.seq += 1
		local payload = { kind = "update", seq = seat.seq, view = view, events = mine }
		if extra then
			-- Per-seat tables (results, gems, rewards) aren't sent whole: each player only gets their own
			-- below (they'd also be arrays with holes, which a RemoteEvent cuts short).
			for k, v in pairs(extra) do
				if k ~= "results" and k ~= "gems" and k ~= "rewards" then
					payload[k] = v
				end
			end
			if extra.results then
				payload.result = extra.results[s]
				payload.gemsEarned = extra.gems and extra.gems[s]
				payload.rewards = extra.rewards and extra.rewards[s]
			end
		end
		local limit = math.min(ANIMATION_WAIT_MAX, ANIMATION_WAIT_BASE + ANIMATION_WAIT_PER_EVENT * #mine)
		seat.busyUntil = math.max(seat.busyUntil, now()) + limit
		seat.deadlines[seat.seq] = seat.busyUntil
		MatchEvent:FireClient(seat.player, payload)
	end
end

-- Waits until every player's screen has shown the latest update (or its time ran out).
function Match:waitForScreens()
	while not self.ended do
		local waiting = false
		for _, s in ipairs(self:humans()) do
			local seat = self.seats[s]
			local deadline = seat.deadlines[seat.seq] or 0
			if seat.ack < seat.seq and now() < deadline then
				waiting = true
				break
			end
		end
		if not waiting then
			return
		end
		task.wait(0.1)
	end
end

function Match:onAck(player, n)
	local s = self:seatOf(player)
	local seat = s and self.seats[s]
	if seat and type(n) == "number" and n == n and n > seat.ack and n <= seat.seq then
		seat.ack = math.floor(n)
		for k in pairs(seat.deadlines) do
			if k <= seat.ack then
				seat.deadlines[k] = nil
			end
		end
	end
end

function Match:finish(reason)
	if self.ended then
		return
	end
	self.ended = true
	for _, seat in ipairs(self.seats) do
		if seat.kind == "human" then
			if matches[seat.player] == self then
				matches[seat.player] = nil
			end
			if seat.player.Parent and not seat.left then
				MatchEvent:FireClient(seat.player, { kind = "ended", reason = reason, mode = self.mode })
			end
		end
	end
	if self.opts.onFinished then
		task.spawn(self.opts.onFinished, self, self.engine.winner, reason)
	end
end

-- Pays out Gems and XP, moves daily quests along, and shows everyone their result, then sends
-- them back to the room.
function Match:finishIfOver()
	local m = self.engine
	if not m.over then
		return false
	end
	local results, gems, rewards = {}, {}, {}
	for s, seat in ipairs(self.seats) do
		local team = m.seats[s].team
		local result = (m.winner == 0 and "draw") or (m.winner == team and "win") or "loss"
		results[s] = result
		if seat.kind == "human" and seat.player.Parent and not self.opts.noGems then
			-- Beating only humans pays the friends' rate. With a bot on the other side, the win
			-- pays like a bot match (the hardest bot there counts), so filling seats with Easy
			-- bots doesn't farm Gems.
			local amount = 0
			local beatHard = false
			if result == "win" then
				amount = PullRates.PvPWinGems or 40
				local botRate = nil
				for o, other in ipairs(self.seats) do
					if other.kind == "bot" and m.seats[o].team ~= team then
						botRate = math.max(botRate or 0, PullRates.WinGems[other.difficulty] or 0)
						beatHard = beatHard or other.difficulty == "Hard"
					end
				end
				if botRate then
					amount = botRate
				end
			end
			local stats = table.clone(self.stats[s])
			stats.damage = m.seats[s].dealt or 0
			local hardest = nil
			local rank = { Easy = 1, Medium = 2, Hard = 3 }
			for o, other in ipairs(self.seats) do
				if other.kind == "bot" and m.seats[o].team ~= team and (rank[other.difficulty] or 0) > (rank[hardest] or 0) then
					hardest = other.difficulty
				end
			end
			local r = PlayerData and PlayerData.recordMatch and PlayerData.recordMatch(seat.player, {
				result = result,
				winGems = amount,
				deck = seat.deck,
				themes = seat.themes,
				beatHard = beatHard,
				mode = self.mode,
				-- Coins: bot matches pay by the bot's difficulty, matches against people like Hard.
				difficulty = hardest or "Hard",
				seconds = now() - (self.startedAt or now()),
				turns = math.floor((m.seats[s].turns or 0)),
				stats = stats,
			})
			-- A campaign stage: stars, first-clear rewards, drops and chests (CampaignData).
			local camp = nil
			if self.opts.campaign and CampaignData then
				local ok, res = pcall(CampaignData.record, seat.player, self.opts.campaign, {
					result = result,
					hp = m.teams[team].hp,
					maxHp = m.teams[team].maxHp,
					turns = m.seats[s].turns or 0,
				})
				if ok then
					camp = res
				else
					warn("[MatchServer] campaign rewards failed: " .. tostring(res))
				end
			end
			if r then
				rewards[s] = r
				gems[s] = r.totalGems > 0 and r.totalGems or nil
			elseif amount > 0 and addGems(seat.player, amount) then
				gems[s] = amount
			end
			if camp then
				local rw = rewards[s] or { gems = {}, totalGems = gems[s] or 0 }
				rw.gems = rw.gems or {}
				for _, g in ipairs(camp.gems) do
					table.insert(rw.gems, g)
				end
				rw.totalGems = (rw.totalGems or 0) + (camp.totalGems or 0)
				rw.campaign = camp
				rewards[s] = rw
				gems[s] = rw.totalGems > 0 and rw.totalGems or nil
			end
		end
	end
	self.turnToken += 1
	self.turnEndsAt = 0
	self:sendUpdate({ results = results, gems = gems, rewards = rewards, winnerTeam = m.winner })
	task.spawn(function()
		self:waitForScreens()
		task.wait(RESULT_SCREEN_SECONDS)
		self:finish("finished")
	end)
	return true
end

-- What to do after anything happened: the next bot moves, or the next human's clock starts.
function Match:continue(notice)
	if self.ended then
		return
	end
	self:sendUpdate(notice and { notice = notice } or nil)
	if self:finishIfOver() then
		return
	end
	local current = self.seats[self.engine.current]
	if current.kind == "bot" or current.left then
		task.spawn(function()
			self:runBotTurn()
		end)
	else
		self:startClockAfterScreens()
	end
end

function Match:startClockAfterScreens()
	self.turnToken += 1
	local token = self.turnToken
	local seatIndex = self.engine.current
	task.spawn(function()
		self:waitForScreens()
		if self.ended or self.turnToken ~= token or self.engine.current ~= seatIndex or self.engine.over then
			return
		end
		self.turnEndsAt = now() + self.turnRemaining
		for _, s in ipairs(self:humans()) do
			MatchEvent:FireClient(self.seats[s].player, { kind = "timer", turnEndsAt = self.turnEndsAt, current = seatIndex })
		end
		local seconds = self.turnRemaining
		task.delay(seconds, function()
			if not self.ended and self.turnToken == token and self.engine.current == seatIndex and not self.engine.over then
				self:timeUp()
			end
		end)
	end)
end

function Match:pauseClock()
	if self.turnEndsAt > 0 then
		self.turnRemaining = math.max(10, self.turnEndsAt - now())
	end
	self.turnToken += 1
	self.turnEndsAt = 0
end

function Match:timeUp()
	local s = self.engine.current
	self.engine:act(s, { kind = "battle" })
	self.turnRemaining = self.turnSeconds
	self.turnEndsAt = 0
	self:continue("Time's up! " .. self.seats[s].name .. "'s creatures battle on their own.")
end

function Match:runBotTurn()
	if self.botRunning or self.ended then
		return
	end
	self.botRunning = true
	local m = self.engine
	local s = m.current
	local seat = self.seats[s]
	self:waitForScreens()
	if not self.ended then
		task.wait(self:pause(BOT_TURN_START_PAUSE))
	end
	local count = 0
	while not self.ended and not m.over and m.current == s do
		local difficulty = seat.difficulty or "Medium"
		local action = BotBrain.chooseAction(m, s, difficulty, seat.botRng or self.rng)
		count += 1
		if count > BOT_MAX_ACTIONS then
			action = { kind = "battle" }
		end
		task.wait(self:pause(BOT_THINK_SECONDS[action.kind] or 1.2))
		if self.ended or m.over or m.current ~= s then
			break
		end
		local ok = m:act(s, action)
		if not ok then
			m:act(s, { kind = "battle" })
		end
		if m.current ~= s or m.over then
			break
		end
		self:sendUpdate()
		self:waitForScreens()
	end
	self.botRunning = false
	self.turnRemaining = self.turnSeconds
	self:continue()
end

function Match:onAction(player, action)
	local s = self:seatOf(player)
	if not s or self.ended or self.engine.over then
		return
	end
	if self.engine.current ~= s then
		MatchEvent:FireClient(player, { kind = "error", message = "It's not your turn" })
		return
	end
	local ok, err = self.engine:act(s, action)
	if not ok then
		MatchEvent:FireClient(player, { kind = "error", message = err })
		return
	end
	self:pauseClock()
	if self.engine.current ~= s then
		self.turnRemaining = self.turnSeconds
	end
	self:continue()
end

-- A player left or disconnected. In 1v1 their opponent wins; in 2v2 a bot takes their seat.
function Match:onLeave(player)
	local s = self:seatOf(player)
	if not s or self.ended or self.seats[s].released then
		return
	end
	if self.engine.over then
		-- Leaving from the result screen: nothing to forfeit, just go.
		self:release(player)
		if player.Parent then
			MatchEvent:FireClient(player, { kind = "ended", reason = "back", mode = self.mode })
		end
		return
	end
	local seat = self.seats[s]
	seat.left = true
	if matches[player] == self then
		matches[player] = nil
	end
	if seat.player.Parent then
		MatchEvent:FireClient(seat.player, { kind = "ended", reason = "left", mode = self.mode })
	end
	local m = self.engine
	if #self:humans() == 0 then
		-- Nobody left to watch: just end it (in a tournament the other side wins).
		if not m.over then
			m.over = true
			m.winner = 3 - m.seats[s].team
		end
		self:finish("abandoned")
		return
	end
	if self.mode == "Team" then
		self:pauseClock()
		seat.kind = "bot"
		seat.difficulty = "Medium"
		seat.botRng = Rng.new(s * 13 + 5)
		seat.name = seat.name .. " (bot)"
		self:continue(seat.name .. " left, a bot takes over.")
		return
	end
	-- 1v1: the other side wins.
	if not m.over then
		m.over = true
		m.winner = 3 - m.seats[s].team
		m:emit({ type = "win", winner = m.winner, forfeit = true })
	end
	self:sendUpdate({ notice = seat.name .. " left the match." })
	self:finishIfOver()
end

function Match:start(extra)
	local m = self.engine
	local payload = { started = true, firstSeat = m.current }
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	self:sendUpdate(payload)
	local current = self.seats[m.current]
	if current.kind == "bot" then
		task.spawn(function()
			self:runBotTurn()
		end)
	else
		self:startClockAfterScreens()
	end
end

-- A match between two bots nobody watches (tournaments): played out instantly.
local function playBotOnly(seats, seed)
	local setups = {}
	for i, seat in ipairs(seats) do
		local setup = setupForSeat(seat)
		setups[i] = { deck = setup.deck, hero = setup.hero, family = setup.family, lanes = setup.lanes }
	end
	local m = MatchEngine.new(setups, seed)
	m.silent = true
	local rng = Rng.new(seed + 3)
	local guard = 0
	while not m.over and guard < 200 do
		guard += 1
		BotBrain.playTurn(m, m.current, seats[m.current].difficulty or "Medium", rng)
	end
	if not m.over then
		return rng:int(1, 2)
	end
	return m.winner ~= 0 and m.winner or rng:int(1, 2)
end

---------------------------------------------------------------------------
-- Lobbies
---------------------------------------------------------------------------

local function lobbySummary(lobby)
	local slots = {}
	for i = 1, lobby.size do
		local slot = lobby.slots[i]
		if slot then
			slots[i] = {
				kind = slot.kind,
				name = slot.kind == "human" and slot.player.DisplayName or ("Bot (" .. slot.difficulty .. ")"),
				userId = slot.kind == "human" and slot.player.UserId or nil,
				deck = slot.deck,
				deckName = nil,
				deckFamily = nil,
				difficulty = slot.difficulty,
			}
			-- A saved deck ("s2") shows its own name and theme to the others at the table.
			local n = savedSlot(slot.deck)
			if n and slot.kind == "human" then
				local info = PlayerDecks.deckInfo(slot.player, n)
				if info then
					slots[i].deckName = info.name
					slots[i].deckFamily = info.family
				end
			elseif StarterDecks[slot.deck] then
				slots[i].deckName = StarterDecks[slot.deck].name
				slots[i].deckFamily = StarterDecks[slot.deck].family
			end
		else
			slots[i] = { kind = "empty" }
		end
	end
	return {
		id = lobby.id,
		mode = lobby.mode,
		label = MODES[lobby.mode].label,
		host = lobby.host.DisplayName,
		hostId = lobby.host.UserId,
		size = lobby.size,
		slots = slots,
		started = lobby.started,
		cup = lobby.cup and lobby.cup.summary or nil,
	}
end

local function broadcastLobbies()
	local list = {}
	for _, lobby in pairs(lobbies) do
		table.insert(list, lobbySummary(lobby))
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	LobbyEvent:FireAllClients({ kind = "lobbies", list = list })
end

local function closeLobby(lobby, why)
	if lobbies[lobby.id] ~= lobby then
		return
	end
	lobbies[lobby.id] = nil
	for _, slot in pairs(lobby.slots) do
		if slot.kind == "human" and lobbyOf[slot.player] == lobby.id then
			lobbyOf[slot.player] = nil
			if why and slot.player.Parent then
				LobbyEvent:FireClient(slot.player, { kind = "toast", text = why })
			end
		end
	end
	broadcastLobbies()
end

local function slotIndexOf(lobby, player)
	for i = 1, lobby.size do
		local slot = lobby.slots[i]
		if slot and slot.kind == "human" and slot.player == player then
			return i
		end
	end
	return nil
end

local function leaveLobby(player)
	local id = lobbyOf[player]
	local lobby = id and lobbies[id]
	lobbyOf[player] = nil
	if not lobby then
		return
	end
	local i = slotIndexOf(lobby, player)
	if lobby.started then
		-- Leaving a running tournament: you forfeit your next match.
		if lobby.cup and i then
			lobby.cup.gone[i] = true
		end
		broadcastLobbies()
		return
	end
	if i then
		lobby.slots[i] = nil
	end
	if lobby.host == player then
		-- The next human becomes host, or the lobby closes.
		local nextHost = nil
		for k = 1, lobby.size do
			local slot = lobby.slots[k]
			if slot and slot.kind == "human" then
				nextHost = slot.player
				break
			end
		end
		if nextHost then
			lobby.host = nextHost
		else
			closeLobby(lobby, nil)
			return
		end
	end
	broadcastLobbies()
end

local function createLobby(player, mode, deck)
	if matches[player] or not MODES[mode] then
		return
	end
	leaveLobby(player)
	nextLobbyId += 1
	local lobby = {
		id = nextLobbyId,
		mode = mode,
		size = MODES[mode].size,
		host = player,
		slots = { { kind = "human", player = player, deck = deckOk(deck, player) and deck or "Snack" } },
		started = false,
	}
	lobbies[lobby.id] = lobby
	lobbyOf[player] = lobby.id
	broadcastLobbies()
	bringParty(player)
end

local function joinLobby(player, id, deck, slotWanted)
	local lobby = lobbies[id]
	if matches[player] or not lobby or lobby.started then
		return
	end
	local fresh = lobbyOf[player] ~= id
	if fresh then
		leaveLobby(player)
	end
	local current = slotIndexOf(lobby, player)
	local target = nil
	if type(slotWanted) == "number" and lobby.slots[slotWanted] == nil and slotWanted >= 1 and slotWanted <= lobby.size then
		target = slotWanted
	elseif not current then
		for i = 1, lobby.size do
			if not lobby.slots[i] then
				target = i
				break
			end
		end
	end
	if not target and not current then
		LobbyEvent:FireClient(player, { kind = "toast", text = "That table is full." })
		return
	end
	local slot = current and lobby.slots[current] or { kind = "human", player = player, deck = "Snack" }
	if deckOk(deck, player) then
		slot.deck = deck
	end
	if target then
		if current then
			lobby.slots[current] = nil
		end
		lobby.slots[target] = slot
	end
	lobbyOf[player] = id
	broadcastLobbies()
	if fresh then
		bringParty(player)
	end
end

---------------------------------------------------------------------------
-- Parties: play with friends
--
-- Invite someone in this server (or bring Roblox friends in with the invite prompt, see
-- PartyScreen). When the party leader opens a table or sits down at one, the rest of the party sits
-- down with them, so a party of two is one click from a 1v1 or a 2v2 on the same team.
---------------------------------------------------------------------------

local function toast(player, text)
	if player.Parent then
		LobbyEvent:FireClient(player, { kind = "toast", text = text })
	end
end

local function partySummary(party)
	local members = {}
	for _, p in ipairs(party.members) do
		table.insert(members, { userId = p.UserId, name = p.DisplayName, leader = p == party.leader })
	end
	return { leaderId = party.leader.UserId, members = members, max = PARTY_MAX }
end

local function sendParty(player)
	if player.Parent then
		local party = partyOf[player]
		LobbyEvent:FireClient(player, { kind = "party", party = party and partySummary(party) or nil })
	end
end

local function sendPartyToAll(party)
	for _, p in ipairs(party.members) do
		sendParty(p)
	end
end

local function leaveParty(player)
	local party = partyOf[player]
	if not party then
		return
	end
	partyOf[player] = nil
	local i = table.find(party.members, player)
	if i then
		table.remove(party.members, i)
	end
	sendParty(player)
	if #party.members <= 1 then
		-- A party of one is no party.
		for _, p in ipairs(party.members) do
			partyOf[p] = nil
			sendParty(p)
			toast(p, player.DisplayName .. " left, so the party ended.")
		end
		party.members = {}
		return
	end
	if party.leader == player then
		party.leader = party.members[1]
	end
	for _, p in ipairs(party.members) do
		toast(p, player.DisplayName .. " left the party." .. (p == party.leader and " You lead it now." or ""))
	end
	sendPartyToAll(party)
end

-- Put `player` in `inviter`'s party (making one if needed). Returns true if they're in.
local function joinParty(player, inviter)
	if player == inviter or not inviter.Parent or not player.Parent then
		return false
	end
	local party = partyOf[inviter]
	if party and partyOf[player] == party then
		return true
	end
	if party and #party.members >= PARTY_MAX then
		toast(player, inviter.DisplayName .. "'s party is full.")
		return false
	end
	leaveParty(player)
	if not party then
		party = { leader = inviter, members = { inviter } }
		partyOf[inviter] = party
	end
	table.insert(party.members, player)
	partyOf[player] = party
	for _, p in ipairs(party.members) do
		toast(p, p == player and ("You joined " .. party.leader.DisplayName .. "'s party!") or (player.DisplayName .. " joined the party!"))
	end
	sendPartyToAll(party)
	-- Already at a table? Sit the newcomer down too.
	bringParty(party.leader)
	return true
end

-- The leader just sat down at a table that hasn't started: everyone else in the party who isn't
-- busy (in a match or a running tournament) sits down with them, as long as there are seats.
function bringParty(leader)
	local party = partyOf[leader]
	local id = lobbyOf[leader]
	local lobby = id and lobbies[id]
	if not party or party.leader ~= leader or not lobby or lobby.started then
		return
	end
	for _, p in ipairs(party.members) do
		local current = lobbyOf[p] and lobbies[lobbyOf[p]]
		if p ~= leader and p.Parent and not matches[p] and lobbyOf[p] ~= id and not (current and current.started) then
			local free = false
			for i = 1, lobby.size do
				free = free or lobby.slots[i] == nil
			end
			if not free then
				toast(p, "No seat left for you at " .. leader.DisplayName .. "'s table.")
			else
				joinLobby(p, id, lastDeck[p], nil)
				if lobbyOf[p] == id then
					toast(p, "You sat down with " .. leader.DisplayName .. " (" .. MODES[lobby.mode].label .. ").")
				end
			end
		end
	end
end

local function invite(player, target)
	if not target or target == player or not target.Parent then
		return
	end
	local party = partyOf[player]
	if party and partyOf[target] == party then
		toast(player, target.DisplayName .. " is already in your party.")
		return
	end
	if party and #party.members >= PARTY_MAX then
		toast(player, "Your party is full (" .. PARTY_MAX .. ").")
		return
	end
	invites[target] = invites[target] or {}
	local open = invites[target][player]
	if open and open > now() then
		toast(player, "You already invited " .. target.DisplayName .. ".")
		return
	end
	invites[target][player] = now() + INVITE_SECONDS
	LobbyEvent:FireClient(target, {
		kind = "invite",
		fromUserId = player.UserId,
		fromName = player.DisplayName,
		size = party and #party.members or 1,
	})
	toast(player, "Invited " .. target.DisplayName .. ".")
end

local function answerInvite(player, fromUserId, accept)
	local inviter = fromUserId and Players:GetPlayerByUserId(fromUserId)
	local open = inviter and invites[player] and invites[player][inviter]
	if not open then
		return
	end
	invites[player][inviter] = nil
	if open < now() then
		toast(player, "That invite ran out. Ask " .. inviter.DisplayName .. " for a new one.")
		return
	end
	if accept then
		joinParty(player, inviter)
	else
		toast(inviter, player.DisplayName .. " said no thanks.")
	end
end

-- Someone just came into the server. If they came from a friend's Roblox invite, put them in that
-- friend's party. (The invite carries "party:<userId>"; Roblox doesn't always pass it along, so a
-- friend who opened the invite prompt in the last few minutes sends them a party invite instead.)
local function welcome(player)
	local fromId = nil
	for _ = 1, 5 do
		local ok, data = pcall(function()
			return player:GetJoinData()
		end)
		local launch = ok and type(data) == "table" and data.LaunchData
		if type(launch) == "string" and launch ~= "" then
			fromId = tonumber(string.match(launch, "^party:(%d+)$"))
			break
		end
		task.wait(1)
	end
	if not player.Parent then
		return
	end
	local inviter = fromId and Players:GetPlayerByUserId(fromId)
	if inviter and inviter ~= player then
		joinParty(player, inviter)
		return
	end
	for p, at in pairs(outsideInvites) do
		if p.Parent and p ~= player and now() - at < OUTSIDE_INVITE_SECONDS and not partyOf[player] then
			local ok, friends = pcall(function()
				return p:IsFriendsWith(player.UserId)
			end)
			if ok and friends then
				invite(p, player)
				return
			end
		end
	end
end

local function partyAction(player, what, options)
	local target = whole(options.userId)
	target = target and Players:GetPlayerByUserId(target)
	if what == "PartyInvite" then
		invite(player, target)
	elseif what == "PartyAnswer" then
		answerInvite(player, whole(options.fromUserId), options.accept == true)
	elseif what == "PartyLeave" then
		leaveParty(player)
	elseif what == "PartyKick" or what == "PartyLead" then
		local party = partyOf[player]
		if not party or party.leader ~= player or not target or target == player or partyOf[target] ~= party then
			return
		end
		if what == "PartyKick" then
			leaveParty(target)
			toast(target, player.DisplayName .. " removed you from the party.")
		else
			party.leader = target
			for _, p in ipairs(party.members) do
				toast(p, target.DisplayName .. " leads the party now.")
			end
			sendPartyToAll(party)
		end
	elseif what == "InvitedFriends" then
		outsideInvites[player] = now()
	elseif what == "RequestParty" then
		sendParty(player)
	end
end

local Cup = {}

local function startLobby(player)
	local id = lobbyOf[player]
	local lobby = id and lobbies[id]
	if not lobby or lobby.host ~= player or lobby.started then
		return
	end
	local rng = Rng.new(math.floor(now() * 1000) % 2147483647)
	-- Empty seats get bots.
	for i = 1, lobby.size do
		if not lobby.slots[i] then
			lobby.slots[i] = { kind = "bot", difficulty = "Medium", deck = randomDeck(rng) }
		end
	end
	for i = 1, lobby.size do
		local slot = lobby.slots[i]
		if slot.kind == "human" and (not slot.player.Parent or matches[slot.player]) then
			lobby.slots[i] = { kind = "bot", difficulty = "Medium", deck = randomDeck(rng) }
		end
	end
	lobby.started = true
	if lobby.mode == "Duel" or lobby.mode == "Team" then
		-- Seats: the engine takes seats 1, 3 as team 1 and 2, 4 as team 2. In the lobby, slots 1-2
		-- are team A and slots 3-4 are team B (Duel: slot 1 vs slot 2). A coin flip picks who goes first.
		local seats
		local flip = rng:int(1, 2) == 1
		local function copy(slot)
			return { kind = slot.kind, player = slot.player, deck = slot.deck, difficulty = slot.difficulty }
		end
		if lobby.mode == "Duel" then
			seats = flip and { copy(lobby.slots[1]), copy(lobby.slots[2]) } or { copy(lobby.slots[2]), copy(lobby.slots[1]) }
		else
			local a1, a2, b1, b2 = lobby.slots[1], lobby.slots[2], lobby.slots[3], lobby.slots[4]
			if flip then
				seats = { copy(a1), copy(b1), copy(a2), copy(b2) }
			else
				seats = { copy(b1), copy(a1), copy(b2), copy(a2) }
			end
		end
		local match = Match.new(seats, {
			mode = lobby.mode,
			label = MODES[lobby.mode].label,
			onFinished = function(finished)
				reopenLobby(lobby, finished)
			end,
		})
		broadcastLobbies()
		match:start()
	else
		Cup.start(lobby, rng)
	end
end

-- After a friends' match the table stays open with everyone still in their seats, so the host can
-- press Start again for a rematch. Whoever left during the match loses their seat.
reopenLobby = function(lobby, match)
	if lobbies[lobby.id] ~= lobby then
		return
	end
	local gone = {}
	for _, seat in ipairs(match.seats) do
		if seat.player and seat.left and not seat.released then
			gone[seat.player] = true
		end
	end
	for i = 1, lobby.size do
		local slot = lobby.slots[i]
		if slot and slot.kind == "human" and (gone[slot.player] or not slot.player.Parent or lobbyOf[slot.player] ~= lobby.id) then
			if lobbyOf[slot.player] == lobby.id then
				lobbyOf[slot.player] = nil
			end
			lobby.slots[i] = nil
		end
	end
	local host = nil
	for i = 1, lobby.size do
		local slot = lobby.slots[i]
		if slot and slot.kind == "human" and (host == nil or slot.player == lobby.host) then
			host = slot.player
		end
	end
	if not host then
		closeLobby(lobby, nil)
		return
	end
	lobby.host = host
	lobby.started = false
	broadcastLobbies()
	for i = 1, lobby.size do
		local slot = lobby.slots[i]
		if slot and slot.kind == "human" then
			LobbyEvent:FireClient(slot.player, { kind = "toast", text = "Same table, same seats. " .. (slot.player == host and "Press Start for a rematch!" or (host.DisplayName .. " can press Start for a rematch.")) })
		end
	end
end

local function setSlot(player, slotIndex, what, value)
	local id = lobbyOf[player]
	local lobby = id and lobbies[id]
	if not lobby or lobby.started or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > lobby.size then
		return
	end
	if lobby.host ~= player then
		return
	end
	local slot = lobby.slots[slotIndex]
	if what == "addBot" and not slot then
		lobby.slots[slotIndex] = { kind = "bot", difficulty = DIFFICULTIES[value] and value or "Medium", deck = StarterDecks.Order[(slotIndex % #StarterDecks.Order) + 1] }
	elseif what == "removeBot" and slot and slot.kind == "bot" then
		lobby.slots[slotIndex] = nil
	elseif what == "botDifficulty" and slot and slot.kind == "bot" and DIFFICULTIES[value] then
		slot.difficulty = value
	elseif what == "botDeck" and slot and slot.kind == "bot" and type(value) == "string" and StarterDecks[value] ~= nil then
		slot.deck = value
	elseif what == "kick" and slot and slot.kind == "human" and slot.player ~= player then
		lobby.slots[slotIndex] = nil
		lobbyOf[slot.player] = nil
		LobbyEvent:FireClient(slot.player, { kind = "toast", text = "The host removed you from the table." })
	end
	broadcastLobbies()
end

---------------------------------------------------------------------------
-- Tournaments: 8 players, knockout
---------------------------------------------------------------------------

-- The bracket: round 1 has 4 matches (1v2, 3v4, 5v6, 7v8 after a shuffle), the winners of
-- matches 1 and 2 meet in semi-final 1, and so on. cup.summary is what the screens show.
function Cup.summarize(cup)
	local rounds = {}
	for r, round in ipairs(cup.rounds) do
		rounds[r] = { name = ROUND_NAMES[r], matches = {} }
		for k, game in ipairs(round) do
			local function who(entrant)
				if not entrant then
					return nil
				end
				local e = cup.entrants[entrant]
				return { name = e.name, bot = e.kind == "bot", userId = e.userId, deck = e.deck, slot = entrant }
			end
			rounds[r].matches[k] = { a = who(game.a), b = who(game.b), winner = game.winner, status = game.status }
		end
	end
	cup.summary = { rounds = rounds, champion = cup.champion and cup.entrants[cup.champion].name or nil, championSlot = cup.champion }
end

function Cup.update(lobby)
	Cup.summarize(lobby.cup)
	broadcastLobbies()
	for _, e in ipairs(lobby.cup.entrants) do
		if e.kind == "human" and e.player.Parent then
			LobbyEvent:FireClient(e.player, { kind = "bracket", lobbyId = lobby.id, bracket = lobby.cup.summary })
		end
	end
end

function Cup.start(lobby, rng)
	local entrants = {}
	for i = 1, lobby.size do
		local slot = lobby.slots[i]
		entrants[i] = {
			kind = slot.kind,
			player = slot.player,
			userId = slot.kind == "human" and slot.player.UserId or nil,
			name = slot.kind == "human" and slot.player.DisplayName or ("Bot " .. i .. " (" .. slot.difficulty .. ")"),
			deck = slot.deck,
			difficulty = slot.difficulty,
			slot = i,
		}
	end
	local order = {}
	for i = 1, #entrants do
		order[i] = i
	end
	rng:shuffle(order)
	local cup = { entrants = entrants, rounds = {}, gone = {}, rng = rng }
	cup.rounds[1] = {}
	for k = 1, 4 do
		cup.rounds[1][k] = { a = order[2 * k - 1], b = order[2 * k], status = "waiting" }
	end
	cup.rounds[2] = { { status = "waiting" }, { status = "waiting" } }
	cup.rounds[3] = { { status = "waiting" } }
	lobby.cup = cup
	Cup.update(lobby)
	task.delay(CUP_ROUND_PAUSE, function()
		for k = 1, 4 do
			Cup.play(lobby, 1, k)
		end
	end)
end

-- Plays bracket match k of round r once both entrants are known.
function Cup.play(lobby, r, k)
	local cup = lobby.cup
	local game = cup.rounds[r][k]
	if game.status ~= "waiting" or not game.a or not game.b then
		return
	end
	game.status = "playing"
	Cup.update(lobby)
	local ea, eb = cup.entrants[game.a], cup.entrants[game.b]
	-- Someone who left the tournament loses their match.
	local goneA = cup.gone[game.a] or (ea.kind == "human" and not ea.player.Parent)
	local goneB = cup.gone[game.b] or (eb.kind == "human" and not eb.player.Parent)
	local function decide(winnerEntrant)
		game.winner = winnerEntrant
		game.status = "done"
		Cup.advance(lobby, r, k, winnerEntrant)
	end
	if goneA or goneB then
		task.delay(1, function()
			decide((goneA and not goneB) and game.b or game.a)
		end)
		return
	end
	local function seatFor(e)
		if e.kind == "human" and e.player.Parent and not matches[e.player] then
			return { kind = "human", player = e.player, deck = e.deck }
		end
		return { kind = "bot", difficulty = e.difficulty or "Medium", deck = e.deck, name = e.name }
	end
	local sa, sb = seatFor(ea), seatFor(eb)
	if sa.kind == "bot" and sb.kind == "bot" then
		task.delay(BOT_ONLY_MATCH_SECONDS, function()
			local w = playBotOnly({ sa, sb }, cup.rng:int(1, 1e6))
			decide(w == 1 and game.a or game.b)
		end)
		return
	end
	-- A coin flip for who goes first.
	local flip = cup.rng:int(1, 2) == 1
	local seats = flip and { sa, sb } or { sb, sa }
	local label = ROUND_NAMES[r] .. (r < 3 and (" · match " .. k) or "")
	local match = Match.new(seats, {
		mode = "Cup",
		label = label,
		onFinished = function(_, winnerTeam)
			local aIsTeam1 = flip
			local winner
			if winnerTeam == 0 or winnerTeam == nil then
				winner = cup.rng:int(1, 2) == 1 and game.a or game.b
			elseif (winnerTeam == 1) == aIsTeam1 then
				winner = game.a
			else
				winner = game.b
			end
			decide(winner)
		end,
	})
	match:start({ cupRound = ROUND_NAMES[r] })
end

function Cup.advance(lobby, r, k, winner)
	local cup = lobby.cup
	if r == 3 then
		cup.champion = winner
		Cup.update(lobby)
		local e = cup.entrants[winner]
		-- Prizes on top of the match wins, when at least two real players entered.
		local humans = 0
		for _, entrant in ipairs(cup.entrants) do
			if entrant.kind == "human" then
				humans += 1
			end
		end
		local prizes = humans >= 2
		if prizes and e.kind == "human" then
			addGems(e.player, PullRates.CupWinGems or 150)
		end
		-- Cup Champion (achievement) counts every Cup won, bots or not.
		if e.kind == "human" and e.player and e.player.Parent and PlayerData and PlayerData.noteCupWin then
			pcall(PlayerData.noteCupWin, e.player)
		end
		-- The runner-up gets something too.
		local final = cup.rounds[3][1]
		local second = final.a == winner and final.b or final.a
		local s = second and cup.entrants[second]
		if prizes and s and s.kind == "human" then
			addGems(s.player, PullRates.CupRunnerUpGems or 50)
		end
		LobbyEvent:FireAllClients({ kind = "toast", text = "🏆 " .. e.name .. " won the tournament!" })
		task.delay(30, function()
			closeLobby(lobby, nil)
		end)
		return
	end
	local nk = math.ceil(k / 2)
	local nextGame = cup.rounds[r + 1][nk]
	if k % 2 == 1 then
		nextGame.a = winner
	else
		nextGame.b = winner
	end
	Cup.update(lobby)
	if nextGame.a and nextGame.b then
		task.delay(CUP_ROUND_PAUSE + RESULT_SCREEN_SECONDS, function()
			Cup.play(lobby, r + 1, nk)
		end)
	end
end

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------

-- Copy only the fields the engine expects, so odd client data can't break anything.
local function cleanAction(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local function num(v)
		return type(v) == "number" and v == v and math.abs(v) < 1e6 and math.floor(v) or nil
	end
	local function target(t)
		if type(t) ~= "table" then
			return nil
		end
		local team, lane, row = num(t.team), num(t.lane), num(t.row)
		if not team or not lane then
			return nil
		end
		return { team = team, lane = lane, row = (row == 1 or row == 2) and row or nil }
	end
	local kind = raw.kind
	if kind == "play" then
		local row = num(raw.row)
		return { kind = "play", handUid = num(raw.handUid), lane = num(raw.lane), row = (row == 1 or row == 2) and row or nil, target = target(raw.target) }
	elseif kind == "spark" then
		return { kind = "spark", uid = num(raw.uid) }
	elseif kind == "shift" then
		return { kind = "shift", uid = num(raw.uid) }
	elseif kind == "bigmove" then
		return { kind = "bigmove", target = target(raw.target) }
	elseif kind == "battle" or kind == "endturn" then
		return { kind = "battle" }
	end
	return nil
end

MatchAction.OnServerEvent:Connect(function(player, raw)
	local match = matches[player]
	if not match then
		return
	end
	-- "I finished animating update number seq"
	if type(raw) == "table" and raw.kind == "ack" then
		match:onAck(player, raw.seq)
		return
	end
	if type(raw) == "table" and raw.kind == "speed" then
		match:setFast(player, raw.fast == true)
		return
	end
	local action = cleanAction(raw)
	if action then
		match:onAction(player, action)
	end
end)

-- A match against Bot Bonkers. The bot plays one of the other five themed decks.
startBotMatch = function(player, deck, difficulty)
	if matches[player] or not DIFFICULTIES[difficulty] then
		return
	end
	if not deckOk(deck, player) then
		local slot = savedSlot(deck)
		local why = slot and select(2, PlayerDecks.setupFor(player, slot)) or "Pick a deck first"
		LobbyEvent:FireClient(player, { kind = "toast", text = "That deck can't be played yet: " .. tostring(why) })
		return
	end
	leaveLobby(player)
	local rng = Rng.new(math.floor(now() * 1000) % 2147483647)
	-- The bot plays a practice deck of a theme your deck doesn't use.
	local mine = { [deck] = true }
	local slot = savedSlot(deck)
	if slot then
		local setup = PlayerDecks.setupFor(player, slot)
		for _, fam in ipairs(setup and setup.themes or {}) do
			mine[fam] = true
		end
	end
	local others = {}
	for _, key in ipairs(StarterDecks.Order) do
		if not mine[key] then
			table.insert(others, key)
		end
	end
	if #others == 0 then
		others = table.clone(StarterDecks.Order)
	end
	local human = { kind = "human", player = player, deck = deck }
	local bot = { kind = "bot", difficulty = difficulty, deck = rng:pick(others) }
	local seats = rng:int(1, 2) == 1 and { human, bot } or { bot, human }
	local match = Match.new(seats, { mode = "Bot", label = "vs Bot Bonkers (" .. difficulty .. ")", rematch = { deck = deck, difficulty = difficulty } })
	match:start()
end

-- A campaign stage (Campaign.luau): your own deck against the stage's opponent, inside the
-- stage's world. stageId is like "Candy:3:N" or "Challenge:<hour>".
startCampaignMatch = function(player, stageId, deck)
	if matches[player] then
		return
	end
	local function refuse(text)
		LobbyEvent:FireClient(player, { kind = "toast", text = text })
		LobbyEvent:FireClient(player, { kind = "campaignRefused", stage = stageId, text = text })
	end
	local stage = type(stageId) == "string" and Campaign.stage(stageId)
	if not stage then
		return refuse("That stage doesn't exist.")
	end
	if CampaignData then
		local ok, why = CampaignData.canPlay(player, stage.id)
		if not ok then
			return refuse(why or "That stage isn't open yet.")
		end
	end
	-- Campaign stages are played with your own decks (built at the Deck Shelf).
	local slot = savedSlot(deck)
	if not slot then
		return refuse("Pick one of your own decks for the Campaign.")
	end
	local setup, why = PlayerDecks.setupFor(player, slot)
	if not setup then
		return refuse("That deck can't be played yet: " .. tostring(why))
	end
	leaveLobby(player)
	local human = { kind = "human", player = player, deck = deck }
	local fam = stage.family
	if stage.rules and table.find(stage.rules, "homeTurf") then
		human.lanesOverride = { fam, fam, fam, fam }
	end
	local bot = {
		kind = "bot",
		difficulty = stage.difficulty,
		deck = fam,
		name = stage.name,
		bossCard = stage.bossCard,
		setup = { deck = stage.cards, hero = stage.hero, family = fam, lanes = { fam, fam, fam, fam } },
	}
	-- you go first in the first act of the tutorial world; otherwise a coin flip, like a bot match
	local rng = Rng.new(math.floor(now() * 1000) % 2147483647)
	local youFirst = stage.id == "Den:1:N" or rng:int(1, 2) == 1
	local seats = youFirst and { human, bot } or { bot, human }
	local match = Match.new(seats, {
		mode = "Campaign",
		label = stage.title,
		campaign = stage,
		campaignRetry = { stage = stage.id, deck = deck },
	})
	local ruleNames = {}
	for _, r in ipairs(stage.rules) do
		local def = Campaign.Rules[r]
		if def then
			table.insert(ruleNames, { name = def.name, text = def.text, emoji = def.emoji })
		end
	end
	lastDeck[player] = deck
	match:start({
		backdrop = stage.backdrop,
		campaign = {
			id = stage.id,
			title = stage.title,
			name = stage.name,
			boss = stage.boss,
			bossCard = stage.bossCard,
			rules = ruleNames,
			stars = Campaign.starTexts(stage),
			enemyHp = stage.enemyHp,
		},
	})
end

-- The stage after `id` (the next act, or act 1 of the next world after a boss), or nil.
local function nextStage(id)
	local world, act, hard = Campaign.parseId(id)
	if not world then
		return nil
	end
	if act < Campaign.Acts then
		return Campaign.stageId(world.key, act + 1, hard)
	end
	local nextWorld = Campaign.Worlds[world.index + 1]
	if nextWorld and not hard then
		return Campaign.stageId(nextWorld.key, 1, false)
	end
	return nil
end

---------------------------------------------------------------------------
-- Settings each player keeps between visits (deck, bot difficulty, background, action camera,
-- speed, whether they've seen the how-to-play screen). They're "Pref..." attributes on the
-- Player, and PlayerData saves them with the cards.
---------------------------------------------------------------------------

local PREF_KINDS = { Deck = "deck", Difficulty = "difficulty", Backdrop = "word", ActionCam = "bool", Fast = "bool", SeenHelp = "bool", Sound = "bool", SeenDaily = "bool" }

savePrefs = function(player, raw)
	local clean = {}
	for key, kind in pairs(PREF_KINDS) do
		local v = raw[key]
		if kind == "bool" and type(v) == "boolean" then
			clean[key] = v
		elseif kind == "deck" and deckOk(v, player) then
			clean[key] = v
		elseif kind == "difficulty" and DIFFICULTIES[v] then
			clean[key] = v
		elseif kind == "word" and type(v) == "string" and #v <= 16 and string.match(v, "^%a+$") then
			clean[key] = v
		end
	end
	for key, v in pairs(clean) do
		player:SetAttribute("Pref" .. key, v)
	end
	if PlayerData and PlayerData.setPrefs then
		PlayerData.setPrefs(player, clean)
	end
	if clean.Fast ~= nil and matches[player] then
		matches[player]:setFast(player, clean.Fast)
	end
end

MenuAction.OnServerEvent:Connect(function(player, what, options)
	options = type(options) == "table" and options or {}
	if deckOk(options.deck, player) then
		lastDeck[player] = options.deck
	end
	if type(what) == "string" and (string.sub(what, 1, 5) == "Party" or what == "InvitedFriends" or what == "RequestParty") then
		partyAction(player, what, options)
	elseif what == "StartBotMatch" then
		startBotMatch(player, options.deck, options.difficulty)
	elseif what == "Rematch" then
		-- "Play again" on the result screen of a bot match: same deck, same bot difficulty.
		local old = matches[player]
		if old and old.engine.over and old.opts.rematch then
			old:release(player)
			startBotMatch(player, old.opts.rematch.deck, old.opts.rematch.difficulty)
		end
	elseif what == "StartCampaign" then
		startCampaignMatch(player, options.stage, options.deck)
	elseif what == "CampaignRetry" or what == "CampaignNext" then
		-- "Try again" / "Next act" on a campaign result screen.
		local old = matches[player]
		local info = old and old.engine.over and old.opts.campaignRetry
		if info then
			local target = info.stage
			if what == "CampaignNext" then
				target = nextStage(info.stage)
			end
			old:release(player)
			if target then
				startCampaignMatch(player, target, info.deck)
			end
		end
	elseif what == "CampaignState" then
		local snap = CampaignData and CampaignData.snapshot(player)
		LobbyEvent:FireClient(player, { kind = "campaign", snapshot = snap })
	elseif what == "SavePrefs" then
		savePrefs(player, options)
	elseif what == "ClaimDaily" then
		-- The daily reward (the screen shows a pop-up when it's ready).
		if PlayerData and PlayerData.claimDaily then
			local gems, day, coins = PlayerData.claimDaily(player)
			LobbyEvent:FireClient(player, { kind = "claimed", what = "daily", ok = gems ~= nil, gems = gems, day = day, coins = coins })
		end
	elseif what == "ClaimQuest" then
		if PlayerData and PlayerData.claimQuest then
			local index = whole(options.index)
			local r = index and PlayerData.claimQuest(player, index)
			LobbyEvent:FireClient(player, { kind = "claimed", what = "quest", ok = r ~= nil, index = index, gems = r and r.gems, xp = r and r.xp, levelUps = r and r.levelUps })
		end
	elseif what == "LeaveMatch" then
		local match = matches[player]
		if match then
			match:onLeave(player)
		end
	elseif what == "CreateLobby" then
		createLobby(player, options.mode, options.deck)
	elseif what == "JoinLobby" then
		joinLobby(player, whole(options.id), options.deck, whole(options.slot))
	elseif what == "LeaveLobby" then
		leaveLobby(player)
	elseif what == "SetDeck" then
		local id = lobbyOf[player]
		if id then
			joinLobby(player, id, options.deck, nil)
		end
	elseif what == "SetSlot" then
		setSlot(player, whole(options.slot), options.what, options.value)
	elseif what == "StartLobby" then
		startLobby(player)
	elseif what == "RequestLobbies" then
		local list = {}
		for _, lobby in pairs(lobbies) do
			table.insert(list, lobbySummary(lobby))
		end
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
		LobbyEvent:FireClient(player, { kind = "lobbies", list = list })
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local match = matches[player]
	if match then
		match:onLeave(player)
	end
	leaveLobby(player)
	leaveParty(player)
	invites[player] = nil
	for _, open in pairs(invites) do
		open[player] = nil
	end
	lastDeck[player] = nil
	outsideInvites[player] = nil
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(welcome, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(welcome, player)
end

-- Deck Wars match server.
-- Runs every match with the MatchEngine, so players can't cheat from their own screen.
-- Matches against a bot on the 4-lane board (3 rows per side plus a building row). PvP comes later.
-- You play one of your own decks (built at the Deck Shelf from the cards you own) or borrow
-- one of the six practice decks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local MatchEngine = require(Shared:WaitForChild("MatchEngine"))
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local StarterDecks = require(Shared:WaitForChild("StarterDecks"))
local CardData = require(Shared:WaitForChild("CardData"))
local Rng = require(Shared:WaitForChild("Rng"))
local Settings = require(Shared:WaitForChild("Settings"))
local DeckRules = require(Shared:WaitForChild("DeckRules"))
local PlayerDecks = require(game:GetService("ServerScriptService"):WaitForChild("PlayerDecks"))
-- Coins and XP for finished matches (EconomyServer + ServerStorage.DeckWarsServer). Optional:
-- without it matches just don't pay.
local economyModule = game:GetService("ServerStorage"):FindFirstChild("EconomyManager", true)
local Economy = economyModule and require(economyModule) or nil

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent") -- server -> client: board updates
local MatchAction = Remotes:WaitForChild("MatchAction") -- client -> server: play, move, attack, big move, end turn
local MenuAction = Remotes:WaitForChild("MenuAction") -- client -> server: start / leave match

-- Pacing. Raise these numbers to make matches slower, lower them to speed up.
local TURN_SECONDS = 90 -- time you get for your turn (the clock pauses while animations play). 90 since every creature gets a command
local BOT_TURN_START_PAUSE = 1.5 -- the bot "looks at the board" before its first move
-- Pause before each bot action, by kind. Playing a card takes the longest.
local BOT_THINK_SECONDS = { play = 2.0, move = 1.2, attack = 1.4, defend = 1.0, chant = 1.6, bigmove = 2.0, endturn = 1.0 }
local BOT_MAX_ACTIONS = 60 -- safety: the bot ends its turn after this many actions
-- The server waits for your screen to finish animating before it moves on,
-- but never longer than this (in case a player's game is lagging or closed).
local ANIMATION_WAIT_BASE = 8
local ANIMATION_WAIT_PER_EVENT = 2.5
local ANIMATION_WAIT_MAX = 75
local DIFFICULTIES = { Easy = true, Medium = true, Hard = true }

local room = workspace:WaitForChild("MenuRoom")
local duelTable = room:WaitForChild("Stations"):WaitForChild("DuelTable")
local seatNear = duelTable:WaitForChild("Seat_Near")
local seatFar = duelTable:WaitForChild("Seat_Far")

local matches = {} -- [player] = match info

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Hide the cards the opponent draws.
local function filterEvents(events, viewer)
	local out = {}
	for _, e in ipairs(events) do
		if (e.type == "draw" or e.type == "burn") and e.player ~= viewer then
			table.insert(out, { type = e.type, player = e.player })
		else
			table.insert(out, e)
		end
	end
	return out
end

local function now()
	return workspace:GetServerTimeNow()
end

-- Sends the board to the player. Returns a number the player's screen sends back
-- once it has finished animating, so the server can wait for it.
local function sendUpdate(info, extra)
	local m = info.engine
	local view = m:viewFor(info.human)
	if m.current == info.human and not m.over then
		view.legal = m:listActions(info.human)
	else
		view.legal = {}
	end
	view.turnEndsAt = info.turnEndsAt
	view.botName = info.botName
	view.mode = "Bot"
	local events = filterEvents(m:takeEvents(), info.human)
	info.seq += 1
	local payload = { kind = "update", seq = info.seq, view = view, events = events }
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	-- The screen plays updates one after another, so each deadline starts after the previous one.
	local limit = math.min(ANIMATION_WAIT_MAX, ANIMATION_WAIT_BASE + ANIMATION_WAIT_PER_EVENT * #events)
	info.busyUntil = math.max(info.busyUntil, now()) + limit
	info.deadlines[info.seq] = info.busyUntil
	MatchEvent:FireClient(info.player, payload)
	return info.seq
end

-- Wait until the player's screen has shown update number `seq` (or its time limit passed).
local function waitForClient(info, seq)
	local deadline = info.deadlines[seq] or 0
	while not info.ended and info.ackSeq < seq and now() < deadline do
		task.wait(0.1)
	end
end

---------------------------------------------------------------------------
-- Your avatar and the chairs. Everything you see on the table (creatures, effects, the bot
-- across the table, the camera) is made and moved on your own screen by DeckWarsClient; the
-- server only runs the rules. The one physical thing is your avatar sitting in the near chair:
-- it never collides with the table or the chairs (its own collision group), the chairs only
-- take a seat when the server puts you there, and when you get up you are put back on your
-- spawn standing still, instead of jumping out of the chair into the furniture.
---------------------------------------------------------------------------
local AVATARS, FURNITURE = "DeckWarsAvatars", "DeckWarsFurniture"
pcall(function()
	PhysicsService:RegisterCollisionGroup(AVATARS)
	PhysicsService:RegisterCollisionGroup(FURNITURE)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(AVATARS, FURNITURE, false)
end)
for _, d in ipairs(duelTable:GetDescendants()) do
	if d:IsA("BasePart") and d.CanCollide then
		d.CollisionGroup = FURNITURE
	end
end
seatNear.Disabled = true -- no sitting down by walking into a chair; only seatPlayer seats you
seatFar.Disabled = true

local function avatarGroup(character)
	local function set(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = AVATARS
		end
	end
	for _, d in ipairs(character:GetDescendants()) do
		set(d)
	end
	character.DescendantAdded:Connect(set)
end
local function watchPlayer(player)
	player.CharacterAdded:Connect(avatarGroup)
	if player.Character then
		avatarGroup(player.Character)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

local function seatPlayer(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not seatNear.Occupant then
		seatNear.Disabled = false
		seatNear:Sit(humanoid)
	end
end

local function standPlayer(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart == seatNear then
		local weld = seatNear:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
		-- back to where you stood before the match, standing still
		local root = character:FindFirstChild("HumanoidRootPart")
		local spawn = room:FindFirstChild("SpawnLocation", true)
		if root and spawn then
			character:PivotTo(CFrame.new(spawn.Position + Vector3.new(0, 3, 0)) * spawn.CFrame.Rotation)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
	seatNear.Disabled = true
end

local function endMatch(info, reason)
	if matches[info.player] ~= info then
		return
	end
	matches[info.player] = nil
	info.ended = true
	standPlayer(info.player)
	if info.player.Parent then
		MatchEvent:FireClient(info.player, { kind = "ended", reason = reason })
	end
end

---------------------------------------------------------------------------
-- Turn flow
---------------------------------------------------------------------------

local runBotTurn -- forward declaration

-- Stop the player's turn clock (it starts again once their screen catches up).
local function pauseTurnClock(info)
	if info.turnEndsAt > 0 then
		info.turnRemaining = math.max(10, info.turnEndsAt - now())
	end
	info.turnToken += 1
	info.turnEndsAt = 0
end

local function finishIfOver(info)
	if info.engine.over then
		local w = info.engine.winner
		local result = (w == info.human and "win") or (w == 0 and "draw") or "loss"
		local seq = sendUpdate(info, { result = result })
		task.spawn(function()
			waitForClient(info, seq)
			-- pay out once the player has seen the last blow
			if Economy then
				local ok, reward = pcall(Economy.matchReward, info.player, {
					result = result,
					difficulty = info.difficulty,
					seconds = now() - (info.startedAt or now()),
					turns = math.floor((info.engine.turn or 0) / 2),
				})
				if ok and reward and Economy.announce then
					Economy.announce(info.player, "reward", reward)
				elseif not ok then
					warn("Deck Wars: match reward failed: " .. tostring(reward))
				end
			end
			task.wait(5)
			endMatch(info, "finished")
		end)
		return true
	end
	return false
end

local function autoEndTurn(info)
	info.engine:act(info.human, { kind = "endturn" })
	pauseTurnClock(info)
	local seq = sendUpdate(info, { notice = "Time's up! Your turn ended." })
	if not finishIfOver(info) and info.engine.current == info.bot then
		task.spawn(runBotTurn, info, seq)
	end
end

local function startTurnClock(info, seconds)
	info.turnToken += 1
	local token = info.turnToken
	info.turnEndsAt = now() + seconds
	MatchEvent:FireClient(info.player, { kind = "timer", turnEndsAt = info.turnEndsAt })
	task.delay(seconds, function()
		if not info.ended and info.turnToken == token and info.engine.current == info.human and not info.engine.over then
			autoEndTurn(info)
		end
	end)
end

-- Once the player's screen has shown update `seq`, (re)start their turn clock.
local function resumeTurnClockAfter(info, seq)
	local token = info.turnToken
	task.spawn(function()
		waitForClient(info, seq)
		if not info.ended and info.turnToken == token and info.engine.current == info.human and not info.engine.over then
			startTurnClock(info, info.turnRemaining)
		end
	end)
end

function runBotTurn(info, waitSeq)
	if info.botRunning then
		return
	end
	info.botRunning = true
	local m = info.engine
	-- Let the player watch what just happened, then the bot takes a moment.
	if waitSeq then
		waitForClient(info, waitSeq)
	end
	if not info.ended then
		task.wait(BOT_TURN_START_PAUSE)
	end
	local safety = 0
	while not info.ended and not m.over and m.current == info.bot do
		-- Decide first, then "think" for a moment that fits the kind of action.
		local action = BotBrain.chooseAction(m, info.bot, info.difficulty, info.botRng)
		task.wait(BOT_THINK_SECONDS[action.kind] or 1.5)
		if info.ended or m.over or m.current ~= info.bot then
			break
		end
		local ok = m:act(info.bot, action)
		if not ok then
			m:act(info.bot, { kind = "endturn" })
		end
		safety += 1
		if safety > BOT_MAX_ACTIONS and m.current == info.bot then
			m:act(info.bot, { kind = "endturn" })
		end
		local turnPassed = m.current == info.human
		if turnPassed then
			-- The player's clock starts after their screen finishes the bot's turn.
			info.turnToken += 1
			info.turnEndsAt = 0
			info.turnRemaining = TURN_SECONDS
		end
		local seq = sendUpdate(info)
		if finishIfOver(info) then
			break
		end
		if turnPassed then
			resumeTurnClockAfter(info, seq)
		else
			waitForClient(info, seq)
		end
	end
	info.botRunning = false
end

---------------------------------------------------------------------------
-- Starting a match
---------------------------------------------------------------------------

-- options.slot = one of your saved decks, or options.deck = a practice deck's key ("Snack"...).
local function startBotMatch(player, options)
	if matches[player] then
		return
	end
	local difficulty = options.difficulty
	if not DIFFICULTIES[difficulty] then
		return
	end
	local mySetup, myThemes
	if options.slot ~= nil then
		local setup, why = PlayerDecks.setupFor(player, options.slot)
		if not setup then
			MenuAction:FireClient(player, "MatchRefused", type(why) == "string" and why or "That deck can't be played yet")
			return
		end
		mySetup, myThemes = setup, setup.themes
	else
		local practice = StarterDecks[options.deck]
		if not practice then
			return
		end
		mySetup = DeckRules.setupFor(DeckRules.fromPractice(practice))
		myThemes = mySetup.themes
	end
	local seed = math.floor(now() * 1000) % 2147483647
	local rng = Rng.new(seed)
	-- The bot plays one of the practice decks, never one of your own themes.
	local others = {}
	for _, key in ipairs(StarterDecks.Order) do
		if not table.find(myThemes, key) then
			table.insert(others, key)
		end
	end
	local botDeck = StarterDecks[rng:pick(others)]
	local human = rng:int(1, 2) -- coin flip for who goes first
	local bot = 3 - human
	local setups = {}
	setups[human] = mySetup
	setups[bot] = DeckRules.setupFor(DeckRules.fromPractice(botDeck))

	local info = {
		player = player,
		engine = MatchEngine.new(setups[1], setups[2], seed),
		human = human,
		bot = bot,
		difficulty = difficulty,
		botRng = Rng.new(seed + 99),
		botName = "Bot Bonkers (" .. difficulty .. ", " .. botDeck.name .. ")",
		turnToken = 0,
		turnEndsAt = 0,
		turnRemaining = TURN_SECONDS,
		seq = 0,
		ackSeq = 0,
		busyUntil = 0,
		deadlines = {},
		ended = false,
		botRunning = false,
		startedAt = now(),
	}
	matches[player] = info
	seatPlayer(player)
	local seq = sendUpdate(info, { started = true, goesFirst = human == 1 })
	if info.engine.current == bot then
		task.spawn(runBotTurn, info, seq)
	else
		resumeTurnClockAfter(info, seq)
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
	local function tile(t)
		if type(t) ~= "table" then
			return nil
		end
		local col, row = num(t.col), num(t.row)
		if not col or not row then
			return nil
		end
		local out = { col = col, row = row }
		if type(t.terrain) == "string" and CardData.Terrains[t.terrain] then
			out.terrain = t.terrain
		end
		return out
	end
	local kind = raw.kind
	if kind == "play" then
		return { kind = "play", handUid = num(raw.handUid), tile = tile(raw.tile), target = tile(raw.target) }
	elseif kind == "move" then
		return { kind = "move", uid = num(raw.uid), to = tile(raw.to) }
	elseif kind == "attack" then
		return { kind = "attack", uid = num(raw.uid), target = tile(raw.target), hero = raw.hero == true or nil }
	elseif kind == "defend" then
		return { kind = "defend", uid = num(raw.uid) }
	elseif kind == "chant" then
		return { kind = "chant", uid = num(raw.uid), target = tile(raw.target) }
	elseif kind == "bigmove" then
		return { kind = "bigmove", col = num(raw.col) }
	elseif kind == "endturn" then
		return { kind = "endturn" }
	end
	return nil
end

MatchAction.OnServerEvent:Connect(function(player, raw)
	local info = matches[player]
	if not info then
		return
	end
	-- "I finished animating update number seq"
	if type(raw) == "table" and raw.kind == "ack" then
		local n = raw.seq
		if type(n) == "number" and n == n and n > info.ackSeq and n <= info.seq then
			info.ackSeq = math.floor(n)
			for k in pairs(info.deadlines) do
				if k <= info.ackSeq then
					info.deadlines[k] = nil
				end
			end
		end
		return
	end
	if info.engine.over then
		return
	end
	local action = cleanAction(raw)
	if not action then
		return
	end
	local ok, err = info.engine:act(info.human, action)
	if not ok then
		MatchEvent:FireClient(player, { kind = "error", message = err })
		return
	end
	-- Pause the clock while the player's own move animates.
	pauseTurnClock(info)
	local seq = sendUpdate(info)
	if finishIfOver(info) then
		return
	end
	if info.engine.current == info.bot then
		task.spawn(runBotTurn, info, seq)
	else
		resumeTurnClockAfter(info, seq)
	end
end)

---------------------------------------------------------------------------
-- Player settings: kept in a DataStore so they are the same next visit.
-- In Studio this only works with Game Settings > Security > "Enable Studio Access to API
-- Services" turned on; without it (or if Roblox's DataStores are down) settings just
-- last until the player leaves, and nothing breaks.
---------------------------------------------------------------------------
local SETTINGS_SAVE_GAP = 15 -- seconds between DataStore writes per player (Roblox limits writes)
local settingsStore = nil
pcall(function()
	settingsStore = game:GetService("DataStoreService"):GetDataStore("DeckWarsSettings_v1")
end)
local playerSettings = {} -- [player] = { values = {...}, dirty = bool, lastSave = time }

local function settingsKey(player)
	return "u" .. player.UserId
end

local function loadSettings(player)
	local entry = playerSettings[player]
	if entry then
		return entry
	end
	entry = { values = Settings.sanitize(nil), dirty = false, lastSave = 0, loaded = false }
	playerSettings[player] = entry
	if settingsStore then
		local ok, data = pcall(function()
			return settingsStore:GetAsync(settingsKey(player))
		end)
		if ok and type(data) == "table" and not entry.dirty then -- (a save that came in meanwhile wins)
			entry.values = Settings.sanitize(data)
		end
	end
	entry.loaded = true
	return entry
end

local function saveSettings(player, entry)
	if not settingsStore or not entry.dirty then
		return
	end
	entry.dirty = false
	entry.lastSave = os.clock()
	local values = entry.values
	local ok, err = pcall(function()
		settingsStore:SetAsync(settingsKey(player), values)
	end)
	if not ok then
		warn("Deck Wars: could not save settings for " .. player.Name .. ": " .. tostring(err))
	end
end

task.spawn(function()
	while true do
		task.wait(5)
		for player, entry in pairs(playerSettings) do
			if entry.dirty and os.clock() - entry.lastSave >= SETTINGS_SAVE_GAP then
				task.spawn(saveSettings, player, entry)
			end
		end
	end
end)

pcall(function()
	game:BindToClose(function()
		for player, entry in pairs(playerSettings) do
			saveSettings(player, entry)
		end
	end)
end)

-- Deck requests cost a profile read (and a save mark): a client may send at most 12 every 5 seconds.
local deckCalls = setmetatable({}, { __mode = "k" }) -- [player] = { t = window start, n = calls }
local function deckCallAllowed(player)
	local now = time()
	local c = deckCalls[player]
	if not c or now - c.t > 5 then
		c = { t = now, n = 0 }
		deckCalls[player] = c
	end
	c.n += 1
	return c.n <= 12
end

MenuAction.OnServerEvent:Connect(function(player, what, options)
	if (what == "GetDecks" or what == "SaveDeck" or what == "DeleteDeck") and not deckCallAllowed(player) then
		return
	end
	if what == "LoadSettings" then
		local entry = loadSettings(player)
		MenuAction:FireClient(player, "Settings", entry.values)
	elseif what == "SaveSettings" and type(options) == "table" then
		local entry = loadSettings(player)
		entry.values = Settings.sanitize(options)
		entry.dirty = true
	elseif what == "StartBotMatch" and type(options) == "table" then
		startBotMatch(player, { difficulty = options.difficulty, deck = type(options.deck) == "string" and options.deck or nil, slot = type(options.slot) == "number" and options.slot or nil })
	elseif what == "GetDecks" then
		local snap = PlayerDecks.snapshot(player)
		if snap then
			MenuAction:FireClient(player, "Decks", snap)
		end
	elseif what == "SaveDeck" and type(options) == "table" then
		local ok, problems = PlayerDecks.saveDeck(player, options.slot, options.deck)
		MenuAction:FireClient(player, "DeckSaved", { slot = options.slot, ok = ok, problems = problems })
		local snap = PlayerDecks.snapshot(player)
		if snap then
			MenuAction:FireClient(player, "Decks", snap)
		end
	elseif what == "DeleteDeck" and type(options) == "table" then
		PlayerDecks.deleteDeck(player, options.slot)
		local snap = PlayerDecks.snapshot(player)
		if snap then
			MenuAction:FireClient(player, "Decks", snap)
		end
	elseif what == "LeaveMatch" then
		local info = matches[player]
		if info then
			endMatch(info, "left")
		end
	end
end)

-- New players get the starter collection (4 starter characters and the Starter Deck).
local function welcome(player)
	task.spawn(function()
		pcall(PlayerDecks.ensureStarter, player)
	end)
end
Players.PlayerAdded:Connect(welcome)
for _, player in ipairs(Players:GetPlayers()) do
	welcome(player)
end

Players.PlayerRemoving:Connect(function(player)
	local info = matches[player]
	if info then
		endMatch(info, "left")
	end
	PlayerDecks.forget(player)
	local entry = playerSettings[player]
	if entry then
		playerSettings[player] = nil
		saveSettings(player, entry)
	end
end)

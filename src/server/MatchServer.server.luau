-- Deck Wars match server.
-- Runs every match with the MatchEngine, so players can't cheat from their own screen.
-- Matches against a bot on the 5 x 6 tile board. PvP comes in step 3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local MatchEngine = require(Shared:WaitForChild("MatchEngine"))
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local StarterDecks = require(Shared:WaitForChild("StarterDecks"))
local CardData = require(Shared:WaitForChild("CardData"))
local Rng = require(Shared:WaitForChild("Rng"))
local CreatureBuilder = require(Shared:WaitForChild("CreatureBuilder"))

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

-- Bot Bonkers, the robot opponent, sitting in the far chair.
local function buildBotAvatar(name)
	local model = CreatureBuilder.build("bot_bonkers") or Instance.new("Model")
	model.Name = "BotOpponent"
	-- The model is built sitting, with its feet at y = 0, facing -Z. The far chair faces the table.
	local seatPos = seatFar.Position
	model:PivotTo(CFrame.new(seatPos.X, 0, seatPos.Z) * seatFar.CFrame.Rotation)
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	if head then
		local tag = Instance.new("BillboardGui")
		tag.Name = "NameTag"
		tag.Size = UDim2.fromOffset(220, 40)
		tag.StudsOffset = Vector3.new(0, 3.4, 0)
		tag.AlwaysOnTop = true
		tag.LightInfluence = 0
		tag.Parent = head
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = name
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = tag
	end
	model.Parent = duelTable
	return model
end

local function seatPlayer(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not seatNear.Occupant then
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
	end
end

local function endMatch(info, reason)
	if matches[info.player] ~= info then
		return
	end
	matches[info.player] = nil
	info.ended = true
	if info.botAvatar then
		info.botAvatar:Destroy()
	end
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

local function startBotMatch(player, deckKey, difficulty)
	if matches[player] then
		return
	end
	local mine = StarterDecks[deckKey]
	if not mine or not DIFFICULTIES[difficulty] then
		return
	end
	local seed = math.floor(now() * 1000) % 2147483647
	local rng = Rng.new(seed)
	-- The bot plays one of the other five themed decks.
	local others = {}
	for _, key in ipairs(StarterDecks.Order) do
		if key ~= deckKey then
			table.insert(others, key)
		end
	end
	local botDeck = StarterDecks[rng:pick(others)]
	local human = rng:int(1, 2) -- coin flip for who goes first
	local bot = 3 - human
	local setups = {}
	setups[human] = { deck = mine.cards, hero = mine.hero, family = mine.family }
	setups[bot] = { deck = botDeck.cards, hero = botDeck.hero, family = botDeck.family }

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
	}
	matches[player] = info
	info.botAvatar = buildBotAvatar(info.botName)
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

MenuAction.OnServerEvent:Connect(function(player, what, options)
	if what == "StartBotMatch" and type(options) == "table" then
		startBotMatch(player, options.deck, options.difficulty)
	elseif what == "LeaveMatch" then
		local info = matches[player]
		if info then
			endMatch(info, "left")
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local info = matches[player]
	if info then
		endMatch(info, "left")
	end
end)

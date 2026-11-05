-- The Campaign station's panel: the world map (7 worlds x 6 acts, Normal and Hard), your stars
-- and star chests, the hourly Challenge, and a deck picker with a big Start button. Client only.
--
--   CampaignUI.init(ctx)     once, from DeckWarsClient. ctx = { myDecks = fn() -> list, loaded,
--                            prefs = { get, set }, toast = fn(text), panel = Frame (to resize) }
--   CampaignUI.show(body)    builds the panel into the station body and asks the server for the save
--   CampaignUI.hide()        the station closed
--
-- Every number comes from Campaign (shared), and every stage is checked again by the server
-- (MatchServer.startCampaignMatch), so this screen only shows what the server will do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local here = script.Parent
local Campaign = require(here:WaitForChild("Campaign"))
local CardData = require(here:WaitForChild("CardData"))
local Backdrops = require(here:WaitForChild("Backdrops"))
local Juice = require(here:WaitForChild("Juice"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MenuAction = Remotes:WaitForChild("MenuAction")
local LobbyEvent = Remotes:WaitForChild("LobbyEvent")

local rgb, make = Juice.rgb, Juice.make

local INK = rgb(18, 14, 28)
local TILE = rgb(42, 36, 62)
local TILE_HI = rgb(64, 54, 94)
local GOLD = rgb(255, 214, 102)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(160, 154, 182)
local LOCKED = rgb(30, 27, 42)
local GOOD = rgb(70, 190, 110)
local HARD = rgb(200, 70, 90)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium

local CampaignUI = {}

local S = {
	ctx = nil,
	body = nil, -- the station body we draw into (nil when closed)
	snap = nil, -- the server's snapshot (CampaignData.snapshotOf)
	world = nil, -- the selected world key
	hard = false,
	act = nil, -- the selected act (1..6)
	tab = "map", -- "map" or "challenge"
	deck = nil, -- your deck key ("s1"...)
	waiting = false, -- a Start was sent and the match hasn't begun
}

local function corner(parent, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return make("UIStroke", { Color = color or INK, Thickness = thickness or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function text(parent, str, props)
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = str,
		Font = BODY_FONT,
		TextSize = 14,
		TextColor3 = TEXT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 18),
	}, parent)
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	return t
end

local function button(parent, str, color, onClick, props)
	local b = make("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Text = str,
		Font = TITLE_FONT,
		TextSize = 16,
		TextColor3 = TEXT,
		Size = UDim2.fromOffset(100, 32),
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 8)
	stroke(b, INK, 2)
	Juice.button(b)
	b.Activated:Connect(onClick)
	return b
end

local function worldColors(w)
	local info = Backdrops.ByKey and Backdrops.ByKey[w.backdrop]
	if info and info.colors then
		return info.colors[1], info.colors[2]
	end
	return GOLD, TILE
end

local function save()
	return S.snap or { clears = {}, chests = {} }
end

local function starsOf(id)
	local c = save().clears[id]
	return c and c.stars or 0
end

local function starString(mask)
	local s = ""
	for i = 1, 3 do
		s ..= bit32.band(mask, bit32.lshift(1, i - 1)) ~= 0 and "★" or "☆"
	end
	return s
end

local function rarityColor(rarity)
	local c = CardData.RarityColors and CardData.RarityColors[rarity]
	if typeof(c) == "Color3" then
		return c
	elseif type(c) == "table" then
		return rgb(c[1], c[2], c[3])
	end
	return TEXT
end

-- The newest world you can play (where the map opens).
local function newestWorld()
	local key = Campaign.Worlds[1].key
	for _, w in ipairs(Campaign.Worlds) do
		if Campaign.worldUnlocked(save(), w.key) then
			key = w.key
		end
	end
	return key
end

-- The first act you haven't beaten in a world and mode (or the boss when all are beaten).
local function nextAct(worldKey, hard)
	for act = 1, Campaign.Acts do
		if not Campaign.cleared(save(), Campaign.stageId(worldKey, act, hard)) then
			return act
		end
	end
	return Campaign.Acts
end

local function myDeck()
	local list = S.ctx.myDecks and S.ctx.myDecks() or {}
	local found = nil
	for _, d in ipairs(list) do
		if d.key == S.deck then
			found = d
		end
	end
	if not found then
		-- the deck you picked last time (Duel Table or here), else your first good deck
		local pref = S.ctx.prefs and S.ctx.prefs.get("CampaignDeck")
		for _, d in ipairs(list) do
			if d.key == pref and d.ok ~= false then
				found = d
			end
		end
		if not found then
			for _, d in ipairs(list) do
				if d.ok ~= false then
					found = found or d
				end
			end
		end
		S.deck = found and found.key or nil
	end
	return found, list
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local render -- (forward)

local function clearBody()
	if not S.body then
		return
	end
	for _, c in ipairs(S.body:GetChildren()) do
		c:Destroy()
	end
end

-- A deck picker row and the Start button, at the bottom of both tabs.
local function startRow(scroll, order, stageId, canStart, why)
	local deck, list = myDeck()
	local row = make("Frame", { Name = "DeckRow", Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, scroll)
	local function cycle(dir)
		if #list == 0 then
			return
		end
		local index = 1
		for i, d in ipairs(list) do
			if d.key == S.deck then
				index = i
			end
		end
		index = (index - 1 + dir) % #list + 1
		S.deck = list[index].key
		if S.ctx.prefs then
			S.ctx.prefs.set("CampaignDeck", S.deck)
		end
		render()
	end
	button(row, "◀", TILE, function()
		cycle(-1)
	end, { Size = UDim2.fromOffset(34, 34) })
	local name = deck and (deck.name .. "  ·  " .. table.concat(deck.themes or { deck.family }, " + ")) or "No deck yet: build one at the Deck Shelf"
	local lbl = text(row, name, { Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -80, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, Font = TITLE_FONT, TextSize = 15, BackgroundColor3 = TILE, BackgroundTransparency = 0 })
	corner(lbl, 8)
	if deck and deck.ok == false then
		lbl.TextColor3 = HARD
		lbl.Text = deck.name .. " isn't ready: " .. tostring(deck.problem or "fix it at the Deck Shelf")
	end
	button(row, "▶", TILE, function()
		cycle(1)
	end, { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -34, 0, 0) })

	local ready = canStart and deck ~= nil and deck.ok ~= false and not S.waiting
	local start = button(scroll, S.waiting and "Starting..." or "⚔  START", ready and GOOD or LOCKED, function()
		if not ready then
			if S.ctx.toast then
				S.ctx.toast(why or (deck == nil and "Build a deck at the Deck Shelf first.") or "You can't start this one yet.")
			end
			return
		end
		S.waiting = true
		MenuAction:FireServer("StartCampaign", { stage = stageId, deck = S.deck })
		render()
		task.delay(6, function()
			if S.waiting then
				S.waiting = false
				render()
			end
		end)
	end, { Name = "StartButton", Size = UDim2.new(1, 0, 0, 48), TextSize = 24, LayoutOrder = order + 1 })
	if ready then
		Juice.shine(start, 3.2, UDim.new(0, 8))
	else
		start.TextColor3 = DIM
	end
end

local function drawChallenge(scroll)
	local snap = save()
	local hour = Campaign.challengeHour()
	local stage = Campaign.stage("Challenge:" .. hour)
	local box = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = TILE, LayoutOrder = 3 }, scroll)
	corner(box, 10)
	stroke(box, GOLD, 1.5, 0.4)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, box)
	text(box, "⏳ The hourly Challenge", { Font = TITLE_FONT, TextSize = 20, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 })
	if not stage then
		text(box, "No Challenge right now.", { LayoutOrder = 2 })
		return
	end
	local left = math.max(0, (hour + 1) * 3600 - os.time())
	local timer = text(box, "", { TextColor3 = DIM, LayoutOrder = 2 })
	local function tick()
		left = math.max(0, (hour + 1) * 3600 - os.time())
		timer.Text = string.format("A new one in %d:%02d", left // 60, left % 60)
	end
	tick()
	task.spawn(function()
		while timer.Parent do
			task.wait(1)
			if timer.Parent then
				tick()
				if left <= 0 then
					render()
				end
			end
		end
	end)
	text(box, stage.name .. ", " .. stage.title, { Font = TITLE_FONT, TextSize = 17, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 3 })
	text(box, "A " .. stage.difficulty .. " bot with a full " .. stage.family .. " deck, in " .. stage.worldName .. ".", { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
	for i, r in ipairs(stage.rules) do
		local def = Campaign.Rules[r]
		if def then
			text(box, def.emoji .. " " .. def.name .. ": " .. def.text, { AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = rgb(255, 190, 150), LayoutOrder = 4 + i })
		end
	end
	local reward = "Win to get 💎 " .. Campaign.Challenge.gems .. " and a random Rare, Epic or Mythic card (once an hour)."
	if snap.challengeWon and snap.challengeHour == hour then
		reward = "✓ You won this hour's Challenge. Come back for the next one!"
	end
	text(box, reward, { AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = snap.challengeWon and GOOD or GOLD, Font = TITLE_FONT, TextSize = 15, LayoutOrder = 20 })
	local open = snap.challengeOpen == true
	startRow(scroll, 10, stage.id, open, not open and "Beat the Card Den boss to open the Challenge." or nil)
end

local function drawMap(scroll)
	local snap = save()
	local worldsRow = make("Frame", { Name = "Worlds", Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, LayoutOrder = 3 }, scroll)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, worldsRow)
	for i, w in ipairs(Campaign.Worlds) do
		local open = Campaign.worldUnlocked(snap, w.key)
		local c1 = worldColors(w)
		local on = S.world == w.key
		local b = button(worldsRow, open and w.emoji or "🔒", on and c1:Lerp(INK, 0.35) or (open and TILE or LOCKED), function()
			if not open then
				if S.ctx.toast then
					S.ctx.toast("Beat " .. Campaign.Worlds[i - 1].boss.name .. " in " .. Campaign.Worlds[i - 1].name .. " to open " .. w.name .. ".")
				end
				return
			end
			S.world = w.key
			S.act = nextAct(w.key, S.hard and Campaign.hardUnlocked(snap, w.key))
			S.hard = S.hard and Campaign.hardUnlocked(snap, w.key)
			render()
		end, { Name = "World" .. w.key, Size = UDim2.fromOffset(52, 48), TextSize = 26, LayoutOrder = i })
		if on then
			b:FindFirstChildOfClass("UIStroke").Color = c1
		end
	end

	local world = Campaign.WorldByKey[S.world]
	local c1, c2 = worldColors(world)
	local header = make("Frame", { Name = "WorldHeader", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = c2:Lerp(INK, 0.6), LayoutOrder = 4 }, scroll)
	corner(header, 10)
	stroke(header, c1, 1.5, 0.3)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, header)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, header)
	text(header, world.emoji .. "  " .. world.name, { Font = TITLE_FONT, TextSize = 21, TextColor3 = c1:Lerp(TEXT, 0.35), Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 })
	text(header, world.blurb, { AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13, TextColor3 = DIM, LayoutOrder = 2 })
	-- world stars with the three chests on the bar
	local have = Campaign.worldStars(snap, world.key)
	local max = Campaign.Acts * 3 * 2
	local barHolder = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 }, header)
	local bar = make("Frame", { Size = UDim2.new(1, -60, 0, 10), Position = UDim2.fromOffset(0, 14), BackgroundColor3 = INK }, barHolder)
	corner(bar, 5)
	local fill = make("Frame", { Size = UDim2.fromScale(math.clamp(have / Campaign.Chests[#Campaign.Chests].stars, 0, 1), 1), BackgroundColor3 = GOLD }, bar)
	corner(fill, 5)
	text(barHolder, "★ " .. have .. "/" .. max, { Position = UDim2.new(1, -56, 0, 8), Size = UDim2.fromOffset(56, 20), TextXAlignment = Enum.TextXAlignment.Right, Font = TITLE_FONT, TextColor3 = GOLD })
	for n, def in ipairs(Campaign.Chests) do
		local taken = snap.chests and snap.chests[world.key .. ":" .. n]
		local x = def.stars / Campaign.Chests[#Campaign.Chests].stars
		local chest = Campaign.chest(world.key, n)
		local tip = def.stars .. "★: 💎 " .. chest.gems .. (chest.card and (" + " .. (CardData.Cards[chest.card] and CardData.Cards[chest.card].name or chest.card)) or "") .. (chest.title and (' + title "' .. chest.title .. '"') or "")
		local pip = button(barHolder, taken and "✓" or "🎁", taken and GOOD or TILE_HI, function()
			if S.ctx.toast then
				S.ctx.toast((taken and "Opened. " or "") .. tip)
			end
		end, { Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, -60 * x, 0, 1), TextSize = 14 })
		pip.ZIndex = 3
	end

	-- Normal / Hard
	local hardOpen = Campaign.hardUnlocked(snap, world.key)
	local modes = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 5 }, scroll)
	button(modes, "Normal", not S.hard and GOLD:Lerp(INK, 0.45) or TILE, function()
		S.hard = false
		S.act = nextAct(world.key, false)
		render()
	end, { Size = UDim2.new(0.5, -3, 1, 0) })
	local hb = button(modes, hardOpen and "🔥 Hard" or "🔒 Hard", S.hard and HARD or (hardOpen and TILE or LOCKED), function()
		if not hardOpen then
			if S.ctx.toast then
				S.ctx.toast("Beat " .. world.boss.name .. " on Normal to open Hard mode.")
			end
			return
		end
		S.hard = true
		S.act = nextAct(world.key, true)
		render()
	end, { Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0) })
	if not hardOpen then
		hb.TextColor3 = DIM
	end

	-- the six acts
	for act = 1, Campaign.Acts do
		local id = Campaign.stageId(world.key, act, S.hard)
		local stage = Campaign.stage(id)
		local ok = Campaign.canPlay(snap, id)
		local on = S.act == act
		local boss = act == Campaign.Acts
		local row = make("TextButton", {
			Name = "Act" .. act,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1, 0, 0, boss and 44 or 36),
			BackgroundColor3 = on and (S.hard and HARD:Lerp(INK, 0.45) or c1:Lerp(INK, 0.55)) or (ok and TILE or LOCKED),
			LayoutOrder = 10 + act,
		}, scroll)
		corner(row, 8)
		stroke(row, on and c1 or INK, on and 2 or 1.5)
		text(row, ok and tostring(act) or "🔒", { Size = UDim2.new(0, 28, 1, 0), Position = UDim2.fromOffset(6, 0), TextXAlignment = Enum.TextXAlignment.Center, Font = TITLE_FONT, TextSize = 18, TextColor3 = ok and GOLD or DIM })
		text(row, (boss and "👑 " or "") .. stage.name, { Size = UDim2.new(1, -170, 1, 0), Position = UDim2.fromOffset(38, 0), Font = TITLE_FONT, TextSize = boss and 17 or 15, TextColor3 = ok and TEXT or DIM, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
		text(row, stage.difficulty, { Size = UDim2.fromOffset(60, 36), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12, TextColor3 = stage.difficulty == "Hard" and rgb(255, 140, 140) or DIM })
		local stars = starsOf(id)
		text(row, starString(stars), { Size = UDim2.fromOffset(60, 36), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, Font = TITLE_FONT, TextSize = 18, TextColor3 = stars > 0 and GOLD or DIM })
		Juice.button(row, { grow = 1.02 })
		row.Activated:Connect(function()
			S.act = act
			render()
		end)
	end

	-- the selected act
	local id = Campaign.stageId(world.key, S.act or 1, S.hard)
	local stage = Campaign.stage(id)
	local ok, why = Campaign.canPlay(snap, id)
	local box = make("Frame", { Name = "Stage", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = TILE, LayoutOrder = 30 }, scroll)
	corner(box, 10)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, box)
	text(box, stage.name .. ", " .. stage.title, { Font = TITLE_FONT, TextSize = 17, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1 })
	local deckWord = stage.boss and "boss deck" or (stage.tier == "full" and "full deck" or (stage.tier == "basic" and "starter deck" or "deck"))
	text(box, "A " .. stage.difficulty .. " bot with a " .. stage.family .. " " .. deckWord .. ", " .. stage.enemyHp .. " hit points.", { AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13, TextColor3 = DIM, LayoutOrder = 2 })
	if stage.bossCard and CardData.Cards[stage.bossCard] then
		local card = CardData.Cards[stage.bossCard]
		text(box, "👑 Fights with " .. card.name .. " (" .. card.rarity .. ")", { TextSize = 13, TextColor3 = rarityColor(card.rarity), LayoutOrder = 3 })
	end
	for i, r in ipairs(stage.rules) do
		local def = Campaign.Rules[r]
		if def then
			text(box, def.emoji .. " " .. def.name .. ": " .. def.text, { AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13, TextColor3 = rgb(255, 190, 150), LayoutOrder = 3 + i })
		end
	end
	local stars = starsOf(id)
	for i, t in ipairs(Campaign.starTexts(stage)) do
		local got = bit32.band(stars, bit32.lshift(1, i - 1)) ~= 0
		text(box, (got and "★ " or "☆ ") .. t, { TextSize = 13, TextColor3 = got and GOLD or TEXT, LayoutOrder = 10 + i })
	end
	local cleared = Campaign.cleared(snap, id)
	local reward
	if not cleared then
		reward = "First clear: 💎 " .. stage.firstGems
		local card = stage.firstCard and CardData.Cards[stage.firstCard]
		if card then
			reward ..= " + " .. card.name .. " (" .. card.rarity .. ")"
		end
	else
		reward = "Cleared ✓  Replays can drop " .. stage.family .. " cards (" .. tostring(snap.dropsLeft or Campaign.DropsPerDay) .. " drops left today)."
		if stage.boss and not stage.hard and stage.bossCard then
			reward ..= " The boss may drop its Legendary."
		end
	end
	text(box, reward, { AutomaticSize = Enum.AutomaticSize.Y, Font = TITLE_FONT, TextSize = 14, TextColor3 = cleared and GOOD or GOLD, LayoutOrder = 20 })
	startRow(scroll, 40, id, ok, why)
end

function render()
	if not S.body or not S.body.Parent then
		return
	end
	local keepScroll = 0
	local old = S.body:FindFirstChild("CampaignScroll")
	if old then
		keepScroll = old.CanvasPosition.Y
	end
	clearBody()
	local snap = save()
	if not S.world or not Campaign.worldUnlocked(snap, S.world) then
		S.world = newestWorld()
		S.hard = false
		S.act = nextAct(S.world, false)
	end

	-- top: your stars and the two tabs
	local top = make("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, S.body)
	text(top, "★ " .. tostring(snap.totalStars or Campaign.totalStars(snap)) .. " / " .. Campaign.MaxStars, { Size = UDim2.new(0.4, 0, 1, 0), Font = TITLE_FONT, TextSize = 18, TextColor3 = GOLD })
	button(top, "🗺 Map", S.tab == "map" and GOLD:Lerp(INK, 0.45) or TILE, function()
		S.tab = "map"
		render()
	end, { Size = UDim2.new(0.28, -4, 1, 0), Position = UDim2.new(0.44, 0, 0, 0), TextSize = 15 })
	local chal = button(top, "⏳ Challenge", S.tab == "challenge" and GOLD:Lerp(INK, 0.45) or TILE, function()
		S.tab = "challenge"
		render()
	end, { Size = UDim2.new(0.28, 0, 1, 0), Position = UDim2.new(0.72, 0, 0, 0), TextSize = 14 })
	if snap.challengeOpen and not snap.challengeWon then
		local dot = make("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.new(1, -4, 0, -4), BackgroundColor3 = rgb(230, 70, 80), ZIndex = 4 }, chal)
		corner(dot, 5)
	end

	local scroll = make("ScrollingFrame", {
		Name = "CampaignScroll",
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = GOLD,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, S.body)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	make("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, scroll)
	if not S.snap then
		text(scroll, "Loading your Campaign...", { TextColor3 = DIM, LayoutOrder = 1 })
	end
	if S.tab == "challenge" then
		drawChallenge(scroll)
	else
		drawMap(scroll)
	end
	task.defer(function()
		if scroll.Parent then
			scroll.CanvasPosition = Vector2.new(0, keepScroll)
		end
	end)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

function CampaignUI.init(ctx)
	S.ctx = ctx or {}
	LobbyEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "campaign" then
			if type(payload.snapshot) == "table" then
				S.snap = payload.snapshot
			end
			render()
		elseif payload.kind == "campaignRefused" then
			S.waiting = false
			render()
		end
	end)
end

-- After a campaign match the result carries the new save, so the map is fresh straight away.
function CampaignUI.setSnapshot(snap)
	if type(snap) == "table" then
		S.snap = snap
	end
end

function CampaignUI.show(body)
	S.body = body
	S.waiting = false
	if S.ctx.panel then
		S.ctx.panel.Size = UDim2.fromOffset(430, 620)
	end
	render()
	MenuAction:FireServer("CampaignState", {})
end

function CampaignUI.hide()
	S.body = nil
	S.waiting = false
end

-- (for tests and the hub) the state of the screen
CampaignUI.S = S
CampaignUI.render = function()
	render()
end

return CampaignUI

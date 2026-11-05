-- Pack Party: pick a pack (on the 3D Pack Shelf or with the arrows), see what's inside and the
-- exact odds, and open 1 or 10 for Gems. The server rolls the pull and takes the Gems; this plays
-- the show: the 3D pack leaps off the shelf, the Pack Tease (tap it open), the Pack Brawl, then
-- the reveal (pack rip, card flip, stat card) and, for 10 packs, the card fan.
-- Used by the main game's Pack Party corner and by the test place's panel.
--
--   PackParty.mount(parent, {
--     onStart = function() end,      -- the cinematic is about to start (hide your UI)
--     onEnd = function(result) end,  -- the reveal closed, or the pull was refused (show your UI)
--     onStatus = function(text) end, -- short status lines (also shown in the panel)
--     isActive = function() return true end, -- is the panel on screen? (shelf hover, Q/E keys)
--     previews = true | false,       -- tier preview buttons (default: only in Studio)
--     noDive = true,                 -- skip the Dive into the room's Duel Table (the Plaza's altar)
--   })
--   PackParty.request(count, tier, packId, free) -- also used by the developer panel
--   PackParty.select(packId), PackParty.selected()
--   PackParty.clickAt(pos) / PackParty.hoverAt(pos) -- the room forwards clicks and the mouse
-- Mounting again (for example after the parent was cleared) replaces the old panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local Kit = require(here:WaitForChild("Kit"))
local Casting = require(here:WaitForChild("Casting"))
local Scripts = require(here:WaitForChild("Scripts"))
local Director = require(here:WaitForChild("Director"))
local Reveal = require(here:WaitForChild("Reveal"))
local PackTease = require(here:WaitForChild("PackTease"))
local PackShelf = require(here:WaitForChild("PackShelf"))
local Packs = require(here:WaitForChild("Packs"))
local PullRates = require(here:WaitForChild("PullRates"))
local BiomeFx = require(here:WaitForChild("BiomeFx"))
local BiomeStage = require(here:WaitForChild("BiomeStage"))
local CardData = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("CardData"))
local Juice = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("Juice"))
local Settings = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("Settings"))

local rgb, make = Kit.rgb, Kit.make
local INK = rgb(18, 14, 28)
local WHITE = rgb(255, 255, 255)
local GEM = "💎"

local PackParty = {}

-- The match world the player picked on the Duel Table panel (the Brawl Pack opens there).
local function tableWorld()
	local ok, choice = pcall(function()
		local m = ReplicatedStorage:FindFirstChild("DeckWars") and ReplicatedStorage.DeckWars:FindFirstChild("Backdrops")
		return m and require(m).choice
	end)
	return ok and choice or nil
end

-- The world a pack opens in, as the panel names it.
local function worldName(packId)
	local key = BiomeFx.PackWorld[packId]
	if key then
		return BiomeFx.recipe(key).name
	end
	local choice = tableWorld()
	if choice and BiomeFx.IsWorld[choice] then
		return BiomeFx.recipe(choice).name .. " (your table's world)"
	end
	return "a surprise world"
end

-- The Dive: the camera swings from the pack corner down into the Duel Table, and the board's
-- colour fills the screen just as the biome stage takes over (it starts hidden in fog).
local function dive(color, onDone)
	local camera = workspace.CurrentCamera
	local room = workspace:FindFirstChild("MenuRoom")
	local duel = room and room:FindFirstChild("DuelTable", true)
	local top = duel and duel:FindFirstChild("TableTop", true)
	if not (camera and top and top:IsA("BasePart")) or Settings.get("packFights") == "Quick" then
		onDone()
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", { Name = "PackDive", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 49 }, playerGui)
	local veil = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)
	local savedType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local from, fov0 = camera.CFrame, camera.FieldOfView
	local target = top.Position + Vector3.new(0, top.Size.Y / 2, 0)
	local mid = CFrame.lookAt(target + Vector3.new(0, 16, 15), target)
	local close = CFrame.lookAt(target + Vector3.new(0, 4, 3.5), target)
	local elapsed = 0
	local DUR = 1.0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local a = math.clamp(elapsed / DUR, 0, 1)
		local e = a * a * (3 - 2 * a)
		if e < 0.6 then
			camera.CFrame = from:Lerp(mid, e / 0.6)
		else
			camera.CFrame = mid:Lerp(close, (e - 0.6) / 0.4)
		end
		camera.FieldOfView = fov0 + (50 - fov0) * e
		veil.BackgroundTransparency = 1 - math.clamp((a - 0.72) / 0.28, 0, 1)
		if a >= 1 then
			conn:Disconnect()
			-- the veil covers the screen: put the camera back so the cinematic restores it there
			camera.CFrame = from
			camera.CameraType = savedType
			camera.FieldOfView = fov0
			onDone()
			-- the stage is up behind the veil: let it go
			local fade = 0
			local c2
			c2 = RunService.RenderStepped:Connect(function(dt2)
				fade += dt2
				local b = math.clamp(fade / 0.3, 0, 1)
				veil.BackgroundTransparency = b
				if b >= 1 then
					c2:Disconnect()
					gui:Destroy()
				end
			end)
		end
	end)
end

local state = {
	busy = false,
	playing = false,
	opts = nil,
	connected = false,
	selected = Packs.Default,
	ui = nil, -- the mounted panel's parts
	requestId = 0,
}
PackParty.state = state -- (for tests)

local function status(text)
	local o = state.opts
	if o and o.onStatus then
		o.onStatus(text)
	end
	local ui = state.ui
	if ui and ui.status.Parent then
		ui.status.Text = text
	end
end

local function active()
	local ui = state.ui
	if not (ui and ui.holder.Parent) then
		return false
	end
	local o = state.opts
	if o and o.isActive then
		return o.isActive() and true or false
	end
	return true
end

local function remotes()
	local r = ReplicatedStorage:WaitForChild("PullRemotes")
	return r:WaitForChild("PullRequest"), r:WaitForChild("PullResult")
end

local function gems()
	local v = Players.LocalPlayer:GetAttribute(Packs.Currency)
	return type(v) == "number" and v or nil
end

local function commas(n)
	local s = tostring(math.floor(n))
	while true do
		local k
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			return s
		end
	end
end

local function finish(result)
	state.playing = false
	state.busy = false
	PackShelf.restore()
	local o = state.opts
	if o and o.onEnd then
		o.onEnd(result)
	end
end

local REFUSED = {
	gems = function(r)
		return string.format("Not enough Gems: this costs %s %s and you have %s %s.", GEM, commas(r.price or 0), GEM, commas(r.balance or gems() or 0))
	end,
	cooldown = function()
		return "Too fast! Try again in a moment."
	end,
	busy = function()
		return "Still opening your last pack..."
	end,
	failed = function()
		return "Something went wrong, so your Gems were given back. Try again."
	end,
	pack = function()
		return "That pack isn't on the shelf any more."
	end,
}

local function onResult(result)
	state.requestId += 1
	if type(result) ~= "table" then
		return
	end
	if result.error then
		local why = REFUSED[result.error]
		status(why and why(result) or "The pack didn't open. Try again.")
		local ui = state.ui
		if ui and result.error == "gems" and ui.balance.Parent then
			Juice.shake(ui.balance, 6, 0.3)
			Juice.sound("thud", 0.7, 0.4)
		end
		finish(nil)
		return
	end
	local best = result.best
	local id = result.cards[best]
	local pack = Packs.get(result.packId)
	local cast = Casting.build(id, result.seed)
	local brawl = Scripts.build(cast)
	brawl.pack = pack
	-- biome pulls: the fight happens on the Duel Table inside the pack's world
	if BiomeStage.available() then
		brawl.world = BiomeFx.worldFor(pack.id, result.seed, tableWorld())
	end
	state.playing = true
	local o = state.opts
	if o and o.onStart then
		o.onStart()
	end
	status("")
	-- the 3D pack leaps off the shelf, then it is in your hands (tap it open), then it flies into the Brawl Box
	PackShelf.launch(pack.id)
	task.delay(PackShelf.has() and 0.3 or 0, function()
		PackTease.play({ tier = CardData.get(id).rarity, count = #result.cards, quick = Settings.get("packFights") == "Quick", pack = pack }, function()
			local function startBrawl(fn)
				if brawl.world and not (state.opts and state.opts.noDive) then
					dive(Kit.tierColor("Common", 0):Lerp(Packs.color(pack, "color"), 0.7), function()
						Director.play(brawl, fn)
					end)
				else
					Director.play(brawl, fn)
				end
			end
			startBrawl(function()
				local function back()
					local def = CardData.get(id)
					local owned = result.uniqueOwned and string.format(" You own %d different cards.", result.uniqueOwned) or ""
					status(string.format("Last pull: %s (%s).%s", def.name, def.rarity, owned))
					finish(result)
				end
				Reveal.single({
					id = id,
					isNew = result.isNew and result.isNew[best],
					dupes = result.dupes and result.dupes[best],
					pack = pack,
					count = #result.cards,
					onDone = function()
						if #result.cards > 1 then
							Reveal.fan({ cards = result.cards, best = best, isNew = result.isNew, onDone = back })
						else
							back()
						end
					end,
				})
			end)
		end)
	end)
end

function PackParty.isPlaying()
	return state.playing or state.busy
end

function PackParty.selected()
	return state.selected
end

-- Opens `count` packs. tier and free only work in Studio and for developers (the server checks).
function PackParty.request(count, tier, packId, free)
	if state.busy then
		return
	end
	packId = packId or state.selected
	if not Packs.valid(packId) then
		packId = Packs.Default
	end
	-- not enough Gems: say so here instead of asking the server (it would refuse anyway)
	local price = Packs.price(count)
	local have = gems()
	if tier == nil and free ~= true and price and have and have < price then
		onResult({ error = "gems", price = price, balance = have })
		return
	end
	local PullRequest = remotes()
	state.busy = true
	local o = state.opts
	if o and o.onRequest then
		o.onRequest()
	end
	status("Opening...")
	PullRequest:FireServer(count, tier, packId, free)
	-- the server always answers; if it never does (lost connection), unlock again
	state.requestId += 1
	local myRequest = state.requestId
	task.delay(15, function()
		if state.busy and not state.playing and state.requestId == myRequest then
			onResult({ error = "failed" })
		end
	end)
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function tierDot(parent, tier, size)
	local d = make("Frame", { Name = "Dot", Size = UDim2.fromOffset(size, size), BackgroundColor3 = Kit.TierColor[tier] or WHITE, BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
	if tier == "Secret" then
		make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 80, 80)), ColorSequenceKeypoint.new(0.5, rgb(80, 220, 255)), ColorSequenceKeypoint.new(1, rgb(220, 90, 255)) }) }, d)
	end
	return d
end

local function fillContents(ui, def)
	for _, c in ipairs(ui.contents:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local _, list = Packs.cardOdds(def.id)
	for i, e in ipairs(list) do
		local row = make("Frame", { Name = "Row_" .. e.id, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 20), BackgroundTransparency = 1 }, ui.contents)
		local dot = tierDot(row, e.tier, 10)
		dot.Position = UDim2.fromOffset(2, 5)
		local shared = def.family and e.family ~= def.family
		make("TextLabel", {
			Name = "CardName",
			Position = UDim2.fromOffset(18, 0),
			Size = UDim2.new(1, -78, 1, 0),
			BackgroundTransparency = 1,
			Text = e.name .. (shared and (e.family == "Any" and "  · shared" or ("  · " .. e.family)) or ""),
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = shared and rgb(175, 170, 195) or rgb(240, 236, 250),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
		make("TextLabel", {
			Name = "Chance",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(58, 20),
			BackgroundTransparency = 1,
			Text = Packs.percent(e.chance),
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Kit.TierColor[e.tier]:Lerp(WHITE, 0.3),
			TextXAlignment = Enum.TextXAlignment.Right,
		}, row)
	end
end

local function refreshPrices()
	local ui = state.ui
	if not (ui and ui.holder.Parent) then
		return
	end
	local have = gems()
	for count, b in pairs(ui.openButtons) do
		local price = Packs.price(count)
		local short = have ~= nil and have < price
		b.Text = string.format("Open %d  ·  %s %s", count, GEM, commas(price))
		b.BackgroundColor3 = short and rgb(90, 80, 110) or (count == 1 and rgb(255, 194, 26) or rgb(255, 150, 90))
		b.TextColor3 = short and rgb(200, 195, 215) or INK
	end
	ui.balance.Text = have and (GEM .. " " .. commas(have) .. " Gems") or (GEM .. " ...")
end

local function showPack(id, fromShelf)
	local ui = state.ui
	local def = Packs.get(id)
	if not def then
		return
	end
	local changed = state.selected ~= def.id
	state.selected = def.id
	PackShelf.select(def.id)
	if not (ui and ui.holder.Parent) then
		return
	end
	local main, accent = Packs.color(def, "color"), Packs.color(def, "accent")
	ui.name.Text = def.name
	ui.name.TextColor3 = main:Lerp(WHITE, 0.35)
	ui.nameStroke.Color = Packs.color(def, "dark")
	local where = (def.family and (def.family .. " family") or "All six families") .. " · opens in " .. worldName(def.id)
	ui.tagline.Text = where .. "\n" .. def.tagline
	ui.accent.BackgroundColor3 = main
	ui.accentGrad.Color = ColorSequence.new(main, accent)
	for pid, dot in pairs(ui.dots) do
		local d = Packs.get(pid)
		dot.Size = pid == def.id and UDim2.fromOffset(14, 14) or UDim2.fromOffset(9, 9)
		dot.BackgroundTransparency = pid == def.id and 0 or 0.35
		dot.BackgroundColor3 = Packs.color(d, "color")
	end
	ui.share.Text = def.family and string.format("3 in 4 cards are %s cards, 1 in 4 are shared spells and buildings. Rarities this family doesn't have come from every family.", def.family) or "Any card from any family."
	fillContents(ui, def)
	if changed then
		Juice.pop(ui.name, 1.15, 0.4)
		if not fromShelf then
			Juice.sound("pop", 1.1 + def.index * 0.04, 0.3)
		end
	end
end

function PackParty.select(id)
	showPack(id, false)
end

local function step(dir)
	local i = Packs.get(state.selected).index
	i = (i - 1 + dir) % #Packs.List + 1
	showPack(Packs.List[i].id, false)
end

-- The room forwards clicks (screen position) and the mouse (viewport position) here first.
-- Returns true when the click was on the shelf (so the room doesn't use it).
function PackParty.clickAt(pos)
	if not active() or state.busy then
		return false
	end
	local id = PackShelf.packAt(pos, true)
	if id then
		Juice.sound("pop", 1.2, 0.35)
		showPack(id, true)
		return true
	end
	return false
end

function PackParty.hoverAt(pos)
	if not active() then
		PackShelf.hover(nil)
		return false
	end
	local id = PackShelf.packAt(pos, false)
	PackShelf.hover(id)
	return id ~= nil
end

local function button(parent, name, text, pos, size, color, textColor)
	local b = make("TextButton", { Name = name, Position = pos, Size = size, BackgroundColor3 = color, Text = text, Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = textColor or rgb(30, 25, 40), AutoButtonColor = true }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
	return b
end

local keysConnected = false

-- Builds the panel inside `parent` (a Frame about 360 x 460 pixels or more; the card list
-- takes whatever height is left).
function PackParty.mount(parent, opts)
	state.opts = opts or {}
	if not state.connected then
		state.connected = true
		local _, PullResult = remotes()
		PullResult.OnClientEvent:Connect(onResult)
		Players.LocalPlayer:GetAttributeChangedSignal(Packs.Currency):Connect(function()
			refreshPrices()
			local ui = state.ui
			if ui and ui.balance.Parent then
				Juice.pop(ui.balance, 1.25, 0.4)
			end
		end)
		RunService.RenderStepped:Connect(function()
			PackShelf.setActive(active() and not state.playing)
		end)
	end
	if not keysConnected then
		keysConnected = true
		-- Q / E (or the gamepad's L2 / R2) pick the previous / next pack while the panel is open
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or state.busy or not active() or UserInputService:GetFocusedTextBox() then
				return
			end
			local k = input.KeyCode
			if k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonL2 then
				step(-1)
			elseif k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonR2 then
				step(1)
			end
		end)
	end
	PackShelf.attach()
	local previews = state.opts.previews
	if previews == nil then
		previews = RunService:IsStudio()
	end
	local holder = make("Frame", { Name = "PackPartyControls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, parent)
	local B = previews and 50 or 0 -- room for the preview buttons at the bottom
	local ui = { holder = holder, openButtons = {}, dots = {} }
	state.ui = ui

	-- header: ◀ pack name ▶, with a color bar in the pack's colors
	local prev = button(holder, "PrevPack", "◀", UDim2.fromOffset(0, 2), UDim2.fromOffset(34, 34), rgb(52, 44, 80), WHITE)
	local nextB = button(holder, "NextPack", "▶", UDim2.new(1, -34, 0, 2), UDim2.fromOffset(34, 34), rgb(52, 44, 80), WHITE)
	for _, b in ipairs({ prev, nextB }) do
		Juice.button(b)
	end
	prev.Activated:Connect(function()
		step(-1)
	end)
	nextB.Activated:Connect(function()
		step(1)
	end)
	ui.name = make("TextLabel", { Name = "PackName", Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -80, 0, 38), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = WHITE }, holder)
	make("UITextSizeConstraint", { MaxTextSize = 26 }, ui.name)
	ui.nameStroke = make("UIStroke", { Thickness = 2, Color = INK }, ui.name)
	ui.accent = make("Frame", { Name = "PackAccent", Position = UDim2.fromOffset(40, 40), Size = UDim2.new(1, -80, 0, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ui.accent)
	ui.accentGrad = make("UIGradient", {}, ui.accent)
	ui.tagline = make("TextLabel", { Name = "PackTagline", Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamMedium, TextSize = 14, TextWrapped = true, TextColor3 = rgb(215, 210, 230) }, holder)
	-- one dot per pack (click to pick)
	local dots = make("Frame", { Name = "PackDots", Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1 }, holder)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8) }, dots)
	for i, def in ipairs(Packs.List) do
		local d = make("TextButton", { Name = "Dot_" .. def.id, LayoutOrder = i, Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Packs.color(def, "color"), Text = "", AutoButtonColor = false }, dots)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
		make("UIStroke", { Thickness = 1, Color = WHITE, Transparency = 0.5 }, d)
		d.Activated:Connect(function()
			showPack(def.id, false)
		end)
		ui.dots[def.id] = d
	end
	-- what's inside, with each card's exact chance
	make("TextLabel", { Name = "InsideTitle", Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "WHAT'S INSIDE  ·  chance per card", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = rgb(255, 214, 102), TextXAlignment = Enum.TextXAlignment.Left }, holder)
	ui.contents = make("ScrollingFrame", { Name = "Contents", Position = UDim2.fromOffset(0, 124), Size = UDim2.new(1, 0, 1, -(124 + 168 + B)), BackgroundColor3 = rgb(12, 10, 22), BackgroundTransparency = 0.4, BorderSizePixel = 0, ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, holder)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, ui.contents)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, ui.contents)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, ui.contents)
	ui.share = make("TextLabel", { Name = "ShareNote", Position = UDim2.new(0, 0, 1, -(164 + B)), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamMedium, TextSize = 11, TextWrapped = true, TextColor3 = rgb(175, 170, 195), TextXAlignment = Enum.TextXAlignment.Left }, holder)
	local o = PullRates.Odds
	make("TextLabel", {
		Name = "Odds",
		Position = UDim2.new(0, 0, 1, -(134 + B)),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = string.format("Rarity odds: Common %g%% · Rare %g%% · Epic %g%% · Mythic %g%% · Legendary %g%% · Secret %g%%. 10 packs always hold an %s or better.", o.Common, o.Rare, o.Epic, o.Mythic, o.Legendary, o.Secret, PullRates.TenPullFloor),
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextWrapped = true,
		TextColor3 = rgb(175, 170, 195),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)
	-- buy buttons and your Gems
	local open1 = button(holder, "Open1", "", UDim2.new(0, 0, 1, -(100 + B)), UDim2.new(0.5, -5, 0, 42), rgb(255, 194, 26))
	local open10 = button(holder, "Open10", "", UDim2.new(0.5, 5, 1, -(100 + B)), UDim2.new(0.5, -5, 0, 42), rgb(255, 150, 90))
	ui.openButtons[1], ui.openButtons[10] = open1, open10
	for _, b in ipairs({ open1, open10 }) do
		b.TextSize = 17
		make("UIStroke", { Thickness = 2, Color = rgb(30, 25, 40), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		Juice.shine(b, 3, UDim.new(0, 10))
		Juice.button(b)
	end
	open1.Activated:Connect(function()
		PackParty.request(1)
	end)
	open10.Activated:Connect(function()
		PackParty.request(10)
	end)
	ui.balance = make("TextLabel", { Name = "GemBalance", Position = UDim2.new(0, 0, 1, -(54 + B)), Size = UDim2.new(0.5, 0, 0, 22), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = rgb(140, 220, 255), TextXAlignment = Enum.TextXAlignment.Left }, holder)
	make("TextLabel", { Name = "KeysHint", Position = UDim2.new(0.5, 0, 1, -(54 + B)), Size = UDim2.new(0.5, 0, 0, 22), BackgroundTransparency = 1, Text = "Q / E: other packs", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = rgb(150, 145, 170), TextXAlignment = Enum.TextXAlignment.Right }, holder)
	ui.status = make("TextLabel", { Name = "PackStatus", Position = UDim2.new(0, 0, 1, -(32 + B)), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "Click a pack on the shelf. Hold the screen to fast-forward a fight.", Font = Enum.Font.GothamMedium, TextSize = 12, TextWrapped = true, TextColor3 = rgb(200, 200, 220), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, holder)
	if previews then
		make("TextLabel", { Name = "PreviewTitle", Position = UDim2.new(0, 0, 1, -48), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "Studio only: preview a tier's cinematic (free)", Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = rgb(160, 155, 180), TextXAlignment = Enum.TextXAlignment.Left }, holder)
		local n = #PullRates.Tiers
		for k, tier in ipairs(PullRates.Tiers) do
			local light = tier == "Rare" or tier == "Epic" or tier == "Mythic"
			local b = button(holder, "Preview_" .. tier, tier, UDim2.new((k - 1) / n, 2, 1, -30), UDim2.new(1 / n, -4, 0, 30), Kit.TierColor[tier], light and WHITE or nil)
			b.TextSize = 12
			b.Activated:Connect(function()
				PackParty.request(1, tier)
			end)
		end
	end
	showPack(state.selected, true)
	refreshPrices()
	return holder
end

return PackParty

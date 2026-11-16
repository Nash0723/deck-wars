-- RoomTour: a short, friendly tour of your room the first time you play. Client only.
--
-- A card sits just above the dock and walks you round the room one station at a time: the
-- camera glides to each one and a gold ring pulses round its button in the dock. Next / Skip,
-- and at the end "Start the Campaign" or "Look around". Opening any station yourself ends the
-- tour (you've got the idea). The client remembers that you've seen it (the SeenTour pref).
--
--   RoomTour.start({
--       parent = menuFrame,                  -- the room's UI frame (the same ScreenGui as the dock)
--       focus = function(key) end,           -- glide the camera to a station ("Overview" for the room)
--       dockButton = function(key) end,      -- the station's button in the dock (or nil)
--       busy = function() return false end,  -- true once a station or window is open: the tour ends
--       onFinish = function(startCampaign) end,
--       sound = function(name, pitch, volume) end,
--   })

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local RoomTour = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium
local BOLD_FONT = Enum.Font.GothamBold
local GOLD = Color3.fromRGB(255, 214, 120)
local CREAM = Color3.fromRGB(247, 237, 222)
local INK = Color3.fromRGB(28, 19, 14)

RoomTour.Steps = {
	{
		key = "Overview",
		icon = "👋",
		title = "Welcome to your room!",
		text = "This cozy room is your home base in Deck Wars. Let's take a quick look around. It only takes a moment.",
	},
	{
		key = "DuelTable",
		icon = "⚔",
		title = "The Duel Table",
		text = "Card battles happen here. Pick a deck and press PLAY to take on a friend, or practise against a bot.",
	},
	{
		key = "Campaign",
		icon = "🗺",
		title = "The Campaign",
		text = "New here? Start with the Campaign: short story battles that teach you the game one step at a time, with rewards along the way.",
	},
	{
		key = "DeckShelf",
		icon = "📚",
		title = "The Deck Shelf",
		text = "Every card you collect lives here. Build your own decks and level up your favourite cards.",
	},
	{
		key = "PackParty",
		icon = "🎁",
		title = "Pack Party",
		text = "Spend 💎 Gems to open card packs. You earn Gems from daily rewards, quests, levelling up and your first win each day.",
	},
	{
		key = "TrophyWall",
		icon = "🏆",
		title = "Trophies",
		text = "Daily rewards, quests and achievements. When something's ready to collect, a red ! shows on its button.",
	},
	{
		key = "ParkDoor",
		icon = "🌳",
		title = "The Park",
		text = "Step out the front door into the Park: a glasshouse garden where you can meet other players and trade cards.",
	},
	{
		key = "Overview",
		icon = "✨",
		title = "You're all set!",
		text = "Tip: you can click anything in the room, too. Ready for your first battle?",
		final = true,
	},
}

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function tween(inst, time, goals, style)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goals)
	t:Play()
	return t
end

local active = nil

function RoomTour.running()
	return active ~= nil
end

function RoomTour.start(ctx)
	if active then
		return
	end
	local parent = ctx.parent
	local sound = ctx.sound or function() end
	local tour = { step = 0, done = false }
	active = tour

	local layer = make("Frame", { Name = "RoomTour", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20 }, parent)

	-- the gold ring that pulses round the station's dock button
	local ring = make("Frame", { Name = "Ring", BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, layer)
	local ringCorner = corner(ring, 30)
	local ringStroke = make("UIStroke", { Thickness = 4, Color = GOLD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)

	-- the card
	local card = make("Frame", {
		Name = "TourCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(36, 25, 18),
		BackgroundTransparency = 0.06,
		ZIndex = 22,
	}, layer)
	corner(card, 18)
	make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(214, 168, 98), Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 246, 232), Color3.fromRGB(190, 168, 150)) }, card)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, card)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	local cardScale = make("UIScale", { Scale = 1 }, card)

	-- top line: the step counter as dots, and the icon + title
	local top = make("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22 }, card)
	local icon = make("TextLabel", { Name = "Icon", Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(70, 50, 34), Text = "", TextSize = 20, Font = TITLE_FONT, TextColor3 = CREAM, ZIndex = 23 }, top)
	corner(icon, 17)
	make("UIStroke", { Thickness = 1.5, Color = GOLD, Transparency = 0.3 }, icon)
	local title = make("TextLabel", { Name = "Title", Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -120, 1, 0), BackgroundTransparency = 1, Text = "", Font = TITLE_FONT, TextSize = 24, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 }, top)
	make("UIStroke", { Thickness = 1.5, Color = INK, Transparency = 0.3 }, title)
	local dots = make("Frame", { Name = "Dots", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(70, 10), BackgroundTransparency = 1, ZIndex = 23 }, top)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4) }, dots)
	local dotList = {}
	for i = 1, #RoomTour.Steps do
		local d = make("Frame", { Name = "Dot" .. i, Size = UDim2.fromOffset(6, 6), BackgroundColor3 = CREAM, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 23 }, dots)
		corner(d, 3)
		dotList[i] = d
	end

	local body = make("TextLabel", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "", Font = BODY_FONT, TextSize = 16, TextWrapped = true, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, ZIndex = 23 }, card)

	local row = make("Frame", { Name = "Buttons", Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 3, ZIndex = 22 }, card)
	local function pill(name, text, gold, width)
		local b = make("TextButton", {
			Name = name,
			Size = UDim2.fromOffset(width, 38),
			BackgroundColor3 = gold and Color3.new(1, 1, 1) or Color3.fromRGB(70, 50, 36),
			BackgroundTransparency = gold and 0 or 0.2,
			AutoButtonColor = false,
			Text = text,
			Font = gold and TITLE_FONT or BOLD_FONT,
			TextSize = gold and 19 or 14,
			TextColor3 = gold and INK or CREAM,
			ZIndex = 24,
		}, row)
		corner(b, 19)
		if gold then
			make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 222, 120), Color3.fromRGB(242, 146, 52)) }, b)
			make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(110, 60, 20), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		end
		local s = make("UIScale", { Scale = 1 }, b)
		b.MouseEnter:Connect(function()
			tween(s, 0.15, { Scale = 1.06 }, Enum.EasingStyle.Back)
		end)
		b.MouseLeave:Connect(function()
			tween(s, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		return b
	end
	local skip = pill("Skip", "Skip tour", false, 100)
	skip.Position = UDim2.new(0, 0, 0.5, 0)
	skip.AnchorPoint = Vector2.new(0, 0.5)
	local nextB = pill("Next", "Next  →", true, 130)
	nextB.Position = UDim2.new(1, 0, 0.5, 0)
	nextB.AnchorPoint = Vector2.new(1, 0.5)

	local ringTarget = nil
	local function finish(startCampaign)
		if tour.done then
			return
		end
		tour.done = true
		active = nil
		if tour.conn then
			tour.conn:Disconnect()
		end
		ring.Visible = false
		tween(cardScale, 0.25, { Scale = 0.85 })
		tween(card, 0.25, { BackgroundTransparency = 1 })
		task.delay(0.25, function()
			layer:Destroy()
		end)
		if ctx.onFinish then
			task.spawn(ctx.onFinish, startCampaign == true)
		end
	end

	local function show(i)
		local st = RoomTour.Steps[i]
		if not st then
			finish(false)
			return
		end
		tour.step = i
		sound("whoosh", 1.1 + i * 0.03, 0.25)
		if ctx.focus then
			ctx.focus(st.key)
		end
		icon.Text = st.icon
		title.Text = st.title
		body.Text = st.text
		for k, d in ipairs(dotList) do
			d.BackgroundTransparency = (k == i) and 0 or (k < i and 0.4 or 0.75)
			d.BackgroundColor3 = (k == i) and GOLD or CREAM
			d.Size = (k == i) and UDim2.fromOffset(14, 6) or UDim2.fromOffset(6, 6)
		end
		if st.final then
			skip.Text = "Look around"
			skip.Size = UDim2.fromOffset(120, 38)
			nextB.Text = "Start the Campaign  ▶"
			nextB.Size = UDim2.fromOffset(210, 38)
		else
			skip.Text = "Skip tour"
			nextB.Text = (i == 1) and "Show me  →" or "Next  →"
		end
		ringTarget = (st.key ~= "Overview" and ctx.dockButton) and ctx.dockButton(st.key) or nil
		-- the card bounces in
		cardScale.Scale = 0.92
		tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	nextB.Activated:Connect(function()
		local st = RoomTour.Steps[tour.step]
		if st and st.final then
			sound("pop", 1.2, 0.4)
			finish(true)
		else
			sound("pop", 1 + tour.step * 0.04, 0.3)
			show(tour.step + 1)
		end
	end)
	skip.Activated:Connect(function()
		sound("pop", 0.9, 0.3)
		finish(false)
	end)

	local clock = 0
	tour.conn = RunService.RenderStepped:Connect(function(dt)
		clock += dt
		if ctx.busy and ctx.busy() then
			finish(false)
			return
		end
		if ringTarget and ringTarget.Parent and ringTarget.AbsoluteSize.X > 0 then
			local pad = 7 + math.sin(clock * 5) * 2
			local p = ringTarget.AbsolutePosition - layer.AbsolutePosition
			local s = ringTarget.AbsoluteSize
			ring.Position = UDim2.fromOffset(p.X - pad, p.Y - pad)
			ring.Size = UDim2.fromOffset(s.X + pad * 2, s.Y + pad * 2)
			ringCorner.CornerRadius = UDim.new(0, math.min(s.X, s.Y) / 2 + pad)
			ringStroke.Transparency = 0.05 + 0.3 * (0.5 + 0.5 * math.sin(clock * 5))
			ring.Visible = true
		else
			ring.Visible = false
		end
	end)

	show(1)
	return tour
end

return RoomTour

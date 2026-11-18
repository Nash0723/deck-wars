-- LandPicker: choose the biome under each of your four lanes before a match.
--
-- Each lane's land is one of the six biomes (one per card family). A creature standing on its
-- own family's land gets +1 attack, so picking your lands is a small piece of strategy. The
-- choice is saved as the "Lands" pref ("Snack,Critter,Snack,Critter"; "" = Auto: the lands your
-- deck brings) and the server lays those lands for you in your next match.
--
--   LandPicker.build(parent, {
--       order = 5,                         -- LayoutOrder in the parent's list
--       get = function() return "..." end, -- the saved pref ("" or nil = Auto)
--       set = function(str) end,           -- save a new pref
--       auto = { "Snack", ... },           -- the deck's own lands (shown while on Auto), optional
--       compact = false,                   -- smaller tiles (narrow panels)
--   })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end
local CardData = req("CardData")

local LandPicker = {}

LandPicker.Order = { "Snack", "Critter", "Weather", "Junk", "Spooky", "Robo" }
LandPicker.Emoji = { Snack = "🥤", Critter = "☁️", Weather = "❄️", Junk = "✨", Spooky = "🍄", Robo = "🌋" }
LandPicker.Lanes = 4

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

-- "Snack,Critter,Snack,Critter" -> { "Snack", "Critter", "Snack", "Critter" } (nil if not valid)
function LandPicker.parse(str)
	if type(str) ~= "string" or str == "" then
		return nil
	end
	local out = {}
	for word in string.gmatch(str, "[^,]+") do
		if not CardData.Terrains[word] then
			return nil
		end
		table.insert(out, word)
	end
	if #out ~= LandPicker.Lanes then
		return nil
	end
	return out
end

function LandPicker.join(list)
	return table.concat(list, ",")
end

function LandPicker.build(parent, opts)
	opts = opts or {}
	local compact = opts.compact
	local frame = make("Frame", {
		Name = "LandPicker",
		Size = UDim2.new(1, 0, 0, compact and 96 or 112),
		BackgroundColor3 = Color3.fromRGB(24, 19, 30),
		BackgroundTransparency = 0.1,
		LayoutOrder = opts.order or 0,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
	make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(214, 168, 98), Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, frame)

	local title = make("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -80, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 214, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "🌍 Your lands  ·  tap a lane to change it",
	}, frame)
	local auto = make("TextButton", {
		Name = "Auto",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -1),
		Size = UDim2.fromOffset(74, 20),
		BackgroundColor3 = Color3.fromRGB(70, 52, 38),
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(247, 237, 222),
		Text = "Auto",
	}, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, auto)

	local row = make("Frame", { Name = "Lanes", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1 }, frame)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local hint = make("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(190, 180, 170),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, frame)

	local current = LandPicker.parse(opts.get and opts.get()) -- nil = Auto
	local tiles = {}

	local function lands()
		if current then
			return current
		end
		local a = opts.auto
		local out = {}
		for i = 1, LandPicker.Lanes do
			out[i] = (type(a) == "table" and CardData.Terrains[a[i] or ""] and a[i]) or LandPicker.Order[1]
		end
		return out
	end

	local function paint()
		local list = lands()
		for i, t in ipairs(tiles) do
			local fam = list[i]
			local c = rgb(CardData.FamilyColors[fam] or { 200, 200, 200 })
			t.button.BackgroundColor3 = c:Lerp(Color3.fromRGB(30, 24, 30), 0.35)
			t.gradient.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.25), c:Lerp(Color3.fromRGB(20, 16, 20), 0.45))
			t.emoji.Text = LandPicker.Emoji[fam] or "?"
			t.name.Text = CardData.Terrains[fam] or fam
			t.button.BackgroundTransparency = current and 0 or 0.35
		end
		auto.BackgroundColor3 = current and Color3.fromRGB(70, 52, 38) or Color3.fromRGB(214, 168, 98)
		auto.TextColor3 = current and Color3.fromRGB(247, 237, 222) or Color3.fromRGB(28, 19, 14)
		hint.Text = current and "Your creatures get +1 ⚔ on their own family's land." or "Auto: the lands your deck brings. Tap a lane to pick your own."
	end

	for i = 1, LandPicker.Lanes do
		local b = make("TextButton", {
			Name = "Lane" .. i,
			Size = UDim2.new(0.25, -5, 1, 0),
			BackgroundColor3 = Color3.fromRGB(60, 50, 40),
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
		local gradient = make("UIGradient", { Rotation = 90 }, b)
		make("UIStroke", { Thickness = 1, Color = Color3.fromRGB(255, 240, 210), Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local emoji = make("TextLabel", { Name = "Emoji", Size = UDim2.new(1, 0, 0.58, 0), BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.GothamBold, Text = "" }, b)
		make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 2) }, emoji)
		local name = make("TextLabel", { Name = "LandName", Position = UDim2.fromScale(0, 0.58), Size = UDim2.new(1, 0, 0.42, 0), BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = Color3.new(1, 1, 1), Text = "" }, b)
		make("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingBottom = UDim.new(0, 4) }, name)
		make("UIStroke", { Thickness = 1.2, Color = Color3.fromRGB(20, 14, 10), Transparency = 0.2 }, name)
		local laneNo = make("TextLabel", { Name = "LaneNo", Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.fromRGB(255, 245, 225), Text = tostring(i) }, b)
		local scale = make("UIScale", { Scale = 1 }, b)
		tiles[i] = { button = b, gradient = gradient, emoji = emoji, name = name, laneNo = laneNo, scale = scale }
		b.MouseEnter:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end)
		b.Activated:Connect(function()
			local list = table.clone(lands())
			local at = table.find(LandPicker.Order, list[i]) or 0
			list[i] = LandPicker.Order[at % #LandPicker.Order + 1]
			current = list
			if opts.set then
				opts.set(LandPicker.join(list))
			end
			paint()
			scale.Scale = 0.85
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			if opts.sound then
				opts.sound()
			end
		end)
	end
	auto.Activated:Connect(function()
		current = nil
		if opts.set then
			opts.set("")
		end
		paint()
	end)
	paint()
	return frame
end

return LandPicker

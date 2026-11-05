-- UIKit: the shared look and behaviour of every Deck Wars menu. Client only.
--
-- Icons Roblox can't draw as text are drawn from frames here (the 🪙 coin and the ✕ close
-- mark show as empty boxes in Roblox's fonts), plus the round level badge and the Focus
-- manager, which keeps one thing on screen at a time:
--
--   UIKit.coinIcon(parent, 20)                      -- a gold coin, 20 px
--   UIKit.currency(parent, "Coins", "300", opts)    -- [coin] 300, as one row that sizes itself
--   UIKit.caption(button, "Coins", "120")           -- a button that shows [coin] 120 in the middle
--   UIKit.closeButton(parent, onClick, props)       -- a round button with a drawn ✕ (Name "Close")
--   UIKit.levelBadge(parent, 44, props)             -- the round level badge: badge.set(12)
--
-- Focus: when a window opens, everything that would crowd it slides out of the way, the room
-- behind dims and softly blurs, and the window springs in. When it closes, they come back.
--   UIKit.Focus.chrome("profile", UIKit.Focus.slide(profileCard, UDim2.fromOffset(-420, 0)))
--   UIKit.Focus.watch(shopWindow, { hide = { "title", "profile" }, dim = 0.4, blur = 10 })
--   UIKit.close(shopWindow)                         -- shrinks away, then hides
-- Watched windows are followed by their Visible property (and their ScreenGui), so the code
-- that opens and closes them doesn't need to know about Focus at all.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Juice = require(script.Parent:WaitForChild("Juice"))
local Settings = nil
pcall(function()
	Settings = require(script.Parent:WaitForChild("Settings"))
end)

local rgb, make = Juice.rgb, Juice.make

local UIKit = {}

UIKit.TITLE_FONT = Enum.Font.FredokaOne
UIKit.BODY_FONT = Enum.Font.GothamMedium
UIKit.BOLD_FONT = Enum.Font.GothamBold

UIKit.Color = {
	ink = rgb(18, 14, 28),
	panel = rgb(30, 25, 46),
	panelHi = rgb(40, 34, 60),
	tile = rgb(42, 36, 62),
	tileHi = rgb(56, 48, 82),
	line = rgb(70, 62, 98),
	gold = rgb(255, 220, 90),
	text = rgb(236, 232, 246),
	dim = rgb(176, 170, 196),
	good = rgb(70, 190, 110),
	bad = rgb(220, 80, 80),
	gem = rgb(110, 200, 255),
	coin = rgb(255, 200, 70),
	close = rgb(120, 58, 72),
}
local C = UIKit.Color

local function tween(inst, time, goals, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end
UIKit.tween = tween

local function round(obj, px)
	return make("UICorner", { CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0) }, obj)
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

-- A gold coin: a round face with a soft top light, a darker rim, an inner ring and a star.
function UIKit.coinIcon(parent, px, props)
	px = px or 20
	local c = make("Frame", {
		Name = "CoinIcon",
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, parent)
	round(c)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 236, 140), rgb(236, 152, 28)) }, c)
	make("UIStroke", { Thickness = math.max(1, math.floor(px * 0.09 + 0.5)), Color = rgb(150, 86, 12), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, c)
	local ring = make("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.66, 0.66),
		BackgroundTransparency = 1,
	}, c)
	round(ring)
	make("UIStroke", { Thickness = math.max(1, math.floor(px * 0.06 + 0.5)), Color = rgb(198, 120, 18), Transparency = 0.15 }, ring)
	make("TextLabel", {
		Name = "Star",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = "★",
		TextScaled = true,
		Font = UIKit.TITLE_FONT,
		TextColor3 = rgb(178, 104, 12),
	}, c)
	local shine = make("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.18, 0.12),
		Size = UDim2.fromScale(0.3, 0.16),
		Rotation = -32,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, c)
	round(shine)
	for k, v in pairs(props or {}) do
		c[k] = v
	end
	return c
end

-- The gem: Roblox draws 💎 well, so it stays an emoji (sized like the coin).
function UIKit.gemIcon(parent, px, props)
	px = px or 20
	local g = make("TextLabel", {
		Name = "GemIcon",
		Size = UDim2.fromOffset(px + 2, px + 2),
		BackgroundTransparency = 1,
		Text = "💎",
		TextScaled = true,
		Font = UIKit.TITLE_FONT,
	}, parent)
	for k, v in pairs(props or {}) do
		g[k] = v
	end
	return g
end

function UIKit.icon(parent, cur, px, props)
	if cur == "Gems" then
		return UIKit.gemIcon(parent, px, props)
	end
	return UIKit.coinIcon(parent, px, props)
end

-- [icon] value, as one row that grows to fit. opts: size (text size, default 18), color, font,
-- height, gap, iconSize. Returns the row and its TextLabel ("Value").
function UIKit.currency(parent, cur, value, opts)
	opts = opts or {}
	local size = opts.size or 18
	local row = make("Frame", {
		Name = opts.name or cur,
		Size = UDim2.fromOffset(0, opts.height or (size + 8)),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = opts.align or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, opts.gap or math.floor(size * 0.3)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local icon = UIKit.icon(row, cur, opts.iconSize or math.floor(size * 1.05 + 0.5))
	icon.LayoutOrder = 1
	local l = make("TextLabel", {
		Name = "Value",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = tostring(value),
		Font = opts.font or UIKit.TITLE_FONT,
		TextSize = size,
		TextColor3 = opts.color or (cur == "Gems" and C.gem or C.coin),
		LayoutOrder = 2,
	}, row)
	if opts.stroke then
		make("UIStroke", { Thickness = 1.5, Color = C.ink, Transparency = 0.3 }, l)
	end
	return row, l
end

-- A button (or label) that shows an icon and a caption together, centered: the caption moves
-- into a child TextLabel. cur is "Coins", "Gems" or nil (just the text). The full caption is kept
-- in the "Caption" attribute (with "Coins " / "Gems " in front) so scripts can read it.
function UIKit.caption(obj, cur, text)
	local holder = obj:FindFirstChild("Caption")
	if not holder then
		holder = make("Frame", { Name = "Caption", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = obj.ZIndex }, obj)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, holder)
		make("TextLabel", {
			Name = "Text",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			ZIndex = obj.ZIndex,
		}, holder)
	end
	local t = holder.Text
	t.Font = obj.Font
	t.TextSize = obj.TextSize
	t.TextColor3 = obj.TextColor3
	t.TextStrokeTransparency = obj.TextStrokeTransparency
	t.TextStrokeColor3 = obj.TextStrokeColor3
	t.Text = text
	local icon = holder:FindFirstChild("CoinIcon") or holder:FindFirstChild("GemIcon")
	local want = cur == "Gems" and "GemIcon" or (cur == "Coins" and "CoinIcon" or nil)
	if icon and icon.Name ~= want then
		icon:Destroy()
		icon = nil
	end
	if want and not icon then
		icon = UIKit.icon(holder, cur, math.floor(obj.TextSize * 1.1 + 0.5), { ZIndex = obj.ZIndex, LayoutOrder = 1 })
	end
	obj.Text = ""
	obj:SetAttribute("Caption", (cur and (cur .. " ") or "") .. text)
	return holder
end

-- A round close button with a drawn ✕ (Roblox's fonts have no ✕).
function UIKit.closeButton(parent, onClick, props)
	local size = props and props.Size or UDim2.fromOffset(40, 40)
	local b = make("TextButton", {
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.close,
		Size = size,
	}, parent)
	round(b, 12)
	make("UIStroke", { Thickness = 2.5, Color = C.ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(196, 186, 206)) }, b)
	for _, rot in ipairs({ 45, -45 }) do
		local bar = make("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.52, 0, 0, 4),
			Rotation = rot,
			BackgroundColor3 = rgb(255, 240, 240),
			BorderSizePixel = 0,
		}, b)
		round(bar, 2)
	end
	b:SetAttribute("Caption", "Close")
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Juice.button(b, { grow = 1.08 })
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- The round level badge: a violet disc with a gold rim and the level centered in it.
-- Returns the badge (a Frame) with a .Value TextLabel; badge:SetAttribute is not needed:
-- call UIKit.setLevel(badge, n).
function UIKit.levelBadge(parent, px, props)
	px = px or 44
	local f = make("Frame", { Name = "Level", Size = UDim2.fromOffset(px, px), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, parent)
	round(f)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(132, 108, 226), rgb(66, 48, 138)) }, f)
	make("UIStroke", { Thickness = 2.5, Color = rgb(255, 208, 102), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local inner = make("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1 }, f)
	round(inner)
	make("UIStroke", { Thickness = 1, Color = Color3.new(1, 1, 1), Transparency = 0.75 }, inner)
	-- The number fills the whole disc and is centered both ways (no padding, no offsets), so it
	-- sits in the middle whatever the digits are.
	make("TextLabel", {
		Name = "Value",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "1",
		Font = UIKit.TITLE_FONT,
		TextSize = math.floor(px * 0.46 + 0.5),
		TextColor3 = rgb(255, 234, 150),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, f)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	return f
end

function UIKit.setLevel(badge, level)
	local v = badge:FindFirstChild("Value")
	if v then
		local s = tostring(level)
		v.Text = s
		-- three digits get a little smaller so they stay inside the disc
		v.TextSize = math.floor(badge.Size.Y.Offset * (#s >= 3 and 0.36 or 0.46) + 0.5)
	end
end

-- A faint light rim just inside a panel's outline, so it reads as one clean, finished piece.
-- (Only for panels without a layout of their own: the rim is a child frame.)
function UIKit.rim(panel, radius)
	if panel:FindFirstChild("Rim") then
		return panel.Rim
	end
	local rim = make("Frame", { Name = "Rim", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, rim)
	make("UIStroke", { Thickness = 1, Color = Color3.new(1, 1, 1), Transparency = 0.86 }, rim)
	return rim
end

---------------------------------------------------------------------------
-- Window motion
---------------------------------------------------------------------------

local function kitScale(obj)
	local s = obj:FindFirstChild("KitScale")
	if not s then
		s = make("UIScale", { Name = "KitScale", Scale = 1 }, obj)
	end
	return s
end

-- Springs a window in: from a little smaller to its size, quick and soft.
function UIKit.animateIn(win, opts)
	opts = opts or {}
	local s = kitScale(win)
	s.Scale = opts.from or 0.92
	tween(s, opts.time or 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Shrinks a window a little, then hides it (and calls after). Opening it again right away
-- (UIKit.keepOpen, or just setting Visible = true again) cancels the hide.
local closing = setmetatable({}, { __mode = "k" }) -- [window] = token while it's closing
function UIKit.close(win, after)
	if not win or not win.Visible or closing[win] then
		if after then
			after()
		end
		return
	end
	local token = {}
	closing[win] = token
	local s = kitScale(win)
	tween(s, 0.12, { Scale = 0.94 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.12, function()
		if closing[win] ~= token then
			return -- opened again meanwhile
		end
		closing[win] = nil
		win.Visible = false
		s.Scale = 1
		if after then
			after()
		end
	end)
end

-- Stop a window that's closing from hiding (it's being opened again).
function UIKit.keepOpen(win)
	if win and closing[win] then
		closing[win] = nil
		tween(kitScale(win), 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

---------------------------------------------------------------------------
-- Focus
---------------------------------------------------------------------------
local Focus = {
	chromeItems = {}, -- [name] = { hide = fn, show = fn, allowed = fn? }
	hidden = {}, -- [name] = true while hidden
	windows = {}, -- [GuiObject] = rules
	shownWas = {}, -- [GuiObject] = was shown last update
	dim = nil,
	blur = nil,
	dimNow = 0,
	blurNow = 0,
}
UIKit.Focus = Focus

local SLIDE_TIME = 0.34

-- A chrome item that slides `obj` by `offset` (a UDim2) when hidden and back home when shown.
-- With keepVisible, the object stays Visible (only moved), for things other scripts check.
function Focus.slide(obj, offset, keepVisible)
	local home = nil
	local token = 0
	local item = {}
	function item.hide()
		home = home or obj.Position
		token += 1
		local my = token
		tween(obj, SLIDE_TIME, { Position = home + offset }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		if not keepVisible then
			task.delay(SLIDE_TIME, function()
				if token == my then
					obj.Visible = false
				end
			end)
		end
	end
	function item.show()
		token += 1
		obj.Visible = true
		if home then
			tween(obj, SLIDE_TIME, { Position = home }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end
	-- (if something else moves the object for good, call item.rehome())
	function item.rehome()
		home = obj.Position
	end
	return item
end

-- Same, but by AnchorPoint (the object can still be placed and animated by Position elsewhere).
-- delta is how many of its own sizes it moves (Vector2), e.g. (1.1, 0) slides it right off.
function Focus.anchorSlide(obj, delta)
	local home = nil
	local item = {}
	function item.hide()
		home = home or obj.AnchorPoint
		tween(obj, SLIDE_TIME, { AnchorPoint = home - delta }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	function item.show()
		if home then
			tween(obj, SLIDE_TIME, { AnchorPoint = home }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end
	return item
end

-- Register something that gets out of the way. item = { hide = fn, show = fn, allowed = fn? }
-- (allowed() false means "don't bring it back now", e.g. the room's signs during a match).
function Focus.chrome(name, item)
	Focus.chromeItems[name] = item
	if Focus.hidden[name] then
		item.hide()
	end
	Focus.update()
end

-- Is the GuiObject really on screen (it and its parents Visible, its ScreenGui Enabled)?
local function shown(obj)
	local node = obj
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		elseif node:IsA("PlayerGui") or node == game then
			return false
		end
		node = node.Parent
	end
	return false
end
Focus.shown = shown

local function lowGraphics()
	return Settings ~= nil and Settings.get("graphics") == "Low"
end

function Focus.setup()
	if Focus.dim then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = make("ScreenGui", { Name = "DeckWarsFocus", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	Focus.dim = make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(10, 8, 18), BackgroundTransparency = 1, BorderSizePixel = 0 }, g)
	-- a soft vignette on top of the dim: darker at the edges, so the eye goes to the window
	Focus.vignette = make("ImageLabel", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/VignetteOverlay.png",
		ImageTransparency = 1,
	}, g)
	Focus.blur = make("BlurEffect", { Name = "FocusBlur", Size = 0 }, Lighting)
	-- Watched windows are checked a few times a second too (some open by their ScreenGui).
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			Focus.update()
		end
	end)
end

-- Follow a window. rules: hide = { chrome names }, dim = 0..1 (how dark the room gets),
-- blur = BlurEffect size, animate = false to skip the spring-in.
function Focus.watch(win, rules)
	rules = rules or {}
	Focus.setup()
	Focus.windows[win] = rules
	Focus.shownWas[win] = shown(win)
	win:GetPropertyChangedSignal("Visible"):Connect(function()
		Focus.update()
	end)
	Focus.update()
	return win
end

function Focus.update()
	local want, dim, blur = {}, 0, 0
	for win, rules in pairs(Focus.windows) do
		if win.Parent == nil then
			-- (destroyed windows drop out; the frame loop calls update a few times a second)
			Focus.windows[win] = nil
			Focus.shownWas[win] = nil
			continue
		end
		local on = shown(win)
		if on and not Focus.shownWas[win] and rules.animate ~= false then
			UIKit.animateIn(win, rules)
		end
		Focus.shownWas[win] = on
		if on then
			for _, n in ipairs(rules.hide or {}) do
				want[n] = true
			end
			dim = math.max(dim, rules.dim or 0)
			blur = math.max(blur, rules.blur or 0)
		end
	end
	for name, item in pairs(Focus.chromeItems) do
		local h = want[name] == true
		if h ~= (Focus.hidden[name] == true) then
			if h then
				Focus.hidden[name] = true
				item.hide()
			elseif not item.allowed or item.allowed() then
				Focus.hidden[name] = nil
				item.show()
			end
		end
	end
	if lowGraphics() then
		blur = 0
	end
	if Focus.dim and dim ~= Focus.dimNow then
		Focus.dimNow = dim
		tween(Focus.dim, 0.3, { BackgroundTransparency = 1 - dim })
		tween(Focus.vignette, 0.3, { ImageTransparency = dim > 0 and 0.25 or 1 })
	end
	if Focus.blur and blur ~= Focus.blurNow then
		Focus.blurNow = blur
		tween(Focus.blur, 0.35, { Size = blur })
	end
end

-- Is any watched window with this chrome name in its hide list open right now?
function Focus.isHidden(name)
	return Focus.hidden[name] == true
end

return UIKit

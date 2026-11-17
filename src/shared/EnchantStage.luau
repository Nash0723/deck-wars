-- EnchantStage: the enchant itself, in front of everything. Client only. EnchantUI opens it when
-- you press Enchant or Lucky at the Enchanting Crystal.
--
--   1. Everything else steps away: the menus and the Park's HUD hide (opts.hideMenus), the world
--      behind blurs and darkens and the camera leans in.
--   2. Your card flies forward to the middle of the screen and the crystal's power gathers into
--      it: a rune circle turns behind it, runes circle it, light streams in and its rim flickers
--      through the rarity colours. The flicker slows down, longer for rarer runes; Legendary and
--      Secret seem to stop on a lower rarity, then crack through.
--   3. The rune lands: the card pops and the screen shakes, both harder the rarer it is
--      (EnchantStage.Land; the Screen shake setting still counts), a painted burst in the rune's
--      colour, rays from Epic up, stars from Mythic, wings and confetti from Legendary, and the
--      whole stage shifts through the rainbow for Secret.
--   4. The rune's name and power, then Enchant again / Lucky / Done. When the card already had a
--      rune: Keep new / Keep old (point at one to see it on the card).
--   5. Done flies the card back to its place and everything comes back.
-- Clicking anywhere while it rolls hurries it to the landing.
--
--   local stage = EnchantStage.open(opts)
--   stage:result(data)    the server's answer to Enchant ("CardResult": ok, enchant, rarity, old,
--                         pending, pity, or ok = false and why)
--   stage:chosen(data)    the server's answer to EnchantChoose (ok, enchant, kept)
--   stage:again(lucky)    rolls again (the caller already sent the request)
--   stage:note(text)      a line under the buttons (e.g. "not enough Shards")
--   stage:close(instant)  flies the card back and gives everything back (instant: at once)
--   stage.alive, stage.phase ("charge", "suspense", "land", "result", "choice", "closing")
-- opts: cardId, enchant (the rune on the card now, or nil), lucky, makeCard, hideMenus(hidden),
--   from (the card in the window it flies out of), onAgain(lucky), onChoose(keep), onClosed()

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local Enchants = require(here:WaitForChild("Enchants"))
local EnchantFx = require(here:WaitForChild("EnchantFx"))
local ShopCatalog = require(here:WaitForChild("ShopCatalog"))
local Juice = require(here:WaitForChild("Juice"))
local UIKit = require(here:WaitForChild("UIKit"))
local VfxAssets = require(here:WaitForChild("VfxAssets"))
local LayerFx = nil
pcall(function()
	LayerFx = require(here:WaitForChild("LayerFx"))
end)
local Settings = nil
pcall(function()
	Settings = require(here:WaitForChild("Settings"))
end)

local player = Players.LocalPlayer
local rgb, make, tween = Juice.rgb, Juice.make, Juice.tween

local INK = rgb(14, 10, 24)
local TEXT = rgb(240, 236, 250)
local DIM = rgb(178, 172, 200)
local GOLD = rgb(255, 214, 102)
local BAD = rgb(245, 125, 125)
local CRYSTAL = rgb(176, 222, 255)
local WHITE = Color3.new(1, 1, 1)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium
local BOLD_FONT = Enum.Font.GothamBold

local EnchantStage = {}

-- How each rarity lands. pop: how far the card jumps; shake: pixels and seconds (times the Screen
-- shake setting); flash: how see-through the flash starts (lower = brighter); lean: the camera's
-- punch in degrees; word: the size of "EPIC RUNE"; wait: seconds before the result shows.
EnchantStage.Land = {
	Common = { pop = 1.1, shake = 3, time = 0.25, flash = 0.84, lean = 0, word = 46, wait = 0.55 },
	Rare = { pop = 1.16, shake = 6, time = 0.3, flash = 0.76, lean = 1.5, word = 50, wait = 0.65 },
	Epic = { pop = 1.24, shake = 10, time = 0.42, flash = 0.66, lean = 2.5, word = 56, wait = 0.8 },
	Mythic = { pop = 1.32, shake = 15, time = 0.55, flash = 0.55, lean = 3.5, word = 60, wait = 0.95 },
	Legendary = { pop = 1.42, shake = 22, time = 0.7, flash = 0.42, lean = 5, word = 66, wait = 1.15 },
	Secret = { pop = 1.55, shake = 30, time = 0.9, flash = 0.3, lean = 7, word = 72, wait = 1.35 },
}
EnchantStage.MinCharge = 0.85 -- seconds the power gathers before a rune can land, however fast the server
EnchantStage.Timeout = 10 -- no answer by then: the crystal fizzles and you can try again
EnchantStage.FakeFrom = 5 -- from this rank (Legendary) the flicker fakes a stop, then cracks through
EnchantStage.Lean = 8 -- degrees the camera leans in while the stage is up

local function shakeScale()
	if not (Settings and Settings.ShakeScale) then
		return 1
	end
	return Settings.ShakeScale[Settings.get("shake")] or 1
end

local function lowGraphics()
	return Settings ~= nil and Settings.get("graphics") == "Low"
end

local function blurAllowed()
	return not lowGraphics() and not (Settings ~= nil and Settings.get("blur") == false)
end

local function screenSize()
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function corner(obj, px)
	return make("UICorner", { CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0) }, obj)
end

local function text(parent, str, props)
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = str,
		Font = BODY_FONT,
		TextSize = 16,
		TextColor3 = TEXT,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 20),
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
		TextSize = 20,
		TextColor3 = TEXT,
		Size = UDim2.fromOffset(170, 50),
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 14)
	make("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, rgb(196, 192, 212)) }, b)
	Juice.button(b)
	b.Activated:Connect(onClick)
	return b
end

-- One layer (1 glow, 2 rim, 3 middle, 4 core) of a painted effect sheet (VfxAssets), as a still
-- picture. nil when that sheet isn't uploaded.
local QUAD = { Vector2.new(0, 0), Vector2.new(512, 0), Vector2.new(0, 512), Vector2.new(512, 512) }
local function sheet(parent, name, layer, props)
	local id = VfxAssets[name]
	if type(id) == "number" then
		id = id > 0 and ("rbxassetid://" .. id) or nil
	end
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local img = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = id,
		ImageRectOffset = QUAD[layer],
		ImageRectSize = Vector2.new(512, 512),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 1,
	}, parent)
	for k, v in pairs(props or {}) do
		img[k] = v
	end
	return img
end

-- Colours a still picture or its text stand-in.
local function paint(obj, color, transparency)
	if obj:IsA("ImageLabel") then
		obj.ImageColor3 = color
		obj.ImageTransparency = transparency
	else
		obj.TextColor3 = color
		obj.TextTransparency = transparency
	end
end

local RAINBOW = {}
for i = 1, 5 do
	RAINBOW[i] = EnchantFx.rainbowAt((i - 1) / 5)
end

---------------------------------------------------------------------------
-- The stage
---------------------------------------------------------------------------

local Stage = {}
Stage.__index = Stage

function EnchantStage.open(opts)
	local self = setmetatable({
		opts = opts or {},
		alive = true,
		phase = "intro",
		token = 0,
		cardId = opts.cardId,
		enchant = opts.enchant, -- the rune the card wears right now
		conns = {},
		glow = 0, -- how lit the stage is (eases toward glowTarget)
		glowTarget = 0,
		spin = 0.08, -- turns a second of the rune circle (eases toward spinTarget)
		spinTarget = 0.12,
		orbitAngle = 0,
		tremble = 0, -- degrees the card shivers
		rollColor = CRYSTAL,
		rarity = nil, -- the rune that landed (the stage takes its colour)
	}, Stage)
	self:_build()
	self:_enter()
	self:_roll(opts.lucky == true)
	return self
end

function Stage:_live(token)
	return self.alive and self.token == token
end

function Stage:_build()
	local view = screenSize()
	self.view = view
	local gui = make("ScreenGui", {
		Name = "EnchantStage",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 56, -- over the menus and the pack opening, under the briefs and the toasts
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	self.gui = gui
	-- the card: as big as the screen allows, with room for the word above and the panel below
	local h = math.floor(math.clamp(math.min(view.Y - 270, view.Y * 0.5), 150, 400))
	local w = math.floor(h * 120 / 168 + 0.5)
	self.cardW, self.cardH = w, h
	local cy = math.floor(math.max(view.Y * 0.4, h / 2 + 82))
	self.cy = cy
	self.center = UDim2.new(0.5, 0, 0, cy)

	-- the room behind: darker at the edges (the blur is in Lighting)
	self.dim = make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(6, 4, 14), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
	self.vignette = make("ImageLabel", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "rbxasset://textures/ui/VignetteOverlay.png", ImageTransparency = 1, ZIndex = 2 }, gui)

	-- everything that shakes together
	local rig = make("Frame", { Name = "Rig", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 }, gui)
	self.rig = rig
	self.halo = sheet(rig, "bloom", 1, { Name = "Halo", Position = self.center, Size = UDim2.fromOffset(h * 2.6, h * 2.6), ZIndex = 2 })
	self.circle = sheet(rig, "circle", 2, { Name = "RuneCircle", Position = self.center, Size = UDim2.fromOffset(h * 1.8, h * 1.8), ZIndex = 3 })
	self.circle2 = sheet(rig, "circle", 3, { Name = "RuneCircleInner", Position = self.center, Size = UDim2.fromOffset(h * 1.3, h * 1.3), ZIndex = 3 })
	-- runes circling the card (the ones passing in front are drawn over it)
	self.runes = {}
	local runeSize = math.floor(h * 0.15)
	for i = 1, 6 do
		local r = sheet(rig, "rune", 3, { Name = "Rune" .. i, Size = UDim2.fromOffset(runeSize, runeSize), ZIndex = 4 })
		if not r then
			r = text(rig, "◆", { Name = "Rune" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(runeSize, runeSize), TextScaled = true, Font = TITLE_FONT, TextTransparency = 1, ZIndex = 4 })
		end
		self.runes[i] = r
	end
	-- the card
	local holder = make("Frame", { Name = "CardHolder", AnchorPoint = Vector2.new(0.5, 0.5), Position = self.center, Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, ZIndex = 6 }, rig)
	self.holder = holder
	local card = nil
	if self.opts.makeCard then
		local ok, made = pcall(self.opts.makeCard, holder, self.cardId, UDim2.fromScale(1, 1))
		card = ok and made or nil
	end
	if card then
		card.Name = "BigCard"
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.Active = false
			end
		end
		if self.enchant then
			EnchantFx.decorateCard(card, self.enchant, { gem = self:_gemSize() })
		end
	else
		card = make("Frame", { Name = "BigCard", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(60, 50, 90) }, holder)
		corner(card, 12)
		local def = CardData.Cards[self.cardId]
		text(card, def and def.name or "?", { Font = TITLE_FONT, TextScaled = true, Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.4) })
	end
	self.card = card
	-- the rim that flickers through the colours while it rolls
	local rim = make("Frame", { Name = "RollRim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 18, 1, 18), BackgroundTransparency = 1, ZIndex = 9 }, holder)
	corner(rim, 18)
	self.rimStroke = make("UIStroke", { Name = "Glow", Thickness = 7, Color = CRYSTAL, Transparency = 1 }, rim)
	self.rim = rim
	-- "EPIC RUNE" over the card
	self.word = text(rig, "", {
		Name = "Word",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, cy - h / 2 - 16),
		Size = UDim2.fromOffset(math.min(view.X - 24, 760), 64),
		Font = TITLE_FONT,
		TextSize = 34,
		TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 1,
		TextTransparency = 1,
		ZIndex = 8,
	})

	-- clicks anywhere hurry the roll (the buttons sit over this)
	local catcher = make("TextButton", { Name = "Catcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 20 }, gui)
	catcher.Activated:Connect(function()
		if self.phase == "charge" or self.phase == "suspense" then
			if not self.hurry then
				self.hurry = true
				Juice.sound("whoosh", 1.5, 0.25)
			end
		end
	end)

	-- the result: the rune's plate and the buttons, under the card
	local top = cy + h / 2 + 18
	self.panelRoom = math.max(120, view.Y - top - 12)
	self.panel = make("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top),
		Size = UDim2.fromOffset(math.min(view.X - 32, 640), self.panelRoom),
		BackgroundTransparency = 1,
		ZIndex = 30,
	}, gui)
	self.panelLayout = make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, self.panel)
	self.panelFit = make("UIScale", { Name = "Fit", Scale = 1 }, self.panel) -- (small screens: see _fitPanel)
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	self.hint = text(gui, touch and "Tap anywhere to hurry" or "Click anywhere to hurry", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(400, 20), TextSize = 14, TextColor3 = DIM, TextTransparency = 1, ZIndex = 30 })

	-- top: where you are, and what you have
	text(gui, "◆  ENCHANTING CRYSTAL", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(420, 22), Font = TITLE_FONT, TextSize = 18, TextColor3 = CRYSTAL, TextTransparency = 0.25, ZIndex = 30 })
	local wallet = make("Frame", { Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 14), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, BackgroundTransparency = 0.3, ZIndex = 30 }, gui)
	corner(wallet, 18)
	make("UIStroke", { Color = UIKit.Color.shard, Transparency = 0.55, Thickness = 1.5 }, wallet)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, wallet)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, wallet)
	local shardsRow, shardsLabel = UIKit.currency(wallet, "Shards", "", { size = 19, height = 30 })
	shardsRow.LayoutOrder = 1
	local gemsRow, gemsLabel = UIKit.currency(wallet, "Gems", "", { size = 19, height = 30 })
	gemsRow.LayoutOrder = 2
	local function wallet_()
		shardsLabel.Text = ShopCatalog.format(player:GetAttribute("Shards") or 0)
		gemsLabel.Text = ShopCatalog.format(player:GetAttribute("Gems") or 0)
	end
	wallet_()
	table.insert(self.conns, player:GetAttributeChangedSignal("Shards"):Connect(function()
		wallet_()
		Juice.pop(shardsRow, 1.2, 0.35)
	end))
	table.insert(self.conns, player:GetAttributeChangedSignal("Gems"):Connect(wallet_))

	-- the painted effects, the flashes and the confetti go over everything
	self.fx = make("Frame", { Name = "Fx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40 }, gui)

	-- one loop for everything that moves all the time
	local t = 0
	table.insert(self.conns, RunService.RenderStepped:Connect(function(dt)
		t += dt
		self:_frame(t, dt)
	end))
end

function Stage:_gemSize()
	return math.max(18, math.floor(self.cardH * 0.09))
end

-- The colour the stage glows in right now: the landed rune's (Secret shifts), else the flicker's.
function Stage:_color(offset)
	if self.rarity then
		return EnchantFx.color(self.rarity, offset)
	end
	return self.rollColor
end

function Stage:_frame(t, dt)
	local ease = math.min(1, dt * 4)
	self.glow += (self.glowTarget - self.glow) * ease
	self.spin += (self.spinTarget - self.spin) * ease
	local col = self:_color()
	local glow = self.glow
	if self.halo then
		self.halo.ImageColor3 = col
		self.halo.ImageTransparency = 1 - glow * (0.62 + 0.14 * math.sin(t * 2.6))
	end
	if self.circle then
		self.circle.Rotation = (self.circle.Rotation + dt * self.spin * 360) % 360
		self.circle.ImageColor3 = col
		self.circle.ImageTransparency = 1 - glow * 0.75
	end
	if self.circle2 then
		self.circle2.Rotation = (self.circle2.Rotation - dt * self.spin * 220) % 360
		self.circle2.ImageColor3 = self:_color(0.3):Lerp(WHITE, 0.25)
		self.circle2.ImageTransparency = 1 - glow * 0.5
	end
	-- the runes: an ellipse round the card, as if seen from a little above
	self.orbitAngle += dt * (0.5 + self.spin * 5)
	local n = #self.runes
	local rx, ry = self.cardW * 0.98, self.cardH * 0.6
	for i, r in ipairs(self.runes) do
		local a = self.orbitAngle + (i - 1) / n * math.pi * 2
		local front = math.sin(a) -- -1 behind the card .. 1 in front of it
		r.Position = UDim2.new(0.5, math.cos(a) * rx, 0, self.cy + front * ry * 0.45 - self.cardH * 0.04)
		r.ZIndex = front > 0 and 7 or 4
		local s = 0.75 + 0.35 * (front + 1) / 2
		r.Size = UDim2.fromOffset(self.cardH * 0.15 * s, self.cardH * 0.15 * s)
		r.Rotation = math.deg(a) * 0.25
		paint(r, self:_color(i / n), 1 - glow * (0.45 + 0.5 * (front + 1) / 2))
	end
	-- the roll's rim and the card's shiver
	if self.rimStroke and self.rimShown then
		self.rimStroke.Color = col
		self.rimStroke.Transparency = 0.15 + 0.2 * math.sin(t * 9)
	end
	if self.tremble > 0 and not self.flying then
		self.holder.Rotation = (math.random() - 0.5) * 2 * self.tremble
	end
	-- Secret: the word and the rays keep shifting through the rainbow
	if self.rarity == "Secret" then
		if self.word.TextTransparency < 1 then
			self.word.TextColor3 = col
		end
		if self.rays then
			for k, ray in ipairs(self.rayList or {}) do
				ray.BackgroundColor3 = EnchantFx.color("Secret", k / #self.rayList)
			end
		end
	end
end

---------------------------------------------------------------------------
-- In and out
---------------------------------------------------------------------------

function Stage:_enter()
	local o = self.opts
	-- where the card starts: its place in the window (read before the menus hide)
	local from = o.from
	if from and from.Parent and from.AbsoluteSize.X > 4 then
		local ap, as = from.AbsolutePosition, from.AbsoluteSize
		local sg = from:FindFirstAncestorOfClass("ScreenGui")
		local inset = (sg and not sg.IgnoreGuiInset) and GuiService:GetGuiInset().Y or 0
		self.flyFrom = { x = ap.X + as.X / 2, y = ap.Y + as.Y / 2 + inset, w = as.X, h = as.Y }
		self.holder.Position = UDim2.fromOffset(self.flyFrom.x, self.flyFrom.y)
		self.holder.Size = UDim2.fromOffset(as.X, as.Y)
		self.holder.Rotation = -5
	else
		Juice.scaleOf(self.holder).Scale = 0.15
	end
	-- the menus go, the world blurs and darkens, the camera leans in
	if o.hideMenus then
		local ok, err = pcall(o.hideMenus, true)
		if not ok then
			warn("[EnchantStage] hideMenus: " .. tostring(err))
		end
	end
	local blur = blurAllowed()
	tween(self.dim, 0.5, { BackgroundTransparency = blur and 0.42 or 0.22 })
	tween(self.vignette, 0.5, { ImageTransparency = 0.05 })
	if blur then
		self.blur = make("BlurEffect", { Name = "EnchantStageBlur", Size = 0 }, Lighting)
		tween(self.blur, 0.55, { Size = 24 })
	end
	local cam = Workspace.CurrentCamera
	if cam then
		self.fov0 = cam.FieldOfView
		self.fovIn = math.max(20, self.fov0 - EnchantStage.Lean)
		self.fovTween = tween(cam, 1.4, { FieldOfView = self.fovIn }, Enum.EasingStyle.Sine)
	end
	-- the card flies forward (it starts to shiver once it's there)
	self.flying = true
	tween(self.holder, 0.65, { Position = self.center, Size = UDim2.fromOffset(self.cardW, self.cardH), Rotation = 0 }, Enum.EasingStyle.Quint)
	task.delay(0.66, function()
		self.flying = false
	end)
	if not self.flyFrom then
		tween(Juice.scaleOf(self.holder), 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	Juice.sound("whoosh", 1.05, 0.45)
	self.glowTarget = 0.55
end

-- Gives everything back (once). instant: no easing back (Escape, leaving the Park).
function Stage:_restore(instant)
	if self.restored then
		return
	end
	self.restored = true
	if self.opts.hideMenus then
		local ok, err = pcall(self.opts.hideMenus, false)
		if not ok then
			warn("[EnchantStage] hideMenus: " .. tostring(err))
		end
	end
	if self.blur then
		local b = self.blur
		self.blur = nil
		if instant then
			b:Destroy()
		else
			tween(b, 0.35, { Size = 0 })
			task.delay(0.4, function()
				b:Destroy()
			end)
		end
	end
	if self.fovTween then
		self.fovTween:Cancel()
		self.fovTween = nil
	end
	local cam = Workspace.CurrentCamera
	if cam and self.fov0 then
		if instant then
			cam.FieldOfView = self.fov0
		else
			tween(cam, 0.5, { FieldOfView = self.fov0 }, Enum.EasingStyle.Sine)
		end
	end
end

function Stage:_destroy()
	for _, c in ipairs(self.conns) do
		c:Disconnect()
	end
	self.conns = {}
	if self.gui then
		self.gui:Destroy()
	end
	local cb = self.opts.onClosed
	self.opts.onClosed = nil
	if cb then
		task.spawn(cb)
	end
end

-- Done: the card flies back to its place in the window and everything comes back.
-- instant: at once (Escape, leaving the Park).
function Stage:close(instant)
	if not self.alive then
		return
	end
	self.alive = false
	self.token += 1
	self.phase = "closing"
	if instant then
		self:_restore(true)
		self:_destroy()
		return
	end
	self:_clearPanel()
	self.glowTarget = 0
	self.spinTarget = 0
	self.tremble = 0
	self.rimShown = false
	tween(self.word, 0.25, { TextTransparency = 1, TextStrokeTransparency = 1 })
	tween(self.hint, 0.2, { TextTransparency = 1 })
	tween(self.dim, 0.45, { BackgroundTransparency = 1 })
	tween(self.vignette, 0.45, { ImageTransparency = 1 })
	self:_clearRays(0.3)
	Juice.sound("whoosh", 0.85, 0.35)
	if self.flyFrom then
		tween(self.holder, 0.45, { Position = UDim2.fromOffset(self.flyFrom.x, self.flyFrom.y), Size = UDim2.fromOffset(self.flyFrom.w, self.flyFrom.h), Rotation = 4 }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	else
		Juice.popOut(self.holder, 0.3)
	end
	-- the menus come back while the card lands in its place
	task.delay(0.25, function()
		self:_restore()
	end)
	task.delay(0.5, function()
		self:_destroy()
	end)
end

---------------------------------------------------------------------------
-- The roll
---------------------------------------------------------------------------

-- Roll again (the caller already sent the request).
function Stage:again(lucky)
	if not self.alive or (self.phase ~= "result" and self.phase ~= "intro") then
		return
	end
	self:_roll(lucky == true)
end

function Stage:_roll(lucky)
	self.token += 1
	local token = self.token
	self.lucky = lucky
	self.res = nil
	self.hurry = false
	self.choosing = nil
	self.phase = "charge"
	self.rarity = nil
	self.rollColor = lucky and GOLD or CRYSTAL
	self:_clearPanel()
	self:_clearRays(0.3)
	tween(self.hint, 0.3, { TextTransparency = 0.2 })
	task.spawn(function()
		self:_play(token)
	end)
end

-- The server's answer to Enchant.
function Stage:result(data)
	if not self.alive or type(data) ~= "table" then
		return
	end
	if self.phase == "charge" and self.res == nil then
		self.res = data
	elseif not data.ok then
		self:note(tostring(data.why or "That didn't work."))
	end
end

-- One tick of the flicker: the rim, the word and a tick, in a rarity's colour.
function Stage:_flick(rarity, size, transparency, pitch, volume)
	local col = EnchantFx.color(rarity)
	self.rollColor = col
	self.rimShown = true
	self.word.Text = string.upper(rarity)
	self.word.TextSize = size
	self.word.TextColor3 = col
	self.word.TextTransparency = transparency
	self.word.TextStrokeTransparency = math.min(1, transparency + 0.2)
	if volume and volume > 0 then
		Juice.sound("tick", pitch, volume)
	end
end

-- Light streaming in from all round, into the card.
function Stage:_motes(n)
	if lowGraphics() then
		n = math.max(1, math.floor(n / 2))
	end
	local col = self:_color()
	for _ = 1, n do
		local ang = math.random() * math.pi * 2
		local dist = self.cardH * (0.85 + math.random() * 0.75)
		local x, y = math.cos(ang) * dist, math.sin(ang) * dist * 0.8
		local size = math.random(4, 9)
		local m = make("Frame", {
			Name = "Mote",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0, self.cy + y),
			Size = UDim2.fromOffset(size, size),
			Rotation = 45,
			BackgroundColor3 = col:Lerp(WHITE, math.random() * 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, self.rig)
		corner(m, 2)
		tween(m, 0.15, { BackgroundTransparency = 0.05 })
		local tw = tween(m, 0.45 + math.random() * 0.3, { Position = UDim2.new(0.5, x * 0.1, 0, self.cy + y * 0.1), Size = UDim2.fromOffset(2, 2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tw.Completed:Connect(function()
			m:Destroy()
		end)
	end
end

-- The camera's punch: it leans in a little more for a moment.
function Stage:_lean(degrees)
	local cam = Workspace.CurrentCamera
	if not (cam and self.fovIn) or degrees <= 0 or shakeScale() <= 0 then
		return
	end
	if self.fovTween then
		self.fovTween:Cancel()
	end
	cam.FieldOfView = self.fovIn - degrees * shakeScale()
	self.fovTween = tween(cam, 0.7, { FieldOfView = self.fovIn }, Enum.EasingStyle.Back)
end

function Stage:_clearRays(time)
	local rays = self.rays
	self.rays, self.rayList = nil, nil
	if rays then
		for _, d in ipairs(rays:GetDescendants()) do
			if d.Name == "Ray" then
				tween(d, time or 0.3, { BackgroundTransparency = 1 })
			end
		end
		task.delay((time or 0.3) + 0.05, function()
			rays:Destroy()
		end)
	end
end

-- Sun rays behind the card (Epic and up), fading in.
function Stage:_raysFor(col, rank)
	self:_clearRays(0.2)
	local view = self.view
	local rays = Juice.sunburst(self.rig, col, {
		position = self.center,
		count = 10 + rank * 2,
		length = math.max(view.X, view.Y),
		width = math.floor(self.cardW * (0.35 + rank * 0.03)),
		transparency = 1,
		speed = 6 + rank * 2,
		zIndex = 1,
	})
	rays.Name = "Rays"
	local list = {}
	for _, d in ipairs(rays:GetDescendants()) do
		if d.Name == "Ray" then
			table.insert(list, d)
			tween(d, 0.6, { BackgroundTransparency = 0.9 - rank * 0.025 })
		end
	end
	self.rays, self.rayList = rays, list
end

function Stage:_play(token)
	-- 1. The power gathers, until the server has answered (and at least MinCharge).
	local started = os.clock()
	Juice.sound("charge", self.lucky and 1.12 or 1, 0.5)
	self.glowTarget = 0.8
	self.spinTarget = 0.45
	if self.lucky then
		self.word.Text = "LUCKY ENCHANT"
		self.word.TextColor3 = GOLD
		self.word.TextSize = 40
		self.word.TextTransparency = 0
		self.word.TextStrokeTransparency = 0.3
		Juice.pop(self.word, 1.4, 0.4)
		task.wait(0.45)
	end
	local idx = math.random(1, #Enchants.Rarities)
	local i = 0
	while self:_live(token) do
		local waited = os.clock() - started
		if self.res and waited >= (self.hurry and 0.66 or EnchantStage.MinCharge) then -- (not before the card has flown in)
			break
		end
		if waited > EnchantStage.Timeout then
			self.res = { ok = false, why = "The crystal didn't answer. Give it another go." }
			break
		end
		i += 1
		idx = idx % #Enchants.Rarities + 1
		local r = Enchants.Rarities[idx]
		if self.lucky and r == "Common" then
			idx = idx % #Enchants.Rarities + 1 -- (Lucky never shows Common)
			r = Enchants.Rarities[idx]
		end
		self:_flick(r, 34, 0.35, 1 + (i % 6) * 0.04, (i % 2 == 0) and 0.14 or 0)
		self.tremble = math.min(1.2, waited * 0.8)
		self:_motes(3)
		task.wait(0.075)
	end
	if not self:_live(token) then
		return
	end
	local res = self.res
	if not res.ok then
		self:_fizzle(token, tostring(res.why or "That didn't work."))
		return
	end
	local e = Enchants.get(res.enchant)
	local rarity = (e and e.rarity) or res.rarity or "Common"
	local rank = Enchants.Rank[rarity] or 1

	-- 2. The suspense: the flicker slows down onto its stop (rarer: longer).
	self.phase = "suspense"
	local fake = rank >= EnchantStage.FakeFrom
	local stop = fake and ((rank >= 6 or math.random() < 0.5) and "Mythic" or "Epic") or rarity
	local stopRank = Enchants.Rank[stop]
	local ticks = self.hurry and 3 or (7 + rank * 2)
	local slow = 0.3 + rank * 0.04
	for k = 1, ticks do
		if not self:_live(token) then
			return
		end
		local back = ticks - k
		local r = Enchants.Rarities[((stopRank - 1 - back) % #Enchants.Rarities) + 1]
		if self.lucky and r == "Common" then
			r = "Rare"
		end
		local f = k / ticks
		self:_flick(r, 36 + f * 10, 0.2 - f * 0.2, 0.9 + f * 0.7, 0.3)
		self.tremble = 0.5 + f * rank * 0.5
		self.spinTarget = 0.45 - f * 0.25
		if not self.hurry and rank >= 4 and k == ticks - 2 then
			Juice.sound("heartbeat", 1, 0.5)
		end
		if k < ticks then
			local d = 0.06 + f ^ 2.2 * slow
			task.wait(self.hurry and d * 0.35 or d)
		end
	end
	if not self:_live(token) then
		return
	end

	if fake then
		-- It seems to stop here... then the rune cracks through.
		self:_softLand(stop)
		local hold = self.hurry and 0.3 or 0.75
		local t0 = os.clock()
		while os.clock() - t0 < hold and self:_live(token) do
			self.tremble = 0.6 + (os.clock() - t0) / hold * 3.5
			self:_motes(1)
			task.wait(0.05)
		end
		if not self:_live(token) then
			return
		end
		self:_crack(rarity)
		task.wait(self.hurry and 0.12 or 0.3)
		for r = stopRank + 1, rank do
			if not self:_live(token) then
				return
			end
			local name = Enchants.Rarities[r]
			self:_flick(name, 52, 0, 1.2 + (r - stopRank) * 0.2, 0.45)
			Juice.pop(self.word, 1.25, 0.2)
			if r < rank then
				task.wait(self.hurry and 0.08 or 0.22)
			end
		end
		if not self.hurry then
			task.wait(0.18)
		end
	end
	if not self:_live(token) then
		return
	end

	-- 3. The landing.
	self:_land(res, rarity, rank)
	local L = EnchantStage.Land[rarity] or EnchantStage.Land.Common
	task.wait(self.hurry and 0.35 or L.wait)
	if not self:_live(token) then
		return
	end

	-- 4. What you got.
	self.lastPity = tonumber(res.pity)
	if res.pending and Enchants.get(res.old) then
		self:_showChoice(res)
	else
		self.enchant = res.enchant
		self:_showResult(res.enchant)
	end
end

-- A small landing that turns out not to be the end (the fake stop).
function Stage:_softLand(rarity)
	local col = EnchantFx.color(rarity)
	self.rollColor = col
	self.word.Text = string.upper(rarity) .. "?"
	self.word.TextSize = 48
	self.word.TextTransparency = 0
	self.word.TextStrokeTransparency = 0.2
	Juice.pop(self.word, 1.3, 0.35)
	Juice.pop(self.holder, 1.06, 0.35)
	Juice.sound("land", 1.1, 0.4)
	self.spinTarget = 0.05
	self.glowTarget = 0.65
end

-- The crack: light splits the card's frame open and the climb goes on.
function Stage:_crack(rarity)
	local pal = EnchantFx.palette(rarity)
	Juice.sound("glass", 1, 0.55)
	Juice.sound("fakesting", 1, 0.6)
	Juice.flash(self.fx, WHITE, 0.35, 0.35)
	if LayerFx and LayerFx.screen then
		pcall(LayerFx.screen, "crack", self.fx, self.center, self.cardH * 1.3, { palette = pal })
	end
	local k = shakeScale()
	if k > 0 then
		Juice.shake(self.rig, 9 * k, 0.35)
	end
	Juice.shake(self.word, 6, 0.3)
	self.spinTarget = 0.9
	self.glowTarget = 1
	self.tremble = 0
end

function Stage:_land(res, rarity, rank)
	self.phase = "land"
	self.rarity = rarity -- (the stage takes the rune's colour from here on)
	self.tremble = 0
	self.holder.Rotation = 0
	self.rimShown = false
	tween(self.rimStroke, 0.3, { Transparency = 1 })
	tween(self.hint, 0.2, { TextTransparency = 1 })
	local L = EnchantStage.Land[rarity] or EnchantStage.Land.Common
	local col = EnchantFx.color(rarity)
	local pal = EnchantFx.palette(rarity)
	local sy = self.cy / self.view.Y
	-- the rune goes on the card
	EnchantFx.decorateCard(self.card, res.enchant, { gem = self:_gemSize() })
	-- the pop and the shake
	Juice.pop(self.holder, L.pop, 0.6 + rank * 0.04)
	local k = shakeScale()
	if k > 0 then
		Juice.shake(self.rig, L.shake * k, L.time)
	end
	self:_lean(L.lean)
	-- the light
	Juice.flash(self.fx, col:Lerp(WHITE, 0.45), 0.45 + rank * 0.07, L.flash)
	if LayerFx and LayerFx.screen then
		pcall(LayerFx.screen, "enchant", self.fx, self.center, self.cardH * 1.5, { palette = pal })
	end
	EnchantFx.screenBurst(self.fx, self.center, self.cardH * (0.9 + rank * 0.12), rarity)
	if rank >= 3 then
		self:_raysFor(col, rank)
	end
	if rank >= 4 then
		Juice.stars(self.fx, 0.5, sy, 8 + rank * 3, { color = col:Lerp(WHITE, 0.2), size = 26 + rank * 3, speed = 1 + rank * 0.12 })
	end
	if rank >= 5 then
		if LayerFx and LayerFx.screen then
			pcall(LayerFx.screen, "wings", self.fx, UDim2.new(0.5, 0, 0, self.cy - self.cardH * 0.08), self.cardH * 2.3, { palette = pal })
		end
		Juice.confetti(self.fx, 0.5, math.max(0.1, sy - 0.12), 30 + rank * 8, { colors = rank >= 6 and RAINBOW or { col, col:Lerp(WHITE, 0.5), GOLD, pal[2] } })
	end
	-- the sound
	Juice.sound("sting_" .. rarity, 1, 0.7)
	if rank >= 5 then
		Juice.sound("choir", 1, 0.45)
		Juice.sound("boom", 0.85, 0.5)
	elseif rank >= 3 then
		Juice.sound("crater", 1.15, 0.35)
	else
		Juice.sound("pop", 1.1, 0.45)
	end
	-- "LEGENDARY RUNE"
	self.word.Text = string.upper(rarity) .. " RUNE"
	self.word.TextSize = L.word
	self.word.TextColor3 = col
	self.word.TextTransparency = 0
	self.word.TextStrokeTransparency = 0
	Juice.pop(self.word, 1.7, 0.55)
	self.glowTarget = 0.55 + rank * 0.07
	self.spinTarget = 0.1 + rank * 0.025
end

-- No answer (or the server said no): the gathered power fades away.
function Stage:_fizzle(token, why)
	self.tremble = 0
	self.holder.Rotation = 0
	self.rimShown = false
	tween(self.rimStroke, 0.3, { Transparency = 1 })
	tween(self.hint, 0.2, { TextTransparency = 1 })
	self.glowTarget = 0.25
	self.spinTarget = 0.06
	self.word.Text = "THE CRYSTAL FALLS QUIET"
	self.word.TextSize = 30
	self.word.TextColor3 = DIM
	self.word.TextTransparency = 0.1
	self.word.TextStrokeTransparency = 0.5
	Juice.sound("thud", 0.9, 0.45)
	Juice.shake(self.holder, 5, 0.25)
	task.wait(0.35)
	if self:_live(token) then
		self:_showResult(self.enchant, why, true)
	end
end

---------------------------------------------------------------------------
-- The panel under the card
---------------------------------------------------------------------------

function Stage:_clearPanel()
	if not self.panel then
		return
	end
	for _, c in ipairs(self.panel:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	self.noteLabel = nil
end

-- The rune's plate: its name, rarity and what it does.
function Stage:_plate(eid, order, heading)
	local e = Enchants.get(eid)
	if not e then
		return nil
	end
	local col = EnchantFx.color(e.rarity)
	local def = CardData.Cards[self.cardId]
	local plate = make("Frame", { Name = "Plate", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = INK, BackgroundTransparency = 0.22, LayoutOrder = order or 1, ZIndex = 30 }, self.panel)
	corner(plate, 14)
	make("UIStroke", { Color = col, Thickness = 2, Transparency = 0.15 }, plate)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, plate)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, plate)
	text(plate, "◆ " .. e.name, { Name = "Name", Font = TITLE_FONT, TextSize = 28, TextColor3 = col, Size = UDim2.new(1, 0, 0, 32), TextStrokeColor3 = INK, TextStrokeTransparency = 0.4, LayoutOrder = 1, ZIndex = 31 })
	text(plate, heading or (e.rarity .. " rune  ·  on every copy of " .. (def and def.name or "this card")), { Name = "Rarity", TextSize = 14, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2, ZIndex = 31 })
	text(plate, e.text, { Name = "Text", TextSize = 17, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 31 })
	Juice.popIn(plate, 0, { twist = 0, sound = false, time = 0.35 })
	return plate
end

function Stage:note(str, color)
	if not (self.alive and self.panel) then
		return
	end
	if not (self.noteLabel and self.noteLabel.Parent) then
		self.noteLabel = text(self.panel, "", { Name = "Note", TextSize = 15, Font = BOLD_FONT, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 9, ZIndex = 31 })
	end
	self.noteLabel.Text = str
	self.noteLabel.TextColor3 = color or BAD
	Juice.pop(self.noteLabel, 1.12, 0.3)
	self:_fitPanel()
end

-- Small screens: once the plate and the buttons have sprung in, the panel shrinks to fit the
-- room under the card (so Done is never off the screen).
function Stage:_fitPanel()
	local token = self.token
	task.delay(0.45, function()
		if not (self:_live(token) and self.panelLayout and self.panelFit) then
			return
		end
		local now = self.panelFit.Scale
		local need = self.panelLayout.AbsoluteContentSize.Y / math.max(0.01, now)
		local want = math.clamp(self.panelRoom / math.max(1, need), 0.55, 1)
		if math.abs(want - now) > 0.01 then
			tween(self.panelFit, 0.2, { Scale = want })
		end
	end)
end

-- After a rune: Enchant again / Lucky / Done (and the bad-luck count).
function Stage:_showResult(eid, noteText, failed)
	self.phase = "result"
	self:_clearPanel()
	self:_plate(eid, 1)
	local row = make("Frame", { Name = "Buttons", Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, LayoutOrder = 3, ZIndex = 30 }, self.panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local cur, cost = ShopCatalog.priceOf(Enchants.Cost)
	local lcur, lcost = ShopCatalog.priceOf(Enchants.LuckyCost)
	local again = button(row, "", rgb(124, 72, 206), function()
		self:_again(false)
	end, { Name = "EnchantAgain", Size = UDim2.fromOffset(220, 50), LayoutOrder = 1, ZIndex = 31 })
	UIKit.caption(again, cur, (failed and "Try again  " or "Enchant again  ") .. cost)
	local lucky = button(row, "", rgb(44, 118, 184), function()
		self:_again(true)
	end, { Name = "LuckyAgain", Size = UDim2.fromOffset(160, 50), LayoutOrder = 2, ZIndex = 31 })
	UIKit.caption(lucky, lcur, "Lucky  " .. lcost)
	button(row, "Done", rgb(72, 64, 98), function()
		self:close()
	end, { Name = "Done", Size = UDim2.fromOffset(120, 50), LayoutOrder = 3, ZIndex = 31 })
	-- can't afford it: the button looks it (pressing still says where to get more)
	if cur and (player:GetAttribute(cur) or 0) < cost then
		again.BackgroundColor3 = rgb(70, 56, 96)
	end
	if lcur and (player:GetAttribute(lcur) or 0) < lcost then
		lucky.BackgroundColor3 = rgb(48, 64, 86)
	end
	local pity = self.lastPity
	if pity and not failed then
		local left = Enchants.untilPity(pity)
		text(self.panel, left <= 1 and "★ Your next enchant is Epic or better!" or ("★ Epic or better within " .. left .. " enchants"), { Name = "Pity", TextSize = 14, TextColor3 = left <= 1 and GOLD or DIM, LayoutOrder = 4, ZIndex = 31 })
	end
	for i, b in ipairs({ again, lucky }) do
		Juice.popIn(b, 0.05 * i, { twist = 0, sound = false, time = 0.3 })
	end
	if noteText then
		self:note(noteText, failed and BAD or TEXT)
	end
	self:_fitPanel()
end

function Stage:_again(lucky)
	if self.phase ~= "result" then
		return
	end
	if self.opts.onAgain then
		self.opts.onAgain(lucky)
	end
end

-- The card already had a rune: keep the new one or the old one. Pointing at either shows it on
-- the card.
function Stage:_showChoice(res)
	self.phase = "choice"
	self:_clearPanel()
	local def = CardData.Cards[self.cardId]
	text(self.panel, "This card already wears a rune. Which one stays on " .. (def and def.name or "it") .. "?", { Name = "Ask", Font = TITLE_FONT, TextSize = 19, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, ZIndex = 31 })
	local row = make("Frame", { Name = "Choice", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, ZIndex = 30 }, self.panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local boxW = math.floor((self.panel.AbsoluteSize.X > 0 and self.panel.AbsoluteSize.X or 600) / 2 - 8)
	self.choiceButtons = {}
	local gem = { gem = self:_gemSize() }
	local function option(tag, eid, keep, order)
		local e = Enchants.get(eid)
		local col = e and EnchantFx.color(e.rarity) or DIM
		local box = make("Frame", { Name = keep == "new" and "NewRune" or "OldRune", Size = UDim2.fromOffset(boxW, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = INK, BackgroundTransparency = 0.2, LayoutOrder = order, ZIndex = 30 }, row)
		corner(box, 14)
		make("UIStroke", { Color = col, Thickness = 2, Transparency = 0.15 }, box)
		make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, box)
		text(box, tag .. "  ·  " .. (e and e.rarity or "?"), { TextSize = 13, Font = BOLD_FONT, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, ZIndex = 31 })
		text(box, "◆ " .. (e and e.name or "?"), { Font = TITLE_FONT, TextSize = 24, TextColor3 = col, Size = UDim2.new(1, 0, 0, 28), TextStrokeColor3 = INK, TextStrokeTransparency = 0.4, LayoutOrder = 2, ZIndex = 31 })
		text(box, e and e.text or "", { TextSize = 15, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 31 })
		local b = button(box, keep == "new" and "Keep new" or "Keep old", keep == "new" and col:Lerp(INK, 0.35) or rgb(72, 64, 98), function()
			self:_choose(keep)
		end, { Name = keep == "new" and "KeepNew" or "KeepOld", Size = UDim2.new(1, 0, 0, 44), TextSize = 19, LayoutOrder = 4, ZIndex = 31 })
		self.choiceButtons[keep] = b
		-- point at it: the card wears it
		local function preview()
			if self.phase == "choice" and not self.choosing and e then
				EnchantFx.decorateCard(self.card, eid, gem)
				self.rarity = e.rarity
				self.word.Text = string.upper(e.rarity) .. " RUNE"
				self.word.TextColor3 = col
			end
		end
		box.MouseEnter:Connect(preview)
		b.MouseEnter:Connect(preview)
		b.SelectionGained:Connect(preview)
		Juice.popIn(box, 0.06 * order, { twist = 0, sound = false, time = 0.32 })
	end
	option("NEW", res.enchant, "new", 1)
	option("OLD", res.old, "old", 2)
	self:_fitPanel()
end

function Stage:_choose(keep)
	if self.phase ~= "choice" or self.choosing then
		return
	end
	self.choosing = keep
	for k, b in pairs(self.choiceButtons or {}) do
		b.AutoButtonColor = false
		if k ~= keep then
			tween(b, 0.2, { BackgroundTransparency = 0.6, TextTransparency = 0.5 })
		end
	end
	if self.opts.onChoose then
		self.opts.onChoose(keep)
	end
	-- (no answer in a while: let them pick again)
	local token = self.token
	task.delay(6, function()
		if self:_live(token) and self.phase == "choice" and self.choosing == keep then
			self.choosing = nil
			self:note("No answer from the crystal. Pick again.")
		end
	end)
end

-- The server's answer to EnchantChoose.
function Stage:chosen(data)
	if not self.alive or type(data) ~= "table" then
		return
	end
	if self.phase ~= "choice" then
		return
	end
	self.choosing = nil
	if not data.ok then
		self:note(tostring(data.why or "That didn't work."))
		return
	end
	local eid = Enchants.get(data.enchant) and data.enchant or nil
	self.enchant = eid
	local e = Enchants.get(eid)
	if e then
		EnchantFx.decorateCard(self.card, eid, { gem = self:_gemSize() })
		self.rarity = e.rarity
		self.word.Text = string.upper(e.rarity) .. " RUNE"
		self.word.TextColor3 = EnchantFx.color(e.rarity)
		Juice.pop(self.word, 1.2, 0.35)
	end
	Juice.pop(self.holder, 1.1, 0.45)
	Juice.sound(data.kept == "new" and "twang" or "land", 1.1, 0.45)
	self:_showResult(eid, data.kept == "new" and "The new rune is on." or "The old rune stays.")
end

return EnchantStage

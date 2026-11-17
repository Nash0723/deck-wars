-- CardInspect: a card's 3D model up close, big, on a lit plinth. Client only.
--
-- Opened from the Deck Shelf: tap a card to see its copies, then tap the big card (or the
-- Inspect button under it). Cards you haven't found yet open here straight from All cards.
--
--   CardInspect.open(id, opts)   opts = { makeCard, buildModel, level, enchant, owned, onClose }
--                                (makeCard / buildModel are DeckWarsClient's, passed in by the shelf)
--   CardInspect.close()
--   CardInspect.isOpen()         -- true while it's open, and for a blink after it closes, so the key
--                                   that closed it doesn't also move the room (DeckWarsClient checks it)
--
-- While it's open: drag (or A / D, Left / Right) turns the model, the mouse wheel or a pinch zooms,
-- dragging up and down tilts the view, Esc / S / Backspace (or tapping outside) closes.
-- Everything else steps aside (UIKit.Focus), the room blurs, and a glow in the card's rarity
-- colour sits behind it. Creatures breathe and look around, and play their Pack Brawl moves on the
-- buttons under them (Rig + Moves): an attack, a cheer, a flex and, for the big ones, their
-- signature move.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local CardLevels = require(here:WaitForChild("CardLevels"))
local CreatureBuilder = require(here:WaitForChild("CreatureBuilder"))
local Juice = require(here:WaitForChild("Juice"))
local UIKit = require(here:WaitForChild("UIKit"))
local Enchants = require(here:WaitForChild("Enchants"))
local EnchantFx = require(here:WaitForChild("EnchantFx"))
local Settings = nil
pcall(function()
	Settings = require(here:WaitForChild("Settings"))
end)

local rgb, make, tween = Juice.rgb, Juice.make, Juice.tween
local C = UIKit.Color
local WHITE = rgb(255, 255, 255)
local INK = rgb(18, 13, 10)

local CardInspect = {}

-- Knobs
CardInspect.AutoTurnSpeed = 0.32 -- radians a second while nobody touches it
CardInspect.AutoTurnDelay = 2.2 -- seconds after the last drag before it starts turning again
CardInspect.DragSpeed = 0.011 -- radians per pixel dragged
CardInspect.KeyTurnSpeed = 2.2 -- radians a second while A / D is held
CardInspect.ZoomMin, CardInspect.ZoomMax = 0.55, 1.7
CardInspect.PitchMin, CardInspect.PitchMax = -6, 42 -- degrees the view can tilt
CardInspect.StartYaw = math.rad(24) -- a three-quarter view to start with

local RANK = { Common = 1, Rare = 2, Epic = 3, Mythic = 4, Legendary = 5, Secret = 6 }
local TIER = {
	Common = rgb(222, 212, 190),
	Rare = rgb(61, 165, 255),
	Epic = rgb(166, 77, 255),
	Mythic = rgb(255, 59, 92),
	Legendary = rgb(255, 194, 26),
	Secret = rgb(255, 255, 255),
}

local S = nil -- the open inspector
local closedAt = -10

local function lowGraphics()
	return Settings ~= nil and Settings.get("graphics") == "Low"
end

local function c3(v, fallback)
	return v and rgb(v[1], v[2], v[3]) or fallback
end

local function round(obj, px)
	return make("UICorner", { CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0) }, obj)
end

local function label(parent, str, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = str,
		Font = UIKit.BODY_FONT,
		TextSize = 15,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function rainbowAt(t)
	return Color3.fromHSV(t % 1, 0.5, 1)
end

-- Pack Brawl's rig and moves (in ReplicatedStorage.PackBrawl). Without them the model just turns.
local Rig, Moves = nil, nil
local function brawlKit()
	if Rig == nil then
		local ok = pcall(function()
			local pb = ReplicatedStorage:WaitForChild("PackBrawl", 5)
			Rig = require(pb:WaitForChild("Rig", 5))
			Moves = require(pb:WaitForChild("Moves", 5))
		end)
		if not ok or not Rig or not Moves then
			Rig, Moves = false, false
		end
	end
	return Rig or nil, Moves or nil
end

---------------------------------------------------------------------------
-- The model
---------------------------------------------------------------------------

-- Particles, fire and lights don't draw in a ViewportFrame, so they're left out.
local function stripEffects(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
end

-- The model for a card (its own one from ReplicatedStorage.CreatureModels when there is one) and
-- whether it's a custom one (those don't get the moving limbs).
local function modelFor(id, opts)
	local folder = ReplicatedStorage:FindFirstChild("CreatureModels")
	local custom = folder and folder:FindFirstChild(id)
	if custom and custom:IsA("Model") and opts.buildModel then
		return opts.buildModel(id), true
	end
	if CreatureBuilder.has(id) then
		return CreatureBuilder.build(id), false
	end
	return nil, false
end

-- Each part with its place relative to the model's feet, and the bone that moves it (matched to the
-- rig's parts by name and position, the way Pack Brawl's fighters do it).
local function collectParts(model, rig)
	local base = model:GetPivot()
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d == model.PrimaryPart and d.Name == "Root" then
				d.Transparency = 1
			else
				table.insert(parts, { part = d, offset = base:ToObjectSpace(d.CFrame), size = d.Size, bone = "body" })
			end
		end
	end
	if rig then
		local used = {}
		for _, e in ipairs(parts) do
			local pos = e.offset.Position
			local best, bd = nil, math.huge
			for i, rp in ipairs(rig.parts) do
				if not used[i] and rp.name == e.part.Name then
					local dd = (pos.X - rp.pos[1]) ^ 2 + (pos.Y - rp.pos[2]) ^ 2 + (pos.Z - rp.pos[3]) ^ 2
					if dd < bd then
						best, bd = i, dd
					end
				end
			end
			if best then
				used[best] = true
				e.bone = rig.partBone[best] or "body"
			end
		end
	end
	return parts
end

-- A calm idle: breathing, a slow look around, arms loose, the tail and wings drifting.
local function idlePose(t, phase, rig)
	local b = math.sin(t * 1.7 + phase)
	local pose = {
		root = { u = 0.006 * (1 + b) },
		body = { p = 2.5 * b, y = 4 * math.sin(t * 0.55 + phase), r = 1.5 * math.sin(t * 0.9 + phase) },
		head = { p = -2 + 4 * math.sin(t * 1.7 + phase + 0.8), y = 12 * math.sin(t * 0.42 + phase + 1.3), r = 3 * math.sin(t * 0.6 + phase) },
		lead = { p = 6 + 5 * math.sin(t * 1.7 + phase + 1.2), r = 6 },
		rear = { p = 6 + 5 * math.sin(t * 1.7 + phase + 2.0), r = 6 },
		tail = { y = 16 * math.sin(t * 1.9 + phase), p = 5 * math.sin(t * 1.3 + phase) },
		wings = { r = 14 + 10 * math.sin(t * 3.2 + phase) },
	}
	if rig.kind == "quad" then
		pose.body = { p = 1.5 * b }
		pose.head = { p = 6 + 4 * math.sin(t * 1.1 + phase), y = 14 * math.sin(t * 0.4 + phase) }
	elseif rig.kind == "blob" or rig.kind == "arms" then
		pose.root = { u = 0.01 * (1 + b) }
		pose.body = { p = 3 * b, r = 3 * math.sin(t * 1.2 + phase) }
	end
	return pose
end

-- The round plinth the model stands on: dark walnut, a thin rim in the rarity colour, the family
-- colour inlaid on top and a soft contact shadow (a ViewportFrame draws no shadows of its own).
local function buildPlinth(parent, diameter, tier, fam)
	local plinth = Instance.new("Model")
	plinth.Name = "Plinth"
	local function disc(name, d, height, y, color, material, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(height, d, d)
		p.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Transparency = transparency or 0
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = plinth
		return p
	end
	disc("Foot", diameter * 1.08, 0.18, -0.62, rgb(38, 26, 20))
	disc("Body", diameter, 0.56, -0.3, rgb(66, 45, 33), Enum.Material.Wood)
	local rim = disc("Rim", diameter * 1.035, 0.1, -0.07, tier, Enum.Material.Neon)
	disc("Inlay", diameter * 0.86, 0.05, -0.005, fam:Lerp(rgb(30, 22, 18), 0.55))
	disc("InlayRing", diameter * 0.9, 0.04, -0.012, fam:Lerp(WHITE, 0.15), Enum.Material.SmoothPlastic)
	disc("Shadow", diameter * 0.55, 0.02, 0.03, rgb(8, 6, 6), Enum.Material.SmoothPlastic, 0.45)
	plinth.Parent = parent
	return plinth, rim
end

---------------------------------------------------------------------------
-- The info panel
---------------------------------------------------------------------------

local function chip(parent, value, caption, color, order)
	local f = make("Frame", { Name = "Chip_" .. caption, Size = UDim2.new(0.31, 0, 0, 58), BackgroundColor3 = color:Lerp(C.ink, 0.55), LayoutOrder = order }, parent)
	round(f, 12)
	make("UIStroke", { Thickness = 1.5, Color = color, Transparency = 0.35 }, f)
	label(f, tostring(value), { Name = "Value", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 5), Font = UIKit.TITLE_FONT, TextSize = 28, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center })
	label(f, caption, { Name = "Caption", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -20), TextSize = 12, TextColor3 = color:Lerp(WHITE, 0.55), TextXAlignment = Enum.TextXAlignment.Center })
	return f
end

local function block(parent, order, accent)
	local f = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.tile, BackgroundTransparency = 0.15, LayoutOrder = order }, parent)
	round(f, 12)
	if accent then
		make("UIStroke", { Thickness = 1.5, Color = accent, Transparency = 0.4 }, f)
	end
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

local function wrapped(parent, str, props)
	local base = { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }
	for k, v in pairs(props or {}) do
		base[k] = v
	end
	return label(parent, str, base)
end

local function buildInfo(panel, def, opts, tier)
	local scroll = make("ScrollingFrame", {
		Name = "Info",
		Size = UDim2.new(1, -8, 1, -16),
		Position = UDim2.fromOffset(4, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.line,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, scroll)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	-- the card itself, with its name and rarity beside it
	local head = make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 1, LayoutOrder = 1 }, scroll)
	if opts.makeCard then
		local holder = make("Frame", { Name = "MiniCard", Size = UDim2.fromOffset(102, 143), Position = UDim2.fromOffset(2, 3), BackgroundTransparency = 1, Rotation = -3 }, head)
		local ok, card = pcall(opts.makeCard, holder, def.id, UDim2.fromScale(1, 1), nil, true, opts.level)
		if ok and card and opts.enchant then
			pcall(EnchantFx.decorateCard, card, opts.enchant)
		end
	end
	local side = make("Frame", { Name = "Side", Size = UDim2.new(1, -118, 1, 0), Position = UDim2.fromOffset(118, 0), BackgroundTransparency = 1 }, head)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, side)
	local pill = label(side, string.upper(def.rarity), {
		Name = "Rarity",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = tier,
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		TextColor3 = INK,
		LayoutOrder = 1,
	})
	round(pill, 11)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, pill)
	if def.rarity == "Secret" then
		pill:SetAttribute("Rainbow", true)
	end
	wrapped(side, def.name, { Name = "CardName", Font = UIKit.TITLE_FONT, TextSize = 26, TextColor3 = C.gold, LayoutOrder = 2 })
	local fam = def.family ~= "Any" and def.family or nil
	label(side, def.type .. (fam and ("  ·  " .. fam) or ""), { Name = "Kind", Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = C.dim, LayoutOrder = 3 })

	-- the numbers
	local stats = make("Frame", { Name = "Stats", Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, LayoutOrder = 2 }, scroll)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.035, 0), SortOrder = Enum.SortOrder.LayoutOrder }, stats)
	chip(stats, def.cost, "Cost", rgb(70, 130, 235), 1)
	if def.atk ~= nil and def.type ~= "Building" then
		chip(stats, def.atk, "Attack", rgb(220, 96, 70), 2)
	end
	if def.hp ~= nil then
		chip(stats, def.hp, "Health", rgb(70, 180, 110), 3)
	end

	-- what it does
	local text = def.text
	if (text == nil or text == "") and def.type == "Creature" then
		text = "Just a good fighter."
	end
	if text and text ~= "" then
		local b = block(scroll, 3)
		label(b, "ABILITY", { Size = UDim2.new(1, 0, 0, 14), Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.dim, LayoutOrder = 1 })
		wrapped(b, text, { TextSize = 15, LayoutOrder = 2 })
	end
	if def.sparkText then
		local purple = rgb(186, 120, 255)
		local b = block(scroll, 4, purple)
		label(b, "SPARK  ·  " .. (def.sparkCost or 0) .. " ✨", { Size = UDim2.new(1, 0, 0, 14), Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = purple, LayoutOrder = 1 })
		wrapped(b, def.sparkText, { TextSize = 15, LayoutOrder = 2 })
	end
	local kws = {}
	for k in pairs(def.keywords or {}) do
		if CardData.KeywordText and CardData.KeywordText[k] then
			table.insert(kws, k)
		end
	end
	table.sort(kws)
	if #kws > 0 then
		local b = block(scroll, 5)
		label(b, "KEYWORDS", { Size = UDim2.new(1, 0, 0, 14), Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.dim, LayoutOrder = 1 })
		for i, k in ipairs(kws) do
			wrapped(b, "<b>" .. k .. "</b>  " .. CardData.KeywordText[k], { RichText = true, TextSize = 13, TextColor3 = C.text, LayoutOrder = 1 + i })
		end
	end

	-- your copy: its level and enchant
	if opts.level then
		local max = CardLevels.maxLevel(def.id)
		local b = block(scroll, 6)
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
		UIKit.levelPips(row, opts.level, max, { Size = UDim2.fromOffset(0, 18), Position = UDim2.fromOffset(0, 1), AnchorPoint = Vector2.new(0, 0) })
		label(row, "Level " .. opts.level .. " of " .. max .. (opts.level >= max and "  ·  MAX" or ""), { Size = UDim2.new(1, -96, 1, 0), Position = UDim2.fromOffset(96, 0), Font = UIKit.TITLE_FONT, TextSize = 16, TextColor3 = opts.level >= max and C.gold or C.text })
		local now = CardLevels.bonusText(def.id, opts.level)
		wrapped(b, now ~= "no bonus" and ("Bonus: " .. now) or "No level bonus yet. Fuse copies to level it up.", { TextSize = 13, TextColor3 = C.dim, LayoutOrder = 2 })
	end
	local e = Enchants.get(opts.enchant)
	if e then
		local col = EnchantFx.color(e.rarity)
		local b = block(scroll, 7, col)
		label(b, "◆ " .. e.name .. "  ·  " .. e.rarity, { Size = UDim2.new(1, 0, 0, 20), Font = UIKit.TITLE_FONT, TextSize = 16, TextColor3 = col, LayoutOrder = 1 })
		wrapped(b, e.text, { TextSize = 13, LayoutOrder = 2 })
	end
	local owned = opts.owned or 0
	label(scroll, owned > 0 and ("In your collection  ×" .. owned) or "Not found yet  ·  open packs at Pack Party", {
		Name = "Owned",
		Size = UDim2.new(1, 0, 0, 22),
		Font = owned > 0 and UIKit.TITLE_FONT or UIKit.BODY_FONT,
		TextSize = owned > 0 and 16 or 14,
		TextColor3 = owned > 0 and C.gold or C.dim,
		LayoutOrder = 9,
	})
	return scroll, pill
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

function CardInspect.isOpen()
	return S ~= nil or (os.clock() - closedAt) < 0.25
end

function CardInspect.close()
	local s = S
	if not s or s.closing then
		return
	end
	s.closing = true
	s.closeT = s.t
	closedAt = os.clock()
	Juice.sound("whoosh", 1.25, 0.3)
	if s.onClose then
		task.spawn(s.onClose)
	end
	tween(s.backdrop, 0.3, { BackgroundTransparency = 1 })
	tween(s.vignette, 0.3, { ImageTransparency = 1 })
	if s.panelOut then
		tween(s.panel, 0.28, { AnchorPoint = s.panelOut() }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	for _, g in ipairs(s.fadeOut) do
		if g:IsA("TextLabel") or g:IsA("TextButton") then
			tween(g, 0.2, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif g:IsA("ViewportFrame") then
			tween(g, 0.3, { ImageTransparency = 1 })
		else
			tween(g, 0.25, { BackgroundTransparency = 1 })
		end
	end
	task.delay(0.32, function()
		for _, c in ipairs(s.conns) do
			c:Disconnect()
		end
		if s.root.Parent then
			s.root.Visible = false -- (Focus brings the room's menus back)
		end
		s.gui:Destroy()
		if S == s then
			S = nil
		end
		closedAt = os.clock()
	end)
end

function CardInspect.open(id, opts)
	local def = CardData.Cards[id]
	if not def then
		return
	end
	if S then
		-- (instantly: a new card replaces the one being looked at)
		local old = S
		S = nil
		for _, c in ipairs(old.conns) do
			c:Disconnect()
		end
		old.gui:Destroy()
	end
	opts = opts or {}
	local rank = RANK[def.rarity] or 1
	local tier = TIER[def.rarity] or TIER.Common
	local secret = def.rarity == "Secret"
	local fam = c3(CardData.FamilyColors[def.family], rgb(220, 210, 200))
	local low = lowGraphics()
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", { Name = "CardInspect", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
	local root = make("Frame", { Name = "Inspect", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	root:SetAttribute("KeepColors", true) -- (the cozy menu colours leave the rarity light alone)

	local s = {
		id = id,
		def = def,
		gui = gui,
		root = root,
		conns = {},
		fadeOut = {},
		t = 0,
		phase = math.random() * 6.28,
		yaw = CardInspect.StartYaw,
		yawVel = 0,
		pitch = 12,
		pitchTarget = 12,
		zoom = 1,
		zoomTarget = 1,
		autoTurn = true,
		lastInput = -10,
		keyDir = 0,
		swings = 0,
		onClose = opts.onClose,
	}
	S = s
	local function on(signal, fn)
		local c = signal:Connect(fn)
		table.insert(s.conns, c)
		return c
	end

	-- behind everything: the room, blurred and dimmed (Focus), then a dark wash with a vignette
	local backdrop = make("TextButton", { Name = "Backdrop", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(14, 10, 12), BackgroundTransparency = 1, BorderSizePixel = 0 }, root)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.55, 0.5),
			NumberSequenceKeypoint.new(1, 0.12),
		}),
	}, backdrop)
	local vignette = make("ImageLabel", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "rbxasset://textures/ui/VignetteOverlay.png", ImageColor3 = rgb(0, 0, 0), ImageTransparency = 1 }, root)
	s.backdrop, s.vignette = backdrop, vignette
	tween(backdrop, 0.35, { BackgroundTransparency = 0 })
	tween(vignette, 0.35, { ImageTransparency = 0.15 })
	on(backdrop.Activated, function()
		CardInspect.close()
	end)

	-- the stage (left / top) and the info panel (right / bottom)
	-- (the stage takes clicks too, so only a tap on the margins closes it)
	local stage = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Active = true, ZIndex = 2 }, root)
	local panel = make("Frame", { Name = "Panel", BackgroundColor3 = C.panel, BackgroundTransparency = 0.04, Active = true, ZIndex = 3 }, root)
	round(panel, 18)
	make("UIStroke", { Thickness = 2, Color = tier, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	UIKit.rim(panel, 18)
	s.panel = panel

	-- the glow behind the model, in the rarity colour (soft rings stacked into a pool of light)
	local glow = make("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, stage)
	make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, glow)
	local glowRings = {}
	for k = 1, 6 do
		local ring = make("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.22 + k * 0.13, 0.22 + k * 0.13), BackgroundColor3 = tier, BackgroundTransparency = 1, BorderSizePixel = 0 }, glow)
		round(ring)
		table.insert(glowRings, ring)
		table.insert(s.fadeOut, ring)
		tween(ring, 0.6, { BackgroundTransparency = rank >= 5 and 0.9 or 0.93 })
	end
	local rays = nil
	if rank >= 4 and not low then
		rays = Juice.sunburst(glow, tier, { count = 10, length = 900, width = 70, transparency = 1, speed = 5 })
		for _, d in ipairs(rays:GetDescendants()) do
			if d.Name == "Ray" then
				make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 1) }) }, d)
				tween(d, 0.8, { BackgroundTransparency = 0.88 })
				table.insert(s.fadeOut, d)
			end
		end
	end

	-- the card's name, huge and faint, behind the model (the fighting-game select screen look)
	local bigName = label(stage, string.upper(def.name), {
		Name = "BigName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.96, 0.2),
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = tier,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	make("UITextSizeConstraint", { MaxTextSize = 110 }, bigName)
	tween(bigName, 0.8, { TextTransparency = 0.86 })
	table.insert(s.fadeOut, bigName)

	-- the 3D view
	local view = make("ViewportFrame", {
		Name = "View",
		Size = UDim2.new(1, 0, 1, -86),
		BackgroundTransparency = 1,
		Active = true, -- (clicks on the model don't close it)
		Ambient = rgb(138, 134, 150),
		LightColor = rgb(255, 245, 230),
		LightDirection = Vector3.new(-0.6, -1, -0.8), -- (the same key light as the little card pictures)
	}, stage)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = view
	view.CurrentCamera = cam
	s.view, s.cam = view, cam
	view.ImageTransparency = 1
	tween(view, 0.25, { ImageTransparency = 0 })
	table.insert(s.fadeOut, view)

	local model, custom = modelFor(id, opts)
	local h, wide = 2.5, 2.5
	local plinthD
	if model then
		stripEffects(model)
		if custom then
			local ok, _, size = pcall(function()
				return model:GetBoundingBox()
			end)
			if ok and size then
				h, wide = size.Y, math.max(size.X, size.Z)
			end
		else
			local info = CreatureBuilder.info(id)
			if info then
				h, wide = math.max(info.height, 0.5), math.max(info.width, info.depth, 0.5)
			end
		end
		local R, M = brawlKit()
		local rig = (not custom and def.type == "Creature" and R) and R.get(id) or nil
		s.rig, s.Moves = rig, M
		s.leadSide = (rig and rig.weaponSide == -1) and "L" or "R"
		s.parts = collectParts(model, rig)
		s.model = model
		s.h, s.wide = h, wide
		model.Parent = view
		plinthD = math.max(wide * 1.3, h * 0.75, 2.4)
		local _, rim = buildPlinth(view, plinthD, tier, fam)
		s.rim = rim
	else
		-- a spell without a 3D model: the card itself floats on the stage
		local holder = make("Frame", { Name = "FloatCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.78), BackgroundTransparency = 1, ZIndex = 3 }, stage)
		make("UIAspectRatioConstraint", { AspectRatio = 120 / 168 }, holder)
		if opts.makeCard then
			pcall(opts.makeCard, holder, id, UDim2.fromScale(1, 1), nil, nil, opts.level)
		end
		s.floatCard = holder
		Juice.popIn(holder, 0.1, { sound = false })
	end
	s.plinthD = plinthD or 2.4

	-- moves under the stage
	local bar = make("Frame", { Name = "Actions", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, stage)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local order = 0
	local function action(text, color, fn)
		order += 1
		local b = make("TextButton", {
			Name = "Action_" .. order,
			Text = text,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(0, 38),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = color or C.tile,
			BackgroundTransparency = 0.05,
			Font = UIKit.TITLE_FONT,
			TextSize = 16,
			TextColor3 = C.text,
			LayoutOrder = order,
		}, bar)
		round(b, 19)
		make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, b)
		make("UIStroke", { Thickness = 1.5, Color = INK, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		Juice.button(b, { grow = 1.06 })
		Juice.popIn(b, 0.25 + order * 0.05, { sound = false, twist = 0 })
		on(b.Activated, function()
			s.lastInput = s.t
			fn(b)
		end)
		table.insert(s.fadeOut, b)
		return b
	end
	local function playMove(name, hold)
		local M = s.Moves
		local m = M and M.get(name)
		if not m then
			return
		end
		s.anim = { move = m, t0 = s.t, hold = hold or (m.loop and 1.9) or m.dur }
		Juice.sound("whoosh", 1.1 + math.random() * 0.2, 0.35)
		if m.contact then
			task.delay(m.contact, function()
				if S == s and not s.closing then
					Juice.sound("slap", 0.95 + math.random() * 0.15, 0.4)
				end
			end)
		end
		return m
	end
	if s.rig and s.Moves then
		action("Attack", rgb(150, 66, 50), function()
			s.swings += 1
			local power = (s.swings - 1) % 3 + 1
			playMove(s.Moves.pickAttack(s.rig, power, s.swings, id, false))
		end)
		action("Cheer", nil, function()
			playMove("cheer", 1.9)
		end)
		if s.rig.has and s.rig.has.arms then
			action("Flex", nil, function()
				playMove("flex", 2.0)
			end)
		end
		if s.Moves.Signatures and s.Moves.Signatures[id] then
			action("★ Signature", rgb(196, 140, 40), function(b)
				local m = playMove(id)
				if m then
					local at = m.contact or s.Moves.SignatureContact or 0.45
					task.delay(at, function()
						if S ~= s or s.closing then
							return
						end
						Juice.shake(stage, 6, 0.3)
						local a, z = stage.AbsolutePosition, root.AbsoluteSize
						if z.X > 0 then
							local c = a + stage.AbsoluteSize * Vector2.new(0.5, 0.55)
							Juice.stars(root, c.X / z.X, c.Y / z.Y, low and 6 or 12, { color = tier, zIndex = 30, size = 22 })
						end
					end)
				end
			end)
		end
	end
	local turnButton
	turnButton = action("Auto-turn: On", nil, function()
		s.autoTurn = not s.autoTurn
		turnButton.Text = s.autoTurn and "Auto-turn: On" or "Auto-turn: Off"
		Juice.sound("tick", 1.1, 0.35)
	end)
	action("Reset view", nil, function()
		s.yawTarget = CardInspect.StartYaw
		s.pitchTarget = 12
		s.zoomTarget = 1
		Juice.sound("tick", 0.9, 0.35)
	end)
	local hint = label(stage, touch and "Drag to turn  ·  Pinch to zoom  ·  Tap outside to close" or "Drag to turn  ·  Scroll to zoom  ·  A / D turn  ·  Esc to close", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 13,
		TextColor3 = rgb(230, 220, 205),
		TextTransparency = 1,
		TextStrokeTransparency = 0.7,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tween(hint, 0.6, { TextTransparency = 0.2 })
	table.insert(s.fadeOut, hint)

	local _, rarityPill = buildInfo(panel, def, opts, tier)
	s.pill = rarityPill

	local close = UIKit.closeButton(root, function()
		CardInspect.close()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 18), Size = UDim2.fromOffset(44, 44), ZIndex = 5 })
	table.insert(s.fadeOut, close)

	-- layout: side by side on wide screens, stacked on narrow ones
	local homeAnchor = Vector2.new(1, 0.5)
	local function layout()
		local sz = root.AbsoluteSize
		if sz.X <= 0 then
			return
		end
		if sz.X < 860 then
			homeAnchor = Vector2.new(0.5, 1)
			panel.Position = UDim2.new(0.5, 0, 1, -12)
			panel.Size = UDim2.new(1, -24, 0.38, 0)
			stage.Position = UDim2.fromOffset(12, 64)
			stage.Size = UDim2.new(1, -24, 0.62, -84)
		else
			homeAnchor = Vector2.new(1, 0.5)
			panel.Position = UDim2.new(1, -28, 0.5, 14)
			panel.Size = UDim2.new(0, 372, 0.8, 0)
			stage.Position = UDim2.fromOffset(28, 70)
			stage.Size = UDim2.new(1, -(28 + 372 + 28 + 24), 1, -96)
		end
		if not s.panelIn then
			panel.AnchorPoint = homeAnchor
		end
	end
	layout()
	on(root:GetPropertyChangedSignal("AbsoluteSize"), function()
		s.panelIn = false
		layout()
	end)
	-- the panel slides in from its side (and out again when it closes)
	function s.panelOut()
		return homeAnchor.Y == 1 and Vector2.new(0.5, 0) or Vector2.new(-0.1, 0.5)
	end
	s.panelIn = true
	panel.AnchorPoint = s.panelOut()
	tween(panel, 0.5, { AnchorPoint = homeAnchor }, Enum.EasingStyle.Quint).Completed:Connect(function()
		s.panelIn = false
	end)

	-- everything else steps aside while you look
	UIKit.Focus.watch(root, { hide = { "title", "profile", "signs", "station", "nav", "dev" }, dim = 0.45, blur = 16, animate = false })

	-- the entrance: a whoosh, the model springs up out of the plinth, the rarer the louder
	Juice.sound("whoosh", 0.95, 0.4)
	task.delay(0.28, function()
		if S ~= s then
			return
		end
		Juice.sound(rank >= 3 and "chime" or "pop", 0.85 + rank * 0.06, 0.4)
		local a, z = stage.AbsolutePosition, root.AbsoluteSize
		if z.X <= 0 then
			return
		end
		local c = a + view.AbsoluteSize * Vector2.new(0.5, 0.62)
		if rank >= 2 then
			-- a ring of light runs out across the floor
			local ring = make("Frame", { Name = "Pulse", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(c.X, c.Y), Size = UDim2.fromOffset(60, 22), BackgroundTransparency = 1, ZIndex = 5 }, root)
			round(ring)
			local st = make("UIStroke", { Thickness = 4, Color = tier, Transparency = 0.1 }, ring)
			tween(ring, 0.7, { Size = UDim2.fromOffset(view.AbsoluteSize.X * 0.8, view.AbsoluteSize.X * 0.22) }, Enum.EasingStyle.Quint)
			tween(st, 0.7, { Transparency = 1, Thickness = 1 }).Completed:Connect(function()
				ring:Destroy()
			end)
		end
		if rank >= 3 and not low then
			Juice.stars(root, c.X / z.X, (c.Y - view.AbsoluteSize.Y * 0.2) / z.Y, 4 + rank * 2, { color = tier, zIndex = 30, size = 20, gravity = 120 })
		end
		if rank >= 5 then
			Juice.flash(root, tier, 0.5, 0.78)
		end
	end)

	-- input: drag to turn and tilt, the wheel / a pinch to zoom, A / D to turn, Esc to close
	local dragging = nil
	local lastPos = nil
	on(view.InputBegan, function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = input
			lastPos = input.Position
			s.yawVel = 0
			s.yawTarget = nil
			s.lastInput = s.t
		end
	end)
	on(view.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			s.zoomTarget = math.clamp(s.zoomTarget * (1 - input.Position.Z * 0.12), CardInspect.ZoomMin, CardInspect.ZoomMax)
			s.lastInput = s.t
		end
	end)
	on(UserInputService.InputChanged, function(input)
		if not dragging or not lastPos then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == dragging) then
			local d = input.Position - lastPos
			lastPos = input.Position
			s.yaw += d.X * CardInspect.DragSpeed
			s.yawVel = s.yawVel * 0.5 + d.X * CardInspect.DragSpeed * 30
			s.pitchTarget = math.clamp(s.pitchTarget + d.Y * 0.18, CardInspect.PitchMin, CardInspect.PitchMax)
			s.lastInput = s.t
		end
	end)
	on(UserInputService.InputEnded, function(input)
		local t = input.UserInputType
		if dragging and (t == Enum.UserInputType.MouseButton1 or (t == Enum.UserInputType.Touch and input == dragging)) then
			dragging = nil
			s.lastInput = s.t
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.A or k == Enum.KeyCode.Left or k == Enum.KeyCode.DPadLeft or k == Enum.KeyCode.D or k == Enum.KeyCode.Right or k == Enum.KeyCode.DPadRight then
			s.keyDir = 0
			s.lastInput = s.t
		end
	end)
	local pinchFrom = nil
	on(UserInputService.TouchPinch, function(_, scale, _, state)
		if state == Enum.UserInputState.Begin then
			pinchFrom = s.zoomTarget
		elseif pinchFrom and scale and scale > 0 then
			s.zoomTarget = math.clamp(pinchFrom / scale, CardInspect.ZoomMin, CardInspect.ZoomMax)
		end
		if state == Enum.UserInputState.End then
			pinchFrom = nil
		end
		s.lastInput = s.t
	end)
	on(UserInputService.InputBegan, function(input)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace or k == Enum.KeyCode.S or k == Enum.KeyCode.Down or k == Enum.KeyCode.ButtonB then
			CardInspect.close()
		elseif k == Enum.KeyCode.A or k == Enum.KeyCode.Left or k == Enum.KeyCode.DPadLeft then
			s.keyDir = -1
			s.yawTarget = nil
		elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right or k == Enum.KeyCode.DPadRight then
			s.keyDir = 1
			s.yawTarget = nil
		end
	end)

	-- every frame: the camera, the turn, the pose
	local sizeDone = false
	on(RunService.RenderStepped, function(dt)
		dt = math.min(dt, 0.1)
		s.t += dt
		local t = s.t
		-- turning
		if s.keyDir ~= 0 then
			s.yaw += s.keyDir * CardInspect.KeyTurnSpeed * dt
			s.lastInput = t
		elseif s.yawTarget then
			-- Reset view: the short way round to the start
			local diff = (s.yawTarget - s.yaw + math.pi) % (2 * math.pi) - math.pi
			s.yaw += diff * math.min(1, dt * 6)
			if math.abs(diff) < 0.002 then
				s.yawTarget = nil
			end
		elseif not dragging then
			s.yaw += s.yawVel * dt
			s.yawVel *= math.exp(-3.5 * dt)
			if s.autoTurn then
				local idle = t - s.lastInput - CardInspect.AutoTurnDelay
				if idle > 0 then
					s.yaw += dt * CardInspect.AutoTurnSpeed * math.min(1, idle)
				end
			end
		end
		s.pitch += (s.pitchTarget - s.pitch) * math.min(1, dt * 8)
		s.zoom += (s.zoomTarget - s.zoom) * math.min(1, dt * 8)

		-- Secret: the light runs through the rainbow
		if secret then
			local col = rainbowAt(t * 0.12)
			for _, r in ipairs(glowRings) do
				r.BackgroundColor3 = col
			end
			if s.rim then
				s.rim.Color = col
			end
			if s.pill then
				s.pill.BackgroundColor3 = col
			end
			bigName.TextColor3 = col
		end

		if s.floatCard then
			s.floatCard.Position = UDim2.new(0.5, 0, 0.5, math.sin(t * 1.6) * 8)
			s.floatCard.Rotation = math.sin(t * 0.9) * 3
			return
		end
		if not s.model then
			return
		end

		-- the camera: framed on the model, tilted by pitch, pulled back by zoom
		local size = view.AbsoluteSize
		local aspect = (size.Y > 0) and (size.X / size.Y) or 1
		local R = math.max(s.h * 0.6, s.wide * 0.72, s.plinthD * 0.5)
		local dist = R / math.tan(math.rad(cam.FieldOfView / 2)) * 1.12
		if aspect < 1 then
			dist /= math.max(aspect, 0.45)
		end
		dist *= s.zoom
		local look = Vector3.new(0, s.h * 0.44, 0)
		local p = math.rad(s.pitch)
		cam.CFrame = CFrame.lookAt(look + Vector3.new(0, math.sin(p) * dist, -math.cos(p) * dist), look)

		-- the entrance (springs up out of the plinth with a spin) and the exit (sinks back into it)
		local scale, spin = 1, 0
		if s.closing then
			local a = math.clamp((t - s.closeT) / 0.25, 0, 1)
			scale = 1 - a * a * 0.85
			sizeDone = false
		else
			local a = math.clamp((t - 0.05) / 0.62, 0, 1)
			local c1, c3k = 1.70158, 2.70158
			local back = 1 + c3k * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
			scale = 0.12 + 0.88 * back
			spin = -((1 - a) ^ 3) * math.pi * 1.1
		end
		local bob = s.rig and 0 or math.sin(t * 1.4 + s.phase) * 0.015 * s.h
		local rootCf = CFrame.new(0, bob, 0) * CFrame.Angles(0, s.yaw + spin, 0)

		-- the pose: a calm idle, with a move laid over it
		local bones = nil
		if s.rig then
			local pose = idlePose(t, s.phase, s.rig)
			local a = s.anim
			if a then
				local tt = t - a.t0
				if tt >= a.hold then
					s.anim = nil
				else
					local mp = s.Moves.sample(a.move, tt)
					local w = math.clamp(math.min(1, tt / 0.12, (a.hold - tt) / 0.28), 0, 1)
					pose = s.Moves.blend(pose, mp, w)
				end
			end
			pose = table.clone(pose)
			pose.leadSide = s.leadSide
			local ok, solved = pcall(Rig.solve, s.rig, pose)
			if ok and solved then
				bones = {}
				for name, tf in pairs(solved) do
					local m, tt = tf.m, tf.t
					bones[name] = CFrame.new(tt[1], tt[2], tt[3], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9])
				end
			end
		end
		local resize = not sizeDone or scale ~= 1
		for _, e in ipairs(s.parts) do
			local o = e.offset
			if bones then
				local b = bones[e.bone]
				if b then
					o = b * o
				end
			end
			e.part.CFrame = rootCf * CFrame.new(o.Position * scale) * o.Rotation
			if resize then
				e.part.Size = e.size * scale
			end
		end
		sizeDone = scale == 1
	end)
	return s
end

return CardInspect

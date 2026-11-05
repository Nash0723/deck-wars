-- The card reveal after you slash a pack open (PackOpen.luau hands over its screen): the card
-- waits face down in the pack's scene until you tap it, then flips, and only then does its rarity
-- show (burst, colours, sound). Then the stat card. For 10 packs, the card fan: every card face
-- down, tap each one (or Reveal all). Both can offer "Watch the Brawl" (the Pack Brawl fight of
-- the best card, played after the reveal). UI only, animated with TweenService.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent:WaitForChild("Kit"))
local PackArt = require(script.Parent:WaitForChild("PackArt"))
local PackOpen = require(script.Parent:WaitForChild("PackOpen"))
local Packs = require(script.Parent:WaitForChild("Packs"))
local DeckWars = ReplicatedStorage:WaitForChild("DeckWars")
local CardData = require(DeckWars:WaitForChild("CardData"))
local CreatureBuilder = require(DeckWars:WaitForChild("CreatureBuilder"))
local Juice = require(DeckWars:WaitForChild("Juice"))

-- How big each tier's moment is (1 Common .. 6 Secret).
local RANK = { Common = 1, Rare = 2, Epic = 3, Mythic = 4, Legendary = 5, Secret = 6 }

local rgb, make = Kit.rgb, Kit.make
local WHITE, INK = rgb(255, 255, 255), rgb(30, 25, 40)
local TITLE = Enum.Font.FredokaOne
local BODY = Enum.Font.GothamMedium

local Reveal = {}

local function tween(inst, time, goals, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end

local function corner(p, r)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end

local function label(parent, text, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = TITLE,
		TextColor3 = INK,
		Size = UDim2.fromScale(1, 1),
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function rainbowGradient(parent)
	return make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 80, 80)),
			ColorSequenceKeypoint.new(0.33, rgb(255, 230, 80)),
			ColorSequenceKeypoint.new(0.66, rgb(80, 220, 255)),
			ColorSequenceKeypoint.new(1, rgb(220, 90, 255)),
		}),
	}, parent)
end

local function newGui(name)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	return make("ScreenGui", { Name = name, IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
end

-- A creature (or building) turning slowly inside the card art.
local function addArt(art, def)
	if not CreatureBuilder.has(def.id) then
		label(art, def.type == "Spell" and "★" or "?", { TextColor3 = Kit.TierColor[def.rarity] or WHITE, Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.2, 0.1) })
		return nil
	end
	local model = CreatureBuilder.build(def.id)
	local vp = make("ViewportFrame", {
		Name = "ArtView",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = rgb(150, 150, 165),
		LightColor = rgb(255, 244, 228),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
	}, art)
	model.Parent = vp
	local info = CreatureBuilder.info(def.id) or { height = 2.5, width = 2.5, depth = 2.5 }
	local h = math.max(info.height, 0.5)
	local wide = math.max(info.width, info.depth)
	local look = Vector3.new(0, h * 0.48, 0)
	local dist = math.max(h * 2.3, wide * 1.35) + 0.8
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(look + Vector3.new(math.sin(-0.5) * dist, dist * 0.22, -math.cos(-0.5) * dist), look)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return { model = model, look = look, dist = dist, cam = cam }
end

-- The card face. Returns the frame and a function that animates it (shine, rainbow border).
function Reveal.cardFace(parent, cardId, stamp)
	local def = CardData.get(cardId)
	local tier = def.rarity
	local famColor = Kit.FamilyColor[def.family] or Kit.FamilyColor.Any
	local tierColor = Kit.TierColor[tier] or WHITE
	local card = make("Frame", { Name = "Front", Size = UDim2.fromScale(1, 1), BackgroundColor3 = famColor:Lerp(WHITE, 0.55) }, parent)
	corner(card, 16)
	local stroke = make("UIStroke", { Thickness = 7, Color = tierColor }, card)
	local rainbow = tier == "Secret" and rainbowGradient(stroke) or nil
	-- cost
	local cost = make("Frame", { Size = UDim2.fromScale(0.24, 0.17), Position = UDim2.fromScale(-0.05, -0.04), BackgroundColor3 = rgb(40, 90, 200), ZIndex = 3 }, card)
	corner(cost, 100)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, cost)
	make("UIStroke", { Thickness = 3, Color = rgb(20, 40, 110) }, cost)
	label(cost, tostring(def.cost), { TextColor3 = WHITE, ZIndex = 3 })
	label(card, def.name, { Size = UDim2.new(0.72, 0, 0.1, 0), Position = UDim2.fromScale(0.23, 0.03), TextXAlignment = Enum.TextXAlignment.Left })
	-- art
	local art = make("Frame", { Name = "Art", Size = UDim2.fromScale(0.88, 0.4), Position = UDim2.fromScale(0.06, 0.15), BackgroundColor3 = WHITE, ClipsDescendants = true }, card)
	corner(art, 10)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(famColor:Lerp(WHITE, 0.45), famColor:Lerp(rgb(0, 0, 0), 0.35)) }, art)
	local spinner = addArt(art, def)
	label(card, def.type .. (def.family ~= "Any" and (" · " .. def.family) or ""), { Size = UDim2.new(0.9, 0, 0.055, 0), Position = UDim2.fromScale(0.05, 0.565), Font = BODY, TextColor3 = rgb(60, 50, 70) })
	local box = make("Frame", { Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.625), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25 }, card)
	corner(box, 8)
	label(box, def.text ~= "" and def.text or "Just a good fighter.", { Font = BODY, TextWrapped = true, Size = UDim2.fromScale(0.94, 0.9), Position = UDim2.fromScale(0.03, 0.05) })
	if def.atk ~= nil then
		label(card, def.type == "Building" and ("❤ " .. def.hp) or ("⚔ " .. def.atk .. "    ❤ " .. def.hp), { Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.835) })
	end
	-- rarity banner
	local banner = make("Frame", { Name = "Rarity", Size = UDim2.fromScale(1, 0.085), Position = UDim2.fromScale(0, 0.915), BackgroundColor3 = tierColor, ZIndex = 2 }, card)
	corner(banner, 12)
	if rainbow then
		rainbowGradient(banner)
	end
	label(banner, string.upper(tier), { TextColor3 = (tier == "Common" or tier == "Legendary" or tier == "Secret") and INK or WHITE, Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1), ZIndex = 2 })
	-- NEW stamp or +1
	local stampLabel
	if stamp then
		stampLabel = label(card, stamp, {
			Name = "Stamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.42, 0.11),
			Position = UDim2.fromScale(0.86, 0.12),
			Rotation = 14,
			TextColor3 = stamp == "NEW" and rgb(255, 70, 90) or rgb(90, 200, 120),
			ZIndex = 6,
			TextTransparency = 1,
		})
		make("UIStroke", { Thickness = 3, Color = WHITE }, stampLabel)
	end
	-- shine sweep for Epic and up
	local shine
	if (Kit.TierGrade[tier] and tier ~= "Common" and tier ~= "Rare") then
		local sf = make("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 5 }, card)
		corner(sf, 16)
		shine = make("UIGradient", {
			Rotation = 25,
			Offset = Vector2.new(-1.2, 0),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, sf)
	end
	local t = 0
	local function animate(dt)
		t += dt
		if spinner then
			local yaw = -0.5 + math.sin(t * 0.8) * 0.5
			spinner.cam.CFrame = CFrame.lookAt(spinner.look + Vector3.new(math.sin(yaw) * spinner.dist, spinner.dist * 0.22, -math.cos(yaw) * spinner.dist), spinner.look)
		end
		if shine then
			shine.Offset = Vector2.new(-1.2 + ((t * 0.6) % 2.4), 0)
		end
		if rainbow then
			rainbow.Rotation = (t * 120) % 360
		end
		if tier == "Legendary" then
			stroke.Color = tierColor:Lerp(WHITE, 0.35 + 0.35 * math.sin(t * 6))
		end
	end
	return card, animate, stampLabel
end

-- The stat card beside the revealed card: name, rarity / family / type, attack, health and cost
-- bars that fill up, keywords with what they do, the ability, and NEW or how many you own.
-- Returns the panel and fill(instant): animates the bars (or sets them at once).
local STAT_MAX = 10
local function statCard(parent, def, opts)
	local tier = def.rarity
	local tierColor = Kit.TierColor[tier] or WHITE
	local famColor = Kit.FamilyColor[def.family] or Kit.FamilyColor.Any
	local panel = make("Frame", { Name = "StatCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1.4, 0.5), Size = UDim2.fromOffset(330, 420), BackgroundColor3 = rgb(16, 12, 30), BackgroundTransparency = 0.08, ZIndex = 20 }, parent)
	corner(panel, 18)
	local stroke = make("UIStroke", { Thickness = 3, Color = tierColor, Transparency = 0.1 }, panel)
	if tier == "Secret" then
		local g = rainbowGradient(stroke)
		Juice.onFrame(panel, function(t)
			g.Rotation = (t * 120) % 360
		end)
	end
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 255, 255), rgb(170, 165, 190)) }, panel)
	local y = 14
	local function text(name, str, size, h, props)
		local l = label(panel, str, { Name = name, Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, h), TextScaled = false, TextSize = size, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = WHITE, ZIndex = 21 })
		for k, v in pairs(props or {}) do
			l[k] = v
		end
		y += h
		return l
	end
	text("CardName", def.name, 28, 36, { TextScaled = true })
	-- pills: rarity, family, type
	local pills = make("Frame", { Name = "Pills", Position = UDim2.fromOffset(18, y + 2), Size = UDim2.new(1, -36, 0, 24), BackgroundTransparency = 1, ZIndex = 21 }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, pills)
	local function pill(str, bgc, fg)
		local p = label(pills, str, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = bgc, TextScaled = false, TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = fg, ZIndex = 22 })
		corner(p, 12)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, p)
		return p
	end
	local dark = (tier == "Common" or tier == "Legendary" or tier == "Secret")
	local rp = pill(string.upper(tier), tierColor, dark and INK or WHITE)
	if tier == "Secret" then
		rainbowGradient(rp)
	end
	pill(def.family == "Any" and "Shared" or def.family, famColor:Lerp(rgb(20, 16, 34), 0.15), INK)
	pill(def.type, rgb(60, 54, 90), WHITE)
	y += 32
	if def.type == "Creature" and def.family ~= "Any" and CardData.Terrains[def.family] then
		text("Terrain", "+1 attack on " .. CardData.Terrains[def.family], 13, 20, { TextColor3 = famColor:Lerp(WHITE, 0.35), Font = BODY })
	end
	y += 6
	-- stat bars
	local bars = {}
	local function bar(name, icon, value, color)
		local row = make("Frame", { Name = name, Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, 26), BackgroundTransparency = 1, ZIndex = 21 }, panel)
		label(row, icon .. " " .. string.upper(name), { Size = UDim2.fromOffset(96, 26), TextScaled = false, TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = rgb(210, 205, 230), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
		local back = make("Frame", { Name = "Bar", Position = UDim2.fromOffset(100, 6), Size = UDim2.new(1, -146, 0, 14), BackgroundColor3 = rgb(44, 38, 66), ZIndex = 22 }, row)
		corner(back, 7)
		local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, ZIndex = 23 }, back)
		corner(fill, 7)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, 0.35), color) }, fill)
		local num = label(row, "0", { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(40, 26), TextScaled = false, TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22 })
		table.insert(bars, { fill = fill, num = num, value = value, color = color })
		y += 30
	end
	if def.type == "Creature" and def.atk then
		bar("Attack", "⚔", def.atk, rgb(255, 112, 80))
	end
	if def.hp and def.type ~= "Spell" then
		bar("Health", "❤", def.hp, rgb(80, 214, 120))
	end
	bar("Cost", "⚡", def.cost, rgb(84, 170, 255))
	y += 4
	-- keywords, each with what it does
	local kws = {}
	for _, k in ipairs(CardData.Keywords) do
		if def.keywords and def.keywords[k] then
			table.insert(kws, k)
		end
	end
	for i, k in ipairs(kws) do
		if i > 3 then
			break
		end
		text("Keyword_" .. k, k .. ": " .. (CardData.KeywordText[k] or ""), 13, 34, { Font = BODY, RichText = false, TextColor3 = rgb(255, 226, 150) })
	end
	if def.type == "Building" then
		text("BuildingNote", "Buildings never move or attack. They help from where they stand.", 13, 34, { Font = BODY, TextColor3 = rgb(200, 196, 220) })
	end
	-- ability
	local boxH = math.max(54, 420 - y - 50)
	local box = make("Frame", { Name = "Ability", Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, boxH), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.9, ZIndex = 21 }, panel)
	corner(box, 10)
	label(box, def.text ~= "" and def.text or "Just a good fighter.", { Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 6), TextScaled = true, Font = BODY, TextColor3 = WHITE, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 22 })
	-- footer: NEW or how many you own now
	local own = opts.isNew and "NEW CARD!" or ("You own " .. tostring(opts.dupes or 2) .. " of these")
	local foot = label(panel, own, { Name = "Owned", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -36, 0, 28), TextScaled = false, TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = opts.isNew and rgb(255, 92, 120) or rgb(120, 220, 150), ZIndex = 22 })
	local function fill(instant)
		for i, b in ipairs(bars) do
			local k = math.clamp(b.value / STAT_MAX, 0.04, 1)
			if instant then
				b.fill.Size = UDim2.fromScale(k, 1)
				b.num.Text = tostring(b.value)
			else
				task.delay((i - 1) * 0.16, function()
					if not b.fill.Parent then
						return
					end
					tween(b.fill, 0.45, { Size = UDim2.fromScale(k, 1) }, Enum.EasingStyle.Quart)
					local t0 = Juice.clock()
					local shown = -1
					Juice.onFrame(b.num, function(t)
						local f = math.clamp((t - t0) / 0.45, 0, 1)
						local v = math.floor(b.value * f + 0.5)
						if v ~= shown then
							shown = v
							b.num.Text = tostring(v)
							if v > 0 then
								Juice.sound("tick", 1 + v * 0.06, 0.25)
							end
						end
					end)
					Juice.pop(b.num, 1.4, 0.4)
				end)
			end
		end
		if not instant then
			task.delay(#bars * 0.16 + 0.35, function()
				if foot.Parent then
					Juice.pop(foot, 1.5, 0.5)
					if opts.isNew then
						Juice.sound("glass", 1.2, 0.4)
					end
				end
			end)
		end
	end
	return panel, fill
end

-- Fades everything under `root` out (frames, text, strokes, images) over `time` seconds.
local function fadeAll(root, time)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then
			if d.BackgroundTransparency < 1 then
				tween(d, time, { BackgroundTransparency = 1 })
			end
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				tween(d, time, { TextTransparency = 1 })
			elseif d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("ViewportFrame") then
				tween(d, time, { ImageTransparency = 1 })
			end
		elseif d:IsA("UIStroke") then
			tween(d, time, { Transparency = 1 })
		end
	end
end
Reveal.fadeAll = fadeAll

-- The screen to reveal on: the one PackOpen handed over, or a fresh one (tests, previews).
local function takeOver(opts, count)
	local h = opts.handoff
	if not h then
		local pack = opts.pack
		local gui, scene, stage, stageScale = PackOpen.newScreen(pack, "PackReveal")
		local cards = {}
		for i = 1, count do
			local holder = count > 1 and PackOpen.cardHolder(stage, PackOpen.FanW, PackOpen.FanH) or PackOpen.cardHolder(stage, PackOpen.CardW, PackOpen.CardH)
			holder.CardScale.Scale = count > 1 and 1 or 0.9
			cards[i] = holder
		end
		h = { gui = gui, scene = scene, stage = stage, stageScale = stageScale, cards = cards, pack = pack, count = count }
	end
	h.gui.Name = count > 1 and "PackBrawlFan" or "PackBrawlReveal"
	return h
end

-- The rarity moment, when a card turns face up: everything here is in the card's colours.
local function rarityBurst(gui, stage, holder, tier, big)
	local color = Kit.TierColor[tier] or WHITE
	local rank = RANK[tier] or 1
	local ring = make("Frame", { Name = "Burst", AnchorPoint = Vector2.new(0.5, 0.5), Position = holder.Position, Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, ZIndex = 15 }, stage)
	corner(ring, 1000)
	local st = make("UIStroke", { Thickness = big and 14 or 8, Color = color, Transparency = 0.1 }, ring)
	if tier == "Secret" then
		rainbowGradient(st)
	end
	local size = (big and 520 or 260) + rank * (big and 40 or 20)
	tween(ring, big and 0.6 or 0.45, { Size = UDim2.fromOffset(size, size) }, Enum.EasingStyle.Quad)
	tween(st, big and 0.6 or 0.45, { Transparency = 1, Thickness = 2 }, Enum.EasingStyle.Quad).Completed:Connect(function()
		ring:Destroy()
	end)
	local p = holder.AbsolutePosition + holder.AbsoluteSize / 2
	local sz = gui.AbsoluteSize
	local sx, sy = 0.5, 0.5
	if sz.X > 0 and sz.Y > 0 and p.X > 0 then
		sx, sy = p.X / sz.X, p.Y / sz.Y
	end
	Juice.stars(gui, sx, sy, (big and 8 or 4) + rank * (big and 3 or 2), { text = "★", color = tier ~= "Secret" and color:Lerp(WHITE, 0.3) or nil, speed = big and (1 + rank * 0.15) or 0.7, size = big and (18 + rank * 2) or 16 })
	if rank >= 3 and big then
		Juice.flash(gui, color, 0.35, 0.55)
	end
	if rank >= 5 then
		Juice.confetti(gui, sx, sy, (big and 30 or 14) + (rank - 5) * 25, { colors = tier == "Secret" and { rgb(255, 80, 80), rgb(255, 230, 80), rgb(80, 220, 255), rgb(220, 90, 255), WHITE } or { color, color:Lerp(WHITE, 0.5), WHITE } })
	end
	if big or rank >= 3 then
		Juice.sound("sting_" .. tier, 1, big and 0.6 or 0.4)
	else
		Juice.sound("pop", 0.85 + rank * 0.08, 0.45)
	end
	if tier == "Secret" then
		Juice.sound("choir", 1, big and 0.6 or 0.35)
	end
end

-- A gold button at the bottom of the screen.
local function bottomButton(gui, name, text, x, colorBg, colorText)
	local b = make("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, x, 1, -26), Size = UDim2.fromOffset(220, 52), BackgroundColor3 = colorBg, Text = text, Font = TITLE, TextSize = 22, TextColor3 = colorText or INK, AutoButtonColor = true, ZIndex = 45 }, gui)
	corner(b, 14)
	make("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	Juice.button(b)
	return b
end

-- Single card reveal, after the slash. The card waits face down in the pack's scene:
--   1. tap it (or wait): it lifts and shudders (the same for every rarity), then flips,
--   2. face up, the rarity shows: a burst, the scene washes to the card's colour, its sound,
--   3. the card slides left and the stat card slides in: bars fill up, keywords, ability.
-- Tapping during 2-3 jumps to the finished stat card; tap again to continue.
-- opts = { id, isNew, dupes, pack, handoff (from PackOpen), quick, onDone, onWatch }
Reveal.AutoFlip = 6 -- seconds before a card nobody taps flips by itself
function Reveal.single(opts)
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local def = CardData.get(opts.id)
	local tier = def.rarity
	local color = Kit.TierColor[tier] or WHITE
	local rank = RANK[tier] or 1
	local h = takeOver(opts, 1)
	local gui, scene, stage = h.gui, h.scene, h.stage
	local holder = h.cards[1]
	local scale = holder:FindFirstChild("CardScale")
	local back = holder:FindFirstChild("Back")
	local CARD_W, CARD_H = PackOpen.CardW, PackOpen.CardH
	local stamp = opts.isNew and "NEW" or ("+1" .. ((opts.dupes and opts.dupes > 1) and (" (x" .. opts.dupes .. ")") or ""))
	local front, animate, stampLabel = Reveal.cardFace(holder, opts.id, stamp)
	front.Visible = false
	local stats, fillStats = statCard(stage, def, opts)
	stats.Visible = false -- (it waits off to the side; hidden so wide screens can't see it early)

	local tweens = {}
	local function tw(inst, time, goals, style, dir)
		local t = tween(inst, time, goals, style, dir)
		table.insert(tweens, t)
		return t
	end

	-- a soft glow behind the face-down card (the pack's colour, not the card's)
	local packMain = Packs.color(scene.pack, "accent")
	local aura = make("Frame", { Name = "CardAura", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 26, 1, 26), BackgroundTransparency = 1, ZIndex = 0 }, holder)
	corner(aura, 26)
	local auraStroke = make("UIStroke", { Thickness = 10, Color = packMain:Lerp(WHITE, 0.4), Transparency = 0.5 }, aura)
	local backShine = Juice.shine(back, 2.4, UDim.new(0, 16))

	local hint = label(gui, "TAP THE CARD TO FLIP IT", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(420, 28), TextColor3 = WHITE, Font = Enum.Font.GothamBlack, TextTransparency = 1, ZIndex = 44 })
	make("UIStroke", { Thickness = 2, Color = INK }, hint)
	tween(hint, 0.3, { TextTransparency = 0 })

	local state = "waiting" -- waiting, flipping, shown, ready, closing
	local skipped = false
	local word
	local watch

	local function showWord(instant)
		if word then
			return
		end
		word = label(stage, string.upper(tier), { Name = "RarityWord", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.045), Size = UDim2.fromOffset(420, 48), Font = Enum.Font.GothamBlack, TextColor3 = tier == "Secret" and WHITE or color, ZIndex = 29 })
		make("UIStroke", { Thickness = 4, Color = INK }, word)
		if tier == "Secret" then
			rainbowGradient(word)
		end
		if not instant then
			Juice.pop(word, 1.8, 0.6)
		end
	end

	local function setReady()
		if state == "closing" then
			return
		end
		state = "ready"
		hint.Text = "Tap to continue"
		hint.Font = BODY
		tween(hint, 0.3, { TextTransparency = 0.15 })
		if opts.onWatch and not watch then
			watch = bottomButton(gui, "WatchBrawl", "▶  Watch the Brawl", 0, rgb(255, 194, 26))
			watch.Position = UDim2.new(1, -140, 1, -24)
			Juice.popIn(watch, 0)
			watch.Activated:Connect(function()
				if state ~= "ready" then
					return
				end
				state = "closing"
				fadeAll(gui, 0.35)
				task.delay(0.38, function()
					gui:Destroy()
					opts.onWatch()
				end)
			end)
		end
	end

	-- 3. the stat card
	local statsShown = false
	local function showStats(instant)
		if statsShown then
			return
		end
		statsShown = true
		stats.Visible = true
		tween(hint, 0.15, { TextTransparency = 1 })
		if instant then
			holder.Position = UDim2.fromScale(0.29, 0.53)
			scale.Scale = 1
			stats.Position = UDim2.fromScale(0.715, 0.53)
			fillStats(true)
			task.delay(0.2, setReady)
		else
			Juice.sound("whoosh", 1.1, 0.45)
			tw(holder, 0.45, { Position = UDim2.fromScale(0.29, 0.53), Rotation = 0 }, Enum.EasingStyle.Back)
			tw(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			tw(stats, 0.5, { Position = UDim2.fromScale(0.715, 0.53) }, Enum.EasingStyle.Back)
			task.delay(0.3, function()
				if stats.Parent and not skipped then
					fillStats(false)
				end
			end)
			task.delay(1.1, function()
				if not skipped then
					setReady()
				end
			end)
		end
	end

	local function faceUp(instant)
		back.Visible = false
		front.Visible = true
		aura.Visible = false
		backShine.Visible = false
		holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
		scene.tint(color, 0.2 + rank * 0.05, instant and 0.01 or 0.6)
		if stampLabel then
			stampLabel.TextSize = 80
			stampLabel.TextTransparency = instant and 0 or stampLabel.TextTransparency
		end
		showWord(instant)
	end

	-- 1 + 2. the lift, the shudder and the flip
	local function flip()
		if state ~= "waiting" then
			return
		end
		state = "flipping"
		tween(hint, 0.15, { TextTransparency = 1 })
		Juice.sound("charge", 1.25, 0.45)
		tw(scale, 0.3, { Scale = 1.02 }, Enum.EasingStyle.Quad)
		tw(auraStroke, 0.3, { Transparency = 0.1, Thickness = 16 })
		Juice.shake(holder, 5, 0.3)
		task.delay(opts.quick and 0.15 or 0.32, function()
			if skipped then
				return
			end
			local squeeze = tw(holder, 0.16, { Size = UDim2.fromOffset(0, CARD_H) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			squeeze.Completed:Connect(function()
				if skipped then
					return
				end
				state = "shown"
				faceUp(false)
				holder.Size = UDim2.fromOffset(0, CARD_H)
				local open = tw(holder, 0.28, { Size = UDim2.fromOffset(CARD_W, CARD_H) }, Enum.EasingStyle.Back)
				rarityBurst(gui, stage, holder, tier, true)
				Juice.shake(stage, 4 + rank * 2, 0.25)
				open.Completed:Connect(function()
					if stampLabel and not skipped then
						tween(stampLabel, 0.18, { TextTransparency = 0 }, Enum.EasingStyle.Back)
					end
				end)
				task.delay(opts.quick and 0.5 or 0.85, function()
					if not skipped then
						showStats(false)
					end
				end)
			end)
		end)
	end
	Reveal.flipHook = flip -- (for tests)

	-- jump to the finished stat card
	local function skipToEnd()
		if skipped or state == "ready" or state == "closing" then
			return
		end
		skipped = true
		for _, t in ipairs(tweens) do
			t:Cancel()
		end
		state = "shown"
		holder.Rotation = 0
		faceUp(true)
		showStats(true)
	end
	Reveal.skipHook = skipToEnd -- (for tests)

	local t0 = 0
	local floatT = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		animate(dt)
		t0 += dt
		if state == "waiting" then
			-- the card hovers, waiting for you
			holder.Position = UDim2.new(0.5, 0, 0.5, math.sin(t0 * 2) * 7)
			holder.Rotation = math.sin(t0 * 1.3) * 2
			auraStroke.Transparency = 0.35 + 0.25 * math.sin(t0 * 3)
			if t0 >= Reveal.AutoFlip then
				flip()
			end
		elseif state == "ready" then
			-- the card hovers and tilts a little while you look at it
			floatT += dt
			holder.Position = UDim2.new(0.29, 0, 0.53, math.sin(floatT * 1.8) * 6)
			holder.Rotation = math.sin(floatT * 1.1) * 1.5
		end
	end)

	local function close()
		if state ~= "ready" then
			return
		end
		state = "closing"
		Juice.sound("whoosh", 1.2, 0.4)
		if word then
			tween(word, 0.25, { TextTransparency = 1 })
		end
		if watch then
			watch.Visible = false
		end
		-- the card flies to the collection corner, the stat card slides away, back to the game
		tween(holder, 0.45, { Position = UDim2.fromScale(-0.2, -0.1), Rotation = -12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(scale, 0.45, { Scale = 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(stats, 0.4, { Position = UDim2.fromScale(1.5, 0.53) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(hint, 0.3, { TextTransparency = 1 })
		task.delay(0.25, function()
			fadeAll(scene.root, 0.35)
			scene.setCalm(true)
		end)
		task.delay(0.65, function()
			conn:Disconnect()
			gui:Destroy()
			if opts.onDone then
				opts.onDone()
			end
		end)
	end

	local tap = make("TextButton", { Name = "Tap", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 40 }, gui)
	local function pressed()
		if state == "waiting" then
			flip()
		elseif state == "flipping" or state == "shown" then
			skipToEnd()
		elseif state == "ready" then
			close()
		end
	end
	tap.Activated:Connect(pressed)
	local keyConn
	keyConn = UserInputService.InputBegan:Connect(function(input)
		if not gui.Parent then
			keyConn:Disconnect()
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA then
			pressed()
		end
	end)
	return gui
end

-- The 10-pack fan: the stack from the pack deals out into two rows, all face down. Tap a card to
-- flip it (its rarity shows as it turns), or Reveal all. When every card is up, the best one gets
-- a BEST PULL ribbon (and Watch the Brawl, when offered).
-- opts = { cards = { id, ... }, best = index, isNew = { bool, ... }, pack, handoff, onDone, onWatch }
function Reveal.fan(opts)
	local RunService = game:GetService("RunService")
	local h = takeOver(opts, #opts.cards)
	local gui, scene, stage = h.gui, h.scene, h.stage
	local area = make("Frame", { Name = "Cards", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(5 * 150, 2 * 215), BackgroundTransparency = 1, ZIndex = 18 }, stage)
	local animators = {}
	local slots = {}
	local flipped = 0
	local doneButton, revealAll, watch
	local closing = false

	local function allUp()
		local best = slots[opts.best]
		if best then
			local ribbon = label(best.holder, "BEST PULL", { Name = "BestRibbon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -14), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 0, BackgroundColor3 = rgb(255, 214, 102), TextScaled = false, TextSize = 15, Font = Enum.Font.GothamBlack, ZIndex = 30 })
			corner(ribbon, 12)
			make("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ribbon)
			Juice.popIn(ribbon, 0.1)
			Juice.pop(best.holder, 1.18, 0.6)
			local tier = CardData.get(best.id).rarity
			scene.tint(Kit.TierColor[tier] or WHITE, 0.25, 0.6)
		end
		if doneButton then
			doneButton.Text = "Done"
			doneButton.BackgroundColor3 = rgb(255, 194, 26)
			doneButton.TextColor3 = INK
		end
		if revealAll then
			revealAll.Visible = false
		end
		if opts.onWatch and not watch then
			watch = bottomButton(gui, "WatchBrawl", "▶  Watch the Brawl", -120, rgb(110, 90, 200), WHITE)
			Juice.popIn(watch, 0.2)
			watch.Activated:Connect(function()
				if closing then
					return
				end
				closing = true
				fadeAll(gui, 0.35)
				task.delay(0.38, function()
					gui:Destroy()
					opts.onWatch()
				end)
			end)
			doneButton.Position = UDim2.new(0.5, 120, 1, -26)
		end
	end

	local function flip(slot, quiet)
		if slot.open then
			return
		end
		slot.open = true
		flipped += 1
		local squeeze = tween(slot.holder, 0.14, { Size = UDim2.fromOffset(0, PackOpen.FanH) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		squeeze.Completed:Connect(function()
			slot.back.Visible = false
			slot.front.Visible = true
			tween(slot.holder, 0.18, { Size = UDim2.fromOffset(PackOpen.FanW, PackOpen.FanH) }, Enum.EasingStyle.Back)
			local tier = CardData.get(slot.id).rarity
			if not quiet or (RANK[tier] or 1) >= 3 then
				rarityBurst(gui, stage, slot.holder, tier, false)
			end
			Juice.pop(slot.holder, 1.12, 0.45)
			if slot.stamp then
				tween(slot.stamp, 0.18, { TextTransparency = 0 })
			end
		end)
		if flipped >= #slots then
			task.delay(0.45, allUp)
		end
	end

	for i, id in ipairs(opts.cards) do
		local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
		local holder = h.cards[i] or PackOpen.cardHolder(stage, PackOpen.FanW, PackOpen.FanH)
		local back = holder:FindFirstChild("Back")
		local stamp = (opts.isNew and opts.isNew[i]) and "NEW" or "+1"
		local front, animate, stampLabel = Reveal.cardFace(holder, id, stamp)
		front.Visible = false
		if stampLabel then
			stampLabel.TextTransparency = 1
		end
		table.insert(animators, animate)
		local button = make("TextButton", { Name = "Flip", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 28 }, holder)
		local slot = { id = id, holder = holder, back = back, front = front, stamp = stampLabel }
		-- deal the card from the stack to its place (positions are offsets from the stage's centre)
		local x, y = (col - 2) * 150, (row - 0.5) * 215 - 28
		task.delay(0.05 + (i - 1) * 0.06, function()
			if holder.Parent then
				tween(holder, 0.4, { Position = UDim2.new(0.5, x, 0.5, y), Rotation = (col - 2) * 2 }, Enum.EasingStyle.Back)
				tween(holder.CardScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
				Juice.sound("whoosh", 1.3 + i * 0.03, 0.2)
			end
		end)
		button.Activated:Connect(function()
			flip(slot)
		end)
		slots[i] = slot
	end
	area:Destroy() -- (the cards sit on the stage itself)

	local hint = label(gui, "Tap the cards to flip them", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Size = UDim2.fromOffset(400, 24), TextColor3 = rgb(230, 225, 240), Font = BODY, ZIndex = 44 })
	revealAll = bottomButton(gui, "RevealAll", "Reveal all", -120, rgb(255, 194, 26))
	doneButton = bottomButton(gui, "Done", "Skip", 120, rgb(80, 70, 110), WHITE)
	revealAll.Activated:Connect(function()
		local k = 0
		for _, s in ipairs(slots) do
			if not s.open then
				task.delay(k * 0.12, function()
					flip(s, true)
				end)
				k += 1
			end
		end
	end)
	local conn = RunService.RenderStepped:Connect(function(dt)
		for _, a in ipairs(animators) do
			a(dt)
		end
	end)
	doneButton.Activated:Connect(function()
		if closing then
			return
		end
		closing = true
		hint.Visible = false
		for _, s in ipairs(slots) do
			tween(s.holder, 0.4, { Position = s.holder.Position + UDim2.fromOffset(0, 700) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		revealAll.Visible = false
		doneButton.Visible = false
		if watch then
			watch.Visible = false
		end
		task.delay(0.2, function()
			fadeAll(scene.root, 0.35)
			scene.setCalm(true)
		end)
		task.delay(0.6, function()
			conn:Disconnect()
			gui:Destroy()
			if opts.onDone then
				opts.onDone()
			end
		end)
	end)
	return gui
end

return Reveal

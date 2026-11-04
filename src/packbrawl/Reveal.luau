-- The card reveal after a Pack Brawl (pack rip, card flip, stat card), and the card fan for 10-pulls.
-- UI only, animated with TweenService (the brawl clock has stopped by now).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent:WaitForChild("Kit"))
local PackTease = require(script.Parent:WaitForChild("PackTease"))
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

-- The Deck Wars card back.
local function cardBack(parent)
	local back = make("Frame", { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(32, 38, 74) }, parent)
	corner(back, 16)
	make("UIStroke", { Thickness = 6, Color = rgb(242, 230, 201) }, back)
	local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.5), BackgroundTransparency = 1 }, back)
	make("UIStroke", { Thickness = 5, Color = rgb(242, 230, 201) }, ring)
	corner(ring, 200)
	label(back, "DECK\nWARS", { Size = UDim2.fromScale(0.6, 0.25), Position = UDim2.fromScale(0.2, 0.375), TextColor3 = rgb(242, 230, 201) })
	return back
end

-- A creature (or building) turning slowly inside the card art.
local function addArt(art, def)
	if not CreatureBuilder.has(def.id) then
		label(art, def.type == "Spell" and "✦" or "?", { TextColor3 = Kit.TierColor[def.rarity] or WHITE, Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.2, 0.1) })
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

-- Single card reveal, after the Pack Brawl. Starts on a full screen of the tier color (where the
-- wipe left off), then:
--   1. the pack drops in, shakes and RIPS open: the top tears off, light blasts out, shreds fly,
--   2. the card shoots up out of it face down and flips over (rarity word, sparks, confetti),
--   3. the card slides left and the stat card slides in: bars fill up, keywords, ability.
-- Tapping before the end jumps straight to the finished stat card; tap again to continue.
-- opts = { id, isNew, dupes, pack (from Packs.luau, optional), count (1 or 10), onDone }
function Reveal.single(opts)
	local RunService = game:GetService("RunService")
	local def = CardData.get(opts.id)
	local tier = def.rarity
	local color = Kit.TierColor[tier] or WHITE
	local rank = RANK[tier] or 1
	local gui = newGui("PackBrawlReveal")
	local bg = make("Frame", { Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, gui)
	if tier == "Secret" then
		rainbowGradient(bg)
	end
	-- soft rays behind everything
	local rays = make("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, bg)
	for k = 0, 11 do
		local holder = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Rotation = k * 30 }, rays)
		make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(1400, 70), BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0 }, holder)
	end
	tween(bg, 0.5, { BackgroundColor3 = color:Lerp(rgb(10, 8, 20), 0.6) })

	-- everything sits on a 760 x 560 stage that shrinks to fit small screens
	local stage = make("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(760, 560), BackgroundTransparency = 1 }, gui)
	local stageScale = make("UIScale", { Scale = 1 }, stage)
	local function fit()
		local s = gui.AbsoluteSize
		if s.X > 0 and s.Y > 0 then
			stageScale.Scale = math.min(1, s.X / 780, s.Y / 580)
		end
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local tweens = {}
	local function tw(inst, time, goals, style, dir)
		local t = tween(inst, time, goals, style, dir)
		table.insert(tweens, t)
		return t
	end

	-- the card: a holder whose width is squeezed to fake a 3D flip; hidden behind the pack at first
	local CARD_W, CARD_H = 300, 420
	local holder = make("Frame", { Name = "CardHolder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundTransparency = 1, Visible = false, ZIndex = 2 }, stage)
	local scale = make("UIScale", { Scale = 0.62 }, holder)
	local back = cardBack(holder)
	local stamp = opts.isNew and "NEW" or ("+1" .. ((opts.dupes and opts.dupes > 1) and (" (x" .. opts.dupes .. ")") or ""))
	local front, animate, stampLabel = Reveal.cardFace(holder, opts.id, stamp)
	front.Visible = false
	local stats, fillStats = statCard(stage, def, opts)

	-- the pack (the same art as the Pack Tease)
	local pack = PackTease.buildPack(stage, opts.count or 1, opts.pack)
	pack.Position = UDim2.fromScale(0.5, -0.45)
	pack.Rotation = -14
	local glow = make("Frame", { Name = "PackGlow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromOffset(268, 368), BackgroundTransparency = 1, ZIndex = 1 }, stage)
	corner(glow, 26)
	local glowStroke = make("UIStroke", { Thickness = 16, Color = color, Transparency = 1 }, glow)

	local word, title
	local stage2Done, statsShown, ready, done, skipped = false, false, false, false, false
	local hint = label(gui, "Tap to continue", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(300, 26), TextColor3 = rgb(230, 225, 240), Font = BODY, TextTransparency = 1, ZIndex = 30 })

	local function showWord(instant)
		if word then
			return
		end
		word = label(stage, string.upper(tier), { Name = "RarityWord", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.055), Size = UDim2.fromOffset(500, 60), Font = Enum.Font.GothamBlack, TextColor3 = tier == "Secret" and WHITE or color, ZIndex = 29 })
		make("UIStroke", { Thickness = 4, Color = INK }, word)
		if tier == "Secret" then
			rainbowGradient(word)
		end
		if not instant then
			Juice.pop(word, 2.2, 0.6)
		end
	end

	-- 3. the stat card
	local function showStats(instant)
		if statsShown then
			return
		end
		statsShown = true
		if instant then
			holder.Position = UDim2.fromScale(0.29, 0.53)
			stats.Position = UDim2.fromScale(0.715, 0.53)
		else
			Juice.sound("whoosh", 1.1, 0.45)
			tw(holder, 0.45, { Position = UDim2.fromScale(0.29, 0.53), Rotation = 0 }, Enum.EasingStyle.Back)
			tw(stats, 0.5, { Position = UDim2.fromScale(0.715, 0.53) }, Enum.EasingStyle.Back)
		end
		if instant then
			fillStats(true)
		else
			task.delay(0.3, function()
				if stats.Parent and not skipped then
					fillStats(false)
				end
			end)
		end
		task.delay(instant and 0.25 or 1.2, function()
			if gui.Parent and not done then
				ready = true
				tween(hint, 0.3, { TextTransparency = 0.2 })
			end
		end)
	end

	-- 2b. the flip
	local function flip(instant)
		if stage2Done then
			return
		end
		stage2Done = true
		if instant then
			back.Visible = false
			front.Visible = true
			holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
			scale.Scale = 1
			if stampLabel then
				stampLabel.TextSize = 80
				stampLabel.TextTransparency = 0
			end
			showWord(true)
			return
		end
		local squeeze = tw(holder, 0.18, { Size = UDim2.fromOffset(0, CARD_H) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		squeeze.Completed:Connect(function()
			if skipped then
				return
			end
			back.Visible = false
			front.Visible = true
			local open = tw(holder, 0.28, { Size = UDim2.fromOffset(CARD_W, CARD_H) }, Enum.EasingStyle.Back)
			Juice.sound("pop", 0.8 + rank * 0.08, 0.6)
			showWord(false)
			Juice.stars(gui, 0.5, 0.5, 6 + rank * 3, { text = "✦", color = tier == "Secret" and nil or color:Lerp(WHITE, 0.3), speed = 1 + rank * 0.15, size = 18 + rank * 2 })
			if rank >= 3 then
				Juice.flash(gui, color, 0.35, 0.55)
			end
			if rank >= 5 then
				-- Legendary and Secret: a shower of confetti in the tier's colors
				Juice.confetti(gui, 0.5, 0.5, 30 + (rank - 5) * 25, { colors = tier == "Secret" and { rgb(255, 80, 80), rgb(255, 230, 80), rgb(80, 220, 255), rgb(220, 90, 255), WHITE } or { color, color:Lerp(WHITE, 0.5), WHITE } })
			end
			open.Completed:Connect(function()
				if stampLabel and not skipped then
					stampLabel.TextSize = 80
					tween(stampLabel, 0.18, { TextTransparency = 0 }, Enum.EasingStyle.Back)
				end
			end)
		end)
	end

	-- 1. the pack drops in, shakes and rips
	local packGone = false
	local function dropPack()
		if packGone then
			return
		end
		packGone = true
		tw(pack, 0.5, { Position = UDim2.fromScale(0.5, 1.6), Rotation = 24 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tw(glowStroke, 0.3, { Transparency = 1 })
		task.delay(0.55, function()
			pack:Destroy()
			glow:Destroy()
		end)
	end
	local steps = {
		{
			0,
			function()
				Juice.sound("whoosh", 0.9, 0.5)
				tw(pack, 0.32, { Position = UDim2.fromScale(0.5, 0.56), Rotation = 0 }, Enum.EasingStyle.Back)
			end,
		},
		{
			0.32,
			function()
				Juice.sound("thud", 0.9, 0.6)
				Juice.shake(stage, 5, 0.18)
				tw(glowStroke, 0.3, { Transparency = 0.35 })
				Juice.shake(pack, 4 + rank, 0.32)
			end,
		},
		{
			0.66,
			function()
				-- RIP: the top tears off, light pours out of the opening
				local top = pack:FindFirstChild("Top")
				if top then
					tw(top, 0.4, { Position = UDim2.new(0.45, 0, -0.75, 0), Rotation = 38, BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
					task.delay(0.4, function()
						top:Destroy()
					end)
				end
				local beam = make("Frame", { Name = "RipLight", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(200, 0), BackgroundColor3 = color:Lerp(WHITE, 0.4), BorderSizePixel = 0, ZIndex = 9 }, pack)
				make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 0) }) }, beam)
				tw(beam, 0.25, { Size = UDim2.fromOffset(230, 520) }, Enum.EasingStyle.Quad)
				Juice.sound("rip", 1, 0.8)
				if rank >= 4 then
					Juice.sound("boom", 1.1 - rank * 0.04, 0.5)
				end
				Juice.flash(gui, color, 0.3, 0.35)
				Juice.shake(stage, 6 + rank * 2, 0.3)
				local main = PackTease.colorsOf(opts.pack)
				Juice.confetti(gui, 0.5, 0.25, 26 + rank * 4, { colors = { main, main:Lerp(WHITE, 0.5), color, WHITE }, speed = 0.9 })
				Juice.stars(gui, 0.5, 0.25, 6 + rank * 2, { text = "✦", color = color:Lerp(WHITE, 0.3), size = 20 })
			end,
		},
		{
			0.82,
			function()
				-- the card shoots up out of the pack, face down, and the pack falls away
				holder.Visible = true
				tw(holder, 0.3, { Position = UDim2.fromScale(0.5, 0.2) }, Enum.EasingStyle.Quad)
				tw(scale, 0.3, { Scale = 0.8 }, Enum.EasingStyle.Quad)
				Juice.sound("whoosh", 1.25, 0.45)
			end,
		},
		{ 1.0, dropPack },
		{
			1.12,
			function()
				tw(holder, 0.32, { Position = UDim2.fromScale(0.5, 0.53) }, Enum.EasingStyle.Back)
				tw(scale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
			end,
		},
		{ 1.44, function()
			flip(false)
		end },
		{ 2.25, function()
			showStats(false)
		end },
	}
	local elapsed, nextStep = 0, 1
	local floatT = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		animate(dt)
		rays.Rotation = (rays.Rotation + dt * 8) % 360
		if not skipped then
			elapsed += dt
			while steps[nextStep] and steps[nextStep][1] <= elapsed do
				local fn = steps[nextStep][2]
				nextStep += 1
				fn()
			end
		end
		if ready then
			-- the card hovers and tilts a little while you look at it
			floatT += dt
			holder.Position = UDim2.new(0.29, 0, 0.53, math.sin(floatT * 1.8) * 6)
			holder.Rotation = math.sin(floatT * 1.1) * 1.5
		end
	end)

	-- jump to the finished stat card
	local function skipToEnd()
		if skipped or statsShown and ready then
			return
		end
		skipped = true
		for _, t in ipairs(tweens) do
			t:Cancel()
		end
		if pack.Parent then
			pack:Destroy()
		end
		if glow.Parent then
			glow:Destroy()
		end
		packGone = true
		holder.Visible = true
		flip(true)
		back.Visible = false
		front.Visible = true
		holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
		holder.Rotation = 0
		scale.Scale = 1
		showWord(true)
		if stampLabel then
			stampLabel.TextSize = 80
			stampLabel.TextTransparency = 0
		end
		if statsShown then
			holder.Position = UDim2.fromScale(0.29, 0.53)
			stats.Position = UDim2.fromScale(0.715, 0.53)
			fillStats(true)
			task.delay(0.25, function()
				if gui.Parent and not done then
					ready = true
					tween(hint, 0.3, { TextTransparency = 0.2 })
				end
			end)
		else
			showStats(true)
		end
	end
	Reveal.skipHook = skipToEnd -- (for tests)

	local tap = make("TextButton", { Name = "Tap", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 40 }, gui)
	tap.Activated:Connect(function()
		if done then
			return
		end
		if not ready then
			skipToEnd()
			return
		end
		done = true
		Juice.sound("whoosh", 1.2, 0.4)
		if word then
			tween(word, 0.25, { TextTransparency = 1 })
		end
		-- the card flies to the collection corner, the stat card slides away, back to the game
		tween(holder, 0.45, { Position = UDim2.fromOffset(-120, -60), Rotation = -12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(scale, 0.45, { Scale = 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(stats, 0.4, { Position = UDim2.fromScale(1.5, 0.53) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(hint, 0.3, { TextTransparency = 1 })
		local fade = tween(bg, 0.5, { BackgroundTransparency = 1 })
		fade.Completed:Connect(function()
			conn:Disconnect()
			gui:Destroy()
			if opts.onDone then
				opts.onDone()
			end
		end)
	end)
	return gui
end

-- The 10-pull fan: every card face-down except the best one; tap to flip, or Reveal all.
-- opts = { cards = { id, ... }, best = index, isNew = { bool, ... }, onDone }
function Reveal.fan(opts)
	local RunService = game:GetService("RunService")
	local gui = newGui("PackBrawlFan")
	local bg = make("Frame", { Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(16, 12, 30), BackgroundTransparency = 0.05, BorderSizePixel = 0 }, gui)
	local area = make("Frame", { Name = "Cards", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(5 * 150, 2 * 215), BackgroundTransparency = 1 }, gui)
	local animators = {}
	local slots = {}
	local flipped = 0
	local doneButton
	local function flip(slot)
		if slot.open then
			return
		end
		slot.open = true
		flipped += 1
		local squeeze = tween(slot.holder, 0.14, { Size = UDim2.fromOffset(0, 200) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		squeeze.Completed:Connect(function()
			slot.back.Visible = false
			slot.front.Visible = true
			tween(slot.holder, 0.18, { Size = UDim2.fromOffset(140, 200) }, Enum.EasingStyle.Back)
			local tier = CardData.get(slot.id).rarity
			local burst = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = Kit.TierColor[tier], BackgroundTransparency = 0.2, ZIndex = 0 }, slot.slot)
			corner(burst, 100)
			tween(burst, 0.35, { Size = UDim2.fromOffset(260, 260), BackgroundTransparency = 1 })
			local rank = RANK[tier] or 1
			Juice.sound("pop", 0.85 + rank * 0.08, 0.45)
			if slot.aura then
				slot.aura.Visible = false
			end
			if rank >= 3 then
				local p = slot.slot.AbsolutePosition + slot.slot.AbsoluteSize / 2
				local sz = gui.AbsoluteSize
				if sz.X > 0 and sz.Y > 0 then
					Juice.stars(gui, p.X / sz.X, p.Y / sz.Y, 4 + rank * 2, { text = "✦", color = Kit.TierColor[tier], size = 16, speed = 0.7 })
				end
				Juice.pop(slot.holder, 1.15, 0.5)
			end
			if slot.stamp then
				tween(slot.stamp, 0.18, { TextTransparency = 0 })
			end
		end)
		if flipped >= #slots and doneButton then
			doneButton.Text = "Done"
		end
	end
	for i, id in ipairs(opts.cards) do
		local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
		local slotFrame = make("Frame", { Name = "Slot" .. i, Size = UDim2.fromOffset(150, 215), Position = UDim2.fromOffset(col * 150, row * 215), BackgroundTransparency = 1 }, area)
		local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(140, 200), BackgroundTransparency = 1, Rotation = (col - 2) * 2 }, slotFrame)
		local back = cardBack(holder)
		local stamp = (opts.isNew and opts.isNew[i]) and "NEW" or "+1"
		local front, animate, stampLabel = Reveal.cardFace(holder, id, stamp)
		front.Visible = false
		table.insert(animators, animate)
		local button = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, holder)
		local slot = { id = id, holder = holder, back = back, front = front, slot = slotFrame, stamp = stampLabel }
		-- face-down Epic and up glow in their tier color (a hint of what is under it)
		local tierOf = CardData.get(id).rarity
		if (RANK[tierOf] or 1) >= 3 and i ~= opts.best then
			local aura = make("Frame", { Name = "Aura", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 10, 1, 10), BackgroundTransparency = 1, ZIndex = 0 }, holder)
			corner(aura, 20)
			local st = make("UIStroke", { Thickness = 6, Color = Kit.TierColor[tierOf], Transparency = 0.3 }, aura)
			local ph = i * 0.7
			Juice.onFrame(aura, function(t)
				st.Transparency = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(t * 4 + ph))
				if tierOf == "Secret" then
					st.Color = Kit.prism(t)
				end
			end)
			slot.aura = aura
		end
		-- deal the card in from the bottom of the screen
		local finalPos = slotFrame.Position
		slotFrame.Position = UDim2.new(0, 2 * 150, 0, 900)
		slotFrame.Rotation = (col - 2) * 12
		task.delay(0.05 + (i - 1) * 0.06, function()
			if slotFrame.Parent then
				tween(slotFrame, 0.4, { Position = finalPos, Rotation = 0 }, Enum.EasingStyle.Back)
				Juice.sound("whoosh", 1.3 + i * 0.03, 0.2)
			end
		end)
		button.Activated:Connect(function()
			flip(slot)
		end)
		slots[i] = slot
	end
	-- the best card was already revealed by the cinematic
	if slots[opts.best] then
		local s = slots[opts.best]
		s.open = true
		flipped += 1
		s.back.Visible = false
		s.front.Visible = true
		if s.stamp then
			s.stamp.TextTransparency = 0
		end
	end
	local revealAll = make("TextButton", { Name = "RevealAll", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, -110, 0.88, 0), Size = UDim2.fromOffset(200, 50), BackgroundColor3 = rgb(255, 194, 26), Text = "Reveal all", Font = TITLE, TextSize = 24, TextColor3 = INK }, gui)
	corner(revealAll, 14)
	doneButton = make("TextButton", { Name = "Done", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 110, 0.88, 0), Size = UDim2.fromOffset(200, 50), BackgroundColor3 = rgb(80, 70, 110), Text = "Skip", Font = TITLE, TextSize = 24, TextColor3 = WHITE }, gui)
	corner(doneButton, 14)
	revealAll.Activated:Connect(function()
		for k, s in ipairs(slots) do
			task.delay((k - 1) * 0.08, function()
				flip(s)
			end)
		end
	end)
	local conn = RunService.RenderStepped:Connect(function(dt)
		for _, a in ipairs(animators) do
			a(dt)
		end
	end)
	local closing = false
	doneButton.Activated:Connect(function()
		if closing then
			return
		end
		closing = true
		local fade = tween(bg, 0.4, { BackgroundTransparency = 1 })
		tween(area, 0.4, { Position = UDim2.fromScale(0.5, 1.3) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		revealAll.Visible = false
		doneButton.Visible = false
		fade.Completed:Connect(function()
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

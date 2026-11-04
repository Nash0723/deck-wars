-- The Pack Tease: the moment before a Pack Brawl, when the pack is in your hands.
--
-- The pack rises into the middle of the screen. Tap it (or press Space / Enter / gamepad A)
-- three times: each tap jolts it, cracks it a little more, and light leaks out of the cracks.
-- The light's color teases how rare the pull is ("EPIC OR BETTER"). It never shows more than
-- the real rarity, and for Mythic and up it stops one step short, so the brawl can still
-- surprise you. After the last tap the pack shakes, then flies off into the Brawl Box ring,
-- where the cinematic picks it up (it lands and rips open).
--
-- No tapping: it opens by itself after a few seconds. "Pack fights: Quick" needs one tap.
--
--   PackTease.play({ tier = "Epic", count = 1 | 10, quick = bool }, onDone)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local Kit = require(here:WaitForChild("Kit"))
local PullRates = require(here:WaitForChild("PullRates"))
local Juice = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("Juice"))

local make, tween, rgb = Juice.make, Juice.tween, Juice.rgb

local PackTease = {}

PackTease.Taps = 3
PackTease.QuickTaps = 1
PackTease.AutoOpen = 5 -- seconds without a tap before the pack opens itself

local GOLD = rgb(255, 214, 102)
local INK = rgb(18, 14, 28)

-- Index of each tier, low to high.
local function tierIndex(tier)
	return table.find(PullRates.Tiers, tier) or 1
end

-- The highest tier the tease may show for a pull of `tier`.
function PackTease.capFor(tier)
	local i = tierIndex(tier)
	if i >= tierIndex("Mythic") then
		i -= 1
	end
	return i
end

-- The tier shown after tap `k` of `n`.
function PackTease.shownAfter(tier, k, n)
	local cap = PackTease.capFor(tier)
	return PullRates.Tiers[1 + math.floor((cap - 1) * k / n + 1e-9)]
end

local function buildPack(parent, count)
	local pack = make("Frame", { Name = "Pack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1.4), Size = UDim2.fromOffset(240, 340), BackgroundColor3 = rgb(255, 255, 255), BorderSizePixel = 0, Rotation = -10, ZIndex = 10 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, pack)
	local foil = make("UIGradient", {
		Rotation = 35,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(30, 26, 70)),
			ColorSequenceKeypoint.new(0.45, rgb(70, 40, 120)),
			ColorSequenceKeypoint.new(0.55, rgb(110, 70, 160)),
			ColorSequenceKeypoint.new(1, rgb(24, 20, 56)),
		}),
	}, pack)
	make("UIStroke", { Thickness = 4, Color = GOLD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pack)
	Juice.onFrame(pack, function(t)
		foil.Offset = Vector2.new(math.sin(t * 0.9) * 0.25, 0)
	end)
	-- the crimped top strip with its tear line
	local top = make("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = rgb(205, 160, 60), BorderSizePixel = 0, ZIndex = 11 }, pack)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, top)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 228, 140), rgb(190, 130, 40)) }, top)
	for k = 0, 11 do
		make("Frame", { Name = "Dash", Position = UDim2.new(k / 12, 4, 1, -3), Size = UDim2.new(1 / 12, -8, 0, 2), BackgroundColor3 = INK, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 12 }, top)
	end
	-- emblem
	local emblem = make("TextLabel", { Name = "Emblem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(170, 110), BackgroundTransparency = 1, Text = "DW", Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = rgb(255, 255, 255), ZIndex = 12 }, pack)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 238, 170), rgb(255, 156, 40)) }, emblem)
	make("UIStroke", { Thickness = 3, Color = INK }, emblem)
	make("TextLabel", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromOffset(200, 24), BackgroundTransparency = 1, Text = "DECK WARS", Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = GOLD, ZIndex = 12 }, pack)
	make("TextLabel", { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.75), Size = UDim2.fromOffset(200, 18), BackgroundTransparency = 1, Text = count > 1 and (count .. " CARDS · BRAWL PACK") or "1 CARD · BRAWL PACK", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = rgb(210, 200, 230), ZIndex = 12 }, pack)
	if count > 1 then
		local badge = make("TextLabel", { Name = "Count", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -10, 0, 54), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = rgb(255, 84, 112), Text = "x" .. count, Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = rgb(255, 255, 255), Rotation = 12, ZIndex = 14 }, pack)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
		make("UIStroke", { Thickness = 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
	end
	Juice.shine(pack, 2.2, UDim.new(0, 14))
	return pack
end

-- A crack in the pack with light pouring out of it.
local function addCrack(pack, color, k)
	local x = 0.25 + math.random() * 0.5
	local y = 0.25 + (k - 1) * 0.2 + math.random() * 0.08
	local crack = make("Frame", { Name = "Crack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(0, 4), BackgroundColor3 = rgb(255, 255, 255), BorderSizePixel = 0, Rotation = math.random(-40, 40), ZIndex = 13 }, pack)
	make("UIStroke", { Name = "Light", Thickness = 3, Color = color, Transparency = 0.2 }, crack)
	tween(crack, 0.12, { Size = UDim2.fromOffset(60 + math.random() * 70, 4) }, Enum.EasingStyle.Quad)
	return crack
end

function PackTease.play(opts, onDone)
	opts = opts or {}
	local tier = opts.tier or "Common"
	local count = opts.count or 1
	local needed = opts.quick and PackTease.QuickTaps or PackTease.Taps
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", { Name = "PackTease", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 55, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	local state = { taps = 0, finished = false, lastTap = 0, shown = PullRates.Tiers[1], cracks = {} }

	local dim = make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(6, 4, 12), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
	tween(dim, 0.35, { BackgroundTransparency = 0.25 })
	local rays = Juice.sunburst(gui, Kit.TierColor[state.shown], { count = 14, width = 60, length = 1000, transparency = 0.94, speed = 8, zIndex = 2 })
	-- the glow around the pack: the tease color
	local glow = make("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(260, 360), BackgroundTransparency = 1, ZIndex = 3 }, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 26) }, glow)
	local glowStroke = make("UIStroke", { Thickness = 18, Color = Kit.TierColor[state.shown], Transparency = 1 }, glow)
	local pack = buildPack(gui, count)
	local packScale = Juice.scaleOf(pack)

	local hint = make("TextLabel", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 200), Size = UDim2.fromOffset(400, 28), BackgroundTransparency = 1, Text = "TAP TO OPEN", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = rgb(255, 255, 255), TextTransparency = 1, ZIndex = 20 }, gui)
	make("UIStroke", { Thickness = 2, Color = INK }, hint)
	local dots = make("TextLabel", { Name = "Dots", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 232), Size = UDim2.fromOffset(200, 22), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = GOLD, ZIndex = 20 }, gui)
	local function refreshDots()
		local s = {}
		for k = 1, needed do
			s[k] = k <= state.taps and "●" or "○"
		end
		dots.Text = needed > 1 and table.concat(s, "  ") or ""
	end
	refreshDots()
	local teaseLabel = make("TextLabel", { Name = "Tease", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -200), Size = UDim2.fromOffset(500, 40), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = Kit.TierColor.Common, TextTransparency = 1, ZIndex = 20 }, gui)
	make("UIStroke", { Thickness = 3, Color = INK }, teaseLabel)

	local tapButton = make("TextButton", { Name = "TapPack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 30 }, gui)
	local ready = false
	local conn

	-- the pack rises into view
	Juice.sound("whoosh", 1.1, 0.5)
	tween(pack, 0.55, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }, Enum.EasingStyle.Back)
	task.delay(0.5, function()
		ready = true
		state.lastTap = Juice.clock()
		tween(hint, 0.3, { TextTransparency = 0 })
		tween(glowStroke, 0.4, { Transparency = 0.55 })
	end)
	Juice.onFrame(hint, function(t)
		hint.TextSize = 24 + math.sin(t * 5) * 1.5
	end)
	Juice.onFrame(glow, function(t)
		glow.Size = UDim2.fromOffset(260 + math.sin(t * 4) * 8, 360 + math.sin(t * 4) * 8)
		glow.Rotation = pack.Rotation
		glow.Position = pack.Position
	end)

	local function finish()
		if state.finished then
			return
		end
		state.finished = true
		ready = false
		if conn then
			conn:Disconnect()
		end
		tween(hint, 0.2, { TextTransparency = 1 })
		dots.Text = ""
		-- build-up: hard shaking while the light swells
		Juice.sound("charge", 1.2, 0.5)
		Juice.shake(pack, 9, 0.5)
		tween(glowStroke, 0.5, { Transparency = 0.1, Thickness = 30 })
		for _, c in ipairs(state.cracks) do
			tween(c, 0.4, { Size = UDim2.fromOffset(c.Size.X.Offset * 1.5, 7) })
		end
		task.delay(0.55, function()
			-- off it goes, into the ring
			Juice.sound("whoosh", 0.8, 0.7)
			tween(pack, 0.35, { Position = UDim2.fromScale(0.5, -0.4), Rotation = 28 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(packScale, 0.35, { Scale = 0.55 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(glowStroke, 0.25, { Transparency = 1 })
			tween(teaseLabel, 0.25, { TextTransparency = 1 })
			Juice.stars(gui, 0.5, 0.5, 14, { text = "✦", color = Kit.TierColor[state.shown], speed = 1.5, size = 22 })
			task.delay(0.33, function()
				Juice.flash(gui, rgb(255, 255, 255), 0.25, 0)
				tween(dim, 0.25, { BackgroundTransparency = 1 })
				rays.Visible = false
				task.delay(0.12, function()
					if onDone then
						task.spawn(onDone)
					end
				end)
				task.delay(0.3, function()
					gui:Destroy()
				end)
			end)
		end)
	end

	local function tap()
		if not ready or state.finished then
			return
		end
		state.taps += 1
		state.lastTap = Juice.clock()
		refreshDots()
		local k = state.taps
		-- jolt
		Juice.sound("thud", 0.9 + k * 0.15, 0.6)
		Juice.pop(pack, 1.1, 0.45)
		pack.Rotation = (k % 2 == 1 and 1 or -1) * (5 + k * 2)
		tween(pack, 0.4, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		Juice.shake(pack, 6 + k * 2, 0.2)
		-- the tease color for this tap
		local was = state.shown
		local now = PackTease.shownAfter(tier, k, needed)
		state.shown = now
		local color = Kit.TierColor[now]
		table.insert(state.cracks, addCrack(pack, color, k))
		Juice.stars(gui, 0.5, 0.5, 6 + k * 2, { text = "✦", color = color, size = 16 + k * 3 })
		if tierIndex(now) > tierIndex(was) or (k == 1 and now ~= "Common") then
			-- level up: the light changes color with a flash and a sound
			Juice.sound("glass", 1 + tierIndex(now) * 0.06, 0.4)
			Juice.flash(gui, color, 0.3, 0.6)
			tween(glowStroke, 0.25, { Color = color })
			Juice.tintSunburst(rays, color, 0.25)
		end
		if now ~= "Common" then
			teaseLabel.Text = string.upper(now) .. " OR BETTER"
			teaseLabel.TextColor3 = color
			teaseLabel.TextTransparency = 0
			Juice.pop(teaseLabel, 1.35, 0.5)
		end
		for _, r in ipairs(rays:GetDescendants()) do
			if r.Name == "Ray" then
				r.BackgroundTransparency = 0.8 - k * 0.05
			end
		end
		if k >= needed then
			task.delay(0.3, finish)
		end
	end
	PackTease.tapHook = tap -- (for tests)

	tapButton.Activated:Connect(tap)
	conn = UserInputService.InputBegan:Connect(function(input)
		local key = input.KeyCode
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			tap()
		end
	end)
	-- nobody tapping: open it anyway
	task.spawn(function()
		while not state.finished and gui.Parent do
			task.wait(0.25)
			if ready and not state.finished and Juice.clock() - state.lastTap >= PackTease.AutoOpen then
				for _ = state.taps + 1, needed do
					tap()
					task.wait(0.3)
				end
			end
		end
	end)
	return { gui = gui, state = state, tap = tap }
end

return PackTease

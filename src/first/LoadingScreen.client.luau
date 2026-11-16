-- The loading screen: the first thing a player sees. It runs from ReplicatedFirst, so it's up
-- before anything else has loaded, and it stays up while the game gets ready: the world arrives,
-- the Park is built on the server, the sounds, meshes and pictures are fetched, and your
-- character spawns. Then it sweeps away and the title screen starts, smooth instead of
-- stuttering through the first seconds.
--
-- The look: a deep night-blue backdrop with a slow turning glow, five cards fanned over the
-- DECK WARS logo that deal themselves out and flip to show their rarity colours, embers drifting
-- up, a gold progress bar with a shine running through it, what's loading right now, and a tip.
--
-- When it's done it sets the player's "Loaded" attribute (DeckWarsClient waits for that before
-- the title screen). It gives up waiting on anything slow after a while, so it never blocks.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player = Players.LocalPlayer
local gui0 = player:WaitForChild("PlayerGui")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function tween(inst, t, goal, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local GOLD = rgb(255, 214, 102)
local GOLD_DEEP = rgb(255, 150, 40)
local INK = rgb(20, 14, 30)
local FONT = Enum.Font.FredokaOne
local RARITY = { rgb(170, 170, 180), rgb(80, 150, 255), rgb(176, 96, 255), rgb(255, 196, 60), rgb(255, 90, 170) }

local TIPS = {
	"Tip: walk out to the Park from the door in your room.",
	"Tip: open packs at the Pull Altar on the island.",
	"Tip: swap spare cards with friends at the Trading Post.",
	"Tip: hop across the stepping stones to reach the island.",
	"Tip: fuse duplicates at the Deck Shelf to level a card up.",
	"Tip: your first creature in the showcase follows you around the Park.",
	"Tip: come back every day for the daily reward.",
	"Tip: after dark, look up: shooting stars cross the glasshouse roof.",
}

---------------------------------------------------------------------------
-- The screen
---------------------------------------------------------------------------

local gui = make("ScreenGui", { Name = "LoadingScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, gui0)
local bg = make("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255), BorderSizePixel = 0 }, gui) -- (white: the gradient below gives the colour)
local bgGrad = make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(40, 24, 78)), ColorSequenceKeypoint.new(0.5, rgb(16, 18, 52)), ColorSequenceKeypoint.new(1, rgb(10, 30, 58)) }), Rotation = 30 }, bg)

-- a big soft glow behind the logo that slowly breathes
local halo = make("Frame", { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.55, 0.55), BackgroundColor3 = rgb(255, 160, 70), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, bg)
make("UIAspectRatioConstraint", { AspectRatio = 1 }, halo)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.6), NumberSequenceKeypoint.new(1, 1) }) }, halo)

-- a dark edge round the screen
local vignette = make("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2 }, bg)
make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.25, 1), NumberSequenceKeypoint.new(0.75, 1), NumberSequenceKeypoint.new(1, 0.35) }), Rotation = 90 }, vignette)

-- embers drifting up
local embers = make("Frame", { Name = "Embers", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, bg)
local emberList = {}
for i = 1, 26 do
	local e = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = i % 3 == 0 and rgb(255, 120, 200) or GOLD, BorderSizePixel = 0, ZIndex = 3 }, embers)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, e)
	table.insert(emberList, { frame = e, x = math.random(), y = math.random(), speed = 0.03 + math.random() * 0.06, sway = math.random() * 6, size = 2 + math.random() * 5 })
end

-- the fan of cards over the logo
local stage = make("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(560, 420), BackgroundTransparency = 1, ZIndex = 5 }, bg)
local scale = make("UIScale", { Scale = 1 }, stage)
local cards = {}
for i = 1, 5 do
	local holder = make("Frame", { Name = "Card" .. i, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.62, 0), Size = UDim2.fromOffset(92, 130), BackgroundTransparency = 1, ZIndex = 5, Rotation = 0 }, stage)
	local face = make("Frame", { Name = "Face", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(46, 30, 86), BorderSizePixel = 0, ZIndex = 6 }, holder)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, face)
	make("UIStroke", { Color = GOLD, Thickness = 3 }, face)
	local grad = make("UIGradient", { Color = ColorSequence.new(rgb(90, 60, 160), rgb(40, 26, 80)), Rotation = 60 }, face)
	local mark = make("TextLabel", { Name = "Mark", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "★", Font = FONT, TextScaled = true, TextColor3 = GOLD, TextTransparency = 0.15, ZIndex = 7 }, face)
	make("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0), PaddingLeft = UDim.new(0.2, 0), PaddingRight = UDim.new(0.2, 0) }, mark)
	cards[i] = { holder = holder, face = face, grad = grad, mark = mark }
end

-- the logo
local logo = make("Frame", { Name = "Logo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.78, 0), Size = UDim2.fromOffset(560, 110), BackgroundTransparency = 1, ZIndex = 8 }, stage)
local word = make("TextLabel", { Name = "Word", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "DECK WARS", Font = FONT, TextScaled = true, TextColor3 = rgb(255, 255, 255), ZIndex = 9 }, logo)
make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 244, 196)), ColorSequenceKeypoint.new(0.55, GOLD), ColorSequenceKeypoint.new(1, GOLD_DEEP) }), Rotation = 90 }, word)
make("UIStroke", { Color = INK, Thickness = 5 }, word)
local shine = make("TextLabel", { Name = "Shine", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "DECK WARS", Font = FONT, TextScaled = true, TextColor3 = rgb(255, 255, 255), TextTransparency = 0, ZIndex = 10 }, logo)
local shineGrad = make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }), Rotation = 20, Offset = Vector2.new(-1, 0) }, shine)

-- the progress bar, what's loading and a tip
local bottom = make("Frame", { Name = "Bottom", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -48), Size = UDim2.fromOffset(520, 96), BackgroundTransparency = 1, ZIndex = 8 }, bg)
local bottomScale = make("UIScale", { Scale = 1 }, bottom)
local status = make("TextLabel", { Name = "Status", BackgroundTransparency = 1, Size = UDim2.new(1, -70, 0, 26), Text = "Shuffling the deck…", Font = FONT, TextSize = 22, TextColor3 = rgb(240, 236, 255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9 }, bottom)
local percent = make("TextLabel", { Name = "Percent", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), BackgroundTransparency = 1, Size = UDim2.fromOffset(70, 26), Text = "0%", Font = FONT, TextSize = 22, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 9 }, bottom)
local track = make("Frame", { Name = "Track", Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = rgb(10, 8, 24), BorderSizePixel = 0, ZIndex = 9 }, bottom)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
make("UIStroke", { Color = rgb(255, 214, 102), Transparency = 0.6, Thickness = 2 }, track)
local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 10 }, track)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
local fillGrad = make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, GOLD_DEEP), ColorSequenceKeypoint.new(0.45, GOLD), ColorSequenceKeypoint.new(0.5, rgb(255, 252, 230)), ColorSequenceKeypoint.new(0.55, GOLD), ColorSequenceKeypoint.new(1, GOLD_DEEP) }), Offset = Vector2.new(-1, 0) }, fill)
local tip = make("TextLabel", { Name = "Tip", Position = UDim2.fromOffset(0, 60), BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), Text = TIPS[math.random(1, #TIPS)], Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = rgb(180, 174, 210), ZIndex = 9 }, bottom)

---------------------------------------------------------------------------
-- The animation (every frame until it's gone)
---------------------------------------------------------------------------

local shown = 0 -- the bar as drawn (eases toward `target`)
local target = 0
local born = os.clock()
local finished = false

local function fit()
	local cam = workspace.CurrentCamera
	local view = cam and cam.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(view.X / 900, view.Y / 640), 0.45, 1.25)
	bottomScale.Scale = math.clamp(view.X / 640, 0.5, 1)
end

local conn = RunService.RenderStepped:Connect(function(dt)
	if finished then
		return -- (the fly-away tweens take over)
	end
	local t = os.clock() - born
	fit()
	bgGrad.Rotation = 30 + t * 6
	halo.BackgroundTransparency = 0.86 + 0.05 * math.sin(t * 1.6)
	-- the cards: fanned out, each lifting in turn and flipping to show a rarity colour
	for i, c in ipairs(cards) do
		local k = i - 3
		local lift = math.max(0, math.sin(t * 2.2 - i * 0.7)) ^ 3
		c.holder.Rotation = k * 13 + math.sin(t * 1.2 + i) * 1.5
		c.holder.Position = UDim2.new(0.5, k * 62, 0.62, -math.abs(k) * 10 + k * k * 4 - lift * 26)
		-- the flip: squash to nothing, swap the colour, open again
		local flip = (t * 0.55 + i * 0.37) % 2
		local w = math.abs(math.cos(flip * math.pi))
		c.face.Size = UDim2.fromScale(math.max(0.02, w), 1)
		local front = flip > 0.5 and flip < 1.5
		local col = RARITY[(i + math.floor((t * 0.55 + i * 0.37) / 2)) % #RARITY + 1]
		c.grad.Color = front and ColorSequence.new(col:Lerp(rgb(255, 255, 255), 0.25), col:Lerp(rgb(0, 0, 0), 0.35)) or ColorSequence.new(rgb(90, 60, 160), rgb(40, 26, 80))
		c.mark.Text = front and "✦" or "★"
		c.mark.TextColor3 = front and rgb(255, 255, 255) or GOLD
	end
	-- the logo bobs and a shine sweeps across it every couple of seconds
	logo.Position = UDim2.new(0.5, 0, 0.78, math.sin(t * 1.8) * 4)
	shineGrad.Offset = Vector2.new(((t * 0.6) % 1.6) * 2 - 1.3, 0)
	-- embers
	for _, e in ipairs(emberList) do
		e.y -= e.speed * dt
		if e.y < -0.05 then
			e.y = 1.05
			e.x = math.random()
		end
		e.frame.Position = UDim2.new(e.x, math.sin(t + e.sway) * 12, e.y, 0)
		e.frame.Size = UDim2.fromOffset(e.size, e.size)
		e.frame.BackgroundTransparency = 0.25 + 0.5 * math.abs(math.sin(t * 2 + e.sway))
	end
	-- the bar eases toward where loading is, with a shine running through it
	shown += (target - shown) * math.min(1, dt * 5)
	fill.Size = UDim2.fromScale(shown, 1)
	fillGrad.Offset = Vector2.new(((t * 0.8) % 1.4) * 2 - 1.2, 0)
	percent.Text = math.floor(shown * 100 + 0.5) .. "%"
end)

-- a new tip every few seconds
task.spawn(function()
	local n = math.random(1, #TIPS)
	while not finished do
		task.wait(4.5)
		if finished then
			break
		end
		n = n % #TIPS + 1
		tween(tip, 0.25, { TextTransparency = 1 }).Completed:Wait()
		tip.Text = TIPS[n]
		tween(tip, 0.25, { TextTransparency = 0 })
	end
end)

---------------------------------------------------------------------------
-- The loading itself: each step moves the bar between its share
---------------------------------------------------------------------------

local function step(text, from, to, work, limit)
	status.Text = text
	target = math.max(target, from)
	local done = false
	task.spawn(function()
		pcall(work, function(frac)
			target = math.max(target, from + (to - from) * math.clamp(frac, 0, 1))
		end)
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < (limit or 20) do
		task.wait(0.05)
	end
	target = math.max(target, to)
end

-- 1. the world arrives
step("Shuffling the deck…", 0, 0.15, function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
end, 30)

-- 2. the game's own scripts and pictures
step("Waking the creatures…", 0.15, 0.3, function()
	game:GetService("ReplicatedStorage"):WaitForChild("DeckWars", 20)
end, 20)

-- 3. the Park, built on the server
step("Planting the park…", 0.3, 0.45, function()
	workspace:WaitForChild("Park", 25)
end, 25)

-- 4. sounds, meshes and textures (the bar follows what's left in the download queue)
step("Polishing the glasshouse…", 0.45, 0.9, function(progress)
	local list = { game:GetService("SoundService"), workspace }
	local fetched, over = 0, false
	task.spawn(function()
		while not over and not finished do
			local left = ContentProvider.RequestQueueSize
			progress(fetched / math.max(1, fetched + left))
			task.wait(0.1)
		end
	end)
	ContentProvider:PreloadAsync(list, function()
		fetched += 1
	end)
	over = true
end, 25)

-- 5. your character
step("Opening the doors…", 0.9, 0.98, function()
	if not player.Character then
		player.CharacterAdded:Wait()
	end
end, 15)

-- (a short minimum, so the screen never just flickers past)
while os.clock() - born < 3 do
	task.wait(0.05)
end
target = 1
status.Text = "Ready!"
task.wait(0.55)
fill.Size = UDim2.fromScale(1, 1)
percent.Text = "100%"

---------------------------------------------------------------------------
-- Away it goes: the cards fly up, the logo swells, everything fades
---------------------------------------------------------------------------

finished = true
player:SetAttribute("Loaded", true)
for i, c in ipairs(cards) do
	tween(c.holder, 0.5, { Position = c.holder.Position - UDim2.fromOffset(0, 500), Rotation = c.holder.Rotation + (i - 3) * 25 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
end
tween(scale, 0.7, { Scale = scale.Scale * 1.25 })
for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("TextLabel") then
		tween(d, 0.6, { TextTransparency = 1 })
	elseif d:IsA("UIStroke") then
		tween(d, 0.6, { Transparency = 1 })
	elseif d:IsA("ImageLabel") then
		tween(d, 0.6, { ImageTransparency = 1 })
	end
end
task.wait(0.35)
for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("Frame") and d.BackgroundTransparency < 1 then
		tween(d, 0.7, { BackgroundTransparency = 1 })
	end
end
task.wait(0.8)
conn:Disconnect()
gui:Destroy()

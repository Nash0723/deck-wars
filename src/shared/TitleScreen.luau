-- The opening of Deck Wars: a title screen over the slowly drifting card room.
--
-- Black fades to a dim view of the room, the words DECK and WARS slam together in the middle
-- (flash, shake, sparks), a light glint runs across the logo, two showcase creatures turn on
-- glowing plinths at the sides, embers drift up, and the gold PLAY button pulses.
-- Pressing PLAY (or Enter / Space / gamepad A) sweeps it all away and hands over to the room.
--
--   TitleScreen.show({ onPlay = function() end }) -> { gui = ScreenGui, play = function() }
-- onPlay runs the moment the title starts to clear (move the camera then); the GUI removes
-- itself about a second later.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local Juice = require(here:WaitForChild("Juice"))
local CardData = require(here:WaitForChild("CardData"))
local CreatureBuilder = require(here:WaitForChild("CreatureBuilder"))

local make, tween, rgb = Juice.make, Juice.tween, Juice.rgb

local GOLD = rgb(255, 214, 102)
local GOLD_DEEP = rgb(255, 156, 40)
local INK = rgb(28, 18, 10)
local LOGO_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.FredokaOne

local TitleScreen = {}

-- Big creatures that look good turning on a plinth (two are picked at random each time).
TitleScreen.Showcase = {
	"queen_parfait", "the_junk_king", "stormlord_nimbus", "big_momma_moose", "the_mannequin_duke",
	"mega_blender_prime", "burrito_bouncer", "scrapheap_titan", "tornado_twins", "sergeant_snail",
	"escalator_wraith", "mecha_fridge", "lightning_llama", "spaghetti_hydra",
}

local TAGLINE = "COLLECT   ·   BATTLE   ·   BRAWL"

-- Text with the gold logo look: gradient fill, dark outline, and a white glint layer on top.
local function logoWord(parent, text, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = LOGO_FONT,
		TextScaled = true,
		TextColor3 = rgb(255, 255, 255),
	}, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 238, 170), GOLD_DEEP) }, l)
	make("UIStroke", { Thickness = 5, Color = INK }, l)
	local glint = make("TextLabel", {
		Name = "Glint",
		BackgroundTransparency = 1,
		Text = text,
		Font = LOGO_FONT,
		TextScaled = true,
		TextColor3 = rgb(255, 255, 255),
		Size = UDim2.fromScale(1, 1),
		ZIndex = l.ZIndex + 1,
	}, l)
	local g = make("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1.3, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, glint)
	return l, g
end

-- A creature turning slowly in a ViewportFrame, standing in a pool of light.
local function showcase(parent, id, side)
	local holder = make("Frame", {
		Name = "Showcase_" .. side,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(side == "Left" and 0.16 or 0.84, 0.9),
		Size = UDim2.fromOffset(260, 300),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, parent)
	-- light pool under its feet
	local pool = make("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(220, 46), BackgroundColor3 = GOLD, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 4 }, holder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, pool)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, pool)
	local vp = make("ViewportFrame", {
		Name = "View",
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
		Ambient = rgb(120, 110, 130),
		LightColor = rgb(255, 236, 200),
		LightDirection = Vector3.new(-0.5, -1, -0.7),
		ZIndex = 5,
	}, holder)
	local model = CreatureBuilder.build(id)
	if model then
		model.Parent = vp
		local info = CreatureBuilder.info(id) or { height = 3, width = 3, depth = 3 }
		local h = math.max(info.height, 0.5)
		local wide = math.max(info.width, info.depth)
		local look = Vector3.new(0, h * 0.5, 0)
		local dist = math.max(h * 2.4, wide * 1.6) + 1
		local cam = make("Camera", { FieldOfView = 30 }, vp)
		cam.CFrame = CFrame.lookAt(look + Vector3.new(0, h * 0.15, -dist), look)
		vp.CurrentCamera = cam
		local base = model:GetPivot()
		local dir = side == "Left" and 1 or -1
		local phase = math.random() * 6.28
		Juice.onFrame(vp, function(t)
			model:PivotTo(base * CFrame.new(0, math.sin(t * 1.4 + phase) * 0.04 * h, 0) * CFrame.Angles(0, dir * (0.6 + math.sin(t * 0.45 + phase) * 0.7), 0))
		end)
	end
	local def = CardData.get(id)
	local tag = make("TextLabel", {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(260, 22),
		BackgroundTransparency = 1,
		Text = string.upper(def.name) .. "  ·  " .. string.upper(def.rarity),
		Font = BODY_FONT,
		TextSize = 13,
		TextColor3 = rgb(235, 225, 205),
		TextTransparency = 0.15,
		ZIndex = 5,
	}, holder)
	make("UIStroke", { Thickness = 1.5, Color = INK, Transparency = 0.3 }, tag)
	return holder
end

-- Gold embers that drift up the screen while the title is open.
local function embers(parent)
	local holder = make("Frame", { Name = "Embers", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, parent)
	local list = {}
	local spawnAt = 0
	Juice.onFrame(holder, function(t, dt)
		if t >= spawnAt and #list < 28 then
			spawnAt = t + 0.12 + math.random() * 0.15
			local s = math.random(3, 7)
			local e = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(s, s), BackgroundColor3 = math.random() < 0.7 and GOLD or rgb(255, 140, 60), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 2 }, holder)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, e)
			table.insert(list, { inst = e, x = math.random(), y = 1.05, vy = 0.05 + math.random() * 0.07, sway = math.random() * 6.28, life = 0 })
		end
		local i = 1
		while i <= #list do
			local e = list[i]
			e.life += dt
			e.y -= e.vy * dt
			if e.y < -0.05 then
				e.inst:Destroy()
				table.remove(list, i)
			else
				e.inst.Position = UDim2.fromScale(e.x + math.sin(t * 0.8 + e.sway) * 0.01, e.y)
				e.inst.BackgroundTransparency = 0.2 + 0.6 * (1 - e.y) + 0.15 * math.sin(t * 6 + e.sway)
				i += 1
			end
		end
	end)
	return holder
end

function TitleScreen.show(opts)
	opts = opts or {}
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", { Name = "DeckWarsTitle", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	local handle = { gui = gui, done = false }

	-- dim the room behind: darker at the top and bottom
	local shade = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(8, 6, 14), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1 }, gui)
	local shadeGrad = make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.45, 0.45),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
	}, shade)
	-- starts fully black, then fades to the dim view
	local blackout = make("Frame", { Name = "Blackout", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0, 0, 0), BorderSizePixel = 0, ZIndex = 40 }, gui)
	tween(blackout, 0.9, { BackgroundTransparency = 1 })
	-- cinema bars
	local barTop = make("Frame", { Name = "BarTop", Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = rgb(0, 0, 0), BorderSizePixel = 0, ZIndex = 30 }, gui)
	local barBottom = make("Frame", { Name = "BarBottom", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = rgb(0, 0, 0), BorderSizePixel = 0, ZIndex = 30 }, gui)

	embers(gui)
	local rays = Juice.sunburst(gui, GOLD, { position = UDim2.fromScale(0.5, 0.33), count = 14, width = 70, length = 900, transparency = 1, speed = 6, zIndex = 2 })

	-- the logo: DECK slides in from the left, WARS from the right, and they slam together
	local logo = make("Frame", { Name = "Logo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.33), Size = UDim2.fromOffset(820, 150), BackgroundTransparency = 1, ZIndex = 10 }, gui)
	local deck, deckGlint = logoWord(logo, "DECK", { Name = "Deck", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.5, -1400, 0.5, 0), Size = UDim2.new(0.5, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 10 })
	local wars, warsGlint = logoWord(logo, "WARS", { Name = "Wars", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 1400, 0.5, 0), Size = UDim2.new(0.5, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10 })
	local underline = make("Frame", { Name = "Underline", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 8), Size = UDim2.fromOffset(0, 4), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 10 }, logo)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, underline)
	local tagline = make("TextLabel", { Name = "Tagline", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.33, 110), Size = UDim2.fromOffset(600, 26), BackgroundTransparency = 1, Text = TAGLINE, Font = BODY_FONT, TextSize = 20, TextColor3 = rgb(240, 232, 215), TextTransparency = 1, ZIndex = 10 }, gui)
	local taglineStroke = make("UIStroke", { Thickness = 1.5, Color = INK, Transparency = 1 }, tagline)

	-- showcase creatures, two different families
	local pool = {}
	for _, id in ipairs(TitleScreen.Showcase) do
		if CreatureBuilder.has(id) and CardData.Cards[id] then
			table.insert(pool, id)
		end
	end
	local shows = {}
	if #pool >= 2 then
		local a = pool[math.random(1, #pool)]
		local b
		for _ = 1, 20 do
			b = pool[math.random(1, #pool)]
			if CardData.Cards[b].family ~= CardData.Cards[a].family then
				break
			end
		end
		if b == a then
			b = pool[(table.find(pool, a) % #pool) + 1]
		end
		shows = { showcase(gui, a, "Left"), showcase(gui, b, "Right") }
		for _, s in ipairs(shows) do
			s.Visible = false
		end
	end

	-- PLAY: a gold button with a pulse ring behind it
	local playHolder = make("Frame", { Name = "PlayHolder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromOffset(280, 78), BackgroundTransparency = 1, Visible = false, ZIndex = 12 }, gui)
	local ring = make("Frame", { Name = "PulseRing", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 11 }, playHolder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local ringStroke = make("UIStroke", { Thickness = 3, Color = GOLD, Transparency = 0.3 }, ring)
	Juice.onFrame(ring, function(t)
		local k = (t * 0.7) % 1
		ring.Size = UDim2.new(1, 40 * k, 1, 40 * k)
		ringStroke.Transparency = 0.25 + 0.75 * k
	end)
	local play = make("TextButton", {
		Name = "Play",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(255, 255, 255),
		AutoButtonColor = false,
		Text = "PLAY",
		Font = LOGO_FONT,
		TextSize = 38,
		TextColor3 = INK,
		ZIndex = 12,
	}, playHolder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, play)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 232, 150), GOLD_DEEP) }, play)
	make("UIStroke", { Thickness = 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, play)
	Juice.shine(play, 2.6, UDim.new(1, 0))
	Juice.button(play, { grow = 1.06, sound = false })
	local hint = make("TextLabel", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.7, 52), Size = UDim2.fromOffset(400, 20), BackgroundTransparency = 1, Text = "Press Enter or tap PLAY", Font = BODY_FONT, TextSize = 14, TextColor3 = rgb(200, 190, 175), TextTransparency = 1, ZIndex = 12 }, gui)

	local ready = false

	-- the slam
	task.delay(0.35, function()
		Juice.sound("whoosh", 0.9, 0.5)
		tween(deck, 0.28, { Position = UDim2.new(0.5, -12, 0.5, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(wars, 0.28, { Position = UDim2.new(0.5, 12, 0.5, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end)
	task.delay(0.63, function()
		if handle.done then
			return
		end
		Juice.sound("heavy", 1, 0.7)
		Juice.sound("theme", 1, 0.5)
		Juice.flash(gui, rgb(255, 240, 200), 0.45, 0.35)
		Juice.shake(logo, 14, 0.35)
		Juice.pop(logo, 1.12, 0.6)
		Juice.stars(gui, 0.5, 0.33, 18, { text = "✦", color = GOLD, speed = 1.6, size = 22, gravity = 120 })
		Juice.tintSunburst(rays, GOLD, 0.1)
		for _, r in ipairs(rays:GetDescendants()) do
			if r.Name == "Ray" then
				r.BackgroundTransparency = 0.55
				tween(r, 1.2, { BackgroundTransparency = 0.93 })
			end
		end
		tween(underline, 0.5, { Size = UDim2.fromOffset(640, 4) }, Enum.EasingStyle.Quint)
	end)
	-- the glint runs across the logo every few seconds
	local glintAt = 1.0
	Juice.onFrame(logo, function(t)
		if t < glintAt then
			return
		end
		local k = (t - glintAt) % 4.5
		local o = k < 0.9 and (-1.3 + 2.6 * k / 0.9) or 1.3
		deckGlint.Offset = Vector2.new(o, 0)
		warsGlint.Offset = Vector2.new(o - 0.6, 0)
		logo.Rotation = math.sin(t * 0.6) * 0.6
	end)
	task.delay(1.0, function()
		if handle.done then
			return
		end
		glintAt = Juice.clock()
		tagline.Position = UDim2.new(0.5, 0, 0.33, 124)
		tween(tagline, 0.6, { TextTransparency = 0.1, Position = UDim2.new(0.5, 0, 0.33, 110) })
		tween(taglineStroke, 0.6, { Transparency = 0.4 })
	end)
	task.delay(1.25, function()
		if handle.done then
			return
		end
		for k, s in ipairs(shows) do
			s.Visible = true
			local final = s.Position
			s.Position = final + UDim2.fromOffset(0, 60)
			task.delay((k - 1) * 0.15, function()
				tween(s, 0.7, { Position = final }, Enum.EasingStyle.Back)
			end)
		end
	end)
	task.delay(1.5, function()
		if handle.done then
			return
		end
		playHolder.Visible = true
		Juice.popIn(playHolder, 0, { twist = 0, pitch = 1.1 })
		tween(hint, 0.5, { TextTransparency = 0.2 })
		ready = true
	end)

	local conn
	function handle.play()
		if handle.done then
			return
		end
		handle.done = true
		ready = false
		if conn then
			conn:Disconnect()
		end
		Juice.sound("pop", 1.0, 0.6)
		Juice.sound("whoosh", 0.75, 0.6)
		if opts.onPlay then
			task.spawn(opts.onPlay)
		end
		-- everything clears: logo grows and fades, the bars slide off, the shade lifts
		local ls = Juice.scaleOf(logo)
		tween(ls, 0.6, { Scale = 1.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, l in ipairs({ deck, wars, deck:FindFirstChild("Glint"), wars:FindFirstChild("Glint"), tagline, hint }) do
			if l then
				tween(l, 0.45, { TextTransparency = 1 })
				local st = l:FindFirstChildOfClass("UIStroke")
				if st then
					tween(st, 0.35, { Transparency = 1 })
				end
			end
		end
		tween(underline, 0.4, { BackgroundTransparency = 1 })
		Juice.popOut(playHolder, 0.25)
		for _, s in ipairs(shows) do
			tween(s, 0.5, { Position = s.Position + UDim2.fromOffset(0, 400) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		tween(barTop, 0.7, { Position = UDim2.fromOffset(0, -60) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(barBottom, 0.7, { Position = UDim2.new(0, 0, 1, 60) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(shade, 0.9, { BackgroundTransparency = 1 })
		rays.Visible = false
		task.delay(1.0, function()
			gui:Destroy()
		end)
	end
	play.Activated:Connect(function()
		if ready then
			handle.play()
		end
	end)
	conn = UserInputService.InputBegan:Connect(function(input)
		local k = input.KeyCode
		if ready and (k == Enum.KeyCode.Return or k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.ButtonStart) then
			handle.play()
		end
	end)
	return handle
end

return TitleScreen

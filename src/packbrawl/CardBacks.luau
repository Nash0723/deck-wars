-- Card backs by rarity: while a pulled card waits face down, its back "wakes up" in the colours of
-- what's inside. Client only, GUI only.
--
-- Turn it off with one line: CardBacks.ByRarity = false (every card keeps the classic navy back
-- and nothing hints at the rarity before the flip, as before).
--
-- Every back keeps the same Deck Wars crest so it still reads as the card back; the rarer the
-- card, the more it dresses up:
--   Common      the classic navy back (it doesn't change)
--   Rare        cobalt, a blue inner frame, corner gems, two pips
--   Epic        royal purple, pinstripes, a double crest ring, a light that sweeps across
--   Mythic      crimson, a slow sunburst behind the crest, a plate under the name
--   Legendary   black and gold, a gold lattice, gold lettering, a star on top
--   Secret      shifting iridescent colours, a starfield, a rainbow edge and lettering
--
--   CardBacks.dress(back, rarity) -> the dressed state, or nil (flag off, Common, or no back).
--        The rarity look is built inside the back but stays hidden until it is woken.
--   CardBacks.awaken(back, delay) -- after `delay` seconds the look fades in, with a pop and a
--        shake that grow with the rarity (and a sound).
--
-- PackOpen makes the backs (PackArt.cardBack); Reveal dresses and wakes them, since it knows the ids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeckWars = ReplicatedStorage:WaitForChild("DeckWars")
local Juice = require(DeckWars:WaitForChild("Juice"))
local Settings = nil
pcall(function()
	Settings = require(DeckWars:WaitForChild("Settings"))
end)

local make, tween, rgb = Juice.make, Juice.tween, Juice.rgb
local WHITE = rgb(255, 255, 255)
local INK = rgb(18, 14, 28)
local CREAM = rgb(242, 230, 201)

local CardBacks = {}

CardBacks.ByRarity = true -- false: classic backs only, no rarity hint before the flip

local RANK = { Common = 1, Rare = 2, Epic = 3, Mythic = 4, Legendary = 5, Secret = 6 }

-- Each rarity's colours: body top / bottom, the trim, the edge, the lettering.
local LOOK = {
	Rare = { top = rgb(38, 86, 160), bottom = rgb(10, 22, 58), trim = rgb(61, 165, 255), edge = rgb(130, 200, 255), letters = CREAM },
	Epic = { top = rgb(86, 38, 150), bottom = rgb(22, 8, 50), trim = rgb(176, 98, 255), edge = rgb(206, 156, 255), letters = CREAM },
	Mythic = { top = rgb(140, 24, 52), bottom = rgb(34, 4, 14), trim = rgb(255, 72, 104), edge = rgb(255, 140, 156), letters = rgb(255, 232, 228) },
	Legendary = { top = rgb(52, 36, 12), bottom = rgb(12, 8, 4), trim = rgb(255, 194, 26), edge = rgb(255, 214, 92), letters = rgb(255, 226, 130) },
	Secret = { top = rgb(54, 22, 96), bottom = rgb(8, 32, 54), trim = rgb(255, 255, 255), edge = rgb(255, 255, 255), letters = WHITE },
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 90, 110)),
	ColorSequenceKeypoint.new(0.2, rgb(255, 200, 80)),
	ColorSequenceKeypoint.new(0.4, rgb(120, 240, 140)),
	ColorSequenceKeypoint.new(0.6, rgb(90, 200, 255)),
	ColorSequenceKeypoint.new(0.8, rgb(200, 120, 255)),
	ColorSequenceKeypoint.new(1, rgb(255, 90, 110)),
})

local dressed = setmetatable({}, { __mode = "k" })

local function lowGraphics()
	return Settings ~= nil and Settings.get("graphics") == "Low"
end

local function frame(parent, props)
	local f = make("Frame", { BorderSizePixel = 0 }, parent)
	for k, v in pairs(props) do
		f[k] = v
	end
	return f
end

local function corner(p, px)
	return make("UICorner", { CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0) }, p)
end

-- Hard-edged stripes as a colour gradient (n of each colour; n <= 9 keeps under 20 keypoints).
local function stripes(parent, a, b, n, rot)
	local keys = {}
	for k = 0, n - 1 do
		local x0, x1 = k / n, (k + 1) / n
		local col = (k % 2 == 0) and a or b
		table.insert(keys, ColorSequenceKeypoint.new(x0, col))
		table.insert(keys, ColorSequenceKeypoint.new(math.max(x0, x1 - 0.001), col))
	end
	keys[#keys] = ColorSequenceKeypoint.new(1, (n % 2 == 1) and a or b)
	return make("UIGradient", { Rotation = rot or 45, Color = ColorSequence.new(keys) }, parent)
end

-- A small diamond (a turned square).
local function gem(parent, x, y, px, color, z)
	local g = frame(parent, { Name = "Gem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(px, px), Rotation = 45, BackgroundColor3 = color, ZIndex = z or 1 })
	make("UIStroke", { Thickness = math.max(1, px * 0.12), Color = INK, Transparency = 0.35 }, g)
	return g
end

function CardBacks.dress(back, rarity)
	if not CardBacks.ByRarity or not back or not back.Parent then
		return nil
	end
	local look = LOOK[rarity]
	if not look then
		return nil -- (Common keeps the classic back)
	end
	if dressed[back] then
		return dressed[back]
	end
	local rank = RANK[rarity] or 2
	local low = lowGraphics()
	local w = back.Parent:IsA("GuiObject") and back.Parent.Size.X.Offset or 0
	local k = (w > 0 and w or 300) / 300 -- 1 for the big single card, about 0.47 in a 10-pack fan
	back:SetAttribute("KeepColors", true) -- (the cozy menu colours leave the backs alone)

	-- the whole look lives in one group that fades in when the card wakes up
	local trim = make("CanvasGroup", { Name = "RarityBack", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, GroupTransparency = 1 }, back)
	corner(trim, math.floor(16 * k + 0.5))
	local body = make("UIGradient", { Rotation = 90, Color = ColorSequence.new(look.top, look.bottom) }, trim)
	local spin = {} -- things that turn slowly: { inst, degrees per second }

	if rarity == "Secret" then
		body.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(70, 26, 110)),
			ColorSequenceKeypoint.new(0.5, rgb(18, 62, 96)),
			ColorSequenceKeypoint.new(1, rgb(96, 22, 74)),
		})
		table.insert(spin, { body, 22 })
		-- a starfield
		local r = Random.new(7)
		for _ = 1, low and 10 or 18 do
			local px = math.max(2, math.floor((2 + r:NextNumber() * 3) * k + 0.5))
			local star = frame(trim, { Name = "Star", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.06 + r:NextNumber() * 0.88, 0.05 + r:NextNumber() * 0.9), Size = UDim2.fromOffset(px, px), BackgroundColor3 = WHITE, BackgroundTransparency = 0.3 })
			corner(star)
			local phase, speed = r:NextNumber() * 6.28, 1.5 + r:NextNumber() * 2
			Juice.onFrame(star, function(t)
				star.BackgroundTransparency = 0.25 + 0.6 * (0.5 + 0.5 * math.sin(t * speed + phase))
			end)
		end
	elseif rank >= 3 then
		-- pinstripes (Epic, Mythic); Legendary crosses them into a lattice
		local n = rarity == "Legendary" and 9 or 8
		local p1 = frame(trim, { Name = "Pattern", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = rarity == "Legendary" and 0.9 or 0.92 })
		stripes(p1, look.trim, look.bottom, n, 45)
		if rarity == "Legendary" then
			local p2 = frame(trim, { Name = "Pattern2", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.9 })
			stripes(p2, look.trim, look.bottom, n, -45)
		end
	end

	-- a slow sunburst behind the crest (Mythic and up)
	if rank >= 4 then
		local rays = frame(trim, { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 })
		local fade = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.55), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(0.65, 0.55), NumberSequenceKeypoint.new(1, 1) })
		for i = 0, (low and 5 or 8) - 1 do
			local ray = frame(rays, { Name = "Ray", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(math.floor(460 * k), math.floor(22 * k + 0.5)), Rotation = i * (180 / (low and 5 or 8)), BackgroundColor3 = look.trim, BackgroundTransparency = 0.55 })
			make("UIGradient", { Transparency = fade }, ray)
		end
		table.insert(spin, { rays, rarity == "Secret" and 14 or 9 })
	end

	-- the inner frame line and the corner gems (all of them)
	local inset = math.floor(11 * k + 0.5)
	local line = frame(trim, { Name = "InnerFrame", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -inset * 2, 1, -inset * 2), BackgroundTransparency = 1 })
	corner(line, math.floor(10 * k + 0.5))
	local lineStroke = make("UIStroke", { Thickness = math.max(1, 2 * k), Color = look.trim, Transparency = 0.2 }, line)
	local gemPx = math.max(5, math.floor(13 * k + 0.5))
	for _, c in ipairs({ { 0.1, 0.075 }, { 0.9, 0.075 }, { 0.1, 0.925 }, { 0.9, 0.925 } }) do
		gem(trim, c[1], c[2], gemPx, look.trim)
	end

	-- the crest: a dark plate (Mythic and up), the ring (doubled from Epic) and the name
	if rank >= 4 then
		local plate = frame(trim, { Name = "Plate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.46), BackgroundColor3 = look.bottom, BackgroundTransparency = 0.2 })
		corner(plate, 400)
	end
	local ring = frame(trim, { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.5), BackgroundTransparency = 1 })
	corner(ring, 400)
	local ringStroke = make("UIStroke", { Thickness = math.max(1.5, 5 * k), Color = look.edge }, ring)
	if rank >= 3 then
		local inner = frame(trim, { Name = "Ring2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.41), BackgroundTransparency = 1 })
		corner(inner, 400)
		make("UIStroke", { Thickness = math.max(1, 2 * k), Color = look.trim, Transparency = 0.35 }, inner)
	end
	local letters = make("TextLabel", {
		Name = "Crest",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.25),
		BackgroundTransparency = 1,
		Text = "DECK\nWARS",
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = rarity == "Legendary" and WHITE or look.letters,
	}, trim)
	make("UIStroke", { Thickness = math.max(1, 2 * k), Color = INK, Transparency = 0.35 }, letters)
	if rarity == "Legendary" then
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 244, 190), rgb(255, 168, 30)) }, letters)
	elseif rarity == "Secret" then
		table.insert(spin, { make("UIGradient", { Color = RAINBOW }, letters), 60 })
		table.insert(spin, { make("UIGradient", { Color = RAINBOW }, ringStroke), -40 })
		table.insert(spin, { make("UIGradient", { Color = RAINBOW }, lineStroke), 40 })
	end

	-- a star over the crest (Legendary and Secret)
	if rank >= 5 then
		local star = make("TextLabel", {
			Name = "TopStar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.17),
			Size = UDim2.fromOffset(math.floor(40 * k + 0.5), math.floor(40 * k + 0.5)),
			BackgroundTransparency = 1,
			Text = "★",
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			TextColor3 = rarity == "Secret" and WHITE or look.trim,
		}, trim)
		make("UIStroke", { Thickness = math.max(1, 1.5 * k), Color = INK, Transparency = 0.3 }, star)
		if rarity == "Secret" then
			table.insert(spin, { make("UIGradient", { Color = RAINBOW }, star), 80 })
		end
		local base = star.Size
		Juice.onFrame(star, function(t)
			local s = 1 + 0.08 * math.sin(t * 3)
			star.Size = UDim2.fromOffset(base.X.Offset * s, base.Y.Offset * s)
		end)
	end

	-- pips: how rare, at a glance (2 for Rare ... 6 for Secret)
	local pipPx = math.max(4, math.floor(10 * k + 0.5))
	local gap = pipPx * 1.9
	for i = 1, rank do
		local x = 0.5 + ((i - (rank + 1) / 2) * gap) / math.max(1, w > 0 and w or 300)
		gem(trim, x, 0.84, pipPx, look.edge)
	end

	-- a light that sweeps across (Epic and up), more often the rarer it is
	if rank >= 3 and not low then
		Juice.shine(trim, ({ [3] = 3.2, [4] = 2.6, [5] = 2.1, [6] = 1.8 })[rank] or 3, UDim.new(0, math.floor(16 * k + 0.5)))
	end

	if #spin > 0 then
		Juice.onFrame(trim, function(_, dt)
			for _, sp in ipairs(spin) do
				sp[1].Rotation = (sp[1].Rotation + sp[2] * (dt or 0)) % 360
			end
		end)
	end

	local state = { trim = trim, rank = rank, rarity = rarity, look = look, k = k, awake = false }
	dressed[back] = state
	return state
end

function CardBacks.awaken(back, delay)
	local st = back and dressed[back]
	if not st or st.awake then
		return
	end
	local function go()
		if st.awake or not back.Parent or not back.Visible then
			return
		end
		st.awake = true
		local rank = st.rank
		tween(st.trim, 0.35 + rank * 0.05, { GroupTransparency = 0 })
		local edge = back:FindFirstChildOfClass("UIStroke")
		if edge then
			tween(edge, 0.4, { Color = st.look.edge })
			if st.rarity == "Secret" then
				local g = make("UIGradient", { Color = RAINBOW }, edge)
				Juice.onFrame(g, function(_, dt)
					g.Rotation = (g.Rotation + 90 * (dt or 0)) % 360
				end)
			end
		end
		-- a flash of light across the back as it changes
		local flash = make("Frame", { Name = "WakeFlash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = st.rarity == "Secret" and WHITE or st.look.edge, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 8 }, back)
		corner(flash, math.floor(16 * st.k + 0.5))
		tween(flash, 0.45, { BackgroundTransparency = 1 }).Completed:Connect(function()
			flash:Destroy()
		end)
		-- the rarer, the bigger the pop and the shake
		if rank >= 3 then
			Juice.pop(back, 1 + 0.025 * rank, 0.55)
		end
		if rank >= 4 then
			Juice.shake(back, (1 + rank) * st.k * 1.4, 0.2 + 0.05 * rank)
		end
		Juice.sound(rank >= 5 and "charge" or "tick", 0.75 + rank * 0.1, 0.2 + rank * 0.05)
	end
	if delay and delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
end

return CardBacks

-- Card backs by biome and rarity: while a pulled card waits face down, its back "wakes up".
-- Client only, GUI only.
--
-- The art is the card's biome (its family's world): Gumdrop Plaza for Snack, Sunset Grasslands
-- for Critter, Frostglass Lake for Weather, Ember Caldera for Junk, Cosmic Void for Robo and
-- Midnight Mall for Spooky. Cards of no family keep the Deck Wars back. The rarity is the foil
-- over it: a tint and a sheen in the rarity's colour, the edge, the crest, the pips and how hard
-- the back pops when it wakes (Common is matte, Secret a shifting rainbow holo).
--
-- Two flags (at the top, below):
--   CardBacks.ByBiome = false   every card uses the Deck Wars back art (rarity foil still shows)
--   CardBacks.ByRarity = false  no foil, no rarity hint at all before the flip
-- Both false: the classic navy back for every card, as before.
--
-- A card of no family dresses up by rarity alone:
--   Common      the classic navy back (it doesn't change)
--   Rare        cobalt, a blue inner frame, corner gems, two pips
--   Epic        royal purple, pinstripes, a double crest ring, a light that sweeps across
--   Mythic      crimson, a slow sunburst behind the crest, a plate under the name
--   Legendary   black and gold, a gold lattice, gold lettering, a star on top
--   Secret      shifting iridescent colours, a starfield, a rainbow edge and lettering
--
--   CardBacks.dress(back, rarity, family) -> the dressed state, or nil (flags off, a Common card
--        of no family, or no back).
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

CardBacks.ByRarity = true -- false: no rarity foil, no rarity hint before the flip
CardBacks.ByBiome = true -- false: no biome art (cards of every family use the Deck Wars back)

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

---------------------------------------------------------------------------
-- Biome art (each draws into `art`, a full-size frame; k = card width / 300; r = a seeded random)
---------------------------------------------------------------------------

local function dot(parent, x, y, px, color, transparency)
	local d = frame(parent, { Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(px, px), BackgroundColor3 = color, BackgroundTransparency = transparency or 0 })
	corner(d)
	return d
end

-- a round shape sized by the card's width (so it stays round on a tall card)
local function blob(parent, x, y, wScale, color, transparency, name)
	local b = frame(parent, { Name = name or "Blob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(wScale, wScale), BackgroundColor3 = color, BackgroundTransparency = transparency or 0 })
	make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, b)
	corner(b)
	return b
end

local function twinkle(d, r, base)
	local phase, speed = r:NextNumber() * 6.28, 1.2 + r:NextNumber() * 2
	Juice.onFrame(d, function(t)
		d.BackgroundTransparency = base + (1 - base) * 0.75 * (0.5 + 0.5 * math.sin(t * speed + phase))
	end)
end

local BIOME = {}

-- Snack: Gumdrop Plaza. Pink and mint candy stripes, sprinkles, a row of gumdrops.
BIOME.Snack = {
	name = "Gumdrop Plaza",
	top = rgb(255, 150, 196),
	bottom = rgb(150, 58, 120),
	accent = rgb(130, 236, 214),
	plate = rgb(110, 30, 80),
	draw = function(art, k, r, low)
		local band = frame(art, { Name = "Stripes", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8 })
		stripes(band, rgb(255, 250, 240), rgb(255, 120, 180), 9, 35)
		local cols = { WHITE, rgb(130, 236, 214), rgb(255, 230, 90), rgb(120, 180, 255), rgb(255, 120, 120) }
		for _ = 1, low and 10 or 18 do
			local sp = frame(art, { Name = "Sprinkle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.06 + r:NextNumber() * 0.88, 0.06 + r:NextNumber() * 0.7), Size = UDim2.fromOffset(math.max(2, 4 * k), math.max(5, 12 * k)), Rotation = r:NextNumber() * 180, BackgroundColor3 = cols[r:NextInteger(1, #cols)] })
			corner(sp)
		end
		local drops = { rgb(255, 90, 140), rgb(130, 236, 214), rgb(255, 214, 90), rgb(170, 120, 255), rgb(255, 140, 80) }
		for i = 0, 4 do
			local g = blob(art, 0.02 + i * 0.24, 1.0, 0.3, drops[i + 1], 0, "Gumdrop")
			dot(g, 0.32, 0.25, math.max(3, 9 * k), WHITE, 0.35)
		end
	end,
}

-- Critter: Sunset Grasslands. A sunset sky, a big low sun, rolling hills, grass and fireflies.
BIOME.Critter = {
	name = "Sunset Grasslands",
	top = rgb(98, 58, 132),
	bottom = rgb(255, 156, 76),
	accent = rgb(150, 230, 110),
	plate = rgb(60, 34, 60),
	draw = function(art, k, r, low)
		blob(art, 0.5, 0.66, 0.78, rgb(255, 214, 120), 0.15, "Sun")
		blob(art, 0.5, 0.66, 1.0, rgb(255, 200, 110), 0.8, "SunGlow")
		blob(art, 0.15, 1.08, 0.95, rgb(58, 104, 54), 0, "Hill")
		blob(art, 0.9, 1.12, 1.0, rgb(44, 86, 44), 0, "Hill")
		for i = 0, low and 10 or 18 do
			local x = i / (low and 10 or 18)
			frame(art, { Name = "Blade", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, 1.01), Size = UDim2.fromOffset(math.max(2, 4 * k), (16 + r:NextNumber() * 18) * k), Rotation = (r:NextNumber() - 0.5) * 30, BackgroundColor3 = rgb(70, 130, 60) })
		end
		for _ = 1, low and 4 or 8 do
			twinkle(dot(art, 0.08 + r:NextNumber() * 0.84, 0.55 + r:NextNumber() * 0.35, math.max(2, 5 * k), rgb(255, 250, 150), 0.2), r, 0.1)
		end
	end,
}

-- Weather: Frostglass Lake. Icy blue, northern lights, frost crystals, snow and a frozen shore.
BIOME.Weather = {
	name = "Frostglass Lake",
	top = rgb(36, 50, 140),
	bottom = rgb(150, 220, 255),
	accent = rgb(170, 240, 255),
	plate = rgb(20, 36, 90),
	draw = function(art, k, r, low)
		local aurora = frame(art, { Name = "Aurora", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromScale(1.4, 0.16), Rotation = -12, BackgroundColor3 = WHITE, BackgroundTransparency = 0.45 })
		make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(90, 255, 180)), ColorSequenceKeypoint.new(0.5, rgb(110, 200, 255)), ColorSequenceKeypoint.new(1, rgb(200, 120, 255)) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(0.7, 0.4), NumberSequenceKeypoint.new(1, 1) }) }, aurora)
		Juice.onFrame(aurora, function(t)
			aurora.Rotation = -12 + math.sin(t * 0.5) * 3
		end)
		local lake = frame(art, { Name = "Lake", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.24), BackgroundColor3 = rgb(210, 245, 255), BackgroundTransparency = 0.2 })
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(235, 252, 255), rgb(130, 200, 240)) }, lake)
		for i = 1, 3 do
			frame(lake, { Name = "Glint", Position = UDim2.fromScale(0.1 + r:NextNumber() * 0.5, i * 0.25), Size = UDim2.new(0.3, 0, 0, math.max(1, 2 * k)), BackgroundColor3 = WHITE, BackgroundTransparency = 0.3 })
		end
		for _ = 1, low and 4 or 7 do
			local px = (10 + r:NextNumber() * 26) * k
			local c = frame(art, { Name = "Crystal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.08 + r:NextNumber() * 0.84, 0.3 + r:NextNumber() * 0.42), Size = UDim2.fromOffset(px, px * 1.6), Rotation = 45, BackgroundColor3 = rgb(200, 240, 255), BackgroundTransparency = 0.7 })
			make("UIStroke", { Thickness = math.max(1, 1.5 * k), Color = WHITE, Transparency = 0.3 }, c)
		end
		for _ = 1, low and 8 or 16 do
			twinkle(dot(art, r:NextNumber(), r:NextNumber() * 0.75, math.max(2, (2 + r:NextNumber() * 3) * k), WHITE, 0.2), r, 0.15)
		end
	end,
}

-- Junk: Ember Caldera. Charcoal rock, a lava glow below, volcano peaks, glowing cracks, embers.
BIOME.Junk = {
	name = "Ember Caldera",
	top = rgb(44, 30, 28),
	bottom = rgb(110, 30, 20),
	accent = rgb(255, 150, 50),
	plate = rgb(30, 14, 10),
	draw = function(art, k, r, low)
		local glow = frame(art, { Name = "LavaGlow", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = rgb(255, 110, 30) })
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.15) }, glow)
		for _, p in ipairs({ { 0.18, 0.92, 0.5 }, { 0.8, 0.95, 0.6 }, { 0.5, 1.02, 0.45 } }) do
			local peak = frame(art, { Name = "Peak", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[1], p[2]), Size = UDim2.fromScale(p[3], p[3]), Rotation = 45, BackgroundColor3 = rgb(28, 18, 16) })
			make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, peak)
			frame(peak, { Name = "Lava", Size = UDim2.fromScale(0.16, 0.16), BackgroundColor3 = rgb(255, 140, 40) })
		end
		for _ = 1, low and 3 or 5 do
			local x, y = 0.1 + r:NextNumber() * 0.8, 0.12 + r:NextNumber() * 0.5
			for seg = 0, 2 do
				frame(art, { Name = "Crack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x + seg * 0.035, y + seg * 0.03), Size = UDim2.fromOffset(math.max(1, 2 * k), (14 + r:NextNumber() * 10) * k), Rotation = (seg % 2 == 0) and 30 or -25, BackgroundColor3 = rgb(255, 120, 40), BackgroundTransparency = 0.25 })
			end
		end
		for _ = 1, low and 6 or 12 do
			local e = dot(art, r:NextNumber(), 0.2 + r:NextNumber() * 0.75, math.max(2, (2 + r:NextNumber() * 3) * k), rgb(255, 170, 60), 0.1)
			local x0, speed, phase = e.Position.X.Scale, 0.04 + r:NextNumber() * 0.05, r:NextNumber()
			Juice.onFrame(e, function(t)
				local a = (t * speed + phase) % 1
				e.Position = UDim2.fromScale(x0 + math.sin(t * 2 + phase * 6) * 0.01, 1 - a)
				e.BackgroundTransparency = 0.1 + 0.9 * a
			end)
		end
	end,
}

-- Robo: Cosmic Void. Deep space, stars, a ringed planet and faint circuit lines.
BIOME.Robo = {
	name = "Cosmic Void",
	top = rgb(40, 30, 110),
	bottom = rgb(6, 6, 22),
	accent = rgb(110, 230, 255),
	plate = rgb(8, 8, 30),
	draw = function(art, k, r, low)
		blob(art, 0.3, 0.75, 0.9, rgb(150, 70, 220), 0.85, "Nebula")
		blob(art, 0.75, 0.3, 0.7, rgb(60, 120, 255), 0.88, "Nebula")
		local planet = blob(art, 0.76, 0.17, 0.26, rgb(255, 150, 110), 0, "Planet")
		make("UIGradient", { Rotation = 45, Color = ColorSequence.new(rgb(255, 190, 140), rgb(170, 60, 90)) }, planet)
		local ring = frame(art, { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.76, 0.17), Size = UDim2.fromScale(0.44, 0.05), Rotation = -18, BackgroundTransparency = 1 })
		corner(ring)
		make("UIStroke", { Thickness = math.max(1, 3 * k), Color = rgb(255, 220, 170), Transparency = 0.15 }, ring)
		for i = 1, 3 do
			local y = 0.55 + i * 0.1
			frame(art, { Name = "Trace", Position = UDim2.fromScale(0, y), Size = UDim2.new(0.35 + r:NextNumber() * 0.3, 0, 0, math.max(1, 1.5 * k)), BackgroundColor3 = rgb(110, 230, 255), BackgroundTransparency = 0.55 })
			dot(art, 0.35 + r:NextNumber() * 0.3, y, math.max(3, 6 * k), rgb(110, 230, 255), 0.3)
		end
		for _ = 1, low and 12 or 24 do
			twinkle(dot(art, r:NextNumber(), r:NextNumber(), math.max(1, (1 + r:NextNumber() * 3) * k), WHITE, 0.15), r, 0.1)
		end
	end,
}

-- Spooky: Midnight Mall. A dark purple sky, a low moon, the mall's skyline with neon windows, fog.
BIOME.Spooky = {
	name = "Midnight Mall",
	top = rgb(70, 36, 110),
	bottom = rgb(14, 8, 28),
	accent = rgb(255, 90, 210),
	plate = rgb(20, 10, 36),
	draw = function(art, k, r, low)
		blob(art, 0.74, 0.16, 0.3, rgb(250, 240, 210), 0.05, "Moon")
		blob(art, 0.74, 0.16, 0.5, rgb(250, 240, 210), 0.88, "MoonGlow")
		local x = -0.02
		while x < 1 do
			local w, hgt = 0.14 + r:NextNumber() * 0.12, 0.16 + r:NextNumber() * 0.2
			local b = frame(art, { Name = "Building", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(x, 1), Size = UDim2.fromScale(w, hgt), BackgroundColor3 = rgb(24, 14, 40) })
			for _ = 1, low and 2 or 4 do
				local neon = (r:NextNumber() < 0.5) and rgb(255, 90, 210) or rgb(90, 230, 255)
				frame(b, { Name = "Window", Position = UDim2.fromScale(0.15 + r:NextNumber() * 0.55, 0.12 + r:NextNumber() * 0.6), Size = UDim2.fromOffset(math.max(2, 7 * k), math.max(2, 7 * k)), BackgroundColor3 = neon, BackgroundTransparency = r:NextNumber() * 0.4 })
			end
			x += w + 0.01
		end
		local fog = frame(art, { Name = "Fog", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.2), BackgroundColor3 = rgb(200, 170, 230) })
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.55) }, fog)
		for _ = 1, low and 4 or 8 do
			twinkle(dot(art, r:NextNumber(), r:NextNumber() * 0.45, math.max(1, 3 * k), WHITE, 0.3), r, 0.2)
		end
	end,
}
CardBacks.Biomes = BIOME

-- The rarity foil over biome art: how strongly it tints (Common is matte: no foil).
local FOIL = { Rare = 0.8, Epic = 0.76, Mythic = 0.72, Legendary = 0.7, Secret = 0.66 }

function CardBacks.dress(back, rarity, family)
	if not back or not back.Parent then
		return nil
	end
	local biome = CardBacks.ByBiome and BIOME[family] or nil
	local look = CardBacks.ByRarity and LOOK[rarity] or nil
	if not look and not biome then
		return nil -- (the classic back)
	end
	if not look then
		-- matte, in the biome's own colours (a Common, or rarity foil switched off)
		look = { top = biome.top, bottom = biome.bottom, trim = biome.accent, edge = biome.accent:Lerp(WHITE, 0.35), letters = CREAM }
		rarity = "Common"
	end
	if dressed[back] then
		return dressed[back]
	end
	local rank = RANK[rarity] or 1
	local low = lowGraphics()
	local w = back.Parent:IsA("GuiObject") and back.Parent.Size.X.Offset or 0
	local k = (w > 0 and w or 300) / 300 -- 1 for the big single card, about 0.47 in a 10-pack fan
	back:SetAttribute("KeepColors", true) -- (the cozy menu colours leave the backs alone)

	-- the whole look lives in one group that fades in when the card wakes up
	local trim = make("CanvasGroup", { Name = "RarityBack", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, GroupTransparency = 1 }, back)
	corner(trim, math.floor(16 * k + 0.5))
	local body = make("UIGradient", { Rotation = 90, Color = ColorSequence.new(look.top, look.bottom) }, trim)
	local spin = {} -- things that turn slowly: { inst, degrees per second }

	if biome then
		-- the biome's art, then the rarity's foil over it
		body.Color = ColorSequence.new(biome.top, biome.bottom)
		local art = frame(trim, { Name = "BiomeArt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		local seed = 0
		for i = 1, #family do
			seed = seed * 31 + string.byte(family, i)
		end
		biome.draw(art, k, Random.new(seed % 100000), low)
		local foil = CardBacks.ByRarity and FOIL[rarity]
		if foil then
			local tint = frame(trim, { Name = "Foil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = foil })
			if rarity == "Secret" then
				table.insert(spin, { make("UIGradient", { Color = RAINBOW, Rotation = 30 }, tint), 30 })
			else
				make("UIGradient", {
					Rotation = 35,
					Color = ColorSequence.new(look.trim:Lerp(WHITE, 0.25), look.trim),
					Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) }),
				}, tint)
			end
			if rarity == "Legendary" then
				local lattice = frame(trim, { Name = "GoldLattice", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.88 })
				stripes(lattice, look.trim, look.bottom, 9, 45)
			end
		end
	elseif rarity == "Secret" then
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
	if rank >= 4 or biome then
		local plate = frame(trim, { Name = "Plate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.46), BackgroundColor3 = biome and biome.plate or look.bottom, BackgroundTransparency = biome and 0.25 or 0.2 })
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
	if (rank >= 3 or (biome and rank >= 2)) and not low then
		Juice.shine(trim, ({ [2] = 3.8, [3] = 3.2, [4] = 2.6, [5] = 2.1, [6] = 1.8 })[rank] or 3, UDim.new(0, math.floor(16 * k + 0.5)))
	end

	if #spin > 0 then
		Juice.onFrame(trim, function(_, dt)
			for _, sp in ipairs(spin) do
				sp[1].Rotation = (sp[1].Rotation + sp[2] * (dt or 0)) % 360
			end
		end)
	end

	local state = { trim = trim, rank = rank, rarity = rarity, look = look, k = k, awake = false, biome = biome }
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

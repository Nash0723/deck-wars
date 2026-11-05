-- Pack art: every pack on the shelf has its own look, and its own scene behind it when you open it.
-- GUI only (Frames, gradients and strokes; no uploaded images), client only.
--
--   Brawl Pack       "foil"      classic crimped foil pack, gold DW crest, lightning, spotlights
--   Sugar Rush       "wrapper"   striped candy wrapper with frilled ends and sprinkles, candy hills
--   Scrap Heap       "crate"     riveted tin with a hazard band and rust, scrap piles and embers
--   Storm Front      "cloud"     frosted pouch with a cloud top and a lightning bolt, rain and thunder
--   Burrow Bunch     "sack"      tied burlap seed sack with leaves and a paw stamp, grass and fireflies
--   Midnight Mall    "bag"       neon shopping bag with peeking eyes, a dark mall row and fog
--   Overclock        "cartridge" circuit cartridge with grip ridges and LED meter, a neon grid floor
--
-- None of it uses rarity colours: nothing in the pack or the scene tells you what is inside.
--
--   PackArt.design(pack)                 -> the design table for a Packs.luau def (or nil = Brawl)
--   PackArt.build(parent, pack, count, opts) -> the pack Frame (240 x 340, AnchorPoint 0.5, 0.5)
--        opts.static = true: no turning mascot (used for the two halves after a slash)
--   PackArt.scene(parent, pack)          -> scene { root, tint(color, amount, time), burst(x, y, angle), setCalm(bool) }
--   PackArt.burst(parent, pack, sx, sy, angle) -- the pack's own burst where it was cut
--   PackArt.cardBack(parent)             -> the Deck Wars card back (also used by the reveal)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local here = script.Parent
local Packs = require(here:WaitForChild("Packs"))
local DeckWars = ReplicatedStorage:WaitForChild("DeckWars")
local CreatureBuilder = require(DeckWars:WaitForChild("CreatureBuilder"))
local Juice = require(DeckWars:WaitForChild("Juice"))
local Settings = nil
pcall(function()
	Settings = require(DeckWars:WaitForChild("Settings"))
end)

local make, tween, rgb = Juice.make, Juice.tween, Juice.rgb
local WHITE = rgb(255, 255, 255)
local INK = rgb(18, 14, 28)

local PackArt = {}

PackArt.Width, PackArt.Height = 240, 340

local function c3(v)
	return rgb(v[1], v[2], v[3])
end

local function lowGraphics()
	return Settings ~= nil and Settings.get("graphics") == "Low"
end

-- Every design: shape, font, where the dotted cut guide sits (0..1 down the pack) and its tilt,
-- the scene (sky top/bottom, scenery, ambient bits) and the burst when it is cut.
PackArt.Designs = {
	brawl = { shape = "foil", font = Enum.Font.LuckiestGuy, cutY = 0.2, cutAngle = -6, sky = { { 38, 20, 78 }, { 8, 6, 22 } }, scenery = "spotlights", ambient = "sparks", burst = "sparks", cutSound = { "slap", 0.8 } },
	snack = { shape = "wrapper", font = Enum.Font.FredokaOne, cutY = 0.17, cutAngle = -10, sky = { { 120, 40, 70 }, { 40, 12, 30 } }, scenery = "hills", ambient = "sprinkles", burst = "candy", cutSound = { "pop", 0.7 } },
	junk = { shape = "crate", font = Enum.Font.SpecialElite, cutY = 0.21, cutAngle = 4, sky = { { 30, 62, 64 }, { 10, 16, 18 } }, scenery = "scrap", ambient = "embers", burst = "bolts", cutSound = { "bonk", 0.7 } },
	weather = { shape = "cloud", font = Enum.Font.Michroma, cutY = 0.24, cutAngle = -4, sky = { { 30, 56, 120 }, { 6, 12, 34 } }, scenery = "clouds", ambient = "rain", burst = "zap", cutSound = { "boom", 1.4 } },
	critter = { shape = "sack", font = Enum.Font.DenkOne, cutY = 0.2, cutAngle = 8, sky = { { 36, 70, 52 }, { 8, 22, 16 } }, scenery = "grass", ambient = "fireflies", burst = "leaves", cutSound = { "burrow", 1.2 } },
	spooky = { shape = "bag", font = Enum.Font.Creepster, cutY = 0.22, cutAngle = -8, sky = { { 50, 24, 86 }, { 8, 4, 18 } }, scenery = "mall", ambient = "wisps", burst = "ghosts", cutSound = { "wind", 1.3 } },
	robo = { shape = "cartridge", font = Enum.Font.Sarpanch, cutY = 0.19, cutAngle = 0, sky = { { 24, 30, 52 }, { 4, 6, 14 } }, scenery = "grid", ambient = "data", burst = "circuit", cutSound = { "beam", 1.5 } },
}

function PackArt.design(pack)
	pack = pack or Packs.get(nil)
	return PackArt.Designs[pack.id] or PackArt.Designs.brawl, pack
end

local function colors(pack)
	return c3(pack.color), c3(pack.dark), c3(pack.accent)
end

-- A small seeded random so every pack's sprinkles and rivets sit in the same place each time.
local function seeded(seed)
	local s = seed % 2147483647
	if s <= 0 then
		s = 1
	end
	return function()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function corner(p, r)
	return make("UICorner", { CornerRadius = r == "round" and UDim.new(1, 0) or UDim.new(0, r) }, p)
end

local function frame(parent, props)
	local f = make("Frame", { BorderSizePixel = 0 }, parent)
	for k, v in pairs(props) do
		f[k] = v
	end
	return f
end

local function vgrad(parent, a, b, rot)
	return make("UIGradient", { Rotation = rot or 90, Color = ColorSequence.new(a, b) }, parent)
end

-- Hard-edged stripes as a gradient (n stripes of two colours).
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

local function text(parent, str, props)
	local l = make("TextLabel", { BackgroundTransparency = 1, Text = str, TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = WHITE }, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end

-- The pack's mascot turning slowly in a window (themed packs only).
local function mascotView(parent, pack, props)
	if not (pack.mascot and CreatureBuilder.has(pack.mascot)) then
		return nil
	end
	local model = CreatureBuilder.build(pack.mascot)
	if not model then
		return nil
	end
	local vp = make("ViewportFrame", { Name = "Mascot", BackgroundTransparency = 1, Ambient = rgb(170, 165, 185), LightColor = rgb(255, 246, 230), LightDirection = Vector3.new(-0.5, -1, -0.7) }, parent)
	for k, v in pairs(props) do
		vp[k] = v
	end
	model.Parent = vp
	local info = CreatureBuilder.info(pack.mascot) or { height = 4, width = 3, depth = 3 }
	local h = math.max(info.height, 0.5)
	local look = Vector3.new(0, h * 0.5, 0)
	local dist = math.max(h * 2.1, math.max(info.width, info.depth) * 1.4) + 0.5
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	Juice.onFrame(vp, function(t)
		local yaw = math.sin(t * 0.7) * 0.45
		cam.CFrame = CFrame.lookAt(look + Vector3.new(math.sin(yaw) * dist, dist * 0.18, -math.cos(yaw) * dist), look)
	end)
	return vp
end

-- The window the mascot stands in; the glyph shows instead when there is no mascot (or on a half).
local function window(body, pack, opts, props)
	local main, dark, accent = colors(pack)
	local w = frame(body, { Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = main:Lerp(WHITE, 0.3), BackgroundTransparency = 0.25 })
	for k, v in pairs(props) do
		w[k] = v
	end
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.05, 0.6) }, w)
	make("UIStroke", { Thickness = 3, Color = accent, Transparency = 0.15 }, w)
	local vp = (not opts.static) and mascotView(w, pack, { Size = UDim2.fromScale(1, 1), ZIndex = w.ZIndex + 1 }) or nil
	if not vp then
		local g = text(w, pack.glyph or "DW", { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.6), TextColor3 = WHITE, ZIndex = w.ZIndex + 1 })
		make("UIStroke", { Thickness = 3, Color = dark }, g)
	end
	return w
end

---------------------------------------------------------------------------
-- The seven shapes
---------------------------------------------------------------------------
local Shapes = {}

-- Brawl Pack: crimped foil, gold crest, lightning.
function Shapes.foil(root, pack, design, opts)
	local main, dark, accent = colors(pack)
	local body = frame(root, { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
	corner(body, 14)
	local foil = make("UIGradient", {
		Rotation = 35,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, dark),
			ColorSequenceKeypoint.new(0.45, main:Lerp(dark, 0.2)),
			ColorSequenceKeypoint.new(0.55, main:Lerp(WHITE, 0.22)),
			ColorSequenceKeypoint.new(1, dark),
		}),
	}, body)
	make("UIStroke", { Thickness = 4, Color = accent, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	if not opts.static then
		Juice.onFrame(body, function(t)
			foil.Offset = Vector2.new(math.sin(t * 0.9) * 0.25, 0)
		end)
	end
	for _, top in ipairs({ true, false }) do
		local crimp = frame(body, { Name = top and "Top" or "Bottom", AnchorPoint = Vector2.new(0, top and 0 or 1), Position = UDim2.fromScale(0, top and 0 or 1), Size = UDim2.new(1, 0, 0, top and 40 or 22), BackgroundColor3 = accent })
		corner(crimp, 14)
		vgrad(crimp, accent:Lerp(WHITE, 0.45), accent:Lerp(dark, 0.3))
		for k = 0, 19 do
			frame(crimp, { Name = "Tooth", Position = UDim2.new(k / 20, 3, 0, 3), Size = UDim2.new(0, 2, 1, -6), BackgroundColor3 = dark, BackgroundTransparency = 0.6 })
		end
	end
	text(body, "DECK WARS", { Name = "Brand", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 21), Size = UDim2.fromOffset(160, 16), TextColor3 = dark, Font = Enum.Font.GothamBlack })
	-- lightning behind the crest
	for k, seg in ipairs({ { 0.42, 0.3, 30 }, { 0.55, 0.42, -40 }, { 0.47, 0.55, 32 } }) do
		frame(body, { Name = "Bolt" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(seg[1], seg[2]), Size = UDim2.fromOffset(16, 76), BackgroundColor3 = accent, BackgroundTransparency = 0.55, Rotation = seg[3] })
	end
	local crest = text(body, "DW", { Name = "Emblem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(170, 110), Font = Enum.Font.LuckiestGuy })
	vgrad(crest, rgb(255, 238, 170), rgb(255, 156, 40))
	make("UIStroke", { Thickness = 3, Color = INK }, crest)
	local r = seeded(7)
	for k = 1, 6 do
		text(body, "★", { Name = "Glint", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.15 + r() * 0.7, 0.18 + r() * 0.55), Size = UDim2.fromOffset(12 + r() * 10, 12 + r() * 10), TextColor3 = accent:Lerp(WHITE, 0.5), TextTransparency = 0.25 })
	end
	return body
end

-- Sugar Rush: a striped candy wrapper with frilled ends and sprinkles.
function Shapes.wrapper(root, pack, design, opts)
	local main, dark, accent = colors(pack)
	-- the frills (zigzag teeth) poke out above and below the body
	for _, top in ipairs({ true, false }) do
		local row = frame(root, { Name = top and "FrillTop" or "FrillBottom", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, top and 0 or 1, top and 6 or -6), Size = UDim2.new(1, -10, 0, 24), BackgroundTransparency = 1 })
		for k = 0, 10 do
			frame(row, { Name = "Tooth", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(k / 10, 0, 0.5, top and -4 or 4), Size = UDim2.fromOffset(20, 20), Rotation = 45, BackgroundColor3 = accent:Lerp(main, 0.25) })
		end
	end
	local body = frame(root, { Name = "Body", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 1, -20), BackgroundColor3 = WHITE })
	corner(body, 26)
	stripes(body, main, main:Lerp(WHITE, 0.28), 11, 45)
	make("UIStroke", { Thickness = 4, Color = dark, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	-- the twisted bands near each end
	for _, y in ipairs({ 0.1, 0.9 }) do
		local band = frame(body, { Name = "Twist", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, y), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = accent })
		vgrad(band, accent:Lerp(WHITE, 0.5), accent:Lerp(dark, 0.25))
		for k = 0, 7 do
			frame(band, { Name = "Pleat", Position = UDim2.new(k / 8, 6, 0, 2), Size = UDim2.new(0, 3, 1, -4), Rotation = 20, BackgroundColor3 = dark, BackgroundTransparency = 0.55 })
		end
	end
	local r = seeded(31)
	local sprinkle = { rgb(255, 255, 255), accent, rgb(120, 220, 255), rgb(255, 150, 200), rgb(170, 255, 140) }
	for k = 1, 22 do
		local s = frame(body, { Name = "Sprinkle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.08 + r() * 0.84, 0.18 + r() * 0.66), Size = UDim2.fromOffset(4, 11), Rotation = r() * 180, BackgroundColor3 = sprinkle[1 + math.floor(r() * #sprinkle)] })
		corner(s, "round")
	end
	local w = window(body, pack, opts, { Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(150, 150) })
	corner(w, "round")
	local ring = frame(body, { Name = "Lolly", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(166, 166), BackgroundTransparency = 1 })
	corner(ring, "round")
	make("UIStroke", { Thickness = 5, Color = WHITE, Transparency = 0.15 }, ring)
	return body
end

-- Scrap Heap: a riveted tin with a hazard band and rust.
function Shapes.crate(root, pack, design, opts)
	local main, dark, accent = colors(pack)
	local body = frame(root, { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
	corner(body, 8)
	make("UIGradient", { Rotation = 0, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, dark), ColorSequenceKeypoint.new(0.3, main:Lerp(rgb(150, 160, 160), 0.45)), ColorSequenceKeypoint.new(0.55, main:Lerp(WHITE, 0.25)), ColorSequenceKeypoint.new(1, dark) }) }, body)
	make("UIStroke", { Thickness = 5, Color = rgb(40, 44, 44), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	-- the lid plate with rivets
	local lid = frame(body, { Name = "Top", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = rgb(110, 118, 118) })
	corner(lid, 8)
	vgrad(lid, rgb(170, 176, 172), rgb(80, 86, 86))
	for _, x in ipairs({ 0.06, 0.94 }) do
		for _, y in ipairs({ 0.3, 0.72 }) do
			local rv = frame(lid, { Name = "Rivet", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = rgb(200, 200, 190) })
			corner(rv, "round")
			make("UIStroke", { Thickness = 1, Color = rgb(40, 40, 40) }, rv)
		end
	end
	text(lid, "DECK WARS · SCRAP CO.", { Name = "Brand", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(170, 14), Font = Enum.Font.SpecialElite, TextColor3 = rgb(40, 40, 40) })
	-- rust and dents
	local r = seeded(53)
	for k = 1, 6 do
		local rust = frame(body, { Name = "Rust", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.1 + r() * 0.8, 0.2 + r() * 0.7), Size = UDim2.fromOffset(18 + r() * 34, 10 + r() * 22), Rotation = r() * 90, BackgroundColor3 = rgb(170, 90, 40), BackgroundTransparency = 0.55 + r() * 0.2 })
		corner(rust, "round")
	end
	-- hazard band
	local band = frame(body, { Name = "Hazard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = WHITE })
	stripes(band, rgb(30, 30, 30), accent, 14, 0)
	make("UIStroke", { Thickness = 2, Color = rgb(30, 30, 30) }, band)
	local w = window(body, pack, opts, { Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(176, 140) })
	corner(w, 6)
	for _, x in ipairs({ 0.04, 0.96 }) do
		for _, y in ipairs({ 0.06, 0.94 }) do
			local bolt = frame(w, { Name = "Bolt", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = rgb(210, 205, 190), ZIndex = w.ZIndex + 2 })
			corner(bolt, "round")
		end
	end
	return body
end

-- Storm Front: a frosted pouch with a cloud top and a lightning bolt.
function Shapes.cloud(root, pack, design, opts)
	local main, dark, accent = colors(pack)
	local r = seeded(71)
	-- cloud puffs along the top (behind the body)
	for k, p in ipairs({ { 0.12, 50 }, { 0.32, 74 }, { 0.55, 88 }, { 0.78, 70 }, { 0.92, 52 } }) do
		local puff = frame(root, { Name = "Puff" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(p[1], 0, 0, 20), Size = UDim2.fromOffset(p[2], p[2]), BackgroundColor3 = accent:Lerp(WHITE, 0.4) })
		corner(puff, "round")
		vgrad(puff, WHITE, accent)
	end
	local body = frame(root, { Name = "Body", Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 1, -18), BackgroundColor3 = WHITE })
	corner(body, 34)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, accent:Lerp(main, 0.35)), ColorSequenceKeypoint.new(0.45, main), ColorSequenceKeypoint.new(1, dark) }) }, body)
	make("UIStroke", { Thickness = 4, Color = accent, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	-- rain streaks inside (they fall while the pack is in your hands)
	local rain = frame(body, { Name = "Rain", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true })
	local drops = {}
	for k = 1, 12 do
		local d = frame(rain, { Name = "Drop", Position = UDim2.fromScale(r(), r()), Size = UDim2.fromOffset(2, 16), Rotation = 12, BackgroundColor3 = accent:Lerp(WHITE, 0.5), BackgroundTransparency = 0.55 })
		drops[k] = { d = d, x = d.Position.X.Scale, y = d.Position.Y.Scale, v = 0.5 + r() * 0.4 }
	end
	if not opts.static then
		Juice.onFrame(rain, function(_, dt)
			for _, e in ipairs(drops) do
				e.y += e.v * dt
				if e.y > 1.05 then
					e.y -= 1.1
				end
				e.d.Position = UDim2.fromScale(e.x, e.y)
			end
		end)
	end
	-- the bolt
	local yellow = rgb(255, 230, 90)
	for k, seg in ipairs({ { 0.56, 0.2, 24, 60 }, { 0.46, 0.33, -60, 54 }, { 0.5, 0.45, 24, 66 } }) do
		local b = frame(body, { Name = "Bolt" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(seg[1], seg[2]), Size = UDim2.fromOffset(14, seg[4]), Rotation = seg[3], BackgroundColor3 = yellow })
		make("UIStroke", { Thickness = 2, Color = dark }, b)
	end
	local w = window(body, pack, opts, { Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(160, 130) })
	corner(w, 28)
	text(body, "DECK WARS", { Name = "Brand", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 26), Size = UDim2.fromOffset(140, 14), Font = Enum.Font.Michroma, TextColor3 = WHITE, TextTransparency = 0.15 })
	return body
end

-- Burrow Bunch: a tied burlap seed sack with leaves and a paw stamp.
function Shapes.sack(root, pack, design, opts)
	local main, dark, accent = colors(pack)
	local burlap = rgb(196, 160, 104)
	-- the ruffled top above the tie
	local ruffle = frame(root, { Name = "Ruffle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.8, 0, 0, 52), BackgroundColor3 = burlap })
	corner(ruffle, 22)
	vgrad(ruffle, burlap:Lerp(WHITE, 0.2), burlap:Lerp(rgb(90, 60, 30), 0.3))
	make("UIStroke", { Thickness = 3, Color = rgb(110, 76, 40) }, ruffle)
	local body = frame(root, { Name = "Body", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 1, -58), BackgroundColor3 = WHITE })
	corner(body, 46)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(burlap:Lerp(WHITE, 0.12), burlap:Lerp(rgb(90, 60, 30), 0.35)) }, body)
	make("UIStroke", { Thickness = 4, Color = rgb(110, 76, 40), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	-- the weave
	for k = 1, 9 do
		frame(body, { Name = "Weave", Position = UDim2.new(0, 10, k / 10, 0), Size = UDim2.new(1, -20, 0, 1), BackgroundColor3 = rgb(120, 86, 46), BackgroundTransparency = 0.7 })
	end
	for k = 1, 7 do
		frame(body, { Name = "Weave", Position = UDim2.new(k / 8, 0, 0, 10), Size = UDim2.new(0, 1, 1, -20), BackgroundColor3 = rgb(120, 86, 46), BackgroundTransparency = 0.78 })
	end
	-- the twine tie
	local tie = frame(root, { Name = "Tie", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.new(0.74, 0, 0, 14), BackgroundColor3 = rgb(140, 96, 52) })
	corner(tie, 7)
	vgrad(tie, rgb(190, 140, 80), rgb(110, 70, 36))
	local bow = frame(tie, { Name = "Knot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.72, 0.5), Size = UDim2.fromOffset(18, 18), Rotation = 45, BackgroundColor3 = rgb(170, 120, 64) })
	corner(bow, 4)
	-- leaves
	for k, l in ipairs({ { 0.14, 0.26, -30 }, { 0.86, 0.3, 35 }, { 0.2, 0.86, 20 } }) do
		local leaf = frame(body, { Name = "Leaf" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(l[1], l[2]), Size = UDim2.fromOffset(22, 44), Rotation = l[3], BackgroundColor3 = main })
		corner(leaf, "round")
		vgrad(leaf, main:Lerp(WHITE, 0.25), dark, 0)
		frame(leaf, { Name = "Vein", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 0.8, 0), BackgroundColor3 = dark, BackgroundTransparency = 0.3 })
	end
	-- the paw stamp
	local paw = frame(body, { Name = "Paw", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.8, 0.85), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Rotation = 14 })
	local pad = frame(paw, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.65), Size = UDim2.fromOffset(20, 16), BackgroundColor3 = dark, BackgroundTransparency = 0.25 })
	corner(pad, "round")
	for k, t in ipairs({ { 0.2, 0.3 }, { 0.4, 0.12 }, { 0.62, 0.12 }, { 0.82, 0.3 } }) do
		local toe = frame(paw, { Name = "Toe" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(t[1], t[2]), Size = UDim2.fromOffset(9, 10), BackgroundColor3 = dark, BackgroundTransparency = 0.25 })
		corner(toe, "round")
	end
	local w = window(body, pack, opts, { Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(150, 136) })
	corner(w, 40)
	return body
end

-- Midnight Mall: a neon shopping bag with eyes peeking over the top.
function Shapes.bag(root, pack, design, opts)
	local main, dark, accent = colors(pack)
	-- handles (behind the body)
	for k, x in ipairs({ 0.32, 0.68 }) do
		local h = frame(root, { Name = "Handle" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, 30), Size = UDim2.fromOffset(52, 64), BackgroundTransparency = 1 })
		corner(h, "round")
		make("UIStroke", { Thickness = 6, Color = dark:Lerp(INK, 0.3) }, h)
	end
	local body = frame(root, { Name = "Body", Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundColor3 = WHITE })
	corner(body, 10)
	vgrad(body, main:Lerp(dark, 0.3), dark:Lerp(INK, 0.5))
	local neon = make("UIStroke", { Thickness = 4, Color = accent, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	-- the folded top edge
	local fold = frame(body, { Name = "Top", Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = main })
	corner(fold, 10)
	vgrad(fold, main:Lerp(WHITE, 0.15), main:Lerp(dark, 0.4))
	-- eyes peeking out of the bag
	local eyes = {}
	for k, x in ipairs({ 0.4, 0.6 }) do
		local eye = frame(root, { Name = "Eye" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, 36), Size = UDim2.fromOffset(20, 26), BackgroundColor3 = accent:Lerp(WHITE, 0.6) })
		corner(eye, "round")
		local pupil = frame(eye, { Name = "Pupil", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(8, 10), BackgroundColor3 = INK })
		corner(pupil, "round")
		eyes[k] = eye
	end
	-- the moon logo
	local moon = frame(body, { Name = "Moon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.82, 0.2), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = accent })
	corner(moon, "round")
	local bite = frame(moon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.75, 0.38), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = main:Lerp(dark, 0.4) })
	corner(bite, "round")
	local w = window(body, pack, opts, { Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(160, 140) })
	corner(w, 70)
	if not opts.static then
		-- the neon trim flickers now and then, the eyes blink
		Juice.onFrame(body, function(t)
			local flick = (math.sin(t * 13) > 0.97 or math.sin(t * 7.3 + 1) > 0.985) and 0.75 or 0
			neon.Transparency = flick
			local blink = (t % 3.7) < 0.14
			for _, e in ipairs(eyes) do
				e.Size = UDim2.fromOffset(20, blink and 3 or 26)
			end
		end)
	end
	return body
end

-- Overclock: a circuit cartridge with grip ridges, an LED meter and a porthole.
function Shapes.cartridge(root, pack, design, opts)
	local main, dark, accent = colors(pack)
	local body = frame(root, { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
	corner(body, 12)
	make("UIGradient", { Rotation = 0, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, dark), ColorSequenceKeypoint.new(0.5, main), ColorSequenceKeypoint.new(1, dark) }) }, body)
	make("UIStroke", { Thickness = 4, Color = rgb(20, 22, 32), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	-- grip ridges on the top
	local grip = frame(body, { Name = "Top", Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = dark })
	corner(grip, 12)
	for k = 0, 4 do
		frame(grip, { Name = "Ridge", Position = UDim2.new(0, 14, 0, 7 + k * 6), Size = UDim2.new(1, -28, 0, 3), BackgroundColor3 = main:Lerp(WHITE, 0.15), BackgroundTransparency = 0.2 })
	end
	-- circuit traces
	local r = seeded(97)
	for k = 1, 9 do
		local x, y = 0.08 + r() * 0.84, 0.18 + r() * 0.7
		local horiz = r() > 0.5
		local tr = frame(body, { Name = "Trace", Position = UDim2.fromScale(x, y), Size = horiz and UDim2.fromOffset(30 + r() * 40, 2) or UDim2.fromOffset(2, 30 + r() * 40), BackgroundColor3 = accent, BackgroundTransparency = 0.55 })
		local node = frame(tr, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = accent, BackgroundTransparency = 0.3 })
		corner(node, "round")
	end
	-- the porthole
	local w = window(body, pack, opts, { Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(150, 150) })
	corner(w, "round")
	local ring = frame(body, { Name = "Porthole", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(170, 170), BackgroundTransparency = 1 })
	corner(ring, "round")
	make("UIStroke", { Thickness = 8, Color = rgb(30, 34, 48) }, ring)
	-- LED meter
	local meter = frame(body, { Name = "Meter", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(150, 14), BackgroundColor3 = rgb(14, 16, 24) })
	corner(meter, 4)
	local leds = {}
	for k = 1, 8 do
		local led = frame(meter, { Name = "Led" .. k, Position = UDim2.new((k - 1) / 8, 3, 0, 3), Size = UDim2.new(1 / 8, -6, 1, -6), BackgroundColor3 = accent, BackgroundTransparency = 0.8 })
		corner(led, 2)
		leds[k] = led
	end
	if not opts.static then
		Juice.onFrame(meter, function(t)
			local lit = math.floor((t * 6) % 10)
			for k, led in ipairs(leds) do
				led.BackgroundTransparency = k <= lit and 0.05 or 0.8
			end
		end)
	end
	return body
end

-- The pack as a GUI Frame. Children others use: Body, Title, CutGuide, Count.
function PackArt.build(parent, pack, count, opts)
	opts = opts or {}
	local design
	design, pack = PackArt.design(pack)
	local main, dark, accent = colors(pack)
	count = count or 1
	local root = frame(parent, { Name = "Pack", AnchorPoint = Vector2.new(0.5, 0.5), Position = opts.position or UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PackArt.Width, PackArt.Height), BackgroundTransparency = 1, ZIndex = opts.zIndex or 10 })
	-- a 10-pack is a bundle: two more packs peek out behind it
	if count > 1 then
		for k = 2, 1, -1 do
			local s = frame(root, { Name = "Stack" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, k * 9, 0.5, -k * 7), Size = UDim2.fromScale(0.96, 0.96), Rotation = k * 3, BackgroundColor3 = dark:Lerp(main, 0.3 * k) })
			corner(s, 16)
			make("UIStroke", { Thickness = 3, Color = accent, Transparency = 0.4 }, s)
		end
	end
	local holder = frame(root, { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local body = Shapes[design.shape](holder, pack, design, opts)
	-- the name
	local title = string.upper((string.gsub(pack.name, " Pack$", "")))
	local titleLabel = text(body, title, { Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromOffset(212, 34), Font = design.font, TextColor3 = WHITE })
	make("UIStroke", { Thickness = 2.5, Color = dark:Lerp(INK, 0.4) }, titleLabel)
	local what = pack.family and (string.upper(pack.family) .. " PACK") or "BRAWL PACK"
	text(body, (count > 1 and (count .. " CARDS · ") or "1 CARD · ") .. what, { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.81), Size = UDim2.fromOffset(200, 15), Font = Enum.Font.GothamBold, TextColor3 = accent:Lerp(WHITE, 0.2) })
	if count > 1 then
		local badge = text(root, "x" .. count, { Name = "Count", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 62), Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 0, BackgroundColor3 = rgb(255, 84, 112), Rotation = 12, ZIndex = (opts.zIndex or 10) + 6, TextScaled = false, TextSize = 24 })
		corner(badge, "round")
		make("UIStroke", { Thickness = 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
	end
	-- the dotted cut guide
	if not opts.noGuide then
		local guide = frame(root, { Name = "CutGuide", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, design.cutY), Size = UDim2.new(1, 24, 0, 4), Rotation = design.cutAngle, BackgroundTransparency = 1, ZIndex = (opts.zIndex or 10) + 4 })
		for k = 0, 13 do
			frame(guide, { Name = "Dash", Position = UDim2.new(k / 14, 2, 0, 0), Size = UDim2.new(1 / 14, -6, 1, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.15 })
		end
		for _, side in ipairs({ 0, 1 }) do
			local tip = frame(guide, { Name = "Tip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(side, 0.5), Size = UDim2.fromOffset(10, 10), Rotation = 45, BackgroundColor3 = accent })
			corner(tip, 2)
		end
	end
	if not opts.static then
		Juice.shine(body, 2.6, UDim.new(0, 14))
	end
	return root
end

---------------------------------------------------------------------------
-- The card back (shared with the reveal)
---------------------------------------------------------------------------
function PackArt.cardBack(parent)
	local back = frame(parent, { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(32, 38, 74) })
	corner(back, 16)
	make("UIStroke", { Thickness = 6, Color = rgb(242, 230, 201) }, back)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(70, 80, 140), rgb(22, 24, 52)) }, back)
	local ring = frame(back, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.5), BackgroundTransparency = 1 })
	make("UIStroke", { Thickness = 5, Color = rgb(242, 230, 201) }, ring)
	corner(ring, 200)
	text(back, "DECK\nWARS", { Size = UDim2.fromScale(0.6, 0.25), Position = UDim2.fromScale(0.2, 0.375), TextColor3 = rgb(242, 230, 201), Font = Enum.Font.FredokaOne })
	return back
end

---------------------------------------------------------------------------
-- Scenes
---------------------------------------------------------------------------

-- Bits that drift across the scene (sparks, sprinkles, rain...). Positions are 0..1 of the screen.
local function particleSystem(root)
	local list = {}
	local sys = { list = list, rate = 1 }
	function sys.add(inst, p)
		p.inst = inst
		p.age = 0
		table.insert(list, p)
		if #list > 70 then
			local old = table.remove(list, 1)
			if old.inst.Parent then
				old.inst:Destroy()
			end
		end
	end
	function sys.step(dt)
		for i = #list, 1, -1 do
			local p = list[i]
			p.age += dt
			if p.age >= p.life or not p.inst.Parent then
				if p.inst.Parent then
					p.inst:Destroy()
				end
				table.remove(list, i)
			else
				p.vx = (p.vx or 0) + (p.ax or 0) * dt
				p.vy = (p.vy or 0) + (p.ay or 0) * dt
				p.x += p.vx * dt + (p.sway and math.sin(p.age * p.sway + (p.phase or 0)) * 0.02 * dt or 0)
				p.y += p.vy * dt
				p.inst.Position = UDim2.fromScale(p.x, p.y)
				if p.spin then
					p.inst.Rotation += p.spin * dt
				end
				local a = p.age / p.life
				local fade = math.min(1, p.age / 0.3, (1 - a) / 0.3)
				local base = p.alpha or 0
				local tr = 1 - (1 - base) * math.clamp(fade, 0, 1)
				if p.pulse then
					tr = 1 - (1 - tr) * (0.5 + 0.5 * math.sin(p.age * p.pulse + (p.phase or 0)))
				end
				if p.inst:IsA("TextLabel") then
					p.inst.TextTransparency = tr
				else
					p.inst.BackgroundTransparency = tr
				end
			end
		end
	end
	return sys
end

local Ambient = {}
function Ambient.sparks(sys, layer, pack, r)
	local _, _, accent = colors(pack)
	local f = frame(layer, { Name = "Spark", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = accent:Lerp(WHITE, r() * 0.6), BackgroundTransparency = 1 })
	corner(f, "round")
	sys.add(f, { x = r(), y = 1.02, vx = (r() - 0.5) * 0.02, vy = -(0.06 + r() * 0.08), life = 6 + r() * 4, alpha = 0.2, sway = 1.5, phase = r() * 6 })
	return 0.12
end
function Ambient.sprinkles(sys, layer, pack, r)
	local main, _, accent = colors(pack)
	local cols = { WHITE, accent, main:Lerp(WHITE, 0.4), rgb(120, 220, 255), rgb(170, 255, 140) }
	local f = frame(layer, { Name = "Sprinkle", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 14), Rotation = r() * 180, BackgroundColor3 = cols[1 + math.floor(r() * #cols)], BackgroundTransparency = 1 })
	corner(f, "round")
	sys.add(f, { x = r(), y = -0.03, vx = (r() - 0.5) * 0.03, vy = 0.07 + r() * 0.06, spin = (r() - 0.5) * 200, life = 14, alpha = 0.15 })
	return 0.16
end
function Ambient.embers(sys, layer, pack, r)
	local f = frame(layer, { Name = "Ember", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4 + r() * 3, 4 + r() * 3), Rotation = r() * 90, BackgroundColor3 = rgb(255, 140 + r() * 80, 40), BackgroundTransparency = 1 })
	sys.add(f, { x = 0.1 + r() * 0.8, y = 1.02, vx = (r() - 0.5) * 0.04, vy = -(0.08 + r() * 0.1), spin = (r() - 0.5) * 120, life = 5 + r() * 3, alpha = 0.1, sway = 3, phase = r() * 6, pulse = 9 })
	return 0.1
end
function Ambient.rain(sys, layer, pack, r)
	local _, _, accent = colors(pack)
	local f = frame(layer, { Name = "Rain", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 26 + r() * 18), Rotation = 14, BackgroundColor3 = accent:Lerp(WHITE, 0.5), BackgroundTransparency = 1 })
	sys.add(f, { x = r() * 1.2, y = -0.05, vx = -0.18, vy = 0.9 + r() * 0.4, life = 1.4, alpha = 0.5 })
	return 0.025
end
function Ambient.fireflies(sys, layer, pack, r)
	local f = frame(layer, { Name = "Firefly", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 5), BackgroundColor3 = rgb(220, 255, 120), BackgroundTransparency = 1 })
	corner(f, "round")
	make("UIStroke", { Thickness = 3, Color = rgb(200, 255, 100), Transparency = 0.6 }, f)
	sys.add(f, { x = r(), y = 0.45 + r() * 0.5, vx = (r() - 0.5) * 0.03, vy = (r() - 0.5) * 0.02, life = 6 + r() * 4, alpha = 0, sway = 1.2, phase = r() * 6, pulse = 3 })
	if r() < 0.3 then
		local main, dark = colors(pack)
		local leaf = frame(layer, { Name = "Leaf", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(9, 16), Rotation = r() * 180, BackgroundColor3 = main:Lerp(dark, r()), BackgroundTransparency = 1 })
		corner(leaf, "round")
		sys.add(leaf, { x = r(), y = -0.03, vx = 0.02, vy = 0.06, spin = 60, life = 16, alpha = 0.2, sway = 2, phase = r() * 6 })
	end
	return 0.35
end
function Ambient.wisps(sys, layer, pack, r)
	local main = colors(pack)
	local size = 160 + r() * 200
	local f = frame(layer, { Name = "Wisp", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size * 0.4), BackgroundColor3 = main:Lerp(WHITE, 0.5), BackgroundTransparency = 1 })
	corner(f, "round")
	local left = r() < 0.5
	sys.add(f, { x = left and -0.2 or 1.2, y = 0.55 + r() * 0.4, vx = (left and 1 or -1) * (0.03 + r() * 0.03), vy = 0, life = 18, alpha = 0.88 })
	return 0.9
end
function Ambient.data(sys, layer, pack, r)
	local _, _, accent = colors(pack)
	local l = text(layer, r() < 0.5 and "0" or "1", { Name = "Bit", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), Font = Enum.Font.Code, TextColor3 = accent, TextTransparency = 1 })
	sys.add(l, { x = r(), y = 1.02, vx = 0, vy = -(0.08 + r() * 0.08), life = 9, alpha = 0.35, pulse = 6, phase = r() * 6 })
	return 0.09
end

local Scenery = {}
function Scenery.spotlights(layer, pack)
	local _, _, accent = colors(pack)
	for k, s in ipairs({ { 0.22, 24 }, { 0.78, -24 }, { 0.5, 0 } }) do
		local cone = frame(layer, { Name = "Spotlight" .. k, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(s[1], -0.1), Size = UDim2.new(0, 260, 1.3, 0), Rotation = s[2], BackgroundColor3 = accent:Lerp(WHITE, 0.5) })
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }) }, cone)
		Juice.onFrame(cone, function(t)
			cone.Rotation = s[2] + math.sin(t * 0.5 + k) * 6
		end)
	end
	-- a crowd's heads along the bottom
	local r = seeded(5)
	for k = 0, 26 do
		local head = frame(layer, { Name = "Crowd", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(k / 26, 0, 1, -10 - r() * 26), Size = UDim2.fromOffset(70 + r() * 30, 80), BackgroundColor3 = rgb(6, 4, 14) })
		corner(head, "round")
	end
end
function Scenery.hills(layer, pack)
	local main, dark = colors(pack)
	for k, h in ipairs({ { 0.1, 520, 0.35 }, { 0.5, 700, 0.5 }, { 0.92, 560, 0.4 }, { 0.3, 460, 0.65 }, { 0.75, 480, 0.7 } }) do
		local hill = frame(layer, { Name = "Hill" .. k, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(h[1], 0, 1, -h[2] * 0.32), Size = UDim2.fromOffset(h[2], h[2]), BackgroundColor3 = main:Lerp(dark, h[3]):Lerp(rgb(10, 4, 10), 0.35) })
		corner(hill, "round")
	end
	for k, x in ipairs({ 0.16, 0.84 }) do
		frame(layer, { Name = "Stick" .. k, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(x, 0, 1, -60), Size = UDim2.fromOffset(8, 180), BackgroundColor3 = rgb(240, 230, 220), BackgroundTransparency = 0.4 })
		local pop = frame(layer, { Name = "Lolly" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 1, -240), Size = UDim2.fromOffset(96, 96), BackgroundColor3 = WHITE, BackgroundTransparency = 0.3 })
		corner(pop, "round")
		stripes(pop, main, WHITE, 9, 30)
	end
end
function Scenery.scrap(layer, pack)
	local r = seeded(11)
	for k = 1, 16 do
		frame(layer, { Name = "Scrap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(r(), 0, 1, -r() * 90), Size = UDim2.fromOffset(80 + r() * 160, 30 + r() * 80), Rotation = (r() - 0.5) * 60, BackgroundColor3 = rgb(10 + r() * 14, 18 + r() * 14, 20 + r() * 14) })
	end
	-- a crane hook hanging in
	frame(layer, { Name = "Cable", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.86, 0), Size = UDim2.new(0, 3, 0.36, 0), BackgroundColor3 = rgb(20, 26, 28) })
	local hook = frame(layer, { Name = "Hook", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.86, 0.36), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1 })
	corner(hook, "round")
	make("UIStroke", { Thickness = 6, Color = rgb(20, 26, 28) }, hook)
end
function Scenery.clouds(layer, pack)
	local _, dark, accent = colors(pack)
	local r = seeded(19)
	for k = 1, 9 do
		local size = 220 + r() * 260
		local c = frame(layer, { Name = "Cloud", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(r(), 0, k <= 5 and 1 or 0, (k <= 5 and -1 or 1) * size * 0.15), Size = UDim2.fromOffset(size, size * 0.6), BackgroundColor3 = dark:Lerp(accent, 0.15 + r() * 0.15), BackgroundTransparency = 0.25 })
		corner(c, "round")
	end
	-- thunder: the sky lights up now and then
	local glow = frame(layer, { Name = "Thunder", Size = UDim2.fromScale(1, 1), BackgroundColor3 = accent:Lerp(WHITE, 0.6), BackgroundTransparency = 1, ZIndex = 0 })
	local nextAt = nil
	Juice.onFrame(glow, function(t)
		nextAt = nextAt or (t + 2.5)
		if t >= nextAt then
			nextAt = t + 3 + (t * 7.13 % 4)
			glow.BackgroundTransparency = 0.82
			tween(glow, 0.5, { BackgroundTransparency = 1 })
		end
	end)
end
function Scenery.grass(layer, pack)
	local main, dark = colors(pack)
	local moon = frame(layer, { Name = "Moon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.8, 0.18), Size = UDim2.fromOffset(110, 110), BackgroundColor3 = rgb(255, 246, 210), BackgroundTransparency = 0.1 })
	corner(moon, "round")
	make("UIStroke", { Thickness = 18, Color = rgb(255, 246, 210), Transparency = 0.85 }, moon)
	local r = seeded(23)
	for k = 0, 60 do
		local h = 60 + r() * 110
		local blade = frame(layer, { Name = "Blade", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(k / 60, 0, 1, 10), Size = UDim2.fromOffset(10 + r() * 8, h), Rotation = (r() - 0.5) * 24, BackgroundColor3 = dark:Lerp(main, r() * 0.35):Lerp(rgb(4, 10, 6), 0.45) })
		corner(blade, "round")
		local base, ph = blade.Rotation, r() * 6
		Juice.onFrame(blade, function(t)
			blade.Rotation = base + math.sin(t * 1.3 + ph) * 3
		end)
	end
end
function Scenery.mall(layer, pack)
	local main, dark, accent = colors(pack)
	for k = 0, 5 do
		local shop = frame(layer, { Name = "Shop" .. k, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new((k + 0.5) / 6, 0, 1, 0), Size = UDim2.new(1 / 6, -14, 0.32, 0), BackgroundColor3 = dark:Lerp(INK, 0.55) })
		corner(shop, 30)
		local win = frame(shop, { Name = "Window", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.new(1, -30, 0.5, 0), BackgroundColor3 = (k % 2 == 0) and accent or main, BackgroundTransparency = 0.75 })
		corner(win, 16)
		local ph = k * 1.7
		Juice.onFrame(win, function(t)
			win.BackgroundTransparency = (math.sin(t * 11 + ph) > 0.96) and 0.95 or 0.75
		end)
	end
	local sign = text(layer, "MIDNIGHT MALL", { Name = "Sign", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(420, 46), Font = Enum.Font.Creepster, TextColor3 = accent, TextTransparency = 0.55 })
	Juice.onFrame(sign, function(t)
		sign.TextTransparency = (math.sin(t * 9) > 0.95) and 0.85 or 0.55
	end)
end
function Scenery.grid(layer, pack)
	local _, _, accent = colors(pack)
	-- a glowing floor grid that runs toward the horizon
	local floor = frame(layer, { Name = "Floor", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 0.4), BackgroundTransparency = 1, ClipsDescendants = true })
	local rows = {}
	for k = 1, 9 do
		rows[k] = frame(floor, { Name = "Row", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = accent, BackgroundTransparency = 0.5 })
	end
	for k = -6, 6 do
		frame(floor, { Name = "Col", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5 + k * 0.02, 0), Size = UDim2.new(0, 2, 2.6, 0), Rotation = -k * 9, BackgroundColor3 = accent, BackgroundTransparency = 0.6 })
	end
	frame(layer, { Name = "Horizon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = accent, BackgroundTransparency = 0.2 })
	Juice.onFrame(floor, function(t)
		for k, row in ipairs(rows) do
			local a = ((k - 1) / #rows + t * 0.12) % 1
			row.Position = UDim2.fromScale(0.5, a * a)
			row.BackgroundTransparency = 0.85 - a * 0.5
		end
	end)
end

-- The scene behind the pack. Returns { root, tint, burst, setCalm, destroy }.
function PackArt.scene(parent, pack)
	local design
	design, pack = PackArt.design(pack)
	local main, _, accent = colors(pack)
	local top, bottom = c3(design.sky[1]), c3(design.sky[2])
	local root = frame(parent, { Name = "Scene", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 1 })
	local sky = make("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom) }, root)
	-- the tint layer: the reveal washes the scene toward the card's colour after the flip
	local tintLayer = frame(root, { Name = "Tint", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 1 })
	local scenery = frame(root, { Name = "Scenery", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 })
	Scenery[design.scenery](scenery, pack)
	local bits = frame(root, { Name = "Ambient", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 })
	-- the soft light behind the pack
	local halo = frame(root, { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 620), BackgroundColor3 = main:Lerp(WHITE, 0.35), BackgroundTransparency = 0.82, ZIndex = 2 })
	corner(halo, "round")
	local halo2 = frame(halo, { Name = "Core", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.6), BackgroundColor3 = accent:Lerp(WHITE, 0.5), BackgroundTransparency = 0.8, ZIndex = 2 })
	corner(halo2, "round")
	-- vignette: darker edges keep the eye in the middle
	for k, e in ipairs({ { Vector2.new(0, 0), UDim2.new(1, 0, 0.22, 0), 90 }, { Vector2.new(0, 1), UDim2.new(1, 0, 0.22, 0), -90 }, { Vector2.new(0, 0), UDim2.new(0.18, 0, 1, 0), 0 }, { Vector2.new(1, 0), UDim2.new(0.18, 0, 1, 0), 180 } }) do
		local v = frame(root, { Name = "Vignette" .. k, AnchorPoint = e[1], Position = UDim2.fromScale(e[1].X, e[1].Y), Size = e[2], BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 0, ZIndex = 3 })
		make("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new(0.35, 1) }, v)
	end
	local sys = particleSystem(bits)
	local r = seeded(pack.index * 1000 + 17)
	local spawnIn = 0
	local calm = false
	local spawner = Ambient[design.ambient]
	local slow = lowGraphics() and 2 or 1
	-- start with the scene already full of bits
	for _ = 1, 10 do
		spawner(sys, bits, pack, r)
		local p = sys.list[#sys.list]
		if p then
			p.age = r() * p.life * 0.5
			p.y = r()
		end
	end
	Juice.onFrame(root, function(t, dt)
		halo.Size = UDim2.fromOffset(620 + math.sin(t * 1.4) * 24, 620 + math.sin(t * 1.4) * 24)
		spawnIn -= dt
		if spawnIn <= 0 and not calm then
			spawnIn = spawner(sys, bits, pack, r) * slow
		end
		sys.step(dt)
	end)
	local scene = { root = root, halo = halo, sky = sky, design = design, pack = pack }
	function scene.tint(color, amount, time)
		tintLayer.BackgroundColor3 = color
		tween(tintLayer, time or 0.5, { BackgroundTransparency = 1 - (amount or 0.4) })
		tween(halo, time or 0.5, { BackgroundColor3 = color:Lerp(WHITE, 0.3) })
		tween(halo2, time or 0.5, { BackgroundColor3 = color:Lerp(WHITE, 0.6) })
	end
	function scene.setCalm(on)
		calm = on
	end
	function scene.burst(sx, sy, angle)
		PackArt.burst(parent, pack, sx, sy, angle)
	end
	function scene.destroy()
		root:Destroy()
	end
	return scene
end

-- The burst where the pack was cut: in the pack's colours, never the card's.
local Bursts = {
	sparks = { text = "★", n = 16, confetti = 26 },
	candy = { shape = "round", n = 26, confetti = 20 },
	bolts = { shape = "square", n = 18, confetti = 8, dark = true },
	zap = { text = "★", n = 12, confetti = 14 },
	leaves = { shape = "leaf", n = 22, confetti = 10 },
	ghosts = { shape = "round", n = 16, confetti = 10 },
	circuit = { shape = "square", n = 20, confetti = 12 },
}
function PackArt.burst(parent, pack, sx, sy, angle)
	local design
	design, pack = PackArt.design(pack)
	local main, dark, accent = colors(pack)
	local b = Bursts[design.burst] or Bursts.sparks
	local cols = { main, main:Lerp(WHITE, 0.5), accent, WHITE }
	if b.dark then
		cols = { rgb(120, 126, 126), rgb(200, 200, 190), accent, rgb(255, 180, 80) }
	end
	if b.text then
		Juice.stars(parent, sx, sy, b.n, { text = b.text, color = accent:Lerp(WHITE, 0.3), speed = 1.4, size = 24, zIndex = 45 })
	else
		local n = math.floor(b.n * (lowGraphics() and 0.5 or 1))
		local vw = parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.X or 1280
		local vh = parent.AbsoluteSize.Y > 0 and parent.AbsoluteSize.Y or 720
		for k = 1, n do
			local size = b.shape == "leaf" and Vector2.new(10, 18) or Vector2.new(9, 9)
			local f = frame(parent, { Name = "Bit", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(sx, sy), Size = UDim2.fromOffset(size.X, size.Y), Rotation = math.random(0, 360), BackgroundColor3 = cols[1 + (k % #cols)], ZIndex = 45 })
			if b.shape ~= "square" then
				corner(f, "round")
			end
			-- out along both sides of the cut
			local side = (k % 2 == 0) and 1 or -1
			local a = math.rad(angle or 0) + side * math.pi / 2 + (math.random() - 0.5) * 1.6
			local dist = 160 + math.random() * 220
			local goal = UDim2.fromScale(sx + math.cos(a) * dist / vw, sy + math.sin(a) * dist / vh + 0.08)
			tween(f, 0.7 + math.random() * 0.3, { Position = goal, Rotation = f.Rotation + math.random(-220, 220), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			task.delay(1.1, function()
				f:Destroy()
			end)
		end
	end
	Juice.confetti(parent, sx, sy, b.confetti, { colors = cols, speed = 0.8, zIndex = 44 })
end

return PackArt

-- Match backgrounds: the world around the Duel Table during a match.
--
-- You pick one on the Duel Table panel before you start ("Background"). It's only on your screen,
-- so everyone at a table can have their own. "Card Den" keeps the room. The others hide the
-- room (on your screen), build a themed world out of parts around the table and change the sky and
-- lighting. When the match ends everything goes back exactly as it was.
--
-- The seat camera sees the ground around the table out to about 45 studs, so that ring is the
-- most detailed. Bigger landmarks and the sky are further out, for the low action-camera shots.
-- Client only. DeckWarsClient calls Backdrops.apply(key, room, duelTable) when a match starts and
-- Backdrops.clear() when it ends.

local Backdrops = {}

local Lighting = game:GetService("Lighting")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Backdrops.List = {
	{ key = "Room", name = "Card Den", emoji = "🏠", colors = { rgb(170, 120, 75), rgb(70, 45, 30) }, blurb = "The cozy room you start in." },
	{ key = "Candy", name = "Gumdrop Plaza", emoji = "🍬", colors = { rgb(255, 120, 190), rgb(120, 230, 210) }, blurb = "A peppermint plaza, gumdrop hills, giant lollipops, a chocolate river and a candy castle under a rainbow." },
	{ key = "Meadow", name = "Sunset Grasslands", emoji = "🌄", colors = { rgb(255, 150, 70), rgb(90, 190, 80) }, blurb = "Wildflower hills, a lily pond, fireflies and a giant treehouse at sunset." },
	{ key = "Ice", name = "Frostglass Lake", emoji = "❄️", colors = { rgb(140, 220, 255), rgb(70, 60, 190) }, blurb = "A frozen lake, glowing ice crystals, snowmen, an ice castle and the northern lights." },
	{ key = "Fire", name = "Ember Caldera", emoji = "🌋", colors = { rgb(255, 160, 40), rgb(170, 20, 30) }, blurb = "An obsidian plaza in a ring of torches, lava rivers and smoking volcanoes." },
	{ key = "Space", name = "Cosmic Void", emoji = "🌌", colors = { rgb(200, 90, 255), rgb(40, 50, 160) }, blurb = "A floating asteroid among ringed planets, nebulas and a sky full of stars." },
	{ key = "Mall", name = "Midnight Mall", emoji = "🌙", colors = { rgb(255, 80, 200), rgb(60, 40, 115) }, blurb = "A haunted parking lot under a low moon: flickering lamps, runaway carts and a mall that never closes." },
	{ key = "Random", name = "Surprise me", emoji = "🎲", colors = { rgb(255, 210, 80), rgb(120, 90, 220) }, blurb = "A different world every match." },
}
Backdrops.ByKey = {}
for _, b in ipairs(Backdrops.List) do
	Backdrops.ByKey[b.key] = b
end
Backdrops.choice = "Room" -- what the Duel Table panel has picked

-- What's been changed, so clear() can put it all back.
local S = { folder = nil, saved = {}, added = {}, removed = {}, current = nil, count = 0 }

local function save(inst, prop)
	table.insert(S.saved, { inst, prop, inst[prop] })
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

local B = {}

local function make(props, className)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = S.folder
	S.count += 1
	return p
end

local function asCF(at)
	return typeof(at) == "CFrame" and at or CFrame.new(at)
end

function B.block(cf, size, color, mat, extra)
	local props = extra or {}
	props.CFrame, props.Size, props.Color, props.Material = cf, size, color, mat or Enum.Material.SmoothPlastic
	return make(props)
end

function B.ball(at, d, color, mat, extra)
	local props = extra or {}
	props.Shape = Enum.PartType.Ball
	props.CFrame, props.Size, props.Color, props.Material = asCF(at), Vector3.new(d, d, d), color, mat or Enum.Material.SmoothPlastic
	return make(props)
end

-- A cylinder standing up, `h` tall and `d` across, its bottom at `base` (a CFrame, so it can lean).
function B.cyl(base, h, d, color, mat, extra)
	local props = extra or {}
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(h, d, d)
	props.CFrame = asCF(base) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
	props.Color, props.Material = color, mat or Enum.Material.SmoothPlastic
	return make(props)
end

-- A cone made of stacked cylinders getting narrower (trees, roofs, volcanoes, mountains).
function B.cone(base, h, d, color, mat, steps, extra, topD)
	steps = steps or 6
	topD = topD or d * 0.12
	local out = {}
	for i = 0, steps - 1 do
		local f = i / steps
		local p = B.cyl(asCF(base) * CFrame.new(0, h * f, 0), h / steps, d + (topD - d) * f, color, mat, extra and table.clone(extra) or nil)
		table.insert(out, p)
	end
	return out
end

-- A flat disc facing `target` (lollipop candy, planet rings face up instead).
function B.facing(center, target, d, thick, color, mat, extra)
	local props = extra or {}
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(thick, d, d)
	props.CFrame = CFrame.lookAt(center, target) * CFrame.Angles(0, math.pi / 2, 0)
	props.Color, props.Material = color, mat or Enum.Material.SmoothPlastic
	return make(props)
end

-- A flat disc lying on the ground, its top at height `top`.
function B.disc(x, z, top, d, thick, color, mat, extra)
	return B.cyl(CFrame.new(x, top - thick, z), thick, d, color, mat, extra)
end

-- A segment between two points (rivers, cane hooks, rainbows, branches).
function B.beam(a, b, width, height, color, mat, extra)
	local len = (b - a).Magnitude
	return B.block(CFrame.lookAt((a + b) / 2, b), Vector3.new(width, height, len + width * 0.2), color, mat, extra)
end

function B.light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 12
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = p
	return l
end

-- An invisible box that gives off particles (snow, fireflies, embers, sparkles).
function B.particles(cf, size, cfg)
	local holder = make({ CFrame = cf, Size = size, Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = cfg.texture or "rbxasset://textures/particles/sparkles_main.dds"
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = cfg.dir or Enum.NormalId.Top
	e.Speed = NumberRange.new(cfg.speed[1], cfg.speed[2])
	e.Lifetime = NumberRange.new(cfg.life[1], cfg.life[2])
	e.Rate = cfg.rate
	e.Size = NumberSequence.new(cfg.size[1], cfg.size[2])
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, cfg.alpha or 0.1), NumberSequenceKeypoint.new(0.8, cfg.alpha or 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(cfg.colors[1], cfg.colors[2] or cfg.colors[1])
	e.LightEmission = cfg.glow or 0.5
	e.SpreadAngle = Vector2.new(cfg.spread or 20, cfg.spread or 20)
	if cfg.accel then
		e.Acceleration = cfg.accel
	end
	if cfg.spin then
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-cfg.spin, cfg.spin)
	end
	e.Parent = holder
	return holder, e
end

-- The ground: one big slab whose top is the room's floor height (0).
function B.ground(color, mat)
	return B.block(CFrame.new(0, -1, 0), Vector3.new(1600, 2, 1600), color, mat)
end

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

-- A point on the ground between rMin and rMax studs from the table, within `spread` degrees either
-- side of straight ahead (the far side of the table; 180 = all the way round).
local function spot(rng, rMin, rMax, spread)
	local a = math.rad(rng:NextNumber(-spread, spread))
	local r = math.sqrt(rng:NextNumber(rMin * rMin, rMax * rMax))
	return Vector3.new(math.sin(a) * r, 0, -math.cos(a) * r)
end

-- Turned to face your seat (so lollipops, windows and snowmen look at you).
local SEAT = Vector3.new(0, 6, 14)
local function towardSeat(pos)
	return CFrame.lookAt(pos, Vector3.new(SEAT.X, pos.Y, SEAT.Z))
end

-- Shared pieces --------------------------------------------------------------------------------

-- A round tree: trunk and a few canopy balls.
local function roundTree(rng, pos, h, greens, trunkColor)
	local lean = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(0, 6.28), rng:NextNumber(-0.06, 0.06))
	B.cyl(lean, h, h * 0.16, trunkColor or rgb(120, 80, 50), Enum.Material.Wood)
	local top = (lean * CFrame.new(0, h, 0)).Position
	local size = h * 0.95
	B.ball(top, size, pick(rng, greens), Enum.Material.Grass)
	for _ = 1, 3 do
		local off = Vector3.new(rng:NextNumber(-0.45, 0.45), rng:NextNumber(-0.35, 0.1), rng:NextNumber(-0.45, 0.45)) * size
		B.ball(top + off, size * rng:NextNumber(0.55, 0.8), pick(rng, greens), Enum.Material.Grass)
	end
end

-- A pine tree in tiers, with snow on each tier if `snowy`.
local function pineTree(rng, pos, h, snowy)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	B.cyl(base, h * 0.2, h * 0.1, rgb(100, 65, 40), Enum.Material.Wood)
	local tiers = 4
	for i = 0, tiers - 1 do
		local w = h * (0.62 - i * 0.13)
		local y = h * (0.16 + i * 0.2)
		B.cyl(base * CFrame.new(0, y, 0), h * 0.2, w, i % 2 == 0 and rgb(35, 95, 70) or rgb(45, 110, 75), Enum.Material.Grass)
		if snowy then
			B.cyl(base * CFrame.new(0, y + h * 0.2, 0), h * 0.035, w * 0.86, rgb(245, 250, 255), Enum.Material.Snow)
		end
	end
	B.ball(base * CFrame.new(0, h * 0.98, 0), h * 0.09, snowy and rgb(220, 245, 255) or rgb(255, 230, 120), Enum.Material.Neon)
end

-- A cluster of crystal spikes.
local function crystals(rng, pos, h, colors, glowColor, withLight)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local biggest
	for i = 1, rng:NextInteger(3, 5) do
		local hh = h * rng:NextNumber(0.45, 1)
		local w = hh * rng:NextNumber(0.14, 0.22)
		local cf = base * CFrame.new(rng:NextNumber(-0.25, 0.25) * h, 0, rng:NextNumber(-0.25, 0.25) * h) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6.28), rng:NextNumber(-0.35, 0.35))
		local p = B.block(cf * CFrame.new(0, hh / 2 - 0.3, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w, hh, w), pick(rng, colors), Enum.Material.Glass, { Transparency = 0.2, Reflectance = 0.15 })
		-- a glowing core inside
		B.block(cf * CFrame.new(0, hh / 2 - 0.3, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w * 0.4, hh * 0.85, w * 0.4), glowColor, Enum.Material.Neon)
		if not biggest or hh > biggest.Size.Y then
			biggest = p
		end
	end
	if withLight and biggest then
		B.light(biggest, glowColor, h * 2.2, 1.6)
	end
end

-- A river winding across in front of the table, from x = -span to span around z = zMid.
local function river(rng, zMid, width, span, color, mat, extra, onSegment)
	local step = 7
	local phase = rng:NextNumber(0, 6.28)
	local prev
	for x = -span, span, step do
		local z = zMid + math.sin(x / 19 + phase) * 6 + math.sin(x / 7.3) * 1.2
		local p = Vector3.new(x, 0.06, z)
		if prev then
			local seg = B.beam(prev, p, width, 0.12, color, mat, extra and table.clone(extra) or nil)
			if onSegment then
				onSegment(seg, prev, p)
			end
		end
		prev = p
	end
end

-- A rainbow arc (or aurora ribbon): bands of colour bent into a half circle.
local function arc(center, facingYaw, radius, colors, band, segments, transparency)
	local frame = CFrame.new(center) * CFrame.Angles(0, facingYaw, 0)
	for i, color in ipairs(colors) do
		local r = radius - (i - 1) * band
		local prev
		for k = 0, segments do
			local a = k / segments * math.pi
			local p = (frame * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0)).Position
			if prev then
				-- thin across the arc's plane, `band` wide along the radius
				B.beam(prev, p, band * 0.25, band * 1.05, color, Enum.Material.Neon, { Transparency = transparency or 0.3 })
			end
			prev = p
		end
	end
end

---------------------------------------------------------------------------
-- The worlds
---------------------------------------------------------------------------

local THEMES = {}

THEMES.Candy = {
	-- The wide opening shot when a match starts, before the camera settles at your seat.
	intro = { pos = Vector3.new(24, 26, 40), look = Vector3.new(-50, 14, -60), fov = 62, drift = Vector3.new(-7, -4, -8) },
	lighting = {
		ClockTime = 14.5,
		Brightness = 2.4,
		Ambient = rgb(130, 100, 125),
		OutdoorAmbient = rgb(205, 160, 195),
		ColorShift_Top = rgb(255, 220, 235),
		ColorShift_Bottom = rgb(90, 60, 80),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0,
	},
	atmosphere = { Density = 0.28, Offset = 0.1, Color = rgb(255, 195, 228), Decay = rgb(255, 150, 210), Glare = 0.4, Haze = 1.6 },
	sky = { StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 14 },
	bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 },
	color = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.28, TintColor = rgb(255, 245, 250) },
	depth = { FarIntensity = 0.06, FocusDistance = 30, InFocusRadius = 45 },
	preview = { sky = rgb(255, 200, 230), fog = rgb(255, 205, 232), fogDensity = 0.004 },
}
function THEMES.Candy.build(rng)
	B.ground(rgb(255, 178, 212), Enum.Material.Sand) -- sugar
	-- the peppermint plaza the table stands on
	B.disc(0, 0, 0.05, 66, 0.05, rgb(225, 35, 70))
	B.disc(0, 0, 0.09, 62, 0.05, rgb(255, 250, 250), Enum.Material.SmoothPlastic, { Reflectance = 0.08 })
	for k = 0, 7 do
		B.block(CFrame.new(0, 0.1, 0) * CFrame.Angles(0, k * math.pi / 8, 0), Vector3.new(4.6, 0.04, 61), rgb(235, 45, 80), Enum.Material.SmoothPlastic, { Reflectance = 0.08 })
	end
	B.disc(0, 0, 0.12, 16, 0.04, rgb(255, 250, 250)) -- the middle stays white
	-- sprinkles on the sugar
	local SPRINKLE = { rgb(255, 225, 60), rgb(80, 180, 255), rgb(120, 230, 120), rgb(190, 120, 255), rgb(255, 140, 60), rgb(255, 255, 255), rgb(255, 90, 160) }
	for _ = 1, 170 do
		local p = spot(rng, 34, 80, 125)
		B.block(CFrame.new(p.X, 0.12, p.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(0.5, 0.25, 1.6), pick(rng, SPRINKLE))
	end
	-- gumdrops
	local GUM = { rgb(255, 70, 120), rgb(255, 205, 40), rgb(80, 220, 140), rgb(110, 165, 255), rgb(195, 105, 255), rgb(255, 140, 45) }
	for _ = 1, 26 do
		local p = spot(rng, 35, 72, 150)
		local d = rng:NextNumber(2.5, 5.5)
		B.ball(Vector3.new(p.X, d * 0.18, p.Z), d, pick(rng, GUM), Enum.Material.SmoothPlastic, { Reflectance = 0.12 })
	end
	-- lollipops, their swirls turned to your seat
	local PAIRS = { { rgb(255, 70, 140), rgb(255, 240, 250) }, { rgb(255, 200, 40), rgb(255, 110, 60) }, { rgb(90, 200, 255), rgb(240, 250, 255) }, { rgb(170, 90, 255), rgb(255, 150, 220) }, { rgb(80, 220, 150), rgb(255, 250, 200) } }
	for _ = 1, 16 do
		local p = spot(rng, 34, 64, 115)
		local r = p.Magnitude
		local h = 3.2 + (r - 34) * 0.22 + rng:NextNumber(0, 1.5)
		local D = rng:NextNumber(3, 4.6)
		B.cyl(CFrame.new(p), h, 0.35, rgb(250, 250, 245))
		local center = p + Vector3.new(0, h + D / 2 - 0.3, 0)
		local face = towardSeat(center)
		local pair = pick(rng, PAIRS)
		for k = 0, 4 do
			local c = (face * CFrame.new(0, 0, -k * 0.04)).Position
			B.facing(c, c + face.LookVector, D * (1 - k * 0.19), 0.3, k % 2 == 0 and pair[1] or pair[2], Enum.Material.SmoothPlastic, { Reflectance = 0.1 })
		end
	end
	-- candy canes
	for _ = 1, 10 do
		local p = spot(rng, 33, 60, 150)
		local base = CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, 6.28), rng:NextNumber(-0.08, 0.08))
		local n = rng:NextInteger(5, 8)
		for i = 0, n - 1 do
			B.cyl(base * CFrame.new(0, i, 0), 1, 0.9, i % 2 == 0 and rgb(230, 30, 50) or rgb(255, 250, 250), Enum.Material.SmoothPlastic, { Reflectance = 0.1 })
		end
		local R = 1.25
		for k = 0, 7 do
			local a = k / 7 * math.pi
			B.ball(base * CFrame.new(R - R * math.cos(a), n + R * math.sin(a), 0), 0.9, k % 2 == 0 and rgb(230, 30, 50) or rgb(255, 250, 250))
		end
	end
	-- the chocolate river, with marshmallows bobbing in it
	river(rng, -44, 8, 160, rgb(105, 55, 30), Enum.Material.SmoothPlastic, { Reflectance = 0.18 }, function(seg, a, b)
		if rng:NextNumber() < 0.35 then
			local m = a:Lerp(b, rng:NextNumber())
			B.block(CFrame.new(m + Vector3.new(rng:NextNumber(-2, 2), 0.35, rng:NextNumber(-2, 2))) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(1.2, 0.8, 1.2), rgb(255, 245, 240))
		end
	end)
	-- cotton candy trees
	for _ = 1, 18 do
		local p = spot(rng, 50, 120, 170)
		local h = rng:NextNumber(7, 13)
		B.cyl(CFrame.new(p), h, 0.9, rgb(255, 235, 240))
		local top = p + Vector3.new(0, h, 0)
		local fluff = pick(rng, { rgb(255, 170, 215), rgb(170, 215, 255), rgb(215, 180, 255) })
		for _ = 1, 4 do
			B.ball(top + Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-1, 2), rng:NextNumber(-2.5, 2.5)), rng:NextNumber(5, 8), fluff, Enum.Material.SmoothPlastic, { Transparency = 0.05 })
		end
	end
	-- gumdrop hills all around
	local HILLS = { rgb(255, 190, 220), rgb(190, 240, 220), rgb(215, 195, 255), rgb(255, 215, 175), rgb(180, 220, 255) }
	for i = 1, 24 do
		local p = spot(rng, 120, 260, 180)
		local d = rng:NextNumber(45, 95)
		B.ball(Vector3.new(p.X, -d * 0.22, p.Z), d, HILLS[(i % #HILLS) + 1], Enum.Material.Sand)
	end
	-- the candy castle (west) under a rainbow
	local c = CFrame.new(-150, 0, -70)
	local castleFace = Vector3.new(0, 0, 0)
	B.cyl(c, 16, 52, rgb(255, 150, 200))
	B.cyl(c * CFrame.new(0, 16, 0), 1.6, 55, rgb(255, 250, 250))
	B.cyl(c * CFrame.new(0, 17.6, 0), 13, 38, rgb(150, 230, 210))
	B.cyl(c * CFrame.new(0, 30.6, 0), 1.4, 40, rgb(255, 250, 250))
	B.cyl(c * CFrame.new(0, 32, 0), 11, 24, rgb(205, 170, 255))
	B.cone(c * CFrame.new(0, 43, 0), 30, 16, rgb(255, 110, 175), nil, 8)
	local heart = B.ball(c * CFrame.new(0, 75, 0), 5, rgb(255, 80, 160), Enum.Material.Neon)
	B.light(heart, rgb(255, 120, 190), 30, 2)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		local tc = c * CFrame.new(math.cos(a) * 27, 0, math.sin(a) * 27)
		local th = 30 + (k % 2) * 12
		B.cyl(tc, th, 8, k % 2 == 0 and rgb(255, 175, 215) or rgb(170, 235, 220))
		B.cyl(tc * CFrame.new(0, th, 0), 1.2, 9.6, rgb(255, 250, 250))
		B.cone(tc * CFrame.new(0, th + 1.2, 0), 15, 10, k % 2 == 0 and rgb(190, 110, 255) or rgb(255, 120, 170), nil, 6)
		B.ball(tc * CFrame.new(0, th + 17, 0), 2.6, pick(rng, GUM), Enum.Material.SmoothPlastic, { Reflectance = 0.15 })
		local towerPos = tc.Position
		local dir = (castleFace - towerPos) * Vector3.new(1, 0, 1)
		dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(1, 0, 0)
		for w = 1, 3 do
			local wp = towerPos + dir * 4 + Vector3.new(0, th * (w / 4), 0)
			B.block(CFrame.lookAt(wp, wp + dir), Vector3.new(1.4, 2.4, 0.3), rgb(255, 230, 130), Enum.Material.Neon)
		end
	end
	arc(Vector3.new(-150, -10, -110), math.rad(35), 120, { rgb(255, 60, 70), rgb(255, 150, 40), rgb(255, 230, 60), rgb(80, 220, 110), rgb(70, 160, 255), rgb(160, 90, 255) }, 6, 20, 0.35)
	-- a giant cupcake mountain (east)
	local cc = CFrame.new(160, 0, -20)
	B.cyl(cc, 20, 60, rgb(255, 120, 170))
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		B.block(cc * CFrame.new(math.cos(a) * 30, 10, math.sin(a) * 30) * CFrame.Angles(0, -a, 0), Vector3.new(1.2, 20, 3), rgb(225, 90, 145))
	end
	B.cone(cc * CFrame.new(0, 20, 0), 36, 70, rgb(255, 250, 245), nil, 7, nil, 14)
	B.ball(cc * CFrame.new(0, 60, 0), 12, rgb(230, 20, 50), Enum.Material.SmoothPlastic, { Reflectance = 0.2 })
	B.beam(Vector3.new(160, 65, -20), Vector3.new(163, 72, -18), 0.8, 0.8, rgb(80, 140, 50))
	for _ = 1, 26 do
		local a = rng:NextNumber(0, 6.28)
		local y = rng:NextNumber(0.1, 0.85)
		local r = 35 * (1 - y) + 7
		B.block(cc * CFrame.new(math.cos(a) * r, 20 + y * 36, math.sin(a) * r) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), Vector3.new(1, 0.6, 3), pick(rng, SPRINKLE))
	end
	-- cotton candy clouds
	for _ = 1, 12 do
		local p = spot(rng, 90, 260, 180) + Vector3.new(0, rng:NextNumber(35, 80), 0)
		local col = pick(rng, { rgb(255, 205, 235), rgb(255, 255, 255), rgb(205, 230, 255) })
		for _ = 1, 5 do
			B.ball(p + Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-3, 4), rng:NextNumber(-6, 6)), rng:NextNumber(10, 20), col, Enum.Material.SmoothPlastic, { Transparency = 0.08 })
		end
	end
	-- sugar sparkles drifting over the table
	B.particles(CFrame.new(0, 7, -8), Vector3.new(90, 6, 70), { speed = { 0.2, 0.6 }, life = { 3, 5 }, rate = 14, size = { 0.25, 0 }, colors = { rgb(255, 150, 220), rgb(150, 230, 255) }, glow = 0.8, spread = 180 })
end

THEMES.Meadow = {
	-- The wide opening shot when a match starts, before the camera settles at your seat.
	intro = { pos = Vector3.new(24, 26, 40), look = Vector3.new(-50, 16, -60), fov = 62, drift = Vector3.new(-7, -4, -8) },
	lighting = {
		ClockTime = 17.6,
		Brightness = 2.4,
		Ambient = rgb(115, 85, 85),
		OutdoorAmbient = rgb(195, 135, 115),
		ColorShift_Top = rgb(255, 190, 140),
		ColorShift_Bottom = rgb(80, 50, 60),
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.5,
		ExposureCompensation = 0.1,
	},
	atmosphere = { Density = 0.32, Offset = 0.25, Color = rgb(255, 180, 130), Decay = rgb(255, 110, 150), Glare = 1.2, Haze = 2 },
	sky = { StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 24 },
	bloom = { Intensity = 0.4, Size = 26, Threshold = 1.7 },
	color = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.3, TintColor = rgb(255, 238, 222) },
	depth = { FarIntensity = 0.06, FocusDistance = 30, InFocusRadius = 45 },
	preview = { sky = rgb(255, 170, 120), fog = rgb(255, 185, 140), fogDensity = 0.004 },
}
function THEMES.Meadow.build(rng)
	B.ground(rgb(105, 180, 70), Enum.Material.Grass)
	-- a worn patch of earth under the table, and stepping stones off towards the treehouse
	B.disc(0, 0, 0.05, 44, 0.05, rgb(150, 112, 70), Enum.Material.Ground)
	B.disc(0, 0, 0.08, 38, 0.04, rgb(165, 125, 80), Enum.Material.Ground)
	for i = 1, 11 do
		local t = i / 11
		local p = Vector3.new(-10 - t * 60 + math.sin(t * 5) * 4, 0.12, -22 - t * 30)
		B.disc(p.X, p.Z, 0.14, rng:NextNumber(2.6, 3.4), 0.1, rgb(150, 150, 160), Enum.Material.Slate)
	end
	-- wildflowers and tall grass
	local FLOWERS = { rgb(255, 90, 140), rgb(255, 220, 60), rgb(255, 255, 255), rgb(180, 110, 255), rgb(255, 140, 50), rgb(255, 60, 70), rgb(110, 190, 255) }
	for _ = 1, 230 do
		local p = spot(rng, 23, 75, 150)
		local d = rng:NextNumber(0.6, 1.1)
		B.ball(Vector3.new(p.X, 0.45, p.Z), d, pick(rng, FLOWERS), Enum.Material.SmoothPlastic)
	end
	for _ = 1, 110 do
		local p = spot(rng, 23, 60, 160)
		local h = rng:NextNumber(1, 2.2)
		B.block(CFrame.new(p.X, h / 2, p.Z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Vector3.new(0.18, h, 0.18), pick(rng, { rgb(80, 165, 60), rgb(120, 200, 70), rgb(95, 150, 55) }), Enum.Material.Grass)
	end
	-- spotted mushrooms
	for _ = 1, 12 do
		local p = spot(rng, 24, 48, 150)
		local h = rng:NextNumber(1.4, 3)
		local capD = h * 1.4
		B.cyl(CFrame.new(p), h, h * 0.35, rgb(245, 235, 220))
		local cap = p + Vector3.new(0, h, 0)
		B.ball(cap, capD, rgb(230, 45, 50))
		B.cyl(CFrame.new(cap - Vector3.new(0, 0.1, 0)), 0.2, capD * 1.02, rgb(245, 225, 210))
		for _ = 1, 4 do
			local a = rng:NextNumber(0, 6.28)
			local up = rng:NextNumber(0.35, 0.75)
			local dir = Vector3.new(math.cos(a) * math.sqrt(1 - up * up), up, math.sin(a) * math.sqrt(1 - up * up))
			B.ball(cap + dir * capD * 0.47, capD * 0.18, rgb(255, 255, 255))
		end
	end
	-- the lily pond
	local pond = Vector3.new(34, 0, -36)
	B.disc(pond.X, pond.Z, 0.05, 20, 0.05, rgb(120, 95, 70), Enum.Material.Ground)
	B.disc(pond.X, pond.Z, 0.1, 17, 0.06, rgb(70, 165, 220), Enum.Material.Glass, { Transparency = 0.1, Reflectance = 0.3 })
	for _ = 1, 6 do
		local a = rng:NextNumber(0, 6.28)
		local r = rng:NextNumber(2, 6.5)
		B.disc(pond.X + math.cos(a) * r, pond.Z + math.sin(a) * r, 0.16, rng:NextNumber(1.6, 2.4), 0.04, rgb(70, 160, 60))
		if rng:NextNumber() < 0.6 then
			B.ball(Vector3.new(pond.X + math.cos(a) * r, 0.35, pond.Z + math.sin(a) * r), 0.7, rgb(255, 160, 210))
		end
	end
	-- round trees, some in pink blossom
	local GREENS = { rgb(70, 150, 60), rgb(95, 175, 70), rgb(60, 130, 80), rgb(120, 180, 60) }
	local BLOSSOM = { rgb(255, 175, 205), rgb(255, 205, 225), rgb(250, 150, 190) }
	for _ = 1, 42 do
		local p = spot(rng, 42, 140, 180)
		roundTree(rng, p, rng:NextNumber(6, 11), rng:NextNumber() < 0.25 and BLOSSOM or GREENS)
	end
	-- the giant treehouse (west)
	local fort = CFrame.new(-120, 0, -75)
	B.cyl(fort, 80, 20, rgb(110, 75, 45), Enum.Material.Wood)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		B.beam(fort.Position + Vector3.new(math.cos(a) * 9, 6, math.sin(a) * 9), fort.Position + Vector3.new(math.cos(a) * 19, 0, math.sin(a) * 19), 4, 4, rgb(100, 68, 40), Enum.Material.Wood)
	end
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		local p = fort.Position + Vector3.new(math.cos(a) * rng:NextNumber(14, 30), rng:NextNumber(68, 95), math.sin(a) * rng:NextNumber(14, 30))
		B.ball(p, rng:NextNumber(28, 44), pick(rng, GREENS), Enum.Material.Grass)
	end
	local houseAt = fort * CFrame.new(0, 48, 0)
	B.block(houseAt * CFrame.new(0, 0, 0), Vector3.new(28, 2, 28), rgb(140, 95, 55), Enum.Material.WoodPlanks)
	B.block(houseAt * CFrame.new(8, 7, 8), Vector3.new(14, 12, 12), rgb(185, 130, 75), Enum.Material.WoodPlanks)
	B.block(houseAt * CFrame.new(8, 16, 8), Vector3.new(16, 6, 14), rgb(70, 140, 200), Enum.Material.SmoothPlastic)
	local win = B.block(houseAt * CFrame.new(8, 7, 14.1), Vector3.new(4, 4, 0.4), rgb(255, 210, 120), Enum.Material.Neon)
	B.light(win, rgb(255, 190, 110), 30, 2)
	B.block(houseAt * CFrame.new(15.1, 7, 8), Vector3.new(0.4, 4, 4), rgb(255, 210, 120), Enum.Material.Neon)
	for i = 0, 12 do
		B.block(fort * CFrame.new(11, 3 + i * 3.4, 0), Vector3.new(0.6, 0.5, 4), rgb(160, 115, 70), Enum.Material.Wood)
	end
	-- rolling hills and far purple mountains
	for _ = 1, 30 do
		local p = spot(rng, 150, 320, 180)
		local d = rng:NextNumber(70, 150)
		B.ball(Vector3.new(p.X, -d * 0.32, p.Z), d, pick(rng, { rgb(95, 170, 70), rgb(125, 185, 75), rgb(80, 150, 75), rgb(150, 190, 80) }), Enum.Material.Grass)
	end
	for _ = 1, 11 do
		local p = spot(rng, 380, 560, 180)
		local h = rng:NextNumber(110, 180)
		B.cone(CFrame.new(p), h, h * 1.4, rgb(125, 105, 165), Enum.Material.Rock, 14)
		B.cone(CFrame.new(p + Vector3.new(0, h * 0.72, 0)), h * 0.28, h * 0.42, rgb(250, 235, 240), Enum.Material.Snow, 4)
	end
	-- fireflies over the grass
	B.particles(CFrame.new(0, 2.5, -10), Vector3.new(110, 4, 90), { speed = { 0.1, 0.4 }, life = { 2.5, 4 }, rate = 18, size = { 0.22, 0.05 }, colors = { rgb(255, 250, 140), rgb(190, 255, 120) }, glow = 1, spread = 180 })
end

THEMES.Ice = {
	-- The wide opening shot when a match starts, before the camera settles at your seat.
	intro = { pos = Vector3.new(-24, 26, 40), look = Vector3.new(50, 18, -60), fov = 62, drift = Vector3.new(7, -4, -8) },
	lighting = {
		ClockTime = 23,
		Brightness = 1.2,
		Ambient = rgb(95, 110, 145),
		OutdoorAmbient = rgb(115, 135, 195),
		ColorShift_Top = rgb(180, 220, 255),
		ColorShift_Bottom = rgb(60, 60, 110),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.8,
		ExposureCompensation = 0.25,
	},
	atmosphere = { Density = 0.3, Offset = 0.1, Color = rgb(150, 200, 255), Decay = rgb(110, 90, 215), Glare = 0, Haze = 1 },
	sky = { StarCount = 3000, CelestialBodiesShown = true, MoonAngularSize = 16 },
	bloom = { Intensity = 0.45, Size = 26, Threshold = 1.6 },
	color = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.22, TintColor = rgb(235, 245, 255) },
	depth = { FarIntensity = 0.06, FocusDistance = 30, InFocusRadius = 45 },
	preview = { sky = rgb(40, 50, 110), fog = rgb(120, 150, 220), fogDensity = 0.004 },
}
function THEMES.Ice.build(rng)
	B.ground(rgb(232, 242, 255), Enum.Material.Snow)
	-- the frozen lake the table stands on, ringed by snowbanks
	B.disc(0, 0, 0.06, 58, 0.06, rgb(150, 210, 255), Enum.Material.Glacier, { Reflectance = 0.2 })
	for k = 0, 27 do
		local a = k / 28 * math.pi * 2
		local d = rng:NextNumber(4, 7)
		B.ball(Vector3.new(math.cos(a) * 30.5, -d * 0.15, math.sin(a) * 30.5), d, rgb(245, 250, 255), Enum.Material.Snow)
	end
	for _ = 1, 9 do -- glowing cracks in the ice
		local a = rng:NextNumber(0, 6.28)
		local r1 = rng:NextNumber(16, 22)
		local p1 = Vector3.new(math.cos(a) * r1, 0.08, math.sin(a) * r1)
		local p2 = p1 + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
		B.beam(p1, p2, 0.15, 0.02, rgb(150, 240, 255), Enum.Material.Neon, { Transparency = 0.3 })
	end
	-- ice crystal clusters, a few lighting up the snow
	local ICE = { rgb(160, 225, 255), rgb(120, 190, 255), rgb(190, 170, 255), rgb(200, 245, 255) }
	for i = 1, 26 do
		local p = spot(rng, 34, 85, 170)
		crystals(rng, p, rng:NextNumber(4, 11), ICE, i % 2 == 0 and rgb(120, 230, 255) or rgb(170, 130, 255), i <= 6)
	end
	-- snowmen
	for _ = 1, 5 do
		local p = spot(rng, 33, 46, 130)
		local look = towardSeat(p)
		B.ball(p + Vector3.new(0, 1.2, 0), 3, rgb(250, 252, 255), Enum.Material.Snow)
		B.ball(p + Vector3.new(0, 3.3, 0), 2.2, rgb(250, 252, 255), Enum.Material.Snow)
		B.ball(p + Vector3.new(0, 4.9, 0), 1.6, rgb(250, 252, 255), Enum.Material.Snow)
		for _, side in ipairs({ -0.3, 0.3 }) do
			B.ball((look * CFrame.new(side, 5.1, -0.7)).Position, 0.22, rgb(25, 25, 30))
		end
		B.beam((look * CFrame.new(0, 4.85, -0.7)).Position, (look * CFrame.new(0, 4.75, -1.6)).Position, 0.22, 0.22, rgb(255, 130, 30))
		B.cyl(look * CFrame.new(0, 5.5, 0), 0.25, 1.9, rgb(40, 40, 50))
		B.cyl(look * CFrame.new(0, 5.75, 0), 1, 1.2, rgb(40, 40, 50))
		B.block(look * CFrame.new(0, 4.15, 0), Vector3.new(2, 0.4, 2), rgb(220, 40, 60), Enum.Material.Fabric)
		B.beam((look * CFrame.new(-1, 3.5, 0)).Position, (look * CFrame.new(-2.4, 4.6, 0)).Position, 0.15, 0.15, rgb(100, 65, 40), Enum.Material.Wood)
		B.beam((look * CFrame.new(1, 3.5, 0)).Position, (look * CFrame.new(2.4, 4.6, 0)).Position, 0.15, 0.15, rgb(100, 65, 40), Enum.Material.Wood)
	end
	-- snowy pines
	for _ = 1, 32 do
		local p = spot(rng, 45, 150, 180)
		pineTree(rng, p, rng:NextNumber(9, 17), true)
	end
	-- the Ice King's castle on its mountain (north-east)
	local m = CFrame.new(110, 0, -170)
	B.cone(m, 60, 130, rgb(200, 228, 255), Enum.Material.Glacier, 10, nil, 40)
	local top = m * CFrame.new(0, 60, 0)
	B.cyl(top, 22, 30, rgb(150, 210, 255), Enum.Material.Glass, { Transparency = 0.15, Reflectance = 0.2 })
	B.cone(top * CFrame.new(0, 22, 0), 26, 22, rgb(120, 190, 255), Enum.Material.Glass, 7, { Transparency = 0.1 })
	local gem = B.ball(top * CFrame.new(0, 50, 0), 5, rgb(140, 240, 255), Enum.Material.Neon)
	B.light(gem, rgb(140, 220, 255), 40, 2)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + 0.4
		local tc = top * CFrame.new(math.cos(a) * 17, 0, math.sin(a) * 17)
		B.cyl(tc, 30, 7, rgb(170, 220, 255), Enum.Material.Glass, { Transparency = 0.15 })
		B.cone(tc * CFrame.new(0, 30, 0), 14, 8, rgb(110, 170, 255), Enum.Material.Glass, 5, { Transparency = 0.1 })
		B.block(tc * CFrame.new(0, 18, 0), Vector3.new(7.4, 1, 7.4), rgb(120, 230, 255), Enum.Material.Neon)
	end
	-- mountains all around
	for _ = 1, 14 do
		local p = spot(rng, 260, 480, 180)
		local h = rng:NextNumber(90, 170)
		B.cone(CFrame.new(p), h, h * 1.3, rgb(170, 185, 215), Enum.Material.Rock, 14)
		B.cone(CFrame.new(p + Vector3.new(0, h * 0.55, 0)), h * 0.45, h * 0.62, rgb(245, 250, 255), Enum.Material.Snow, 6)
	end
	-- the northern lights
	arc(Vector3.new(-40, -60, -300), math.rad(10), 160, { rgb(90, 255, 170), rgb(70, 220, 230), rgb(150, 110, 255) }, 14, 18, 0.62)
	arc(Vector3.new(200, -80, -120), math.rad(-70), 150, { rgb(120, 255, 190), rgb(190, 120, 255) }, 14, 16, 0.66)
	-- falling snow and ice sparkles
	B.particles(CFrame.new(0, 26, -10), Vector3.new(150, 2, 130), { dir = Enum.NormalId.Bottom, speed = { 3, 5 }, life = { 6, 8 }, rate = 60, size = { 0.3, 0.2 }, colors = { rgb(255, 255, 255) }, glow = 0.3, spread = 15, spin = 40 })
	B.particles(CFrame.new(0, 2, -8), Vector3.new(80, 3, 70), { speed = { 0.05, 0.2 }, life = { 1, 2 }, rate = 10, size = { 0.2, 0 }, colors = { rgb(170, 240, 255), rgb(255, 255, 255) }, glow = 1, spread = 180 })
end

THEMES.Fire = {
	-- The wide opening shot when a match starts, before the camera settles at your seat.
	intro = { pos = Vector3.new(0, 27, 44), look = Vector3.new(0, 14, -70), fov = 64, drift = Vector3.new(0, -4, -9) },
	lighting = {
		ClockTime = 19.5,
		Brightness = 1.2,
		Ambient = rgb(115, 60, 45),
		OutdoorAmbient = rgb(160, 75, 55),
		ColorShift_Top = rgb(255, 150, 90),
		ColorShift_Bottom = rgb(120, 30, 10),
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0.15,
	},
	atmosphere = { Density = 0.38, Offset = 0, Color = rgb(255, 125, 75), Decay = rgb(140, 25, 20), Glare = 0.6, Haze = 2.4 },
	sky = { StarCount = 0, CelestialBodiesShown = false },
	bloom = { Intensity = 0.55, Size = 28, Threshold = 1.5 },
	color = { Brightness = 0.02, Contrast = 0.18, Saturation = 0.25, TintColor = rgb(255, 235, 222) },
	depth = { FarIntensity = 0.08, FocusDistance = 30, InFocusRadius = 45 },
	preview = { sky = rgb(150, 45, 30), fog = rgb(200, 80, 50), fogDensity = 0.005 },
}
function THEMES.Fire.build(rng)
	B.ground(rgb(70, 45, 40), Enum.Material.CrackedLava)
	-- the obsidian plaza with a glowing rim
	B.disc(0, 0, 0.05, 56, 0.05, rgb(255, 110, 30), Enum.Material.Neon)
	B.disc(0, 0, 0.1, 54, 0.06, rgb(35, 28, 34), Enum.Material.Basalt, { Reflectance = 0.06 })
	for k = 0, 11 do -- gold inlay spokes
		local a = k / 12 * math.pi * 2
		B.beam(Vector3.new(math.cos(a) * 17, 0.12, math.sin(a) * 17), Vector3.new(math.cos(a) * 26, 0.12, math.sin(a) * 26), 0.4, 0.03, rgb(230, 170, 70), Enum.Material.Metal)
	end
	-- a ring of flaming torches
	for k = 0, 9 do
		local a = (k + 0.5) / 10 * math.pi * 2
		local p = Vector3.new(math.cos(a) * 29.5, 0, math.sin(a) * 29.5)
		B.cyl(CFrame.new(p), 4, 1.3, rgb(45, 36, 40), Enum.Material.Basalt)
		B.cyl(CFrame.new(p + Vector3.new(0, 4, 0)), 0.7, 2.4, rgb(70, 55, 50), Enum.Material.Metal)
		local flame = B.ball(p + Vector3.new(0, 5.1, 0), 1.6, rgb(255, 150, 40), Enum.Material.Neon)
		local fire = Instance.new("Fire")
		fire.Size = 5
		fire.Heat = 9
		fire.Color = rgb(255, 120, 30)
		fire.SecondaryColor = rgb(255, 220, 80)
		fire.Parent = flame
		if k % 2 == 0 then
			B.light(flame, rgb(255, 140, 50), 18, 2)
		end
	end
	-- the lava river, bubbling
	river(rng, -42, 7, 160, rgb(255, 100, 25), Enum.Material.Neon, nil, function(seg, a, b)
		if rng:NextNumber() < 0.3 then
			B.ball(a:Lerp(b, rng:NextNumber()) + Vector3.new(rng:NextNumber(-2, 2), 0.2, rng:NextNumber(-2, 2)), rng:NextNumber(0.8, 1.6), rgb(255, 200, 60), Enum.Material.Neon)
		end
		if rng:NextNumber() < 0.13 then
			B.light(seg, rgb(255, 110, 40), 24, 2)
		end
	end)
	B.particles(CFrame.new(0, 0.5, -42), Vector3.new(200, 1, 14), { speed = { 1, 3 }, life = { 1, 2.2 }, rate = 30, size = { 0.3, 0 }, colors = { rgb(255, 220, 90), rgb(255, 80, 30) }, glow = 1, spread = 25 })
	-- obsidian spires with glowing veins
	for _ = 1, 30 do
		local p = spot(rng, 33, 95, 170)
		local h = rng:NextNumber(4, 16)
		local cf = CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6.28), rng:NextNumber(-0.25, 0.25))
		B.cone(cf, h, h * 0.35, rgb(40, 32, 38), Enum.Material.Basalt, 4)
		B.block(cf * CFrame.new(0, h * 0.35, -h * 0.1), Vector3.new(0.25, h * 0.6, 0.25), rgb(255, 110, 30), Enum.Material.Neon)
	end
	-- fire crystals
	for i = 1, 12 do
		local p = spot(rng, 36, 70, 160)
		crystals(rng, p, rng:NextNumber(3, 7), { rgb(255, 120, 50), rgb(255, 60, 60), rgb(255, 190, 70) }, rgb(255, 130, 40), i <= 3)
	end
	-- smoking volcanoes with lava running down them
	for i = 1, 6 do
		local p = spot(rng, 140, 360, 180)
		local h = rng:NextNumber(70, 140)
		local d = h * 1.6
		local base = CFrame.new(p)
		B.cone(base, h, d, rgb(60, 40, 40), Enum.Material.Basalt, 16, nil, d * 0.25)
		local crater = B.cyl(base * CFrame.new(0, h - 0.5, 0), 1, d * 0.2, rgb(255, 120, 30), Enum.Material.Neon)
		B.light(crater, rgb(255, 120, 40), 60, 3)
		for s = 1, 3 do
			local a = rng:NextNumber(0, 6.28)
			local topP = p + Vector3.new(math.cos(a) * d * 0.11, h, math.sin(a) * d * 0.11)
			local botP = p + Vector3.new(math.cos(a) * d * 0.45, 2, math.sin(a) * d * 0.45)
			B.beam(topP, botP, rng:NextNumber(2, 4), 1, rgb(255, 100, 25), Enum.Material.Neon)
		end
		if i <= 3 then
			B.particles(base * CFrame.new(0, h + 2, 0), Vector3.new(d * 0.15, 1, d * 0.15), { texture = "rbxasset://textures/particles/smoke_main.dds", speed = { 6, 10 }, life = { 6, 9 }, rate = 6, size = { 12, 30 }, colors = { rgb(90, 70, 70), rgb(40, 35, 40) }, glow = 0, alpha = 0.35, spread = 12 })
		end
	end
	-- embers in the air
	B.particles(CFrame.new(0, 1, -10), Vector3.new(120, 2, 100), { speed = { 1, 2.5 }, life = { 2, 4 }, rate = 30, size = { 0.2, 0 }, colors = { rgb(255, 210, 90), rgb(255, 70, 30) }, glow = 1, spread = 30, accel = Vector3.new(0, 0.5, 0) })
end

THEMES.Space = {
	-- The wide opening shot when a match starts, before the camera settles at your seat.
	intro = { pos = Vector3.new(24, 26, 40), look = Vector3.new(-50, 10, -60), fov = 62, drift = Vector3.new(-7, -4, -8) },
	lighting = {
		ClockTime = 0,
		Brightness = 0.6,
		Ambient = rgb(100, 85, 145),
		OutdoorAmbient = rgb(85, 75, 135),
		ColorShift_Top = rgb(200, 170, 255),
		ColorShift_Bottom = rgb(40, 30, 80),
		EnvironmentDiffuseScale = 0.3,
		EnvironmentSpecularScale = 0.8,
		ExposureCompensation = 0.25,
	},
	atmosphere = { Density = 0.02, Offset = 0, Color = rgb(120, 80, 200), Decay = rgb(30, 20, 80), Glare = 0, Haze = 0 },
	sky = { StarCount = 5000, CelestialBodiesShown = false },
	bloom = { Intensity = 0.6, Size = 30, Threshold = 1.4 },
	color = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.28, TintColor = rgb(242, 236, 255) },
	depth = { FarIntensity = 0, FocusDistance = 30, InFocusRadius = 50 },
	preview = { sky = rgb(8, 6, 22), fog = rgb(20, 10, 40), fogDensity = 0.0008 },
}
function THEMES.Space.build(rng)
	-- the asteroid the table stands on
	B.disc(0, 0, 0, 48, 3, rgb(85, 78, 100), Enum.Material.Slate)
	for _ = 1, 14 do
		local a = rng:NextNumber(0, 6.28)
		local r = rng:NextNumber(4, 20)
		local d = rng:NextNumber(10, 22)
		B.ball(Vector3.new(math.cos(a) * r, -3 - d * 0.3, math.sin(a) * r), d, pick(rng, { rgb(80, 72, 95), rgb(95, 85, 110), rgb(70, 62, 85) }), Enum.Material.Rock)
	end
	for _ = 1, 14 do -- glowing veins in the rock
		local a = rng:NextNumber(0, 6.28)
		local r1 = rng:NextNumber(17, 22)
		local p1 = Vector3.new(math.cos(a) * r1, 0.03, math.sin(a) * r1)
		B.beam(p1, p1 + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), 0.18, 0.03, pick(rng, { rgb(90, 230, 255), rgb(220, 110, 255) }), Enum.Material.Neon)
	end
	local CRYSTAL = { rgb(150, 110, 255), rgb(90, 200, 255), rgb(255, 120, 230) }
	for i = 1, 10 do
		local a = (i + rng:NextNumber(-0.3, 0.3)) / 10 * math.pi * 2
		crystals(rng, Vector3.new(math.cos(a) * 21.5, 0, math.sin(a) * 21.5), rng:NextNumber(3, 6), CRYSTAL, i % 2 == 0 and rgb(120, 220, 255) or rgb(230, 120, 255), i % 3 == 0)
	end
	-- planets
	local function planet(pos, d, color, band, ring)
		B.ball(pos, d, color, Enum.Material.SmoothPlastic)
		if band then -- a lighter belt and a darker one
			B.cyl(CFrame.new(pos - Vector3.new(0, d * 0.08, 0)), d * 0.1, d * 1.005, band[1], Enum.Material.SmoothPlastic)
			B.cyl(CFrame.new(pos + Vector3.new(0, d * 0.16, 0)), d * 0.06, d * 0.97, band[2], Enum.Material.SmoothPlastic)
		end
		if ring then
			local tilt = CFrame.new(pos) * CFrame.Angles(ring.tilt, ring.yaw or 0, 0.15)
			B.cyl(tilt * CFrame.new(0, -0.3, 0), 0.6, d * 2.1, ring.color, Enum.Material.Neon, { Transparency = 0.55 })
			B.cyl(tilt * CFrame.new(0, -0.25, 0), 0.5, d * 1.7, ring.inner or ring.color, Enum.Material.Neon, { Transparency = 0.4 })
			B.cyl(tilt * CFrame.new(0, -0.2, 0), 0.4, d * 1.25, rgb(10, 8, 20), Enum.Material.SmoothPlastic, { Transparency = 0.9 })
		end
	end
	planet(Vector3.new(30, -170, -300), 230, rgb(255, 130, 190), { rgb(255, 180, 215), rgb(220, 90, 160) })
	planet(Vector3.new(-160, -45, -190), 90, rgb(240, 180, 110), { rgb(255, 215, 150), rgb(200, 130, 80) }, { color = rgb(255, 220, 160), inner = rgb(255, 170, 120), tilt = 0.35 })
	planet(Vector3.new(175, -25, -95), 70, rgb(70, 170, 255), { rgb(120, 230, 210), rgb(40, 110, 220) })
	B.ball(Vector3.new(130, 5, -60), 16, rgb(200, 200, 215), Enum.Material.Slate) -- its moon
	planet(Vector3.new(-200, 20, 120), 110, rgb(150, 90, 255), { rgb(190, 140, 255), rgb(110, 60, 210) }, { color = rgb(120, 230, 255), tilt = -0.5, yaw = 0.6 })
	planet(Vector3.new(220, 60, 180), 50, rgb(255, 110, 70))
	-- nebula clouds, glowing through each other
	local NEB = { rgb(255, 80, 200), rgb(120, 90, 255), rgb(60, 200, 255), rgb(255, 140, 90) }
	for _ = 1, 22 do
		local p = spot(rng, 380, 620, 180) + Vector3.new(0, rng:NextNumber(-260, 160), 0)
		B.ball(p, rng:NextNumber(160, 320), pick(rng, NEB), Enum.Material.Neon, { Transparency = rng:NextNumber(0.9, 0.95) })
	end
	-- floating asteroids
	for _ = 1, 55 do
		local p = spot(rng, 30, 200, 180) + Vector3.new(0, rng:NextNumber(-70, 35), 0)
		local d = rng:NextNumber(1.5, 12)
		local rock = B.block(CFrame.new(p) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)), Vector3.new(d, d * rng:NextNumber(0.6, 0.9), d * rng:NextNumber(0.6, 1)), pick(rng, { rgb(90, 82, 105), rgb(110, 100, 120), rgb(70, 64, 88) }), Enum.Material.Rock)
		if rng:NextNumber() < 0.25 then
			B.block(rock.CFrame * CFrame.new(0, rock.Size.Y * 0.5, 0), Vector3.new(d * 0.2, d * 0.25, d * 0.2), pick(rng, CRYSTAL), Enum.Material.Neon)
		end
	end
	-- twinkling stars close by
	B.particles(CFrame.new(0, 0, -40), Vector3.new(220, 120, 160), { speed = { 0, 0 }, life = { 1.5, 3 }, rate = 40, size = { 0.5, 0 }, colors = { rgb(255, 255, 255), rgb(170, 220, 255) }, glow = 1, spread = 0 })
end

THEMES.Mall = {
	-- The wide opening shot when a match starts, before the camera settles at your seat.
	intro = { pos = Vector3.new(-24, 24, 40), look = Vector3.new(30, 16, -70), fov = 62, drift = Vector3.new(7, -4, -8) },
	lighting = {
		ClockTime = 0.5,
		Brightness = 0.9,
		Ambient = rgb(90, 75, 125),
		OutdoorAmbient = rgb(95, 85, 150),
		ColorShift_Top = rgb(175, 255, 200),
		ColorShift_Bottom = rgb(55, 30, 85),
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 0.8,
		ExposureCompensation = 0.3,
	},
	atmosphere = { Density = 0.33, Offset = 0.05, Color = rgb(125, 95, 175), Decay = rgb(60, 40, 115), Glare = 0, Haze = 1.4 },
	sky = { StarCount = 1500, CelestialBodiesShown = false },
	bloom = { Intensity = 0.55, Size = 28, Threshold = 1.45 },
	color = { Brightness = 0.02, Contrast = 0.16, Saturation = 0.24, TintColor = rgb(240, 235, 255) },
	depth = { FarIntensity = 0.06, FocusDistance = 30, InFocusRadius = 45 },
	preview = { sky = rgb(30, 20, 60), fog = rgb(90, 70, 140), fogDensity = 0.004 },
}
function THEMES.Mall.build(rng)
	B.ground(rgb(46, 44, 56), Enum.Material.Asphalt)
	-- the round parking-lot plaza: faded paint, cracks and a manhole
	B.disc(0, 0, 0.05, 58, 0.05, rgb(64, 62, 76), Enum.Material.Asphalt)
	B.disc(0, 0, 0.08, 56, 0.03, rgb(90, 86, 104), Enum.Material.Concrete)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		B.block(CFrame.new(math.cos(a) * 21, 0.1, math.sin(a) * 21) * CFrame.Angles(0, -a, 0), Vector3.new(9, 0.03, 0.4), rgb(225, 220, 190), Enum.Material.SmoothPlastic, { Transparency = 0.35 })
	end
	for _ = 1, 26 do
		local p = spot(rng, 13, 30, 180)
		B.block(CFrame.new(p.X, 0.11, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(rng:NextNumber(2, 6), 0.03, 0.18), rgb(30, 28, 38))
	end
	B.disc(-20, -15, 0.13, 4.6, 0.05, rgb(55, 55, 62), Enum.Material.DiamondPlate)
	B.disc(-20, -15, 0.15, 3.6, 0.04, rgb(70, 70, 78), Enum.Material.DiamondPlate)
	-- flickering lamp posts in a ring, their heads a cold green-white
	for k = 0, 9 do
		local a = math.rad(-150 + k * (300 / 9))
		local p = Vector3.new(math.sin(a) * 33, 0, -math.cos(a) * 33)
		B.cyl(CFrame.new(p), 15, 0.7, rgb(60, 62, 70), Enum.Material.Metal)
		local dir = (Vector3.new(0, 0, 0) - p) * Vector3.new(1, 0, 1)
		dir = dir.Unit
		B.beam(p + Vector3.new(0, 15, 0), p + Vector3.new(0, 15, 0) + dir * 3, 0.35, 0.35, rgb(60, 62, 70), Enum.Material.Metal)
		local head = B.block(CFrame.lookAt(p + Vector3.new(0, 14.6, 0) + dir * 3, p + dir * 10), Vector3.new(1.6, 0.5, 2.4), rgb(215, 255, 225), Enum.Material.Neon)
		B.light(head, rgb(190, 255, 210), 26, 1.4)
	end
	-- runaway shopping carts
	for _ = 1, 7 do
		local p = spot(rng, 19, 46, 170)
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), rng:NextNumber() < 0.3 and math.rad(80) or 0)
		local metal = rgb(185, 190, 200)
		B.block(cf * CFrame.new(0, 1.3, 0), Vector3.new(2.2, 0.12, 3.2), metal, Enum.Material.Metal)
		B.block(cf * CFrame.new(1.1, 2.1, 0), Vector3.new(0.1, 1.6, 3.2), metal, Enum.Material.Metal, { Transparency = 0.3 })
		B.block(cf * CFrame.new(-1.1, 2.1, 0), Vector3.new(0.1, 1.6, 3.2), metal, Enum.Material.Metal, { Transparency = 0.3 })
		B.block(cf * CFrame.new(0, 2.1, 1.6), Vector3.new(2.2, 1.6, 0.1), metal, Enum.Material.Metal, { Transparency = 0.3 })
		B.block(cf * CFrame.new(0, 2.1, -1.6), Vector3.new(2.2, 1.6, 0.1), metal, Enum.Material.Metal, { Transparency = 0.3 })
		B.block(cf * CFrame.new(0, 3.2, 2.1), Vector3.new(2.4, 0.2, 0.2), rgb(220, 50, 60))
		for _, w in ipairs({ { 0.9, 1.3 }, { -0.9, 1.3 }, { 0.9, -1.3 }, { -0.9, -1.3 } }) do
			B.ball(cf * CFrame.new(w[1], 0.3, w[2]), 0.6, rgb(30, 30, 34))
		end
	end
	-- the toppled fountain with glowing coins
	local f = CFrame.new(27, 0, -27)
	B.cyl(f, 1.4, 12, rgb(150, 145, 160), Enum.Material.Concrete)
	B.cyl(f * CFrame.new(0, 0.2, 0), 1.3, 10.4, rgb(60, 120, 140), Enum.Material.Glass, { Transparency = 0.3 })
	B.cyl(f * CFrame.new(3, 1.4, 1) * CFrame.Angles(0, 0, math.rad(70)), 6, 1.6, rgb(160, 155, 170), Enum.Material.Concrete)
	for _ = 1, 9 do
		B.disc(27 + rng:NextNumber(-4, 4), -27 + rng:NextNumber(-4, 4), 1.5, 0.6, 0.08, rgb(255, 220, 90), Enum.Material.Neon)
	end
	-- the mall: a long dark facade with shop windows, mannequins and lit glass doors
	local mz = -95
	B.block(CFrame.new(0, 17, mz - 12), Vector3.new(230, 34, 24), rgb(70, 62, 92), Enum.Material.Concrete)
	B.block(CFrame.new(0, 34.5, mz - 12), Vector3.new(234, 2, 26), rgb(48, 42, 66), Enum.Material.Concrete)
	B.block(CFrame.new(0, 8, mz + 0.2), Vector3.new(230, 0.6, 0.6), rgb(160, 120, 255), Enum.Material.Neon, { Transparency = 0.2 })
	for i = -5, 5 do
		local x = i * 19
		if i ~= 0 then
			local lit = rng:NextNumber() < 0.4
			B.block(CFrame.new(x, 6.5, mz + 0.1), Vector3.new(14, 9, 0.4), lit and rgb(120, 90, 190) or rgb(25, 22, 40), Enum.Material.Glass, { Transparency = lit and 0.15 or 0.05, Reflectance = 0.2 })
			if lit or rng:NextNumber() < 0.5 then
				-- a mannequin in the window, turned a little toward the table
				local m = CFrame.lookAt(Vector3.new(x + rng:NextNumber(-3, 3), 0, mz - 2), Vector3.new(0, 0, 0))
				B.cyl(m * CFrame.new(0, 2, 0), 4.2, 1.4, rgb(235, 230, 225))
				B.ball(m * CFrame.new(0, 7, 0), 1.5, rgb(240, 235, 230))
				B.block(m * CFrame.new(0.3, 7.1, -0.7), Vector3.new(0.18, 0.18, 0.1), rgb(160, 255, 140), Enum.Material.Neon, { Name = "MannequinEye" })
				B.block(m * CFrame.new(-0.3, 7.1, -0.7), Vector3.new(0.18, 0.18, 0.1), rgb(160, 255, 140), Enum.Material.Neon, { Name = "MannequinEye", Transparency = 0 })
			end
		end
	end
	-- glass doors and the escalator behind them
	B.block(CFrame.new(0, 6, mz + 0.1), Vector3.new(16, 12, 0.4), rgb(255, 235, 180), Enum.Material.Glass, { Transparency = 0.35 })
	local door = B.block(CFrame.new(0, 6, mz - 1), Vector3.new(15, 11, 0.2), rgb(255, 225, 160), Enum.Material.Neon, { Transparency = 0.55 })
	B.light(door, rgb(255, 220, 160), 40, 1.5)
	B.block(CFrame.new(0, 6, mz - 8) * CFrame.Angles(math.rad(35), 0, 0), Vector3.new(5, 0.6, 16), rgb(90, 90, 100), Enum.Material.Metal)
	-- the broken MALL sign (the landmark): one L is dark
	local sy, sz = 44, mz - 1
	local function bar(x, y, w, h, on)
		B.block(CFrame.new(x, sy + y, sz), Vector3.new(w, h, 0.8), on and rgb(255, 80, 200) or rgb(70, 40, 70), on and Enum.Material.Neon or Enum.Material.SmoothPlastic, { Name = "Landmark" })
	end
	-- M
	bar(-27, 0, 1.4, 9, true)
	bar(-19, 0, 1.4, 9, true)
	B.block(CFrame.new(-25, sy + 1.5, sz) * CFrame.Angles(0, 0, math.rad(-35)), Vector3.new(1.4, 6, 0.8), rgb(255, 80, 200), Enum.Material.Neon, { Name = "Landmark" })
	B.block(CFrame.new(-21, sy + 1.5, sz) * CFrame.Angles(0, 0, math.rad(35)), Vector3.new(1.4, 6, 0.8), rgb(255, 80, 200), Enum.Material.Neon, { Name = "Landmark" })
	-- A
	B.block(CFrame.new(-10.5, sy, sz) * CFrame.Angles(0, 0, math.rad(-18)), Vector3.new(1.4, 9.4, 0.8), rgb(255, 80, 200), Enum.Material.Neon, { Name = "Landmark" })
	B.block(CFrame.new(-5.5, sy, sz) * CFrame.Angles(0, 0, math.rad(18)), Vector3.new(1.4, 9.4, 0.8), rgb(255, 80, 200), Enum.Material.Neon, { Name = "Landmark" })
	bar(-8, -1, 4.4, 1.2, true)
	-- L L (the second one is out)
	bar(3, 0, 1.4, 9, true)
	bar(5.6, -3.9, 4, 1.2, true)
	bar(13, 0, 1.4, 9, false)
	bar(15.6, -3.9, 4, 1.2, false)
	local signLight = B.block(CFrame.new(-6, sy, sz + 2), Vector3.new(1, 1, 1), rgb(255, 80, 200), Enum.Material.SmoothPlastic, { Transparency = 1, Name = "Landmark" })
	B.light(signLight, rgb(255, 90, 210), 50, 2)
	-- the low moon with its green halo
	local moonAt = Vector3.new(70, 120, -380)
	B.ball(moonAt, 64, rgb(235, 245, 215), Enum.Material.Neon)
	B.facing(moonAt + Vector3.new(0, 0, -8), Vector3.new(0, 6, 14), 120, 0.5, rgb(150, 255, 170), Enum.Material.Neon, { Transparency = 0.85 })
	-- a dark town all around: blocky buildings with a few lit windows
	for _ = 1, 34 do
		local p = spot(rng, 150, 330, 180)
		local h = rng:NextNumber(20, 70)
		local w = rng:NextNumber(18, 40)
		local b = B.block(CFrame.new(p.X, h / 2, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(w, h, w * rng:NextNumber(0.6, 1)), pick(rng, { rgb(40, 36, 58), rgb(52, 46, 72), rgb(34, 32, 48) }), Enum.Material.Concrete)
		if rng:NextNumber() < 0.6 then
			B.block(b.CFrame * CFrame.new(0, h * rng:NextNumber(-0.2, 0.3), -b.Size.Z / 2 - 0.1), Vector3.new(3, 2.5, 0.2), rgb(255, 210, 120), Enum.Material.Neon)
		end
	end
	-- purple ground fog, drifting flyers and little green wisps
	B.particles(CFrame.new(0, 0.6, -10), Vector3.new(130, 1, 110), { texture = "rbxasset://textures/particles/smoke_main.dds", speed = { 0.2, 0.6 }, life = { 5, 8 }, rate = 10, size = { 6, 12 }, colors = { rgb(140, 100, 200), rgb(90, 60, 150) }, glow = 0.1, alpha = 0.7, spread = 180 })
	B.particles(CFrame.new(0, 3, -10), Vector3.new(90, 4, 80), { speed = { 0.6, 1.4 }, life = { 4, 6 }, rate = 3, size = { 0.7, 0.7 }, colors = { rgb(240, 235, 220) }, glow = 0, alpha = 0.1, spread = 180, spin = 60 })
	B.particles(CFrame.new(0, 4, -8), Vector3.new(80, 6, 70), { speed = { 0.1, 0.4 }, life = { 2.5, 4 }, rate = 12, size = { 0.3, 0.05 }, colors = { rgb(170, 255, 150), rgb(120, 255, 200) }, glow = 1, spread = 180 })
end

-- Build a world into `folder` (which should not be in the workspace yet), moved by `offset`.
-- Used by the pack pull's biome stage: the same world as the match backdrop, built somewhere
-- else, without hiding the room or touching the lighting. Returns the theme and the part count.
function Backdrops.buildInto(key, folder, offset)
	local theme = THEMES[key]
	if not theme or not folder then
		return nil, 0
	end
	local prevFolder, prevCount = S.folder, S.count
	S.folder, S.count = folder, 0
	local ok, err = pcall(theme.build, Random.new(20260 + #key * 17))
	local n = S.count
	S.folder, S.count = prevFolder, prevCount
	if not ok then
		warn("[Backdrops] building " .. key .. " failed: " .. tostring(err))
	end
	if offset and offset.Magnitude > 0 then
		for _, p in ipairs(folder:GetChildren()) do
			if p:IsA("BasePart") then
				p.CFrame = p.CFrame + offset
			end
		end
	end
	return theme, n
end

---------------------------------------------------------------------------
-- Turning a world on and off
---------------------------------------------------------------------------

-- The hanging table lamps disappear outdoors (there's no ceiling to hang from) but keep their light.
local LAMP = { TableLampCord = true, TableLampShade = true, TableLampTop = true, TableLampRim = true, TableLamp = true }
local LIGHT_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation" }

local function hideRoom(room, duelTable)
	for _, d in ipairs(room:GetDescendants()) do
		local inTable = d:IsDescendantOf(duelTable)
		if d:IsA("BasePart") then
			if not inTable or LAMP[d.Name] then
				save(d, "Transparency")
				d.Transparency = 1
			end
		elseif not inTable then
			if d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				save(d, "Enabled")
				d.Enabled = false
			elseif d:IsA("Decal") or d:IsA("Texture") then
				save(d, "Transparency")
				d.Transparency = 1
			end
		end
	end
end

local function setProps(inst, props)
	if not (inst and props) then
		return
	end
	for k, v in pairs(props) do
		save(inst, k)
		inst[k] = v
	end
end

local function setLighting(theme)
	local l = {}
	for _, k in ipairs(LIGHT_PROPS) do
		l[k] = theme.lighting[k]
	end
	setProps(Lighting, l)
	setProps(Lighting:FindFirstChildOfClass("BloomEffect"), theme.bloom)
	setProps(Lighting:FindFirstChildOfClass("ColorCorrectionEffect"), theme.color)
	setProps(Lighting:FindFirstChildOfClass("DepthOfFieldEffect"), theme.depth)
	-- Our own sky and atmosphere; any that were there step aside until the match ends.
	for _, cls in ipairs({ "Sky", "Atmosphere" }) do
		local old = Lighting:FindFirstChildOfClass(cls)
		if old then
			table.insert(S.removed, old)
			old.Parent = nil
		end
	end
	local sky = Instance.new("Sky")
	for k, v in pairs(theme.sky or {}) do
		sky[k] = v
	end
	sky.Name = "MatchBackdropSky"
	sky.Parent = Lighting
	table.insert(S.added, sky)
	local atmo = Instance.new("Atmosphere")
	for k, v in pairs(theme.atmosphere or {}) do
		atmo[k] = v
	end
	atmo.Name = "MatchBackdropAtmosphere"
	atmo.Parent = Lighting
	table.insert(S.added, atmo)
end

-- Put a world around the table. `key` is one of Backdrops.List ("Random" picks one). Returns the
-- key it actually used.
function Backdrops.apply(key, room, duelTable)
	Backdrops.clear()
	if key == "Random" then
		local options = {}
		for _, b in ipairs(Backdrops.List) do
			if THEMES[b.key] then
				table.insert(options, b.key)
			end
		end
		key = options[math.random(1, #options)]
	end
	local theme = THEMES[key]
	if not theme or not room or not duelTable then
		return "Room"
	end
	S.current = key
	S.count = 0
	S.folder = Instance.new("Folder")
	S.folder.Name = "MatchBackdrop"
	S.folder.Parent = workspace
	hideRoom(room, duelTable)
	setLighting(theme)
	-- The same world every time you pick it (only the particles move).
	theme.build(Random.new(20260 + #key * 17))
	return key
end

-- Put the room and the lighting back.
function Backdrops.clear()
	for i = #S.saved, 1, -1 do
		local s = S.saved[i]
		pcall(function()
			s[1][s[2]] = s[3]
		end)
	end
	S.saved = {}
	for _, inst in ipairs(S.added) do
		inst:Destroy()
	end
	S.added = {}
	for _, inst in ipairs(S.removed) do
		inst.Parent = Lighting
	end
	S.removed = {}
	if S.folder then
		S.folder:Destroy()
		S.folder = nil
	end
	S.current = nil
end

-- The world that's up (nil for the room) and how many parts it's made of.
function Backdrops.current()
	return S.current, S.count
end

-- The opening shot of the world that's up, or nil.
function Backdrops.intro()
	local theme = S.current and THEMES[S.current]
	return theme and theme.intro
end

Backdrops.THEMES = THEMES
return Backdrops

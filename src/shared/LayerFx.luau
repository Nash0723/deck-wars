-- LayerFx: painted effects made of four pictures on top of each other.
--
-- Every effect picture is drawn as four layers (vfx/draw_layers.py):
--     glow   a soft bloom behind everything
--     rim    the whole silhouette, in the dark, saturated colour
--     middle a smaller shape inside it, in the bright colour
--     core   the hottest part, nearly white
-- A still picture looks flat, so the layers never move together: the core snaps out first and
-- dies first, the middle follows, the rim arrives last and lingers, and the glow swells behind
-- them. Bits of paint are thrown out on top. That offset is what makes a hit feel like a hit.
--
--   local LayerFx = require(ReplicatedStorage.DeckWars.LayerFx)
--   LayerFx.play("hit", position, { palette = "ember", size = 5, aim = direction })
--   LayerFx.play("bolt", from, { to = target, palette = "frost" })
--   LayerFx.play("slam", tableTop, { palette = "gold", size = 7 })      -- lies flat
--   LayerFx.screen("hit", someFrame, UDim2.fromScale(0.5, 0.5), 260, { palette = "gold" })
--
-- Client only. The pictures are uploaded images (VfxAssets); an effect whose sheet has no id
-- yet is skipped, and play() returns nil.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Assets = require(script.Parent:WaitForChild("VfxAssets"))
local Settings = nil
pcall(function()
	Settings = require(script.Parent:WaitForChild("Settings"))
end)

local LayerFx = {}
LayerFx.Assets = Assets

local Q = 512 -- one layer on a sheet
local RECT = { Vector2.new(0, 0), Vector2.new(Q, 0), Vector2.new(0, Q), Vector2.new(Q, Q) }
local GLOW, RIM, MID, CORE = 1, 2, 3, 4
-- the four loose pictures on the "bits" sheet
local DOT, DASH, CHIP, CURL = 1, 2, 3, 4

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- glow, rim, middle, core
LayerFx.Palettes = {
	ember = { rgb(255, 150, 40), rgb(196, 84, 12), rgb(255, 184, 62), rgb(255, 250, 226) },
	gold = { rgb(255, 196, 70), rgb(176, 108, 14), rgb(255, 214, 96), rgb(255, 252, 232) },
	blood = { rgb(255, 70, 60), rgb(150, 20, 30), rgb(255, 104, 80), rgb(255, 236, 220) },
	frost = { rgb(90, 190, 255), rgb(30, 96, 190), rgb(120, 214, 255), rgb(240, 252, 255) },
	arcane = { rgb(176, 110, 255), rgb(92, 40, 176), rgb(196, 150, 255), rgb(250, 240, 255) },
	verdant = { rgb(110, 240, 140), rgb(26, 132, 70), rgb(150, 250, 150), rgb(244, 255, 232) },
	rust = { rgb(226, 150, 90), rgb(120, 74, 40), rgb(222, 164, 104), rgb(255, 240, 214) },
	steel = { rgb(130, 226, 240), rgb(60, 104, 130), rgb(170, 226, 238), rgb(246, 255, 255) },
	holy = { rgb(255, 236, 170), rgb(214, 160, 50), rgb(255, 240, 180), rgb(255, 255, 255) },
	smoke = { rgb(120, 120, 140), rgb(52, 50, 66), rgb(128, 126, 146), rgb(214, 214, 226) },
	rose = { rgb(255, 110, 150), rgb(176, 30, 80), rgb(255, 150, 176), rgb(255, 240, 244) },
}

-- Which colours a card family fights in.
LayerFx.FamilyPalette = {
	Snack = "ember",
	Junk = "rust",
	Weather = "frost",
	Critter = "verdant",
	Spooky = "arcane",
	Robo = "steel",
	Any = "gold",
}

-- Card rarities, for pack reveals.
LayerFx.RarityPalette = {
	Common = "smoke",
	Rare = "frost",
	Epic = "arcane",
	Mythic = "rose",
	Legendary = "gold",
	Secret = "holy",
}

-- Four layer colours made from one colour (for things that already have a colour of their own).
function LayerFx.paletteFrom(color)
	local black, white = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
	return { color, color:Lerp(black, 0.45), color:Lerp(white, 0.25), color:Lerp(white, 0.88) }
end

function LayerFx.paletteFor(family)
	return LayerFx.FamilyPalette[family] or "gold"
end

---------------------------------------------------------------------------
-- Easing
---------------------------------------------------------------------------
local function outCubic(t)
	local u = 1 - t
	return 1 - u * u * u
end
local function outBack(t)
	local c1, c3 = 1.70158, 2.70158
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end
local function lerp(a, b, t)
	return a + (b - a) * t
end

---------------------------------------------------------------------------
-- Recipes
--
-- A recipe is a list of sprites. Each sprite is one layer of one sheet with its own timing:
--   s sheet, l layer (1 glow .. 4 core), c palette slot (defaults to l)
--   t0, t1    when it lives, as fractions of the effect's length
--   from, to  its size (1 = the size the effect was asked for)
--   grow      the part of its life in which it reaches `to` (it keeps drifting after)
--   drift     extra size it creeps up to by the end
--   a         how solid it is at its peak; fade = where in its life it starts to fade
--   r0, r1    rotation in degrees;  x0,y0,x1,y1 where it sits (0 = middle, 1 = one size away)
--   back      overshoot like a spring
---------------------------------------------------------------------------
local function sprite(s, l, t0, t1, from, to, o)
	o = o or {}
	o.s, o.l, o.t0, o.t1, o.from, o.to = s, l, t0, t1, from, to
	return o
end

-- The four layers of one sheet, timed so they never move as one picture.
local function stack(list, s, o)
	o = o or {}
	local t0, len = o.t0 or 0, o.len or 1
	local size, from = o.size or 1, o.from or 0.3
	local r, spin = o.r or 0, o.spin or 0
	local x, y = o.x or 0, o.y or 0
	local function add(l, a0, a1, f, k, extra)
		local sp = sprite(s, l, t0 + a0 * len, t0 + a1 * len, size * f, size * k, {
			r0 = r - spin * (5 - l) * 0.5,
			r1 = r + spin * (5 - l) * 0.5,
			x0 = x, y0 = y, x1 = x + (o.dx or 0), y1 = y + (o.dy or 0),
			ax = o.ax, ay = o.ay,
			back = o.back ~= false and l ~= GLOW,
		})
		for key, v in pairs(extra) do
			sp[key] = v
		end
		table.insert(list, sp)
	end
	add(GLOW, 0.0, 1.0, from * 1.6, 1.3, { a = o.glow or 0.5, grow = 0.5, fade = 0.3, drift = 0.25 })
	add(RIM, 0.04, 1.0, from, 1.0, { a = 1, grow = 0.34, fade = 0.6, drift = 0.1 })
	add(MID, 0.02, 0.82, from, 1.0, { a = 1, grow = 0.3, fade = 0.5, drift = 0.05 })
	add(CORE, 0.0, 0.6, from * 1.5, 1.08, { a = 1, grow = 0.24, fade = 0.35 })
	return list
end

-- Loose paint thrown outward from the middle.
local function throw(list, pic, n, o)
	o = o or {}
	local seed = o.seed or 1
	for i = 1, n do
		-- a fixed scatter, so an effect looks the same every time (and tests can count on it)
		local h = (i * 0.618034 + seed * 0.37) % 1
		local h2 = (i * 0.414214 + seed * 0.71) % 1
		local ang = (o.a0 or 0) + ((i - 1 + h * 0.8) / n) * (o.arc or math.pi * 2)
		local far = lerp(o.near or 0.45, o.far or 0.85, h2)
		local t0 = (o.t0 or 0.02) + h * 0.12
		local c, s = math.cos(ang), math.sin(ang)
		table.insert(list, sprite("bits", pic, t0, math.min(1, t0 + (o.life or 0.6) * (0.7 + 0.5 * h2)), (o.size or 0.16) * (0.7 + 0.6 * h), (o.size or 0.16) * 0.35, {
			c = o.c or ((i % 3 == 0) and CORE or MID),
			a = 1, grow = 1, fade = 0.55,
			x0 = c * (o.start or 0.12), y0 = s * (o.start or 0.12) * (o.squash or 1),
			x1 = c * far, y1 = s * far * (o.squash or 1) + (o.fall or 0),
			r0 = math.deg(ang), r1 = math.deg(ang) + (o.twirl or 0),
			ease = "out",
			bit = true,
		}))
	end
	return list
end

local R = {}

-- A blow lands: the star of the hit, a white glint in its heart, paint flying off.
R.hit = { len = 0.42, sprites = (function()
	local l = stack({}, "burst", { spin = 10 })
	table.insert(l, sprite("spark", CORE, 0, 0.4, 0.3, 0.95, { a = 1, grow = 0.4, fade = 0.3, r0 = 0, r1 = 25, c = CORE }))
	throw(l, DASH, 9, { near = 0.5, far = 0.95, size = 0.2, seed = 3 })
	return l
end)() }

-- A heavier blow: two stars a moment apart and a ring bursting out behind them.
R.bigHit = { len = 0.6, sprites = (function()
	local l = {}
	table.insert(l, sprite("ring", RIM, 0.05, 0.9, 0.4, 1.45, { a = 0.9, grow = 0.6, fade = 0.4, c = RIM }))
	table.insert(l, sprite("ring", CORE, 0.02, 0.6, 0.4, 1.4, { a = 1, grow = 0.5, fade = 0.3, c = CORE }))
	stack(l, "burst", { spin = 14, len = 0.8 })
	stack(l, "burst", { t0 = 0.14, len = 0.7, size = 0.62, r = 140, spin = -12, x = 0.14, y = -0.1, glow = 0.3 })
	table.insert(l, sprite("spark", CORE, 0, 0.36, 0.4, 1.3, { a = 1, grow = 0.4, fade = 0.3, r0 = 0, r1 = 30, c = CORE }))
	throw(l, DASH, 14, { near = 0.6, far = 1.2, size = 0.22, seed = 5 })
	throw(l, CHIP, 6, { near = 0.4, far = 0.9, size = 0.12, seed = 8, twirl = 240, fall = 0.25 })
	return l
end)() }

-- A swing of a weapon or claw (drawn swinging "forward": aim it with opts.aim).
R.slash = { len = 0.34, aimTurn = 90, sprites = (function()
	local l = {}
	local function swipe(layer, t0, t1, from, fade, a)
		table.insert(l, sprite("slash", layer, t0, t1, from, 1.0, { a = a or 1, grow = 0.3, fade = fade, drift = 0.12, r0 = -38, r1 = 8, y0 = 0.12, y1 = -0.06 }))
	end
	swipe(GLOW, 0, 1, 0.7, 0.3, 0.5)
	swipe(RIM, 0.06, 1, 0.62, 0.55)
	swipe(MID, 0.03, 0.8, 0.62, 0.45)
	swipe(CORE, 0, 0.55, 0.66, 0.3)
	throw(l, DASH, 5, { a0 = -math.pi * 0.85, arc = math.pi * 0.7, near = 0.5, far = 0.9, size = 0.15, seed = 2 })
	return l
end)() }

-- Something heavy lands: a ring racing out over the ground and dust thrown up. Lies flat.
R.slam = { len = 0.6, flat = true, sprites = (function()
	local l = {}
	table.insert(l, sprite("ring", GLOW, 0, 1, 0.3, 1.2, { a = 0.55, grow = 0.6, fade = 0.3 }))
	table.insert(l, sprite("ring", RIM, 0.05, 1, 0.25, 1.0, { a = 1, grow = 0.5, fade = 0.5, drift = 0.14, r0 = 0, r1 = 14 }))
	table.insert(l, sprite("ring", MID, 0.02, 0.8, 0.25, 1.0, { a = 1, grow = 0.45, fade = 0.45, drift = 0.08, r0 = 0, r1 = 9 }))
	table.insert(l, sprite("ring", CORE, 0, 0.55, 0.3, 1.02, { a = 1, grow = 0.4, fade = 0.3, r0 = 0, r1 = 5 }))
	table.insert(l, sprite("burst", MID, 0, 0.4, 0.2, 0.55, { a = 0.9, grow = 0.5, fade = 0.3, c = CORE }))
	throw(l, CHIP, 8, { near = 0.55, far = 1.05, size = 0.1, seed = 4, twirl = 200 })
	return l
end)() }

-- A spell circle turning on the ground. Lies flat.
R.circle = { len = 1.0, flat = true, sprites = (function()
	local l = {}
	table.insert(l, sprite("circle", GLOW, 0, 1, 0.5, 1.0, { a = 0.6, grow = 0.25, fade = 0.7 }))
	table.insert(l, sprite("circle", RIM, 0, 1, 0.3, 1.0, { a = 1, grow = 0.22, fade = 0.72, r0 = -50, r1 = 40, back = true }))
	table.insert(l, sprite("circle", MID, 0.05, 0.95, 0.3, 1.0, { a = 1, grow = 0.22, fade = 0.7, r0 = 60, r1 = -50, back = true }))
	table.insert(l, sprite("circle", CORE, 0.1, 0.9, 0.2, 1.0, { a = 1, grow = 0.2, fade = 0.7, r0 = 0, r1 = 120, back = true }))
	return l
end)() }

-- A column of light shooting up (stands on its foot: the position is the ground).
R.pillar = { len = 0.8, sprites = (function()
	local l = {}
	local function col(layer, t0, t1, w0, fade, a)
		-- anchored at its foot: it stretches up, then thins away
		table.insert(l, sprite("pillar", layer, t0, t1, 0.2, 1.0, { a = a or 1, grow = 0.26, fade = fade, ax = 0.5, ay = 0.93, wide0 = w0, wide1 = 0.45, back = layer ~= GLOW }))
	end
	col(GLOW, 0, 1, 1.5, 0.35, 0.55)
	col(RIM, 0.05, 1, 1.25, 0.55)
	col(MID, 0.02, 0.85, 1.25, 0.45)
	col(CORE, 0, 0.6, 1.3, 0.3)
	throw(l, DASH, 8, { a0 = -math.pi * 0.8, arc = math.pi * 0.6, near = 0.35, far = 0.95, size = 0.12, seed = 6, start = 0.05, t0 = 0.1 })
	table.insert(l, sprite("spark", CORE, 0.05, 0.5, 0.1, 0.5, { a = 1, grow = 0.4, fade = 0.4, y0 = 0, y1 = 0, c = CORE }))
	return l
end)() }

-- A thrown bolt (give opts.to; it flies there, then use "hit").
R.bolt = { len = 0.3, travels = true, sprites = (function()
	local l = {}
	local function b(layer, t0, a, from)
		table.insert(l, sprite("bolt", layer, t0, 1, from, 1.0, { a = a, grow = 0.3, fade = 0.85 }))
	end
	b(GLOW, 0, 0.55, 0.6)
	b(RIM, 0.08, 1, 0.4)
	b(MID, 0.04, 1, 0.5)
	b(CORE, 0, 1, 0.6)
	return l
end)() }

-- Something is knocked out: a fat cloud that billows and breaks up.
R.puff = { len = 0.7, sprites = (function()
	local l = {}
	table.insert(l, sprite("puff", GLOW, 0, 0.8, 0.5, 1.2, { a = 0.4, grow = 0.5, fade = 0.3 }))
	table.insert(l, sprite("puff", RIM, 0, 1, 0.35, 1.0, { a = 1, grow = 0.35, fade = 0.55, drift = 0.2, r0 = -8, r1 = 10, y0 = 0, y1 = -0.12, back = true }))
	table.insert(l, sprite("puff", MID, 0.03, 0.85, 0.3, 1.0, { a = 1, grow = 0.35, fade = 0.45, drift = 0.14, r0 = 6, r1 = -8, y0 = 0, y1 = -0.16, back = true }))
	table.insert(l, sprite("puff", CORE, 0, 0.55, 0.3, 1.0, { a = 1, grow = 0.3, fade = 0.3, y0 = 0, y1 = -0.2, back = true }))
	throw(l, CURL, 6, { near = 0.5, far = 0.95, size = 0.22, seed = 9, twirl = 90, life = 0.7, c = MID })
	throw(l, DOT, 5, { near = 0.4, far = 0.8, size = 0.2, seed = 12, life = 0.8, c = RIM })
	return l
end)() }

-- Mending and blessings: leaves of light fanning upward, glints drifting up after them.
R.bloom = { len = 0.8, sprites = (function()
	local l = stack({}, "bloom", { from = 0.4, dy = -0.12, glow = 0.55, back = true })
	for i = 1, 5 do
		local x = (i - 3) * 0.2
		table.insert(l, sprite("spark", (i % 2 == 0) and CORE or MID, 0.1 + i * 0.07, math.min(1, 0.6 + i * 0.08), 0.05, 0.22, { a = 1, grow = 0.3, fade = 0.5, x0 = x, x1 = x * 1.15, y0 = 0.1, y1 = -0.55 - 0.08 * (i % 3), r0 = 0, r1 = 45, c = (i % 2 == 0) and CORE or MID, bit = true }))
	end
	return l
end)() }

-- A ward flashes up and holds for a beat.
R.shield = { len = 0.7, sprites = (function()
	local l = {}
	table.insert(l, sprite("shield", GLOW, 0, 1, 0.7, 1.12, { a = 0.6, grow = 0.2, fade = 0.55 }))
	table.insert(l, sprite("shield", RIM, 0.03, 1, 0.6, 1.0, { a = 1, grow = 0.2, fade = 0.65, back = true }))
	table.insert(l, sprite("shield", MID, 0.0, 0.9, 0.6, 1.0, { a = 1, grow = 0.2, fade = 0.55, back = true }))
	table.insert(l, sprite("shield", CORE, 0.0, 0.7, 0.6, 1.0, { a = 1, grow = 0.2, fade = 0.3, back = true }))
	table.insert(l, sprite("ring", CORE, 0, 0.5, 0.4, 1.5, { a = 0.8, grow = 0.7, fade = 0.2 }))
	return l
end)() }

-- Ice (or glass, or steel) bursting out in hard spikes.
R.shards = { len = 0.6, sprites = (function()
	local l = stack({}, "shard", { spin = 0, from = 0.25 })
	throw(l, CHIP, 9, { near = 0.5, far = 1.0, size = 0.12, seed = 7, twirl = 300, fall = 0.2 })
	table.insert(l, sprite("spark", CORE, 0, 0.4, 0.3, 0.9, { a = 1, grow = 0.4, fade = 0.3, c = CORE }))
	return l
end)() }

-- Fire licking up (or a ghost light, in a cold colour).
R.flame = { len = 0.75, sprites = (function()
	local l = {}
	local function lick(layer, t0, t1, fade, a, sway)
		table.insert(l, sprite("flame", layer, t0, t1, 0.4, 1.0, { a = a or 1, grow = 0.3, fade = fade, drift = 0.12, ax = 0.5, ay = 0.82, r0 = -sway, r1 = sway, wide0 = 1.2, wide1 = 0.85, back = layer ~= GLOW }))
	end
	lick(GLOW, 0, 1, 0.4, 0.55, 0)
	lick(RIM, 0.04, 1, 0.6, 1, 5)
	lick(MID, 0.02, 0.85, 0.5, 1, -6)
	lick(CORE, 0, 0.65, 0.4, 1, 4)
	throw(l, DOT, 6, { a0 = -math.pi * 0.75, arc = math.pi * 0.5, near = 0.4, far = 0.95, size = 0.1, seed = 10, life = 0.8, t0 = 0.15, c = MID })
	return l
end)() }

-- A small glint (a charge gained, a keyword, a coin of magic).
R.glint = { len = 0.5, sprites = (function()
	local l = stack({}, "spark", { spin = 30, from = 0.2 })
	return l
end)() }

-- A big arrival: circle on the floor is separate ("circle"); this is the flash in the air.
R.nova = { len = 0.7, sprites = (function()
	local l = {}
	table.insert(l, sprite("ring", RIM, 0.04, 1, 0.2, 1.3, { a = 1, grow = 0.6, fade = 0.4 }))
	table.insert(l, sprite("ring", MID, 0.02, 0.8, 0.2, 1.28, { a = 1, grow = 0.55, fade = 0.35 }))
	table.insert(l, sprite("ring", CORE, 0, 0.6, 0.2, 1.26, { a = 1, grow = 0.5, fade = 0.3 }))
	stack(l, "spark", { spin = 40, size = 1.5, from = 0.2, len = 0.8 })
	stack(l, "burst", { spin = 12, size = 0.8, len = 0.7, glow = 0.4 })
	throw(l, DASH, 16, { near = 0.6, far = 1.3, size = 0.2, seed = 13 })
	return l
end)() }

LayerFx.Recipes = R

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local active = {}
local loop = nil
local folder = nil

local function lowGraphics()
	return Settings ~= nil and Settings.get("graphics") == "Low"
end

local function imageFor(sheet)
	local id = Assets[sheet]
	if type(id) == "number" then
		return id > 0 and ("rbxassetid://" .. id) or nil
	end
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

-- True when every sheet this recipe uses has been uploaded.
function LayerFx.ready(name)
	local recipe = R[name]
	if not recipe then
		return false
	end
	for _, sp in ipairs(recipe.sprites) do
		if not sp.bit and not imageFor(sp.s) then
			return false
		end
	end
	return true
end

local function fxFolder()
	if not (folder and folder.Parent) then
		folder = Instance.new("Folder")
		folder.Name = "LayerFx"
		folder.Parent = Workspace
	end
	return folder
end

local function resolvePalette(p)
	if type(p) == "table" then
		return p
	end
	return LayerFx.Palettes[p] or LayerFx.Palettes.gold
end

local function buildSprites(fx, recipe, parent)
	local low = lowGraphics()
	for _, sp in ipairs(recipe.sprites) do
		local image = imageFor(sp.s)
		if image and not (low and sp.bit) then
			local img = Instance.new("ImageLabel")
			img.Name = sp.s .. sp.l
			img.BackgroundTransparency = 1
			img.BorderSizePixel = 0
			img.Image = image
			img.ImageRectOffset = RECT[sp.l]
			img.ImageRectSize = Vector2.new(Q, Q)
			img.ImageColor3 = fx.palette[sp.c or sp.l]
			img.ImageTransparency = 1
			img.AnchorPoint = Vector2.new(sp.ax or 0.5, sp.ay or 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(0, 0)
			img.ZIndex = (sp.bit and 6 or sp.l) + (sp.z or 0)
			img.Visible = false
			img.Parent = parent
			table.insert(fx.sprites, { spec = sp, img = img })
		end
	end
end

-- Puts every sprite where it belongs at time a (0..1 through the effect).
local function pose(fx, a)
	local inner = fx.inner -- the size of 1 inside the container (the container leaves room around it)
	local turn = fx.turn or 0
	for _, s in ipairs(fx.sprites) do
		local sp, img = s.spec, s.img
		if a < sp.t0 or a > sp.t1 then
			if img.Visible then
				img.Visible = false
			end
		else
			local t = (a - sp.t0) / math.max(sp.t1 - sp.t0, 1e-4)
			local g = math.clamp(t / (sp.grow or 0.35), 0, 1)
			local e = sp.back and outBack(g) or outCubic(g)
			local size = lerp(sp.from, sp.to, e) + (sp.drift or 0) * t
			local wide = sp.wide0 and lerp(sp.wide0, sp.wide1, outCubic(t)) or 1
			local m = sp.ease == "out" and outCubic(t) or t
			local x = lerp(sp.x0 or 0, sp.x1 or sp.x0 or 0, m)
			local y = lerp(sp.y0 or 0, sp.y1 or sp.y0 or 0, m)
			if turn ~= 0 and (x ~= 0 or y ~= 0) then
				local c, sn = math.cos(math.rad(turn)), math.sin(math.rad(turn))
				x, y = x * c - y * sn, x * sn + y * c
			end
			local fade = sp.fade or 0.5
			local alpha = (sp.a or 1) * math.clamp(t / 0.08, 0, 1)
			if t > fade then
				local k = (t - fade) / math.max(1 - fade, 1e-4)
				alpha *= (1 - k) * (1 - k)
			end
			img.Visible = true
			img.Size = UDim2.fromScale(size * inner * wide, size * inner)
			img.Position = UDim2.fromScale(0.5 + x * inner, 0.5 + y * inner)
			img.Rotation = lerp(sp.r0 or 0, sp.r1 or sp.r0 or 0, outCubic(t)) + turn
			img.ImageTransparency = 1 - alpha * fx.alpha
		end
	end
end

-- The turn (in degrees, on screen) that points a camera-facing picture along a direction in
-- the world.
local function screenTurn(pos, dir)
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	local a = camera:WorldToViewportPoint(pos)
	local b = camera:WorldToViewportPoint(pos + dir)
	local dx, dy = b.X - a.X, b.Y - a.Y
	if dx * dx + dy * dy < 1e-6 then
		return 0
	end
	return math.deg(math.atan2(dy, dx))
end

local function finish(fx)
	fx.done = true
	if fx.root and fx.root.Parent then
		fx.root:Destroy()
	end
	if fx.onDone then
		fx.onDone()
	end
end

local function advance(fx, a)
	if fx.done then
		return
	end
	if fx.root.Parent == nil then
		fx.done = true
		return
	end
	if fx.from and fx.to then
		local p = fx.from:Lerp(fx.to, a)
		fx.anchor.CFrame = CFrame.new(p)
		fx.pos = p
	end
	if fx.aim then
		fx.turn = screenTurn(fx.pos, fx.aim) + (fx.aimTurn or 0)
	end
	pose(fx, a)
end

local function ensureLoop()
	if loop then
		return
	end
	loop = RunService.RenderStepped:Connect(function(dt)
		for i = #active, 1, -1 do
			local fx = active[i]
			fx.age += dt
			local a = math.clamp(fx.age / fx.len, 0, 1)
			if fx.age >= 0 then
				advance(fx, a)
			end
			if a >= 1 or fx.done then
				table.remove(active, i)
				if not fx.done then
					finish(fx)
				end
			end
		end
		if #active == 0 and loop then
			loop:Disconnect()
			loop = nil
		end
	end)
end

local Handle = {}
Handle.__index = Handle
-- For effects played with opts.manual: move it to time a (0..1) yourself.
function Handle:set(a)
	advance(self.fx, math.clamp(a, 0, 1))
end
function Handle:stop()
	if not self.fx.done then
		finish(self.fx)
	end
end

local function start(fx, recipe, opts)
	fx.len = (opts.seconds or recipe.len) * (opts.pace or 1)
	fx.age = -(opts.delay or 0) * (opts.pace or 1)
	fx.alpha = opts.alpha or 1
	fx.onDone = opts.onDone
	fx.done = false
	if #fx.sprites == 0 then
		finish(fx)
		return nil
	end
	local handle = setmetatable({ fx = fx }, Handle)
	if opts.manual then
		advance(fx, 0)
	else
		table.insert(active, fx)
		ensureLoop()
		if fx.age >= 0 then
			advance(fx, 0)
		end
	end
	return handle
end

-- Plays an effect in the world.
--   where   a Vector3 (the middle of the effect; for "pillar" and "flame" the ground under it)
--   opts    palette  a name from LayerFx.Palettes or a table of four colours
--           size     in studs (default 4)
--           aim      a direction in the world to point the picture along (slashes, hits)
--           to       where a bolt flies to
--           seconds, delay, pace, alpha, onTop, manual, onDone, parent
function LayerFx.play(name, where, opts)
	local recipe = R[name]
	if not recipe or not LayerFx.ready(name) then
		return nil
	end
	opts = opts or {}
	local size = opts.size or 4
	local fx = { sprites = {}, palette = resolvePalette(opts.palette), pos = where }
	local anchor = Instance.new("Part")
	anchor.Name = "Fx_" .. name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	fx.anchor = anchor
	fx.root = anchor
	if recipe.flat then
		-- lies on the ground: a thin slab with the pictures on its top face
		local room = 2.6
		anchor.Size = Vector3.new(size * room, 0.05, size * room)
		anchor.CFrame = CFrame.new(where) * CFrame.Angles(0, math.rad(opts.yaw or 0), 0)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Layers"
		gui.Face = Enum.NormalId.Top
		gui.CanvasSize = Vector2.new(900, 900)
		gui.LightInfluence = 0
		gui.Brightness = opts.brightness or 1.3
		gui.AlwaysOnTop = opts.onTop == true
		gui.Parent = anchor
		fx.inner = 1 / room
		buildSprites(fx, recipe, gui)
	else
		-- faces the camera
		local room = 3
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(where)
		local gui = Instance.new("BillboardGui")
		gui.Name = "Layers"
		gui.Size = UDim2.fromScale(size * room, size * room)
		gui.LightInfluence = 0
		gui.Brightness = opts.brightness or 1.3
		gui.AlwaysOnTop = opts.onTop == true
		gui.ClipsDescendants = false
		gui.StudsOffset = Vector3.new(0, 0, opts.toward or 1) -- a touch toward the camera, clear of the model
		gui.Parent = anchor
		fx.inner = 1 / room
		buildSprites(fx, recipe, gui)
		if recipe.travels and opts.to then
			fx.from, fx.to = where, opts.to
			fx.aim = (opts.to - where)
			if fx.aim.Magnitude < 1e-3 then
				fx.aim = nil
			else
				fx.aim = fx.aim.Unit
			end
		elseif opts.aim and opts.aim.Magnitude > 1e-3 then
			fx.aim = opts.aim.Unit
		end
		fx.aimTurn = recipe.aimTurn
	end
	anchor.Parent = opts.parent or fxFolder()
	return start(fx, recipe, opts)
end

-- Plays an effect on the screen, inside a GuiObject or ScreenGui.
--   position  a UDim2 inside `parent`;  pixels  the size of the effect
--   opts      palette, turn (degrees), seconds, delay, pace, alpha, zIndex, manual, onDone
function LayerFx.screen(name, parent, position, pixels, opts)
	local recipe = R[name]
	if not recipe or not LayerFx.ready(name) or not parent then
		return nil
	end
	opts = opts or {}
	local fx = { sprites = {}, palette = resolvePalette(opts.palette), inner = 1, turn = opts.turn }
	local holder = Instance.new("Frame")
	holder.Name = "Fx_" .. name
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = position
	holder.Size = UDim2.fromOffset(pixels, pixels)
	holder.ZIndex = opts.zIndex or 50
	holder.Active = false
	fx.root = holder
	buildSprites(fx, recipe, holder)
	if opts.zIndex then
		for _, s in ipairs(fx.sprites) do
			s.img.ZIndex += opts.zIndex
		end
	end
	if recipe.aimTurn and opts.turn then
		fx.turn = opts.turn + recipe.aimTurn
	end
	holder.Parent = parent
	return start(fx, recipe, opts)
end

-- How many effects are playing right now (for tests).
function LayerFx.count()
	return #active
end

return LayerFx

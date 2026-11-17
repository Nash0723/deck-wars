-- EnchantFx: what an enchant looks like. Client only. Every enchant rarity has its own colour
-- (Enchants.Colors / Enchants.Palettes); the Secret one shifts through the rainbow.
--
--   EnchantFx.color(rarity)                 the colour right now (Secret changes every frame)
--   EnchantFx.palette(rarity, hue)          four LayerFx colours (glow, rim, middle, core)
--   EnchantFx.decorateCard(card, enchantId) a glowing rim round a card face and a rune gem on
--                                           its top-right corner (the cost is top-left), in the
--                                           hand, on the Deck Shelf and at the Enchanting Crystal
--   EnchantFx.aura(model, enchantId, folder, height, live)
--                                           a slow glow under an enchanted creature on the table:
--                                           a rune ring, a soft light and motes rising round it.
--                                           It follows the model and goes away with it.
--   EnchantFx.matchEvent(e, api)            the match screen's "enchant" events (arrive, thorns,
--                                           leech, rebirth, cast)
--   EnchantFx.screenBurst(parent, pos, px, rarity)   a painted burst on the screen (the roll)
--
-- The painted effects are LayerFx (the effects thread's module): it's optional here, so
-- everything still works (rims, rings, motes) without it.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local here = script.Parent
local Enchants = require(here:WaitForChild("Enchants"))
local LayerFx = nil
do
	local m = here:FindFirstChild("LayerFx")
	if m then
		local ok, mod = pcall(require, m)
		LayerFx = ok and mod or nil
	end
end

local EnchantFx = {}
EnchantFx.Enchants = Enchants

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local clock = 0
local RAINBOW = {}
for i, t in ipairs(Enchants.Rainbow) do
	RAINBOW[i] = c3(t)
end

-- The rainbow at a point (0..1 goes once round).
local function rainbowAt(x)
	x = x % 1
	local n = #RAINBOW
	local f = x * n
	local i = math.floor(f)
	return RAINBOW[i % n + 1]:Lerp(RAINBOW[(i + 1) % n + 1], f - i)
end
EnchantFx.rainbowAt = rainbowAt

function EnchantFx.color(rarity, offset)
	if rarity == "Secret" then
		return rainbowAt(clock * 0.18 + (offset or 0))
	end
	return c3(Enchants.color(rarity))
end

-- Four colours for LayerFx. hue (0..1) picks a rainbow colour for Secret (default: now).
function EnchantFx.palette(rarity, hue)
	if rarity == "Secret" then
		local base = hue and rainbowAt(hue) or EnchantFx.color("Secret")
		local white = Color3.new(1, 1, 1)
		return { base, base:Lerp(Color3.new(0, 0, 0), 0.4), base:Lerp(white, 0.35), base:Lerp(white, 0.9) }
	end
	local p = Enchants.Palettes[rarity] or Enchants.Palettes.Common
	return { c3(p[1]), c3(p[2]), c3(p[3]), c3(p[4]) }
end

local function sequence(rarity)
	if rarity == "Secret" then
		local keys = {}
		for i = 0, 4 do
			table.insert(keys, ColorSequenceKeypoint.new(i / 4, rainbowAt(i / 5)))
		end
		return ColorSequence.new(keys)
	end
	local col = EnchantFx.color(rarity)
	return ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.5), col)
end

---------------------------------------------------------------------------
-- One loop for everything that glows (rims, gems, auras)
---------------------------------------------------------------------------

local rims = setmetatable({}, { __mode = "k" }) -- [UIStroke or GuiObject] = { rarity, phase, kind }
local auras = {} -- list of aura records
local loop = nil

local function step(dt)
	clock += dt
	for obj, r in pairs(rims) do
		if not obj.Parent then
			rims[obj] = nil
		else
			local pulse = 0.5 + 0.5 * math.sin(clock * (r.rank >= 5 and 3.2 or 2.2) + r.phase)
			if r.kind == "stroke" then
				obj.Color = EnchantFx.color(r.rarity, r.phase / 6.28)
				obj.Transparency = 0.45 - pulse * 0.4
			elseif r.kind == "gem" then
				obj.BackgroundColor3 = EnchantFx.color(r.rarity, r.phase / 6.28)
				obj.Rotation = 45 + math.sin(clock * 1.4 + r.phase) * 8
			elseif r.kind == "halo" then
				obj.BackgroundColor3 = EnchantFx.color(r.rarity, r.phase / 6.28)
				obj.BackgroundTransparency = 0.82 - pulse * 0.3
				obj.Rotation = 45 + math.sin(clock * 1.4 + r.phase) * 8
			elseif r.kind == "gradient" then
				obj.Rotation = (clock * 90 + r.phase * 57) % 360
			end
		end
	end
	for i = #auras, 1, -1 do
		local a = auras[i]
		if not (a.model and a.model.Parent) then
			a.folder:Destroy()
			if a.handle then
				pcall(function()
					a.handle:stop()
				end)
			end
			table.remove(auras, i)
		else
			local pivot = a.model:GetPivot()
			local at = pivot.Position - Vector3.new(0, a.drop, 0)
			local pulse = 0.5 + 0.5 * math.sin(clock * 1.6 + a.phase)
			local col = EnchantFx.color(a.rarity, a.phase / 6.28)
			a.ring.CFrame = CFrame.new(at + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, clock * 0.5 + a.phase, math.rad(90))
			a.ring.Color = col
			a.ring.Transparency = 0.55 - pulse * 0.25
			a.inner.CFrame = CFrame.new(at + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, -clock * 0.8, math.rad(90))
			a.inner.Color = col
			a.inner.Transparency = 0.8 - pulse * 0.15
			a.mote.CFrame = CFrame.new(at + Vector3.new(0, a.height * 0.5, 0))
			a.light.Color = col
			a.light.Brightness = a.bright * (0.7 + pulse * 0.5)
			if a.rarity == "Secret" then
				a.emitter.Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.4), rainbowAt(clock * 0.18 + 0.3))
			end
		end
	end
end

local function ensureLoop()
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------

-- A glowing rim round a card face (just outside its edge) and a rune gem on its top-right corner,
-- clear of the cost (top-left); the card's name gives the gem a little room. opts.gem: the gem's
-- size in pixels (18). Returns the rim frame, or nil when there's no enchant.
function EnchantFx.decorateCard(card, enchantId, opts)
	local e = Enchants.get(enchantId)
	if not (card and e) then
		return nil
	end
	opts = opts or {}
	local old = card:FindFirstChild("EnchantRim")
	if old then
		old:Destroy()
	end
	for _, name in ipairs({ "EnchantGem", "EnchantHalo" }) do
		local o = card:FindFirstChild(name)
		if o then
			o:Destroy()
		end
	end
	local rank = Enchants.Rank[e.rarity] or 1
	local phase = math.random() * 6.28
	local rim = Instance.new("Frame")
	rim.Name = "EnchantRim"
	rim.BackgroundTransparency = 1
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, 8, 1, 8)
	rim.ZIndex = 30
	rim.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 13)
	corner.Parent = rim
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Glow"
	stroke.Thickness = rank >= 5 and 4 or 3
	stroke.Color = EnchantFx.color(e.rarity)
	stroke.Transparency = 0.25
	stroke.Parent = rim
	rims[stroke] = { rarity = e.rarity, phase = phase, kind = "stroke", rank = rank }
	if rank >= 4 then
		-- Mythic and up: a bright band runs round the rim
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.45, 0.6),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.55, 0.6),
			NumberSequenceKeypoint.new(1, 0.6),
		})
		g.Parent = stroke
		rims[g] = { rarity = e.rarity, phase = phase, kind = "gradient", rank = rank }
	end
	rim.Parent = card
	-- the rune gem: a small cut gem on the top-right corner (a light crown over a darker
	-- pavilion, a glint), glowing softly behind for Legendary and Secret runes
	local size = opts.gem or 18
	local inset = math.floor(size * 0.12 + 0.5)
	local where = UDim2.new(1, -inset, 0, inset)
	if rank >= 5 then
		local halo = Instance.new("Frame")
		halo.Name = "EnchantHalo"
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = where
		halo.Size = UDim2.fromOffset(math.floor(size * 1.7), math.floor(size * 1.7))
		halo.Rotation = 45
		halo.BackgroundColor3 = EnchantFx.color(e.rarity)
		halo.BackgroundTransparency = 0.7
		halo.BorderSizePixel = 0
		halo.ZIndex = 30
		halo.Active = false
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, math.floor(size * 0.4))
		hc.Parent = halo
		halo.Parent = card
		rims[halo] = { rarity = e.rarity, phase = phase, kind = "halo", rank = rank }
	end
	local gem = Instance.new("Frame")
	gem.Name = "EnchantGem"
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Position = where
	gem.Size = UDim2.fromOffset(size, size)
	gem.Rotation = 45
	gem.BackgroundColor3 = EnchantFx.color(e.rarity)
	gem.BorderSizePixel = 0
	gem.ZIndex = 31
	gem.Active = false
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0, math.max(2, math.floor(size * 0.18)))
	gc.Parent = gem
	local gs = Instance.new("UIStroke")
	gs.Thickness = size >= 24 and 2.5 or 2
	gs.Color = Color3.fromRGB(18, 14, 28)
	gs.Parent = gem
	-- the cut: the top half lighter, the bottom half deeper (the gradient runs top to bottom on
	-- screen; the gem itself is turned 45 degrees)
	local cut = Instance.new("UIGradient")
	cut.Rotation = 45
	cut.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(236, 236, 236)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(168, 168, 176)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 140)),
	})
	cut.Parent = gem
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.2
	shine.BorderSizePixel = 0
	shine.Size = UDim2.fromScale(0.3, 0.3)
	shine.Position = UDim2.fromScale(0.16, 0.16)
	shine.ZIndex = 32
	shine.Active = false
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(1, 0)
	sc.Parent = shine
	shine.Parent = gem
	gem.Parent = card
	-- the name steps back from the corner so the gem never sits on its last letters
	local nameLabel = card:FindFirstChild("CardName")
	if nameLabel and nameLabel:IsA("GuiObject") then
		local base = nameLabel:GetAttribute("BaseSize")
		if typeof(base) ~= "UDim2" then
			base = nameLabel.Size
			nameLabel:SetAttribute("BaseSize", base)
		end
		nameLabel.Size = base - UDim2.fromOffset(math.floor(size * 0.6 + 0.5), 0)
	end
	rims[gem] = { rarity = e.rarity, phase = phase, kind = "gem", rank = rank }
	ensureLoop()
	return rim
end

---------------------------------------------------------------------------
-- On the table
---------------------------------------------------------------------------

local function anchored(name, size, color, parent, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Transparency = 0.5
	p.Parent = parent
	return p
end

-- The aura under an enchanted creature. live = false (a duel: the enchant only shows) makes it
-- quieter. Returns the record (it cleans itself up when the model is gone).
function EnchantFx.aura(model, enchantId, parent, height, live)
	local e = Enchants.get(enchantId)
	if not (model and e) then
		return nil
	end
	local rank = Enchants.Rank[e.rarity] or 1
	local folder = Instance.new("Folder")
	folder.Name = "EnchantAura"
	folder.Parent = parent or workspace
	local _, size = model:GetBoundingBox()
	local cf = model:GetPivot()
	local bottom = cf.Position.Y - (model:GetBoundingBox().Position.Y - size.Y / 2)
	local width = math.clamp(math.max(size.X, size.Z) * 0.95, 1.4, 2.4)
	local col = EnchantFx.color(e.rarity)
	-- a thin glowing ring with a fainter disc inside (cylinders lie on their side: Z turn)
	local ring = anchored("Ring", Vector3.new(0.05, width, width), col, folder, Enum.PartType.Cylinder)
	local inner = anchored("Disc", Vector3.new(0.03, width * 0.8, width * 0.8), col, folder, Enum.PartType.Cylinder)
	inner.Transparency = 0.8
	-- the motes: a soft light and little sparks drifting up round it
	local mote = anchored("Motes", Vector3.new(width * 0.8, math.max(0.5, (height or 2) * 0.9), width * 0.8), col, folder)
	mote.Transparency = 1
	local light = Instance.new("PointLight")
	light.Range = 4 + rank * 0.6
	light.Brightness = 0.6 + rank * 0.15
	light.Color = col
	light.Shadows = false
	light.Parent = mote
	local em = Instance.new("ParticleEmitter")
	em.Name = "Motes"
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = sequence(e.rarity)
	em.LightEmission = 1
	em.LightInfluence = 0
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.3, 0.16 + rank * 0.02), NumberSequenceKeypoint.new(1, 0) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.15), NumberSequenceKeypoint.new(1, 1) })
	em.Lifetime = NumberRange.new(1.6, 2.6)
	em.Speed = NumberRange.new(0.5, 0.9)
	em.SpreadAngle = Vector2.new(10, 10)
	em.EmissionDirection = Enum.NormalId.Top
	em.Acceleration = Vector3.new(0, 0.3, 0)
	em.Rate = (live == false) and 1.5 or (2 + rank * 1.2)
	em.Parent = mote
	local rec = {
		model = model,
		folder = folder,
		ring = ring,
		inner = inner,
		mote = mote,
		light = light,
		emitter = em,
		rarity = e.rarity,
		drop = bottom,
		height = height or 2,
		phase = math.random() * 6.28,
		bright = light.Brightness,
	}
	-- the effects thread's looping aura, when it's there (a glow with rising glints)
	if LayerFx and LayerFx.Recipes and LayerFx.Recipes.aura then
		pcall(function()
			rec.handle = LayerFx.play("aura", cf.Position, { loop = true, follow = model, palette = EnchantFx.palette(e.rarity, rank >= 6 and 0.6 or nil), size = width * 1.6, parent = parent, onTop = false })
		end)
	end
	table.insert(auras, rec)
	ensureLoop()
	step(0)
	return rec
end

-- A LayerFx effect, if LayerFx (and that recipe) is there.
local function play(api, name, pos, opts)
	if not (LayerFx and LayerFx.Recipes and LayerFx.Recipes[name]) then
		return nil
	end
	if api and api.fx then
		return api.fx(name, pos, opts)
	end
	return LayerFx.play(name, pos, opts)
end

-- The match screen's "enchant" events.
--   api: units, fx(name, pos, opts), unitPosition(entry), groundOf(entry), heroPos(team),
--        floatText(pos, text, color, big), step(seconds), sound(name, opts)
function EnchantFx.matchEvent(e, api)
	local def = Enchants.get(e.enchant)
	if not def then
		return
	end
	local rarity = def.rarity
	local rank = Enchants.Rank[rarity] or 1
	local pal = EnchantFx.palette(rarity)
	local entry = e.uid and api.units[e.uid]
	local col = EnchantFx.color(rarity)
	if e.what == "arrive" then
		if not entry then
			return
		end
		local ground = api.groundOf(entry)
		local top = api.unitPosition(entry)
		-- the rune circle opens under it, the colour climbs it; rarer = bigger and slower
		play(api, "circle", ground, { palette = pal, size = 3 + rank * 0.25, seconds = 1.3 + rank * 0.1, delay = 0.25 })
		if LayerFx and LayerFx.Recipes and LayerFx.Recipes.enchant then
			play(api, "enchant", top, { palette = pal, size = 2.6 + rank * 0.2, delay = 0.35 })
		else
			play(api, "glint", top + Vector3.new(0, 0.6, 0), { palette = pal, size = 2 + rank * 0.2, delay = 0.45, seconds = 1.1 })
		end
		if rank >= 4 then
			play(api, "pillar", ground, { palette = pal, size = 4 + rank * 0.5, delay = 0.3, seconds = 1.6 })
		end
		if rank >= 6 then
			-- Secret: the colours of the rainbow ring out one after another
			for i = 1, 3 do
				play(api, "ring" , top, { palette = EnchantFx.palette("Secret", i / 3), size = 3 + i, delay = 0.4 + i * 0.22 })
				play(api, "nova", top, { palette = EnchantFx.palette("Secret", i / 3), size = 2.4 + i * 0.6, delay = 0.45 + i * 0.25 })
			end
		end
		if api.floatText then
			api.floatText(top + Vector3.new(0, 0.8, 0), "◆ " .. def.name, col, rank >= 4)
		end
		if api.sound then
			api.sound("chime", { volume = 0.35 + rank * 0.05, pitch = 1.25 - rank * 0.05 })
		end
		if api.step then
			api.step(0.35 + rank * 0.08)
		end
	elseif e.what == "thorns" then
		local target = e.target and api.units[e.target]
		if entry and target then
			local from, to = api.unitPosition(entry), api.unitPosition(target)
			play(api, "shards", to, { palette = pal, size = 2.4, aim = (to - from) })
			if api.floatText then
				api.floatText(from, "◆ Thorns", col, false)
			end
		end
		if api.step then
			api.step(0.35)
		end
	elseif e.what == "leech" then
		if entry and api.heroPos then
			local from = api.unitPosition(entry)
			local to = api.heroPos(e.team) + Vector3.new(0, 1.2, 0)
			play(api, "bolt", from, { to = to, palette = pal, size = 1.6, seconds = 0.8 })
			play(api, "bloom", to, { palette = pal, size = 2.6, delay = 0.5 })
			if api.floatText then
				api.floatText(from, "◆ " .. def.name, col, false)
			end
		end
		if api.step then
			api.step(0.45)
		end
	elseif e.what == "rebirth" then
		if entry then
			local ground = api.groundOf(entry)
			play(api, "pillar", ground, { palette = pal, size = 6, seconds = 1.8 })
			play(api, "flame", ground, { palette = pal, size = 3, delay = 0.1, seconds = 1.4 })
			play(api, "nova", api.unitPosition(entry), { palette = pal, size = 3.2, delay = 0.5 })
			if api.floatText then
				api.floatText(api.unitPosition(entry), "◆ " .. def.name .. "! Back again", col, true)
			end
			if api.sound then
				api.sound("chime", { volume = 0.7, pitch = 0.8 })
			end
		end
		if api.step then
			api.step(0.9)
		end
	elseif e.what == "cast" then
		if api.heroPos and e.team then
			local at = api.heroPos(e.team) + Vector3.new(0, 1.4, 0)
			play(api, "glint", at, { palette = pal, size = 2.4 })
			play(api, "bloom", at, { palette = pal, size = 2.4, delay = 0.25 })
			if api.floatText then
				api.floatText(at, "◆ " .. def.name, col, false)
			end
		end
		if api.step then
			api.step(0.5)
		end
	end
end

-- A painted burst on the screen, in the enchant's colour (the roll in the enchant window).
function EnchantFx.screenBurst(parent, position, pixels, rarity)
	if not (LayerFx and LayerFx.screen) then
		return
	end
	local rank = Enchants.Rank[rarity] or 1
	local pal = EnchantFx.palette(rarity)
	pcall(function()
		LayerFx.screen("nova", parent, position, pixels, { palette = pal, seconds = 1.2 + rank * 0.1 })
		LayerFx.screen("circle", parent, position, pixels * 1.2, { palette = pal, delay = 0.1, seconds = 1.5 })
		if rank >= 4 then
			LayerFx.screen("bigHit", parent, position, pixels * 1.3, { palette = pal, delay = 0.15 })
		end
		if rank >= 6 then
			for i = 1, 4 do
				LayerFx.screen("nova", parent, position, pixels * (1 + i * 0.2), { palette = EnchantFx.palette("Secret", i / 4), delay = 0.25 * i })
			end
		end
	end)
end

-- (for the tests)
function EnchantFx.count()
	return #auras
end
EnchantFx.step = step

return EnchantFx

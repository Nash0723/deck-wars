-- The Duel Table when nobody is playing. Client only.
--
-- The room's table still carries the old 5x6 tile board (MenuRoom.rbxmx: Board.Tile_*, plinths,
-- crystal sockets, energy gems, the board bed and frame). Matches have long been played on the
-- two-row lane board instead (MatchScreen builds it when a match starts), so between matches the
-- table looked like an older game. This module hides the old board and lays the real one on the
-- felt, at rest:
--
--   * the lane field exactly where the match field rises (4 lanes x Front/Back + a building slab
--     per lane, each side), in the colours of your board theme (Shop > Deck & Field),
--   * inlaid rings on every creature spot, brass corner caps, a gold seam with a Deck Wars
--     medallion in the middle,
--   * two of the game's big creatures squaring off in the middle lanes as a showcase; every
--     half minute they sink into the board and two others rise,
--   * a slow, calm shimmer: the rings breathe and a soft light runs along the seam now and then.
--
-- When a match starts it all goes away (the match board rises in its place) and it comes back
-- after. Everything is anchored and can't be clicked: clicks fall through to the table itself,
-- so the Duel Table still opens.
--
--   IdleTable.attach(duelTable)   -- once, from DeckWarsClient
--   IdleTable.setVisible(on)      -- false for a match, true after
--   IdleTable.repaint(boardId)    -- the board theme changed
--   IdleTable.update(dt)          -- every frame (cheap: a few parts)
--
-- Old parts are hidden by Transparency; each keeps its original value in the attribute
-- "IdleTransparency" (the pull stage copies the table and can put them back).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local CreatureBuilder = require(here:WaitForChild("CreatureBuilder"))
local Cosmetics = require(here:WaitForChild("Cosmetics"))

local IdleTable = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- The match field's numbers (MatchScreen.makeLayout, 1v1), so the rest pose sits exactly where
-- the match board rises.
local L = {
	lanes = 4,
	pitch = 3.075,
	half = 7.35, -- depth of each side
	frame = 0.36,
	creatureZ = 1.95,
	backZ = 4.2,
	buildingZ = 6.25,
}
L.halfWidth = L.pitch * L.lanes / 2
L.spot = math.min(L.pitch * 0.82, 2.1)

IdleTable.ShowcaseHeight = 2.5 -- studs tall, the figurines on the middle spots
IdleTable.SwapSeconds = 28

-- The parts of the old board that go (same list MatchScreen hides in a match).
local OLD = { BoardBed = true, BoardFrame = true, FrameCap = true, HalfwayLine = true, HalfwayMark = true, TilePlinth = true, CrystalSocket = true }
local function isOld(name)
	return OLD[name] or name:match("^Tile_") ~= nil or name:match("^Energy_") ~= nil
end

local S = {
	table = nil,
	folder = nil,
	visible = true,
	t = 0,
	parts = {}, -- by role: rings, strips, frame, caps, seam, medal, glowRing, sweep
	showcase = {}, -- [1] near, [2] far: { model, home, id, phase }
	nextSwap = 0,
	swapping = false,
	pool = nil,
	base = 4.1,
}
IdleTable.state = S -- (for tests)

local function part(props)
	local p = Instance.new("Part")
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
	return p
end

local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder lying as a disc

local function disc(name, x, y, z, d, thick, color, mat, extra)
	local props = extra or {}
	props.Name = name
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(thick, d, d)
	props.CFrame = CFrame.new(x, y, z) * FLAT
	props.Color = color
	props.Material = mat or Enum.Material.SmoothPlastic
	return part(props)
end

local function add(role, p)
	S.parts[role] = S.parts[role] or {}
	table.insert(S.parts[role], p)
	return p
end

---------------------------------------------------------------------------
-- Colours: from the equipped board theme (nil slots = Walnut Classic, the table as built)
---------------------------------------------------------------------------
local WALNUT = {
	felt = { rgb(34, 92, 60), Enum.Material.Fabric },
	rim = { rgb(70, 44, 27), Enum.Material.Wood },
	frame = { rgb(150, 105, 65), Enum.Material.Wood },
	trim = { rgb(215, 175, 80), Enum.Material.Metal },
}
local function look(boardId)
	local theme = Cosmetics.Boards[boardId or ""] or {}
	local out = {}
	for slot, v in pairs(WALNUT) do
		out[slot] = theme[slot] or v
	end
	return out
end

---------------------------------------------------------------------------
-- Building the rest pose
---------------------------------------------------------------------------
local function feltTop(duelTable)
	local felt = duelTable:FindFirstChild("Felt")
	return felt and felt:IsA("BasePart") and (felt.Position.Y + felt.Size.Y / 2) or 4.1
end

local function hideOld(duelTable)
	local folders = { duelTable }
	local board = duelTable:FindFirstChild("Board")
	if board then
		table.insert(folders, board)
	end
	for _, f in ipairs(folders) do
		for _, d in ipairs(f:GetChildren()) do
			if d:IsA("BasePart") and isOld(d.Name) and d:GetAttribute("IdleTransparency") == nil then
				d:SetAttribute("IdleTransparency", d.Transparency)
				d.Transparency = 1
				for _, g in ipairs(d:GetChildren()) do
					if g:IsA("Light") or g:IsA("ParticleEmitter") or g:IsA("SurfaceGui") then
						g.Enabled = false
					end
				end
			end
		end
	end
end

local function build()
	local base = S.base
	local W, D, fw = L.halfWidth, L.half, L.frame
	local groundTop = base + 0.2
	-- the bed under the field and its wooden frame, brass caps on the corners and the seam ends
	add("rim", part({ Name = "IdleBed", Size = Vector3.new(2 * (W + fw), 0.1, 2 * (D + fw)), CFrame = CFrame.new(0, base + 0.05, 0), Material = Enum.Material.Wood }))
	local fh = 0.34
	for _, sx in ipairs({ -1, 1 }) do
		add("frame", part({ Name = "IdleFrame", Size = Vector3.new(fw, fh, 2 * (D + fw)), CFrame = CFrame.new(sx * (W + fw / 2), base + fh / 2, 0), Material = Enum.Material.Wood, Reflectance = 0.04 }))
		add("frame", part({ Name = "IdleFrame", Size = Vector3.new(2 * W, fh, fw), CFrame = CFrame.new(0, base + fh / 2, sx * (D + fw / 2)), Material = Enum.Material.Wood, Reflectance = 0.04 }))
		for _, sz in ipairs({ -1, 0, 1 }) do
			add("caps", part({ Name = "IdleCap", Size = Vector3.new(fw + 0.12, 0.1, fw + 0.12), CFrame = CFrame.new(sx * (W + fw / 2), base + fh + 0.05, sz * (D + fw / 2)), Reflectance = 0.2 }))
		end
		-- a thin bevel along the inside of the frame (catches the lamp light)
		add("caps", part({ Name = "IdleBevel", Size = Vector3.new(0.05, 0.04, 2 * D), CFrame = CFrame.new(sx * (W - 0.02), groundTop + 0.02, 0), Reflectance = 0.2 }))
		add("caps", part({ Name = "IdleBevel", Size = Vector3.new(2 * W, 0.04, 0.05), CFrame = CFrame.new(0, groundTop + 0.02, sx * (D - 0.02)), Reflectance = 0.2 }))
	end
	-- each side: four lanes of felt that touch, a little lighter and darker in turn
	for side = 1, 2 do
		local sz = side == 1 and 1 or -1
		for lane = 1, L.lanes do
			local x = (lane - (L.lanes + 1) / 2) * L.pitch
			local strip = add("strips", part({ Name = "IdleLane", Size = Vector3.new(L.pitch, groundTop - base - 0.1, D), CFrame = CFrame.new(x, base + 0.1 + (groundTop - base - 0.1) / 2, sz * D / 2) }))
			strip:SetAttribute("Shade", (lane + side) % 2 == 0 and 0.08 or -0.04)
			-- Front and Back spots: an inlaid ring (trim colour) round a darker well
			for row, z in ipairs({ L.creatureZ, L.backZ }) do
				local ring = add("rings", disc("IdleRing", x, groundTop + 0.006, sz * z, L.spot, 0.02, Color3.new(), Enum.Material.Metal, { Transparency = 0.35, Reflectance = 0.15 }))
				ring:SetAttribute("Row", row)
				ring:SetAttribute("Phase", lane * 0.7 + side * 1.9 + row * 0.4)
				add("wells", disc("IdleWell", x, groundTop + 0.012, sz * z, L.spot - 0.2, 0.02, Color3.new(), Enum.Material.Fabric))
			end
			-- the building slab behind them: dark stone on a brass edge
			add("caps", part({ Name = "IdleSlabEdge", Size = Vector3.new(L.pitch * 0.58 + 0.14, 0.02, 1.64), CFrame = CFrame.new(x, groundTop + 0.008, sz * L.buildingZ), Transparency = 0.2 }))
			add("slabs", part({ Name = "IdleSlab", Size = Vector3.new(L.pitch * 0.58, 0.03, 1.5), CFrame = CFrame.new(x, groundTop + 0.016, sz * L.buildingZ), Material = Enum.Material.Slate, Color = rgb(52, 46, 50) }))
		end
		-- grooves between the lanes
		for lane = 1, L.lanes - 1 do
			local x = (lane - L.lanes / 2) * L.pitch
			add("grooves", part({ Name = "IdleGroove", Size = Vector3.new(0.06, 0.03, D - 0.12), CFrame = CFrame.new(x, groundTop + 0.004, sz * (D / 2 + 0.06)), Color = rgb(18, 14, 16), Transparency = 0.45 }))
		end
		-- the row line between Front and Back, faint
		add("grooves", part({ Name = "IdleRowLine", Size = Vector3.new(2 * W - 0.3, 0.02, 0.04), CFrame = CFrame.new(0, groundTop + 0.003, sz * (L.creatureZ + L.backZ) / 2), Color = rgb(18, 14, 16), Transparency = 0.7 }))
	end
	-- the seam where the sides meet, and the medallion on it
	add("seam", part({ Name = "IdleSeam", Size = Vector3.new(2 * W, 0.03, 0.1), CFrame = CFrame.new(0, groundTop + 0.01, 0), Reflectance = 0.2 }))
	add("medal", disc("IdleMedalRim", 0, groundTop + 0.03, 0, 1.5, 0.06, Color3.new(), Enum.Material.Metal, { Reflectance = 0.25 }))
	add("wells", disc("IdleMedalFace", 0, groundTop + 0.065, 0, 1.18, 0.04, Color3.new(), Enum.Material.Fabric))
	-- crossed blades on the medallion (two thin bars) and a gem in the middle
	for _, a in ipairs({ math.rad(45), math.rad(-45) }) do
		add("medal", part({ Name = "IdleMedalBlade", Size = Vector3.new(0.12, 0.03, 0.96), CFrame = CFrame.new(0, groundTop + 0.09, 0) * CFrame.Angles(0, a, 0), Material = Enum.Material.Metal, Reflectance = 0.25 }))
	end
	S.parts.gem = { part({ Name = "IdleMedalGem", Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34), CFrame = CFrame.new(0, groundTop + 0.12, 0), Material = Enum.Material.Neon, Color = rgb(255, 210, 120), Transparency = 0.15 }) }
	-- the soft light that runs along the seam now and then
	S.parts.sweep = { part({ Name = "IdleSweep", Size = Vector3.new(1.6, 0.04, 0.14), CFrame = CFrame.new(-W, groundTop + 0.02, 0), Material = Enum.Material.Neon, Color = rgb(255, 225, 150), Transparency = 1 }) }
	S.groundTop = groundTop
end

function IdleTable.repaint(boardId)
	if not S.folder then
		return
	end
	local lk = look(boardId)
	local felt, rim, frame, trim = lk.felt, lk.rim, lk.frame, lk.trim
	for _, p in ipairs(S.parts.rim or {}) do
		p.Color, p.Material = rim[1]:Lerp(rgb(0, 0, 0), 0.25), rim[2]
	end
	for _, p in ipairs(S.parts.frame or {}) do
		p.Color, p.Material = frame[1], frame[2]
	end
	for _, role in ipairs({ "caps", "seam", "medal", "rings" }) do
		for _, p in ipairs(S.parts[role] or {}) do
			p.Color = trim[1]
			if role ~= "rings" then
				p.Material = trim[2] == Enum.Material.Neon and Enum.Material.Metal or trim[2]
			end
		end
	end
	for _, p in ipairs(S.parts.strips or {}) do
		local shade = p:GetAttribute("Shade") or 0
		p.Color = shade >= 0 and felt[1]:Lerp(rgb(255, 255, 255), shade) or felt[1]:Lerp(rgb(0, 0, 0), -shade)
		p.Material = felt[2]
	end
	for _, p in ipairs(S.parts.wells or {}) do
		p.Color = felt[1]:Lerp(rgb(0, 0, 0), 0.3)
		p.Material = felt[2]
	end
	local glow = trim[1]:Lerp(rgb(255, 255, 255), 0.35)
	for _, p in ipairs(S.parts.gem or {}) do
		p.Color = glow
	end
	for _, p in ipairs(S.parts.sweep or {}) do
		p.Color = glow
	end
end

---------------------------------------------------------------------------
-- The showcase: two big creatures facing off in the middle lanes
---------------------------------------------------------------------------
local function showcasePool()
	if S.pool then
		return S.pool
	end
	local pool = {}
	for _, id in ipairs(CardData.List) do
		local c = CardData.Cards[id]
		if c.type == "Creature" and not c.token and (c.rarity == "Legendary" or c.rarity == "Mythic" or c.rarity == "Epic") and CreatureBuilder.has(id) then
			table.insert(pool, id)
		end
	end
	S.pool = pool
	return pool
end

local function setFade(model, k)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = k
		end
	end
end

local function spawnFigure(slot, id)
	local model = CreatureBuilder.build(id)
	if not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
			d:Destroy() -- calm: no smoke or sparks on a table nobody is using
		end
	end
	local info = CreatureBuilder.info(id)
	pcall(function()
		model:ScaleTo(IdleTable.ShowcaseHeight / math.max(info and info.height or 3, 0.5))
	end)
	-- near figure in lane 2 facing the far side (-Z), far figure in lane 3 facing you
	local x = (slot == 1 and (2 - (L.lanes + 1) / 2) or (3 - (L.lanes + 1) / 2)) * L.pitch
	local z = slot == 1 and L.creatureZ or -L.creatureZ
	local home = CFrame.new(x, S.groundTop + 0.03, z) * CFrame.Angles(0, slot == 1 and 0 or math.pi, 0)
	-- turned a little toward each other
	home = home * CFrame.Angles(0, slot == 1 and -0.32 or -0.32, 0)
	model:PivotTo(home)
	model.Name = "Showcase_" .. id
	model.Parent = S.folder
	return { model = model, home = home, id = id, phase = slot * 1.7, rise = 1 }
end

local function pickTwo()
	local pool = showcasePool()
	if #pool == 0 then
		return nil, nil
	end
	local a = pool[math.random(1, #pool)]
	local b = a
	local guard = 0
	while #pool > 1 and (b == a or CardData.Cards[b].family == CardData.Cards[a].family) and guard < 20 do
		b = pool[math.random(1, #pool)]
		guard += 1
	end
	return a, b
end

local function fillShowcase()
	local a, b = pickTwo()
	for slot, id in ipairs({ a, b }) do
		local old = S.showcase[slot]
		if old and old.model then
			old.model:Destroy()
		end
		S.showcase[slot] = id and spawnFigure(slot, id) or nil
	end
end

-- The two figures sink into the board, two new ones rise.
local function swapShowcase()
	if S.swapping then
		return
	end
	S.swapping = true
	task.spawn(function()
		local steps = 18
		for i = 1, steps do
			for _, f in pairs(S.showcase) do
				f.rise = 1 - i / steps
			end
			task.wait(1 / 30)
		end
		fillShowcase()
		for _, f in pairs(S.showcase) do
			f.rise = 0
		end
		for i = 1, steps do
			for _, f in pairs(S.showcase) do
				f.rise = i / steps
			end
			task.wait(1 / 30)
		end
		S.swapping = false
	end)
end

---------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------
function IdleTable.update(dt)
	if not (S.folder and S.visible) then
		return
	end
	S.t += dt
	local t = S.t
	-- rings breathe, slowly and out of step
	for _, r in ipairs(S.parts.rings or {}) do
		local ph = r:GetAttribute("Phase") or 0
		r.Transparency = 0.42 + 0.14 * math.sin(t * 0.9 + ph)
	end
	-- the gem in the medallion glows softly
	for _, g in ipairs(S.parts.gem or {}) do
		g.Transparency = 0.12 + 0.12 * math.sin(t * 1.6)
	end
	-- every 7 seconds a light runs along the seam
	local sweep = S.parts.sweep and S.parts.sweep[1]
	if sweep then
		local cycle = (t % 7) / 1.6
		if cycle <= 1 then
			local W = L.halfWidth
			sweep.CFrame = CFrame.new(-W + 0.8 + (2 * W - 1.6) * cycle, S.groundTop + 0.025, 0)
			sweep.Transparency = 1 - 0.75 * math.sin(cycle * math.pi)
		elseif sweep.Transparency < 1 then
			sweep.Transparency = 1
		end
	end
	-- the showcase figures breathe and turn a touch; they rise and sink when swapped
	for _, f in pairs(S.showcase) do
		if f.model.Parent then
			local k = f.rise
			local bob = math.sin(t * 1.4 + f.phase) * 0.05
			local turn = math.sin(t * 0.45 + f.phase) * 0.12
			f.model:PivotTo(f.home * CFrame.new(0, bob - (1 - k) * IdleTable.ShowcaseHeight * 0.9, 0) * CFrame.Angles(0, turn, 0))
			setFade(f.model, k < 0.999 and (1 - k) or 0)
		end
	end
	if t >= S.nextSwap then
		S.nextSwap = t + IdleTable.SwapSeconds
		if t > 1 then
			swapShowcase()
		end
	end
end

function IdleTable.setVisible(on)
	on = on and true or false
	S.visible = on
	if S.folder then
		S.folder.Parent = on and workspace or nil
	end
end

function IdleTable.isVisible()
	return S.visible and S.folder ~= nil and S.folder.Parent ~= nil
end

function IdleTable.attach(duelTable)
	if S.folder or not duelTable then
		return S.folder ~= nil
	end
	S.table = duelTable
	S.base = feltTop(duelTable)
	hideOld(duelTable)
	S.folder = Instance.new("Folder")
	S.folder.Name = "IdleTable"
	build()
	IdleTable.repaint(Cosmetics.equipped().board)
	fillShowcase()
	S.nextSwap = IdleTable.SwapSeconds
	S.folder.Parent = S.visible and workspace or nil
	Cosmetics.onChanged(function(eq)
		IdleTable.repaint(eq and eq.board)
	end)
	return true
end

return IdleTable

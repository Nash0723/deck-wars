-- The Brawl Box: a giant opened cardboard pack box turned into a wrestling ring, floating in the dark.
-- Built by the client for each pull (about 350 parts, a few milliseconds) and destroyed after.

local Kit = require(script.Parent:WaitForChild("Kit"))
local rgb, part, make = Kit.rgb, Kit.part, Kit.make

local Arena = {}
Arena.__index = Arena

local RING = 10.5
local TILE = 4
local NAVY, NAVY2 = rgb(32, 38, 74), rgb(40, 47, 90)
local CREAM = rgb(242, 230, 201)
local CARDBOARD = rgb(176, 132, 88)
local FAMILIES = { "Snack", "Junk", "Weather", "Critter", "Spooky", "Robo" }

local function at(x, y, z)
	return CFrame.new(Kit.ORIGIN + Vector3.new(x, y, z))
end

function Arena.new(parent)
	local self = setmetatable({}, Arena)
	local model = make("Model", { Name = "BrawlBox" }, parent)
	self.model = model
	self.tiles = {}
	self.ropes = {}
	self.rim = {}
	self.lights = {}
	self.posts = {}
	self.banners = {}
	self.crowd = {}
	self.halves = { left = {}, right = {} } -- for the Secret "reality shear"
	self.moving = {} -- parts with a temporary animation { part, base, t0, t1, fn }

	local function track(p)
		local side = (p.Position.X - Kit.ORIGIN.X) < 0 and "left" or "right"
		table.insert(self.halves[side], { part = p, base = p.CFrame })
		return p
	end

	-- floor: 6 x 6 tiles so pieces can pop up, in two navy shades
	for i = 0, 5 do
		for j = 0, 5 do
			local x, z = -10 + i * TILE, -10 + j * TILE
			local p = track(part({
				Name = "FloorTile",
				Size = Vector3.new(TILE - 0.04, 1, TILE - 0.04),
				CFrame = at(x, -0.5, z),
				Color = ((i + j) % 2 == 0) and NAVY or NAVY2,
			}, model))
			table.insert(self.tiles, { part = p, base = p.CFrame, x = x, z = z })
		end
	end
	-- card-back swirl: a cream ring with the logo in the middle
	local swirl = track(part({ Name = "Swirl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 15, 15), CFrame = at(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = CREAM }, model))
	local inner = track(part({ Name = "SwirlInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 13.4, 13.4), CFrame = at(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = NAVY }, model))
	local logo = track(part({ Name = "Logo", Size = Vector3.new(12, 0.06, 4), CFrame = at(0, 0.05, 0), Transparency = 1 }, model))
	local sg = make("SurfaceGui", { Face = Enum.NormalId.Top, LightInfluence = 0.6, CanvasSize = Vector2.new(600, 200) }, logo)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "DECK WARS",
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = CREAM,
		TextTransparency = 0.25,
	}, sg)
	self.swirl = { swirl, inner }

	-- the box under the ring, with its flaps folded out
	part({ Name = "Box", Size = Vector3.new(24.6, 5, 24.6), CFrame = at(0, -3.5, 0), Color = CARDBOARD, Material = Enum.Material.Cardboard }, model)
	for k = 0, 3 do
		local a = math.rad(90 * k)
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		local flapCf = CFrame.new(Kit.ORIGIN + dir * 15 + Vector3.new(0, -5.5, 0)) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-25), 0, 0)
		part({ Name = "Flap", Size = Vector3.new(24.6, 0.4, 7), CFrame = flapCf, Color = CARDBOARD:Lerp(rgb(0, 0, 0), 0.15), Material = Enum.Material.Cardboard }, model)
	end

	-- glowing rim around the floor (Hype Lights)
	for k = 0, 3 do
		local horiz = k % 2 == 0
		local sgn = k < 2 and 1 or -1
		local p = track(part({
			Name = "Rim",
			Size = horiz and Vector3.new(24.2, 0.25, 0.3) or Vector3.new(0.3, 0.25, 24.2),
			CFrame = horiz and at(0, 0.02, sgn * 12) or at(sgn * 12, 0.02, 0),
			Material = Enum.Material.Neon,
			Color = CREAM,
		}, model))
		table.insert(self.rim, p)
	end

	-- corner posts: stacked pencil erasers
	local ERASERS = { rgb(255, 140, 170), rgb(110, 170, 255), rgb(255, 140, 170) }
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
		local post = {}
		for e = 1, 3 do
			local p = track(part({ Name = "Eraser", Size = Vector3.new(1.3, 1.4, 1.3), CFrame = at(c[1] * RING, -0.7 + e * 1.45, c[2] * RING) * CFrame.Angles(0, math.rad(e * 9), 0), Color = ERASERS[e] }, model))
			table.insert(post, p)
		end
		table.insert(self.posts, post)
	end
	-- ropes: glowing hype ropes top and bottom, a licorice rope in the middle
	for _, h in ipairs({ 1.3, 2.5, 3.7 }) do
		for k = 0, 3 do
			local horiz = k % 2 == 0
			local sgn = k < 2 and 1 or -1
			local cf = horiz and at(0, h, sgn * RING) or at(sgn * RING, h, 0) * CFrame.Angles(0, math.rad(90), 0)
			local isLicorice = h == 2.5
			local p = track(part({
				Name = isLicorice and "Licorice" or "Rope",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(2 * RING, 0.28, 0.28),
				CFrame = cf,
				Material = isLicorice and Enum.Material.SmoothPlastic or Enum.Material.Neon,
				Color = isLicorice and rgb(170, 20, 40) or CREAM,
			}, model))
			if not isLicorice then
				table.insert(self.ropes, p)
			end
		end
	end
	-- hype lights under the ropes
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
		local holder = part({ Name = "HypeLight", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = at(c[1] * (RING - 0.8), 0.6, c[2] * (RING - 0.8)), Transparency = 1 }, model)
		table.insert(self.lights, make("PointLight", { Range = 14, Brightness = 1.6, Color = CREAM, Shadows = false }, holder))
	end

	-- family banners hanging behind the far rope
	for k, fam in ipairs(FAMILIES) do
		local x = -10 + (k - 1) * 4
		local p = track(part({ Name = "Banner_" .. fam, Size = Vector3.new(3, 4.2, 0.12), CFrame = at(x, 8.2, -13.5), Color = Kit.FamilyColor[fam], Material = Enum.Material.Fabric }, model))
		local g = make("SurfaceGui", { Face = Enum.NormalId.Front, LightInfluence = 0.8, CanvasSize = Vector2.new(150, 210) }, p)
		make("TextLabel", { Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.35), BackgroundTransparency = 1, Text = string.upper(fam), TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(30, 25, 40) }, g)
		part({ Name = "BannerPole", Size = Vector3.new(3.4, 0.18, 0.18), CFrame = at(x, 10.35, -13.5), Color = rgb(90, 70, 50) }, model)
		table.insert(self.banners, { part = p, base = p.CFrame })
	end

	-- the crowd: paper cut-outs on popsicle sticks behind three sides
	local seed = 7
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	local placements = {}
	for row = 0, 1 do
		for k = 0, 7 do
			table.insert(placements, { -10.5 + k * 3 + row * 1.5, -15.5 - row * 2.5, 0 })
			table.insert(placements, { -16 - row * 2.5, -9 + k * 2.6 + row * 1.2, 1 })
			table.insert(placements, { 16 + row * 2.5, -9 + k * 2.6 + row * 1.2, -1 })
		end
	end
	for i, pl in ipairs(placements) do
		local x, z = pl[1], pl[2]
		local baseY = -1 + (math.abs(z) > 15 and 0 or 0) + (i % 3) * 0.2
		local face = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, 0))
		local color = Color3.fromHSV(rnd(), 0.55, 0.95)
		local stick = part({ Name = "Stick", Size = Vector3.new(0.15, 3, 0.15), Color = rgb(225, 190, 140), Material = Enum.Material.Wood }, model)
		local head = part({ Name = "Fan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 2.2, 2.2), Color = color }, model)
		local eyeL = part({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Color = rgb(20, 15, 25) }, model)
		local eyeR = part({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Color = rgb(20, 15, 25) }, model)
		table.insert(self.crowd, {
			parts = { stick, head, eyeL, eyeR },
			offsets = {
				CFrame.new(0, 1.5, 0),
				CFrame.new(0, 3.9, 0) * CFrame.Angles(0, math.rad(90), 0),
				CFrame.new(-0.4, 4.1, -0.1),
				CFrame.new(0.4, 4.1, -0.1),
			},
			base = CFrame.new(Kit.ORIGIN + Vector3.new(x, baseY, z)) * face.Rotation,
			phase = rnd() * 6.28,
			speed = 4 + rnd() * 3,
		})
	end

	-- one warm key light over the ring
	local rig = part({ Name = "KeyLight", Size = Vector3.new(1, 1, 1), CFrame = at(0, 24, 4), Transparency = 1 }, model)
	self.key = make("SpotLight", { Face = Enum.NormalId.Bottom, Angle = 70, Brightness = 5, Range = 45, Color = rgb(255, 236, 205), Shadows = true }, rig)
	-- distant specks so the void has depth
	for k = 1, 70 do
		local a, b = rnd() * math.pi * 2, rnd() * 1.2 - 0.3
		local r = 140
		part({
			Name = "Speck",
			Size = Vector3.new(0.6, 0.6, 0.6),
			Shape = Enum.PartType.Ball,
			CFrame = CFrame.new(Kit.ORIGIN + Vector3.new(math.cos(a) * math.cos(b) * r, math.sin(b) * r, math.sin(a) * math.cos(b) * r)),
			Material = Enum.Material.Neon,
			Color = Color3.fromHSV(0.62 + rnd() * 0.2, 0.3, 0.6 + rnd() * 0.4),
		}, model)
	end

	self.hype = "Common"
	self.hypeFlare = 0
	self.cheer = 0.3 -- crowd excitement 0..1
	self:update(0, 0)
	return self
end

-- Ropes, rim and lights take the color of the rarest fighter in the ring.
function Arena:setHype(tier, now)
	self.hype = tier
	self.hypeFlare = 1
	self.cheer = math.min(1, self.cheer + 0.25)
	self:paint(now or 0)
end

function Arena:paint(now)
	local c = Kit.tierColor(self.hype, now)
	local boost = 1 + self.hypeFlare * 1.5
	for i, p in ipairs(self.ropes) do
		p.Color = self.hype == "Secret" and Kit.prism(now, i * 0.07) or c
	end
	for i, p in ipairs(self.rim) do
		p.Color = self.hype == "Secret" and Kit.prism(now, i * 0.25) or c
	end
	for _, l in ipairs(self.lights) do
		l.Color = c
		l.Brightness = 1.6 * boost
	end
end

-- Pops a floor tile (or a few) up where something landed hard.
function Arena:popTiles(at, now)
	for _, tile in ipairs(self.tiles) do
		local d = math.sqrt((tile.x - at.x) ^ 2 + (tile.z - at.z) ^ 2)
		if d < 4.5 then
			local tilt = (tile.x - at.x >= 0 and 1 or -1) * math.rad(14 + d * 3)
			table.insert(self.moving, {
				part = tile.part,
				base = tile.base,
				t0 = now,
				t1 = now + 0.5,
				fn = function(a)
					local up = math.sin(math.min(a * 2, 1) * math.pi / 2) * 0.6
					return tile.base * CFrame.new(0, up, 0) * CFrame.Angles(0, 0, tilt * math.min(a * 3, 1))
				end,
				keep = true,
			})
		end
	end
end

function Arena:crater(at, now)
	self:popTiles(at, now)
end

-- A banner tears and falls.
function Arena:dropBanner(now)
	for _, b in ipairs(self.banners) do
		if not b.fallen then
			b.fallen = true
			table.insert(self.moving, {
				part = b.part,
				base = b.base,
				t0 = now,
				t1 = now + 0.9,
				fn = function(a)
					return b.base * CFrame.new(0, -9 * a * a, 1.5 * a) * CFrame.Angles(math.rad(-80 * a), 0, math.rad(25 * a))
				end,
				keep = true,
			})
			return
		end
	end
end

-- Eraser chunks fly off a corner post.
function Arena:knockPost(index, now)
	local post = self.posts[((index - 1) % #self.posts) + 1]
	local top = post[#post]
	if top and not top:GetAttribute("Knocked") then
		top:SetAttribute("Knocked", true)
		local base = top.CFrame
		table.insert(self.moving, {
			part = top,
			base = base,
			t0 = now,
			t1 = now + 1.0,
			fn = function(a)
				return base * CFrame.new(3 * a, 5 * a - 9 * a * a, -2 * a) * CFrame.Angles(a * 6, a * 4, 0)
			end,
			keep = true,
		})
	end
end

-- Secret: the two halves of the world slide out of line ...
function Arena:shear(amount)
	for side, list in pairs(self.halves) do
		local s = side == "left" and 1 or -1
		local off = CFrame.new(0, s * 1.8 * amount, 0) * CFrame.Angles(0, 0, math.rad(s * 4 * amount))
		for _, e in ipairs(list) do
			e.part.CFrame = e.base * off
		end
	end
	self.sheared = amount > 0
end

-- ... and snap back.
function Arena:unshear()
	for _, list in pairs(self.halves) do
		for _, e in ipairs(list) do
			e.part.CFrame = e.base
		end
	end
	self.sheared = false
end

-- Every frame: crowd bobbing, hype flare fading, rainbow ropes, temporary part animations.
function Arena:update(now, dt, frozen)
	if frozen then
		return
	end
	self.hypeFlare = math.max(0, self.hypeFlare - dt * 2.5)
	self.cheer = math.max(0.3, self.cheer - dt * 0.05)
	self:paint(now)
	for _, fan in ipairs(self.crowd) do
		local bob = math.abs(math.sin(now * fan.speed + fan.phase)) * (0.3 + 1.2 * self.cheer)
		local sway = math.sin(now * fan.speed * 0.5 + fan.phase) * 0.12 * self.cheer
		local cf = fan.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, sway)
		for i, p in ipairs(fan.parts) do
			p.CFrame = cf * fan.offsets[i]
		end
	end
	for i = #self.moving, 1, -1 do
		local m = self.moving[i]
		local a = math.clamp((now - m.t0) / (m.t1 - m.t0), 0, 1)
		if now >= m.t0 then
			m.part.CFrame = m.fn(a)
		end
		if a >= 1 then
			table.remove(self.moving, i)
		end
	end
end

-- The pack in the middle of the ring at the start: shakes, then rips open.
-- pack = a pack from Packs.luau (its colors and name), or nil for the classic Brawl Pack look.
function Arena:makePack(parent, at, pack)
	local base = CFrame.new(Kit.world(at, 2.2))
	local main, accent, label = rgb(120, 70, 220), rgb(150, 100, 240), "DECK\nWARS"
	if pack and pack.color then
		main = rgb(pack.color[1], pack.color[2], pack.color[3])
		accent = rgb(pack.accent[1], pack.accent[2], pack.accent[3])
		if pack.family then
			label = string.upper(string.gsub(pack.name, " Pack$", ""))
		end
	end
	local body = part({ Name = "PackBody", Size = Vector3.new(3, 3.4, 0.5), CFrame = base, Color = main, Material = Enum.Material.Foil, Reflectance = 0.15 }, parent)
	local top = part({ Name = "PackTop", Size = Vector3.new(3, 0.8, 0.5), CFrame = base * CFrame.new(0, 2.1, 0), Color = accent, Material = Enum.Material.Foil }, parent)
	local g = make("SurfaceGui", { Face = Enum.NormalId.Front, LightInfluence = 0.5, CanvasSize = Vector2.new(300, 340) }, body)
	make("TextLabel", { Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.25), BackgroundTransparency = 1, Text = label, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 230, 120):Lerp(accent, 0.5) }, g)
	return { body = body, top = top, base = base }
end

function Arena:destroy()
	self.model:Destroy()
end

return Arena

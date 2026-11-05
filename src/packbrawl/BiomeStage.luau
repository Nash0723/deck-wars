-- The biome stage: Pack Brawl fought on the Duel Table inside one of the match worlds.
--
-- A copy of the room's Duel Table plus a world from DeckWars.Backdrops are built far above the
-- room (at Kit.ORIGIN), on this player's screen only, so the real room, other players and any
-- match are never touched. The table's top is the ring: the board surface sits exactly at
-- Kit.ORIGIN.Y, so the fight's positions work unchanged.
--
-- It answers the same calls as the Brawl Box (Arena.luau): setHype, paint, popTiles, crater,
-- dropBanner, knockPost, shear, unshear, update, makePack, destroy, plus:
--   setLevel(cue, now)  the world escalation from Scripts.addEnv (levels 0..5, calm, slam, pulse)
--   podium(tier, now)   Take the Top: the world sinks so the table rises as the winner's podium
--   rebuild(color)      Secret: the world comes back in the winner's colours
--
-- BiomeStage.new(parent, worldKey, opts) opts = { tier, winnerColor, low = true on Low graphics }

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local here = script.Parent
local Kit = require(here:WaitForChild("Kit"))
local BiomeFx = require(here:WaitForChild("BiomeFx"))
local Arena = require(here:WaitForChild("Arena"))
local rgb, part, make = Kit.rgb, Kit.part, Kit.make

local BiomeStage = {}
BiomeStage.__index = BiomeStage

local function backdrops()
	local shared = ReplicatedStorage:FindFirstChild("DeckWars")
	local m = shared and shared:FindFirstChild("Backdrops")
	return m and require(m)
end

-- Is the biome stage available (the world module is in the game)?
function BiomeStage.available()
	local ok, B = pcall(backdrops)
	return ok and B ~= nil and B.buildInto ~= nil
end

-- Table parts that don't belong on a podium: the chairs, the hanging lamps, the seats.
local DROP_PREFIX = { "Chair", "Armrest", "ArmPost", "BackCushion", "TableLamp", "Seat_" }
local LEG_NAMES = { Leg = true, LegKnob = true, LegFoot = true, Stretcher = true }
local FLOOR_NAMES = { TableTop = true, Felt = true, BoardBed = true }
local RIM_NAMES = { Rim = true, RimCorner = true }

local function startsWith(s, list)
	for _, p in ipairs(list) do
		if string.sub(s, 1, #p) == p then
			return true
		end
	end
	return false
end

local function findTable()
	local room = workspace:FindFirstChild("MenuRoom")
	local stations = room and room:FindFirstChild("Stations")
	local t = stations and stations:FindFirstChild("DuelTable")
	if t then
		return t
	end
	return room and room:FindFirstChild("DuelTable", true)
end

local function flat(p)
	return p.Size.Y < 0.6 and math.min(p.Size.X, p.Size.Z) > 1.5
end

local function moveAll(parts, cfs)
	if #parts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(parts) do
			p.CFrame = cfs[i]
		end
	end
end

function BiomeStage.new(parent, worldKey, opts)
	opts = opts or {}
	local B = assert(backdrops(), "DeckWars.Backdrops is missing")
	local self = setmetatable({}, BiomeStage)
	self.world = BiomeFx.IsWorld[worldKey] and worldKey or "Candy"
	self.recipe = BiomeFx.recipe(self.world)
	self.tier = opts.tier or "Common"
	self.low = opts.low == true
	self.model = make("Folder", { Name = "BiomeStage" }, nil)
	self.hype = "Common"
	self.hypeFlare = 0
	self.cheer = 0.3
	self.level = 0
	self.calm = false
	self.moving = {} -- { part = entry, t0, t1, fn(a) -> CFrame (before the drop) }
	self.drop = 0
	self.lastDrop = 0
	self.tiles = {}
	self.ropes = {}
	self.rim = {}
	self.entries = {} -- every part that sinks or splits: { part, base, side, moving, cluster }
	self.clusters = {} -- props that sway and topple: { entries, pivot, phase, r, down }
	self.emitters = {} -- { emitter, rate }
	self.extras = {} -- things added by levels (pillar, eye, storm...)

	-- 1. the table copy, its board surface at Kit.ORIGIN
	local O = Kit.ORIGIN
	local real = findTable()
	local floorY, center, top = 4, Vector3.new(0, 0, 0), nil
	if real then
		local tt = real:FindFirstChild("TableTop", true)
		if tt and tt:IsA("BasePart") then
			top = tt
			center = Vector3.new(tt.Position.X, 0, tt.Position.Z)
			floorY = tt.Position.Y + tt.Size.Y / 2
		end
		for _, d in ipairs(real:GetDescendants()) do
			if d:IsA("BasePart") and FLOOR_NAMES[d.Name] then
				floorY = math.max(floorY, d.Position.Y + d.Size.Y / 2)
			end
		end
	end
	self.tableSize = top and Vector2.new(top.Size.X, top.Size.Z) or Vector2.new(25, 22)
	local tableShift = O - Vector3.new(center.X, floorY, center.Z)
	self.worldShift = O - Vector3.new(0, floorY, 0)
	local copy
	if real then
		copy = real:Clone()
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("Seat") or d:IsA("VehicleSeat") or d:IsA("BaseScript") or d:IsA("ClickDetector") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
				d:Destroy()
			elseif d:IsA("BasePart") and startsWith(d.Name, DROP_PREFIX) then
				d:Destroy()
			end
		end
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("BasePart") then
				-- the old tile board is hidden in the room (IdleTable lays the lane board over
				-- it); the stage's copy keeps its tiles, which sink and split in the fight
				local was = d:GetAttribute("IdleTransparency")
				if type(was) == "number" then
					d.Transparency = was
				end
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CFrame = d.CFrame + tableShift
			end
		end
		copy.Name = "StageTable"
	else
		copy = make("Model", { Name = "StageTable" }, nil)
		part({ Name = "TableTop", Size = Vector3.new(25, 1.2, 22), CFrame = CFrame.new(O - Vector3.new(0, 0.6, 0)), Color = rgb(120, 80, 50), Material = Enum.Material.Wood }, copy)
	end
	copy.Parent = self.model
	self.table = copy
	self.legs = {}
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then
			local tileC, tileR = string.match(d.Name, "^Tile_(%d+)_(%d+)$")
			if tileC then
				table.insert(self.tiles, { part = d, base = d.CFrame, x = d.Position.X - O.X, z = d.Position.Z - O.Z })
			elseif RIM_NAMES[d.Name] then
				table.insert(self.rim, d)
			elseif LEG_NAMES[d.Name] then
				table.insert(self.legs, d)
			end
		end
	end

	-- the ring's edge: four glowing strips round the table top, in the fight's colour
	local hx, hz = self.tableSize.X / 2 - 0.15, self.tableSize.Y / 2 - 0.15
	for _, s in ipairs({ { 0, hz, self.tableSize.X, 0.25 }, { 0, -hz, self.tableSize.X, 0.25 }, { hx, 0, 0.25, self.tableSize.Y }, { -hx, 0, 0.25, self.tableSize.Y } }) do
		table.insert(self.ropes, part({ Name = "RingEdge", Size = Vector3.new(s[3], 0.12, s[4]), CFrame = CFrame.new(O + Vector3.new(s[1], 0.08, s[2])), Material = Enum.Material.Neon, Color = Kit.TierColor.Common }, self.model))
	end
	-- a soft key light over the ring (the world's sun does most of the work; the poses dim this
	-- one for their own spotlight moments, like the Spooky bow)
	local rig = part({ Name = "KeyLight", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(O + Vector3.new(0, 24, 4)), Transparency = 1 }, self.model)
	self.key = make("SpotLight", { Face = Enum.NormalId.Bottom, Angle = 70, Brightness = 2.5, Range = 45, Color = rgb(255, 240, 220), Shadows = true }, rig)
	-- the podium column under the table, shown when the table rises
	local floor = self.recipe.floor
	self.column = part({ Name = "PodiumColumn", Size = Vector3.new(self.tableSize.X * 0.72, 30, self.tableSize.Y * 0.72), CFrame = CFrame.new(O - Vector3.new(0, 1.3 + 15, 0)), Color = floor.color, Material = floor.material, Transparency = 1 }, self.model)
	self.columnTrim = part({ Name = "PodiumTrim", Size = Vector3.new(self.tableSize.X * 0.76, 0.5, self.tableSize.Y * 0.76), CFrame = CFrame.new(O - Vector3.new(0, 1.55, 0)), Color = Kit.TierColor.Common, Material = Enum.Material.Neon, Transparency = 1 }, self.model)

	-- 2. the world
	local worldFolder = make("Folder", { Name = "World" }, nil)
	local theme, count = B.buildInto(self.world, worldFolder, self.worldShift)
	self.partCount = count
	self.theme = theme
	worldFolder.Parent = self.model
	self.worldFolder = worldFolder
	self:classify(worldFolder)

	-- 3. sky, atmosphere and lighting (the Director saved the old values and puts them back)
	self.savedSky = {}
	for _, cls in ipairs({ "Sky", "Atmosphere" }) do
		for _, old in ipairs(Lighting:GetChildren()) do
			if old:IsA(cls) then
				table.insert(self.savedSky, old)
				old.Parent = nil
			end
		end
	end
	if theme then
		self.sky = make("Sky", theme.sky or {}, Lighting)
		self.sky.Name = "BiomeStageSky"
		self.atmo = make("Atmosphere", theme.atmosphere or {}, Lighting)
		self.atmo.Name = "BiomeStageAtmosphere"
		self.baseLight = theme.lighting or {}
		for k, v in pairs(self.baseLight) do
			pcall(function()
				Lighting[k] = v
			end)
		end
		self.baseDensity = self.atmo.Density
		self.baseAtmoColor = self.atmo.Color
		-- the Bloom: the world starts hidden in its own fog and clears outward
		self.atmo.Density = 0.92
	end
	self.lightTarget = self.baseLight
	self.model.Parent = parent
	self:update(0, 0)
	return self
end

-- Sorts the world's parts: what sinks and splits, the props that sway and topple, the landmark,
-- the far scenery (hidden on Low graphics) and the particle emitters.
function BiomeStage:classify(folder)
	local S = self.worldShift
	local R = self.recipe.landmark
	local candidates = {}
	self.landmark = {}
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			local rel = p.Position - S
			local r = Vector2.new(rel.X, rel.Z).Magnitude
			local huge = p.Size.X > 300 or p.Size.Z > 300
			local isLandmark = false
			if R.named then
				isLandmark = p.Name == R.named
			elseif R.craters then
				isLandmark = r > 120 and p.Material == Enum.Material.Neon and p.Shape == Enum.PartType.Cylinder and math.abs(p.Size.X - 1) < 0.01
			elseif R.center then
				isLandmark = (rel - R.center).Magnitude < R.radius
			end
			if isLandmark then
				table.insert(self.landmark, p)
			end
			if self.low and r > 130 and not isLandmark and not huge then
				p.Parent = nil
			else
				local e = { part = p, base = p.CFrame, side = (not huge and not (r < 36 and flat(p))) and (rel.X < 0 and -1 or 1) or 0 }
				table.insert(self.entries, e)
				local topY = rel.Y + p.Size.Y / 2
				local botY = rel.Y - p.Size.Y / 2
				if not isLandmark and r > 13.5 and r < 60 and topY < 18 and topY > 0.9 and botY < 6 and not huge then
					table.insert(candidates, e)
				end
				for _, d in ipairs(p:GetChildren()) do
					if d:IsA("ParticleEmitter") then
						table.insert(self.emitters, { emitter = d, rate = d.Rate })
						if self.low then
							d.Rate = d.Rate * 0.5
						end
					end
				end
			end
		end
	end
	-- props: parts standing within 2.6 studs of each other's foot form one prop
	for _, e in ipairs(candidates) do
		local foot = Vector3.new(e.part.Position.X, 0, e.part.Position.Z)
		local home
		for _, c in ipairs(self.clusters) do
			if (c.foot - foot).Magnitude < 2.6 and #c.entries < 16 then
				home = c
				break
			end
		end
		if not home then
			home = { entries = {}, foot = foot }
			table.insert(self.clusters, home)
		end
		table.insert(home.entries, e)
		e.cluster = home
	end
	for i, c in ipairs(self.clusters) do
		local low = math.huge
		for _, e in ipairs(c.entries) do
			low = math.min(low, e.part.Position.Y - e.part.Size.Y / 2)
		end
		c.pivot = CFrame.new(c.foot.X, math.max(low, S.Y), c.foot.Z)
		c.r = Vector2.new(c.foot.X - S.X, c.foot.Z - S.Z).Magnitude
		c.phase = i * 1.7
		c.speed = 1.6 + (i % 5) * 0.25
	end
	table.sort(self.clusters, function(a, b)
		return a.r < b.r
	end)
	-- only the 40 nearest props sway (that's what the camera sees)
	self.swaying = {}
	for i = 1, math.min(40, #self.clusters) do
		table.insert(self.swaying, self.clusters[i])
	end
end

---------------------------------------------------------------------------
-- The Brawl Box calls
---------------------------------------------------------------------------

function BiomeStage:setHype(tier, now)
	self.hype = tier
	self.hypeFlare = 1
	self.cheer = math.min(1, self.cheer + 0.25)
	self:paint(now or 0)
end

function BiomeStage:paint(now)
	local c = Kit.tierColor(self.hype, now)
	for i, p in ipairs(self.ropes) do
		p.Color = self.hype == "Secret" and Kit.prism(now, i * 0.2) or c
	end
	for i, p in ipairs(self.rim) do
		p.Color = self.hype == "Secret" and Kit.prism(now, i * 0.25) or p.Color:Lerp(c, 0.08 + self.hypeFlare * 0.1)
	end
end

-- Board tiles pop up where something landed hard.
function BiomeStage:popTiles(at, now)
	for _, tile in ipairs(self.tiles) do
		local d = math.sqrt((tile.x - at.x) ^ 2 + (tile.z - at.z) ^ 2)
		if d < 4.5 then
			local tilt = (tile.x - at.x >= 0 and 1 or -1) * math.rad(14 + d * 3)
			table.insert(self.moving, {
				part = tile.part,
				t0 = now,
				t1 = now + 0.5,
				table = true,
				fn = function(a)
					local up = math.sin(math.min(a * 2, 1) * math.pi / 2) * 0.5
					return tile.base * CFrame.new(0, up, 0) * CFrame.Angles(0, 0, tilt * math.min(a * 3, 1))
				end,
			})
		end
	end
end

function BiomeStage:crater(at, now)
	self:popTiles(at, now)
	self:quake(now, 0.5)
end

-- The world's banner drops in behind the table and swings to a stop.
function BiomeStage:dropBanner(now)
	if self.bannerDropped then
		return
	end
	self.bannerDropped = true
	local O = Kit.ORIGIN
	local banner = part({ Name = "WorldBanner", Size = Vector3.new(16, 22, 0.3), Color = self.recipe.banner, Material = Enum.Material.Fabric }, self.model)
	local trim = part({ Name = "WorldBannerTrim", Size = Vector3.new(16.6, 0.8, 0.5), Color = Kit.tierColor(self.hype, now), Material = Enum.Material.Neon }, self.model)
	local rest = CFrame.new(O + Vector3.new(0, 16, -44))
	table.insert(self.moving, {
		part = banner,
		t0 = now,
		t1 = now + 1.1,
		fixed = true,
		fn = function(a)
			local fall = (1 - Kit.outBack(a)) * 40
			return rest * CFrame.new(0, fall, 0) * CFrame.Angles(math.rad(math.sin(a * 9) * 10 * (1 - a)), 0, 0)
		end,
	})
	table.insert(self.moving, {
		part = trim,
		t0 = now,
		t1 = now + 1.1,
		fixed = true,
		fn = function(a)
			local fall = (1 - Kit.outBack(a)) * 40
			return rest * CFrame.new(0, fall + 11.2, 0)
		end,
	})
	banner.CFrame = rest * CFrame.new(0, 40, 0)
	trim.CFrame = rest * CFrame.new(0, 51, 0)
end

-- A fighter thrown into the scenery knocks the index-th nearest prop over.
function BiomeStage:knockPost(index, now)
	local n = 0
	for _, c in ipairs(self.clusters) do
		if not c.down then
			n += 1
			if n >= (index or 1) then
				self:topple(c, now)
				return
			end
		end
	end
end

-- Secret: the world splits down the middle and pulls apart ...
function BiomeStage:shear(amount)
	local parts, cfs = {}, {}
	local drop = CFrame.new(0, -self.drop, 0)
	for _, e in ipairs(self.entries) do
		if e.side ~= 0 then
			local s = e.side
			table.insert(parts, e.part)
			table.insert(cfs, CFrame.new(s * 7 * amount, -2.5 * amount, 0) * drop * e.base * CFrame.Angles(0, 0, math.rad(s * 3 * amount)))
		end
	end
	moveAll(parts, cfs)
	self.sheared = amount > 0
end

-- ... and snaps back.
function BiomeStage:unshear()
	self.sheared = false
	self.lastDrop = nil -- forces every part back to its place on the next update
	self:place()
end

-- Every frame (on the Director's clock): fog clearing, light easing to the level, swaying props,
-- particles, toppling props, the sky eye, the sinking world.
function BiomeStage:update(now, dt, frozen)
	self:setFrozen(frozen)
	if frozen then
		return
	end
	self.hypeFlare = math.max(0, self.hypeFlare - dt * 2.5)
	self.cheer = math.max(0.3, self.cheer - dt * 0.05)
	self:paint(now)
	-- the Bloom: fog clears over the first 1.1 s, then follows the level
	if self.atmo then
		local wantD = self.baseDensity + ((self.level >= 3 and self.level < 5 and not self.calm) and 0.08 or 0)
		local a = Kit.clamp01(now / 1.1)
		if a < 1 then
			self.atmo.Density = 0.92 + (wantD - 0.92) * Kit.outCubic(a)
		else
			self.atmo.Density += (wantD - self.atmo.Density) * math.min(1, dt * 3)
		end
		local wantC = (self.level >= 3 and self.level < 5) and self.baseAtmoColor:Lerp(self.recipe.stormTint, 0.5) or self.baseAtmoColor
		self.atmo.Color = self.atmo.Color:Lerp(wantC, math.min(1, dt * 3))
	end
	-- light eases toward the level's target
	local k = math.min(1, dt * 3)
	for key, want in pairs(self.lightTarget or {}) do
		local cur = Lighting[key]
		if typeof(want) == "Color3" and typeof(cur) == "Color3" then
			Lighting[key] = cur:Lerp(want, k)
		elseif type(want) == "number" and type(cur) == "number" and key ~= "ClockTime" then
			Lighting[key] = cur + (want - cur) * k
		end
	end
	-- the sky eye turns
	if self.eye then
		self.eyeSpin = (self.eyeSpin or 0) + dt * 0.4
		self.eye.CFrame = self.eye.CFrame:Lerp(self.eyeHome * CFrame.Angles(0, self.eyeSpin, 0), 1)
		local open = Kit.clamp01((now - self.eyeT0) / 0.8)
		self.eye.Size = Vector3.new(0.6, 52 * Kit.outBack(open) + 0.1, 52 * Kit.outBack(open) + 0.1)
	end
	if self.pillar then
		local a = Kit.clamp01((now - self.pillarT0) / 0.6)
		self.pillar.Transparency = 1 - 0.6 * a
	end
	if self.strike and now > self.strike.t1 then
		self.strike.part:Destroy()
		self.strike = nil
	end
	-- Take the Top: the world sinks so the table rises
	if self.sink then
		local a = Kit.clamp01((now - self.sink.t0) / 0.7)
		self.drop = self.sink.height * Kit.outCubic(a)
	end
	self:place(now)
end

-- Puts every world part where it should be this frame.
function BiomeStage:place(now)
	now = now or self.lastNow or 0
	self.lastNow = now
	if self.sheared then
		return
	end
	local drop = CFrame.new(0, -self.drop, 0)
	local parts, cfs = {}, {}
	local dropChanged = self.lastDrop ~= self.drop
	self.lastDrop = self.drop
	-- moving parts (toppling props, popping tiles, banner)
	local busy = {}
	for i = #self.moving, 1, -1 do
		local m = self.moving[i]
		local a = Kit.clamp01((now - m.t0) / (m.t1 - m.t0))
		local cf = m.fn(a)
		if m.entry then
			busy[m.entry] = true
			if a >= 1 then
				m.entry.base = cf -- it stays where it fell
			end
			table.insert(parts, m.entry.part)
			table.insert(cfs, drop * cf)
		else
			table.insert(parts, m.part)
			table.insert(cfs, cf)
		end
		if a >= 1 then
			table.remove(self.moving, i)
		end
	end
	-- swaying props
	local amp = math.rad(BiomeFx.Sway[self.level] or 0) * (self.calm and 0.15 or 1)
	if self.quakeUntil and now < self.quakeUntil then
		amp += math.rad(6) * (self.quakeUntil - now)
	end
	for _, c in ipairs(self.swaying) do
		if not c.down and amp > 0 then
			local w = math.sin(now * c.speed + c.phase) * amp
			local rot = c.pivot * CFrame.Angles(w * 0.6, 0, w) * c.pivot:Inverse()
			for _, e in ipairs(c.entries) do
				if not busy[e] then
					busy[e] = true
					table.insert(parts, e.part)
					table.insert(cfs, drop * rot * e.base)
				end
			end
		elseif c.wasSwaying then
			for _, e in ipairs(c.entries) do
				if not busy[e] then
					busy[e] = true
					table.insert(parts, e.part)
					table.insert(cfs, drop * e.base)
				end
			end
		end
		c.wasSwaying = amp > 0 and not c.down
	end
	if dropChanged then
		for _, e in ipairs(self.entries) do
			if not busy[e] then
				table.insert(parts, e.part)
				table.insert(cfs, drop * e.base)
			end
		end
		for _, x in ipairs(self.extras) do
			if x.sinks and x.part.Parent then
				table.insert(parts, x.part)
				table.insert(cfs, drop * x.base)
			end
		end
	end
	moveAll(parts, cfs)
end

function BiomeStage:setFrozen(frozen)
	frozen = frozen == true
	if self.frozenNow == frozen then
		return
	end
	self.frozenNow = frozen
	for _, em in ipairs(self.emitters) do
		em.emitter.TimeScale = frozen and 0 or 1
	end
	if self.storm then
		self.storm.TimeScale = frozen and 0 or 1
	end
end

function BiomeStage:setParticleRate(mult)
	for _, em in ipairs(self.emitters) do
		em.emitter.Rate = em.rate * mult * (self.low and 0.5 or 1)
	end
end

function BiomeStage:topple(c, now)
	if c.down then
		return
	end
	c.down = true
	local O = Kit.ORIGIN
	local away = Vector3.new(c.foot.X - O.X, 0, c.foot.Z - O.Z)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
	local axis = Vector3.new(0, 1, 0):Cross(away)
	for _, e in ipairs(c.entries) do
		local base = e.base
		table.insert(self.moving, {
			entry = e,
			t0 = now,
			t1 = now + 0.8,
			fn = function(a)
				local ang = math.rad(82) * Kit.inQuad(a)
				local bounce = a > 0.85 and math.sin((a - 0.85) / 0.15 * math.pi) * math.rad(-6) or 0
				local rot = c.pivot * CFrame.fromAxisAngle(axis, ang + bounce) * c.pivot:Inverse()
				return rot * base
			end,
		})
	end
end

-- A short rumble: props shake harder for a moment.
function BiomeStage:quake(now, seconds)
	self.quakeUntil = now + (seconds or 0.5)
end

---------------------------------------------------------------------------
-- The world escalation
---------------------------------------------------------------------------

local function extra(self, p, sinks)
	table.insert(self.extras, { part = p, base = p.CFrame, sinks = sinks })
	return p
end

-- Where the landmark's light comes from: the top of its tallest part, or the recipe's point.
function BiomeStage:landmarkTop()
	local best
	for _, p in ipairs(self.landmark) do
		local y = p.Position.Y + p.Size.Y / 2
		if not best or y > best.Y then
			best = Vector3.new(p.Position.X, y, p.Position.Z)
		end
	end
	return best or (self.recipe.beaconTop + self.worldShift)
end

function BiomeStage:awaken(now)
	local r = self.recipe
	-- the landmark lights up and sends a pillar of light into the sky
	local topAt = self:landmarkTop()
	self.pillar = extra(self, part({ Name = "LandmarkPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(500, 7, 7), CFrame = CFrame.new(topAt + Vector3.new(0, 250, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = r.glow, Material = Enum.Material.Neon, Transparency = 1 }, self.model), true)
	self.pillarT0 = now
	local lit = 0
	for _, p in ipairs(self.landmark) do
		if lit < 4 and p.Size.Magnitude > 4 then
			lit += 1
			make("PointLight", { Color = r.glow, Range = 60, Brightness = 3, Shadows = false }, p)
		end
		if p.Material == Enum.Material.Neon then
			p.Color = p.Color:Lerp(r.glow, 0.5)
		end
	end
	-- the storm starts, light at first
	local O = Kit.ORIGIN
	local s = r.storm
	local holder = extra(self, part({ Name = "StormBox", Size = Vector3.new(140, 1, 120), CFrame = CFrame.new(O + Vector3.new(0, s.up and -3 or 30, -15)), Transparency = 1 }, self.model), false)
	local dir = s.up and Enum.NormalId.Top or Enum.NormalId.Bottom
	local em = make("ParticleEmitter", {
		Texture = Kit.TEX_SPARK,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = dir,
		Speed = NumberRange.new(s.speed[1], s.speed[2]),
		Lifetime = NumberRange.new(s.life[1], s.life[2]),
		Size = NumberSequence.new(s.size[1], s.size[2]),
		Color = ColorSequence.new(s.colors[1], s.colors[2]),
		LightEmission = 0.6,
		SpreadAngle = Vector2.new(s.side and 50 or 15, s.side and 50 or 15),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-(s.spin or 0), s.spin or 0),
		Acceleration = s.side and Vector3.new(14, -2, 0) or (s.meteor and Vector3.new(-30, 0, 0) or Vector3.zero),
		Rate = 0,
	}, holder)
	self.storm = em
	self.stormRate = s.rate * (self.low and 0.5 or 1)
end

function BiomeStage:skyBreak(now)
	local O = Kit.ORIGIN
	self.eyeHome = CFrame.new(O + Vector3.new(0, 62, -18)) * CFrame.Angles(0, 0, math.rad(90))
	self.eye = extra(self, part({ Name = "SkyEye", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.1, 0.1), CFrame = self.eyeHome, Color = self.recipe.eye, Material = Enum.Material.Neon, Transparency = 0.35 }, self.model), false)
	self.eyeT0 = now
	make("PointLight", { Color = self.recipe.eye, Range = 60, Brightness = 2.5, Shadows = false }, self.eye)
end

-- A beam from the landmark (or the sky eye) to the table on the biggest hits.
function BiomeStage:strikeAt(now)
	local from = self.eye and self.eye.Position or self:landmarkTop()
	local to = Kit.ORIGIN + Vector3.new(0, 1, 0)
	local len = (to - from).Magnitude
	if self.strike then
		self.strike.part:Destroy()
	end
	local p = part({ Name = "LandmarkStrike", Size = Vector3.new(1.6, 1.6, len), CFrame = CFrame.lookAt((from + to) / 2, to), Color = self.recipe.glow:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon, Transparency = 0.15 }, self.model)
	self.strike = { part = p, t1 = now + 0.35 }
	self:quake(now, 0.6)
end

-- Secret: the world comes back in the winner's colours.
function BiomeStage:rebuild(color)
	if not color then
		return
	end
	for _, p in ipairs(self.landmark) do
		p.Color = p.Color:Lerp(color, 0.55)
	end
	for _, c in ipairs(self.clusters) do
		for _, e in ipairs(c.entries) do
			e.part.Color = e.part.Color:Lerp(color, 0.35)
		end
	end
	if self.pillar then
		self.pillar.Color = color
	end
	if self.eye then
		self.eye.Color = color
	end
	if self.storm then
		self.storm.Rate = 0
	end
	self.lightTarget = BiomeFx.lightingFor(self.baseLight or {}, 5, color, self.recipe)
end

-- One env cue from Scripts.addEnv: { level, calm?, slam?, pulse?, cascade? }.
function BiomeStage:setLevel(c, now)
	local level = c.level or self.level
	if c.calm then
		self.calm = true
		self:setParticleRate(BiomeFx.Calm)
		if self.storm then
			self.storm.Rate = self.stormRate * 0.1
		end
		return
	end
	if c.slam then
		self.calm = false
		self:quake(now, 0.8)
		self:knockPost(1, now)
	end
	if c.pulse then
		if self.level >= 3 then
			self:strikeAt(now)
		end
		return
	end
	local from = self.level
	self.level = math.max(self.level, level)
	if not c.slam then
		self.calm = false
	end
	self:setParticleRate(BiomeFx.ParticleRate[self.level] or 1)
	self.lightTarget = BiomeFx.lightingFor(self.baseLight or {}, self.level, Kit.tierColor(self.hype, now), self.recipe)
	if self.level >= 2 and from < 2 then
		self:quake(now, 0.6)
		self:knockPost(1, now)
		self:knockPost(2, now)
	end
	if self.level >= 3 and from < 3 then
		self:awaken(now)
	end
	if self.level >= 4 and from < 4 then
		self:skyBreak(now)
	end
	if self.storm then
		self.storm.Rate = self.stormRate * (BiomeFx.Storm[self.level] or 0)
	end
end

-- Take the Top: the defeated are gone; the world sinks (the table rises with the winner on it).
function BiomeStage:podium(tier, now)
	local h = BiomeFx.Podium[tier] or 2
	self.sink = { t0 = now, height = h }
	self.column.Transparency = 0
	self.columnTrim.Transparency = (tier == "Common" or tier == "Rare") and 1 or 0
	self.columnTrim.Color = Kit.tierColor(tier, now)
	for _, p in ipairs(self.legs) do
		p.Transparency = 1
	end
	self:quake(now, 0.4)
end

-- The pack in the middle of the table at the start (same as the Brawl Box's).
function BiomeStage:makePack(parent, at, pack)
	return Arena.makePack(self, parent, at, pack)
end

function BiomeStage:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.sky then
		self.sky:Destroy()
	end
	if self.atmo then
		self.atmo:Destroy()
	end
	for _, old in ipairs(self.savedSky) do
		old.Parent = Lighting
	end
	self.model:Destroy()
end

return BiomeStage

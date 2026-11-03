-- Fighters in the Brawl Box: the game's own creature models, moved by hand every frame so the
-- Director's clock (hit-stop, slow motion, fast-forward, skip) controls everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent:WaitForChild("Kit"))
local DeckWars = ReplicatedStorage:WaitForChild("DeckWars")
local CreatureBuilder = require(DeckWars:WaitForChild("CreatureBuilder"))
local CardData = require(DeckWars:WaitForChild("CardData"))

local rgb, make = Kit.rgb, Kit.make
local S = Kit.SCALE

local Fighter = {}
Fighter.__index = Fighter

local Fighters = {}

-- A spell has no creature, so it fights as a giant glowing card.
local function buildSpellCard(def)
	local model = Instance.new("Model")
	model.Name = def.id
	local root = Kit.part({ Name = "Root", Size = Vector3.new(1, 0.1, 1), Transparency = 1 }, model)
	model.PrimaryPart = root
	local fam = Kit.FamilyColor[def.family] or Kit.FamilyColor.Any
	local card = Kit.part({ Name = "Card", Size = Vector3.new(2.2, 3.1, 0.12), CFrame = CFrame.new(0, 1.9, 0), Color = rgb(250, 245, 235) }, model)
	Kit.part({ Name = "Frame", Size = Vector3.new(2.4, 3.3, 0.08), CFrame = CFrame.new(0, 1.9, 0.03), Color = Kit.TierColor[def.rarity] or fam, Material = Enum.Material.Neon }, model)
	local g = make("SurfaceGui", { Face = Enum.NormalId.Front, LightInfluence = 0.3, CanvasSize = Vector2.new(220, 310) }, card)
	make("TextLabel", { Size = UDim2.fromScale(0.9, 0.25), Position = UDim2.fromScale(0.05, 0.05), BackgroundTransparency = 1, Text = def.name, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(40, 30, 60) }, g)
	make("TextLabel", { Size = UDim2.fromScale(0.9, 0.4), Position = UDim2.fromScale(0.05, 0.35), BackgroundTransparency = 1, Text = "✦", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = Kit.TierColor[def.rarity] or fam }, g)
	make("TextLabel", { Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.78), BackgroundTransparency = 1, Text = "SPELL", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(90, 80, 110) }, g)
	return model, { height = 3.5, width = 2.4, depth = 0.2 }
end

function Fighters.new(info, index, parent)
	local def = CardData.Cards[info.id]
	local model, size
	if info.kind == "spell" then
		model, size = buildSpellCard(def)
	else
		model = CreatureBuilder.build(info.id)
		size = CreatureBuilder.info(info.id)
	end
	if not model then
		model, size = buildSpellCard(def)
	end
	model.Name = "Fighter_" .. index .. "_" .. info.id
	local self = setmetatable({}, Fighter)
	self.info = info
	self.index = index
	self.model = model
	self.height = (size and size.height or 2.5) * S
	self.depth = (size and size.depth or 1.5) * S
	self.parts = {}
	local root = model.PrimaryPart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			-- offsets were built around a root at the origin
			table.insert(self.parts, { part = d, offset = d.CFrame, size = d.Size })
		end
	end
	if root then
		root.Transparency = 1
	end
	-- ink outline (the cel-shaded look)
	self.outline = make("Highlight", {
		Name = "Ink",
		Adornee = model,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		FillTransparency = 1,
		OutlineColor = rgb(18, 12, 24),
		OutlineTransparency = 0,
	}, model)
	self.pos = Kit.ORIGIN + Vector3.new(0, -60, 0) -- hidden below until it enters
	self.yaw = 0
	self.visible = false
	self.state = "waiting" -- waiting, in, down, gone
	self.motion = nil
	self.squash = Vector3.new(1, 1, 1)
	self.squashT0, self.squashT1, self.squashFrom = 0, 0, Vector3.new(1, 1, 1)
	self.spin = nil -- { t0, t1, turns, axis = "yaw" | "tumble" }
	self.extraY = 0
	self.extraYaw = 0
	self.lean = 0
	self.phase = index * 1.7
	self.lastSize = nil
	self.lookAt = nil
	model.Parent = parent
	self:render(0)
	return self
end

-- A squash (or stretch) that springs back to normal over dur seconds.
function Fighter:poke(sx, sy, sz, now, dur)
	self.squashFrom = Vector3.new(sx, sy, sz)
	self.squashT0 = now
	self.squashT1 = now + (dur or 0.18)
end

-- motion = { t0, t1, from, to (Vector3 world), arc, style, endState, faceTravel, ease }
function Fighter:setMotion(m)
	self.motion = m
	if m.endState then
		self.pendingState = m.endState
	end
end

local function evalMotion(m, now)
	local a = math.clamp((now - m.t0) / math.max(m.t1 - m.t0, 1e-3), 0, 1)
	local e = (m.ease or Kit.inOutQuad)(a)
	local p = m.from:Lerp(m.to, e)
	local arc = (m.arc or 0) * 4 * a * (1 - a)
	return p + Vector3.new(0, arc, 0), a
end

function Fighter:render(now)
	local pos, yaw = self.pos, self.yaw
	local pitch, roll = 0, 0
	if self.motion then
		local m = self.motion
		if now >= m.t0 then
			local p, a = evalMotion(m, now)
			if m.faceTravel and (m.to - m.from).Magnitude > 0.2 then
				local d = m.to - m.from
				yaw = math.atan2(-d.X, -d.Z)
				if m.backwards then
					yaw += math.pi
				end
			end
			self.lean = m.lean or 0
			pos = p
			if a >= 1 then
				self.pos = m.to
				self.motion = nil
				self.lean = 0
				if self.pendingState then
					self.state = self.pendingState
					self.pendingState = nil
				end
				if m.onLand then
					m.onLand(self)
				end
			end
		end
		self.yaw = yaw
	elseif self.lookAt then
		local d = self.lookAt - pos
		if d.Magnitude > 0.1 then
			local target = math.atan2(-d.X, -d.Z)
			local diff = (target - self.yaw + math.pi) % (2 * math.pi) - math.pi
			self.yaw += diff * 0.25
		end
		yaw = self.yaw
	end
	-- spins (knockbacks, tumbles, head spins)
	if self.spin and now >= self.spin.t0 then
		local a = math.clamp((now - self.spin.t0) / (self.spin.t1 - self.spin.t0), 0, 1)
		local ang = Kit.outQuad(a) * self.spin.turns * math.pi * 2
		if self.spin.axis == "tumble" then
			pitch += ang
		else
			yaw += ang
		end
		if a >= 1 then
			self.spin = nil
		end
	end
	-- lying down after a knockout
	local lift = 0
	if self.state == "down" and not self.motion then
		pitch += math.rad(-80)
		lift = self.depth * 0.45
	end
	-- breathing / fighting stance
	local idleY, breathe = 0, 1
	if self.state == "in" and not self.motion then
		idleY = math.abs(math.sin(now * 5 + self.phase)) * 0.18
		breathe = 1 + 0.035 * math.sin(now * 9 + self.phase)
	end
	-- squash spring
	local sq = Vector3.new(1, breathe, 1)
	if now < self.squashT1 then
		local a = (now - self.squashT0) / (self.squashT1 - self.squashT0)
		local wob = math.cos(a * math.pi * 1.5) * (1 - a)
		sq = Vector3.new(1, 1, 1) + (self.squashFrom - Vector3.new(1, 1, 1)) * wob
		sq = Vector3.new(sq.X, sq.Y * breathe, sq.Z)
	end
	if self.squashOverride then
		sq = self.squashOverride
	end
	local rootCf = CFrame.new(pos + Vector3.new(0, idleY + self.extraY + lift, 0))
		* CFrame.Angles(0, yaw + self.extraYaw, 0)
		* CFrame.Angles(pitch + math.rad(self.lean), 0, roll)
	local sizeChanged = self.lastSize == nil or (self.lastSize - sq).Magnitude > 1e-4
	for _, e in ipairs(self.parts) do
		local o = e.offset
		local p = o.Position
		local scaled = Vector3.new(p.X * S * sq.X, p.Y * S * sq.Y, p.Z * S * sq.Z)
		e.part.CFrame = rootCf * CFrame.new(scaled) * o.Rotation
		if sizeChanged then
			-- scale the part along the model's axes (close enough for small squashes)
			local r = o.Rotation
			local rx, ry, rz = r.RightVector, r.UpVector, -r.LookVector
			local function axisScale(ax)
				return math.sqrt((ax.X * sq.X) ^ 2 + (ax.Y * sq.Y) ^ 2 + (ax.Z * sq.Z) ^ 2)
			end
			e.part.Size = Vector3.new(e.size.X * S * axisScale(rx), e.size.Y * S * axisScale(ry), e.size.Z * S * axisScale(rz))
		end
	end
	self.lastSize = sq
	self.renderPos = pos
end

-- Where its chest is (for camera aim and effects).
function Fighter:center()
	return (self.renderPos or self.pos) + Vector3.new(0, self.height * 0.55 + self.extraY, 0)
end

function Fighter:hide()
	self.state = "gone"
	self.pos = Kit.ORIGIN + Vector3.new(0, -60, 0)
	self.motion = nil
end

function Fighter:destroy()
	self.model:Destroy()
end

Fighters.Fighter = Fighter
return Fighters

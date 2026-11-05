-- Fighters in the Brawl Box: the game's own creature models, moved by hand every frame so the
-- Director's clock (hit-stop, slow motion, fast-forward, skip) controls everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent:WaitForChild("Kit"))
local DeckWars = ReplicatedStorage:WaitForChild("DeckWars")
local CreatureBuilder = require(DeckWars:WaitForChild("CreatureBuilder"))
local CardData = require(DeckWars:WaitForChild("CardData"))
local Rig = require(script.Parent:WaitForChild("Rig"))
local Moves = require(script.Parent:WaitForChild("Moves"))

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
	make("TextLabel", { Size = UDim2.fromScale(0.9, 0.4), Position = UDim2.fromScale(0.05, 0.35), BackgroundTransparency = 1, Text = "★", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = Kit.TierColor[def.rarity] or fam }, g)
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
			table.insert(self.parts, { part = d, offset = d.CFrame, size = d.Size, bone = "body" })
		end
	end
	-- moving parts (arms, legs, head...) for the fighting animations
	self.rig = info.kind ~= "spell" and Rig.get(info.id) or nil
	if self.rig then
		self:bindRig()
	end
	self.anim = nil
	self.loopAnim = nil
	self.swings = 0
	self.leadSide = (self.rig and self.rig.weaponSide == -1) and "L" or "R"
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
	-- lying down after a knockout: flat on its back, the way the hit sent it
	local lift = 0
	if self.state == "down" and not self.motion then
		pitch += math.rad(self.rig and 80 or -80)
		lift = self.depth * 0.45
	end
	-- breathing / fighting stance
	local idleY, breathe = 0, 1
	if self.state == "in" and not self.motion then
		if self.rig then
			-- the rig bounces on its toes instead (Moves.stance)
			breathe = 1 + 0.02 * math.sin(now * 9 + self.phase)
		else
			idleY = math.abs(math.sin(now * 5 + self.phase)) * 0.18
			breathe = 1 + 0.035 * math.sin(now * 9 + self.phase)
		end
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
	local boneCf = self.rig and self:poseBones(now) or nil
	for _, e in ipairs(self.parts) do
		local o = e.offset
		if boneCf then
			local b = boneCf[e.bone]
			if b then
				o = b * o
			end
		end
		local p = o.Position
		local scaled = Vector3.new(p.X * S * sq.X, p.Y * S * sq.Y, p.Z * S * sq.Z)
		e.part.CFrame = rootCf * CFrame.new(scaled) * o.Rotation
		if sizeChanged then
			-- scale the part along the model's axes (close enough for small squashes)
			local r = e.offset.Rotation
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

---------------------------------------------------------------------------
-- Fighting animations (Rig + Moves)
---------------------------------------------------------------------------
-- Matches each built part to its entry in the model data, so it knows which bone moves it.
function Fighter:bindRig()
	local rig = self.rig
	local used = {}
	for _, e in ipairs(self.parts) do
		local pos = e.offset.Position
		local best, bd = nil, math.huge
		for i, rp in ipairs(rig.parts) do
			if not used[i] and rp.name == e.part.Name then
				local d = (pos.X - rp.pos[1]) ^ 2 + (pos.Y - rp.pos[2]) ^ 2 + (pos.Z - rp.pos[3]) ^ 2
				if d < bd then
					best, bd = i, d
				end
			end
		end
		if best then
			used[best] = true
			e.bone = rig.partBone[best] or "body"
		end
	end
end

-- Plays a move by name from `at` (defaults to now). opts: lead = "L" | "R", loop = true,
-- speed = playback rate. A move that is already playing is replaced.
function Fighter:play(name, at, opts)
	if not self.rig then
		return
	end
	local m = Moves.get(name)
	if not m then
		return
	end
	opts = opts or {}
	local a = { move = m, name = name, t0 = at, lead = opts.lead or self.leadSide, speed = opts.speed or 1 }
	if m.loop or opts.loop then
		self.loopAnim = a
		self.anim = nil
	elseif opts.queue then
		-- starts at `at`, letting whatever is playing now carry on until then
		self.nextAnim = a
	else
		self.anim = a
		self.nextAnim = nil
	end
end

function Fighter:stopLoop()
	self.loopAnim = nil
end

-- Starts an attack so that it lands at contactT (or starts now when contactT is nil).
-- Returns the move's name.
function Fighter:swing(power, now, sig, contactT)
	if not self.rig then
		return nil
	end
	self.swings += 1
	local name = Moves.pickAttack(self.rig, power, self.swings, self.info.id, sig)
	-- alternate hands on light punches so a flurry looks like a flurry
	local lead = self.leadSide
	if power == 1 and (name == "jab" or name == "cross") and self.rig.has.bothArms and not self.rig.has.weapon then
		lead = (self.swings % 2 == 0) and "L" or "R"
	end
	local m = Moves.get(name)
	local at = now
	if contactT and m and m.contact then
		at = contactT - m.contact
	end
	-- a move with a longer wind-up than planned simply starts part-way through it
	self:play(name, math.min(at, now + 0.5), { lead = lead, queue = at > now })
	return name
end

local function evalAnim(a, now)
	local m = a.move
	local t = (now - a.t0) * a.speed
	if t < 0 then
		return nil, 0, t
	end
	if not m.loop and t >= m.dur then
		return nil, 0, t
	end
	local pose = Moves.sample(m, t)
	-- fade in and out so moves never pop
	local w = 1
	if not m.loop then
		w = math.min(1, t / 0.04, (m.dur - t) / 0.08 + 0.0001)
		w = math.clamp(w, 0, 1)
	end
	return pose, w, t
end

-- Builds this frame's pose and turns it into one CFrame per bone (model space).
function Fighter:poseBones(now)
	local rig = self.rig
	local base
	local st = self.state
	if st == "down" and not self.motion then
		base = Moves.limp(now, self.phase)
		self.loopAnim = nil
		self.anim = nil
		self.nextAnim = nil
	elseif self.motion and now >= self.motion.t0 and (st == "in" or st == "entering") then
		local m = self.motion
		local dist = (m.to - m.from).Magnitude
		local speed = dist / math.max(m.t1 - m.t0, 0.05) / 12
		if dist > 0.5 and (m.arc or 0) < 1.5 then
			base = Moves.run(now, self.phase, speed, rig)
		else
			base = Moves.stance(now, self.phase, rig)
		end
	else
		base = Moves.stance(now, self.phase, rig)
	end
	if self.nextAnim and now >= self.nextAnim.t0 then
		self.anim = self.nextAnim
		self.nextAnim = nil
	end
	local pose = base
	local lead = self.leadSide
	if self.loopAnim then
		local p, w = evalAnim(self.loopAnim, now)
		if p then
			pose = Moves.blend(pose, p, w)
			lead = self.loopAnim.lead
		end
	end
	local head2
	if self.anim then
		local p, w, t = evalAnim(self.anim, now)
		if p then
			pose = Moves.blend(pose, p, w)
			lead = self.anim.lead
			local stagger = self.anim.move.headStagger
			if stagger and rig.has.heads > 1 then
				head2 = {}
				for n = 2, rig.has.heads do
					local tt = t - stagger * (n - 1)
					head2[n] = tt > 0 and Moves.sample(self.anim.move, tt).head or base.head
				end
			end
		elseif t >= 0 then
			self.anim = nil
		end
	end
	pose = table.clone(pose)
	pose.leadSide = lead
	if head2 then
		pose.headLag = head2
	end
	local solved = Rig.solve(rig, pose)
	local out = {}
	for name, tf in pairs(solved) do
		local m, t = tf.m, tf.t
		out[name] = CFrame.new(t[1], t[2], t[3], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9])
	end
	return out
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

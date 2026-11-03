-- Pack Brawl effects: 3D (sparks, shockwaves, dust, comic words, beams, props) and screen
-- (flashes, impact lines, cracks, blackout, freeze frames, wipes). Every effect is animated by
-- the Director's clock through Fx:anim, so freezing, slow motion and skipping stay in sync,
-- and everything lives under one folder and one ScreenGui, so cleanup is a single Destroy.

local Kit = require(script.Parent:WaitForChild("Kit"))
local rgb, make, part = Kit.rgb, Kit.make, Kit.part

local Fx = {}
Fx.__index = Fx

local WHITE, BLACK = rgb(255, 255, 255), rgb(0, 0, 0)

function Fx.new(folder, gui)
	local self = setmetatable({}, Fx)
	self.folder = folder
	self.gui = gui
	self.anims = {}
	self.now = 0
	self.emitters = {}
	self.quiet = false -- true while skipping: no new particles or screen effects
	-- full-screen layers, bottom to top
	self.flashFrame = make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20 }, gui)
	self.black = make("Frame", { Name = "Black", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 30 }, gui)
	self.linesFrame = make("Frame", { Name = "Lines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 15, Visible = false }, gui)
	for k = 0, 23 do
		local holder = make("Frame", { Size = UDim2.fromScale(0, 0), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Rotation = k * 15 + (k % 2) * 4 }, self.linesFrame)
		make("Frame", {
			Size = UDim2.new(0, 900, 0, (k % 3 == 0) and 7 or 3),
			Position = UDim2.fromOffset(170 + (k % 4) * 40, 0),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, holder)
	end
	return self
end

-- fn(a) is called every frame with a from 0 to 1 over dur seconds (starting now).
function Fx:anim(dur, fn, onDone)
	table.insert(self.anims, { t0 = self.now, t1 = self.now + dur, fn = fn, onDone = onDone })
end

function Fx:update(now)
	self.now = now
	for i = #self.anims, 1, -1 do
		local a = self.anims[i]
		local x = math.clamp((now - a.t0) / math.max(a.t1 - a.t0, 1e-3), 0, 1)
		a.fn(x)
		if x >= 1 then
			table.remove(self.anims, i)
			if a.onDone then
				a.onDone()
			end
		end
	end
end

-- Freezes or unfreezes every particle in the scene (time stop, freeze cuts).
function Fx:setParticleTime(scale)
	for _, d in ipairs(self.folder:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.TimeScale = scale
		end
	end
end

---------------------------------------------------------------------------
-- 3D
---------------------------------------------------------------------------
local function emitterAt(self, pos, props, n, life)
	if self.quiet then
		return
	end
	local holder = part({ Name = "FxEmitter", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos), Transparency = 1 }, self.folder)
	local e = make("ParticleEmitter", props, holder)
	e.Enabled = false
	e:Emit(n)
	self:anim(life or 1.5, function() end, function()
		holder:Destroy()
	end)
	return e
end

function Fx:sparks(pos, color, n)
	emitterAt(self, pos, {
		Texture = Kit.TEX_SPARK,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(20, 40),
		Lifetime = NumberRange.new(0.18, 0.3),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
	}, n or 16, 0.6)
end

function Fx:dust(pos, n)
	emitterAt(self, pos, {
		Texture = Kit.TEX_SMOKE,
		Color = ColorSequence.new(rgb(200, 190, 180)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.6) }),
		Speed = NumberRange.new(4, 8),
		Lifetime = NumberRange.new(0.4, 0.6),
		SpreadAngle = Vector2.new(80, 10),
		Drag = 4,
		Acceleration = Vector3.new(0, 2, 0),
	}, n or 8, 0.8)
end

function Fx:confetti(pos, n, colors)
	emitterAt(self, pos, {
		Texture = Kit.TEX_SPARK,
		Color = colors or ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, rgb(255, 220, 60)),
			ColorSequenceKeypoint.new(0.5, rgb(90, 220, 120)),
			ColorSequenceKeypoint.new(0.75, rgb(80, 160, 255)),
			ColorSequenceKeypoint.new(1, rgb(230, 90, 255)),
		}),
		Size = NumberSequence.new(0.35),
		Speed = NumberRange.new(14, 24),
		Lifetime = NumberRange.new(1.5, 2.5),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -14, 0),
		Drag = 1.2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
		EmissionDirection = Enum.NormalId.Top,
	}, n or 60, 3)
end

-- A flat glowing ring that grows and fades.
function Fx:shock(pos, color, size)
	if self.quiet then
		return
	end
	local ring = part({ Name = "Shock", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = color, Size = Vector3.new(0.15, 1, 1), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.1 }, self.folder)
	local base = ring.CFrame
	self:anim(0.38, function(a)
		local d = 1 + (size - 1) * Kit.outCubic(a)
		ring.Size = Vector3.new(0.15, d, d)
		ring.CFrame = base
		ring.Transparency = 0.1 + 0.9 * a
	end, function()
		ring:Destroy()
	end)
end

-- A comic word that pops in with overshoot and fades.
function Fx:word(pos, text, color)
	if self.quiet then
		return
	end
	local holder = part({ Name = "Word", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos), Transparency = 1 }, self.folder)
	local bb = make("BillboardGui", { Size = UDim2.fromOffset(260, 120), AlwaysOnTop = true, LightInfluence = 0, StudsOffset = Vector3.new(0, 1.5, 0) }, holder)
	local star = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bb)
	local scale = make("UIScale", { Scale = 0.2 }, star)
	local lbl = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = color or rgb(255, 230, 80),
		Rotation = -8,
	}, star)
	make("UIStroke", { Thickness = 4, Color = rgb(20, 12, 30) }, lbl)
	self:anim(0.6, function(a)
		scale.Scale = 0.2 + 0.9 * Kit.outBack(math.min(a * 3, 1))
		lbl.TextTransparency = a > 0.7 and (a - 0.7) / 0.3 or 0
		holder.CFrame = CFrame.new(pos + Vector3.new(0, a * 1.2, 0))
	end, function()
		holder:Destroy()
	end)
end

-- A dot on the floor that grows (something is about to land there).
function Fx:marker(pos, color, dur)
	local dot = part({ Name = "Marker", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = color, Size = Vector3.new(0.05, 0.4, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.3 }, self.folder)
	self:anim(dur, function(a)
		local d = 0.4 + 5 * a
		dot.Size = Vector3.new(0.05, d, d)
	end, function()
		dot:Destroy()
	end)
end

-- Two beams meeting in a crackling ball. Returns a handle with :update(now, frozen) and :stop().
function Fx:beam(fromA, fromB, mid, colorA, colorB)
	local beamA = part({ Name = "BeamA", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = colorA, Size = Vector3.new(1, 0.8, 0.8) }, self.folder)
	local beamB = part({ Name = "BeamB", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = colorB, Size = Vector3.new(1, 0.8, 0.8) }, self.folder)
	local ball = part({ Name = "ClashBall", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = WHITE, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(mid) }, self.folder)
	local light = make("PointLight", { Range = 18, Brightness = 4, Color = colorA:Lerp(colorB, 0.5) }, ball)
	local h = { t0 = self.now, frozenAt = nil }
	local function stretch(p, a, b, width)
		local d = (b - a)
		local len = math.max(d.Magnitude, 0.1)
		p.Size = Vector3.new(len, width, width)
		p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	end
	function h.update(_, now, frozen, a, b)
		local t = frozen and (h.frozenAt or now) or now
		if frozen and not h.frozenAt then
			h.frozenAt = now
		elseif not frozen then
			h.frozenAt = nil
		end
		local el = t - h.t0
		local grow = math.min(el / 0.4, 1)
		stretch(beamA, a or fromA, mid:Lerp(a or fromA, 1 - grow), 0.7 + 0.25 * math.sin(el * 40))
		stretch(beamB, b or fromB, mid:Lerp(b or fromB, 1 - grow), 0.7 + 0.25 * math.sin(el * 37 + 1))
		local s = (1.2 + el * 1.4) * (1 + 0.15 * math.sin(el * 55))
		ball.Size = Vector3.new(s, s, s)
		ball.CFrame = CFrame.new(mid)
		ball.Color = (math.floor(el * 20) % 2 == 0) and WHITE or colorA:Lerp(colorB, 0.5)
		light.Brightness = 3 + 2 * math.sin(el * 30)
	end
	function h.stop()
		beamA:Destroy()
		beamB:Destroy()
		ball:Destroy()
	end
	return h
end

-- A big energy explosion.
function Fx:detonate(pos, color)
	if self.quiet then
		return
	end
	local ball = part({ Name = "Boom", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = color, Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(pos) }, self.folder)
	self:anim(0.5, function(a)
		local s = 2 + 26 * Kit.outCubic(a)
		ball.Size = Vector3.new(s, s, s)
		ball.Transparency = a
	end, function()
		ball:Destroy()
	end)
	self:shock(pos - Vector3.new(0, pos.Y - Kit.ORIGIN.Y - 0.1, 0), color, 40)
	self:sparks(pos, color, 50)
end

-- A tornado of stacked spinning rings around a point. Returns a handle with :stop().
function Fx:tornado(getCenter, dur)
	local rings = {}
	for k = 1, 7 do
		local d = 2 + k * 1.1
		table.insert(rings, part({ Name = "Twister", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = rgb(210, 225, 240), Transparency = 0.55, Size = Vector3.new(0.4, d, d) }, self.folder))
	end
	self:anim(dur, function(a)
		local c = getCenter()
		for k, r in ipairs(rings) do
			r.CFrame = CFrame.new(c + Vector3.new(math.sin(self.now * 6 + k) * 0.4, k * 1.3 - 0.5, 0)) * CFrame.Angles(0, self.now * 8 + k, math.rad(90))
			r.Transparency = 0.55 + 0.45 * math.max(0, (a - 0.8) / 0.2)
		end
	end, function()
		for _, r in ipairs(rings) do
			r:Destroy()
		end
	end)
end

-- The golden card that descends from the sky (Legendary).
function Fx:bigCard(pos, color, dur)
	local card = part({ Name = "BigCard", Size = Vector3.new(9, 12.5, 0.3), Color = color, Material = Enum.Material.Neon, Transparency = 0.2 }, self.folder)
	local back = part({ Name = "BigCardFace", Size = Vector3.new(8, 11.5, 0.32), Color = rgb(40, 30, 70) }, self.folder)
	local g = make("SurfaceGui", { Face = Enum.NormalId.Front, LightInfluence = 0, CanvasSize = Vector2.new(400, 560) }, back)
	make("TextLabel", { Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.35), BackgroundTransparency = 1, Text = "✦", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = color }, g)
	local light = make("PointLight", { Range = 30, Brightness = 5, Color = color }, card)
	self:anim(dur, function(a)
		local y = 30 * (1 - Kit.outCubic(a)) + 6.5
		local cf = CFrame.new(pos + Vector3.new(0, y, -0.5)) * CFrame.Angles(0, math.rad(360 * (1 - Kit.outCubic(a))), 0)
		card.CFrame = cf
		back.CFrame = cf
	end)
	-- after it lands it bursts into light when the winner steps out
	self:anim(dur + 0.9, function(a)
		if a > 0.66 then
			local f = (a - 0.66) / 0.34
			card.Transparency = 0.2 + 0.8 * f
			back.Transparency = f
			light.Brightness = 5 * (1 - f)
		end
	end, function()
		card:Destroy()
		back:Destroy()
	end)
end

-- Knocked-out fighters twinkle in the sky as little stars.
function Fx:stars(positions)
	for k, p in ipairs(positions) do
		local s = part({ Name = "Star", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = rgb(255, 245, 200), Size = Vector3.new(0.6, 0.6, 0.6), CFrame = CFrame.new(p) }, self.folder)
		self:anim(2.5, function(a)
			local tw = 0.5 + 0.5 * math.sin(a * 30 + k)
			local sz = 0.3 + 0.9 * tw * (a < 0.15 and a / 0.15 or 1)
			s.Size = Vector3.new(sz, sz, sz)
		end, function()
			s:Destroy()
		end)
	end
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------
function Fx:flash(color, dur, strength)
	if self.quiet then
		return
	end
	local f = self.flashFrame
	f.BackgroundColor3 = color
	self:anim(dur, function(a)
		f.BackgroundTransparency = 1 - (strength or 0.85) * (1 - a)
	end, function()
		f.BackgroundTransparency = 1
	end)
end

-- Anime impact lines for 3 frames.
function Fx:lines()
	if self.quiet then
		return
	end
	self.linesFrame.Visible = true
	self.linesFrame.Rotation = math.random(0, 14)
	self:anim(0.1, function() end, function()
		self.linesFrame.Visible = false
	end)
end

-- Total blackout for dur seconds (fades back out at the end).
function Fx:blackout(dur)
	local b = self.black
	b.BackgroundTransparency = 0
	self:anim(dur, function() end, function()
		b.BackgroundTransparency = 1
	end)
end

-- A jagged crack that spreads across the screen.
function Fx:crack(dur)
	local holder = make("Frame", { Name = "Crack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 25 }, self.gui)
	local segs = {}
	local x, y = 0.08, 0.35
	for k = 1, 14 do
		local nx, ny = x + 0.065, y + ((k % 2 == 0) and 0.06 or -0.04) + (k % 3) * 0.015
		local dx, dy = (nx - x) * 1280, (ny - y) * 720
		local len = math.sqrt(dx * dx + dy * dy)
		local seg = make("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromOffset(0, 5),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 26,
		}, holder)
		make("UIStroke", { Thickness = 2, Color = BLACK }, seg)
		table.insert(segs, { seg = seg, len = len })
		x, y = nx, ny
	end
	self:anim(dur, function(a)
		local shown = a * #segs
		for k, s in ipairs(segs) do
			local f = math.clamp(shown - (k - 1), 0, 1)
			s.seg.Size = UDim2.fromOffset(s.len * f, 5)
		end
	end)
	self.crackHolder = holder
end

function Fx:clearCrack()
	if self.crackHolder then
		self.crackHolder:Destroy()
		self.crackHolder = nil
	end
end

-- Two prismatic eyes open in the dark.
function Fx:eyes(dur)
	local holder = make("Frame", { Name = "Eyes", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 31 }, self.gui)
	local eyes = {}
	for k, x in ipairs({ 0.42, 0.58 }) do
		local e = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.45), Size = UDim2.fromOffset(70, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 32 }, holder)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, e)
		local grad = make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 80, 200)), ColorSequenceKeypoint.new(0.5, rgb(120, 220, 255)), ColorSequenceKeypoint.new(1, rgb(255, 240, 120)) }) }, e)
		eyes[k] = { e = e, grad = grad }
	end
	self:anim(dur, function(a)
		for _, eye in ipairs(eyes) do
			eye.e.Size = UDim2.fromOffset(70, 26 * Kit.outBack(math.min(a * 2.5, 1)))
			eye.grad.Rotation = a * 360
		end
	end, function()
		holder:Destroy()
	end)
end

-- Blinding white that holds, then eases out.
function Fx:whiteFlash(dur)
	local f = self.flashFrame
	f.BackgroundColor3 = WHITE
	f.BackgroundTransparency = 0
	self.black.BackgroundTransparency = 1
	self:anim(dur, function(a)
		f.BackgroundTransparency = Kit.inQuad(a)
	end, function()
		f.BackgroundTransparency = 1
	end)
end

-- Freeze-frame dressing: an ink border and a diagonal slash.
function Fx:freezeFrame(index, color)
	if self.freezeHolder then
		self.freezeHolder:Destroy()
	end
	local holder = make("Frame", { Name = "Freeze", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 18 }, self.gui)
	make("UIStroke", { Thickness = 18, Color = BLACK }, make("Frame", { Size = UDim2.new(1, -18, 1, -18), Position = UDim2.fromOffset(9, 9), BackgroundTransparency = 1, ZIndex = 18 }, holder))
	local slash = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.6, 0, 0, 14), Rotation = ({ -18, 12, -30 })[index] or -18, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 19, BackgroundTransparency = 0.15 }, holder)
	local _ = slash
	self.freezeHolder = holder
end

function Fx:clearFreeze()
	if self.freezeHolder then
		self.freezeHolder:Destroy()
		self.freezeHolder = nil
	end
end

-- Iris wipe: a circle of the tier color grows from a screen point until it covers everything.
function Fx:wipe(color, screenPos, dur, rainbow)
	local circle = make("Frame", {
		Name = "Wipe",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(screenPos.X, screenPos.Y),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 40,
	}, self.gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, circle)
	local grad
	if rainbow then
		grad = make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 80, 80)), ColorSequenceKeypoint.new(0.33, rgb(255, 230, 80)), ColorSequenceKeypoint.new(0.66, rgb(80, 220, 255)), ColorSequenceKeypoint.new(1, rgb(220, 90, 255)) }) }, circle)
	end
	self:anim(dur, function(a)
		local d = 3200 * Kit.inQuad(a)
		circle.Size = UDim2.fromOffset(d, d)
		if grad then
			grad.Rotation = a * 180
		end
	end)
	self.wipeFrame = circle
end

-- The fake ending: a card frame starts to slide up, then cracks and falls away.
function Fx:fakeFrame()
	local frame = make("Frame", { Name = "FakeFrame", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1.4), Size = UDim2.fromOffset(300, 420), BackgroundTransparency = 1, ZIndex = 22 }, self.gui)
	make("UIStroke", { Thickness = 10, Color = Kit.TierColor.Rare }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, frame)
	self.fake = frame
	self:anim(0.5, function(a)
		frame.Position = UDim2.fromScale(0.5, 1.4 - 0.75 * Kit.outCubic(a))
	end)
end

function Fx:fakeCrack()
	local frame = self.fake
	if not frame then
		return
	end
	self.fake = nil
	local start = frame.Position
	self:anim(0.6, function(a)
		frame.Rotation = 25 * a
		frame.Position = UDim2.new(start.X.Scale, 0, start.Y.Scale + 1.2 * a * a, 0)
	end, function()
		frame:Destroy()
	end)
	self:flash(WHITE, 0.12, 0.9)
end

-- "Hold to speed up / Skip" hint.
function Fx:skipButton(onSkip)
	local b = make("TextButton", {
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20),
		Size = UDim2.fromOffset(120, 44),
		BackgroundColor3 = rgb(20, 16, 30),
		BackgroundTransparency = 0.3,
		Text = "SKIP ▶▶",
		Font = Enum.Font.FredokaOne,
		TextSize = 22,
		TextColor3 = WHITE,
		ZIndex = 50,
		Visible = false,
	}, self.gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
	b.Activated:Connect(onSkip)
	make("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 70),
		Size = UDim2.fromOffset(240, 24),
		BackgroundTransparency = 1,
		Text = "Hold to speed up",
		Font = Enum.Font.FredokaOne,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = rgb(220, 215, 235),
		TextTransparency = 0.3,
		ZIndex = 50,
		Visible = false,
	}, self.gui)
	return b
end

return Fx

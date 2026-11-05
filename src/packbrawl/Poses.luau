-- Victory poses (one per family, plus the two Secrets, buildings and spells) and the family
-- ultimates used by Legendary and Secret pulls. Built from simple parts, animated with Fx:anim.

local Kit = require(script.Parent:WaitForChild("Kit"))
local rgb, make, part = Kit.rgb, Kit.make, Kit.part

local Poses = {}

local function prop(d, props)
	return part(props, d.folder)
end

-- Moves the defeated fighters that are still in the ring into a pile behind the winner.
local function gatherLosers(d, cue, spots)
	local w = d:fighter(cue.who)
	local base = w.pos
	local list = {}
	for _, i in ipairs(cue.losers or {}) do
		local f = d:fighter(i)
		local p = f.pos - Kit.ORIGIN
		if f.state ~= "gone" and math.abs(p.X) < 11 and math.abs(p.Z) < 11 and p.Y > -1 then
			table.insert(list, f)
		end
	end
	for k, f in ipairs(list) do
		local off = spots and spots(k, #list) or Vector3.new(((k - 1) % 3 - 1) * 1.6, 0, -1.6 - math.floor((k - 1) / 3) * 1.4)
		f:setMotion({ t0 = d.now, t1 = d.now + 0.35, from = f.pos, to = base + off, arc = 1.5, ease = Kit.inOutQuad, endState = "down" })
		f.state = "down"
		f.spin = nil
	end
	return list
end

local function faceCamera(d, f)
	f.lookAt = f.pos + Vector3.new(0, 0, 20)
end

local function stomp(d, f, strength)
	f:poke(1.3, 0.7, 1.3, d.now, 0.22)
	d.fx:dust(f.pos + Vector3.new(0, 0.3, 0), 6)
	d.cam:addTrauma(strength or 0.25)
	d.sfx:play("thud")
end

local function after(d, delay, fn)
	d.fx:anim(delay, function() end, fn)
end

---------------------------------------------------------------------------
-- Family poses. dur = seconds the pose has (about 1 s for Common, 1.5 to 4.5 s otherwise).
---------------------------------------------------------------------------
local POSE = {}

function POSE.Snack(d, cue, w, dur)
	local losers = gatherLosers(d, cue)
	faceCamera(d, w)
	if #losers > 0 then
		w:setMotion({ t0 = d.now, t1 = d.now + 0.3, from = w.pos, to = w.pos + Vector3.new(0, 0, -0.6), arc = 2.2 })
	end
	-- a fork bigger than the creature
	local fork = prop(d, { Name = "Fork", Size = Vector3.new(0.3, 4.5, 0.3), Color = rgb(215, 220, 230), Material = Enum.Material.Metal, Reflectance = 0.3 })
	local tines = {}
	for k = -1, 1 do
		table.insert(tines, prop(d, { Name = "Tine", Size = Vector3.new(0.18, 1.3, 0.18), Color = rgb(215, 220, 230), Material = Enum.Material.Metal }))
	end
	d.fx:anim(dur, function(a)
		local up = Kit.outBack(math.clamp((a - 0.1) / 0.2, 0, 1))
		local c = w:center() + Vector3.new(1.6, -3 + 4 * up, 0.3)
		fork.CFrame = CFrame.new(c) * CFrame.Angles(0, 0, math.rad(-10))
		for k, tine in ipairs(tines) do
			tine.CFrame = CFrame.new(c) * CFrame.Angles(0, 0, math.rad(-10)) * CFrame.new((k - 2) * 0.35, 2.7, 0)
		end
	end)
	-- sprinkles like seasoning, twice
	for k, at in ipairs({ 0.3, 0.5 }) do
		after(d, dur * at, function()
			d.fx:confetti(w:center() + Vector3.new(0, 2.5, -1.5), 30, ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 120, 180)), ColorSequenceKeypoint.new(0.5, rgb(120, 220, 255)), ColorSequenceKeypoint.new(1, rgb(255, 240, 120)) }))
			local _ = k
		end)
	end
	after(d, dur * 0.75, function()
		w:poke(0.85, 1.3, 0.85, d.now, 0.3)
		d.fx:sparks(w:center() + Vector3.new(0, 1, 0.8), rgb(255, 120, 180), 24)
		d.fx:word(w:center() + Vector3.new(0, 1.5, 0), "MWAH!", rgb(255, 140, 190))
		d.sfx:play("pop")
	end)
end

function POSE.Junk(d, cue, w, dur)
	-- the losers stack themselves into a heap; the winner climbs on top
	local losers = gatherLosers(d, cue, function(k)
		return Vector3.new(((k % 2) - 0.5) * 0.8, 0, -0.2)
	end)
	faceCamera(d, w)
	local heap = 0
	for k, f in ipairs(losers) do
		f.extraY = (k - 1) * f.depth * 0.8
		heap = math.max(heap, (k - 1) * f.depth * 0.8 + f.depth)
	end
	d.fx:anim(0.4, function(a)
		w.extraY = heap * Kit.outBack(a)
	end)
	local pole = prop(d, { Name = "FlagPole", Size = Vector3.new(0.2, 4, 0.2), Color = rgb(150, 150, 160), Material = Enum.Material.Metal })
	local sign = prop(d, { Name = "StreetSign", Size = Vector3.new(2.2, 0.9, 0.1), Color = rgb(40, 150, 70) })
	local g = make("SurfaceGui", { Face = Enum.NormalId.Front, CanvasSize = Vector2.new(220, 90) }, sign)
	make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "MINE ST", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 255, 255) }, g)
	local cans = {}
	for k = 1, 3 do
		cans[k] = prop(d, { Name = "TinCan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 0.6, 0.6), Color = rgb(190, 195, 205), Material = Enum.Material.Metal })
	end
	local plant = 0.35
	d.fx:anim(dur, function(a)
		local base = w.pos + Vector3.new(-1.3, heap, 0)
		local drop = math.clamp((a * dur - plant) / 0.15, 0, 1)
		local tilt = math.rad(12)
		pole.CFrame = CFrame.new(base + Vector3.new(0, 2 + 3 * (1 - drop), 0)) * CFrame.Angles(0, 0, tilt)
		sign.CFrame = pole.CFrame * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(-20))
		for k, can in ipairs(cans) do
			local s = math.clamp((a * dur - plant - 0.2 - k * 0.25) / 0.6, 0, 1)
			local p = w.pos + Vector3.new(0.6 + 3 * s, math.max(0.3, heap * (1 - s) + 0.3), 0.5 + (k - 2) * 0.5)
			can.CFrame = CFrame.new(p) * CFrame.Angles(s * 12, 0, 0)
			can.Transparency = s <= 0 and 1 or 0
		end
	end)
	after(d, plant + 0.15, function()
		stomp(d, w, 0.2)
		d.fx:word(w:center() + Vector3.new(0, 2, 0), "KING!", Kit.FamilyColor.Junk:Lerp(rgb(255, 230, 120), 0.6))
	end)
end

local function rainbow(d, center, dur)
	local bands = { rgb(255, 80, 80), rgb(255, 170, 60), rgb(255, 240, 90), rgb(90, 220, 120), rgb(80, 160, 255) }
	local segs = {}
	for b, col in ipairs(bands) do
		local r = 7.5 - b * 0.55
		for k = 0, 10 do
			local s = prop(d, { Name = "Rainbow", Size = Vector3.new(0.55, 0.5, 2.3), Color = col, Material = Enum.Material.Neon, Transparency = 1 })
			table.insert(segs, { part = s, r = r, k = k })
		end
	end
	d.fx:anim(dur, function(a)
		local shown = math.clamp(a / 0.35, 0, 1) * 11
		-- keep the rainbow behind the winner from wherever the camera is (it orbits)
		local look = d.camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
		local frame = CFrame.lookAt(center + flat * 7, center + flat * 8)
		for _, e in ipairs(segs) do
			local ang = math.rad(e.k * 18)
			e.part.CFrame = frame * CFrame.new(math.cos(ang) * e.r, math.sin(ang) * e.r, 0) * CFrame.Angles(0, 0, ang) * CFrame.Angles(0, math.rad(90), 0)
			e.part.Transparency = (e.k < shown) and 0.15 or 1
		end
	end)
end

local function lightning(d, from, to, color)
	local pts = { from }
	for k = 1, 4 do
		local p = from:Lerp(to, k / 5) + Vector3.new(((k % 2) * 2 - 1) * 0.7, 0, 0)
		table.insert(pts, p)
	end
	table.insert(pts, to)
	local segs = {}
	for k = 1, #pts - 1 do
		local a, b = pts[k], pts[k + 1]
		local s = prop(d, { Name = "Bolt", Size = Vector3.new(0.25, 0.25, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color or rgb(255, 250, 170), Material = Enum.Material.Neon })
		table.insert(segs, s)
	end
	d.fx:anim(0.3, function(a)
		for _, s in ipairs(segs) do
			s.Transparency = a
		end
	end, function()
		for _, s in ipairs(segs) do
			s:Destroy()
		end
	end)
end

function POSE.Weather(d, cue, w, dur)
	gatherLosers(d, cue)
	faceCamera(d, w)
	local base = w.pos
	d.fx:anim(dur, function(a)
		w.extraY = 2 * Kit.outCubic(math.min(a / 0.3, 1)) + 0.2 * math.sin(a * dur * 4)
	end)
	rainbow(d, base + Vector3.new(0, 0, 0), dur)
	after(d, dur * 0.7, function()
		lightning(d, w:center() + Vector3.new(0.8, 0.5, 0.5), base + Vector3.new(0.8, 0, 0.8))
		d.fx:flash(rgb(255, 250, 200), 0.08, 0.5)
		d.fx:word(w:center() + Vector3.new(0, 1.8, 0), "*mic drop*", rgb(255, 250, 170))
		d.cam:addTrauma(0.3)
		d.sfx:play("boom", 0.4)
	end)
end

function POSE.Critter(d, cue, w, dur)
	gatherLosers(d, cue)
	local center = Kit.ORIGIN + Vector3.new(0, 0, -1)
	local start = w.pos
	local lap = math.min(dur * 0.45, 1.2)
	local r = 5.5
	local a0 = math.atan2((start - center).Z, (start - center).X)
	w.lookAt = nil
	d.fx:anim(lap, function(a)
		local ang = a0 + a * math.pi * 2
		local p = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		local back = center + Vector3.new(math.cos(ang - 0.1) * r, 0, math.sin(ang - 0.1) * r)
		w.pos = p
		local dir = p - back
		w.yaw = math.atan2(-dir.X, -dir.Z)
		w.lean = -18
		if math.floor(a * 14) ~= math.floor((a - 0.02) * 14) then
			d.fx:dust(p, 2)
		end
	end, function()
		w.lean = 0
		w.pos = start
		faceCamera(d, w)
		d.fx:dust(start, 10)
		d.sfx:play("whoosh")
		w:poke(1.3, 0.7, 1.3, d.now, 0.2)
	end)
	after(d, lap + 0.25, function()
		d.fx:anim(math.max(dur - lap - 0.25, 0.3), function(a)
			local puff = Kit.outBack(math.min(a / 0.3, 1))
			w.squashOverride = Vector3.new(1 + 0.15 * puff, 1 + 0.22 * puff, 1 + 0.15 * puff)
		end, function()
			w.squashOverride = nil
		end)
		d.fx:sparks(w:center(), Kit.FamilyColor.Critter, 20)
		d.fx:word(w:center() + Vector3.new(0, 2, 0), "FLUFF!", Kit.FamilyColor.Critter)
	end)
end

function POSE.Spooky(d, cue, w, dur)
	local losers = gatherLosers(d, cue)
	faceCamera(d, w)
	-- a bedsheet drops over the losers
	if #losers > 0 then
		local sheet = prop(d, { Name = "Sheet", Size = Vector3.new(6, 1.6, 4), Color = rgb(245, 245, 250), Material = Enum.Material.Fabric, Transparency = 0.05 })
		local spot = w.pos + Vector3.new(0, 0.6, -1.8)
		d.fx:anim(0.4, function(a)
			sheet.CFrame = CFrame.new(spot + Vector3.new(0, 6 * (1 - Kit.outCubic(a)), 0))
		end)
	end
	-- the bow
	d.fx:anim(dur, function(a)
		local bow = math.sin(math.clamp((a - 0.25) / 0.35, 0, 1) * math.pi)
		w.lean = 45 * bow
	end, function()
		w.lean = 0
	end)
	-- lights down to one spotlight, eyes glow, wisps circle
	local key = d.arena.key
	local keyB = key.Brightness
	local spotPart = prop(d, { Name = "Spot", Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1, CFrame = CFrame.new(w.pos + Vector3.new(0, 16, 2)) })
	local spot = make("SpotLight", { Face = Enum.NormalId.Bottom, Angle = 22, Range = 24, Brightness = 0, Color = rgb(235, 220, 255), Shadows = true }, spotPart)
	local eyes = {}
	for k = 1, 2 do
		eyes[k] = prop(d, { Name = "GlowEye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Material = Enum.Material.Neon, Color = rgb(140, 255, 200), Transparency = 1 })
	end
	local wisps = {}
	for k = 1, 5 do
		wisps[k] = prop(d, { Name = "Wisp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), Material = Enum.Material.Neon, Color = Kit.FamilyColor.Spooky:Lerp(rgb(255, 255, 255), 0.4), Transparency = 0.3 })
	end
	d.fx:anim(dur, function(a)
		local dim = math.clamp((a - 0.3) / 0.2, 0, 1)
		key.Brightness = keyB * (1 - 0.8 * dim)
		spot.Brightness = 6 * dim
		local head = w:center() + Vector3.new(0, w.height * 0.25, 0)
		for k, e in ipairs(eyes) do
			e.CFrame = CFrame.new(head + Vector3.new((k - 1.5) * 0.6, 0, 0.9))
			e.Transparency = 1 - dim
		end
		for k, s in ipairs(wisps) do
			local ang = d.now * 2.5 + k * 1.25
			s.CFrame = CFrame.new(w:center() + Vector3.new(math.cos(ang) * 2.6, math.sin(ang * 1.7) * 0.8, math.sin(ang) * 2.6))
		end
	end)
	after(d, dur * 0.35, function()
		d.fx:word(w:center() + Vector3.new(0, 2, 0), "BOO-YAH!", Kit.FamilyColor.Spooky)
	end)
end

function POSE.Robo(d, cue, w, dur)
	gatherLosers(d, cue)
	faceCamera(d, w)
	after(d, 0.05, function()
		stomp(d, w, 0.3)
	end)
	after(d, 0.35, function()
		stomp(d, w, 0.3)
	end)
	after(d, 0.6, function()
		d.fx:anim(0.45, function(a)
			w.extraYaw = math.pi * 2 * Kit.inOutQuad(a)
		end, function()
			w.extraYaw = 0
		end)
		d.sfx:play("whoosh")
	end)
	-- the scoreboard
	local holder = prop(d, { Name = "Scoreboard", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
	local bb = make("BillboardGui", { Size = UDim2.fromOffset(160, 140), AlwaysOnTop = true, LightInfluence = 0, Enabled = false }, holder)
	local board = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(20, 24, 30) }, bb)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, board)
	make("UIStroke", { Thickness = 4, Color = rgb(120, 130, 150) }, board)
	local lbl = make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "W", TextScaled = true, Font = Enum.Font.Arcade, TextColor3 = rgb(90, 255, 120) }, board)
	d.fx:anim(dur, function(a)
		holder.CFrame = CFrame.new(w:center() + Vector3.new(0, w.height * 0.6 + 1, 0))
		bb.Enabled = a > 0.45
		lbl.TextTransparency = (a > 0.8 and math.floor(a * dur * 8) % 2 == 0) and 0.6 or 0
	end)
	after(d, dur * 0.5, function()
		local steam = { Texture = Kit.TEX_SMOKE, Color = ColorSequence.new(rgb(235, 240, 245)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }), Speed = NumberRange.new(6, 9), Lifetime = NumberRange.new(0.6, 0.9), SpreadAngle = Vector2.new(10, 10), EmissionDirection = Enum.NormalId.Top }
		for _, side in ipairs({ -1, 1 }) do
			local p = prop(d, { Name = "Vent", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(w:center() + Vector3.new(side * 1, 0.6, 0)) })
			local e = make("ParticleEmitter", steam, p)
			e.Enabled = false
			e:Emit(14)
		end
		d.fx:word(w:center() + Vector3.new(0, 2.6, 0), "VICTORY.EXE", rgb(120, 255, 150))
	end)
end

function POSE.captain_confetti(d, cue, w, dur)
	faceCamera(d, w)
	local start = w.pos
	d.fx:anim(dur, function(a)
		local march = math.clamp(a / 0.5, 0, 1)
		w.pos = start + Vector3.new(-2 + 4 * march, 0, 0)
		w.extraY = math.max(w.extraY, 0)
		w.lean = (march < 1) and 6 * math.sin(a * dur * 14) or 0
	end, function()
		w.lean = 0
	end)
	for k, at in ipairs({ 0.45, 0.6, 0.75 }) do
		after(d, dur * at, function()
			for _, side in ipairs({ -1, 1 }) do
				d.fx:confetti(w.pos + Vector3.new(side * 3, 1, 0), 70)
			end
			d.cam:addTrauma(0.25)
			d.sfx:play("pop")
			local _ = k
		end)
	end
	after(d, dur * 0.82, function()
		w:poke(0.85, 1.25, 0.85, d.now, 0.3)
		d.fx:word(w:center() + Vector3.new(0, 2.5, 0), "PARADE OF ONE!", rgb(255, 230, 90))
	end)
end

function POSE.omega_microwave(d, cue, w, dur)
	faceCamera(d, w)
	local glowPart = prop(d, { Name = "OmegaGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Material = Enum.Material.Neon, Color = rgb(255, 140, 40), Transparency = 1 })
	local light = make("PointLight", { Range = 26, Brightness = 0, Color = rgb(255, 150, 50) }, glowPart)
	local pile = {}
	for _, i in ipairs(cue.losers or {}) do
		local f = d:fighter(i)
		if f.state ~= "gone" then
			table.insert(pile, f)
		end
	end
	d.fx:anim(dur, function(a)
		local open = math.clamp((a - 0.1) / 0.15, 0, 1) * (1 - math.clamp((a - 0.75) / 0.1, 0, 1))
		glowPart.CFrame = CFrame.new(w:center())
		local s = 3 + 6 * open
		glowPart.Size = Vector3.new(s, s, s)
		glowPart.Transparency = 1 - 0.55 * open
		light.Brightness = 8 * open
		for k, f in ipairs(pile) do
			local ang = d.now * 1.4 + k * (math.pi * 2 / math.max(#pile, 1))
			f.pos = w.pos + Vector3.new(math.cos(ang) * 3.2, 0, math.sin(ang) * 3.2)
			f.yaw = ang
		end
	end)
	after(d, dur * 0.88, function()
		d.fx:word(w:center() + Vector3.new(0, 2.5, 0), "DING!", rgb(255, 200, 90))
		d.fx:flash(rgb(255, 210, 140), 0.15, 0.6)
		d.sfx:play("bonk")
	end)
end

function POSE.Building(d, cue, w, dur)
	gatherLosers(d, cue, function(k)
		return Vector3.new(((k - 1) % 3 - 1) * 2.2, 0, 2.2)
	end)
	faceCamera(d, w)
	local holder = prop(d, { Name = "Lights", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(w:center()) })
	local light = make("PointLight", { Range = 16, Brightness = 0, Color = rgb(255, 230, 170) }, holder)
	local ribbonL = prop(d, { Name = "Ribbon", Size = Vector3.new(2.5, 0.4, 0.1), Color = rgb(220, 30, 50) })
	local ribbonR = prop(d, { Name = "Ribbon", Size = Vector3.new(2.5, 0.4, 0.1), Color = rgb(220, 30, 50) })
	d.fx:anim(dur, function(a)
		light.Brightness = 5 * math.clamp(a / 0.15, 0, 1)
		local snap = math.clamp((a - 0.25) / 0.2, 0, 1)
		local front = w.pos + Vector3.new(0, 1.4, 2.6)
		ribbonL.CFrame = CFrame.new(front + Vector3.new(-1.25 - snap * 1.5, -snap * 1.2, 0)) * CFrame.Angles(0, 0, -snap * 1.2)
		ribbonR.CFrame = CFrame.new(front + Vector3.new(1.25 + snap * 1.5, -snap * 1.2, 0)) * CFrame.Angles(0, 0, snap * 1.2)
	end)
	for k, at in ipairs({ 0.35, 0.5, 0.65, 0.8 }) do
		after(d, dur * at, function()
			local p = w.pos + Vector3.new((k % 2 == 0) and 3 or -3, w.height + 5 + k, -2)
			d.fx:sparks(p, Color3.fromHSV((k * 0.23) % 1, 0.7, 1), 40)
			d.fx:flash(Color3.fromHSV((k * 0.23) % 1, 0.4, 1), 0.06, 0.2)
			d.sfx:play("pop", 0.6)
		end)
	end
	after(d, dur * 0.3, function()
		d.fx:word(w:center() + Vector3.new(0, 2.5, 0), "GRAND OPENING!", rgb(255, 230, 120))
	end)
end

function POSE.Spell(d, cue, w, dur)
	gatherLosers(d, cue)
	faceCamera(d, w)
	d.fx:anim(dur, function(a)
		w.extraY = 1.5 + 0.3 * math.sin(a * dur * 3)
		w.extraYaw = math.sin(a * dur * 1.5) * 0.4
	end)
	after(d, 0.2, function()
		d.fx:sparks(w:center(), Kit.TierColor[w.info.tier] or rgb(255, 255, 255), 40)
		d.fx:word(w:center() + Vector3.new(0, 2.5, 0), "RESOLVED!", Kit.TierColor[w.info.tier])
	end)
end

function Poses.play(d, cue, dur)
	local w = d:fighter(cue.who)
	w.state = "in"
	local info = w.info
	local fn
	if info.kind == "building" then
		fn = POSE.Building
	elseif info.kind == "spell" then
		fn = POSE.Spell
	else
		fn = POSE[info.id] or POSE[info.family] or POSE.Critter
	end
	fn(d, cue, w, dur)
	if cue.tier == "Legendary" or cue.tier == "Secret" then
		after(d, 0.3, function()
			d.fx:confetti(w:center() + Vector3.new(0, 6, 0), 90, ColorSequence.new(cue.tier == "Legendary" and Kit.TierColor.Legendary or rgb(255, 255, 255), rgb(255, 255, 255)))
		end)
	end
end

---------------------------------------------------------------------------
-- Ultimates (Legendary and the Secret flash). The hits themselves are cues in the script;
-- these are the props that sell them.
---------------------------------------------------------------------------
local ULT = {}

function ULT.Snack(d, w, dur, targets)
	local spot = Kit.ORIGIN + Vector3.new(0, 0, -1)
	local bowl = prop(d, { Name = "SundaeBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.5, 9, 9), Color = rgb(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.3 })
	local scoops = {}
	for k, c in ipairs({ rgb(255, 240, 220), rgb(255, 160, 190), rgb(120, 70, 50) }) do
		scoops[k] = prop(d, { Name = "Scoop", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Color = c })
	end
	local cherry = prop(d, { Name = "Cherry", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Color = rgb(220, 20, 40) })
	d.fx:anim(dur, function(a)
		local fall = Kit.inQuad(math.clamp(a / 0.22, 0, 1))
		local y = 40 * (1 - fall)
		bowl.CFrame = CFrame.new(spot + Vector3.new(0, 1.2 + y, 0)) * CFrame.Angles(0, 0, math.rad(90))
		for k, s in ipairs(scoops) do
			s.CFrame = CFrame.new(spot + Vector3.new((k - 2) * 2, 4 + y + (k == 2 and 2 or 0), 0))
		end
		local boing = math.clamp((a - 0.3) / 0.2, 0, 1)
		cherry.CFrame = CFrame.new(spot + Vector3.new(0, 9 + y + 3 * math.sin(boing * math.pi), 0))
		local fade = math.clamp((a - 0.85) / 0.15, 0, 1)
		for _, p in ipairs({ bowl, cherry, scoops[1], scoops[2], scoops[3] }) do
			p.Transparency = math.max(p == bowl and 0.3 or 0, fade)
		end
	end)
	after(d, dur * 0.22, function()
		d.fx:shock(spot + Vector3.new(0, 0.2, 0), rgb(255, 255, 255), 34)
		d.cam:addTrauma(1)
		d.sfx:play("crater")
	end)
end

function ULT.Junk(d, w, dur)
	local junk = {}
	for k = 1, 16 do
		local isCan = k % 3 == 0
		junk[k] = {
			part = prop(d, {
				Name = "JunkWave",
				Shape = isCan and Enum.PartType.Cylinder or Enum.PartType.Block,
				Size = isCan and Vector3.new(1.2, 1, 1) or Vector3.new(1.5 + (k % 4) * 0.6, 1.2 + (k % 3) * 0.5, 1.6),
				Color = ({ rgb(150, 140, 120), rgb(120, 90, 70), rgb(180, 180, 190), rgb(90, 110, 130) })[(k % 4) + 1],
				Material = isCan and Enum.Material.Metal or Enum.Material.SmoothPlastic,
			}),
			z = -9 + (k % 8) * 2.4,
			y = (k > 8) and 2.2 or 0.8,
			spin = k,
		}
	end
	d.fx:anim(dur, function(a)
		local x = -20 + 40 * Kit.inOutQuad(math.clamp((a - 0.1) / 0.6, 0, 1))
		for _, j in ipairs(junk) do
			j.part.CFrame = CFrame.new(Kit.ORIGIN + Vector3.new(x + math.sin(j.spin) * 1.5, j.y + math.abs(math.sin(d.now * 8 + j.spin)) * 0.8, j.z)) * CFrame.Angles(d.now * 3 + j.spin, j.spin, 0)
			j.part.Transparency = a > 0.85 and (a - 0.85) / 0.15 or 0
		end
	end)
end

function ULT.Weather(d, w, dur, targets)
	d.fx:tornado(function()
		return Kit.ORIGIN + Vector3.new(0, 0, -1)
	end, dur)
	for k, i in ipairs(targets or {}) do
		after(d, 0.35 + k * 0.11, function()
			local f = d:fighter(i)
			lightning(d, f:center() + Vector3.new(0, 14, 0), f:center())
		end)
	end
	d.fx:flash(rgb(150, 255, 190), 0.3, 0.25)
end

function ULT.Critter(d, w, dur)
	local herd = {}
	for k = 1, 14 do
		local body = prop(d, { Name = "Stampede", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), Color = Color3.fromHSV(0.05 + (k % 5) * 0.06, 0.4, 0.9) })
		local ear = prop(d, { Name = "Ear", Size = Vector3.new(0.3, 0.7, 0.2), Color = body.Color })
		herd[k] = { body = body, ear = ear, z = -9 + (k % 7) * 3, lag = (k % 4) * 0.08 }
	end
	d.fx:anim(dur, function(a)
		for _, h in ipairs(herd) do
			local x = -22 + 44 * math.clamp((a - h.lag) / 0.6, 0, 1)
			local hop = math.abs(math.sin(d.now * 18 + h.z)) * 0.8
			h.body.CFrame = CFrame.new(Kit.ORIGIN + Vector3.new(x, 0.65 + hop, h.z))
			h.ear.CFrame = h.body.CFrame * CFrame.new(0.25, 0.75, 0)
		end
	end)
	d.cam:addTrauma(0.6)
end

function ULT.Spooky(d, w, dur, targets)
	after(d, 0.2, function()
		d.fx:blackout(0.7)
		d.sfx:cut()
	end)
	for k = 1, 6 do
		after(d, 0.25 + k * 0.1, function()
			d.sfx:play("heavy", 0.6)
		end)
	end
end

function ULT.Robo(d, w, dur)
	local beam = prop(d, { Name = "OverclockBeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(30, 3, 3), Material = Enum.Material.Neon, Color = rgb(120, 230, 255), Transparency = 1 })
	d.fx:anim(dur, function(a)
		local on = math.clamp((a - 0.2) / 0.1, 0, 1) * (1 - math.clamp((a - 0.85) / 0.15, 0, 1))
		local sweep = math.rad(-70 + 140 * math.clamp((a - 0.2) / 0.6, 0, 1))
		local c = w:center()
		local dir = Vector3.new(math.sin(sweep), 0, -math.cos(sweep))
		beam.CFrame = CFrame.lookAt(c + dir * 15, c + dir * 30) * CFrame.Angles(0, math.rad(90), 0)
		beam.Size = Vector3.new(30, 2 + 1.2 * math.sin(d.now * 40), 2 + 1.2 * math.sin(d.now * 40))
		beam.Transparency = 1 - 0.9 * on
	end)
end

local function genericUlt(d, w, dur)
	after(d, 0.3, function()
		d.fx:detonate(w:center(), Kit.TierColor.Legendary)
	end)
end

function Poses.ultimate(d, cue)
	local w = d:fighter(cue.who)
	local fam = w.info.kind == "creature" and w.info.family or nil
	local fn = (fam and ULT[fam]) or genericUlt
	w:poke(0.8, 1.3, 0.8, d.now, 0.4)
	fn(d, w, cue.dur or 1.6, cue.targets)
end

return Poses

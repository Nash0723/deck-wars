-- The Pack Brawl Director: plays a timeline from Scripts.luau on the client.
--
-- One clock (t) drives everything. Each frame: t += real dt * time scale (3 while the player
-- holds to fast-forward, 0.05 during hit-stop), cues whose time has come fire once in order,
-- then fighters, arena, effects and camera are drawn for time t. Skip and cleanup go through
-- the same few functions, so nothing is left behind whichever way the cinematic ends.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local here = script.Parent
local Kit = require(here:WaitForChild("Kit"))
local Scripts = require(here:WaitForChild("Scripts"))
local Arena = require(here:WaitForChild("Arena"))
local Fighters = require(here:WaitForChild("Fighters"))
local CamRig = require(here:WaitForChild("CamRig"))
local Fx = require(here:WaitForChild("Fx"))
local Sfx = require(here:WaitForChild("Sfx"))
local Poses = require(here:WaitForChild("Poses"))
local Moves = require(here:WaitForChild("Moves"))

local rgb, make = Kit.rgb, Kit.make

local Director = {}
Director.__index = Director

local FAST_FORWARD = 3

-- The player's settings (Pack fights: Quick, camera shake, graphics); defaults if missing.
local Settings = nil
pcall(function()
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("DeckWars")
	local m = shared and shared:FindFirstChild("Settings")
	if m then
		Settings = require(m)
	end
end)
local function setting(key, default)
	local v = Settings and Settings.get(key)
	if v == nil then
		return default
	end
	return v
end
local LIGHTING_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogEnd", "GlobalShadows" }

local function controls(on)
	local player = Players.LocalPlayer
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and module then
		local c = module:GetControls()
		if on then
			c:Enable()
		else
			c:Disable()
		end
	end
end

-- Plays a script (from Scripts.build). onDone({ skipped = bool }) is called after cleanup.
function Director.play(script_, onDone)
	local self = setmetatable({}, Director)
	self.script = script_
	self.tier = script_.tier
	self.onDone = onDone
	self.t = 0
	self.now = 0
	self.cueIndex = 1
	self.speed = 1
	self.slowUntil = 0
	self.hitstopUntil = 0
	self.realClock = 0
	self.conns = {}
	self.stopped = false
	-- "Quick" pack fights play fast-forwarded the whole way (holding the screen does the same)
	self.quick = setting("packFights", "Full") == "Quick"

	local camera = workspace.CurrentCamera
	self.camera = camera
	self.savedCamera = { CameraType = camera.CameraType, CFrame = camera.CFrame, FieldOfView = camera.FieldOfView }
	camera.CameraType = Enum.CameraType.Scriptable

	-- lighting for the arena (restored afterwards)
	self.savedLighting = {}
	for _, k in ipairs(LIGHTING_PROPS) do
		self.savedLighting[k] = Lighting[k]
	end
	self.disabledEffects = {}
	for _, e in ipairs(Lighting:GetChildren()) do
		if e:IsA("PostEffect") and e.Enabled then
			e.Enabled = false
			table.insert(self.disabledEffects, e)
		end
	end
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = rgb(74, 64, 96)
	Lighting.OutdoorAmbient = rgb(40, 35, 60)
	Lighting.ExposureCompensation = 0
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.FogEnd = 100000
	Lighting.GlobalShadows = setting("graphics", "High") ~= "Low"

	-- post effects live on the camera, so only this cinematic uses them
	local grade = Kit.TierGrade[self.tier] or Kit.TierGrade.Common
	self.grade = grade
	self.bloom = make("BloomEffect", { Name = "PackBrawlBloom", Intensity = grade[1], Threshold = grade[2], Size = 30 }, camera)
	self.cc = make("ColorCorrectionEffect", { Name = "PackBrawlGrade", Contrast = grade[3], Saturation = grade[4], TintColor = grade[5], Brightness = 0 }, camera)

	-- scene and screen
	self.folder = make("Folder", { Name = "PackBrawlScene" }, workspace)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = make("ScreenGui", { Name = "PackBrawlGui", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	self.arena = Arena.new(self.folder)
	self.fx = Fx.new(self.folder, self.gui)
	self.sfx = Sfx.new()
	self.fighters = {}
	for i, info in ipairs(script_.fighters) do
		self.fighters[i] = Fighters.new(info, i, self.folder)
	end
	self.cam = CamRig.new(camera, self.tier, function(i)
		return self.fighters[i]
	end)
	self.cam.shakeScale = Settings and Settings.ShakeScale[setting("shake", "Full")] or 1
	controls(false)

	-- skip button (appears after 0.5 s) and hold-to-fast-forward
	self.skipButton = self.fx:skipButton(function()
		self:skip()
	end)
	table.insert(self.conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.Space then
			self.holding = true
		end
	end))
	table.insert(self.conns, UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.Space then
			self.holding = false
		end
	end))
	table.insert(self.conns, RunService.RenderStepped:Connect(function(dt)
		self:step(dt)
	end))
	-- if the player's character resets mid-cinematic, clean up quietly
	local player = Players.LocalPlayer
	table.insert(self.conns, player.CharacterAdded:Connect(function()
		self:complete(true)
	end))
	self:step(0)
	return self
end

function Director:fighter(i)
	return self.fighters[i]
end

function Director:timeScale()
	if self.realClock < self.hitstopUntil then
		return 0.05
	end
	local s = 1
	if self.realClock < self.slowUntil then
		s = self.slowScale or 0.25
	end
	if (self.holding or self.quick) and not self.finishing then
		s *= FAST_FORWARD
	end
	return s
end

function Director:step(dt)
	if self.stopped then
		return
	end
	self.realClock += dt
	local scale = self:timeScale()
	if scale ~= self.lastScale then
		self.lastScale = scale
		self.sfx:setSpeed(math.max(scale, 0.5))
	end
	self.t += dt * scale
	if self.realClock > 0.5 and not self.finishing then
		self.skipButton.Visible = true
		self.gui.Hint.Visible = true
	end
	self:fireUpTo(self.t)
	if self.stopped then
		return
	end
	self:draw(dt * scale)
end

function Director:fireUpTo(t)
	local cues = self.script.cues
	while not self.stopped and self.cueIndex <= #cues and cues[self.cueIndex].t <= t do
		local c = cues[self.cueIndex]
		self.cueIndex += 1
		self.now = c.t
		self.fx.now = c.t
		local h = Director.handlers[c.k]
		if h then
			h(self, c)
		end
	end
	self.now = t
end

function Director:draw(dt)
	local t = self.t
	for i, f in ipairs(self.fighters) do
		local frozen = self.frozen or (self.timestopped and i ~= self.script.winner)
		if not frozen then
			if f.state == "in" and not f.motion then
				-- face the nearest other fighter still in the fight
				local best, bestD
				for j, g in ipairs(self.fighters) do
					if j ~= i and (g.state == "in") then
						local d = (g.pos - f.pos).Magnitude
						if not bestD or d < bestD then
							best, bestD = g, d
						end
					end
				end
				if best and not f.posing then
					f.lookAt = best.pos
				end
			end
			f:render(t)
		end
	end
	self.arena:update(t, dt, self.frozen or self.timestopped)
	self.fx:update(t)
	if self.stopped then
		return
	end
	if self.beam then
		local a, b = self.fighters[self.beamA], self.fighters[self.beamB]
		self.beam.update(self.beam, t, self.timestopped or self.frozen, a:center(), b:center())
		if t >= self.beamEnd and not self.timestopped then
			self.beam.stop()
			self.beam = nil
		end
	end
	self.cam:update(t, self.frozen and 0 or dt)
end

---------------------------------------------------------------------------
-- Skip, finish, cleanup
---------------------------------------------------------------------------
function Director:skip()
	if self.finishing or self.stopped then
		return
	end
	local target, toReveal = Scripts.skipTarget(self.script, self.t)
	if not toReveal then
		-- Secret: jump to the blinding flash, quietly firing everything on the way
		self.fx.quiet = true
		self.sfx.muted = true
		self.t = target
		self:fireUpTo(target)
		self.fx.quiet = false
		self.sfx.muted = false
		self.sfx:cut()
		if not self.stopped then
			self:draw(0)
		end
		return
	end
	self.finishing = true
	self.skipButton.Visible = false
	self.sfx:fadeOut(0.15, self.fx)
	self.fx:flash(Kit.tierColor(self.tier, self.t), 0.2, 1)
	self.fx.flashFrame.BackgroundTransparency = 0
	self.fx:anim(0.2, function() end, function()
		self:complete(true)
	end)
end

function Director:complete(skipped)
	if self.stopped then
		return
	end
	self:stop()
	if self.onDone then
		self.onDone({ skipped = skipped == true })
	end
end

-- Safe to call more than once.
function Director:stop()
	if self.stopped then
		return
	end
	self.stopped = true
	for _, c in ipairs(self.conns) do
		c:Disconnect()
	end
	self.conns = {}
	if self.beam then
		self.beam.stop()
		self.beam = nil
	end
	self.sfx:destroy()
	self.folder:Destroy()
	self.gui:Destroy()
	self.bloom:Destroy()
	self.cc:Destroy()
	for k, v in pairs(self.savedLighting) do
		Lighting[k] = v
	end
	for _, e in ipairs(self.disabledEffects) do
		e.Enabled = true
	end
	local cam = self.camera
	cam.CameraType = self.savedCamera.CameraType
	cam.CFrame = self.savedCamera.CFrame
	cam.FieldOfView = self.savedCamera.FieldOfView
	controls(true)
end

---------------------------------------------------------------------------
-- Cue handlers
---------------------------------------------------------------------------
local H = {}
Director.handlers = H

local function W(p, y)
	return Kit.world(p, y)
end

local SFX_FOR_POWER = { "slap", "thud", "heavy" }

H.pack = function(d, c)
	local pack = d.arena:makePack(d.folder, c.at, d.script.pack)
	d.pack = pack
	d.fx:anim(0.9, function(a)
		local shake = a < 0.45 and math.sin(a * 90) * 0.12 * (a / 0.45) or 0
		local land = a < 0.12 and (1 - a / 0.12) * 6 or 0
		pack.body.CFrame = pack.base * CFrame.new(shake, land, 0) * CFrame.Angles(0, 0, shake * 0.5)
		if a < 0.45 then
			pack.top.CFrame = pack.body.CFrame * CFrame.new(0, 2.1, 0)
		else
			local f = (a - 0.45) / 0.55
			pack.top.CFrame = pack.base * CFrame.new(1.5 * f, 2.1 + 4 * f - 3 * f * f, 0) * CFrame.Angles(0, 0, -f * 4)
			pack.top.Transparency = f
		end
		if a > 0.55 then
			local f = (a - 0.55) / 0.45
			pack.body.Transparency = f
			pack.body.Size = Vector3.new(3 + f, 3.4 * (1 - 0.6 * f), 0.5)
		end
	end, function()
		pack.body:Destroy()
		pack.top:Destroy()
	end)
end

H.hype = function(d, c)
	d.arena:setHype(c.tier, d.now)
end

H.cam = function(d, c)
	d.cam:setShot(c, d.now)
end

H.sfx = function(d, c)
	d.sfx:play(c.name, c.vol)
end

H.music = function(d, c)
	d.sfx:playMusic(c.name)
end

H.musicstop = function(d)
	d.sfx:stopMusic()
end

H.theme = function(d)
	-- the theme's bass drop is 0.3 s in; start it so the drop lands on the first freeze cut
	d.sfx:playMusic("theme")
end

H.sting = function(d, c)
	d.sfx:play("sting_" .. c.tier)
end

H.enter = function(d, c)
	local f = d:fighter(c.who)
	local to = W(c.to)
	local style = c.style
	local m = { t0 = d.now, t1 = d.now + c.dur, to = to, endState = "in" }
	f.state = "entering"
	if style == "tumble" then
		m.from = W(Scripts.PACK, 1.5)
		m.arc = 2.5
		f.spin = { t0 = d.now, t1 = d.now + c.dur, turns = 1, axis = "tumble" }
	elseif style == "pop" then
		m.from = W(Scripts.PACK, 0.5)
		m.arc = 3
		f:poke(0.75, 1.4, 0.75, d.now, 0.25)
		d.fx:sparks(m.from + Vector3.new(0, 1, 0), Kit.TierColor.Common, 14)
	elseif style == "cannonball" then
		m.from = W(c.from or { x = -16, z = 0 }, 9)
		m.arc = 3
		f.spin = { t0 = d.now, t1 = d.now + c.dur, turns = 2, axis = "tumble" }
	elseif style == "burrow" then
		m.from = to - Vector3.new(0, 7, 0)
		m.ease = Kit.outBack
		d.fx:dust(to, 14)
		d.arena:popTiles(c.to, d.now)
	elseif style == "drop" then
		m.from = to + Vector3.new(0, 45, 0)
		m.ease = Kit.inQuad
		f:poke(0.8, 1.35, 0.8, d.now, c.dur)
	elseif style == "skid" then
		m.from = to + Vector3.new((c.to.x >= 0) and 12 or -12, 0, 0)
		m.ease = Kit.outQuad
		m.lean = -15
		m.faceTravel = true
		d.fx:dust(to, 10)
	elseif style == "walk" then
		m.from = to + Vector3.new(0, 0, 8)
		m.ease = function(x)
			return x
		end
		m.faceTravel = true
	elseif style == "stepout" then
		m.from = to + Vector3.new(0, 0, -1.2)
		m.arc = 1.2
	elseif style == "spellcard" then
		m.from = to + Vector3.new(0, 18, -14)
		m.ease = Kit.outCubic
		f.spin = { t0 = d.now, t1 = d.now + c.dur, turns = 3, axis = "yaw" }
	else -- appear
		m.from = to
	end
	m.onLand = function(fi)
		fi:poke(1.3, 0.7, 1.3, d.now, 0.18)
		if style ~= "appear" and style ~= "walk" and style ~= "stepout" then
			d.fx:dust(fi.pos, 8)
		end
		if style == "drop" or style == "cannonball" then
			d.cam:addTrauma(style == "drop" and 0.7 or 0.35)
			d.cam:punchFov()
		end
	end
	if c.winner then
		f.lookAt = f.pos + Vector3.new(0, 0, 10)
	end
	f:setMotion(m)
end

H.move = function(d, c)
	local f = d:fighter(c.who)
	local from = f.renderPos or f.pos
	local m = { t0 = d.now, t1 = d.now + c.dur, from = from, to = W(c.to), faceTravel = c.style ~= "drag" }
	if c.style == "hop" then
		m.arc = f.rig and 0.5 or 1
	elseif c.style == "dash" then
		m.arc = 0.2
		m.ease = Kit.outQuad
		m.lean = 12
	elseif c.style == "walk" then
		m.ease = function(x)
			return x
		end
	elseif c.style == "drag" then
		m.ease = function(x)
			return x
		end
		m.lean = -12
	end
	if f.state == "down" then
		f.state = "in"
	end
	f:setMotion(m)
end

H.lunge = function(d, c)
	local a, b = d:fighter(c.who), d:fighter(c.target)
	local from = a.renderPos or a.pos
	local tp = b.renderPos or b.pos
	local dir = tp - from
	local dist = dir.Magnitude
	local reach = math.max(dist - 1.6, 0)
	local mid = dist > 0.01 and from + dir.Unit * reach * 0.85 or from
	local half = (c.dur or 0.24) / 2
	if not a.rig then
		-- spell cards have no arms: they still squash into the hit
		a:poke(0.85, 0.9, 1.3, d.now, half)
	end
	a:setMotion({
		t0 = d.now,
		t1 = d.now + half,
		from = from,
		to = mid,
		arc = a.rig and 0.05 or 0.3,
		ease = Kit.outQuad,
		lean = a.rig and 0 or 18,
		onLand = function(fi)
			fi:setMotion({ t0 = d.now, t1 = d.now + half, from = mid, to = from, ease = Kit.inOutQuad })
			fi.lookAt = tp
		end,
	})
	a.lookAt = tp
	a.yaw = math.atan2(-dir.X, -dir.Z)
end

-- The attacker's punch / kick / headbutt / signature move, timed to land on its hit.
H.swing = function(d, c)
	local a = d:fighter(c.who)
	if not a.rig then
		return
	end
	if c.dive or a.state == "entering" then
		a:play("dive", d.now)
		return
	end
	local b = c.target and d:fighter(c.target)
	if b and b.pos then
		local dir = (b.renderPos or b.pos) - (a.renderPos or a.pos)
		if dir.Magnitude > 0.1 then
			a.lookAt = b.renderPos or b.pos
		end
	end
	if c.blocked and b and b.rig and c.contact then
		-- the target sees it coming and gets its guard up just in time
		b:play("block", c.contact - 0.1, { queue = true })
	end
	local name = a:swing(c.power or 1, d.now, c.sig, c.contact)
	if c.sig and name then
		local m = Moves.get(name)
		if m and m.name then
			-- a signature move gets its name shouted
			d.fx:word(a:center() + Vector3.new(0, 2.2, 0), string.upper(m.name) .. "!", Kit.tierColor(a.info.tier, d.now))
		end
		d.sfx:play("whoosh")
	elseif (c.power or 1) >= 2 then
		d.sfx:play("whoosh", 0.4)
	end
end

-- The target of a missed punch gets out of the way.
H.dodge = function(d, c)
	local f = d:fighter(c.who)
	if not f.rig then
		return
	end
	f.dodges = (f.dodges or 0) + 1
	f:play(Moves.pickDodge(f.dodges + f.index), d.now)
	d.fx:anim(math.max((c.contact or d.now) - d.now, 0), function() end, function()
		d.fx:word(f:center() + Vector3.new(0, 1.6, 0), "MISS!", rgb(255, 255, 255))
		d.sfx:play("whoosh", 0.5)
	end)
end

-- A knocked-out creature disappears in a puff once it lands, so the winner has the ring to itself.
local function vanish(d, f, delay)
	d.fx:anim(delay, function() end, function()
		if f.state ~= "gone" or f.pos.Y > Kit.ORIGIN.Y - 2 then
			d.fx:dust(f:center(), 10)
		end
		f:hide()
	end)
end

H.hit = function(d, c)
	local f = d:fighter(c.who)
	local by = c.by and d:fighter(c.by)
	local from = f.renderPos or f.pos
	local to = W(c.to)
	local m = { t0 = d.now, t1 = d.now + c.dur, from = from, ease = Kit.outQuad, faceTravel = true, backwards = true }
	if c.ko == "ropes" then
		m.to = to
		m.arc = 1.6
		m.endState = "down"
	elseif c.ko == "out" then
		m.to = to - Vector3.new(0, 16, 0)
		m.arc = 9
		m.ease = function(x)
			return x
		end
		m.endState = "gone"
	elseif c.ko == "sky" then
		m.to = to + Vector3.new(0, 45, 0)
		m.ease = Kit.outQuad
		m.endState = "gone"
	else
		m.to = to
		m.arc = 0.3 * c.power
		m.endState = "in"
	end
	if c.spin then
		f.spin = { t0 = d.now, t1 = d.now + c.dur, turns = c.ko == "sky" and 3 or 1, axis = c.ko and "tumble" or "yaw" }
	end
	if c.ko then
		m.onLand = function(fi)
			vanish(d, fi, c.ko == "ropes" and 0.5 or 0.05)
		end
	end
	f.state = "hit"
	f:setMotion(m)
	if c.blocked and f.rig then
		-- guard held: arms took it
		if not (f.anim and f.anim.name == "block") and not (f.nextAnim and f.nextAnim.name == "block") then
			f:play("block", d.now - 0.08)
		end
	elseif f.rig then
		f:stopLoop()
		local react = c.ko and "launch" or (c.power >= 2 and "stagger" or "flinch")
		f:play(react, d.now)
		f:poke(1.08, 0.94, 1.08, d.now, 0.15)
	else
		f:poke(1.25, 0.75, 1.25, d.now, 0.2)
	end
	local tierForColor = by and by.info.tier or d.tier
	local color = Kit.tierColor(tierForColor, d.now)
	if c.power >= 2 or not (d.tier == "Common") then
		color = color:Lerp(Kit.tierColor(d.arena.hype, d.now), 0.5)
	end
	local point = from + Vector3.new(0, f.height * 0.55, 0)
	if c.blocked then
		d.fx:sparks(point, rgb(255, 255, 255), 6)
		d.fx:word(point + Vector3.new(0, 1.5, 0), "BLOCK!", rgb(200, 230, 255))
		d.cam:addTrauma(0.12)
		d.sfx:play("thud")
		return
	end
	d.fx:sparks(point, color, ({ 10, 20, 36 })[c.power] or 12)
	if c.power >= 3 then
		d.fx:shock(Vector3.new(point.X, Kit.ORIGIN.Y + 0.15, point.Z), color, 9)
	end
	if c.word then
		d.fx:word(point + Vector3.new(0, 1.5, 0), c.word, Kit.tierColor(d.arena.hype, d.now))
	end
	d.cam:addTrauma(({ 0.22, 0.4, 0.65 })[c.power] or 0.3)
	if c.power >= 2 then
		d.cam:punchFov()
	end
	d.sfx:play(c.power == 1 and ((c.who % 2 == 0) and "slap" or "bonk") or SFX_FOR_POWER[c.power])
	d.arena.cheer = math.min(1, d.arena.cheer + 0.05 * c.power)
end

H.shove = function(d, c)
	local a, b = d:fighter(c.a), d:fighter(c.b)
	a:play("grapple", d.now)
	b:play("grapple", d.now + 0.08)
	d.fx:anim(c.dur, function(x)
		local push = math.sin(x * math.pi * 6) * 0.35
		a.extraYaw = push * 0.2
		b.extraYaw = -push * 0.2
		a.lean = 20 + push * 10
		b.lean = 20 - push * 10
	end, function()
		a.extraYaw, b.extraYaw, a.lean, b.lean = 0, 0, 0, 0
		a:stopLoop()
		b:stopLoop()
	end)
	d.fx:word(a:center():Lerp(b:center(), 0.5) + Vector3.new(0, 2, 0), "GRRR!", rgb(255, 255, 255))
end

H.spin = function(d, c)
	local f = d:fighter(c.who)
	f.spin = { t0 = d.now, t1 = d.now + c.dur, turns = c.turns or 1, axis = "yaw" }
	d.fx:sparks(f:center(), Kit.tierColor(d.tier, d.now), 20)
end

H.hitstop = function(d, c)
	d.hitstopUntil = d.realClock + c.dur
end

H.slowmo = function(d, c)
	d.slowScale = c.scale
	d.slowUntil = d.realClock + c.dur / c.scale
end

H.arena = function(d, c)
	if c.what == "tiles" or c.what == "crater" then
		d.arena:popTiles(c.at, d.now)
	elseif c.what == "banner" then
		d.arena:dropBanner(d.now)
	elseif c.what == "post" then
		d.arena:knockPost(c.index or 1, d.now)
	end
end

H.clash = function(d, c)
	local p = W(c.at, 2.4)
	d.fx:sparks(p, Kit.tierColor(d.arena.hype, d.now), 40)
	d.fx:shock(W(c.at, 0.15), Kit.tierColor(d.arena.hype, d.now), 14)
	d.fx:word(p + Vector3.new(0, 2, 0), "CRASH!", rgb(255, 240, 120))
	d.cam:addTrauma(0.6)
	d.cam:punchFov()
end

H.marker = function(d, c)
	d.fx:marker(W(c.at), Kit.tierColor(c.tier, d.now), c.dur)
end

H.shock = function(d, c)
	d.fx:shock(W(c.at, 0.15), Kit.tierColor(c.tier, d.now), c.size or 10)
end

H.word = function(d, c)
	local pos = c.who and (d:fighter(c.who):center() + Vector3.new(0, 1.5, 0)) or W(c.at, 3.5)
	d.fx:word(pos, c.text, Kit.tierColor(d.arena.hype, d.now):Lerp(rgb(255, 255, 255), 0.25))
end

H.beam = function(d, c)
	local a, b = d:fighter(c.a), d:fighter(c.b)
	local ca = Kit.FamilyColor[a.info.family] or Kit.TierColor[a.info.tier]
	local cb = Kit.FamilyColor[b.info.family] or Kit.TierColor[b.info.tier]
	d.beam = d.fx:beam(a:center(), b:center(), W(c.at, 2.6), ca:Lerp(Kit.TierColor[a.info.tier], 0.4), cb:Lerp(Kit.TierColor[b.info.tier], 0.4))
	d.beamA, d.beamB, d.beamEnd = c.a, c.b, d.now + c.dur
	a.posing, b.posing = true, true
	a.lookAt, b.lookAt = W(c.at), W(c.at)
	a:play("push", d.now)
	b:play("push", d.now)
end

H.timestop = function(d)
	d.timestopped = true
	d.fx:setParticleTime(0)
	d.sfx:cut()
	local cc = d.cc
	local sat0 = cc.Saturation
	d.fx:anim(0.12, function(a)
		cc.Saturation = sat0 + (-1 - sat0) * a
	end)
	local w = d:fighter(d.script.winner)
	w.outline.FillColor = Kit.TierColor.Mythic
	w.outline.FillTransparency = 0.75
end

H.flick = function(d, c)
	local p = W(c.at, 2.6)
	d.fx:word(p + Vector3.new(0, 2, 0), "*flick*", rgb(255, 255, 255))
	local w = d:fighter(c.who)
	w:poke(0.9, 1.1, 1.2, d.now, 0.2)
end

H.timeresume = function(d)
	d.timestopped = false
	d.fx:setParticleTime(1)
	d.cc.Saturation = d.grade[4]
	local w = d:fighter(d.script.winner)
	w.outline.FillTransparency = 1
end

H.detonate = function(d, c)
	if d.beam then
		d.beam.stop()
		d.beam = nil
	end
	for _, f in ipairs(d.fighters) do
		f.posing = false
		f:stopLoop()
	end
	d.fx:detonate(W(c.at, 2.6), Kit.tierColor(c.tier, d.now))
	d.arena:popTiles(c.at, d.now)
	d.arena:dropBanner(d.now)
end

H.flash = function(d, c)
	d.fx:flash(Kit.tierColor(c.tier, d.now), c.dur, 0.7)
	d.cc.Brightness = 0.6
	d.fx:anim(c.dur, function(a)
		d.cc.Brightness = 0.6 * (1 - a)
	end)
end

H.shake = function(d, c)
	d.cam:addTrauma(c.amount)
end

H.lines = function(d)
	d.fx:lines()
end

H.dutchflip = function(d)
	d.cam:flipDutch()
end

H.brawlball = function(d, c)
	local from, to = W(c.from), W(c.to)
	local cloud = Kit.part({ Name = "BrawlCloud", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), Color = rgb(220, 210, 200), Transparency = 0.35 }, d.folder)
	local list = {}
	for k, i in ipairs(c.who) do
		local f = d:fighter(i)
		f.motion = nil
		f.state = "brawl"
		f:play("flail", d.now + k * 0.03)
		list[k] = f
	end
	local lastDust = 0
	d.fx:anim(c.dur, function(a)
		local center = from:Lerp(to, Kit.inOutSine(a)) + Vector3.new(0, 2.2 + math.abs(math.sin(d.fx.now * 7)) * 0.6, 0)
		cloud.CFrame = CFrame.new(center) * CFrame.Angles(d.fx.now * 5, d.fx.now * 3, 0)
		local s = 7 + math.sin(d.fx.now * 13) * 0.6
		cloud.Size = Vector3.new(s, s * 0.85, s)
		for k, f in ipairs(list) do
			local ang = d.fx.now * 9 + k * 2.1
			local r = 1.3 + 0.8 * math.sin(d.fx.now * 11 + k)
			-- limbs and heads poking out of the dust ball
			f.pos = center + Vector3.new(math.cos(ang) * r, -2 + math.sin(ang * 1.3) * 1.2, math.sin(ang) * r)
			f.yaw = ang * 2
		end
		if d.fx.now - lastDust > 0.12 then
			lastDust = d.fx.now
			d.fx:dust(center - Vector3.new(0, 2, 0), 3)
			d.fx:sparks(center + Vector3.new(math.sin(d.fx.now * 20) * 2, 1, 0), rgb(255, 250, 220), 4)
		end
	end, function()
		cloud:Destroy()
	end)
end

H.brawlballend = function(d, c)
	for _, i in ipairs(c.who) do
		local f = d:fighter(i)
		local p = c.to[i]
		f:stopLoop()
		if p then
			f:setMotion({ t0 = d.now, t1 = d.now + 0.25, from = f.pos, to = W(p), arc = 1.5, endState = "in" })
			f.spin = { t0 = d.now, t1 = d.now + 0.25, turns = 1, axis = "tumble" }
		end
	end
end

H.tornado = function(d, c)
	local m = d:fighter(c.who)
	d.fx:tornado(function()
		return m.pos
	end, c.dur)
	local list = {}
	for _, i in ipairs(c.others) do
		if i ~= c.who then
			local f = d:fighter(i)
			f.motion = nil
			f.state = "brawl"
			f:play("flail", d.now)
			table.insert(list, { f = f, home = f.pos })
		end
	end
	d.fx:anim(c.dur, function(a)
		for k, e in ipairs(list) do
			local ang = d.fx.now * 6 + k * (math.pi * 2 / #list)
			local rise = math.sin(math.min(a, 0.85) / 0.85 * math.pi) * 5
			e.f.pos = m.pos + Vector3.new(math.cos(ang) * 3.5, rise, math.sin(ang) * 3.5)
			e.f.yaw = ang * 3
		end
	end, function()
		for _, e in ipairs(list) do
			e.f.pos = Vector3.new(e.f.pos.X, Kit.ORIGIN.Y, e.f.pos.Z)
			e.f.state = "in"
			e.f:stopLoop()
		end
	end)
	m:poke(0.8, 1.3, 0.8, d.now, 0.4)
end

H.bigcard = function(d, c)
	d.fx:bigCard(W(c.at), Kit.TierColor[c.tier] or Kit.TierColor.Legendary, c.dur)
	for _, f in ipairs(d.fighters) do
		if f.state == "in" then
			f.lookAt = W(c.at, 10)
		end
	end
end

H.ultimate = function(d, c)
	Poses.ultimate(d, c)
end

H.stars = function(d, c)
	local pts = {}
	for k, i in ipairs(c.who) do
		local f = d:fighter(i)
		local p = f.pos
		table.insert(pts, Vector3.new(p.X * 0.6, Kit.ORIGIN.Y + 16 + (k % 3) * 2, p.Z - 12))
	end
	d.fx:stars(pts)
end

H.charge = function(d, c)
	local f = d:fighter(c.who)
	local glow = Kit.part({ Name = "Charge", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Kit.TierColor[f.info.tier] or rgb(255, 255, 255), Size = Vector3.new(1, 1, 1), Transparency = 0.3 }, d.folder)
	local light = make("PointLight", { Range = 14, Brightness = 3, Color = glow.Color }, glow)
	d.fx:anim(c.dur + 2, function(a)
		local s = 1 + 3 * math.min(a * (c.dur + 2) / c.dur, 1)
		glow.Size = Vector3.new(s, s, s)
		glow.CFrame = CFrame.new(f:center() + Vector3.new(0, 0, 1.2))
		light.Brightness = 3 + 2 * math.sin(d.fx.now * 30)
	end, function()
		glow:Destroy()
	end)
	f.posing = true
	f:poke(0.8, 1.25, 0.8, d.now, 0.4)
	f:play("powerUp", d.now)
end

H.crack = function(d, c)
	d.frozen = true
	d.fx:setParticleTime(0)
	d.fx:crack(c.dur)
	d.cc.Saturation = -0.4
end

H.shear = function(d)
	-- the world is frozen, but screen and arena effects still run on the clock
	d.fx:anim(0.4, function(a)
		if not d.unsheared then
			d.arena:shear(Kit.outBack(a))
		end
	end)
end

H.blackout = function(d, c)
	d.fx:blackout(c.dur)
	d.sfx:cut()
end

H.eyes = function(d, c)
	d.fx:eyes(c.dur)
end

H.unshear = function(d)
	d.unsheared = true
	d.arena:unshear()
	d.fx:clearCrack()
	d.frozen = false
	d.fx:setParticleTime(1)
	d.cc.Saturation = d.grade[4]
	for _, f in ipairs(d.fighters) do
		f.posing = false
		f:stopLoop()
	end
end

H.whiteflash = function(d, c)
	d.fx:whiteFlash(c.dur)
	d.arena:setHype("Secret", d.now)
	d.cam:addTrauma(1)
	d.bloom.Intensity = 2.5
	d.fx:anim(c.dur, function(a)
		d.bloom.Intensity = 2.5 + (d.grade[1] - 2.5) * a
	end)
end

local FREEZE_SHOTS = {
	{ yaw = 10, dist = 9, height = 1.2, fov = 38, dutch = 22 },
	{ yaw = -30, dist = 26, height = 9, fov = 72, dutch = -22 },
	{ yaw = 35, dist = 12, height = -1.2, fov = 50, dutch = 22 },
}
H.freeze = function(d, c)
	local w = d:fighter(c.who)
	local s = FREEZE_SHOTS[c.index] or FREEZE_SHOTS[1]
	local look = w:center()
	local yaw = math.rad(s.yaw)
	local pos = look + Vector3.new(math.sin(yaw) * s.dist, s.height, math.cos(yaw) * s.dist)
	d.cam:holdAt(CFrame.lookAt(pos, look), s.fov, s.dutch)
	d.frozen = true
	d.fx:setParticleTime(0)
	d.cc.Saturation = -1
	d.cc.Contrast = 0.8
	d.fx:freezeFrame(c.index, Kit.prism(d.now, c.index * 0.3))
	d.sfx:play("heavy")
	d.cam:addTrauma(0.4)
end

H.unfreeze = function(d)
	d.cam:release()
	d.frozen = false
	d.fx:setParticleTime(1)
	d.cc.Saturation = d.grade[4]
	d.cc.Contrast = d.grade[3]
	d.fx:clearFreeze()
end

H.reassemble = function(d, c)
	local w = d:fighter(c.who)
	w.extraY = 0
	d.arena:unshear()
	d.fx:sparks(w:center(), Kit.prism(d.now), 40)
	d.fx:shock(w.pos + Vector3.new(0, 0.15, 0), Kit.prism(d.now), 30)
end

H.fakepose = function(d, c)
	local f = d:fighter(c.who)
	f.posing = true
	f.lookAt = f.pos + Vector3.new(0, 0, 10)
	f:poke(0.85, 1.25, 0.85, d.now, 0.3)
	f:play("cheer", d.now)
	d.fx:word(f:center() + Vector3.new(0, 2, 0), "WINNER?!", Kit.TierColor.Rare)
	d.fx:confetti(f:center() + Vector3.new(0, 3, 0), 30, ColorSequence.new(Kit.TierColor.Rare))
end

H.fakeframe = function(d)
	d.fx:fakeFrame()
end

H.fakecrack = function(d, c)
	d.fx:fakeCrack()
	d.cam:addTrauma(0.6)
	for _, f in ipairs(d.fighters) do
		f.posing = false
		f:stopLoop()
	end
end

H.pose = function(d, c)
	-- nobody but the winner stays for the showcase
	for i, f in ipairs(d.fighters) do
		if i ~= c.who and f.state ~= "gone" then
			d.fx:dust(f:center(), 10)
			f:hide()
		end
	end
	local finishT = d.script.length
	local dur = math.max(finishT - c.t - 0.45, 0.6)
	local w = d:fighter(c.who)
	w.posing = true
	w.lookAt = w.pos + Vector3.new(0, 0, 10)
	-- arms up! (bigger pulls flex instead)
	w:play((c.tier == "Common" or c.tier == "Rare") and "cheer" or "flex", d.now)
	Poses.play(d, c, dur)
end

H.wipe = function(d, c)
	local w = d:fighter(d.script.winner)
	local p = d.camera:WorldToViewportPoint(w:center())
	d.fx:wipe(Kit.tierColor(c.tier, d.now), Vector2.new(p.X, p.Y), 0.25, c.tier == "Secret")
	d.finishing = true
end

H.finish = function(d)
	d:complete(false)
end

return Director

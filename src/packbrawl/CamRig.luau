-- The Pack Brawl camera: planned shots (wide, focus, orbit, crane, push) blended into each other,
-- plus a trauma-based shake, FOV punches and Dutch tilt on top. Everything runs on the
-- Director's clock, so hit-stop and fast-forward slow down or speed up the camera too.

local Kit = require(script.Parent:WaitForChild("Kit"))

local CamRig = {}
CamRig.__index = CamRig

function CamRig.new(camera, tier, getFighter)
	local self = setmetatable({}, CamRig)
	self.camera = camera
	self.tier = tier
	self.numbers = Kit.TierCamera[tier] or Kit.TierCamera.Common
	self.getFighter = getFighter
	self.shot = nil
	self.prevCf = nil
	self.prevFov = self.numbers[1]
	self.trauma = 0
	self.punch = 0
	self.dutchSign = 1
	self.lastCf = camera.CFrame
	self.lastFov = camera.FieldOfView
	self.hold = nil -- a frozen camera (freeze cuts)
	return self
end

local function ringPoint(p, y)
	return Kit.world(p, y or 0)
end

-- Start a new shot. Fields come straight from the cue (see Scripts.luau).
function CamRig:setShot(c, now)
	self.prevCf = self.lastCf
	self.prevFov = self.lastFov
	self.shot = c
	self.shotT0 = now
	if c.shot == "push" then
		self.pushFrom = self.lastCf
		self.pushFov = self.lastFov
	end
end

function CamRig:addTrauma(x)
	self.trauma = math.min(1, self.trauma + x * (self.shakeScale or 1))
end

function CamRig:punchFov()
	self.punch = 1
end

function CamRig:flipDutch()
	self.dutchSign = -self.dutchSign
end

function CamRig:target(c)
	if c.who then
		local f = self.getFighter(c.who)
		if f then
			return f:center()
		end
	end
	if c.at then
		return ringPoint(c.at, 2.4)
	end
	return ringPoint({ x = 0, z = 0 }, 2.4)
end

-- The planned camera for the current shot at time now: CFrame, FOV, Dutch angle (degrees).
function CamRig:planned(now)
	local c = self.shot
	if not c then
		return CFrame.lookAt(ringPoint({ x = 0, z = 18 }, 7), ringPoint({ x = 0, z = 0 }, 2)), self.numbers[1], 0
	end
	local el = now - self.shotT0
	local fov = c.fov or self.numbers[1]
	local dutch = (c.dutch or 0)
	if c.shot == "wide" or c.shot == "focus" then
		local look = c.shot == "focus" and self:target(c) or ringPoint(c.look or { x = 0, z = 0 }, 2.2)
		local yaw = math.rad((c.yaw or 0) + (c.drift or 0) * el)
		local d, h = c.dist or 18, c.height or 7
		local pos = look + Vector3.new(math.sin(yaw) * d, h - (c.shot == "focus" and 1 or 0), math.cos(yaw) * d)
		return CFrame.lookAt(pos, look), fov, dutch
	elseif c.shot == "orbit" then
		local look = self:target(c)
		local a = Kit.inOutSine(math.clamp(el / math.max(c.dur or 1, 0.01), 0, 1))
		local yaw = math.rad((c.from or 0) + ((c.to or 90) - (c.from or 0)) * a)
		local d, h = c.dist or 10, c.height or 3
		local pos = look + Vector3.new(math.sin(yaw) * d, h - 1, math.cos(yaw) * d)
		return CFrame.lookAt(pos, look), fov, dutch
	elseif c.shot == "crane" then
		local base = ringPoint(c.at or { x = 0, z = 0 }, 0)
		local pos = base + Vector3.new(0, c.height or 3, c.dist or 14)
		local up = c.lookUp or 10
		local a = Kit.outQuad(math.clamp(el / 0.6, 0, 1))
		local look = base + Vector3.new(0, 2 + (up - 2) * a, 0)
		return CFrame.lookAt(pos, look), fov, dutch
	elseif c.shot == "push" then
		local from = self.pushFrom or self.lastCf
		local look = self:target(c)
		local a = Kit.inQuad(math.clamp(el / math.max(c.dur or 0.4, 0.01), 0, 1))
		local startPos = from.Position
		local pos = startPos:Lerp(look, 0.45 * a)
		local f = (self.pushFov or fov) + ((c.fov or 30) - (self.pushFov or fov)) * a
		return CFrame.lookAt(pos, look), f, dutch
	end
	return self.lastCf, self.lastFov, 0
end

-- Hold the camera still (freeze cuts) on a given CFrame and FOV.
function CamRig:holdAt(cf, fov, dutch)
	self.hold = { cf = cf, fov = fov, dutch = dutch }
end
function CamRig:release()
	self.hold = nil
end

function CamRig:update(now, dt)
	local cf, fov, dutch
	if self.hold then
		cf, fov, dutch = self.hold.cf, self.hold.fov, self.hold.dutch
	else
		cf, fov, dutch = self:planned(now)
		-- blend from where the camera was when the shot started
		local c = self.shot
		if c and self.prevCf and (c.blend or 0) > 0 then
			local a = Kit.outQuad(math.clamp((now - self.shotT0) / c.blend, 0, 1))
			if a < 1 then
				local p = self.prevCf.Position:Lerp(cf.Position, a)
				local look = (self.prevCf.Position + self.prevCf.LookVector * 10):Lerp(cf.Position + cf.LookVector * 10, a)
				cf = CFrame.lookAt(p, look)
				fov = self.prevFov + (fov - self.prevFov) * a
			end
		end
	end
	self.lastCf, self.lastFov = cf, fov
	-- shake: trauma squared, smooth noise at 18 Hz
	self.trauma = math.max(0, self.trauma - dt * 1.6)
	local s = self.trauma * self.trauma
	local maxMove, maxRoll = self.numbers[3], self.numbers[4]
	local n = now * 18
	local ox = math.noise(n, 1.3, 0) * 2 * maxMove * s
	local oy = math.noise(n, 7.1, 0) * 2 * maxMove * s
	local roll = math.noise(n, 13.7, 0) * 2 * maxRoll * s
	-- FOV punch: snaps in, eases back over 0.3 s
	self.punch = math.max(0, self.punch - dt / 0.3)
	local punchFov = -self.numbers[2] * Kit.outQuad(self.punch)
	local finalCf = cf * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, math.rad(dutch * self.dutchSign + roll))
	self.camera.CFrame = finalCf
	self.camera.FieldOfView = math.clamp(fov + punchFov, 15, 100)
end

return CamRig

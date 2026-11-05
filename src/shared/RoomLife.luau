-- RoomLife: the menu room reacts to your mouse. Client only.
--
-- Point at things in the room and they answer: binders slide half out of the Deck Shelf, balloons
-- bob on their strings, Pickles waves (and his eyes follow your cursor), trophies lift and turn,
-- the radio bops to its own beat, the fire flares, the clock's hands swing round to your real
-- time, curtains and pennants sway, the dance floor lights up under the cursor. Click (or tap on a
-- phone) for a bigger answer: a binder pops, a box hops, Pickles jumps and spins, a candle puffs
-- out and relights, a shooting star crosses the window...
-- Every now and then something fidgets on its own, and Pickles blinks.
--
-- Nothing here changes the room's parts for good: every part is moved from where it was when the
-- room loaded, and everything snaps back when you sit down at the table (RoomLife.rest). The
-- room's parts aren't renamed or regrouped either; props are found by part name and grouped by
-- distance, so a room that was moved around a bit in Studio still works. (The door and the
-- painting over the fireplace are left alone: they become the Plaza door and the Campaign map.)
--
--   RoomLife.attach(room)                 -> number of props found (call once)
--   RoomLife.update(dt, mouse, active)    -> the prop under the mouse (or nil). mouse = viewport
--                                            point or nil; active = false puts everything back
--   RoomLife.click(pos, isScreen)         -> the prop that was clicked (or nil); pokes it
--   RoomLife.rest()                       -- everything back where it was, right now
--   RoomLife.fireBoost(), RoomLife.discoBoost() -- multipliers for the room's fire and disco ball
--   RoomLife.tileGlow(tile), RoomLife.tilesBusy() -- how white a dance floor tile should glow
--   RoomLife.props, RoomLife.kinds, RoomLife.idleFidgets -- (for tests)

local RoomLife = {}

local Shared = script.Parent
local function tryRequire(name)
	local m = Shared:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, mod = pcall(require, m)
	return ok and mod or nil
end
local TableSounds = tryRequire("TableSounds")
local Settings = tryRequire("Settings")

local UP = Vector3.new(0, 1, 0)
local TAU = math.pi * 2
local ID = CFrame.new()

local props = {} -- every prop
local kinds = {} -- kind -> { prop, ... }
local partToProp = {} -- [BasePart] = prop
local awake = {} -- [prop] = true while it moves
local hovered = nil
local clock = 0
local roomModel = nil
local rayParams = nil
local fxFolder = nil
local ripples = {} -- dance floor ripples { pos, t, strength }
local nextIdle = 18
local lastHoverSound = -1
local resting = true

RoomLife.props = props
RoomLife.kinds = kinds
RoomLife.idleFidgets = true -- something fidgets on its own every 12-26 s (tests turn it off)

---------------------------------------------------------------------------
-- Small math helpers
---------------------------------------------------------------------------
local function axisSnap(v)
	if math.abs(v.X) >= math.abs(v.Z) then
		return Vector3.new(v.X >= 0 and 1 or -1, 0, 0)
	end
	return Vector3.new(0, 0, v.Z >= 0 and 1 or -1)
end

local function rot(axis, angle)
	if angle == 0 then
		return ID
	end
	return CFrame.fromAxisAngle(axis, angle)
end

-- A turn (or any CFrame) around a point instead of around the world's origin.
local function about(point, cf)
	return CFrame.new(point) * cf * CFrame.new(-point)
end

local function clamp01(x)
	return math.clamp(x, 0, 1)
end

local function ease(u)
	u = clamp01(u)
	return u * u * (3 - 2 * u)
end

-- A hop: 0 -> 1 -> 0 over `len` seconds.
local function hop(t, len)
	if not t or t < 0 or t > len then
		return 0
	end
	local u = t / len
	return 4 * u * (1 - u)
end

-- A wobble that dies away.
local function ring(t, rate, freq)
	if not t or t < 0 then
		return 0
	end
	return math.exp(-rate * t) * math.sin(freq * t)
end

-- 1 right away, fading to 0.
local function fade(t, rate)
	if not t or t < 0 then
		return 0
	end
	return math.exp(-rate * t)
end

-- The two ends of a rod-shaped part (its long side), lower end first.
local function rodEnds(part)
	local s = part.Size
	local v
	if s.X >= s.Y and s.X >= s.Z then
		v = Vector3.new(s.X / 2, 0, 0)
	elseif s.Y >= s.Z then
		v = Vector3.new(0, s.Y / 2, 0)
	else
		v = Vector3.new(0, 0, s.Z / 2)
	end
	local a, b = part.CFrame * v, part.CFrame * -v
	if a.Y <= b.Y then
		return a, b
	end
	return b, a
end

local function meshOf(part)
	return part:FindFirstChildOfClass("SpecialMesh")
end

---------------------------------------------------------------------------
-- Sound (the table's sound bank, at the player's sound effects volume)
---------------------------------------------------------------------------
local function sfx(s)
	if not (s and TableSounds) then
		return
	end
	local vol = Settings and Settings.volume("sfx") or 1
	if vol <= 0 then
		return
	end
	pcall(TableSounds.play, s[1], { volume = (s[2] or 1) * vol, pitch = s[3] or 1 })
end

---------------------------------------------------------------------------
-- What each kind of prop does.
--   move(p, c)      -> CFrame for the whole prop, turned around p.pivot (nil = still)
--   extra(p, e, c)  -> CFrame for one part, in the room's frame, before the whole-prop move
--   effects(p, c)   -- lights, fire, mesh sizes, colors
--   restFx(p)       -- put those back
-- c = { t = clock, h = hover amount (0..1, springy), pk = seconds since the last poke (or nil),
--       amp = how hard it was poked }
---------------------------------------------------------------------------
local DEFS = {}
local ORDER = {} -- the order props are found in (a part goes to the first kind that claims it)

local function def(kind, d)
	d.kind = kind
	DEFS[kind] = d
	table.insert(ORDER, d)
	return d
end

-- Deck Shelf ----------------------------------------------------------------
def("binder", {
	scope = "DeckShelf", anchor = "Binder", with = { "BinderLabel", "BinderRing" }, radius = 1.5,
	pivot = "bottomOut", neighbors = 1.9, idle = true,
	hoverSound = { "whooshShort", 0.12, 2.2 }, clickSound = { "thudSmall", 0.4, 1.6 },
	move = function(p, c)
		local slide = 0.55 * c.h + 0.6 * c.amp * hop(c.pk, 0.45)
		local tilt = 0.11 * c.h + 0.16 * c.amp * ring(c.pk, 4, 16)
		return CFrame.new(p.out * slide) * rot(p.tipOut, tilt)
	end,
})

def("cardbox", {
	scope = "DeckShelf", anchor = "CardBox", pivot = "bottom", idle = true,
	clickSound = { "thudSmall", 0.4, 1.3 },
	move = function(p, c)
		local lift = 0.14 * c.h + 0.9 * c.amp * hop(c.pk, 0.5)
		return CFrame.new(0, lift, 0) * rot(UP, 0.08 * c.h * math.sin(3 * c.t + p.phase) + 0.7 * c.amp * ring(c.pk, 3, 9))
	end,
})

def("shelflamp", {
	scope = "DeckShelf", anchor = "ShelfLampShade", with = { "ShelfLampPole", "ShelfLampBase" }, radius = 3,
	pivot = "bottom",
	setup = function(p)
		p.light = p.anchor:FindFirstChildWhichIsA("Light")
		p.lightBase = p.light and p.light.Brightness
	end,
	move = function(p, c)
		return rot(p.tipOut, 0.07 * c.h)
	end,
	effects = function(p, c)
		if p.light then
			local flicker = (c.pk and c.pk < 0.45 and math.floor(c.pk * 14) % 2 == 0) and 0.1 or 1
			p.light.Brightness = p.lightBase * (1 + 1.4 * c.h) * flicker
		end
	end,
	restFx = function(p)
		if p.light then
			p.light.Brightness = p.lightBase
		end
	end,
})

-- Pack Party -----------------------------------------------------------------
def("balloon", {
	scope = "PackParty", anchor = "Balloon", with = { "BalloonKnot", "BalloonString" }, radius = 0.6, flat = true,
	pivot = "bottom", neighbors = 2.5, idle = true,
	clickSound = { "boing2", 0.35, 1.3 },
	move = function(p, c)
		local a = 0.09 * c.h * math.sin(2.1 * c.t + p.phase) + 0.12 * c.amp * ring(c.pk, 2, 7)
		local b = 0.06 * c.h * math.sin(1.6 * c.t + p.phase * 2)
		local lift = 0.25 * c.h + 0.9 * c.amp * hop(c.pk, 0.6)
		return CFrame.new(0, lift, 0) * rot(Vector3.new(1, 0, 0), a) * rot(Vector3.new(0, 0, 1), b)
	end,
})

local function beat(t)
	return math.abs(math.sin(math.pi * 2 * t)) ^ 6 -- two thumps a second
end

def("speaker", {
	scope = "PackParty", anchor = "Speaker", with = { "SpeakerCone", "SpeakerDust" }, radius = 3,
	pivot = "bottom", clickSound = { "thud", 0.5, 0.6 },
	setup = function(p)
		local sum, n = Vector3.new(), 0
		for _, e in ipairs(p.parts) do
			if e.part ~= p.anchor then
				sum += e.base.Position
				n += 1
			end
		end
		if n > 0 then
			p.out = axisSnap(sum / n - p.anchor.Position)
		end
	end,
	move = function(p, c)
		return CFrame.new(0, 0.05 * c.h * beat(c.t) + 0.3 * c.amp * hop(c.pk, 0.25), 0)
	end,
	extra = function(p, e, c)
		if e.part == p.anchor then
			return nil
		end
		return CFrame.new(p.out * (0.12 * c.h * beat(c.t) + 0.32 * c.amp * fade(c.pk, 5)))
	end,
	onClick = function(p)
		RoomLife.ripple(p.anchor.Position, 1)
	end,
})

def("discoball", {
	scope = "PackParty", anchor = "DiscoBall", still = true,
	clickSound = { "swishLong", 0.4, 1.4 },
})

def("discotile", {
	scope = "PackParty", anchor = "DiscoTile", still = true, springK = 260,
	clickSound = { "ding", 0.25, 1.4 },
	onEnter = function(p)
		RoomLife.ripple(p.anchor.Position, 0.45)
	end,
	onClick = function(p)
		RoomLife.ripple(p.anchor.Position, 1)
	end,
})

-- Pack Shelf jars (the packs themselves belong to the Pack Shelf)
def("packjar", {
	scope = "PackShelf", anchor = "PackJar", with = { "PackJarLid", "MiniPack" }, radius = 1.6,
	pivot = "bottom", clickSound = { "boing2", 0.35, 1.8 }, idle = true,
	extra = function(p, e, c)
		if e.name == "PackJarLid" then
			local lift = 0.14 * c.h + 1.1 * c.amp * hop(c.pk, 0.55)
			return about(e.base.Position, CFrame.new(0, lift, 0) * rot(p.side, 0.1 * c.h + 0.5 * c.amp * ring(c.pk, 3, 10)))
		elseif e.name == "MiniPack" then
			local j = 0.03 * c.h * math.sin(9 * c.t + e.phase) + 0.25 * c.amp * hop((c.pk or -1) - 0.08, 0.35)
			return CFrame.new(0, j, 0)
		end
		return nil
	end,
})

-- Shop counter -----------------------------------------------------------------
def("pickles", {
	scope = "ShopCounter", anchor = "Pickles", radius = 5,
	with = { "PickleBump", "PicklesApron", "PicklesHat", "PicklesHatBand", "PicklesMustache", "PicklesSmile", "PicklesEye", "PicklesPupil", "PicklesArm", "PicklesHand" },
	pivot = "bottom", always = true, idle = true, clickSound = { "boing", 0.45, 1.0 },
	setup = function(p)
		p.nextBlink = 2 + math.random() * 3
		local cx = p.anchor.Position.X
		-- he waves with the arm nearer the middle of the room
		local waveLeft = math.abs((p.anchor.Position + p.side).X) > math.abs((p.anchor.Position - p.side).X)
		for _, e in ipairs(p.parts) do
			if e.name == "PicklesArm" or e.name == "PicklesHand" then
				local s = (e.base.Position - p.anchor.Position):Dot(p.side)
				e.wave = (s < 0) == waveLeft
			end
			if e.name == "PicklesEye" or e.name == "PicklesPupil" then
				e.mesh = meshOf(e.part)
				e.meshScale = e.mesh and e.mesh.Scale
			end
		end
		for _, e in ipairs(p.parts) do
			if e.name == "PicklesArm" and e.wave then
				local hand = nil
				for _, h in ipairs(p.parts) do
					if h.name == "PicklesHand" and h.wave then
						hand = h
					end
				end
				if hand then
					p.shoulder = e.base.Position * 2 - hand.base.Position
				end
			end
		end
		p.shoulder = p.shoulder or p.anchor.Position
		local _ = cx
	end,
	move = function(p, c)
		local sway = 0.05 * c.h * math.sin(3 * c.t)
		local lift = 0.1 * c.h * math.abs(math.sin(5 * c.t)) + 1.3 * c.amp * hop(c.pk, 0.5)
		local spin = (c.amp >= 0.9 and c.pk) and TAU * ease(c.pk / 0.55) or 0
		return CFrame.new(0, lift, 0) * rot(UP, spin) * rot(p.out, sway)
	end,
	extra = function(p, e, c)
		if e.wave then
			local raise = 1.05 * c.h
			if raise <= 0.001 then
				return nil
			end
			return about(p.shoulder, rot(p.out, 0.35 * c.h * math.sin(10 * c.t)) * rot(p.out:Cross(UP), raise))
		elseif e.name == "PicklesPupil" and p.look then
			local d = p.look - e.base.Position
			d -= p.out * d:Dot(p.out)
			local m = d.Magnitude
			if m > 1e-3 then
				return CFrame.new(d.Unit * math.min(0.12, m * 0.04))
			end
		end
		return nil
	end,
	effects = function(p, c)
		-- a blink now and then
		local blink = 1
		if c.t >= p.nextBlink then
			local u = (c.t - p.nextBlink) / 0.16
			if u >= 1 then
				p.nextBlink = c.t + 2.5 + math.random() * 4
				if math.random() < 0.2 then
					p.nextBlink = c.t + 0.25 -- a double blink
				end
			else
				blink = 0.12 + 0.88 * math.abs(1 - 2 * u)
			end
		end
		for _, e in ipairs(p.parts) do
			if e.mesh and e.meshScale then
				e.mesh.Scale = Vector3.new(e.meshScale.X, e.meshScale.Y * blink, e.meshScale.Z)
			end
		end
	end,
	restFx = function(p)
		for _, e in ipairs(p.parts) do
			if e.mesh and e.meshScale then
				e.mesh.Scale = e.meshScale
			end
		end
	end,
})

def("register", {
	scope = "ShopCounter", anchor = "Register", with = { "RegisterScreen", "RegisterDigits", "RegisterKey", "RegisterDrawer" }, radius = 2.2,
	pivot = "bottom", clickSound = { "ding", 0.5, 1.25 },
	setup = function(p)
		for _, e in ipairs(p.parts) do
			if e.name == "RegisterDigits" then
				p.digits = e.part
				p.digitColor = e.part.Color
			end
		end
	end,
	move = function(p, c)
		return CFrame.new(0, 0.2 * c.amp * hop(c.pk, 0.22), 0)
	end,
	extra = function(p, e, c)
		if e.name == "RegisterDrawer" then
			local pop = 0
			if c.pk and c.pk >= 0 then
				pop = c.pk < 0.1 and c.pk / 0.1 or math.exp(-(c.pk - 0.1) * 2.2)
			end
			return CFrame.new(p.out * (0.3 * c.h + 0.85 * c.amp * pop))
		elseif e.name == "RegisterKey" then
			local press = hop((c.pk or -1) - e.phase * 0.25, 0.12)
			return CFrame.new(0, -0.06 * press * c.amp, 0)
		end
		return nil
	end,
	effects = function(p, c)
		if p.digits then
			local f = c.h * (0.5 + 0.5 * math.sin(c.t * 23))
			p.digits.Color = p.digitColor:Lerp(Color3.new(1, 1, 1), 0.55 * f)
		end
	end,
	restFx = function(p)
		if p.digits then
			p.digits.Color = p.digitColor
		end
	end,
})

def("candyjar", {
	scope = "ShopCounter", anchor = "Jar", with = { "JarCandy" }, radius = 0.6,
	pivot = "bottom", neighbors = 1.3, idle = true, clickSound = { "ding", 0.25, 2.3 },
	move = function(p, c)
		return CFrame.new(0, 0.45 * c.amp * hop(c.pk, 0.35), 0) * rot(p.side, 0.06 * c.h * math.sin(10 * c.t + p.phase) + 0.12 * c.amp * ring(c.pk, 4, 15))
	end,
	extra = function(p, e, c)
		if e.name == "JarCandy" and c.pk then
			return CFrame.new(0, 0.12 * c.amp * hop(c.pk - 0.1, 0.25), 0)
		end
		return nil
	end,
})

def("packbox", {
	scope = "ShopCounter", anchor = "PackBox", pivot = "bottomOut", neighbors = 1.3, idle = true,
	clickSound = { "thudSmall", 0.35, 1.5 },
	move = function(p, c)
		return CFrame.new(0, 0.55 * c.amp * hop(c.pk, 0.4), 0) * rot(p.tipOut, 0.17 * c.h + 0.12 * c.amp * ring(c.pk, 4, 14))
	end,
})

def("displaypack", {
	scope = "ShopCounter", anchor = "DisplayPack", pivot = "bottom", neighbors = 0.6,
	clickSound = { "swish", 0.3, 1.2 },
	move = function(p, c)
		local spin = (c.amp >= 0.9 and c.pk) and TAU * ease(c.pk / 0.5) or 0
		return CFrame.new(0, 0.3 * c.h + 0.5 * c.amp * hop(c.pk, 0.5), 0) * rot(UP, spin)
	end,
})

def("awning", {
	scope = "ShopCounter", anchor = "Awning", with = { "AwningScallop" }, radius = 2.2,
	pivot = "topBack",
	onEnter = function(p)
		-- a wave runs along all the stripes from the one you touched
		for _, q in ipairs(kinds.awning or {}) do
			local d = math.abs((q.anchor.Position - p.anchor.Position):Dot(p.side))
			RoomLife.poke(q, 0.6, d * 0.07)
		end
	end,
	move = function(p, c)
		return rot(p.side, 0.025 * c.h * math.sin(6 * c.t + p.phase) + 0.12 * c.amp * ring(c.pk, 3, 12))
	end,
})

-- Trophy Wall -----------------------------------------------------------------
def("trophy", {
	scope = "TrophyWall", anchor = "TrophyCup", with = { "TrophyBase", "TrophyStem", "TrophyRim", "TrophyHandle" }, radius = 1.7,
	pivot = "bottom", idle = true, clickSound = { "ding", 0.45, 1.6 },
	setup = function(p)
		for _, e in ipairs(p.parts) do
			if e.name ~= "TrophyBase" then
				e.refl = e.part.Reflectance
			end
		end
	end,
	move = function(p, c)
		local spin = (c.amp >= 0.9 and c.pk) and TAU * ease(c.pk / 0.6) or 0
		local turn = 0.5 * c.h * math.sin(2 * c.t + p.phase)
		return CFrame.new(0, 0.22 * c.h + 0.7 * c.amp * hop(c.pk, 0.6), 0) * rot(UP, turn + spin)
	end,
	effects = function(p, c)
		for _, e in ipairs(p.parts) do
			if e.refl then
				e.part.Reflectance = math.min(1, e.refl + 0.3 * c.h)
			end
		end
	end,
	restFx = function(p)
		for _, e in ipairs(p.parts) do
			if e.refl then
				e.part.Reflectance = e.refl
			end
		end
	end,
	onClick = function(p)
		local s = Instance.new("Sparkles")
		s.SparkleColor = Color3.fromRGB(255, 230, 140)
		s.Parent = p.anchor
		task.delay(0.9, function()
			s:Destroy()
		end)
	end,
})

def("pennant", {
	scope = "TrophyWall", anchor = "Pennant", pivot = "top", neighbors = 3.2, idle = true,
	move = function(p, c)
		local a = c.h * (0.17 + 0.09 * math.sin(7 * c.t + p.phase)) + 0.35 * c.amp * math.max(0, ring(c.pk, 2.5, 9))
		return rot(p.swingOut, math.max(0, a))
	end,
})

def("certificate", {
	scope = "TrophyWall", anchor = "Certificate", with = { "Seal" }, radius = 1.4,
	pivot = "top", clickSound = { "swish", 0.25, 0.8 },
	move = function(p, c)
		return rot(p.out, 0.07 * c.h + 0.25 * c.amp * ring(c.pk, 2.2, 7))
	end,
})

-- Settings radio -----------------------------------------------------------------
def("radio", {
	scope = "Radio", anchor = "RadioBox", radius = 4.5,
	with = { "RadioTop", "RadioGrille", "RadioDial", "RadioNeedle", "RadioKnob", "RadioAntenna", "RadioAntennaTip", "MusicNote", "MusicNoteHead" },
	pivot = "bottom", idle = true, clickSound = { "scratch", 0.35, 1.0 },
	setup = function(p)
		for _, e in ipairs(p.parts) do
			if e.name == "RadioAntenna" then
				p.antennaBase = rodEnds(e.part)
			end
		end
		p.antennaBase = p.antennaBase or p.anchor.Position
	end,
	move = function(p, c)
		local bounce = 0.07 * c.h * beat(c.t) + 0.45 * c.amp * hop(c.pk, 0.35)
		return CFrame.new(0, bounce, 0) * rot(p.out, 0.035 * c.h * math.sin(TAU * c.t))
	end,
	extra = function(p, e, c)
		local n = e.name
		if n == "RadioNeedle" then
			local sweep = 0.28 * c.h * math.sin(1.3 * c.t) + 0.4 * c.amp * ring(c.pk, 1.8, 8)
			return CFrame.new(p.side * sweep)
		elseif n == "RadioKnob" then
			return about(e.base.Position, rot(p.out, 1.4 * c.h * math.sin(2 * c.t + e.phase) + 2.5 * c.amp * ring(c.pk, 2, 6)))
		elseif n == "RadioAntenna" or n == "RadioAntennaTip" then
			return about(p.antennaBase, rot(p.out, 0.12 * c.h * math.sin(8 * c.t) + 0.3 * c.amp * ring(c.pk, 3, 13)))
		elseif n == "MusicNote" or n == "MusicNoteHead" then
			local ph = e.base.Position.Y * 3
			return CFrame.new(p.side * (0.15 * c.h * math.sin(1.7 * c.t + ph)) + UP * (c.h * (0.35 + 0.2 * math.sin(2.4 * c.t + ph))))
		end
		return nil
	end,
})

-- The room itself -----------------------------------------------------------------
def("fireplace", {
	scope = "Structure", anchor = "Hearth", radius = 9, still = true,
	with = { "Log", "Grate", "GrateBar", "Embers", "FireBack", "FireFloor", "FirePillar", "FireLintel", "Mantle", "MantleTrim" },
	hoverSound = { "whooshShort", 0.1, 0.5 }, clickSound = { "whoosh", 0.5, 0.7 },
	setup = function(p)
		local room = p.anchor.Parent
		local fl = room and room:FindFirstChild("FireLight")
		p.fire = fl and fl:FindFirstChildOfClass("Fire")
		p.fireSize = p.fire and p.fire.Size
		p.fireHeat = p.fire and p.fire.Heat
		for _, e in ipairs(p.parts) do
			if e.name == "Embers" then
				p.embers = e.part
				p.emberColor = e.part.Color
			end
		end
	end,
	effects = function(p, c)
		local k = 0.45 * c.h + 1.2 * c.amp * fade(c.pk, 2.2)
		p.boost = 1 + k
		if p.fire then
			p.fire.Size = p.fireSize * (1 + 0.45 * k)
			p.fire.Heat = p.fireHeat * (1 + 0.6 * k)
		end
		if p.embers then
			p.embers.Color = p.emberColor:Lerp(Color3.fromRGB(255, 220, 120), clamp01(0.6 * k))
		end
	end,
	restFx = function(p)
		p.boost = 1
		if p.fire then
			p.fire.Size = p.fireSize
			p.fire.Heat = p.fireHeat
		end
		if p.embers then
			p.embers.Color = p.emberColor
		end
	end,
})

def("candle", {
	scope = "Structure", anchor = "Candle", with = { "CandleHolder", "Flame" }, radius = 1.3, still = true,
	clickSound = { "whooshShort", 0.35, 1.8 },
	setup = function(p)
		for _, e in ipairs(p.parts) do
			if e.name == "Flame" then
				p.flame = meshOf(e.part)
				p.flameScale = p.flame and p.flame.Scale
			end
		end
	end,
	effects = function(p, c)
		if not p.flame then
			return
		end
		local s = 1 + 0.45 * c.h * (0.8 + 0.2 * math.sin(c.t * 17 + p.phase))
		local pk = c.amp >= 0.9 and c.pk or nil
		if pk then -- puffed out, then it lights again
			if pk < 0.18 then
				s *= 1 - pk / 0.18
			elseif pk < 0.9 then
				s = 0
			elseif pk < 1.3 then
				s *= 1 + 0.5 * math.sin((pk - 0.9) / 0.4 * math.pi)
			end
		end
		local b = p.flameScale
		p.flame.Scale = Vector3.new(b.X * s, b.Y * s * (1 + 0.25 * c.h), b.Z * s)
	end,
	restFx = function(p)
		if p.flame then
			p.flame.Scale = p.flameScale
		end
	end,
})

def("clock", {
	scope = "Structure", anchor = "Clock", with = { "ClockFace", "ClockHand" }, radius = 1.6,
	pivot = "bottom", clickSound = { "ding", 0.4, 0.75 },
	setup = function(p)
		for _, e in ipairs(p.parts) do
			if e.name == "ClockFace" then
				p.face = e.base.Position
			elseif e.name == "ClockHand" then
				e.hour = e.part.Size.Y > e.part.Size.X -- the short upright one points at 12, the other at 3
			end
		end
		p.face = p.face or p.anchor.Position
	end,
	move = function(p, c)
		local tick = 0.02 * c.h * math.sin(math.pi * c.t)
		return CFrame.new(0, 0.35 * c.amp * hop(c.pk, 0.35), 0) * rot(p.out, tick + 0.1 * c.amp * ring(c.pk, 3, 12))
	end,
	extra = function(p, e, c)
		if e.name ~= "ClockHand" or c.h <= 0.001 then
			return nil
		end
		-- the hands swing round to the time on your computer
		local hours, mins = 10, 10
		local ok, now = pcall(function()
			return os.date("*t")
		end)
		if ok and type(now) == "table" then
			hours, mins = now.hour or hours, now.min or mins
		end
		local target
		if e.hour then
			target = TAU * ((hours % 12) + mins / 60) / 12
		else
			target = TAU * mins / 60 - math.pi / 2
			if target < 0 then
				target += TAU
			end
		end
		return about(p.face, rot(-p.out, target * c.h))
	end,
})

def("mantletrophy", {
	scope = "Structure", anchor = "TrophySmallCup", with = { "TrophySmall", "TrophySmallBase" }, radius = 1.2,
	pivot = "bottom", clickSound = { "ding", 0.35, 1.9 },
	move = function(p, c)
		local spin = (c.amp >= 0.9 and c.pk) and TAU * ease(c.pk / 0.5) or 0
		return CFrame.new(0, 0.12 * c.h + 0.4 * c.amp * hop(c.pk, 0.5), 0) * rot(UP, 0.6 * c.h * math.sin(2 * c.t) + spin)
	end,
})

local function poster(anchor)
	return {
		scope = "Structure", anchor = anchor, with = { "PosterFrame" }, radius = 1.5, pivot = "top",
		clickSound = { "swish", 0.25, 0.9 },
		move = function(p, c)
			return rot(p.swingOut, 0.035 * c.h + 0.05 * c.amp * math.max(0, ring(c.pk, 2, 6))) * rot(p.out, 0.025 * c.h + 0.08 * c.amp * ring(c.pk, 2, 5))
		end,
	}
end
def("poster", poster("Poster"))
def("poster2", poster("Poster2"))

def("lamp", {
	scope = "Structure", anchor = "LampShade", with = { "LampCord", "LampShadeTop", "LampBulb" }, radius = 1.5, flat = true,
	pivot = "top", idle = true,
	move = function(p, c)
		local a = 0.05 * c.h * math.sin(1.9 * c.t + p.phase) + 0.16 * c.amp * ring(c.pk, 1.1, 2.6)
		local b = 0.03 * c.h * math.sin(1.3 * c.t + p.phase)
		return rot(Vector3.new(1, 0, 0), a) * rot(Vector3.new(0, 0, 1), b)
	end,
})

def("plant", {
	scope = "Structure", anchor = "Pot", with = { "PotRim", "Soil", "Leaf", "LeafTop" }, radius = 3.5, flat = true,
	pivot = "bottom", idle = true, hoverSound = { "swish", 0.08, 0.7 }, clickSound = { "swish", 0.3, 0.6 },
	setup = function(p)
		for _, e in ipairs(p.parts) do
			if e.name == "Leaf" or e.name == "LeafTop" then
				e.root = e.base.Position - e.base.UpVector * (e.part.Size.Y / 2)
				local a = e.phase * 7
				e.axis = Vector3.new(math.cos(a), 0, math.sin(a))
			end
		end
	end,
	move = function(p, c)
		return rot(p.side, 0.03 * c.h * math.sin(2.5 * c.t + p.phase) + 0.06 * c.amp * ring(c.pk, 3, 14))
	end,
	extra = function(p, e, c)
		if not e.root then
			return nil
		end
		return about(e.root, rot(e.axis, 0.14 * c.h * math.sin(7 * c.t + e.phase * 9) + 0.32 * c.amp * ring(c.pk, 3.5, 16 + e.phase * 4)))
	end,
})

def("curtain", {
	scope = "Structure", anchor = "Curtain", with = { "CurtainFold", "Tieback" }, radius = 2.2,
	pivot = "top", neighbors = 9, idle = true,
	move = function(p, c)
		local a = c.h * (0.05 + 0.025 * math.sin(2 * c.t + p.phase)) + 0.1 * c.amp * math.max(0, ring(c.pk, 1.8, 5))
		return rot(p.swingOut, math.max(0, a))
	end,
})

def("window", {
	scope = "Structure", anchor = "Glass", radius = 4.2, still = true,
	with = { "NightSky", "Star", "Moon", "MoonShade", "Frame", "Sill" },
	clickSound = { "swishLong", 0.3, 1.7 },
	setup = function(p)
		for _, e in ipairs(p.parts) do
			if e.name == "Star" then
				e.color = e.part.Color
			elseif e.name == "NightSky" then
				p.sky = e.part
			end
		end
	end,
	effects = function(p, c)
		for _, e in ipairs(p.parts) do
			if e.color then
				local tw = c.h * (0.5 + 0.5 * math.sin(5 * c.t + e.phase * 11))
				e.part.Color = e.color:Lerp(Color3.fromRGB(150, 190, 255), 0.7 * tw)
			end
		end
		-- the shooting star
		local s = p.shooter
		if s then
			local u = (c.t - s.start) / 0.75
			if u >= 1 then
				s.part:Destroy()
				p.shooter = nil
			else
				local pos = s.from:Lerp(s.to, ease(u))
				s.part.CFrame = CFrame.lookAt(pos, pos + (s.to - s.from))
				s.part.Transparency = 0.1 + 0.9 * math.max(0, u * 2 - 1)
			end
		end
	end,
	restFx = function(p)
		for _, e in ipairs(p.parts) do
			if e.color then
				e.part.Color = e.color
			end
		end
		if p.shooter then
			p.shooter.part:Destroy()
			p.shooter = nil
		end
	end,
	onClick = function(p)
		if not (p.sky and fxFolder) or p.shooter then
			return
		end
		local sky = p.sky.CFrame
		local w, h = p.sky.Size.X, p.sky.Size.Y
		local front = p.out * 0.06
		local from = (sky * Vector3.new(-w * 0.42, h * 0.38, 0)) + front
		local to = (sky * Vector3.new(w * 0.3, -h * 0.05, 0)) + front
		local part = Instance.new("Part")
		part.Name = "ShootingStar"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 250, 220)
		part.Size = Vector3.new(0.09, 0.09, 0.9)
		part.CFrame = CFrame.lookAt(from, to)
		part.Parent = fxFolder
		p.shooter = { part = part, from = from, to = to, start = clock }
	end,
})

---------------------------------------------------------------------------
-- Finding the props
---------------------------------------------------------------------------
local function containerFor(scope)
	if not roomModel then
		return nil
	end
	if scope == "Structure" then
		return roomModel:FindFirstChild("Structure")
	end
	local stations = roomModel:FindFirstChild("Stations")
	if not stations then
		return nil
	end
	if scope == "PackShelf" then
		local pp = stations:FindFirstChild("PackParty")
		return pp and pp:FindFirstChild("PackShelf")
	end
	return stations:FindFirstChild(scope)
end

-- The box around a prop's parts (in the room's frame).
local function bounds(entries)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, e in ipairs(entries) do
		local s = e.part.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local q = e.base * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
					lo = Vector3.new(math.min(lo.X, q.X), math.min(lo.Y, q.Y), math.min(lo.Z, q.Z))
					hi = Vector3.new(math.max(hi.X, q.X), math.max(hi.Y, q.Y), math.max(hi.Z, q.Z))
				end
			end
		end
	end
	return lo, hi
end

local function pivotFor(p, kind)
	local lo, hi = p.lo, p.hi
	local mid = (lo + hi) / 2
	local half = (hi - lo) / 2
	local alongOut = math.abs(half:Dot(p.out))
	if kind == "bottom" then
		return Vector3.new(mid.X, lo.Y, mid.Z)
	elseif kind == "top" then
		return Vector3.new(mid.X, hi.Y, mid.Z)
	elseif kind == "bottomOut" then
		return Vector3.new(mid.X, lo.Y, mid.Z) + p.out * alongOut
	elseif kind == "topBack" then
		return Vector3.new(mid.X, hi.Y, mid.Z) - p.out * alongOut
	end
	return mid
end

local function hashPhase(v)
	local x = math.sin(v.X * 12.9898 + v.Y * 78.233 + v.Z * 37.719) * 43758.5453
	return x - math.floor(x)
end

local function build(d, container)
	local anchors = {}
	local wanted = {}
	for _, n in ipairs(d.with or {}) do
		wanted[n] = true
	end
	local companions = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("BasePart") and not partToProp[child] then
			if child.Name == d.anchor then
				table.insert(anchors, child)
			elseif wanted[child.Name] then
				table.insert(companions, child)
			end
		end
	end
	if #anchors == 0 then
		return
	end
	local list = {}
	for _, a in ipairs(anchors) do
		local p = { kind = d.kind, def = d, anchor = a, parts = { { part = a, base = a.CFrame, name = a.Name, phase = 0 } }, h = 0, v = 0, target = 0, amp = 0 }
		table.insert(list, p)
	end
	local radius = d.radius or 1
	for _, part in ipairs(companions) do
		local best, bestD = nil, radius
		for _, p in ipairs(list) do
			local dv = part.Position - p.anchor.Position
			if d.flat then
				dv = Vector3.new(dv.X, 0, dv.Z)
			end
			local dist = dv.Magnitude
			if dist <= bestD then
				best, bestD = p, dist
			end
		end
		if best then
			table.insert(best.parts, { part = part, base = part.CFrame, name = part.Name, phase = hashPhase(part.Position), fixed = d.fixed and d.fixed[part.Name] or nil })
		end
	end
	local center = Vector3.new(0, 0, 0)
	for _, p in ipairs(list) do
		p.phase = hashPhase(p.anchor.Position) * TAU
		p.lo, p.hi = bounds(p.parts)
		local mid = (p.lo + p.hi) / 2
		p.out = axisSnap(Vector3.new(center.X - mid.X, 0, center.Z - mid.Z))
		if p.out.Magnitude < 0.5 then
			p.out = Vector3.new(0, 0, 1)
		end
		p.side = UP:Cross(p.out)
		if d.setup then
			d.setup(p)
		end
		-- (setup may turn `out` around, so these come after it)
		p.side = UP:Cross(p.out)
		p.tipOut = UP:Cross(p.out) -- turning around this tips a prop's top toward the room
		p.swingOut = p.out:Cross(UP) -- turning around this swings a hanging prop's bottom toward the room
		p.pivot = pivotFor(p, d.pivot)
		for _, e in ipairs(p.parts) do
			partToProp[e.part] = p
		end
		table.insert(props, p)
	end
	kinds[d.kind] = list
	-- the props next to each other (they wobble a little when a neighbour is touched)
	if d.neighbors then
		for _, p in ipairs(list) do
			p.near = {}
			for _, q in ipairs(list) do
				if q ~= p and (q.anchor.Position - p.anchor.Position).Magnitude <= d.neighbors then
					table.insert(p.near, q)
				end
			end
		end
	end
end

function RoomLife.attach(room)
	if roomModel then
		return #props
	end
	roomModel = room
	for _, d in ipairs(ORDER) do
		local container = containerFor(d.scope)
		if container then
			build(d, container)
		end
	end
	rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { room }
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "RoomLifeFx"
	fxFolder.Parent = workspace
	return #props
end

---------------------------------------------------------------------------
-- Moving them
---------------------------------------------------------------------------
local function wake(p)
	awake[p] = true
	resting = false
end

local function place(p)
	local d = p.def
	if d.still then
		return
	end
	local pk = p.pk
	if pk and pk < 0 then
		pk = nil -- (a poke that hasn't started yet)
	end
	local c = { t = clock, h = p.h, pk = pk, amp = pk and p.amp or 0 }
	local whole = d.move and d.move(p, c) or nil
	local g = whole and about(p.pivot, whole) or nil
	for _, e in ipairs(p.parts) do
		if not e.fixed then
			local cf = e.base
			local x = d.extra and d.extra(p, e, c) or nil
			if x then
				cf = x * cf
			end
			if g then
				cf = g * cf
			end
			e.part.CFrame = cf
		end
	end
end

local function effects(p)
	local d = p.def
	if d.effects then
		local pk = p.pk
		if pk and pk < 0 then
			pk = nil
		end
		d.effects(p, { t = clock, h = p.h, pk = pk, amp = pk and p.amp or 0 })
	end
end

local function settle(p)
	for _, e in ipairs(p.parts) do
		e.part.CFrame = e.base
	end
	if p.def.restFx then
		p.def.restFx(p)
	end
end

-- A poke: amp 1 is a click, smaller ones are neighbours and idle fidgets. delay in seconds.
function RoomLife.poke(p, amp, delay)
	if not p then
		return
	end
	-- a smaller poke doesn't cut off a bigger one that is still playing
	if p.pk and p.pk >= 0 and p.pk < 0.8 and (p.amp or 0) > (amp or 1) then
		return
	end
	p.pk = -(delay or 0)
	p.amp = amp or 1
	wake(p)
end

-- A ring of light running across the dance floor.
function RoomLife.ripple(pos, strength)
	table.insert(ripples, { pos = pos, t = 0, strength = strength or 1 })
	if #ripples > 8 then
		table.remove(ripples, 1)
	end
end

local function setHover(p)
	if p == hovered then
		return
	end
	if hovered then
		hovered.target = 0
	end
	hovered = p
	if p then
		p.target = 1
		wake(p)
		local d = p.def
		if d.hoverSound and clock - lastHoverSound > 0.09 then
			lastHoverSound = clock
			sfx(d.hoverSound)
		end
		if p.near then
			for _, q in ipairs(p.near) do
				RoomLife.poke(q, 0.3, 0.04)
			end
		end
		if d.onEnter then
			d.onEnter(p)
		end
	end
end

local function propAt(pos, isScreen)
	local camera = workspace.CurrentCamera
	if not (camera and rayParams and pos) then
		return nil
	end
	local ray = isScreen and camera:ScreenPointToRay(pos.X, pos.Y) or camera:ViewportPointToRay(pos.X, pos.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
	return hit and partToProp[hit.Instance] or nil, ray
end

-- Everything back where it was, right now (before a match, or when the room is hidden).
function RoomLife.rest()
	setHover(nil)
	for p in pairs(awake) do
		p.h, p.v, p.target, p.pk = 0, 0, 0, nil
		settle(p)
	end
	table.clear(awake)
	table.clear(ripples)
	resting = true
end

local STEP = 1 / 120
function RoomLife.update(dt, mouse, active)
	clock += dt
	if not active then
		if not resting then
			RoomLife.rest()
		end
		return nil
	end
	resting = false
	local p, ray = nil, nil
	if mouse then
		p, ray = propAt(mouse, false)
	end
	setHover(p)

	-- Pickles keeps an eye on your cursor, and blinks
	for _, pk in ipairs(kinds.pickles or {}) do
		wake(pk)
		if ray then
			local dist = (pk.anchor.Position - ray.Origin).Magnitude
			pk.look = ray.Origin + ray.Direction.Unit * dist
		end
	end

	-- something fidgets on its own now and then
	if clock >= nextIdle and RoomLife.idleFidgets then
		nextIdle = clock + 12 + math.random() * 14
		local pool = {}
		for _, q in ipairs(props) do
			if q.def.idle and q ~= hovered then
				table.insert(pool, q)
			end
		end
		if #pool > 0 then
			RoomLife.poke(pool[math.random(1, #pool)], 0.45)
		end
	end

	for i = #ripples, 1, -1 do
		local r = ripples[i]
		r.t += dt
		if r.t > 1.4 then
			table.remove(ripples, i)
		end
	end

	local steps = math.clamp(math.ceil(math.min(dt, 0.1) / STEP), 1, 12)
	local sdt = math.min(dt, 0.1) / steps
	for q in pairs(awake) do
		local d = q.def
		local k = d.springK or 150
		local damp = 2 * math.sqrt(k) * 0.62 -- a little overshoot, so things settle with a bounce
		for _ = 1, steps do
			q.v += ((q.target - q.h) * k - q.v * damp) * sdt
			q.h += q.v * sdt
		end
		if q.pk then
			q.pk += dt
			if q.pk > (d.pokeLen or 1.8) then
				q.pk = nil
			end
		end
		local idle = q.target == 0 and math.abs(q.h) < 0.002 and math.abs(q.v) < 0.01 and q.pk == nil and not (d.always and active)
		if idle then
			q.h, q.v = 0, 0
			settle(q)
			awake[q] = nil
		else
			place(q)
			effects(q)
		end
	end
	return hovered
end

function RoomLife.click(pos, isScreen)
	local p = propAt(pos, isScreen)
	if not p then
		return nil
	end
	RoomLife.poke(p, 1)
	sfx(p.def.clickSound)
	if p.def.onClick then
		p.def.onClick(p)
	end
	return p
end

function RoomLife.hovered()
	return hovered
end

-- How much the fire and the disco ball are hyped up right now.
function RoomLife.fireBoost()
	local p = kinds.fireplace and kinds.fireplace[1]
	return p and p.boost or 1
end

function RoomLife.discoBoost()
	local p = kinds.discoball and kinds.discoball[1]
	if not p then
		return 1
	end
	local pk = p.pk and p.pk >= 0 and p.pk or nil
	return 1 + 5 * math.max(0, p.h) + 14 * p.amp * fade(pk, 1.5) * (pk and 1 or 0)
end

-- 0..1: how white a dance floor tile glows (under the cursor, and the ripples running past).
function RoomLife.tileGlow(tile)
	local p = partToProp[tile]
	local g = p and math.max(0, p.h) or 0
	for _, r in ipairs(ripples) do
		local dist = (Vector3.new(tile.Position.X, 0, tile.Position.Z) - Vector3.new(r.pos.X, 0, r.pos.Z)).Magnitude
		local front = 9 * r.t
		local x = (dist - front) / 1.4
		g += r.strength * math.exp(-x * x) * (1 - r.t / 1.4)
	end
	return clamp01(g)
end

function RoomLife.tilesBusy()
	if #ripples > 0 then
		return true
	end
	for _, p in ipairs(kinds.discotile or {}) do
		if awake[p] then
			return true
		end
	end
	return false
end

-- How many props of each kind were found (for tests and the README).
function RoomLife.counts()
	local out = {}
	for k, list in pairs(kinds) do
		out[k] = #list
	end
	return out
end

return RoomLife

-- Juice: the small things that make the menus feel alive and polished.
-- Bouncy buttons (grow on hover, squish on press, wobble on release), pop-ins, confetti,
-- star bursts, wobbling and breathing idle motion, screen flashes and shakes, and UI sounds.
--
-- Client only (needs TweenService and the frame loop). Used by the main menu, the title
-- screen, the menu buddy, the Pack Tease and the card reveals.
--
--   local Juice = require(ReplicatedStorage.DeckWars.Juice)
--   Juice.button(myButton)                -- bouncy + click sound
--   Juice.popIn(frame, 0.2)               -- springs in from nothing after 0.2 s
--   Juice.confetti(screenGui, 0.5, 0.4, 40) -- confetti from the middle of the screen
--   Juice.sound("pop", 1.2)               -- a sound from SoundService.PackBrawlSounds
--
-- Sounds reuse the Pack Brawl sounds already uploaded (SoundService.PackBrawlSounds), so no new
-- uploads are needed. The volume follows the Sound effects / Music settings.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Settings = nil
pcall(function()
	Settings = require(script.Parent:WaitForChild("Settings"))
end)

local Juice = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
Juice.rgb = rgb

-- Default spark / confetti colors: warm golds and white (the Deck Wars gold).
Juice.Sparks = {
	rgb(255, 214, 102),
	rgb(255, 236, 170),
	rgb(255, 255, 255),
	rgb(255, 176, 64),
}
Juice.Ink = rgb(18, 14, 28) -- outline color

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
Juice.make = make

function Juice.tween(inst, time, goals, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end
local tween = Juice.tween

local function lowGraphics()
	return Settings ~= nil and Settings.get("graphics") == "Low"
end

---------------------------------------------------------------------------
-- The frame loop: idle motion and flying bits all update from one connection
---------------------------------------------------------------------------
local clock = 0
local idles = {} -- [GuiObject] = { fn, ... }
local bits = {} -- confetti and stars in flight
local loop = nil

local function alive(inst)
	return inst.Parent ~= nil
end

local function ensureLoop()
	if loop then
		return
	end
	loop = RunService.RenderStepped:Connect(function(dt)
		clock += dt
		for obj, fns in pairs(idles) do
			if alive(obj) then
				for _, fn in ipairs(fns) do
					fn(clock, dt)
				end
			else
				idles[obj] = nil
			end
		end
		local i = 1
		while i <= #bits do
			local b = bits[i]
			b.age += dt
			if b.age >= b.life or not alive(b.inst) then
				if b.inst.Parent then
					b.inst:Destroy()
				end
				table.remove(bits, i)
			else
				b.vy += b.gravity * dt
				b.vx *= math.exp(-b.drag * dt)
				b.vy *= math.exp(-b.drag * 0.4 * dt)
				b.x += b.vx * dt
				b.y += b.vy * dt
				b.inst.Position = UDim2.new(b.sx, b.x, b.sy, b.y)
				b.inst.Rotation += b.spin * dt
				local fade = math.clamp((b.age - b.life * 0.65) / (b.life * 0.35), 0, 1)
				if b.text then
					b.inst.TextTransparency = fade
				else
					b.inst.BackgroundTransparency = fade
				end
				if b.flutter then
					-- confetti flips over as it falls: squeeze its width
					local w = math.abs(math.cos(b.age * b.flutter + b.phase))
					b.inst.Size = UDim2.fromOffset(math.max(1, b.w * w), b.h)
				end
				i += 1
			end
		end
	end)
end

-- Runs fn(clock, dt) every frame for as long as `obj` is in the game.
function Juice.onFrame(obj, fn)
	ensureLoop()
	idles[obj] = idles[obj] or {}
	table.insert(idles[obj], fn)
end

function Juice.clock()
	return clock
end

---------------------------------------------------------------------------
-- Scale, pops and bounces
---------------------------------------------------------------------------

-- The UIScale that Juice uses on an object (made when missing).
function Juice.scaleOf(obj)
	local s = obj:FindFirstChild("JuiceScale")
	if not s then
		s = make("UIScale", { Name = "JuiceScale", Scale = 1 }, obj)
	end
	return s
end

-- A quick boing: jumps to `from` (default 1.2) and wobbles back to its size.
function Juice.pop(obj, from, time)
	local s = Juice.scaleOf(obj)
	s.Scale = from or 1.2
	return tween(s, time or 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)
end

-- Springs in from nothing (after `delay` seconds), with a little twist.
function Juice.popIn(obj, delay, opts)
	opts = opts or {}
	local s = Juice.scaleOf(obj)
	s.Scale = 0
	local rot = obj.Rotation
	obj.Rotation = rot + (opts.twist or -12)
	local function go()
		if not obj.Parent then
			return
		end
		tween(s, opts.time or 0.45, { Scale = opts.to or 1 }, Enum.EasingStyle.Back)
		tween(obj, (opts.time or 0.45) * 1.2, { Rotation = rot }, Enum.EasingStyle.Back)
		if opts.sound ~= false then
			Juice.sound("pop", opts.pitch or (1 + math.random() * 0.3), 0.35)
		end
	end
	if delay and delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
end

-- Shrinks away to nothing.
function Juice.popOut(obj, time)
	local s = Juice.scaleOf(obj)
	return tween(s, time or 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
end

-- Gentle rocking (degrees either side) around the object's current rotation.
function Juice.wobble(obj, degrees, speed, phase)
	local base = obj.Rotation
	phase = phase or math.random() * 6.28
	Juice.onFrame(obj, function(t)
		obj.Rotation = base + math.sin(t * (speed or 2) + phase) * (degrees or 3)
	end)
end

-- Slow breathing: grows and shrinks a little. Don't use on an object that Juice.button also scales.
function Juice.breathe(obj, amount, speed, phase)
	local s = Juice.scaleOf(obj)
	phase = phase or 0
	Juice.onFrame(obj, function(t)
		s.Scale = 1 + math.sin(t * (speed or 3) + phase) * (amount or 0.04)
	end)
end

-- Bobbing up and down by `pixels` (for frames placed with Position, not by a layout).
function Juice.bob(obj, pixels, speed, phase)
	local base = obj.Position
	phase = phase or math.random() * 6.28
	Juice.onFrame(obj, function(t)
		obj.Position = base + UDim2.fromOffset(0, math.sin(t * (speed or 2.5) + phase) * (pixels or 4))
	end)
end

-- Bouncy button: grows when the mouse is over it, squishes while pressed, boings when clicked,
-- with a pop sound. Safe to call twice.
local juiced = setmetatable({}, { __mode = "k" })
function Juice.button(b, opts)
	if juiced[b] then
		return b
	end
	juiced[b] = true
	opts = opts or {}
	local s = Juice.scaleOf(b)
	local hover, down = false, false
	local grow = opts.grow or 1.07
	local function settle(time)
		local target = down and 0.9 or (hover and grow or 1)
		tween(s, time or 0.18, { Scale = target }, Enum.EasingStyle.Back)
	end
	b.MouseEnter:Connect(function()
		hover = true
		settle()
	end)
	b.MouseLeave:Connect(function()
		hover, down = false, false
		settle()
	end)
	b.MouseButton1Down:Connect(function()
		down = true
		settle(0.08)
	end)
	b.MouseButton1Up:Connect(function()
		down = false
		settle()
	end)
	b.Activated:Connect(function()
		down = false
		s.Scale = 0.86
		tween(s, 0.55, { Scale = hover and grow or 1 }, Enum.EasingStyle.Elastic)
		if opts.sound ~= false then
			Juice.sound(opts.sound or "pop", (opts.pitch or 1) * (0.92 + math.random() * 0.2), opts.volume or 0.45)
		end
	end)
	return b
end

-- A soft light that sweeps across `obj` every `period` seconds (shiny buttons and packs).
function Juice.shine(obj, period, corner)
	local sf = make("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255), BorderSizePixel = 0, ZIndex = obj.ZIndex + 2 }, obj)
	if corner then
		make("UICorner", { CornerRadius = corner }, sf)
	end
	local g = make("UIGradient", {
		Rotation = 25,
		Offset = Vector2.new(-1.2, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sf)
	local phase = math.random() * (period or 3)
	Juice.onFrame(sf, function(t)
		local cyc = (t + phase) % (period or 3)
		g.Offset = Vector2.new(cyc < 0.7 and (-1.2 + 2.4 * cyc / 0.7) or 1.2, 0)
	end)
	return sf
end

-- An outline: dark stroke around a frame or text.
function Juice.outline(obj, thickness, color)
	return make("UIStroke", { Thickness = thickness or 3, Color = color or Juice.Ink, ApplyStrokeMode = obj:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border }, obj)
end

---------------------------------------------------------------------------
-- Confetti, stars, flashes and shakes
---------------------------------------------------------------------------
local MAX_BITS = 140

local function addBit(b)
	if #bits >= MAX_BITS then
		local old = table.remove(bits, 1)
		if old.inst.Parent then
			old.inst:Destroy()
		end
	end
	b.age = 0
	table.insert(bits, b)
	ensureLoop()
end

-- Confetti that bursts up from (sx, sy) (0..1 of `parent`) and flutters down.
-- opts: colors, speed (default 1), spread (0..1, default 1 = all directions up).
function Juice.confetti(parent, sx, sy, count, opts)
	opts = opts or {}
	count = math.floor((count or 30) * (lowGraphics() and 0.5 or 1))
	local colors = opts.colors or Juice.Sparks
	local speed = opts.speed or 1
	for _ = 1, count do
		local w, h = math.random(7, 12), math.random(12, 18)
		local f = make("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(w, h),
			Position = UDim2.fromScale(sx, sy),
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = opts.zIndex or 50,
		}, parent)
		local ang = (math.random() - 0.5) * math.pi * (opts.spread or 1) * 1.2 - math.pi / 2
		local v = (350 + math.random() * 550) * speed
		addBit({
			inst = f, sx = sx, sy = sy, x = 0, y = 0,
			vx = math.cos(ang) * v, vy = math.sin(ang) * v,
			gravity = 900, drag = 1.6, spin = math.random(-400, 400),
			life = 1.6 + math.random() * 0.9, w = w, h = h,
			flutter = 6 + math.random() * 6, phase = math.random() * 6.28,
		})
	end
end

-- Stars (or any text, like "✦" or "♥") that fly out in a ring and fade.
function Juice.stars(parent, sx, sy, count, opts)
	opts = opts or {}
	count = math.floor((count or 10) * (lowGraphics() and 0.6 or 1))
	for k = 1, count do
		local ang = (k / count) * math.pi * 2 + math.random() * 0.5
		local v = (220 + math.random() * 260) * (opts.speed or 1)
		local l = make("TextLabel", {
			Name = "Star",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(opts.size or 28, opts.size or 28),
			Position = UDim2.fromScale(sx, sy),
			BackgroundTransparency = 1,
			Text = opts.text or "★",
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			TextColor3 = opts.color or Juice.Sparks[math.random(1, #Juice.Sparks)],
			ZIndex = opts.zIndex or 50,
		}, parent)
		addBit({
			inst = l, text = true, sx = sx, sy = sy, x = 0, y = 0,
			vx = math.cos(ang) * v, vy = math.sin(ang) * v,
			gravity = opts.gravity or 300, drag = 3, spin = math.random(-300, 300),
			life = opts.life or 0.9,
		})
	end
end

-- A full-screen flash of `color` that fades out.
function Juice.flash(parent, color, time, from)
	local f = make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color or rgb(255, 255, 255), BackgroundTransparency = from or 0.1, BorderSizePixel = 0, ZIndex = 60 }, parent)
	local tw = tween(f, time or 0.4, { BackgroundTransparency = 1 })
	tw.Completed:Connect(function()
		f:Destroy()
	end)
	return f
end

-- Shakes a frame (placed by Position) for `time` seconds, then puts it back.
local shaking = setmetatable({}, { __mode = "k" })
function Juice.shake(obj, pixels, time)
	local st = shaking[obj]
	if st then
		st.left = math.max(st.left, time or 0.3)
		st.px = math.max(st.px, pixels or 8)
		return
	end
	st = { left = time or 0.3, px = pixels or 8, base = obj.Position, total = time or 0.3 }
	shaking[obj] = st
	local conn
	ensureLoop()
	conn = RunService.RenderStepped:Connect(function(dt)
		st.left -= dt
		if st.left <= 0 or not obj.Parent then
			conn:Disconnect()
			shaking[obj] = nil
			if obj.Parent then
				obj.Position = st.base
			end
			return
		end
		local k = st.left / st.total
		obj.Position = st.base + UDim2.fromOffset((math.random() - 0.5) * 2 * st.px * k, (math.random() - 0.5) * 2 * st.px * k)
	end)
end

-- Spinning sun rays (12 soft beams) centered in `parent`; returns the rays frame.
function Juice.sunburst(parent, color, opts)
	opts = opts or {}
	local rays = make("Frame", { Name = "Sunburst", AnchorPoint = Vector2.new(0.5, 0.5), Position = opts.position or UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = opts.zIndex or 1 }, parent)
	local n = opts.count or 12
	for k = 0, n - 1 do
		local holder = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Rotation = k * (360 / n), ZIndex = opts.zIndex or 1 }, rays)
		make("Frame", { Name = "Ray", AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(opts.length or 1400, opts.width or 90), BackgroundColor3 = color or rgb(255, 255, 255), BackgroundTransparency = opts.transparency or 0.85, BorderSizePixel = 0, ZIndex = opts.zIndex or 1 }, holder)
	end
	local speed = opts.speed or 10
	Juice.onFrame(rays, function(_, dt)
		rays.Rotation = (rays.Rotation + dt * speed) % 360
	end)
	return rays
end

-- Recolors a sunburst made by Juice.sunburst.
function Juice.tintSunburst(rays, color, time)
	for _, d in ipairs(rays:GetDescendants()) do
		if d.Name == "Ray" then
			tween(d, time or 0.3, { BackgroundColor3 = color })
		end
	end
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
local groups = {}
local MUSIC = { theme = true, brawl = true }
local function volumeOf(key)
	return Settings and Settings.volume(key) or 1
end

local function groupFor(kind)
	local g = groups[kind]
	if g and g.Parent then
		return g
	end
	g = make("SoundGroup", { Name = kind == "music" and "JuiceMusic" or "JuiceSfx", Volume = 0.8 * volumeOf(kind) }, SoundService)
	groups[kind] = g
	return g
end

if Settings then
	Settings.onChanged(function(key)
		if (key == "sfx" or key == "music") and groups[key] and groups[key].Parent then
			groups[key].Volume = 0.8 * volumeOf(key)
		end
	end)
end

-- Plays one of the Pack Brawl sound templates by name, at `pitch` (1 = normal) and `volume`.
-- Silent if the template is missing or has no SoundId, or the volume setting is 0.
local lastPlayed = {}
function Juice.sound(name, pitch, volume)
	local folder = SoundService:FindFirstChild("PackBrawlSounds")
	local tpl = folder and folder:FindFirstChild(name)
	if not tpl or tpl.SoundId == "" then
		return nil
	end
	local kind = MUSIC[name] and "music" or "sfx"
	if volumeOf(kind) <= 0 then
		return nil
	end
	-- the same sound many times in one frame (a row of buttons popping in) only plays a few
	local key = name .. "@" .. string.format("%.2f", clock)
	lastPlayed[key] = (lastPlayed[key] or 0) + 1
	if lastPlayed[key] > 2 then
		return nil
	end
	local s = tpl:Clone()
	s.Looped = false
	s.PlaybackSpeed = pitch or 1
	if volume then
		s.Volume = volume
	end
	local g = groupFor(kind)
	s.SoundGroup = g
	s.Parent = g
	s:Play()
	Debris:AddItem(s, MUSIC[name] and 12 or 5)
	return s
end

-- Forgets the per-frame sound counts now and then.
task.spawn(function()
	while true do
		task.wait(2)
		table.clear(lastPlayed)
	end
end)

return Juice

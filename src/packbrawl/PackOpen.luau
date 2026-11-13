-- The pack opening: the pack is in your hands, in front of its own scene, and you slash it open.
--
-- Press and swipe across the pack (mouse or finger) like a blade. A quick swipe that cuts most of
-- the way across slices it in two along the line you drew: the halves fly apart, light and the
-- pack's own burst pour out of the cut, and the card (or the stack of 10) rises out face down.
-- A slow drag only scratches it. Space / Enter / gamepad A slash along the dotted guide, and a
-- pack nobody touches shows how after a moment and opens itself after a while.
--
-- Nothing here shows the rarity: the pack, its scene and the cut look the same for every pull.
-- The card itself is the reveal (Reveal.luau takes over this same screen).
--
--   PackOpen.play({ pack = Packs def, count = 1 | 10, quick = bool }, onDone)
--     onDone(handoff) with handoff = { gui, scene, stage, stageScale, cards = { CardHolder, ... }, pack, count }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local Packs = require(here:WaitForChild("Packs"))
local PackArt = require(here:WaitForChild("PackArt"))
local Juice = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("Juice"))
local LayerFx = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("LayerFx"))

local make, tween, rgb = Juice.make, Juice.tween, Juice.rgb
local WHITE = rgb(255, 255, 255)
local INK = rgb(18, 14, 28)

local PackOpen = {}

PackOpen.AutoHint = 2.5 -- seconds without a slash before a ghost blade shows how
PackOpen.AutoOpen = 9 -- seconds before the pack opens itself
PackOpen.MinCut = 0.55 -- a slash must cut through this share of the pack's width
PackOpen.MinSpeed = 450 -- pixels per second (at full stage size): slower is a scratch
PackOpen.StageW, PackOpen.StageH = 760, 560
PackOpen.CardW, PackOpen.CardH = 300, 420 -- the single card (the reveal's size)
PackOpen.FanW, PackOpen.FanH = 140, 200 -- each card of a 10-pack

local function c3(v)
	return rgb(v[1], v[2], v[3])
end

local function guiInset()
	local ok, inset = pcall(function()
		return game:GetService("GuiService"):GetGuiInset()
	end)
	return (ok and typeof(inset) == "Vector2") and inset or Vector2.new(0, 0)
end

local function rotate(v, deg)
	local a = math.rad(deg)
	local c, s = math.cos(a), math.sin(a)
	return Vector2.new(v.X * c - v.Y * s, v.X * s + v.Y * c)
end

-- A card holder: the Deck Wars card back in a frame the reveal flips.
function PackOpen.cardHolder(parent, w, h, name)
	local holder = make("Frame", { Name = name or "CardHolder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, ZIndex = 20 }, parent)
	make("UIScale", { Name = "CardScale", Scale = 1 }, holder)
	PackArt.cardBack(holder)
	return holder
end

-- The screen, the scene and the stage, shared with the reveal (also used on its own by tests).
function PackOpen.newScreen(pack, name)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", { Name = name or "PackOpen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 55, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	local scene = PackArt.scene(gui, pack)
	local stage = make("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PackOpen.StageW, PackOpen.StageH), BackgroundTransparency = 1, ZIndex = 10 }, gui)
	local stageScale = make("UIScale", { Scale = 1 }, stage)
	local function fit()
		local s = gui.AbsoluteSize
		if s.X > 0 and s.Y > 0 then
			stageScale.Scale = math.min(1.15, s.X / 800, s.Y / 600)
		end
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	return gui, scene, stage, stageScale
end

function PackOpen.play(opts, onDone)
	opts = opts or {}
	local pack = opts.pack or Packs.get(nil)
	local count = opts.count or 1
	local quick = opts.quick == true
	local design = PackArt.design(pack)
	local main, accent = c3(pack.color), c3(pack.accent)
	local gui, scene, stage, stageScale = PackOpen.newScreen(pack, "PackOpen")

	local fade = make("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 90 }, gui)
	tween(fade, 0.35, { BackgroundTransparency = 1 }).Completed:Connect(function()
		fade:Destroy()
	end)

	local packFrame = PackArt.build(stage, pack, count)
	packFrame.Position = UDim2.new(0.5, 0, 0.5, 520)
	packFrame.Rotation = -12
	local packScale = Juice.scaleOf(packFrame)
	local guide = packFrame:FindFirstChild("CutGuide")
	local trail = make("Frame", { Name = "Trail", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40 }, gui)
	local hint = make("TextLabel", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 205), Size = UDim2.fromOffset(460, 34), BackgroundTransparency = 1, Text = "SLASH THE PACK OPEN", Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = WHITE, TextTransparency = 1, ZIndex = 30 }, stage)
	make("UIStroke", { Thickness = 2.5, Color = INK }, hint)
	local sub = make("TextLabel", { Name = "SubHint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 240), Size = UDim2.fromOffset(460, 22), BackgroundTransparency = 1, Text = "Swipe across it, fast", Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = rgb(225, 220, 240), TextTransparency = 1, ZIndex = 30 }, stage)
	-- a full-screen button so clicks don't fall through to the room behind
	local catcher = make("TextButton", { Name = "SlashArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 35 }, gui)

	local st = {
		ready = false,
		cut = false,
		now = 0,
		readyAt = math.huge,
		lastTry = 0,
		stroke = nil,
		ox = 0,
		oy = 0,
		tilt = 0,
		mouse = nil,
		ghostAt = 0,
	}
	local conns = {}
	local function disconnect()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		table.clear(conns)
	end

	-- where the pack is on screen (centre and half size, in the ScreenGui's pixels)
	local function screenSize()
		local s = gui.AbsoluteSize
		if s.X > 0 and s.Y > 0 then
			return s
		end
		local cam = workspace.CurrentCamera
		return cam and cam.ViewportSize.X > 0 and cam.ViewportSize or Vector2.new(1280, 720)
	end
	local function packRect()
		local s = screenSize()
		local k = stageScale.Scale * packScale.Scale
		local centre = s / 2 + Vector2.new(st.ox, st.oy) * stageScale.Scale
		return centre, Vector2.new(PackArt.Width / 2, PackArt.Height / 2) * k
	end
	local function inside(p)
		local centre, half = packRect()
		local d = p - centre
		return math.abs(d.X) <= half.X * 1.04 and math.abs(d.Y) <= half.Y * 1.04
	end
	local function toStage(p) -- screen pixels -> offset from the stage's centre
		return (p - screenSize() / 2) / stageScale.Scale
	end

	-- the blade's trail
	local segments = 0
	local function slashSegment(a, b, color, width)
		local d = b - a
		local len = d.Magnitude
		if len < 1 or segments > 60 then
			return
		end
		segments += 1
		local mid = (a + b) / 2
		local seg = make("Frame", { Name = "Blade", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(mid.X, mid.Y), Size = UDim2.fromOffset(len + 6, width or 7), Rotation = math.deg(math.atan2(d.Y, d.X)), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 41 }, trail)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, seg)
		make("UIStroke", { Thickness = 3, Color = color or accent, Transparency = 0.25 }, seg)
		tween(seg, 0.24, { Size = UDim2.fromOffset(len, 0), BackgroundTransparency = 1 }).Completed:Connect(function()
			seg:Destroy()
			segments -= 1
		end)
	end

	local function scratch(p, tooSlow)
		Juice.sound("tick", 1.3, 0.4)
		local s = screenSize()
		Juice.stars(gui, p.X / s.X, p.Y / s.Y, 5, { text = "★", color = accent:Lerp(WHITE, 0.4), size = 14, speed = 0.6, zIndex = 42 })
		Juice.shake(packFrame, 4, 0.15)
		if tooSlow then
			sub.Text = "Faster! Slash right across it"
			Juice.pop(sub, 1.25, 0.4)
		end
	end

	-- After the cut: the card (or the stack) rises out of the pack
	local cards = {}
	local function finishCut(cutPoint)
		local quickK = quick and 0.6 or 1
		if count > 1 then
			for i = 1, count do
				local h = PackOpen.cardHolder(stage, PackOpen.FanW, PackOpen.FanH, "CardHolder")
				h.Position = UDim2.new(0.5, cutPoint.X, 0.5, cutPoint.Y)
				h.Rotation = math.random(-30, 30)
				h.CardScale.Scale = 0.4
				h.ZIndex = 20 + i
				cards[i] = h
				-- out in a spray, then into one neat stack in the middle
				local a = math.rad(-90 + (i - (count + 1) / 2) * 13)
				local out = cutPoint + Vector2.new(math.cos(a), math.sin(a)) * 190
				tween(h, 0.32 * quickK, { Position = UDim2.new(0.5, out.X, 0.5, out.Y), Rotation = (i - 5.5) * 8 }, Enum.EasingStyle.Quad)
				tween(h.CardScale, 0.32 * quickK, { Scale = 1 }, Enum.EasingStyle.Back)
				task.delay((0.34 + i * 0.025) * quickK, function()
					if h.Parent then
						tween(h, 0.3 * quickK, { Position = UDim2.new(0.5, (i - 5.5) * 1.5, 0.5, -i * 1.2), Rotation = (i - 5.5) * 0.8 }, Enum.EasingStyle.Back)
					end
				end)
			end
			Juice.sound("whoosh", 1.4, 0.5)
		else
			local h = PackOpen.cardHolder(stage, PackOpen.CardW, PackOpen.CardH, "CardHolder")
			h.Position = UDim2.new(0.5, cutPoint.X, 0.5, cutPoint.Y)
			h.Rotation = math.random(-25, 25)
			h.CardScale.Scale = 0.35
			cards[1] = h
			tween(h, 0.3 * quickK, { Position = UDim2.new(0.5, 0, 0.5, -150) }, Enum.EasingStyle.Quad)
			tween(h.CardScale, 0.3 * quickK, { Scale = 0.75 }, Enum.EasingStyle.Quad)
			task.delay(0.3 * quickK, function()
				if h.Parent then
					tween(h, 0.42 * quickK, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }, Enum.EasingStyle.Back)
					tween(h.CardScale, 0.42 * quickK, { Scale = 0.9 }, Enum.EasingStyle.Back)
				end
			end)
			Juice.sound("whoosh", 1.25, 0.45)
		end
		task.delay(0.8 * quickK, function()
			disconnect()
			catcher:Destroy()
			trail:Destroy()
			hint:Destroy()
			sub:Destroy()
			if packFrame.Parent then
				packFrame:Destroy()
			end
			if onDone then
				onDone({ gui = gui, scene = scene, stage = stage, stageScale = stageScale, cards = cards, pack = pack, count = count })
			end
		end)
	end

	-- THE CUT: slice the pack in two along the line from a to b (screen pixels)
	local function doCut(a, b)
		if st.cut then
			return
		end
		st.cut = true
		st.ready = false
		st.stroke = nil
		local d = b - a
		local angle = math.deg(math.atan2(d.Y, d.X))
		if angle > 90 then
			angle -= 180
		elseif angle <= -90 then
			angle += 180
		end
		-- the cut line's middle, in stage offsets; the pack's centre
		local p = toStage((a + b) / 2)
		local c = Vector2.new(st.ox, st.oy)
		local rot = packFrame.Rotation
		local k = packScale.Scale
		packFrame.Visible = false
		tween(hint, 0.15, { TextTransparency = 1 })
		tween(sub, 0.15, { TextTransparency = 1 })
		-- the two halves: each is a rotated CanvasGroup whose edge lies on the cut, holding a copy
		local L = 900
		for _, side in ipairs({ -1, 1 }) do
			local centre = p + rotate(Vector2.new(0, side * L / 2), angle)
			local group = make("CanvasGroup", { Name = side < 0 and "HalfA" or "HalfB", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, centre.X, 0.5, centre.Y), Size = UDim2.fromOffset(L, L), Rotation = angle, BackgroundTransparency = 1, ZIndex = 12 }, stage)
			local copy = PackArt.build(group, pack, count, { static = true, noGuide = true })
			local rel = rotate(c - centre, -angle)
			copy.Position = UDim2.new(0.5, rel.X, 0.5, rel.Y)
			copy.Rotation = rot - angle
			make("UIScale", { Scale = k }, copy)
			-- fly apart along the cut's normal, tumbling, and fade out
			local push = rotate(Vector2.new((math.random() - 0.5) * 60, side * 150), angle) + Vector2.new(0, 120)
			tween(group, 0.75, { Position = UDim2.new(0.5, centre.X + push.X, 0.5, centre.Y + push.Y), Rotation = angle + side * (14 + math.random() * 14) }, Enum.EasingStyle.Quad)
			tween(group, 0.75, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.8, function()
				group:Destroy()
			end)
		end
		-- the flash of the blade along the cut
		local line = make("Frame", { Name = "SlashLine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, p.X, 0.5, p.Y), Size = UDim2.fromOffset(PackArt.Width * 1.8 * k, 10), Rotation = angle, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 30 }, stage)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, line)
		make("UIStroke", { Thickness = 5, Color = accent, Transparency = 0.2 }, line)
		tween(line, 0.35, { Size = UDim2.fromOffset(PackArt.Width * 2.4 * k, 0), BackgroundTransparency = 1 }).Completed:Connect(function()
			line:Destroy()
		end)
		-- light pours out of the opening (the pack's own colours)
		local glow = make("Frame", { Name = "CutLight", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, p.X, 0.5, p.Y), Size = UDim2.fromOffset(PackArt.Width * 1.2 * k, 6), Rotation = angle, BackgroundColor3 = accent:Lerp(WHITE, 0.6), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 11 }, stage)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
		tween(glow, 0.5, { Size = UDim2.fromOffset(PackArt.Width * 1.6 * k, 220), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad).Completed:Connect(function()
			glow:Destroy()
		end)
		local s = screenSize()
		local mid = (a + b) / 2
		scene.burst(mid.X / s.X, mid.Y / s.Y, angle)
		-- the painted cut: a swipe along the blade's path and the burst where the pack gives way
		local paint = LayerFx.paletteFrom(accent)
		LayerFx.screen("slash", stage, UDim2.new(0.5, p.X, 0.5, p.Y), PackArt.Width * 2.2 * k, { palette = paint, turn = angle - 90, zIndex = 31 })
		LayerFx.screen("bigHit", stage, UDim2.new(0.5, p.X, 0.5, p.Y), PackArt.Width * 1.5 * k, { palette = paint, delay = 0.05, zIndex = 13 })
		Juice.flash(gui, main:Lerp(WHITE, 0.7), 0.3, 0.55)
		Juice.shake(stage, 12, 0.28)
		Juice.sound("whoosh", 1.7, 0.7)
		Juice.sound("rip", 1.1, 0.8)
		Juice.sound(design.cutSound[1], design.cutSound[2], 0.55)
		PackOpen.lastCut = { a = a, b = b, angle = angle } -- (for tests)
		finishCut(p)
	end

	local function tryCut()
		local stroke = st.stroke
		if not (stroke and stroke.entry and stroke.exit) then
			return false
		end
		local _, half = packRect()
		local chord = stroke.exit - stroke.entry
		local len = chord.Magnitude
		local need = PackOpen.MinCut * half.X * 2
		local took = math.max(stroke.exitT - stroke.entryT, 1 / 120)
		local fast = stroke.auto or len / took >= PackOpen.MinSpeed * stageScale.Scale
		if len >= need and fast then
			doCut(stroke.entry, stroke.exit)
			return true
		end
		if len >= need * 0.4 then
			scratch(stroke.exit, len >= need and not fast)
		end
		stroke.entry, stroke.exit = nil, nil
		return false
	end

	local function strokeBegin(p)
		if not st.ready or st.cut then
			return
		end
		local ins = inside(p)
		st.stroke = { last = p, lastT = st.now, inPack = ins, entry = ins and p or nil, entryT = st.now, exit = ins and p or nil, exitT = st.now }
		st.lastTry = st.now
		Juice.sound("whoosh", 1.9, 0.18)
	end
	local function strokeMove(p)
		local stroke = st.stroke
		if not stroke or st.cut then
			return
		end
		slashSegment(stroke.last, p)
		local from, fromT = stroke.last, stroke.lastT
		local steps = math.max(1, math.ceil((p - from).Magnitude / 10))
		for i = 1, steps do
			local q = from:Lerp(p, i / steps)
			local qt = fromT + (st.now - fromT) * i / steps
			local ins = inside(q)
			if ins and not stroke.inPack then
				stroke.entry, stroke.entryT = q, qt
			end
			if ins then
				stroke.exit, stroke.exitT = q, qt
			end
			if not ins and stroke.inPack then
				if tryCut() then
					return
				end
			end
			stroke.inPack = ins
		end
		stroke.last, stroke.lastT = p, st.now
	end
	local function strokeEnd()
		if st.stroke and not st.cut then
			tryCut()
		end
		st.stroke = nil
	end

	-- a stroke from a list of points (screen pixels), one per frame step of dt seconds (tests, keys)
	local function autoSlash(points, dt, auto)
		task.spawn(function()
			strokeBegin(points[1])
			if st.stroke then
				st.stroke.auto = auto
			end
			for i = 2, #points do
				task.wait(dt or 1 / 60)
				if st.cut then
					return
				end
				strokeMove(points[i])
			end
			strokeEnd()
		end)
	end
	PackOpen.strokeHook = autoSlash -- (for tests)

	-- the dotted guide's line across the pack, in screen pixels (from beyond one edge to the other)
	local function guideLine(extra)
		local centre, half = packRect()
		local y = (design.cutY - 0.5) * half.Y * 2
		local dir = rotate(Vector2.new(1, 0), design.cutAngle + packFrame.Rotation)
		local mid = centre + rotate(Vector2.new(0, y), packFrame.Rotation)
		local reach = half.X * (1 + (extra or 0.35))
		return mid - dir * reach, mid + dir * reach
	end
	local function guideSlash()
		if not st.ready or st.cut then
			return
		end
		local a, b = guideLine()
		local pts = {}
		for i = 0, 8 do
			pts[#pts + 1] = a:Lerp(b, i / 8)
		end
		autoSlash(pts, 1 / 60, true)
	end
	PackOpen.keyHook = guideSlash -- (for tests)

	-- a ghost blade sweeps along the guide to show how (it doesn't cut)
	local function ghost()
		local a, b = guideLine(0.5)
		local n = 10
		for i = 1, n do
			task.delay(i * 0.025, function()
				if not st.cut and gui.Parent then
					slashSegment(a:Lerp(b, (i - 1) / n), a:Lerp(b, i / n), WHITE, 5)
				end
			end)
		end
		Juice.sound("whoosh", 2.1, 0.12)
	end

	-- input: mouse button 1 or a finger starts a stroke; moving draws it
	table.insert(conns, UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			local p = input.Position
			strokeBegin(Vector2.new(p.X, p.Y) + guiInset())
		elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
			guideSlash()
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
			local p = Vector2.new(input.Position.X, input.Position.Y) + guiInset()
			st.mouse = p
			strokeMove(p)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			strokeEnd()
		end
	end))

	-- the pack rises into your hands
	Juice.sound("whoosh", 1.05, 0.5)
	tween(packFrame, quick and 0.4 or 0.6, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }, Enum.EasingStyle.Back)
	task.delay(quick and 0.4 or 0.6, function()
		if st.cut or not gui.Parent then
			return
		end
		st.ready = true
		st.readyAt = st.now
		st.lastTry = st.now
		tween(hint, 0.3, { TextTransparency = 0 })
		tween(sub, 0.3, { TextTransparency = 0.1 })
	end)
	local hoverOn = false
	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		st.now += dt
		if st.cut then
			return
		end
		if st.ready then
			-- bob, and lean toward the mouse
			st.oy = math.sin(st.now * 2.2) * 6
			local s = screenSize()
			local lean = st.mouse and math.clamp((st.mouse.X - s.X / 2) / (s.X / 2), -1, 1) or 0
			st.tilt += (lean * 5 - st.tilt) * math.min(1, dt * 6)
			packFrame.Position = UDim2.new(0.5, st.ox, 0.5, st.oy)
			packFrame.Rotation = st.tilt
			hint.TextSize = 26 + math.sin(st.now * 5) * 1.2
			-- the guide glows brighter under the mouse
			local over = st.mouse ~= nil and inside(st.mouse)
			if over ~= hoverOn then
				hoverOn = over
				tween(packScale, 0.2, { Scale = over and 1.05 or 1 }, Enum.EasingStyle.Back)
				if guide then
					for _, dash in ipairs(guide:GetChildren()) do
						if dash.Name == "Dash" then
							tween(dash, 0.2, { BackgroundTransparency = over and 0 or 0.15, BackgroundColor3 = over and accent:Lerp(WHITE, 0.5) or WHITE })
						end
					end
				end
			end
			if guide then
				guide.Size = UDim2.new(1, 24 + math.sin(st.now * 6) * 4, 0, 4)
			end
			local idle = st.now - st.lastTry
			if idle >= PackOpen.AutoHint and st.now - st.ghostAt >= 2.6 and not st.stroke then
				st.ghostAt = st.now
				ghost()
			end
			if st.now - st.readyAt >= PackOpen.AutoOpen and not st.stroke then
				guideSlash()
			end
		end
	end))
	return { gui = gui, state = st, slash = autoSlash, key = guideSlash, packRect = packRect }
end

return PackOpen

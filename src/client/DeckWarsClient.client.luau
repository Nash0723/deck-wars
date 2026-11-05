-- Deck Wars client: the menu room camera, the station menus and the pack openings.
-- The match table lives in MatchScreen, the Duel Table panel (bot, 1v1, 2v2, tournaments) in LobbyScreen,
-- parties and invites in PartyScreen, and the worlds around the table in a match in Backdrops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local CardData = require(Shared:WaitForChild("CardData"))
local StarterDecks = require(Shared:WaitForChild("StarterDecks"))
local CreatureBuilder = require(Shared:WaitForChild("CreatureBuilder"))
local PullRates = require(Shared:WaitForChild("PullRates"))
local MatchScreen = require(Shared:WaitForChild("MatchScreen"))
local LobbyScreen = require(Shared:WaitForChild("LobbyScreen"))
local PartyScreen = require(Shared:WaitForChild("PartyScreen"))
local Backdrops = require(Shared:WaitForChild("Backdrops"))
local Progression = require(Shared:WaitForChild("Progression"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local room = workspace:WaitForChild("MenuRoom")
local stations = room:WaitForChild("Stations")
local duelTable = stations:WaitForChild("DuelTable")
local board = duelTable:WaitForChild("Board")

pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Pacing of the table animations. 1 = normal. Raise it (for example 1.5) to slow
-- everything down, lower it (for example 0.7) to speed up. The turn timer and the
-- bot's thinking time are set at the top of MatchServer.
local PACE = 1.0
-- Action camera: for attacks, Sparks and big summons the camera swoops in close, then glides back
-- to your seat. Off: in a match the camera stays still at your seat, so the table is easy to read.
local ACTION_CAMERA = false
-- With the action camera off, the camera can still lean in a little toward each fight. Off too.
local ATTACK_CAMERA = false

local FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function familyColor(family)
	return rgb(CardData.FamilyColors[family] or CardData.FamilyColors.Any)
end

-- Shared state, declared up here so every function below can use it.
local mode = "menu" -- "menu", "match" or "pull" (a pack opening, which moves the camera itself)
local clock = 0 -- seconds since the script started (advanced every frame)
local currentStation = nil -- the station whose panel is open

---------------------------------------------------------------------------
-- Camera: glides between spots, can shake, and sways a little during matches
---------------------------------------------------------------------------

local CAMS = {
	Overview = { Vector3.new(0, 15, 22), Vector3.new(0, 3, -6) },
	DuelTable = { Vector3.new(0, 16, 23), Vector3.new(0, 4, 0) },
	-- Your seat in a match: the whole board and the bot across the table. The camera stays here all
	-- match (SeatYou / SeatOpp could lean in on your turn and back on theirs; now they're the same).
	Seat = { Vector3.new(0, 15.8, 12.8), Vector3.new(0, 4.1, 0.2), 50 },
	SeatYou = { Vector3.new(0, 15.8, 12.8), Vector3.new(0, 4.1, 0.2), 50 },
	SeatOpp = { Vector3.new(0, 15.8, 12.8), Vector3.new(0, 4.1, 0.2), 50 },
	DeckShelf = { Vector3.new(-9, 8, 0), Vector3.new(-22, 6, 0) },
	PackParty = { Vector3.new(9.5, 9.5, -9.5), Vector3.new(17, 5.2, -17.5) },
	ShopCounter = { Vector3.new(9, 8.5, 9), Vector3.new(16, 5.2, 17.5) },
	TrophyWall = { Vector3.new(11, 9, 0), Vector3.new(23.5, 8, 0) },
	Radio = { Vector3.new(-13, 6.2, -13), Vector3.new(-17.2, 3.6, -18.2) },
}
local DEFAULT_FOV = 70
local cam = {
	fov = DEFAULT_FOV,
	fromFov = DEFAULT_FOV,
	toFov = DEFAULT_FOV,
	fromPos = CAMS.Overview[1],
	fromLook = CAMS.Overview[2],
	toPos = CAMS.Overview[1],
	toLook = CAMS.Overview[2],
	pos = CAMS.Overview[1],
	look = CAMS.Overview[2],
	start = 0,
	duration = 0,
	shake = 0,
	lean = 0, -- how far the camera leans in toward a fight (0 to 1), eased every frame
	leanTarget = 0,
	leanPoint = nil,
}

local actionCam = { on = ACTION_CAMERA } -- filled in below, after the camera helpers

local function smooth(a)
	return a * a * (3 - 2 * a)
end

-- Glide the camera to `pos`, looking at `look`, over `seconds` (0 = jump). `fov` is the zoom (default 70).
local function glideCamera(pos, look, seconds, fov)
	cam.fromPos, cam.fromLook, cam.fromFov = cam.pos, cam.look, cam.fov
	cam.toPos, cam.toLook, cam.toFov = pos, look, fov or DEFAULT_FOV
	cam.start = clock
	cam.duration = math.max(0, (seconds or 0) * PACE)
	if cam.duration == 0 then
		cam.pos, cam.look, cam.fov = pos, look, cam.toFov
	end
end

-- While a match's opening shot plays, seat moves wait and happen when it ends (see showIntro).
local intro = { untilClock = 0, pending = nil }

local function moveCamera(name, instant, seconds)
	local preset = CAMS[name]
	if not preset then
		return
	end
	if mode == "match" and clock < intro.untilClock then
		intro.pending = name
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	glideCamera(preset[1], preset[2], instant and 0 or (seconds or 1.2), preset[3])
end

local function shakeCamera(strength)
	cam.shake = math.max(cam.shake, strength)
end

-- Lean the camera a little toward a point on the table (a fight), or back again with nil.
local function leanCamera(point, amount)
	if not ATTACK_CAMERA or actionCam.on then
		return
	end
	if point then
		cam.leanPoint = point
	end
	cam.leanTarget = point and (amount or 1) or 0
end

-- The action camera. A "shot" is a camera spot near the action. The camera blends from your seat
-- into the shot, glides from shot to shot while several things happen in a row, and blends back
-- to your seat a moment after the last one. Shots always stay on your side of the action, so
-- left and right never flip.
do
	local act = { w0 = 0, w1 = 0, wt0 = 0, wdur = 0, s0 = nil, s1 = nil, st0 = 0, sdur = 0, releaseAt = nil, punch = 0 }

	local function weightNow()
		local k = act.wdur > 0 and smooth(math.clamp((clock - act.wt0) / act.wdur, 0, 1)) or 1
		return act.w0 + (act.w1 - act.w0) * k
	end

	local function setWeight(target, seconds)
		act.w0 = weightNow()
		act.w1 = target
		act.wt0 = clock
		act.wdur = math.max(0, seconds * PACE)
	end

	local function currentShot()
		if not act.s1 then
			return nil
		end
		local k = act.sdur > 0 and smooth(math.clamp((clock - act.st0) / act.sdur, 0, 1)) or 1
		local a, b = act.s0, act.s1
		return { pos = a.pos:Lerp(b.pos, k), look = a.look:Lerp(b.look, k), fov = a.fov + (b.fov - a.fov) * k }
	end

	function actionCam.active()
		return act.w1 > 0 or weightNow() > 0.01
	end

	-- Move into a shot: the camera at `pos` looking at `look`.
	function actionCam.shot(pos, look, fov, seconds)
		if not actionCam.on or mode ~= "match" then
			return
		end
		seconds = seconds or 0.6
		local new = { pos = pos, look = look, fov = fov or 48 }
		if weightNow() < 0.15 or not act.s1 then
			act.s0, act.s1 = new, new -- coming from the seat: blend straight into it
		else
			act.s0, act.s1 = currentShot(), new -- already close: glide over to the new shot
		end
		act.st0 = clock
		act.sdur = seconds * PACE
		if act.w1 < 1 then
			setWeight(1, seconds)
		end
		act.releaseAt = nil
	end

	-- Two things on the table, like an attacker and its target: a low three-quarter view from the side.
	function actionCam.duel(a, b, opts)
		opts = opts or {}
		local flat = (b - a) * Vector3.new(1, 0, 1)
		local dist = flat.Magnitude
		local dir = dist > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
		local mid = (a + b) / 2
		local side = Vector3.new(0, 1, 0):Cross(dir)
		if side.Z < -0.05 or (math.abs(side.Z) <= 0.05 and side.X * mid.X > 0) then
			side = -side -- stay on your side of the table, or toward the middle of the board
		end
		local pos = mid + side * (3.4 + dist * 0.45) - dir * (1.2 + dist * 0.1) + Vector3.new(0, 2.6 + dist * 0.35, 0)
		actionCam.shot(pos, mid + Vector3.new(0, opts.lookUp or 0.7, 0), opts.fov or 48, opts.seconds)
	end

	-- One creature or tile. `facing` is +1 when it faces you (enemy creatures) and -1 when it faces away
	-- (yours), so yours are seen more from the side than from behind.
	function actionCam.focus(p, opts)
		opts = opts or {}
		local yawDeg = opts.yaw or ((opts.facing or 1) > 0 and 20 or 62)
		if p.X > 0.5 then
			yawDeg = -yawDeg -- look from the middle of the board outward
		end
		local yaw = math.rad(yawDeg + (opts.turn or 0))
		local dist = opts.dist or 4.2
		local pos = p + Vector3.new(math.sin(yaw) * dist, opts.up or 2.2, math.cos(yaw) * dist)
		actionCam.shot(pos, p + Vector3.new(0, opts.lookUp or 0.8, 0), opts.fov or 45, opts.seconds)
	end

	-- Head back to the seat after `delay` seconds, unless another shot starts first.
	function actionCam.release(delay)
		if act.w1 > 0 then
			act.releaseAt = clock + (delay or 0.35) * PACE
		end
	end

	-- Things that follow an action (damage, pops, heals) keep the camera there a little longer.
	function actionCam.hold(seconds)
		if act.releaseAt then
			act.releaseAt = math.max(act.releaseAt, clock + seconds * PACE)
		end
	end

	-- A quick zoom kick when a hit lands.
	function actionCam.punch(amount)
		if actionCam.on then
			act.punch = math.max(act.punch, amount)
		end
	end

	function actionCam.reset()
		act.w0, act.w1, act.wdur, act.releaseAt, act.s0, act.s1, act.punch = 0, 0, 0, nil, nil, nil, 0
	end

	-- Your seat view: "you" leans in over the board on your turn, "opp" leans back on the bot's turn.
	function actionCam.seat(which)
		if mode == "match" then
			moveCamera(which == "you" and "SeatYou" or "SeatOpp", false, 1.3)
		end
	end

	-- Called every frame with the seat camera; returns the camera to use.
	function actionCam.apply(pos, look, fov, dt)
		if act.releaseAt and clock >= act.releaseAt then
			act.releaseAt = nil
			setWeight(0, 0.85)
		end
		local w = weightNow()
		if w > 0.001 and act.s1 then
			local s = currentShot()
			pos = pos:Lerp(s.pos, w)
			look = look:Lerp(s.look, w)
			fov = fov + (s.fov - fov) * w
		elseif act.w1 == 0 and act.s1 then
			act.s0, act.s1 = nil, nil
		end
		if act.punch > 0.05 then
			fov -= act.punch
			act.punch *= math.exp(-dt * 8)
		else
			act.punch = 0
		end
		return pos, look, fov
	end
end

local depthOfField = game:GetService("Lighting"):FindFirstChildOfClass("DepthOfFieldEffect")

local function updateCamera(dt)
	-- During a pack opening the opening owns the camera (see pullMode), so leave it alone.
	if mode == "pull" then
		return
	end
	if cam.duration > 0 then
		local a = math.clamp((clock - cam.start) / cam.duration, 0, 1)
		local e = smooth(a)
		cam.pos = cam.fromPos:Lerp(cam.toPos, e)
		cam.look = cam.fromLook:Lerp(cam.toLook, e)
		cam.fov = cam.fromFov + (cam.toFov - cam.fromFov) * e
		if a >= 1 then
			cam.duration = 0
		end
	end
	local pos, look = cam.pos, cam.look
	cam.lean += (cam.leanTarget - cam.lean) * math.min(1, dt * 3)
	if cam.leanPoint and cam.lean > 0.002 then
		local k = cam.lean
		pos = pos:Lerp(cam.leanPoint + (pos - look) * 0.7, k * 0.3)
		look = look:Lerp(cam.leanPoint, k * 0.4)
	end
	local fov
	pos, look, fov = actionCam.apply(pos, look, cam.fov, dt)
	if mode == "match" then
		-- A very slow drift, so the table doesn't feel frozen.
		pos = pos + Vector3.new(math.sin(clock * 0.3) * 0.05, math.sin(clock * 0.42) * 0.025, 0)
	end
	local cf = CFrame.lookAt(pos, look)
	if cam.shake > 0.005 then
		local t = clock * 28
		local s = cam.shake
		cf = cf * CFrame.new(math.noise(t, 0.5) * s, math.noise(t, 7.3) * s, 0) * CFrame.Angles(0, 0, math.noise(t, 13.1) * s * 0.06)
		cam.shake = s * math.exp(-dt * 5)
	else
		cam.shake = 0
	end
	camera.CFrame = cf
	camera.FieldOfView = fov
	if depthOfField then
		depthOfField.FocusDistance = (pos - look).Magnitude
	end
end

-- Keep the camera ours even after the character respawns, and stop walking around.
local function lockPlayer()
	task.defer(function()
		camera.CameraType = Enum.CameraType.Scriptable
	end)
	pcall(function()
		local PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		PlayerModule:GetControls():Disable()
	end)
end
player.CharacterAdded:Connect(lockPlayer)
if player.Character then
	lockPlayer()
end
camera:GetPropertyChangedSignal("CameraType"):Connect(function()
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end)

---------------------------------------------------------------------------
-- GUI helpers
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DeckWarsUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function label(parent, text, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = FONT,
		TextColor3 = WHITE,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent, text, color, onClick, props)
	local b = make("TextButton", {
		Text = text,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		BackgroundColor3 = color or Color3.fromRGB(70, 130, 220),
		AutoButtonColor = true,
		Size = UDim2.fromOffset(160, 44),
	}, parent)
	corner(b, 10)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, b)
	make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(20, 18, 30), Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- Headings: a warm gold gradient with a soft dark outline (instead of a hard black stroke).
local function headingStyle(l)
	l.TextStrokeTransparency = 1
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 236, 160), Color3.fromRGB(255, 186, 80)) }, l)
	make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(60, 34, 20), Transparency = 0.25 }, l)
	return l
end

-- A panel: dark, slightly see-through, with a soft border (headings inside are gold).
local function panel(parent, size, pos, anchor)
	local f = make("Frame", {
		Size = size,
		Position = pos,
		AnchorPoint = anchor or Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(30, 26, 44),
		BackgroundTransparency = 0.08,
	}, parent)
	corner(f, 14)
	make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(96, 86, 136), Transparency = 0.15 }, f)
	return f
end

---------------------------------------------------------------------------
-- 3D models for cards, heroes and terrain scenery
---------------------------------------------------------------------------

local buildModel
do
	-- A plain stand-in, only used if a card has no model data at all.
	local function placeholderModel(id)
		local def = CardData.Cards[id]
		local color = familyColor(def and def.family or "Any")
		local model = Instance.new("Model")
		local function piece(name, size, pos, c, shape)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = CFrame.new(pos)
			p.Color = c
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			if shape then
				p.Shape = shape
			end
			p.Parent = model
			return p
		end
		local root = piece("Root", Vector3.new(1, 0.1, 1), Vector3.new(0, 0, 0), color)
		root.Transparency = 1
		piece("Body", Vector3.new(2, 2, 2), Vector3.new(0, 1, 0), color, Enum.PartType.Ball)
		piece("Eye", Vector3.new(0.5, 0.5, 0.5), Vector3.new(-0.4, 1.3, -0.85), WHITE, Enum.PartType.Ball)
		piece("Eye", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0.4, 1.3, -0.85), WHITE, Enum.PartType.Ball)
		model.PrimaryPart = root
		return model
	end

	-- The 3D model for a card id (creature or building) or a hero ("hero_bonk").
	-- To use your own model, put a Model with the same name in ReplicatedStorage.CreatureModels.
	-- Build it facing -Z (the front of the part); its feet are placed on the table.
	function buildModel(id)
		local folder = ReplicatedStorage:FindFirstChild("CreatureModels")
		local custom = folder and folder:FindFirstChild(id)
		local model
		if custom and custom:IsA("Model") then
			model = custom:Clone()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			-- Stand the model on its feet: pivot at the bottom middle of its bounding box.
			pcall(function()
				local cf, size = model:GetBoundingBox()
				model.PrimaryPart = nil
				model.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0))
			end)
		else
			model = CreatureBuilder.build(id) or placeholderModel(id)
		end
		model.Name = id
		return model
	end
end

local function modelHeight(id)
	local info = CreatureBuilder.info(id)
	return info and info.height or 2.5
end

-- Particles and lights don't show inside card pictures, so leave them out there.
local function stripEffects(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

local function setScale(model, s)
	pcall(function()
		model:ScaleTo(math.max(0.05, s))
	end)
end

---------------------------------------------------------------------------
-- Cards (GUI)
---------------------------------------------------------------------------

-- Card life: the little 3D creature on a card sways and turns, rare cards get a shine that sweeps
-- across them, Mythic and up glow softly, and spell icons bob. Only cards that are "awake"
-- (in your hand, the big preview and pop-ups) move their creature, to keep phones fast.
local cardLife = {
	arts = setmetatable({}, { __mode = "k" }), -- [ViewportFrame] = { model, base, phase, yaw, alive, hover, spin }
	shines = setmetatable({}, { __mode = "k" }), -- [UIGradient] = { period, phase }
	glows = setmetatable({}, { __mode = "k" }), -- [UIStroke] = phase
	spins = setmetatable({}, { __mode = "k" }), -- [UIGradient] = degrees per second
	icons = setmetatable({}, { __mode = "k" }), -- [TextLabel] = phase
	artClock = 0,
}

-- Wake a card made by makeCard: its creature starts to move. Returns the art's state (nil for spells).
function cardLife.wake(card, spin)
	local view3d = card:FindFirstChild("ArtView", true)
	local a = view3d and cardLife.arts[view3d]
	if a then
		a.alive = true
		a.spin = spin -- turns slowly all the time (big preview, pop-ups)
	end
	return a
end

function cardLife.update(dt)
	for g, info in pairs(cardLife.shines) do
		local cyc = (clock + info.phase) % info.period
		g.Offset = Vector2.new(cyc < 0.85 and (-1 + 2 * cyc / 0.85) or 1.2, 0)
	end
	for stroke, phase in pairs(cardLife.glows) do
		stroke.Transparency = 0.15 + 0.12 * (0.5 + 0.5 * math.sin(clock * 1.3 + phase))
	end
	for g, speed in pairs(cardLife.spins) do
		g.Rotation = (clock * speed) % 360
	end
	for icon, phase in pairs(cardLife.icons) do
		icon.Rotation = math.sin(clock * 0.9 + phase) * 2.5
	end
	-- The creatures update 30 times a second, which is plenty for a slow sway.
	cardLife.artClock += dt
	if cardLife.artClock < 1 / 30 then
		return
	end
	local step = cardLife.artClock
	cardLife.artClock = 0
	for view3d, a in pairs(cardLife.arts) do
		if a.alive and view3d.Parent then
			if a.hover or a.spin then
				a.yaw += step * (a.hover and 1.8 or 0.6)
			else
				if a.yaw > math.pi or a.yaw < -math.pi then
					a.yaw = (a.yaw + math.pi) % (2 * math.pi) - math.pi
				end
				local sway = math.sin(clock * 0.6 + a.phase) * 0.25
				a.yaw += (sway - a.yaw) * math.min(1, step * 2.5)
			end
			local bob = math.sin(clock * 1.3 + a.phase) * 0.015 * a.h
			a.model:PivotTo(a.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, a.yaw, 0))
		end
	end
end

local addCardArt
do
	local SPELL_ICONS = {
		spare_battery = "🔋",
		wrong_turn = "🔄",
		snack_break = "🍪",
		coin_flip_fury = "💰",
		sneeze_storm = "🤧",
		bubble_wrap = "🛡️",
		pep_talk = "📣",
		terrain_shift = "🗺️",
		pothole = "🕳️",
		mystery_box = "🎁",
		earthquake_dance = "💃",
		total_chaos = "🌀",
		scrap = "🔩",
		water_balloon = "🎈",
	}

	-- The picture in the middle of a card: a small 3D view of the creature or building,
	-- or a big icon for spells.
	function addCardArt(art, def, calm)
		if def.type == "Spell" then
			local icon = label(art, SPELL_ICONS[def.id] or "✨", { Name = "Icon", Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), Font = Enum.Font.GothamBold })
			if not calm then
				cardLife.icons[icon] = math.random() * 6.28
			end
			return
		end
		local model = buildModel(def.id)
		stripEffects(model)
		local viewport = make("ViewportFrame", {
			Name = "ArtView",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(150, 150, 165),
			LightColor = Color3.fromRGB(255, 244, 228),
			LightDirection = Vector3.new(-0.6, -1, -0.8),
		}, art)
		model.Parent = viewport
		local info = CreatureBuilder.info(def.id) or { height = 2.5, width = 2.5, depth = 2.5 }
		local h = math.max(info.height, 0.5)
		local wide = math.max(info.width, info.depth)
		local look = Vector3.new(0, h * 0.48, 0)
		local dist = math.max(h * 2.3, wide * 1.35) + 0.8
		local yaw = math.rad(-28)
		local artCam = Instance.new("Camera")
		artCam.FieldOfView = 30
		artCam.CFrame = CFrame.lookAt(look + Vector3.new(math.sin(yaw) * dist, dist * 0.22, -math.cos(yaw) * dist), look)
		artCam.Parent = viewport
		viewport.CurrentCamera = artCam
		cardLife.arts[viewport] = { model = model, base = model:GetPivot(), phase = math.random() * 6.28, yaw = 0, h = h, alive = false }
	end
end

-- A card as a GUI frame. Used in the hand, the collection, pop-ups and the big preview.
-- calm = true: no shine sweeping across it and no glowing border.
-- calm = "compact": calm, and only the cost, name, picture and attack / health (the cards in your
-- hand in a match; hovering one shows the full card).
local function makeCard(parent, cardId, size, costOverride, calm)
	local compact = calm == "compact"
	local def = CardData.get(cardId)
	local hidden = def.rarity == "Secret" and costOverride == "hidden"
	local famColor = familyColor(def.family)
	local card = make("Frame", {
		Name = "Card",
		Size = size or UDim2.fromOffset(120, 168),
		BackgroundColor3 = famColor:Lerp(WHITE, 0.55),
	}, parent)
	corner(card, 10)
	local stroke = make("UIStroke", { Thickness = 4, Color = rgb(CardData.RarityColors[def.rarity]) }, card)
	local rank = ({ Epic = 1, Mythic = 2, Legendary = 3, Secret = 4 })[def.rarity]
	if calm then
		rank = nil
	end
	if rank and rank >= 2 then
		cardLife.glows[stroke] = math.random() * 6.28
	end
	if def.rarity == "Secret" and not calm then
		cardLife.spins[make("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
			}),
		}, stroke)] = 90
	end
	if hidden then
		label(card, "???", { TextColor3 = Color3.fromRGB(60, 50, 80), Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.3) })
		return card
	end
	local costCircle = make("Frame", { Name = "CostCircle", Size = UDim2.fromScale(0.3, 0.21), Position = UDim2.fromScale(-0.06, -0.05), BackgroundColor3 = Color3.fromRGB(40, 90, 200), ZIndex = 3 }, card)
	corner(costCircle, 100)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, costCircle)
	make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(20, 40, 110) }, costCircle)
	local cost = (type(costOverride) == "number") and costOverride or def.cost
	local costLabel = label(costCircle, tostring(cost), { Name = "Cost", ZIndex = 3 })
	if cost < def.cost then
		costLabel.TextColor3 = Color3.fromRGB(140, 255, 150)
	elseif cost > def.cost then
		costLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
	end
	label(card, def.name, {
		Name = "CardName",
		Size = UDim2.new(0.7, 0, 0.13, 0),
		Position = UDim2.fromScale(0.27, 0.03),
		TextColor3 = Color3.fromRGB(30, 25, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local art = make("Frame", {
		Name = "Art",
		Size = UDim2.fromScale(0.86, compact and 0.6 or 0.36),
		Position = UDim2.fromScale(0.07, 0.17),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
	}, card)
	corner(art, 8)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(famColor:Lerp(WHITE, 0.45), famColor:Lerp(BLACK, 0.35)) }, art)
	addCardArt(art, def, calm)
	if compact then
		if def.atk ~= nil then
			local function badge(text, color, x, anchorX)
				local b = label(card, text, { Name = "Stat", Size = UDim2.fromScale(0.42, 0.14), Position = UDim2.fromScale(x, 0.81), AnchorPoint = Vector2.new(anchorX, 0), BackgroundColor3 = color, BackgroundTransparency = 0, TextColor3 = WHITE, ZIndex = 3 })
				corner(b, 8)
				make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, b)
			end
			badge("⚔ " .. def.atk, Color3.fromRGB(190, 85, 60), 0.06, 0)
			badge("❤ " .. def.hp, Color3.fromRGB(60, 150, 95), 0.94, 1)
		else
			label(card, def.type, { Name = "Kind", Size = UDim2.fromScale(0.9, 0.11), Position = UDim2.fromScale(0.05, 0.83), Font = BODY_FONT, TextColor3 = Color3.fromRGB(60, 50, 70) })
		end
		return card
	end
	label(card, def.type .. (def.family ~= "Any" and (" · " .. def.family) or "") .. " · " .. def.rarity, {
		Size = UDim2.new(0.9, 0, 0.07, 0),
		Position = UDim2.fromScale(0.05, 0.54),
		Font = BODY_FONT,
		TextColor3 = Color3.fromRGB(60, 50, 70),
	})
	local textBox = make("Frame", { Name = "TextBox", Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.62), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25 }, card)
	corner(textBox, 6)
	local text = def.text
	if text == "" and def.type == "Creature" and not def.sparkText then
		text = "Just a good fighter."
	end
	-- Creatures with a Spark show it under their ability, in purple.
	local sparkShare = def.sparkText and (text == "" and 0.9 or 0.5) or 0
	if text ~= "" then
		label(textBox, text, {
			Name = "Ability",
			Font = BODY_FONT,
			TextColor3 = Color3.fromRGB(30, 25, 40),
			TextWrapped = true,
			Size = UDim2.fromScale(0.94, 0.9 - sparkShare),
			Position = UDim2.fromScale(0.03, 0.05),
		})
	end
	if def.sparkText then
		label(textBox, "🌀 Spark " .. (def.sparkCost or 0) .. "✨: " .. def.sparkText, {
			Name = "Spark",
			Font = BODY_FONT,
			TextColor3 = Color3.fromRGB(110, 40, 160),
			TextWrapped = true,
			Size = UDim2.fromScale(0.94, sparkShare),
			Position = UDim2.fromScale(0.03, 0.95 - sparkShare),
		})
	end
	if rank then
		-- A soft light sweeps across rare cards now and then (more often the rarer they are).
		local shine = make("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 4 }, card)
		corner(shine, 10)
		local sweep = make("UIGradient", {
			Rotation = 25,
			Offset = Vector2.new(1.2, 0),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, 1),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, shine)
		cardLife.shines[sweep] = { period = ({ 5.0, 3.8, 3.0, 2.4 })[rank], phase = math.random() * 4 }
	end
	if def.atk ~= nil then
		local stats = def.type == "Building" and ("❤ " .. def.hp) or ("⚔ " .. def.atk .. "   ❤ " .. def.hp)
		label(card, stats, {
			Size = UDim2.fromScale(0.9, 0.11),
			Position = UDim2.fromScale(0.05, 0.87),
			TextColor3 = Color3.fromRGB(30, 25, 40),
		})
	end
	return card
end

---------------------------------------------------------------------------
-- Pull reveal: the big card at the end of a pack opening
---------------------------------------------------------------------------

-- Shows a pulled card: a face-down card flies in and flips over (the front is made by makeCard,
-- so it looks just like the card in your hand), then its name, rarity, stats and keywords pop
-- in. Done flips it back and flies it away. Returns right away; the animation runs on its own.
-- opts (all optional):
--   from = Vector2: the screen point the card flies out of, like the winner's head in the
--          opening (default: the middle of the screen)
--   copies = how many copies the player owns now: 1 shows "NEW!", 2 or more shows "x2", "x3"...
--   onDone = function: called after Done, once the reveal is gone
--   onPullAgain = function: adds a "Pull again" button that closes the reveal and calls it
--   onCollection = function: adds a "Collection" button that closes the reveal and calls it
local showCardReveal
do
	local CARD_W, CARD_H = 240, 336
	local STAGE_W, STAGE_H = 640, 760 -- the layout below is drawn for this size, then scaled to fit
	local CENTER = Vector2.new(320, 330) -- where the card lands, in stage coordinates
	local RAINBOW = {
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(255, 220, 60),
		Color3.fromRGB(90, 220, 120),
		Color3.fromRGB(80, 160, 255),
		Color3.fromRGB(230, 90, 255),
	}
	local TIER_RANK = { Common = 0, Rare = 1, Epic = 2, Mythic = 3, Legendary = 4, Secret = 5 }
	local PullSounds = require(Shared:WaitForChild("PullSounds"))
	local current = nil

	local function tween(inst, seconds, props, style, direction)
		local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
		t:Play()
		return t
	end

	local function at(x, y)
		return UDim2.fromOffset(x, y)
	end

	-- The back of a card, framed in the tier's colour.
	local function cardBack(parent, tierColor)
		local back = make("Frame", { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, parent)
		corner(back, 10)
		make("UIStroke", { Thickness = 4, Color = tierColor }, back)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(95, 75, 160), Color3.fromRGB(35, 25, 60)) }, back)
		label(back, "DECK\nWARS", {
			Size = UDim2.fromScale(0.8, 0.3),
			Position = UDim2.fromScale(0.1, 0.35),
			TextColor3 = Color3.fromRGB(255, 220, 90),
			TextStrokeTransparency = 0.3,
		})
		return back
	end

	-- A ring in the tier's colour that rushes out from behind the card.
	local function ring(parent, color)
		local r = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = at(CENTER.X, CENTER.Y), Size = at(CARD_W, CARD_W), BackgroundTransparency = 1, ZIndex = 41 }, parent)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r)
		local stroke = make("UIStroke", { Thickness = 8, Color = color }, r)
		tween(r, 0.6, { Size = at(CARD_W * 3, CARD_W * 3) })
		tween(stroke, 0.6, { Transparency = 1 })
		Debris:AddItem(r, 0.7)
	end

	-- Little squares that burst out from behind the card (Mythic and up).
	local function confetti(parent, colors, count)
		for i = 1, count do
			local angle = (i / count) * math.pi * 2 + math.random() * 0.3
			local dist = 200 + math.random() * 140
			local bit = make("Frame", {
				Size = at(12, 12),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = at(CENTER.X, CENTER.Y),
				BackgroundColor3 = colors[(i - 1) % #colors + 1],
				Rotation = math.random(0, 90),
				ZIndex = 41,
			}, parent)
			tween(bit, 1.0, {
				Position = at(CENTER.X + math.cos(angle) * dist, CENTER.Y + math.sin(angle) * dist),
				Rotation = bit.Rotation + 200,
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quart)
			Debris:AddItem(bit, 1.1)
		end
	end

	-- Squash the card to nothing sideways, swap what shows, and open it up again: a fake 3D flip.
	local function flip(holder, hide, show)
		PullSounds.play("swish", { pitch = 1.3 })
		tween(holder, 0.12, { Size = at(0, CARD_H) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.12)
		hide.Visible = false
		show.Visible = true
		tween(holder, 0.12, { Size = at(CARD_W, CARD_H) })
		task.wait(0.12)
	end

	function showCardReveal(cardId, opts)
		opts = opts or {}
		if current then
			current:Destroy()
		end
		local def = CardData.get(cardId)
		local tierColor = rgb(CardData.RarityColors[def.rarity])
		local rank = TIER_RANK[def.rarity] or 0

		local root = make("Frame", {
			Name = "PullReveal",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 1,
			Active = true, -- clicks on the dark backdrop don't reach the room behind it
			ZIndex = 40,
		}, gui)
		current = root

		-- Everything is laid out on a 640 x 760 stage, shrunk to fit small screens.
		local vp = camera.ViewportSize
		local s = math.min(1, vp.X / (STAGE_W + 40), vp.Y / (STAGE_H + 20))
		local stage = make("Frame", { Name = "Stage", Size = at(STAGE_W, STAGE_H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 41 }, root)
		make("UIScale", { Scale = s }, stage)
		local from = CENTER
		if opts.from then
			from = Vector2.new((opts.from.X - (vp.X - STAGE_W * s) / 2) / s, (opts.from.Y - (vp.Y - STAGE_H * s) / 2) / s)
		end

		local holder = make("Frame", { Name = "Card", Size = at(CARD_W, CARD_H), AnchorPoint = Vector2.new(0.5, 0.5), Position = at(from.X, from.Y), BackgroundTransparency = 1, ZIndex = 42 }, stage)
		local grow = make("UIScale", { Scale = 0.2 }, holder)
		local back = cardBack(holder, tierColor)
		local front = makeCard(holder, cardId, UDim2.fromScale(1, 1))
		front.Visible = false

		-- Name, rarity, stats, keywords and buttons fade out together, so they share a group.
		local info = make("CanvasGroup", { Name = "Info", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 43 }, stage)

		task.spawn(function()
			local function gone()
				return current ~= root
			end

			-- 1. The face-down card flies in.
			tween(root, 0.3, { BackgroundTransparency = 0.45 })
			PullSounds.play("whoosh", { volume = 0.7, pitch = 1.2 })
			tween(holder, 0.45, { Position = at(CENTER.X, CENTER.Y) }, Enum.EasingStyle.Back)
			tween(grow, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(0.5)
			if gone() then
				return
			end

			-- 2. Flip it over.
			holder.Rotation = -4
			flip(holder, back, front)
			tween(holder, 0.3, { Rotation = 0 }, Enum.EasingStyle.Back)
			cardLife.wake(front, true)
			ring(stage, tierColor)
			local tier = PullRates.tierOf(def.rarity) or 1
			PullSounds.play("ding", { pitch = 0.9 + 0.1 * tier }) -- higher for rarer cards
			if tier >= 4 then
				PullSounds.play("ding", { volume = 0.6, pitch = 1.4 + 0.1 * tier })
			end
			if rank >= 3 then
				local colors = def.rarity == "Secret" and RAINBOW or { tierColor, WHITE, tierColor:Lerp(WHITE, 0.5) }
				confetti(stage, colors, rank == 5 and 48 or 28)
			end
			if opts.copies then
				local isNew = opts.copies <= 1
				local badge = label(holder, isNew and "NEW!" or ("x" .. opts.copies), {
					Size = at(78, 34),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(1, -8, 0, 8),
					Rotation = 12,
					BackgroundTransparency = 0,
					BackgroundColor3 = isNew and Color3.fromRGB(255, 80, 90) or Color3.fromRGB(70, 80, 120),
					TextStrokeTransparency = 0.4,
					ZIndex = 45,
				})
				corner(badge, 10)
				local pop = make("UIScale", { Scale = 0 }, badge)
				tween(pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				PullSounds.play(if isNew then "boing2" else "bonk2", { volume = 0.5, pitch = if isNew then 1.5 else 1.3 })
			end

			-- 3. The name slams in, with the rarity under it.
			local name = label(info, def.name, { Size = at(560, 52), AnchorPoint = Vector2.new(0.5, 1), Position = at(320, CENTER.Y - CARD_H / 2 - 40), TextStrokeTransparency = 0 })
			local slam = make("UIScale", { Scale = 1.6 }, name)
			tween(slam, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			PullSounds.play("thud", { volume = 0.8, pitch = 1.1 })
			local light = def.rarity == "Secret" or def.rarity == "Mythic"
			local rarity = label(info, string.upper(def.rarity), {
				Size = at(220, 28),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = at(320, CENTER.Y - CARD_H / 2 - 8),
				BackgroundTransparency = 0,
				BackgroundColor3 = tierColor,
				TextColor3 = light and BLACK or WHITE,
			})
			corner(rarity, 8)
			if def.rarity == "Secret" then
				make("UIGradient", { Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, RAINBOW[1]),
					ColorSequenceKeypoint.new(0.25, RAINBOW[2]),
					ColorSequenceKeypoint.new(0.5, RAINBOW[3]),
					ColorSequenceKeypoint.new(0.75, RAINBOW[4]),
					ColorSequenceKeypoint.new(1, RAINBOW[5]),
				}) }, rarity)
			end
			task.wait(0.2)

			-- 4. Cost, attack and health count up from 0.
			local stats = { { "✨", def.cost or 0 } }
			if def.atk ~= nil and def.type ~= "Building" then
				table.insert(stats, { "⚔", def.atk })
			end
			if def.hp ~= nil then
				table.insert(stats, { "❤", def.hp })
			end
			local statLabel = label(info, "", { Size = at(400, 30), AnchorPoint = Vector2.new(0.5, 0), Position = at(320, CENTER.Y + CARD_H / 2 + 14), TextStrokeTransparency = 0.3 })
			local t0 = os.clock()
			while not gone() do
				local a = math.min(1, (os.clock() - t0) / 0.4)
				local bits = {}
				for _, st in ipairs(stats) do
					table.insert(bits, st[1] .. " " .. math.floor(st[2] * a + 0.5))
				end
				statLabel.Text = table.concat(bits, "     ")
				if a >= 1 then
					break
				end
				task.wait()
			end
			if gone() then
				return
			end

			-- 5. Keyword chips pop in one by one, then the family's rule fades in.
			local keywords = {}
			for k in pairs(def.keywords or {}) do
				table.insert(keywords, k)
			end
			table.sort(keywords)
			if #keywords > 0 then
				local row = make("Frame", { Name = "Keywords", Size = at(600, 26), AnchorPoint = Vector2.new(0.5, 0), Position = at(320, CENTER.Y + CARD_H / 2 + 52), BackgroundTransparency = 1 }, info)
				make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }, row)
				for i, k in ipairs(keywords) do
					local chip = label(row, k, { Size = at(92, 26), BackgroundTransparency = 0, BackgroundColor3 = tierColor:Lerp(BLACK, 0.4) })
					corner(chip, 13)
					local pop = make("UIScale", { Scale = 0 }, chip)
					tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
					PullSounds.play("bonk2", { volume = 0.35, pitch = 1.8 + 0.1 * i })
					task.wait(0.08)
				end
			end
			local rule = CardData.FamilyRules[def.family]
			if rule then
				local ruleLabel = label(info, rule.name .. ": " .. rule.text, {
					Size = at(560, 40),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = at(320, CENTER.Y + CARD_H / 2 + 86),
					Font = BODY_FONT,
					TextWrapped = true,
					TextColor3 = familyColor(def.family):Lerp(WHITE, 0.45),
					TextTransparency = 1,
				})
				tween(ruleLabel, 0.3, { TextTransparency = 0 })
			end

			-- 6. The buttons wait a moment, so a tap meant to skip can't press one by accident.
			task.wait(0.6)
			if gone() then
				return
			end
			local bar = make("Frame", { Name = "Buttons", Size = at(600, 48), AnchorPoint = Vector2.new(0.5, 0), Position = at(320, CENTER.Y + CARD_H / 2 + 146), BackgroundTransparency = 1 }, info)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10) }, bar)

			-- 7. Closing: the card flips to its back, then drops away while everything fades.
			local closing = false
			local function close(after)
				if closing or gone() then
					return
				end
				closing = true
				bar:Destroy()
				flip(holder, front, back)
				PullSounds.play("whoosh", { volume = 0.6, pitch = 0.8 })
				tween(holder, 0.45, { Position = at(CENTER.X, STAGE_H + CARD_H) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				tween(grow, 0.45, { Scale = 0.3 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				tween(info, 0.3, { GroupTransparency = 1 })
				tween(root, 0.45, { BackgroundTransparency = 1 })
				task.wait(0.45)
				root:Destroy()
				if current == root then
					current = nil
				end
				if after then
					after()
				end
			end
			if opts.onPullAgain then
				button(bar, "Pull again", Color3.fromRGB(240, 160, 50), function()
					task.spawn(close, opts.onPullAgain)
				end, { Name = "PullAgain", Size = at(170, 48) })
			end
			if opts.onCollection then
				button(bar, "Collection", Color3.fromRGB(90, 80, 140), function()
					task.spawn(close, opts.onCollection)
				end, { Name = "Collection", Size = at(170, 48) })
			end
			button(bar, "Done", Color3.fromRGB(70, 130, 220), function()
				task.spawn(close, opts.onDone)
			end, { Name = "Done", Size = at(170, 48) })
		end)
		return root
	end
end

-- All the on-screen panels, buttons and labels live in this table.
local ui = {}

---------------------------------------------------------------------------
-- Menu room UI
---------------------------------------------------------------------------

ui.menuUI = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
headingStyle(label(ui.menuUI, "DECK WARS", {
	Name = "Title",
	Size = UDim2.fromOffset(300, 40),
	Position = UDim2.fromOffset(26, 66),
	TextScaled = false,
	TextSize = 36,
	TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Left,
}))
label(ui.menuUI, "Click the Duel Table to play", {
	Name = "Subtitle",
	Size = UDim2.fromOffset(300, 18),
	Position = UDim2.fromOffset(28, 106),
	Font = BODY_FONT,
	TextScaled = false,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(200, 194, 222),
	TextXAlignment = Enum.TextXAlignment.Left,
})
-- You: your level and XP, your Gems, your win streak and today's first-win bonus. The server keeps
-- the real numbers and shows them as attributes on your Player (Level, XP, Gems...).
ui.profile = panel(ui.menuUI, UDim2.fromOffset(320, 66), UDim2.fromOffset(24, 134))
ui.profile.Name = "Profile"
ui.levelBadge = label(ui.profile, "1", { Name = "Level", Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(11, 11), BackgroundColor3 = Color3.fromRGB(80, 66, 140), BackgroundTransparency = 0, TextScaled = false, TextSize = 20, TextColor3 = Color3.fromRGB(255, 230, 140) })
corner(ui.levelBadge, 22)
make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(255, 210, 110), Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ui.levelBadge)
ui.xpText = label(ui.profile, "", { Name = "XPText", Size = UDim2.new(1, -160, 0, 16), Position = UDim2.fromOffset(66, 11), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(210, 206, 235), TextXAlignment = Enum.TextXAlignment.Left })
ui.xpBack = make("Frame", { Size = UDim2.new(1, -164, 0, 8), Position = UDim2.fromOffset(66, 31), BackgroundColor3 = Color3.fromRGB(50, 44, 72) }, ui.profile)
corner(ui.xpBack, 4)
ui.xpFill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(130, 200, 255) }, ui.xpBack)
corner(ui.xpFill, 4)
ui.profileExtra = label(ui.profile, "", { Name = "Extra", Size = UDim2.new(1, -160, 0, 14), Position = UDim2.fromOffset(66, 43), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextColor3 = Color3.fromRGB(255, 200, 130), TextXAlignment = Enum.TextXAlignment.Left })
-- Your Gems (the server keeps the real number and shows it as an attribute on your Player).
ui.gemsLabel = label(ui.profile, "", {
	Name = "Gems",
	Size = UDim2.fromOffset(86, 26),
	Position = UDim2.new(1, -12, 0.5, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	TextScaled = false,
	TextSize = 20,
	TextColor3 = Color3.fromRGB(130, 220, 255),
	TextXAlignment = Enum.TextXAlignment.Right,
})
do
	local function refreshProfile()
		local gems = player:GetAttribute("Gems")
		ui.gemsLabel.Text = if gems then "💎 " .. gems else ""
		local level = player:GetAttribute("Level") or 1
		local xp = player:GetAttribute("XP") or 0
		local need = player:GetAttribute("XPNeeded") or Progression.xpForLevel(level)
		ui.levelBadge.Text = tostring(level)
		ui.xpText.Text = "Level " .. level .. "   ·   " .. xp .. " / " .. need .. " XP"
		ui.xpFill.Size = UDim2.fromScale(math.clamp(xp / math.max(1, need), 0, 1), 1)
		local bits = {}
		local streak = player:GetAttribute("WinStreak") or 0
		if streak >= 2 then
			table.insert(bits, "🔥 " .. streak .. " wins in a row")
		end
		if player:GetAttribute("FirstWinReady") == true then
			table.insert(bits, "⭐ First win: +" .. Progression.FirstWinBonus .. " 💎")
		end
		ui.profileExtra.Text = table.concat(bits, "   ")
	end
	player.AttributeChanged:Connect(function(name)
		if name == "Gems" or name == "Level" or name == "XP" or name == "XPNeeded" or name == "WinStreak" or name == "FirstWinReady" then
			refreshProfile()
		end
	end)
	refreshProfile()
end

ui.navBar = make("Frame", { Size = UDim2.new(1, 0, 0, 64), Position = UDim2.new(0, 0, 1, -72), BackgroundTransparency = 1 }, ui.menuUI)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }, ui.navBar)

ui.stationPanel = panel(ui.menuUI, UDim2.fromOffset(400, 520), UDim2.new(1, -24, 0.5, 14), Vector2.new(1, 0.5))
ui.stationPanel.Visible = false
ui.stationTitle = headingStyle(label(ui.stationPanel, "", { Name = "StationTitle", Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 12), TextScaled = false, TextSize = 24, TextColor3 = WHITE }))
ui.stationBody = make("Frame", { Size = UDim2.new(1, -24, 1, -62), Position = UDim2.fromOffset(12, 52), BackgroundTransparency = 1 }, ui.stationPanel)



local selectStation
local startPull -- set up further down, next to pullMode
do
	local function clearBody()
		for _, child in ipairs(ui.stationBody:GetChildren()) do
			child:Destroy()
		end
		if ui.collectionUI then
			ui.collectionUI.Visible = false
		end
	end

	-- Play the bot, or open a table for friends (1v1, 2v2, tournament). See LobbyScreen.
	local function showDuelTablePanel()
		clearBody()
		ui.stationTitle.Text = "Duel Table"
		LobbyScreen.show(ui.stationBody)
	end

	local function buildCollection()
		-- Under your level and Gems (top left), above the buttons at the bottom.
		ui.collectionUI = panel(ui.menuUI, UDim2.new(0.6, 0, 1, -320), UDim2.fromOffset(24, 232), Vector2.new(0, 0))
		label(ui.collectionUI, "Collection (" .. #CardData.List .. " cards)", { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 8), TextColor3 = Color3.fromRGB(255, 220, 90) })
		local scroll = make("ScrollingFrame", {
			Size = UDim2.new(1, -24, 1, -60),
			Position = UDim2.fromOffset(12, 52),
			BackgroundTransparency = 1,
			ScrollBarThickness = 8,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, ui.collectionUI)
		make("UIGridLayout", { CellSize = UDim2.fromOffset(130, 182), CellPadding = UDim2.fromOffset(12, 12) }, scroll)
		make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8) }, scroll)
		for _, id in ipairs(CardData.List) do
			makeCard(scroll, id, nil, CardData.Cards[id].rarity == "Secret" and "hidden" or nil)
		end
	end

	local function showDeckShelfPanel()
		clearBody()
		ui.stationTitle.Text = "Deck Shelf"
		if not ui.collectionUI then
			buildCollection()
		end
		ui.collectionUI.Visible = true
		local scroll = make("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 6 }, ui.stationBody)
		make("UIListLayout", { Padding = UDim.new(0, 2) }, scroll)
		for _, key in ipairs(StarterDecks.Order) do
			local deck = StarterDecks[key]
			label(scroll, deck.name .. " (" .. CardData.Heroes[deck.hero].name .. ")", { Size = UDim2.new(1, 0, 0, 28), TextColor3 = Color3.fromRGB(255, 200, 120) })
			local counts, order = {}, {}
			for _, id in ipairs(deck.cards) do
				if not counts[id] then
					table.insert(order, id)
				end
				counts[id] = (counts[id] or 0) + 1
			end
			for _, id in ipairs(order) do
				label(scroll, counts[id] .. "x  " .. CardData.get(id).name, { Size = UDim2.new(1, 0, 0, 20), Font = BODY_FONT, TextXAlignment = Enum.TextXAlignment.Left })
			end
		end
		label(scroll, "Building your own decks arrives in the next update.", { Size = UDim2.new(1, 0, 0, 36), Font = BODY_FONT, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 200, 220) })
	end

	local function showComingSoon(title, text)
		clearBody()
		ui.stationTitle.Text = title
		label(ui.stationBody, text, { Font = BODY_FONT, TextWrapped = true, TextScaled = false, TextSize = 20, TextYAlignment = Enum.TextYAlignment.Top })
	end

	-- Pack Party: Gems, the Pull button and the drop rates.
	local function showPackPartyPanel()
		clearBody()
		ui.stationTitle.Text = "Pack Party"
		make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, ui.stationBody)
		label(ui.stationBody, "Pull the lever for a random card. The rarer it is, the wilder the fight!", { Size = UDim2.new(1, 0, 0, 44), Font = BODY_FONT, TextWrapped = true, TextColor3 = Color3.fromRGB(230, 225, 240), LayoutOrder = 1 })
		local gemsText = label(ui.stationBody, "", { Size = UDim2.new(1, 0, 0, 30), TextColor3 = Color3.fromRGB(120, 220, 255), LayoutOrder = 2 })
		local pullButton = button(ui.stationBody, "", Color3.fromRGB(240, 160, 50), function()
			if startPull then
				startPull()
			end
		end, { Name = "PullButton", Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 3 })
		ui.pullStatus = label(ui.stationBody, "", { Size = UDim2.new(1, 0, 0, 30), Font = BODY_FONT, TextWrapped = true, TextColor3 = Color3.fromRGB(255, 170, 170), LayoutOrder = 4 })
		local conn
		local function refresh()
			if not gemsText.Parent then
				conn:Disconnect() -- the panel was closed
				return
			end
			local gems = player:GetAttribute("Gems")
			gemsText.Text = if gems then "💎 " .. gems .. " Gems" else "💎 Loading your Gems..."
			pullButton.Text = "PULL!   💎 " .. PullRates.Cost
			local canPull = gems ~= nil and gems >= PullRates.Cost
			pullButton.BackgroundColor3 = if canPull then Color3.fromRGB(240, 160, 50) else Color3.fromRGB(110, 100, 125)
		end
		conn = player:GetAttributeChangedSignal("Gems"):Connect(refresh)
		refresh()
		label(ui.stationBody, "Drop rates", { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 5 })
		for i, t in ipairs(PullRates.Tiers) do
			label(ui.stationBody, t.rarity .. "   " .. t.percent .. "%", { Size = UDim2.new(1, 0, 0, 18), Font = BODY_FONT, TextColor3 = rgb(CardData.RarityColors[t.rarity]), TextStrokeTransparency = 0.5, LayoutOrder = 5 + i })
		end
		local win = PullRates.WinGems
		label(ui.stationBody, "Win matches for Gems: bots +" .. win.Easy .. "/+" .. win.Medium .. "/+" .. win.Hard .. ", friends +" .. (PullRates.PvPWinGems or 40) .. ", tournament +" .. (PullRates.CupWinGems or 150), { Size = UDim2.new(1, 0, 0, 40), Font = BODY_FONT, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 200, 220), LayoutOrder = 20 })
	end

	-- Quests & Rewards (the Trophy Wall): your level, the daily reward, today's three quests and
	-- the first-win bonus. Everything here comes from attributes the server keeps on your Player.
	local function showTrophyPanel()
		clearBody()
		ui.stationTitle.Text = "Quests & Rewards"
		local body = ui.stationBody
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
		local GOLD = Color3.fromRGB(255, 220, 110)
		local DIM = Color3.fromRGB(185, 180, 205)
		local function box(order, height, name)
			local f = make("Frame", { Name = name, Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Color3.fromRGB(44, 38, 64), LayoutOrder = order }, body)
			corner(f, 10)
			return f
		end
		local function bar(parent, pos, size)
			local back = make("Frame", { Size = size, Position = pos, BackgroundColor3 = Color3.fromRGB(28, 24, 42) }, parent)
			corner(back, 6)
			local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(130, 200, 255) }, back)
			corner(fill, 6)
			return fill
		end
		-- Level
		local lv = box(1, 60, "LevelBox")
		local lvText = label(lv, "", { Size = UDim2.new(0.6, -10, 0, 24), Position = UDim2.fromOffset(10, 6), TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local lvNext = label(lv, "", { Size = UDim2.new(0.4, -10, 0, 20), Position = UDim2.new(0.6, 0, 0, 8), Font = BODY_FONT, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Right })
		local lvFill = bar(lv, UDim2.fromOffset(10, 38), UDim2.new(1, -20, 0, 12))
		-- Daily reward
		local daily = box(2, 64, "DailyBox")
		local dText = label(daily, "", { Size = UDim2.new(1, -130, 0, 24), Position = UDim2.fromOffset(10, 6), TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local dSub = label(daily, "", { Size = UDim2.new(1, -130, 0, 20), Position = UDim2.fromOffset(10, 36), Font = BODY_FONT, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
		local dButton = button(daily, "Claim", Color3.fromRGB(60, 170, 90), function()
			Remotes.MenuAction:FireServer("ClaimDaily")
		end, { Name = "ClaimDaily", Size = UDim2.fromOffset(104, 40), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
		-- First win and streak
		local extra = label(body, "", { Name = "Bonuses", Size = UDim2.new(1, 0, 0, 22), Font = BODY_FONT, TextColor3 = Color3.fromRGB(255, 205, 140), LayoutOrder = 3 })
		label(body, "Today's quests", { Size = UDim2.new(1, 0, 0, 26), TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4 })
		local rows = {}
		for i = 1, Progression.QuestsPerDay do
			local q = box(4 + i, 60, "Quest" .. i)
			local r = {}
			r.text = label(q, "", { Size = UDim2.new(1, -124, 0, 22), Position = UDim2.fromOffset(10, 6), Font = BODY_FONT, TextXAlignment = Enum.TextXAlignment.Left })
			r.fill = bar(q, UDim2.fromOffset(10, 36), UDim2.new(1, -184, 0, 10))
			r.count = label(q, "", { Size = UDim2.fromOffset(56, 18), Position = UDim2.new(1, -168, 0, 32), Font = BODY_FONT, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
			r.button = button(q, "", Color3.fromRGB(60, 170, 90), function()
				Remotes.MenuAction:FireServer("ClaimQuest", { index = i })
			end, { Name = "ClaimQuest" .. i, Size = UDim2.fromOffset(104, 40), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
			rows[i] = r
		end
		local resetText = label(body, "", { Size = UDim2.new(1, 0, 0, 20), Font = BODY_FONT, TextColor3 = DIM, LayoutOrder = 20 })

		local function untilReset()
			local left = Progression.secondsToReset(os.time())
			return string.format("%dh %02dm", math.floor(left / 3600), math.floor(left % 3600 / 60))
		end
		local function refresh()
			local level = player:GetAttribute("Level") or 1
			local xp = player:GetAttribute("XP") or 0
			local need = player:GetAttribute("XPNeeded") or Progression.xpForLevel(level)
			lvText.Text = "Level " .. level .. "  ·  " .. xp .. " / " .. need .. " XP"
			lvNext.Text = "Level " .. (level + 1) .. ": +" .. Progression.levelReward(level + 1) .. " 💎"
			lvFill.Size = UDim2.fromScale(math.clamp(xp / math.max(1, need), 0, 1), 1)
			local ready = player:GetAttribute("DailyReady") == true
			local day = player:GetAttribute("DailyDay") or 1
			if ready then
				dText.Text = "Daily reward: day " .. day
				dSub.Text = "Come back tomorrow for day " .. (day + 1) .. " (+" .. Progression.dailyReward(day + 1) .. " 💎)"
				dButton.Text = "+" .. Progression.dailyReward(day) .. " 💎"
				dButton.Visible = true
			else
				dText.Text = "✓ Daily reward claimed"
				dSub.Text = "Day " .. (day + 1) .. " (+" .. Progression.dailyReward(day + 1) .. " 💎) in " .. untilReset()
				dButton.Visible = false
			end
			local bits = {}
			bits[1] = player:GetAttribute("FirstWinReady") == true and ("⭐ First win today: +" .. Progression.FirstWinBonus .. " 💎") or "✓ First win bonus done for today"
			local streak = player:GetAttribute("WinStreak") or 0
			if streak >= 1 then
				table.insert(bits, "🔥 Streak " .. streak)
			end
			extra.Text = table.concat(bits, "   ")
			for i, r in ipairs(rows) do
				local def = Progression.QuestById[player:GetAttribute("Quest" .. i .. "Id") or ""]
				local progress = player:GetAttribute("Quest" .. i .. "Progress") or 0
				local claimed = player:GetAttribute("Quest" .. i .. "Claimed") == true
				r.text.Parent.Visible = def ~= nil
				if def then
					r.text.Text = (claimed and "✓ " or "") .. def.text
					r.text.TextColor3 = claimed and DIM or WHITE
					r.count.Text = math.min(progress, def.target) .. "/" .. def.target
					r.fill.Size = UDim2.fromScale(math.clamp(progress / def.target, 0, 1), 1)
					local done = progress >= def.target
					r.button.Text = claimed and "Done" or ("+" .. def.gems .. " 💎")
					r.button.AutoButtonColor = done and not claimed
					r.button.BackgroundColor3 = (done and not claimed) and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(70, 64, 92)
				end
			end
			resetText.Text = "New quests in " .. untilReset() .. " · every quest also gives +" .. Progression.QuestXP .. " XP"
		end
		local conn
		conn = player.AttributeChanged:Connect(function()
			if not body.Parent or not lvText.Parent then
				conn:Disconnect()
				return
			end
			refresh()
		end)
		refresh()
		task.spawn(function()
			while lvText.Parent do
				task.wait(30)
				if lvText.Parent then
					refresh()
				end
			end
		end)
	end

	local STATIONS = {
		{ key = "DuelTable", name = "Duel Table", show = showDuelTablePanel },
		{ key = "DeckShelf", name = "Deck Shelf", show = showDeckShelfPanel },
		{
			key = "PackParty",
			name = "Pack Party",
			show = showPackPartyPanel,
		},
		-- Shop and Settings aren't built yet: they open from the room (click the counter or the radio)
		-- but get no button at the bottom, so the menu only shows what you can use.
		{
			key = "ShopCounter",
			name = "Shop",
			nav = false,
			show = function()
				showComingSoon("Shop", "Pickles the shopkeeper will sell packs, Gems and cosmetics here.\n\nComing in a later update.")
			end,
		},
		{ key = "TrophyWall", name = "Quests", show = showTrophyPanel },
		{
			key = "Radio",
			name = "Settings",
			nav = false,
			show = function()
				showComingSoon("Settings", "Music and sound settings will live in this radio.\n\nComing in a later update.")
			end,
		},
	}
	local stationByKey = {}
	for _, s in ipairs(STATIONS) do
		stationByKey[s.key] = s
	end

	function selectStation(key)
		local s = stationByKey[key]
		if not s or mode ~= "menu" then
			return
		end
		moveCamera(key)
		currentStation = key
		ui.stationPanel.Visible = true
		s.show()
	end

	ui.navButtons = {}
	for i, s in ipairs(STATIONS) do
		if s.nav ~= false then
			ui.navButtons[s.key] = button(ui.navBar, s.name, Color3.fromRGB(70, 60, 110), function()
				selectStation(s.key)
			end, { Name = "Nav" .. s.key, LayoutOrder = i, Size = UDim2.fromOffset(150, 52), TextScaled = false, TextSize = 22 })
		end
	end
	-- A little "!" on Quests when there's something to collect.
	do
		local badge = label(ui.navButtons.TrophyWall, "!", { Name = "Badge", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, 4, 0, -8), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(230, 70, 80), BackgroundTransparency = 0, Visible = false, ZIndex = 5 })
		corner(badge, 12)
		local function refreshBadge()
			badge.Visible = player:GetAttribute("DailyReady") == true or (player:GetAttribute("QuestsReady") or 0) > 0
		end
		player.AttributeChanged:Connect(function(name)
			if name == "DailyReady" or name == "QuestsReady" then
				refreshBadge()
			end
		end)
		refreshBadge()
	end
	button(ui.navBar, "Back", Color3.fromRGB(110, 60, 70), function()
		ui.stationPanel.Visible = false
		currentStation = nil
		if ui.collectionUI then
			ui.collectionUI.Visible = false
		end
		moveCamera("Overview")
	end, { LayoutOrder = 99, Size = UDim2.fromOffset(110, 52), TextScaled = false, TextSize = 22 })
end

---------------------------------------------------------------------------
-- The daily reward pop-up (once a visit, when today's reward is waiting) and the replies to
-- claiming rewards
---------------------------------------------------------------------------

local function chime(pitch)
	pcall(function()
		require(Shared:WaitForChild("PullSounds")).play("ding", { volume = 0.5, pitch = pitch or 1 })
	end)
end

ui.dailyPopup = panel(ui.menuUI, UDim2.fromOffset(560, 250), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))
ui.dailyPopup.Name = "DailyPopup"
ui.dailyPopup.Visible = false
ui.dailyPopup.ZIndex = 45
headingStyle(label(ui.dailyPopup, "🎁 Daily reward", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 14), TextScaled = false, TextSize = 28, TextColor3 = WHITE }))
label(ui.dailyPopup, "Come back every day: the rewards grow, and day 7 is the big one.", { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 52), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(205, 200, 225) })
ui.dailyTiles = make("Frame", { Name = "Days", Size = UDim2.new(1, -24, 0, 78), Position = UDim2.fromOffset(12, 80), BackgroundTransparency = 1 }, ui.dailyPopup)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }, ui.dailyTiles)
ui.dailyClaim = button(ui.dailyPopup, "Claim", Color3.fromRGB(60, 170, 90), function()
	Remotes.MenuAction:FireServer("ClaimDaily")
end, { Name = "ClaimDaily", Size = UDim2.fromOffset(220, 50), Position = UDim2.new(0.5, -6, 1, -14), AnchorPoint = Vector2.new(1, 1) })
button(ui.dailyPopup, "Later", Color3.fromRGB(80, 74, 104), function()
	ui.dailyPopup.Visible = false
end, { Name = "DailyLater", Size = UDim2.fromOffset(120, 50), Position = UDim2.new(0.5, 6, 1, -14), AnchorPoint = Vector2.new(0, 1) })

local function showDailyPopup()
	local day = player:GetAttribute("DailyDay") or 1
	local n = #Progression.DailyRewards
	local today = ((day - 1) % n) + 1
	for _, c in ipairs(ui.dailyTiles:GetChildren()) do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	for i = 1, n do
		local past, now = i < today, i == today
		local tile = make("Frame", { Name = "Day" .. i, Size = UDim2.fromOffset(68, 76), BackgroundColor3 = now and Color3.fromRGB(80, 66, 140) or Color3.fromRGB(44, 38, 64), LayoutOrder = i }, ui.dailyTiles)
		corner(tile, 10)
		if now then
			make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(255, 210, 100) }, tile)
		end
		label(tile, past and "✓" or ("Day " .. i), { Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 6), TextColor3 = past and Color3.fromRGB(140, 230, 150) or Color3.fromRGB(235, 230, 245) })
		label(tile, "+" .. Progression.DailyRewards[i] .. " 💎", { Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 42), Font = BODY_FONT, TextColor3 = past and Color3.fromRGB(150, 145, 170) or Color3.fromRGB(130, 220, 255) })
	end
	ui.dailyClaim.Text = "Claim +" .. Progression.dailyReward(day) .. " 💎"
	ui.dailyPopup.Visible = true
end

-- Shown once a visit, in the room, when today's reward is ready.
do
	local shown = false
	local function check()
		if shown or mode ~= "menu" or player:GetAttribute("DailyReady") ~= true or player:GetAttribute("ProgressLoaded") ~= true then
			return
		end
		shown = true
		task.delay(1.5, function()
			if mode == "menu" and player:GetAttribute("DailyReady") == true then
				showDailyPopup()
			end
		end)
	end
	player.AttributeChanged:Connect(function(name)
		if name == "DailyReady" or name == "ProgressLoaded" then
			check()
		end
	end)
	task.defer(check)
	ui.checkDaily = check
end

Remotes:WaitForChild("LobbyEvent").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "claimed" then
		return
	end
	if not payload.ok then
		return
	end
	if payload.what == "daily" then
		ui.dailyPopup.Visible = false
		LobbyScreen.toast("🎁 Daily reward: +" .. tostring(payload.gems) .. " 💎 (day " .. tostring(payload.day) .. ")")
		chime(1)
	elseif payload.what == "quest" then
		local text = "📜 Quest done: +" .. tostring(payload.gems) .. " 💎 and +" .. tostring(payload.xp) .. " XP"
		for _, up in ipairs(payload.levelUps or {}) do
			text = text .. "   ⭐ Level " .. up.level .. "! +" .. up.gems .. " 💎"
		end
		LobbyScreen.toast(text)
		chime(1.15)
	end
end)

-- Clicking and hovering over stations in the 3D room
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 0.8
highlight.OutlineColor = Color3.fromRGB(255, 220, 90)
highlight.Enabled = false
highlight.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { stations }

-- Mouse location (viewport coordinates) or a click position (screen coordinates).
local function stationAt(pos, isScreen)
	local ray = isScreen and camera:ScreenPointToRay(pos.X, pos.Y) or camera:ViewportPointToRay(pos.X, pos.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
	if not hit then
		return nil, nil
	end
	local inst = hit.Instance
	local partHit = inst
	while inst and inst.Parent ~= stations do
		inst = inst.Parent
	end
	return inst, partHit
end

---------------------------------------------------------------------------
-- Match screen: the lanes, your hand and the playback live in the MatchScreen module.
-- Lobbies (1v1, 2v2, tournaments) live in LobbyScreen.
---------------------------------------------------------------------------

-- The signs over the stations in the room: small, soft labels in title case (they used to be big
-- outlined capitals that ran off the edges of the screen). The Trophy Wall is where the quests are.
do
	local NAMES = { ["PACK PARTY"] = "Pack Party", ["DUEL TABLE"] = "Duel Table", ["SHOP"] = "Shop", ["SETTINGS"] = "Settings", ["DECK SHELF"] = "Deck Shelf", ["TROPHY WALL"] = "Quests" }
	for _, d in ipairs(stations:GetDescendants()) do
		if d:IsA("BillboardGui") and d.Name == "Sign" then
			local text = d:FindFirstChildWhichIsA("TextLabel")
			if text then
				local main = text.Text == "DUEL TABLE"
				d.Size = main and UDim2.new(5, 0, 1.15, 0) or UDim2.new(6.4, 0, 1.45, 0) -- in studs (the side ones are further away)
				d.LightInfluence = 0
				text.Text = NAMES[text.Text] or text.Text
				text.Font = FONT
				text.TextScaled = true
				text.TextColor3 = main and Color3.fromRGB(255, 226, 140) or Color3.fromRGB(245, 240, 255)
				text.TextStrokeTransparency = 1
				text.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
				text.BackgroundTransparency = 0.3
				corner(text, 10)
				make("UIPadding", { PaddingTop = UDim.new(0.14, 0), PaddingBottom = UDim.new(0.14, 0), PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0) }, text)
				make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(110, 96, 150), Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, text)
			end
		end
	end
end

local function setStationSigns(on)
	for _, d in ipairs(stations:GetDescendants()) do
		if d:IsA("BillboardGui") and d.Name == "Sign" then
			d.Enabled = on
		end
	end
end

-- Your own character sits at the near chair; hide it so it doesn't block the table.
local function hideCharacter(hidden)
	local char = player.Character
	if not char then
		return
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

-- Where the camera sits in a match. A 2v2 table has 8 lanes a side, so the camera pulls back and
-- zooms out (it stays under the ceiling beams at 17 studs and the lamps over the table).
local function setTableWidth(width)
	if width > 4 then
		CAMS.Seat = { Vector3.new(0, 16.2, 15.8), Vector3.new(0, 3.6, 0.2), 60 }
	else
		CAMS.Seat = { Vector3.new(0, 15.8, 12.8), Vector3.new(0, 4.1, 0.2), 50 }
	end
	CAMS.SeatYou = CAMS.Seat
	CAMS.SeatOpp = CAMS.Seat
	moveCamera("Seat", false, 1.4)
end

-- A match in one of the background worlds opens on a wide shot of it with its name, then the
-- camera glides down to your seat (the lanes rise out of the table meanwhile).
ui.worldTitle = label(gui, "", {
	Name = "WorldTitle",
	Size = UDim2.fromOffset(640, 48),
	Position = UDim2.new(0.5, 0, 0.16, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	TextScaled = false,
	TextSize = 36,
	TextColor3 = Color3.fromRGB(255, 238, 170),
	TextStrokeColor3 = Color3.fromRGB(40, 24, 16),
	TextStrokeTransparency = 0.4,
	Visible = false,
	ZIndex = 40,
})
local INTRO_HOLD = 1.8
-- A click or a key during the opening shot skips it.
local function skipIntro()
	if mode == "match" and clock < intro.untilClock then
		intro.untilClock = 0
		moveCamera(intro.pending or "Seat", false, 1.2)
		intro.pending = nil
		ui.worldTitle.Visible = false
		return true
	end
	return false
end
local function showIntro(key)
	local shot = Backdrops.intro()
	local info = Backdrops.ByKey[key]
	if not shot or not info then
		return false
	end
	camera.CameraType = Enum.CameraType.Scriptable
	glideCamera(shot.pos, shot.look, 0, shot.fov)
	glideCamera(shot.pos + shot.drift, shot.look, INTRO_HOLD + 0.4, shot.fov)
	intro.untilClock = clock + INTRO_HOLD * PACE
	intro.pending = "Seat"
	ui.worldTitle.Text = info.emoji .. "  " .. info.name
	ui.worldTitle.TextTransparency = 0
	ui.worldTitle.TextStrokeTransparency = 0.4
	ui.worldTitle.Visible = true
	TweenService:Create(ui.worldTitle, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, INTRO_HOLD * PACE), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	local until_ = intro.untilClock
	task.delay(INTRO_HOLD * PACE, function()
		if intro.untilClock ~= until_ then
			return -- skipped
		end
		intro.untilClock = 0
		if mode == "match" then
			moveCamera(intro.pending or "Seat", false, 2.4)
		end
		intro.pending = nil
	end)
	task.delay((INTRO_HOLD + 0.9) * PACE, function()
		ui.worldTitle.Visible = false
	end)
	return true
end

-- Your settings: deck, bot difficulty, background, action camera, speed, and whether you've seen
-- the how-to-play screen. The server keeps them as "Pref..." attributes on your Player and saves
-- them with your cards; changes are sent a second after the last one. Something you change in
-- this visit wins over a saved value that arrives late.
local prefs = { mine = {}, pending = {}, queued = false }
function prefs.get(key)
	local v = prefs.mine[key]
	if v == nil then
		v = player:GetAttribute("Pref" .. key)
	end
	return v
end
function prefs.set(key, value)
	prefs.mine[key] = value
	prefs.pending[key] = value
	if not prefs.queued then
		prefs.queued = true
		task.delay(1, function()
			prefs.queued = false
			local send = prefs.pending
			prefs.pending = {}
			Remotes.MenuAction:FireServer("SavePrefs", send)
		end)
	end
end

LobbyScreen.init({
	ui = ui,
	gui = gui,
	headingStyle = headingStyle,
	make = make,
	corner = corner,
	label = label,
	button = button,
	panel = panel,
	WHITE = WHITE,
	BLACK = BLACK,
	BODY_FONT = BODY_FONT,
	player = player,
	WinGems = PullRates.WinGems,
	getMode = function()
		return mode
	end,
	duelPanelOpen = function()
		return mode == "menu" and ui.stationPanel.Visible and currentStation == "DuelTable"
	end,
	partyScreen = PartyScreen,
	backdrops = Backdrops,
	prefs = prefs,
})

PartyScreen.init({
	ui = ui,
	gui = gui,
	headingStyle = headingStyle,
	make = make,
	corner = corner,
	label = label,
	button = button,
	panel = panel,
	WHITE = WHITE,
	BODY_FONT = BODY_FONT,
	player = player,
	toast = LobbyScreen.toast,
	onPartyChanged = function()
		LobbyScreen.refresh()
	end,
})

MatchScreen.init({
	ui = ui,
	gui = gui,
	headingStyle = headingStyle,
	make = make,
	corner = corner,
	label = label,
	button = button,
	panel = panel,
	WHITE = WHITE,
	BLACK = BLACK,
	FONT = FONT,
	BODY_FONT = BODY_FONT,
	PACE = PACE,
	setPace = function(p)
		PACE = p
	end,
	prefs = prefs,
	player = player,
	camera = camera,
	duelTable = duelTable,
	board = board,
	makeCard = makeCard,
	cardLife = cardLife,
	buildModel = buildModel,
	setScale = setScale,
	shakeCamera = shakeCamera,
	leanCamera = leanCamera,
	actionCam = actionCam,
	setTableWidth = setTableWidth,
	getClock = function()
		return clock
	end,
	getMode = function()
		return mode
	end,
	setMode = function(m)
		mode = m
	end,
	onEnterMatch = function()
		-- The world around the table (picked on the Duel Table panel; "Tree Fort Den" keeps the room).
		local ok, used = pcall(Backdrops.apply, Backdrops.choice, room, duelTable)
		if not ok then
			warn("Background failed, keeping the room: " .. tostring(used))
			Backdrops.clear()
			used = "Room"
		end
		-- Calm worlds: fewer, smaller, softer particles (snow and sparkles drifted right past the camera).
		local world = workspace:FindFirstChild("MatchBackdrop")
		if world then
			for _, d in ipairs(world:GetDescendants()) do
				if d:IsA("ParticleEmitter") then
					d.Rate = d.Rate * 0.3
					d.LightEmission = d.LightEmission * 0.5
					pcall(function()
						local pts = {}
						for _, kp in ipairs(d.Size.Keypoints) do
							table.insert(pts, NumberSequenceKeypoint.new(kp.Time, kp.Value < 1 and kp.Value * 0.6 or kp.Value, kp.Envelope))
						end
						d.Size = NumberSequence.new(pts)
					end)
				end
			end
		end
		setStationSigns(false)
		ui.menuUI.Visible = false
		ui.stationPanel.Visible = false
		if ui.collectionUI then
			ui.collectionUI.Visible = false
		end
		highlight.Enabled = false
		hideCharacter(true)
		actionCam.reset()
		if not showIntro(used) then
			moveCamera("Seat", false, 2.2)
		end
	end,
	onExitMatch = function()
		Backdrops.clear()
		setStationSigns(true)
		ui.menuUI.Visible = true
		hideCharacter(false)
		actionCam.reset()
		-- Back at the Duel Table panel, ready for the next game (the same table, after a friends' match).
		currentStation = nil
		selectStation("DuelTable")
		LobbyScreen.onMenu()
	end,
})


-- Saved settings arrive from the server a moment after you join (or are already there).
local function applyPrefs()
	MatchScreen.applyPrefs(prefs)
	LobbyScreen.applyPrefs(prefs)
end
player.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 4) == "Pref" then
		applyPrefs()
	end
end)
applyPrefs()

-- Pack openings. While one plays, mode is "pull": updateCamera leaves the camera alone, the
-- room's station clicks and hover highlight are off, and the menu is hidden. The opening then
-- moves workspace.CurrentCamera itself until it calls pullMode.exit().
local pullMode = {}

-- Takes the camera for an opening. Returns false (and does nothing) unless you're in the room.
function pullMode.enter()
	if mode ~= "menu" then
		return false
	end
	mode = "pull"
	setStationSigns(false)
	ui.menuUI.Visible = false
	ui.stationPanel.Visible = false
	if ui.collectionUI then
		ui.collectionUI.Visible = false
	end
	highlight.Enabled = false
	cam.shake = 0
	camera.CameraType = Enum.CameraType.Scriptable
	return true
end

-- Gives the camera back to the room. It jumps to camKey (a name in CAMS, default "PackParty").
function pullMode.exit(camKey)
	if mode ~= "pull" then
		return
	end
	mode = "menu"
	setStationSigns(true)
	ui.menuUI.Visible = true
	moveCamera(camKey or "PackParty", true)
end

-- Pulls. startPull asks the server for a card (it takes the Gems and saves the card first),
-- then plays the opening and shows the reveal card. Done goes back to the Pack Party panel.
do
	local PullCinematic = require(Shared:WaitForChild("PullCinematic"))
	PullCinematic.preload() -- load the sounds now, so the first pull isn't silent
	local pulling = false

	local function say(text)
		if ui.pullStatus and ui.pullStatus.Parent then
			ui.pullStatus.Text = text
		end
	end

	-- Plays the opening for a card the player already has, then the reveal.
	-- afterwards(again) runs when the reveal closes; again = true means "Pull again".
	local function playOpening(cardId, tier, seed, copies, afterwards)
		if not pullMode.enter() then
			return false
		end
		local opening
		local ok, err = pcall(function()
			opening = PullCinematic.play({
				cardId = cardId,
				tier = tier,
				seed = seed,
				camera = camera,
				buildModel = buildModel,
				onReveal = function(fromPoint)
					local function close(again)
						opening:finish()
						pullMode.exit()
						afterwards(again)
					end
					showCardReveal(cardId, {
						from = fromPoint,
						copies = copies,
						onDone = function()
							close(false)
						end,
						onPullAgain = function()
							close(true)
						end,
					})
				end,
			})
		end)
		if not ok then
			warn("[Pulls] The opening couldn't start: " .. tostring(err))
			if opening then
				opening:finish()
			end
			pullMode.exit()
			return false
		end
		return true
	end

	function startPull()
		if pulling or mode ~= "menu" then
			return
		end
		local gems = player:GetAttribute("Gems")
		if gems == nil then
			say("Still loading your Gems...")
			return
		end
		if gems < PullRates.Cost then
			say("You need " .. PullRates.Cost .. " Gems for a pull. Win matches to earn more!")
			return
		end
		local remote = Remotes:FindFirstChild("RequestPull")
		if not remote then
			say("Pulls aren't open yet.")
			return
		end
		pulling = true
		say("")
		shakeCamera(0.25) -- the machine rattles while the server rolls (it never hints at the rarity)
		PullCinematic.sound("charge", { volume = 0.5, pitch = 1.6 })
		local ok, result = pcall(function()
			return remote:InvokeServer()
		end)
		if not ok or type(result) ~= "table" or not result.ok or type(result.cardId) ~= "string" or not CardData.Cards[result.cardId] then
			pulling = false
			say(if type(result) == "table" and type(result.message) == "string" then result.message else "Something went wrong, and no Gems were spent. Try again!")
			return
		end
		local started = playOpening(result.cardId, result.tier, result.seed, result.copies, function(again)
			pulling = false
			if again then
				startPull()
			else
				selectStation("PackParty")
			end
		end)
		if not started then
			pulling = false
			say("You got " .. CardData.Cards[result.cardId].name .. "! It's in your collection.")
		end
	end

	-- Studio only: play any card's opening without the server (nothing is spent or saved).
	-- During a playtest, switch the command bar to the Client and run, for example:
	--   game.Players.LocalPlayer.PlayerScripts.PullPreview:Fire("toaster_knight")
	-- An optional second value is the number of copies for the badge (1 shows "NEW!").
	if RunService:IsStudio() then
		local preview = Instance.new("BindableEvent")
		preview.Name = "PullPreview"
		preview.Event:Connect(function(cardId, copies)
			local def = type(cardId) == "string" and CardData.Cards[cardId]
			if not def or pulling then
				return
			end
			pulling = true
			local started = playOpening(cardId, PullRates.tierOf(def.rarity), math.random(1, 1e6), copies or 1, function()
				pulling = false
				selectStation("PackParty")
			end)
			if not started then
				pulling = false
			end
		end)
		preview.Parent = script.Parent
	end
end

---------------------------------------------------------------------------
-- Mouse / touch in the 3D world
---------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processedByGui)
	if processedByGui then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Keyboard then
		if not skipIntro() and mode == "match" then
			MatchScreen.onKey(input.KeyCode)
		end
		return
	end
	if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and skipIntro() then
		return
	end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if kind == Enum.UserInputType.MouseButton2 then
		-- Right click lets go of whatever you were aiming.
		if mode == "match" then
			MatchScreen.onClick(pos, true)
		end
		return
	end
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
		return
	end
	if mode == "menu" then
		local station = stationAt(pos, true)
		if station then
			selectStation(station.Name)
		end
	elseif mode == "match" then
		MatchScreen.onClick(pos, false)
	end
end)

---------------------------------------------------------------------------
-- Every frame: camera, cards, the match table, room ambience
---------------------------------------------------------------------------

do

	-- The room comes alive: flickering fire, a spinning disco ball, color-changing party lights.
	local ambience = { tiles = {}, strings = {}, partyLights = {}, nextColor = 0 }
	do
		local fire = room:FindFirstChild("FireLight", true)
		ambience.firePoint = fire and fire:FindFirstChildOfClass("PointLight")
		ambience.fireBase = ambience.firePoint and ambience.firePoint.Brightness or 3
		ambience.disco = room:FindFirstChild("DiscoBall", true)
		ambience.discoBase = ambience.disco and ambience.disco.CFrame
		for _, d in ipairs(room:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "DiscoTile" then
					table.insert(ambience.tiles, d)
				elseif d.Name == "StringLight" then
					table.insert(ambience.strings, d)
				elseif string.match(d.Name, "^PartyLight%d$") then
					table.insert(ambience.partyLights, { part = d, light = d:FindFirstChildOfClass("SpotLight") })
				end
			end
		end
	end

	local function updateAmbience()
		local a = ambience
		if a.firePoint then
			a.firePoint.Brightness = a.fireBase * (0.85 + 0.12 * math.noise(clock * 2.3, 1.1) + 0.08 * math.noise(clock * 7.9, 4.2))
		end
		if a.disco then
			a.disco.CFrame = a.discoBase * CFrame.Angles(0, clock * 0.3, 0)
		end
		-- Slow and soft, so the room feels cosy rather than busy.
		if clock >= a.nextColor then
			a.nextColor = clock + 0.25
			for i, tile in ipairs(a.tiles) do
				tile.Color = Color3.fromHSV((i * 0.137 + clock * 0.04) % 1, 0.6, 1)
			end
			local chase = math.floor(clock * 0.8)
			for i, bulb in ipairs(a.strings) do
				bulb.Transparency = ((chase + i) % 3 == 0) and 0.35 or 0
			end
			for i, pl in ipairs(a.partyLights) do
				local c = Color3.fromHSV((clock * 0.025 + i / 3) % 1, 0.5, 1)
				pl.part.Color = c
				if pl.light then
					pl.light.Color = c
				end
			end
		end
	end

	local hideTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		updateCamera(dt)
		cardLife.update(dt)
		if mode == "menu" then
			local mouse = UserInputService:GetMouseLocation()
			local station = stationAt(mouse)
			if station then
				highlight.Adornee = station
				highlight.Enabled = true
			else
				highlight.Enabled = false
			end
		elseif mode == "match" then
			hideTimer += dt
			if hideTimer > 0.5 then
				hideTimer = 0
				hideCharacter(true)
			end
		end
		MatchScreen.update(dt)
		if not Backdrops.current() then
			updateAmbience() -- the room is hidden while a match background is up
		end
	end)
end

moveCamera("Overview", true)

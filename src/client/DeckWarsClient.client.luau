-- Deck Wars client: the title screen, the menu room camera and the station menus.
-- The match table lives in MatchScreen, the Duel Table panel (bot, 1v1, 2v2, Cup) in LobbyScreen,
-- parties and invites in PartyScreen, and the worlds around the table in a match in Backdrops.
-- The Deck Shelf is DeckBuilderUI, the Shop is ShopUI, the Pack Shelf and its openings are
-- PackBrawl.PackParty, and the player's settings are Settings.

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
local Settings = require(Shared:WaitForChild("Settings")) -- the player's settings (the Settings station)
local Juice = require(Shared:WaitForChild("Juice"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local TableSounds = require(Shared:WaitForChild("TableSounds"))
local MatchScreen = require(Shared:WaitForChild("MatchScreen"))
local LobbyScreen = require(Shared:WaitForChild("LobbyScreen"))
local PartyScreen = require(Shared:WaitForChild("PartyScreen"))
local Backdrops = require(Shared:WaitForChild("Backdrops"))
local Progression = require(Shared:WaitForChild("Progression"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MenuAction = Remotes:WaitForChild("MenuAction")

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
local INK = Color3.fromRGB(18, 14, 28) -- the thick dark outline on buttons, panels and headings

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function familyColor(family)
	return rgb(CardData.FamilyColors[family] or CardData.FamilyColors.Any)
end

-- Shared state, declared up here so every function below can use it.
local mode = "title" -- "title", "menu", "match" or "pack" (a pack opening, which moves the camera itself)
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
	PackParty = { Vector3.new(11.5, 9.4, -6.3), Vector3.new(19.5, 6.0, -14.9) }, -- the Pack Shelf, left of the panel
	ShopCounter = { Vector3.new(9, 8.5, 9), Vector3.new(16, 5.2, 17.5) },
	TrophyWall = { Vector3.new(11, 9, 0), Vector3.new(23.5, 8, 0) },
	Radio = { Vector3.new(-13, 6.2, -13), Vector3.new(-17.2, 3.6, -18.2) },
	-- the title screen: a slow push across the room behind the logo
	TitleFrom = { Vector3.new(-15, 12.5, 19), Vector3.new(0, 4.5, 0), 60 },
	TitleTo = { Vector3.new(-5, 8.5, 13), Vector3.new(0, 4.6, -1), 55 },
	-- after PLAY the camera starts low over the table and rises to the overview
	Entrance = { Vector3.new(0, 7.2, 9.5), Vector3.new(0, 4.4, -2), 50 },
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
	cam.shake = math.max(cam.shake, strength * (cam.shakeScale or 1)) -- (Screen shake in Settings)
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
	-- During a pack opening the opening owns the camera (see PackParty), so leave it alone.
	if mode == "pack" then
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
	-- Cartoon look: a thick dark outline, a light top and a darker bottom, and outlined text.
	make("UIStroke", { Thickness = 2.5, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 190, 210)) }, b)
	b.TextStrokeColor3 = INK
	b.TextStrokeTransparency = 0.35
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	Juice.button(b) -- grows on hover, squishes on press, clicks
	return b
end

-- Headings: a warm gold gradient with a soft dark outline (instead of a hard black stroke).
local function headingStyle(l)
	l.TextStrokeTransparency = 1
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 238, 170), Color3.fromRGB(255, 166, 54)) }, l)
	make("UIStroke", { Thickness = 2.5, Color = INK }, l)
	return l
end

-- A panel: dark, slightly see-through, with a soft border (headings inside are gold).
local function panel(parent, size, pos, anchor)
	local f = make("Frame", {
		Size = size,
		Position = pos,
		AnchorPoint = anchor or Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(30, 26, 44),
		BackgroundTransparency = 0.04,
	}, parent)
	corner(f, 14)
	-- cartoon look: a thick dark outline and a soft purple-to-navy shade
	make("UIStroke", { Thickness = 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 168, 200)) }, f)
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

-- All the on-screen panels, buttons and labels live in this table.
local ui = {}

---------------------------------------------------------------------------
-- Menu room UI
---------------------------------------------------------------------------

ui.menuUI = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
ui.menuTitle = label(ui.menuUI, "DECK WARS", {
	Name = "MenuTitle",
	Size = UDim2.fromOffset(360, 52),
	Position = UDim2.fromOffset(24, 62),
	TextScaled = false,
	TextSize = 46,
	TextXAlignment = Enum.TextXAlignment.Left,
})
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 238, 170), Color3.fromRGB(255, 156, 40)) }, ui.menuTitle)
make("UIStroke", { Thickness = 3, Color = INK }, ui.menuTitle)
label(ui.menuUI, "Click a part of the room or a button below.  A / D or ← / → look around, S goes back", {
	Name = "MenuHint",
	Size = UDim2.fromOffset(620, 18),
	Position = UDim2.fromOffset(28, 112),
	Font = BODY_FONT,
	TextScaled = false,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(225, 220, 240),
	TextStrokeTransparency = 0.5,
	TextXAlignment = Enum.TextXAlignment.Left,
})
-- You: your level and XP, your Gems and Coins, your win streak and today's first-win bonus. The
-- server keeps the real numbers and shows them as attributes on your Player (Level, XP, Gems...).
ui.profile = panel(ui.menuUI, UDim2.fromOffset(340, 66), UDim2.fromOffset(24, 136))
ui.profile.Name = "Profile"
ui.levelBadge = label(ui.profile, "1", { Name = "Level", Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(11, 11), BackgroundColor3 = Color3.fromRGB(80, 66, 140), BackgroundTransparency = 0, TextScaled = false, TextSize = 20, TextColor3 = Color3.fromRGB(255, 230, 140) })
corner(ui.levelBadge, 22)
make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(255, 210, 110), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ui.levelBadge)
ui.xpText = label(ui.profile, "", { Name = "XPText", Size = UDim2.new(1, -170, 0, 16), Position = UDim2.fromOffset(66, 11), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(220, 216, 240), TextXAlignment = Enum.TextXAlignment.Left })
ui.xpBack = make("Frame", { Size = UDim2.new(1, -174, 0, 8), Position = UDim2.fromOffset(66, 31), BackgroundColor3 = Color3.fromRGB(26, 22, 40) }, ui.profile)
corner(ui.xpBack, 4)
ui.xpFill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(130, 200, 255) }, ui.xpBack)
corner(ui.xpFill, 4)
ui.profileExtra = label(ui.profile, "", { Name = "Extra", Size = UDim2.new(1, -170, 0, 14), Position = UDim2.fromOffset(66, 43), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextColor3 = Color3.fromRGB(255, 200, 130), TextXAlignment = Enum.TextXAlignment.Left })
-- Gems (open packs) and Coins (shop items), stacked on the right of the card.
ui.gemsLabel = label(ui.profile, "", { Name = "Gems", Size = UDim2.fromOffset(96, 24), Position = UDim2.new(1, -12, 0, 8), AnchorPoint = Vector2.new(1, 0), TextScaled = false, TextSize = 20, TextColor3 = Color3.fromRGB(130, 220, 255), TextXAlignment = Enum.TextXAlignment.Right })
ui.coinsLabel = label(ui.profile, "", { Name = "Coins", Size = UDim2.fromOffset(96, 22), Position = UDim2.new(1, -12, 0, 34), AnchorPoint = Vector2.new(1, 0), TextScaled = false, TextSize = 18, TextColor3 = Color3.fromRGB(255, 214, 110), TextXAlignment = Enum.TextXAlignment.Right })
do
	local function refreshProfile()
		local gems = player:GetAttribute("Gems")
		local coins = player:GetAttribute("Coins")
		ui.gemsLabel.Text = if gems then "💎 " .. gems else ""
		ui.coinsLabel.Text = if coins then "🪙 " .. coins else ""
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
	local WATCH = { Gems = true, Coins = true, Level = true, XP = true, XPNeeded = true, WinStreak = true, FirstWinReady = true }
	player.AttributeChanged:Connect(function(name)
		if WATCH[name] then
			refreshProfile()
		end
	end)
	refreshProfile()
end

ui.navBar = make("Frame", { Size = UDim2.new(1, 0, 0, 64), Position = UDim2.new(0, 0, 1, -72), BackgroundTransparency = 1 }, ui.menuUI)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }, ui.navBar)

ui.STATION_SIZE = UDim2.fromOffset(400, 520)
ui.STATION_POS = UDim2.new(1, -24, 0.5, 14)
ui.stationPanel = panel(ui.menuUI, ui.STATION_SIZE, ui.STATION_POS, Vector2.new(1, 0.5))
ui.stationPanel.Visible = false
ui.stationTitle = headingStyle(label(ui.stationPanel, "", { Name = "StationTitle", Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 12), TextScaled = false, TextSize = 24, TextColor3 = WHITE }))
ui.stationBody = make("Frame", { Size = UDim2.new(1, -24, 1, -62), Position = UDim2.fromOffset(12, 52), BackgroundTransparency = 1 }, ui.stationPanel)

-- The Shop window and reward toasts (ShopUI), and the Deck Shelf's collection and deck editor
-- (DeckBuilderUI). The server owns every number; they show its snapshots. (Gems and Coins show
-- on the profile card above, so ShopUI's own counter bar isn't used.)
do
	local ShopUI = require(Shared:WaitForChild("ShopUI"))
	ShopUI.init({ makeCard = makeCard })
	require(Shared:WaitForChild("DeckBuilderUI")).init({
		make = make,
		label = label,
		button = button,
		panel = panel,
		makeCard = makeCard,
		familyColor = familyColor,
		menuUI = ui.menuUI,
		BODY_FONT = BODY_FONT,
		MenuAction = MenuAction,
	})
end

-- Your saved decks for the Duel Table (built at the Deck Shelf): { key = "s1", name, family,
-- themes, hero, count, ok, problem }, and whether the list has arrived from the server yet.
function ui.myDecks()
	local snap = require(Shared:WaitForChild("DeckBuilderUI")).snapshot()
	local list = {}
	for _, d in ipairs(snap and snap.decks or {}) do
		table.insert(list, {
			key = "s" .. d.slot,
			name = d.deck.name or ("Deck " .. d.slot),
			family = d.deck.themes and d.deck.themes[1] or "Any",
			themes = d.deck.themes,
			hero = d.deck.hero,
			count = d.deck.cards and #d.deck.cards or 0,
			ok = d.ok,
			problem = d.problems and d.problems[1],
		})
	end
	return list, snap ~= nil
end

-- The Settings panel: built into the Settings station and into the in-match settings window.
-- Every change goes through Settings.set, which applies it at once (see "Applying settings").
ui.settingsLive = {} -- { scroll = ScrollingFrame, refresh = { fn, ... } } for every open settings panel
do
	local GOLD = Color3.fromRGB(255, 220, 90)
	local IDLE = Color3.fromRGB(70, 66, 100)
	local PICKED = Color3.fromRGB(240, 160, 50)
	local TIP = Color3.fromRGB(190, 185, 205)
	local ROWS = {
		{ head = "Sound" },
		{ key = "sfx", kind = "volume", name = "Sound effects" },
		{ key = "music", kind = "volume", name = "Music" },
		{ head = "Camera" },
		{ key = "actionCam", kind = "toggle", name = "Action camera", tip = "Swoops in close for attacks, Sparks and big summons." },
		{ key = "lean", kind = "toggle", name = "Camera lean", tip = "With the action camera off, lean a little toward fights." },
		{ key = "shake", kind = "choice", name = "Screen shake" },
		{ head = "Game" },
		{ key = "speed", kind = "choice", name = "Table speed", tip = "How fast moves play out on the table." },
		{ key = "packFights", kind = "choice", name = "Pack fights", tip = "Quick plays every pack opening fast-forwarded." },
		{ head = "Graphics" },
		{ key = "graphics", kind = "choice", name = "Quality", tip = "Low turns off shadows and glow for slower devices." },
		{ key = "blur", kind = "toggle", name = "Background blur", tip = "Softly blurs the room far behind the table." },
	}

	function ui.buildSettings(parent)
		local refresh = {}
		local scroll = make("ScrollingFrame", {
			Name = "SettingsList",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 6,
		}, parent)
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		local order = 0
		local function nextOrder()
			order += 1
			return order
		end
		for _, row in ipairs(ROWS) do
			if row.head then
				label(scroll, row.head, { Size = UDim2.new(1, -10, 0, 26), TextScaled = false, TextSize = 20, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = nextOrder() })
			else
				local key = row.key
				local f = make("Frame", { Name = "Row_" .. key, Size = UDim2.new(1, -10, 0, row.tip and 58 or 40), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, scroll)
				label(f, row.name, { Size = UDim2.new(0.4, 0, 0, 34), Position = UDim2.fromOffset(0, 3), Font = BODY_FONT, TextScaled = false, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left })
				if row.tip then
					label(f, row.tip, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 39), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextColor3 = TIP, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
				end
				local area = make("Frame", { Size = UDim2.new(0.6, 0, 0, 34), Position = UDim2.new(0.4, 0, 0, 3), BackgroundTransparency = 1 }, f)
				if row.kind == "toggle" then
					local b = button(area, "", nil, function()
						Settings.set(key, not Settings.get(key))
					end, { Name = "Toggle_" .. key, Size = UDim2.fromScale(1, 1), TextScaled = false, TextSize = 18 })
					table.insert(refresh, function()
						local on = Settings.get(key)
						b.Text = on and "On" or "Off"
						b.BackgroundColor3 = on and PICKED or IDLE
					end)
				elseif row.kind == "choice" then
					local choices = Settings.Choices[key]
					local n = #choices
					make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, area)
					for i, c in ipairs(choices) do
						local b = button(area, c, nil, function()
							Settings.set(key, c)
						end, { Name = key .. "_" .. c, Size = UDim2.new(1 / n, -4 * (n - 1) / n, 1, 0), LayoutOrder = i, TextScaled = false, TextSize = 16 })
						table.insert(refresh, function()
							b.BackgroundColor3 = Settings.get(key) == c and PICKED or IDLE
						end)
					end
				else -- volume: - [bar] +
					button(area, "-", IDLE, function()
						Settings.set(key, math.max(0, Settings.get(key) - 1))
					end, { Name = key .. "_Down", Size = UDim2.new(0, 34, 1, 0) })
					button(area, "+", IDLE, function()
						Settings.set(key, math.min(Settings.VolumeMax, Settings.get(key) + 1))
					end, { Name = key .. "_Up", Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(1, -34, 0, 0) })
					local bar = make("Frame", { Size = UDim2.new(1, -80, 0, 20), Position = UDim2.new(0, 40, 0.5, -10), BackgroundColor3 = Color3.fromRGB(25, 22, 35) }, area)
					corner(bar, 8)
					make("UIStroke", { Thickness = 2, Color = INK }, bar)
					local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = PICKED }, bar)
					corner(fill, 8)
					local value = label(bar, "", { Name = "Value_" .. key, ZIndex = 2, Font = BODY_FONT, TextScaled = false, TextSize = 14, TextStrokeTransparency = 0.3 })
					table.insert(refresh, function()
						local v = Settings.get(key)
						fill.Size = UDim2.fromScale(v / Settings.VolumeMax, 1)
						fill.Visible = v > 0
						value.Text = v == 0 and "Off" or (math.floor(v / Settings.VolumeMax * 100 + 0.5) .. "%")
					end)
				end
			end
		end
		label(scroll, "Keys: A / ← and D / → move between the stations in the room, S / ↓ goes back. On a gamepad: D-pad or bumpers, B goes back.", {
			Size = UDim2.new(1, -10, 0, 48),
			Font = BODY_FONT,
			TextScaled = false,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = TIP,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder(),
		})
		button(scroll, "Reset to defaults", Color3.fromRGB(110, 60, 70), function()
			Settings.reset()
		end, { Name = "ResetSettings", Size = UDim2.new(1, -10, 0, 40), LayoutOrder = nextOrder(), TextScaled = false, TextSize = 18 })
		label(scroll, "Settings are saved to your account and come back next time you play.", {
			Size = UDim2.new(1, -10, 0, 34),
			Font = BODY_FONT,
			TextScaled = false,
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = TIP,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder(),
		})
		for _, fn in ipairs(refresh) do
			fn()
		end
		table.insert(ui.settingsLive, { scroll = scroll, refresh = refresh })
		return scroll
	end
end

local selectStation
do
	local function clearBody()
		for _, child in ipairs(ui.stationBody:GetChildren()) do
			child:Destroy()
		end
		require(Shared:WaitForChild("DeckBuilderUI")).hide()
		require(Shared:WaitForChild("ShopUI")).close()
		-- (the Pack Shelf takes over clicks and hovering only while its panel is open)
		ui.onMenuClick = nil
		ui.onMenuHover = nil
		ui.stationPanel.Size = ui.STATION_SIZE
	end

	-- Play the bot, or open a table for friends (1v1, 2v2, Cup), with one of your own decks or a
	-- practice deck. See LobbyScreen.
	local function showDuelTablePanel()
		clearBody()
		ui.stationTitle.Text = "Duel Table"
		LobbyScreen.show(ui.stationBody)
		require(Shared:WaitForChild("DeckBuilderUI")).request()
	end

	-- The Deck Shelf: your collection, your decks and the deck editor (DeckBuilderUI).
	local function showDeckShelfPanel()
		clearBody()
		ui.stationTitle.Text = "Deck Shelf"
		require(Shared:WaitForChild("DeckBuilderUI")).showShelf(ui.stationBody)
	end

	-- The Pack Shelf: pick a pack (click it on the shelf, or use the arrows), then open it.
	local function showPackPartyPanel()
		clearBody()
		ui.stationTitle.Text = "Pack Party"
		local PackParty = require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackParty"))
		ui.stationPanel.Size = UDim2.fromOffset(400, RunService:IsStudio() and 600 or 560)
		local area = make("Frame", { Name = "PackArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, ui.stationBody)
		PackParty.mount(area, {
			isActive = function()
				return mode == "menu" and ui.stationPanel.Visible and area.Parent ~= nil
			end,
			onStart = function()
				-- the opening takes over the camera and the screen until its reveal closes
				mode = "pack"
				gui.Enabled = false
				ui.topGui.Enabled = false
			end,
			onEnd = function()
				if mode == "pack" then
					mode = "menu"
				end
				gui.Enabled = true
				ui.topGui.Enabled = true
				lockPlayer()
			end,
		})
		-- clicks and the mouse go to the shelf first (a pack under the mouse lifts up)
		ui.onMenuClick = PackParty.clickAt
		ui.onMenuHover = PackParty.hoverAt
	end

	-- The Shop: the Shop window opens on the left; this panel shows your wallet, level and boosts.
	local function showShopPanel()
		clearBody()
		ui.stationTitle.Text = "Shop"
		local ShopUI = require(Shared:WaitForChild("ShopUI"))
		ShopUI.stationPanel(ui.stationBody)
		ShopUI.open()
	end

	-- The Trophy Wall: your level, the daily reward, today's three quests, the first-win bonus and
	-- the achievements. Everything here comes from attributes the server keeps on your Player.
	local function showTrophyPanel()
		clearBody()
		ui.stationTitle.Text = "Trophy Wall"
		local body = make("ScrollingFrame", { Name = "TrophyList", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 6 }, ui.stationBody)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
		local GOLD = Color3.fromRGB(255, 220, 110)
		local DIM = Color3.fromRGB(185, 180, 205)
		local READY = Color3.fromRGB(60, 170, 90)
		local IDLE = Color3.fromRGB(70, 64, 92)
		local function box(order, height, name)
			local f = make("Frame", { Name = name, Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = Color3.fromRGB(44, 38, 64), LayoutOrder = order }, body)
			corner(f, 10)
			make("UIStroke", { Thickness = 2, Color = INK, Transparency = 0.2 }, f)
			return f
		end
		local function bar(parent, pos, size)
			local back = make("Frame", { Size = size, Position = pos, BackgroundColor3 = Color3.fromRGB(28, 24, 42) }, parent)
			corner(back, 6)
			local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(130, 200, 255) }, back)
			corner(fill, 6)
			return fill
		end
		local function heading(text, order)
			label(body, text, { Size = UDim2.new(1, -8, 0, 26), TextScaled = false, TextSize = 20, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order })
		end
		-- Level
		local lv = box(1, 60, "LevelBox")
		local lvText = label(lv, "", { Size = UDim2.new(0.6, -10, 0, 24), Position = UDim2.fromOffset(10, 6), TextScaled = false, TextSize = 18, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local lvNext = label(lv, "", { Size = UDim2.new(0.4, -10, 0, 20), Position = UDim2.new(0.6, 0, 0, 8), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Right })
		local lvFill = bar(lv, UDim2.fromOffset(10, 38), UDim2.new(1, -20, 0, 12))
		-- Daily reward
		local daily = box(2, 64, "DailyBox")
		local dText = label(daily, "", { Size = UDim2.new(1, -130, 0, 24), Position = UDim2.fromOffset(10, 6), TextScaled = false, TextSize = 18, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local dSub = label(daily, "", { Size = UDim2.new(1, -130, 0, 20), Position = UDim2.fromOffset(10, 36), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextWrapped = true, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
		local dButton = button(daily, "Claim", READY, function()
			MenuAction:FireServer("ClaimDaily")
		end, { Name = "ClaimDaily", Size = UDim2.fromOffset(104, 40), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextScaled = false, TextSize = 18 })
		-- First win and streak
		local extra = label(body, "", { Name = "Bonuses", Size = UDim2.new(1, -8, 0, 22), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(255, 205, 140), LayoutOrder = 3 })
		heading("Today's quests", 4)
		local rows = {}
		for i = 1, Progression.QuestsPerDay do
			local q = box(4 + i, 60, "Quest" .. i)
			local r = {}
			r.text = label(q, "", { Size = UDim2.new(1, -124, 0, 22), Position = UDim2.fromOffset(10, 6), Font = BODY_FONT, TextScaled = false, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left })
			r.fill = bar(q, UDim2.fromOffset(10, 36), UDim2.new(1, -184, 0, 10))
			r.count = label(q, "", { Size = UDim2.fromOffset(56, 18), Position = UDim2.new(1, -168, 0, 32), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
			r.button = button(q, "", READY, function()
				MenuAction:FireServer("ClaimQuest", { index = i })
			end, { Name = "ClaimQuest" .. i, Size = UDim2.fromOffset(104, 40), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextScaled = false, TextSize = 18 })
			rows[i] = r
		end
		local resetText = label(body, "", { Size = UDim2.new(1, -8, 0, 20), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextColor3 = DIM, LayoutOrder = 9 })
		-- Achievements: one-time goals, claimed once each.
		heading("Achievements", 10)
		local achRows = {}
		for i, a in ipairs(Progression.Achievements) do
			local f = box(10 + i, 60, "Ach_" .. a.id)
			local r = { def = a }
			r.text = label(f, "", { Size = UDim2.new(1, -124, 0, 20), Position = UDim2.fromOffset(10, 5), TextScaled = false, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
			r.sub = label(f, a.text, { Size = UDim2.new(1, -184, 0, 14), Position = UDim2.fromOffset(10, 25), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
			r.fill = bar(f, UDim2.fromOffset(10, 43), UDim2.new(1, -184, 0, 8))
			r.count = label(f, "", { Size = UDim2.fromOffset(56, 18), Position = UDim2.new(1, -168, 0, 38), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
			r.button = button(f, "", READY, function()
				MenuAction:FireServer("ClaimAchievement", { id = a.id })
			end, { Name = "ClaimAch_" .. a.id, Size = UDim2.fromOffset(104, 40), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextScaled = false, TextSize = 18 })
			achRows[i] = r
		end

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
					r.button.BackgroundColor3 = (done and not claimed) and READY or IDLE
				end
			end
			resetText.Text = "New quests in " .. untilReset() .. " · every quest also gives +" .. Progression.QuestXP .. " XP"
			for _, r in ipairs(achRows) do
				local a = r.def
				local progress = player:GetAttribute("Ach_" .. a.id) or 0
				local claimed = player:GetAttribute("Ach_" .. a.id .. "_Claimed") == true
				local done = progress >= a.target
				r.text.Text = (claimed and "🏆 " or "") .. a.name
				r.text.TextColor3 = claimed and GOLD or WHITE
				r.count.Text = math.min(progress, a.target) .. "/" .. a.target
				r.fill.Size = UDim2.fromScale(math.clamp(progress / a.target, 0, 1), 1)
				r.button.Text = claimed and "Done" or ("+" .. a.gems .. " 💎")
				r.button.AutoButtonColor = done and not claimed
				r.button.BackgroundColor3 = (done and not claimed) and READY or IDLE
			end
		end
		local conn
		conn = player.AttributeChanged:Connect(function()
			if not body.Parent then
				conn:Disconnect()
				return
			end
			refresh()
		end)
		refresh()
		task.spawn(function()
			while body.Parent do
				task.wait(30)
				if body.Parent then
					refresh()
				end
			end
		end)
	end

	local function showSettingsPanel()
		clearBody()
		ui.stationTitle.Text = "Settings"
		ui.buildSettings(ui.stationBody)
	end

	local STATIONS = {
		{ key = "DuelTable", name = "Duel Table", show = showDuelTablePanel },
		{ key = "DeckShelf", name = "Deck Shelf", show = showDeckShelfPanel },
		{ key = "PackParty", name = "Pack Party", show = showPackPartyPanel },
		{ key = "ShopCounter", name = "Shop", show = showShopPanel },
		{ key = "TrophyWall", name = "Trophies", show = showTrophyPanel },
		{ key = "Radio", name = "Settings", show = showSettingsPanel },
	}
	local stationByKey = {}
	for _, s in ipairs(STATIONS) do
		stationByKey[s.key] = s
	end

	-- The station the camera is at (nil = the overview) has its nav button lit up.
	local navButtons = {}
	local NAV_IDLE = Color3.fromRGB(34, 30, 52)
	local NAV_HERE = Color3.fromRGB(86, 64, 28)
	local NAV_ICONS = { DuelTable = "⚔", DeckShelf = "📚", PackParty = "🎁", ShopCounter = "🛒", TrophyWall = "🏆", Radio = "⚙" }
	local function markNav()
		for key, b in pairs(navButtons) do
			local here = key == currentStation
			b.BackgroundColor3 = here and NAV_HERE or NAV_IDLE
			local accent = b:FindFirstChild("Accent")
			if accent then
				TweenService:Create(accent, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = here and UDim2.new(0.8, 0, 0, 4) or UDim2.new(0, 0, 0, 4) }):Play()
			end
			if here then
				Juice.pop(b, 1.15, 0.5)
			end
		end
	end

	function selectStation(key)
		local s = stationByKey[key]
		if not s or mode ~= "menu" then
			return
		end
		if currentStation ~= key then
			Juice.sound("whoosh", 1, 0.35)
			-- the panel slides in from the right and settles
			ui.stationPanel.Position = UDim2.new(1, 60, ui.STATION_POS.Y.Scale, ui.STATION_POS.Y.Offset)
			TweenService:Create(ui.stationPanel, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = ui.STATION_POS }):Play()
		end
		currentStation = key
		markNav()
		moveCamera(key)
		ui.stationPanel.Visible = true
		s.show()
	end

	local function goBack()
		currentStation = nil
		markNav()
		ui.stationPanel.Visible = false
		require(Shared:WaitForChild("DeckBuilderUI")).hide()
		require(Shared:WaitForChild("ShopUI")).close()
		ui.onMenuClick = nil
		ui.onMenuHover = nil
		moveCamera("Overview")
	end
	ui.goBack = goBack

	for i, s in ipairs(STATIONS) do
		local b = button(ui.navBar, s.name, NAV_IDLE, function()
			selectStation(s.key)
		end, { Name = "Nav" .. s.key, LayoutOrder = i, Size = UDim2.fromOffset(150, 52), TextScaled = false, TextSize = 20 })
		navButtons[s.key] = b
		b.TextColor3 = Color3.fromRGB(245, 236, 215)
		b:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, 34)
		b:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(130, 100, 48)
		label(b, NAV_ICONS[s.key] or "", { Name = "Icon", Size = UDim2.new(0, 24, 1, 0), Position = UDim2.fromOffset(-28, 0), TextScaled = false, TextSize = 22 })
		local accent = make("Frame", { Name = "Accent", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, -13, 1, 4), Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(255, 214, 102), BorderSizePixel = 0 }, b)
		corner(accent, 2)
	end
	ui.navButtons = navButtons
	-- A little "!" on the Trophy Wall when there's something to collect.
	do
		local badge = label(navButtons.TrophyWall, "!", { Name = "Badge", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, 4, 0, -8), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(230, 70, 80), BackgroundTransparency = 0, Visible = false, ZIndex = 5, TextScaled = false, TextSize = 18 })
		corner(badge, 12)
		make("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
		local function refreshBadge()
			local any = player:GetAttribute("DailyReady") == true or (player:GetAttribute("QuestsReady") or 0) > 0
			for _, a in ipairs(Progression.Achievements) do
				if (player:GetAttribute("Ach_" .. a.id) or 0) >= a.target and player:GetAttribute("Ach_" .. a.id .. "_Claimed") ~= true then
					any = true
				end
			end
			badge.Visible = any
		end
		player.AttributeChanged:Connect(function(name)
			if name == "DailyReady" or name == "QuestsReady" or string.sub(name, 1, 4) == "Ach_" then
				refreshBadge()
			end
		end)
		refreshBadge()
	end
	button(ui.navBar, "Back", Color3.fromRGB(110, 60, 70), goBack, { Name = "NavBack", LayoutOrder = 99, Size = UDim2.fromOffset(110, 52), TextScaled = false, TextSize = 20 })

	-- Keyboard / gamepad: A or Left goes to the station before, D or Right to the next one
	-- (in the order of the buttons, wrapping around); S, Down or Backspace go back to the overview.
	local PREV = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.DPadLeft] = true, [Enum.KeyCode.ButtonL1] = true }
	local NEXT = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true, [Enum.KeyCode.DPadRight] = true, [Enum.KeyCode.ButtonR1] = true }
	local BACK = { [Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true, [Enum.KeyCode.Backspace] = true, [Enum.KeyCode.ButtonB] = true }
	local function stepStation(dir)
		local index = nil
		for i, s in ipairs(STATIONS) do
			if s.key == currentStation then
				index = i
			end
		end
		if not index then
			index = dir > 0 and 1 or #STATIONS
		else
			index = (index - 1 + dir) % #STATIONS + 1
		end
		selectStation(STATIONS[index].key)
	end
	UserInputService.InputBegan:Connect(function(input)
		-- (not "processed by GUI": a focused button must not eat the keys; text boxes still do)
		if mode ~= "menu" or UserInputService:GetFocusedTextBox() then
			return
		end
		local k = input.KeyCode
		if k == nil then
			return
		end
		if PREV[k] then
			stepStation(-1)
		elseif NEXT[k] then
			stepStation(1)
		elseif BACK[k] and currentStation then
			goBack()
		end
	end)

	-- A hook for the developer panel (ServerStorage.DevControls, only given to developers):
	-- "freeRoll" opens the Pack Party and pulls without spending Gems. The server checks
	-- DevAccess before it honours a free roll, so this hook gives normal players nothing.
	local hook = Instance.new("BindableFunction")
	hook.Name = "ClientHook"
	hook.OnInvoke = function(what, count, tier)
		if what == "freeRoll" then
			if mode ~= "menu" then
				return false, "finish your match (or pack) first"
			end
			local PackParty = require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackParty"))
			if PackParty.isPlaying() then
				return false, "a pack is already opening"
			end
			selectStation("PackParty")
			PackParty.request(count == 10 and 10 or 1, tier, nil, true)
			return true
		end
		return false, "unknown request"
	end
	hook.Parent = script
end

---------------------------------------------------------------------------
-- Top right, in the room and at the table: 👥 Party and ⚙, side by side under Roblox's own
-- buttons. ⚙ opens the Settings station in the room and the match menu at the table.
---------------------------------------------------------------------------
ui.topGui = make("ScreenGui", { Name = "DeckWarsTopRight", ResetOnSpawn = false, DisplayOrder = 8, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
pcall(function()
	ui.topGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
ui.topBar = make("Frame", { Name = "TopBar", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 8), Size = UDim2.fromOffset(240, 44), BackgroundTransparency = 1 }, ui.topGui)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ui.topBar)
ui.gearButton = button(ui.topBar, "⚙", Color3.fromRGB(60, 56, 84), function()
	if mode == "match" then
		if ui.toggleMatchMenu then
			ui.toggleMatchMenu()
		end
	elseif mode == "menu" then
		if currentStation == "Radio" then
			ui.goBack()
		else
			selectStation("Radio")
		end
	end
end, { Name = "GearButton", Size = UDim2.fromOffset(48, 44), LayoutOrder = 2, TextScaled = false, TextSize = 26 })

---------------------------------------------------------------------------
-- The daily reward pop-up (once a visit, when today's reward is waiting) and the replies to
-- claiming rewards
---------------------------------------------------------------------------

local function chime(pitch)
	pcall(function()
		TableSounds.play("ding", { volume = 0.5 * Settings.get("sfx") / 8, pitch = pitch or 1 })
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
	MenuAction:FireServer("ClaimDaily")
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
		local coins = (tonumber(payload.coins) or 0) > 0 and ("  +" .. tostring(payload.coins) .. " 🪙") or ""
		LobbyScreen.toast("🎁 Daily reward: +" .. tostring(payload.gems) .. " 💎" .. coins .. " (day " .. tostring(payload.day) .. ")")
		chime(1)
	elseif payload.what == "achievement" then
		local def = Progression.AchievementById[tostring(payload.id)]
		LobbyScreen.toast("🏆 " .. (def and def.name or "Achievement") .. ": +" .. tostring(payload.gems) .. " 💎")
		chime(1.3)
		Juice.confetti(gui, 0.5, 0.35, 40)
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
-- (the mouse turns into a pointing hand over anything in the room that answers it)
do
	local pointing = false
	function ui.setPointer(on)
		if on == pointing then
			return
		end
		pointing = on
		pcall(function()
			UserInputService.MouseIcon = on and "rbxasset://SystemCursors/PointingHand" or ""
		end)
	end
end
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
-- outlined capitals that ran off the edges of the screen). The Trophy Wall holds the quests and achievements.
do
	local NAMES = { ["PACK PARTY"] = "Pack Party", ["DUEL TABLE"] = "Duel Table", ["SHOP"] = "Shop", ["SETTINGS"] = "Settings", ["DECK SHELF"] = "Deck Shelf", ["TROPHY WALL"] = "Trophy Wall" }
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
			MenuAction:FireServer("SavePrefs", send)
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
	WinGems = ShopCatalog.Match.winGems,
	myDecks = ui.myDecks,
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

-- Your saved decks arrive (or change at the Deck Shelf): the Duel Table's deck list follows.
require(Shared:WaitForChild("DeckBuilderUI")).onDecks(function()
	if mode == "menu" and ui.stationPanel.Visible and currentStation == "DuelTable" then
		LobbyScreen.refresh()
	end
end)

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
	sfxScale = function()
		return Settings.get("sfx") / 8
	end,
	onEnterMatch = function()
		-- The world around the table (picked on the Duel Table panel; "Card Den" keeps the room).
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
		require(Shared:WaitForChild("DeckBuilderUI")).hide()
		require(Shared:WaitForChild("ShopUI")).close()
		ui.matchTop.Visible = true
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
		ui.matchTop.Visible = false
		ui.matchSettings.Visible = false
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

---------------------------------------------------------------------------
-- The top-right corner: 👥 Party next to ⚙, in the room and at the table. At the table the ⚙ menu
-- (how to play, speed, sound, action camera, settings, match log, leave) and the match log open
-- under it.
---------------------------------------------------------------------------
do
	ui.partyButton.Parent = ui.topBar
	ui.partyButton.LayoutOrder = 1
	ui.partyButton.Size = UDim2.fromOffset(140, 44)
	ui.partyPanel.Parent = ui.topGui
	ui.partyPanel.AnchorPoint = Vector2.new(1, 0)
	ui.partyPanel.Position = UDim2.new(1, -16, 0, 60)

	ui.matchTop = make("Frame", { Name = "MatchTop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, ui.topGui)
	ui.menuButton.Visible = false -- (the ⚙ in the top bar opens this menu now)
	ui.menuPanel.Parent = ui.matchTop
	ui.menuPanel.Position = UDim2.new(1, -16, 0, 60)
	ui.logFrame.Parent = ui.matchTop
	ui.logFrame.Position = UDim2.new(1, -16, 0, 60)
	ui.toggleMatchMenu = function()
		ui.partyPanel.Visible = false
		MatchScreen.toggleMenu()
	end

	-- The in-match settings window (the same options as the Settings station in the room).
	ui.matchSettings = panel(ui.matchUI, UDim2.fromOffset(420, 540), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	ui.matchSettings.Name = "MatchSettings"
	ui.matchSettings.Visible = false
	ui.matchSettings.ZIndex = 41
	headingStyle(label(ui.matchSettings, "Settings", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 10), TextScaled = false, TextSize = 26, TextColor3 = WHITE }))
	button(ui.matchSettings, "Done", Color3.fromRGB(60, 180, 90), function()
		ui.matchSettings.Visible = false
	end, { Name = "SettingsDone", Size = UDim2.new(1, -24, 0, 42), Position = UDim2.new(0, 12, 1, -52), TextScaled = false, TextSize = 20 })
	local body = make("Frame", { Size = UDim2.new(1, -24, 1, -116), Position = UDim2.fromOffset(12, 54), BackgroundTransparency = 1 }, ui.matchSettings)
	ui.buildSettings(body)

	-- Two more lines in the ⚙ menu: the action camera on / off, and the full settings window.
	ui.leaveButton.LayoutOrder = 9
	ui.camButton = button(ui.menuPanel, "", Color3.fromRGB(70, 66, 100), function()
		Settings.set("actionCam", not actionCam.on) -- (applied below, under "Applying settings")
	end, { Name = "ActionCamButton", Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 5 })
	button(ui.menuPanel, "⚙ All settings", Color3.fromRGB(70, 66, 100), function()
		ui.menuPanel.Visible = false
		ui.matchSettings.Visible = true
	end, { Name = "SettingsButton", Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 6 })

	-- The 💬 emote button (emotes come from the Shop); bubbles pop up over the heroes.
	require(Shared:WaitForChild("ShopUI")).mountEmotes(ui.matchUI, function()
		return MatchScreen.heroPart(true)
	end, function()
		return MatchScreen.heroPart(false)
	end)
end

---------------------------------------------------------------------------
-- Applying settings: every change takes effect at once and is saved to your account
---------------------------------------------------------------------------
do
	local Lighting = game:GetService("Lighting")
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local baseShadows = Lighting.GlobalShadows
	local baseBloom = bloom and bloom.Enabled
	local baseSunRays = sunRays and sunRays.Enabled
	local baseBlur = depthOfField and depthOfField.Enabled
	local lampShadows = {} -- [light] = whether it casts shadows on High
	for _, d in ipairs(room:GetDescendants()) do
		if d:IsA("Light") then
			lampShadows[d] = d.Shadows
		end
	end

	local function apply(key, value)
		if key == "speed" then
			MatchScreen.setBasePace(Settings.Pace[value] or 1)
		elseif key == "actionCam" then
			actionCam.on = value
			if not value and actionCam.release then
				actionCam.release(0)
			end
			ui.camButton.Text = value and "🎥 Action cam: On" or "🎥 Action cam: Off"
		elseif key == "lean" then
			ATTACK_CAMERA = value
			if not value then
				cam.leanTarget = 0
			end
		elseif key == "shake" then
			cam.shakeScale = Settings.ShakeScale[value] or 1
			if value == "Off" then
				cam.shake = 0
			end
		elseif key == "graphics" then
			local low = value == "Low"
			Lighting.GlobalShadows = baseShadows and not low
			if bloom then
				bloom.Enabled = baseBloom and not low
			end
			if sunRays then
				sunRays.Enabled = baseSunRays and not low
			end
			for light, shadows in pairs(lampShadows) do
				if light.Parent then
					light.Shadows = shadows and not low
				end
			end
		elseif key == "blur" then
			if depthOfField then
				depthOfField.Enabled = value and baseBlur ~= false
			end
		end
		-- (sfx and music are read by the sound players each time they play)
	end
	for key, value in pairs(Settings.Values) do
		apply(key, value)
	end

	local saveQueued = false
	local changedHere = false
	Settings.onChanged(function(key, value, fromLoad)
		apply(key, value)
		for i = #ui.settingsLive, 1, -1 do
			local open = ui.settingsLive[i]
			if open.scroll.Parent == nil then
				table.remove(ui.settingsLive, i)
			else
				for _, fn in ipairs(open.refresh) do
					fn()
				end
			end
		end
		if not fromLoad then
			changedHere = true
			if not saveQueued then
				-- wait a moment so clicking + five times is one save
				saveQueued = true
				task.delay(1.5, function()
					saveQueued = false
					MenuAction:FireServer("SaveSettings", Settings.Values)
				end)
			end
		end
	end)
	MenuAction.OnClientEvent:Connect(function(what, data)
		-- your saved settings arrive from the server (ignored if you already changed something)
		if what == "Settings" and not changedHere then
			Settings.load(data)
		end
	end)
	MenuAction:FireServer("LoadSettings")
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
		if ui.onMenuClick and ui.onMenuClick(pos) then
			return -- (a pack on the Pack Shelf took the click)
		end
		if ui.roomLife and not Backdrops.current() then
			ui.roomLife.click(pos, true) -- the prop you clicked answers (and its station still opens)
		end
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
	-- RoomLife makes the props answer the mouse (and can hype up the fire, the disco ball and the
	-- dance floor while you point at them).
	local RoomLife = require(Shared:WaitForChild("RoomLife"))
	RoomLife.attach(room)
	ui.roomLife = RoomLife
	local ambience = { tiles = {}, strings = {}, partyLights = {}, nextColor = 0, discoAngle = 0, tileColors = {} }
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

	local WHITE_GLOW = Color3.fromRGB(255, 250, 235)
	local function updateAmbience(dt)
		local a = ambience
		if a.firePoint then
			a.firePoint.Brightness = a.fireBase * (0.85 + 0.12 * math.noise(clock * 2.3, 1.1) + 0.08 * math.noise(clock * 7.9, 4.2)) * RoomLife.fireBoost()
		end
		if a.disco then
			a.discoAngle = (a.discoAngle + dt * 0.3 * RoomLife.discoBoost()) % (math.pi * 2)
			a.disco.CFrame = a.discoBase * CFrame.Angles(0, a.discoAngle, 0)
		end
		-- the dance floor lights up under the cursor (every frame while it does)
		local busy = RoomLife.tilesBusy()
		if busy or a.tilesGlowing then
			a.tilesGlowing = busy
			for i, tile in ipairs(a.tiles) do
				local base = a.tileColors[i] or tile.Color
				tile.Color = base:Lerp(WHITE_GLOW, RoomLife.tileGlow(tile))
			end
		end
		-- Slow and soft, so the room feels cosy rather than busy.
		if clock >= a.nextColor then
			a.nextColor = clock + 0.25
			for i, tile in ipairs(a.tiles) do
				local c = Color3.fromHSV((i * 0.137 + clock * 0.04) % 1, 0.6, 1)
				a.tileColors[i] = c
				tile.Color = busy and c:Lerp(WHITE_GLOW, RoomLife.tileGlow(tile)) or c
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
			local packHover = ui.onMenuHover and ui.onMenuHover(mouse)
			-- the props in the room answer the mouse (not while a pack on the shelf has it)
			local prop = RoomLife.update(dt, (not packHover and not Backdrops.current()) and mouse or nil, Backdrops.current() == nil)
			ui.setPointer(prop ~= nil or station ~= nil or packHover == true)
			if packHover then
				highlight.Enabled = false -- (a pack on the shelf lifts up instead)
			elseif station then
				highlight.Adornee = station
				highlight.Enabled = true
				-- the hovered station glows with a soft gold pulse
				highlight.FillTransparency = 0.82 + math.sin(clock * 5) * 0.06
				highlight.OutlineTransparency = 0.1 + math.sin(clock * 5) * 0.1
			else
				highlight.Enabled = false
			end
		elseif mode ~= "match" then
			highlight.Enabled = false
			RoomLife.update(dt, nil, false)
			ui.setPointer(false)
		elseif mode == "match" then
			RoomLife.update(dt, nil, false) -- (puts every prop back before the table is copied into a world)
			ui.setPointer(false)
			hideTimer += dt
			if hideTimer > 0.5 then
				hideTimer = 0
				hideCharacter(true)
			end
		end
		MatchScreen.update(dt)
		if not Backdrops.current() then
			updateAmbience(dt) -- the room is hidden while a match background is up
		end
	end)
end

-- The opening: the title screen over a slow camera push across the room. PLAY flies the camera
-- in from low over the table up to the overview, and the menu pops in piece by piece.
do
	local TitleScreen = require(Shared:WaitForChild("TitleScreen"))
	mode = "title"
	ui.menuUI.Visible = false
	ui.topBar.Visible = false
	moveCamera("TitleFrom", true)
	glideCamera(CAMS.TitleTo[1], CAMS.TitleTo[2], 40, CAMS.TitleTo[3])
	TitleScreen.show({
		onPlay = function()
			mode = "menu"
			moveCamera("Entrance", true)
			glideCamera(CAMS.Overview[1], CAMS.Overview[2], 2.4)
			task.wait(0.5)
			ui.menuUI.Visible = true
			ui.topBar.Visible = true
			Juice.popIn(ui.menuTitle, 0.1, { twist = -6, sound = false })
			Juice.popIn(ui.profile, 0.2, { twist = 0, sound = false })
			local hint = ui.menuUI:FindFirstChild("MenuHint")
			if hint then
				hint.TextTransparency = 1
				TweenService:Create(hint, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
			end
			for _, b in ipairs(ui.navBar:GetChildren()) do
				if b:IsA("GuiButton") then
					Juice.popIn(b, 0.35 + b.LayoutOrder % 20 * 0.06, { twist = 0, pitch = 0.9 + (b.LayoutOrder % 20) * 0.05 })
				end
			end
			if ui.checkDaily then
				ui.checkDaily()
			end
		end,
	})
end

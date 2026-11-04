-- Deck Wars client: the menu room camera, the station menus, the match screen,
-- and the creatures that rise out of the tiles, walk around and fight.

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

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent")
local MatchAction = Remotes:WaitForChild("MatchAction")
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
-- Action camera: for attacks, chants, Defend, spells, big summons and Big Moves the camera swoops
-- in close, then glides back to your seat. Players can also turn it off with the button in a match.
local ACTION_CAMERA = true
-- With the action camera off, the camera still leans in a little toward each fight. Set to false to keep it still.
local ATTACK_CAMERA = true

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
local mode = "menu" -- "menu" or "match"
local view = nil -- latest match view from the server
local busy = false -- waiting for the server to answer our action
local processing = false -- playing back animations
local matchId = 0 -- changes whenever a match starts or ends
local playingMatch = -1 -- the match the animations being played belong to
local clock = 0 -- seconds since the script started (advanced every frame)
local turnEndsAt = 0 -- server time when your turn runs out (0 = clock paused)
local turnState = "opp" -- "you", "opp" or "over": what the turn label says

---------------------------------------------------------------------------
-- Camera: glides between spots, can shake, and sways a little during matches
---------------------------------------------------------------------------

local CAMS = {
	Overview = { Vector3.new(0, 15, 22), Vector3.new(0, 3, -6) },
	DuelTable = { Vector3.new(0, 16, 23), Vector3.new(0, 4, 0) },
	Seat = { Vector3.new(0, 15.6, 13.4), Vector3.new(0, 4.0, -0.6), 52 }, -- sitting down: the board and the bot across the table
	SeatYou = { Vector3.new(0, 16, 12), Vector3.new(0, 4.2, 1.25), 48 }, -- your turn: leaning in, the board fills the screen
	SeatOpp = { Vector3.new(0, 15.6, 13.4), Vector3.new(0, 4.0, -0.6), 52 }, -- the bot's turn: leaning back to watch it play
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

local function moveCamera(name, instant, seconds)
	local preset = CAMS[name]
	if not preset then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	glideCamera(preset[1], preset[2], instant and 0 or (seconds or 1.2), preset[3])
end

local function shakeCamera(strength)
	cam.shake = math.max(cam.shake, strength * (cam.shakeScale or 1))
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
	make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(30, 30, 40), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function panel(parent, size, pos, anchor)
	local f = make("Frame", {
		Size = size,
		Position = pos,
		AnchorPoint = anchor or Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(35, 30, 50),
		BackgroundTransparency = 0.1,
	}, parent)
	corner(f, 14)
	make("UIStroke", { Thickness = 3, Color = Color3.fromRGB(255, 210, 90) }, f)
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
	function addCardArt(art, def)
		if def.type == "Spell" then
			local icon = label(art, SPELL_ICONS[def.id] or "✨", { Name = "Icon", Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), Font = Enum.Font.GothamBold })
			cardLife.icons[icon] = math.random() * 6.28
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
local function makeCard(parent, cardId, size, costOverride)
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
	if rank and rank >= 2 then
		cardLife.glows[stroke] = math.random() * 6.28
	end
	if def.rarity == "Secret" then
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
		Size = UDim2.fromScale(0.86, 0.36),
		Position = UDim2.fromScale(0.07, 0.17),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
	}, card)
	corner(art, 8)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(famColor:Lerp(WHITE, 0.45), famColor:Lerp(BLACK, 0.35)) }, art)
	addCardArt(art, def)
	label(card, def.type .. (def.family ~= "Any" and (" · " .. def.family) or "") .. " · " .. def.rarity, {
		Size = UDim2.new(0.9, 0, 0.07, 0),
		Position = UDim2.fromScale(0.05, 0.54),
		Font = BODY_FONT,
		TextColor3 = Color3.fromRGB(60, 50, 70),
	})
	local textBox = make("Frame", { Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.62), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25 }, card)
	corner(textBox, 6)
	label(textBox, def.text ~= "" and def.text or "Just a good fighter.", {
		Font = BODY_FONT,
		TextColor3 = Color3.fromRGB(30, 25, 40),
		TextWrapped = true,
		Size = UDim2.fromScale(0.94, 0.9),
		Position = UDim2.fromScale(0.03, 0.05),
	})
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
label(ui.menuUI, "DECK WARS", {
	Size = UDim2.fromOffset(420, 64),
	Position = UDim2.fromOffset(24, 64),
	TextColor3 = Color3.fromRGB(255, 220, 90),
	TextStrokeTransparency = 0,
	TextXAlignment = Enum.TextXAlignment.Left,
})
label(ui.menuUI, "Click a part of the room or the buttons below. A / D or ← / → look around, S goes back", {
	Name = "MenuHint",
	Size = UDim2.fromOffset(620, 24),
	Position = UDim2.fromOffset(26, 126),
	Font = BODY_FONT,
	TextStrokeTransparency = 0.4,
	TextXAlignment = Enum.TextXAlignment.Left,
})

ui.navBar = make("Frame", { Size = UDim2.new(1, 0, 0, 64), Position = UDim2.new(0, 0, 1, -72), BackgroundTransparency = 1 }, ui.menuUI)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }, ui.navBar)

ui.stationPanel = panel(ui.menuUI, UDim2.fromOffset(390, 480), UDim2.new(1, -24, 0.5, -20), Vector2.new(1, 0.5))
ui.stationPanel.Visible = false
ui.stationTitle = label(ui.stationPanel, "", { Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(12, 10), TextColor3 = Color3.fromRGB(255, 220, 90) })
ui.stationBody = make("Frame", { Size = UDim2.new(1, -24, 1, -70), Position = UDim2.fromOffset(12, 60), BackgroundTransparency = 1 }, ui.stationPanel)


-- The Settings panel: built into the Settings station and into the in-match settings window.
-- Every change goes through Settings.set, which applies it at once (see "Applying settings").
ui.settingsLive = {} -- { scroll = ScrollingFrame, refresh = { fn, ... } } for every open settings panel
do
	local GOLD = Color3.fromRGB(255, 220, 90)
	local IDLE = Color3.fromRGB(80, 80, 110)
	local PICKED = Color3.fromRGB(240, 160, 50)
	local TIP = Color3.fromRGB(190, 185, 205)
	local ROWS = {
		{ head = "Sound" },
		{ key = "sfx", kind = "volume", name = "Sound effects" },
		{ key = "music", kind = "volume", name = "Music" },
		{ head = "Camera" },
		{ key = "actionCam", kind = "toggle", name = "Action camera", tip = "Swoops in close for attacks, chants and spells." },
		{ key = "lean", kind = "toggle", name = "Camera lean", tip = "With the action camera off, lean a little toward fights." },
		{ key = "shake", kind = "choice", name = "Screen shake" },
		{ head = "Game" },
		{ key = "speed", kind = "choice", name = "Table speed", tip = "How fast moves play out on the table." },
		{ key = "packFights", kind = "choice", name = "Pack fights", tip = "Quick plays every Pack Brawl fast-forwarded." },
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
				label(scroll, row.head, { Size = UDim2.new(1, -10, 0, 26), TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = nextOrder() })
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
					end, { Name = "Toggle_" .. key, Size = UDim2.fromScale(1, 1) })
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
						end, { Name = key .. "_" .. c, Size = UDim2.new(1 / n, -4 * (n - 1) / n, 1, 0), LayoutOrder = i })
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
		end, { Name = "ResetSettings", Size = UDim2.new(1, -10, 0, 40), LayoutOrder = nextOrder() })
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
		if ui.collectionUI then
			ui.collectionUI.Visible = false
		end
	end

	local chosenDeck = "Snack"
	local chosenDifficulty = "Medium"

	local function showDuelTablePanel()
		clearBody()
		ui.stationTitle.Text = "Duel Table"
		make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, ui.stationBody)
		label(ui.stationBody, "Pick your deck", { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 })
		local grid = make("Frame", { Size = UDim2.new(1, 0, 0, 3 * 42 + 2 * 6), BackgroundTransparency = 1, LayoutOrder = 2 }, ui.stationBody)
		make("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 42), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local about = label(ui.stationBody, "", { Size = UDim2.new(1, 0, 0, 58), Font = BODY_FONT, TextWrapped = true, TextScaled = true, TextColor3 = Color3.fromRGB(230, 225, 240), LayoutOrder = 3 })
		local deckButtons = {}
		local diffButtons = {}
		local function refresh()
			for key, b in pairs(deckButtons) do
				local fam = familyColor(StarterDecks[key].family)
				b.BackgroundColor3 = key == chosenDeck and fam or fam:Lerp(Color3.fromRGB(40, 35, 60), 0.65)
				b.TextColor3 = key == chosenDeck and BLACK or WHITE
			end
			for key, b in pairs(diffButtons) do
				b.BackgroundColor3 = key == chosenDifficulty and Color3.fromRGB(240, 160, 50) or Color3.fromRGB(80, 80, 110)
			end
			local deck = StarterDecks[chosenDeck]
			about.Text = deck.family .. " deck, hero " .. CardData.Heroes[deck.hero].name .. ". " .. (deck.blurb or "")
		end
		for i, key in ipairs(StarterDecks.Order) do
			deckButtons[key] = button(grid, StarterDecks[key].name, nil, function()
				chosenDeck = key
				refresh()
			end, { LayoutOrder = i })
		end
		label(ui.stationBody, "Bot difficulty", { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 10 })
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 11 }, ui.stationBody)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }, row)
		for _, d in ipairs({ "Easy", "Medium", "Hard" }) do
			diffButtons[d] = button(row, d, nil, function()
				chosenDifficulty = d
				refresh()
			end, { Size = UDim2.new(0.31, 0, 1, 0) })
		end
		button(ui.stationBody, "Sit down and play!", Color3.fromRGB(60, 180, 90), function()
			MenuAction:FireServer("StartBotMatch", { deck = chosenDeck, difficulty = chosenDifficulty })
		end, { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 20 })
		label(ui.stationBody, "The bot picks one of the other decks. Playing friends arrives in a later update.", {
			Size = UDim2.new(1, 0, 0, 30),
			Font = BODY_FONT,
			TextWrapped = true,
			TextColor3 = Color3.fromRGB(200, 200, 220),
			LayoutOrder = 21,
		})
		refresh()
	end

	local function buildCollection()
		ui.collectionUI = panel(ui.menuUI, UDim2.new(0.62, 0, 0.72, 0), UDim2.new(0, 24, 0.5, -10), Vector2.new(0, 0.5))
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

	local STATIONS = {
		{ key = "DuelTable", name = "Duel Table", show = showDuelTablePanel },
		{ key = "DeckShelf", name = "Deck Shelf", show = showDeckShelfPanel },
		{
			key = "PackParty",
			name = "Pack Party",
			show = function()
				-- Pack Brawl: every pack is a fight in the Brawl Box, and the card you pulled wins it
				clearBody()
				ui.stationTitle.Text = "Pack Party"
				label(ui.stationBody, "Every pack is a brawl! Creatures crash the ring and fight it out, and the card you pulled walks in last and wins. Rarer pulls bring bigger fights.", { Size = UDim2.new(1, 0, 0, 96), Font = BODY_FONT, TextWrapped = true, TextScaled = false, TextSize = 18, TextYAlignment = Enum.TextYAlignment.Top })
				local status = label(ui.stationBody, "Hold the screen to fast-forward a fight.", { Name = "PackStatus", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 100), Font = BODY_FONT, TextWrapped = true, TextScaled = false, TextSize = 15, TextColor3 = Color3.fromRGB(200, 200, 220), TextYAlignment = Enum.TextYAlignment.Top })
				local area = make("Frame", { Name = "PackArea", Size = UDim2.new(1, 0, 0, 160), Position = UDim2.fromOffset(0, 150), BackgroundTransparency = 1 }, ui.stationBody)
				local PackParty = require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackParty"))
				PackParty.mount(area, {
					onStart = function()
						-- the cinematic takes over the camera and the screen until the reveal closes
						mode = "pack"
						gui.Enabled = false
					end,
					onEnd = function(result)
						if mode == "pack" then
							mode = "menu"
						end
						gui.Enabled = true
						lockPlayer()
					end,
					onStatus = function(text)
						if status.Parent then
							status.Text = text
						end
					end,
				})
			end,
		},
		{
			key = "ShopCounter",
			name = "Shop",
			show = function()
				showComingSoon("Shop", "Pickles the shopkeeper will sell packs, Gems and cosmetics here.\n\nComing in a later update.")
			end,
		},
		{
			key = "TrophyWall",
			name = "Trophy Wall",
			show = function()
				showComingSoon("Trophy Wall", "Your level, rank, daily quests and unlocked heroes will hang here.\n\nComing in a later update.")
			end,
		},
		{
			key = "Radio",
			name = "Settings",
			show = function()
				clearBody()
				ui.stationTitle.Text = "Settings"
				ui.buildSettings(ui.stationBody)
			end,
		},
	}
	local stationByKey = {}
	for _, s in ipairs(STATIONS) do
		stationByKey[s.key] = s
	end

	-- Which station the camera is at (nil = the overview), and its nav button lit up.
	local current = nil
	local navButtons = {}
	local NAV_IDLE = Color3.fromRGB(70, 60, 110)
	local NAV_HERE = Color3.fromRGB(160, 115, 40)
	local function markNav()
		for key, b in pairs(navButtons) do
			b.BackgroundColor3 = key == current and NAV_HERE or NAV_IDLE
		end
	end

	function selectStation(key)
		local s = stationByKey[key]
		if not s or mode ~= "menu" then
			return
		end
		current = key
		markNav()
		moveCamera(key)
		ui.stationPanel.Visible = true
		s.show()
	end

	local function goBack()
		current = nil
		markNav()
		ui.stationPanel.Visible = false
		if ui.collectionUI then
			ui.collectionUI.Visible = false
		end
		moveCamera("Overview")
	end
	ui.resetNav = function() -- (leaving a match puts the camera back at the overview)
		current = nil
		markNav()
	end

	for i, s in ipairs(STATIONS) do
		navButtons[s.key] = button(ui.navBar, s.name, NAV_IDLE, function()
			selectStation(s.key)
		end, { LayoutOrder = i, Size = UDim2.fromOffset(150, 52) })
	end
	button(ui.navBar, "Back", Color3.fromRGB(110, 60, 70), goBack, { LayoutOrder = 99, Size = UDim2.fromOffset(110, 52) })

	-- Keyboard / gamepad: A or Left goes to the station before, D or Right to the next one
	-- (in the order of the buttons, wrapping around); S, Down or Backspace go back to the overview.
	local PREV = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.DPadLeft] = true, [Enum.KeyCode.ButtonL1] = true }
	local NEXT = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true, [Enum.KeyCode.DPadRight] = true, [Enum.KeyCode.ButtonR1] = true }
	local BACK = { [Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true, [Enum.KeyCode.Backspace] = true, [Enum.KeyCode.ButtonB] = true }
	local function stepStation(dir)
		local index = nil
		for i, s in ipairs(STATIONS) do
			if s.key == current then
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
		-- (not "processed by GUI": the room has no text boxes, and a focused button must not eat the keys)
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
		elseif BACK[k] and current then
			goBack()
		end
	end)
end

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
-- Match screen
---------------------------------------------------------------------------

ui.matchUI = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)

ui.oppBar = panel(ui.matchUI, UDim2.fromOffset(460, 70), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0))
ui.oppName = label(ui.oppBar, "Opponent", { Size = UDim2.new(0.5, -10, 0.45, 0), Position = UDim2.fromOffset(12, 4), TextXAlignment = Enum.TextXAlignment.Left })
ui.oppInfo = label(ui.oppBar, "", { Size = UDim2.new(0.5, -10, 0.4, 0), Position = UDim2.new(0, 12, 0.52, 0), Font = BODY_FONT, TextXAlignment = Enum.TextXAlignment.Left })
ui.oppHpBack = make("Frame", { Size = UDim2.new(0.45, 0, 0.42, 0), Position = UDim2.new(0.52, 0, 0.29, 0), BackgroundColor3 = Color3.fromRGB(60, 20, 30) }, ui.oppBar)
corner(ui.oppHpBack, 8)
ui.oppHpFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(230, 70, 80) }, ui.oppHpBack)
corner(ui.oppHpFill, 8)
ui.oppHpText = label(ui.oppHpBack, "20", { ZIndex = 2 })

ui.meBar = panel(ui.matchUI, UDim2.fromOffset(300, 150), UDim2.new(0, 16, 1, -16), Vector2.new(0, 1))
ui.meName = label(ui.meBar, "You", { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left })
ui.meHpBack = make("Frame", { Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 38), BackgroundColor3 = Color3.fromRGB(20, 50, 30) }, ui.meBar)
corner(ui.meHpBack, 8)
ui.meHpFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(80, 200, 100) }, ui.meHpBack)
corner(ui.meHpFill, 8)
ui.meHpText = label(ui.meHpBack, "20", { ZIndex = 2 })
for _, bar in ipairs({ { ui.oppHpBack, ui.oppHpFill, ui.oppHpText }, { ui.meHpBack, ui.meHpFill, ui.meHpText } }) do
	local trail = make("Frame", { Name = "Trail", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 226, 165), ZIndex = 1 }, bar[1])
	corner(trail, 8)
	make("UIScale", { Scale = 1 }, bar[1])
	bar[2].ZIndex = 2
	bar[3].ZIndex = 3
end
ui.energyText = label(ui.meBar, "Energy 0/0", { Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 70), TextColor3 = Color3.fromRGB(120, 200, 255), TextXAlignment = Enum.TextXAlignment.Left })
ui.bigMoveButton = button(ui.meBar, "Big Move", Color3.fromRGB(150, 80, 200), nil, { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 100) })

ui.endTurnButton = button(ui.matchUI, "END TURN", Color3.fromRGB(200, 100, 60), nil, { Size = UDim2.fromOffset(170, 70), Position = UDim2.new(1, -20, 1, -110), AnchorPoint = Vector2.new(1, 1) })
ui.turnText = label(ui.matchUI, "", { Size = UDim2.fromOffset(300, 34), Position = UDim2.new(1, -20, 1, -186), AnchorPoint = Vector2.new(1, 1), TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Right })
ui.timerText = label(ui.matchUI, "", { Size = UDim2.fromOffset(240, 26), Position = UDim2.new(1, -20, 1, -150), AnchorPoint = Vector2.new(1, 1), Font = BODY_FONT, TextStrokeTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Right })
button(ui.matchUI, "Leave", Color3.fromRGB(110, 60, 70), function()
	MenuAction:FireServer("LeaveMatch")
end, { Size = UDim2.fromOffset(100, 40), Position = UDim2.new(1, -16, 0, 16), AnchorPoint = Vector2.new(1, 0) })
-- Turns the action camera on or off (it glides back to your seat when turned off).
ui.camButton = button(ui.matchUI, actionCam.on and "🎥 Action cam: On" or "🎥 Action cam: Off", Color3.fromRGB(70, 85, 125), function()
	Settings.set("actionCam", not actionCam.on) -- (applied below, under "Applying settings")
end, { Name = "ActionCamButton", Size = UDim2.fromOffset(200, 32), Position = UDim2.new(1, -16, 0, 274), AnchorPoint = Vector2.new(1, 0) })

-- The in-match settings window (the same options as the Settings station in the room).
ui.matchSettings = panel(ui.matchUI, UDim2.fromOffset(420, 540), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
ui.matchSettings.Name = "MatchSettings"
ui.matchSettings.Visible = false
ui.matchSettings.ZIndex = 10
label(ui.matchSettings, "Settings", { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 8), TextColor3 = Color3.fromRGB(255, 220, 90) })
button(ui.matchSettings, "Done", Color3.fromRGB(60, 180, 90), function()
	ui.matchSettings.Visible = false
end, { Name = "SettingsDone", Size = UDim2.new(1, -24, 0, 42), Position = UDim2.new(0, 12, 1, -52) })
do
	local body = make("Frame", { Size = UDim2.new(1, -24, 1, -116), Position = UDim2.fromOffset(12, 54), BackgroundTransparency = 1 }, ui.matchSettings)
	ui.buildSettings(body)
end
button(ui.matchUI, "⚙ Settings", Color3.fromRGB(70, 85, 125), function()
	ui.matchSettings.Visible = not ui.matchSettings.Visible
end, { Name = "SettingsButton", Size = UDim2.fromOffset(200, 32), Position = UDim2.new(1, -16, 0, 312), AnchorPoint = Vector2.new(1, 0) })

---------------------------------------------------------------------------
-- Applying settings: every change takes effect at once and is saved to your account
---------------------------------------------------------------------------
do
	local Lighting = game:GetService("Lighting")
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local baseShadows = Lighting.GlobalShadows
	local baseBloom = bloom and bloom.Enabled
	local lampShadows = {} -- [light] = whether it casts shadows on High
	for _, d in ipairs(room:GetDescendants()) do
		if d:IsA("Light") then
			lampShadows[d] = d.Shadows
		end
	end

	local function apply(key, value)
		if key == "speed" then
			PACE = Settings.Pace[value] or 1
		elseif key == "actionCam" then
			actionCam.on = value
			if not value then
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
			for light, shadows in pairs(lampShadows) do
				if light.Parent then
					light.Shadows = shadows and not low
				end
			end
		elseif key == "blur" then
			if depthOfField then
				depthOfField.Enabled = value
			end
		end
		-- (sfx and music are read by Pack Brawl's sound player each time a brawl starts)
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

-- The hand sits low: cards peek out of the bottom of the screen and lift when you hover them.
ui.handFrame = make("Frame", { Size = UDim2.new(1, -680, 0, 160), Position = UDim2.new(0.5, 0, 1, 52), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, ui.matchUI)
ui.handHover = false

-- The opponent's hand: card backs under its name bar.
ui.oppHand = make("Frame", { Name = "OppHand", Size = UDim2.fromOffset(320, 48), Position = UDim2.new(0.5, 0, 0, 90), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, ui.matchUI)
ui.oppBacks = {}

-- The match log sits in the top right corner, under the Leave button.
ui.logFrame = make("Frame", { Size = UDim2.fromOffset(330, 200), Position = UDim2.new(1, -16, 0, 66), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(20, 16, 30), BackgroundTransparency = 0.45 }, ui.matchUI)
corner(ui.logFrame, 10)
make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, ui.logFrame)
make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }, ui.logFrame)

ui.promptBar = panel(ui.matchUI, UDim2.fromOffset(560, 120), UDim2.new(0.5, 0, 0, 100), Vector2.new(0.5, 0))
ui.promptBar.Name = "PromptBar"
ui.promptBar.Visible = false
ui.promptText = label(ui.promptBar, "", { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 8) })
ui.promptOptions = make("Frame", { Size = UDim2.new(1, -24, 1, -50), Position = UDim2.fromOffset(12, 44), BackgroundTransparency = 1 }, ui.promptBar)
make("UIGridLayout", { CellSize = UDim2.fromOffset(170, 30), CellPadding = UDim2.fromOffset(6, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }, ui.promptOptions)

ui.bannerText = label(ui.matchUI, "", { Size = UDim2.fromOffset(640, 86), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), TextColor3 = Color3.fromRGB(255, 220, 90), TextStrokeTransparency = 0, Visible = false, ZIndex = 10 })
ui.bannerScale = make("UIScale", { Scale = 1 }, ui.bannerText)
ui.popupHolder = make("Frame", { Size = UDim2.fromOffset(200, 280), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 8 }, ui.matchUI)
ui.previewHolder = make("Frame", { Size = UDim2.fromOffset(230, 322), Position = UDim2.new(0, 16, 0.42, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Visible = false }, ui.matchUI)

ui.dice = make("Frame", { Size = UDim2.fromOffset(110, 110), Position = UDim2.fromScale(0.5, 0.3), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 250, 240), Visible = false, ZIndex = 12 }, ui.matchUI)
corner(ui.dice, 20)
make("UIStroke", { Thickness = 4, Color = Color3.fromRGB(60, 40, 80) }, ui.dice)
ui.diceFace = label(ui.dice, "🎲", { ZIndex = 12, TextColor3 = Color3.fromRGB(60, 40, 80), Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1) })
ui.diceResult = label(ui.matchUI, "", { Size = UDim2.fromOffset(420, 40), Position = UDim2.fromScale(0.5, 0.3), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = Color3.fromRGB(255, 230, 120), TextStrokeTransparency = 0, Visible = false, ZIndex = 12 })

-- Small note next to the mouse: the terrain of the tile under it, or a hero's Big Move.
ui.tileTip = label(ui.matchUI, "", { Size = UDim2.fromOffset(260, 26), Font = BODY_FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(20, 16, 30), Visible = false, ZIndex = 20 })
corner(ui.tileTip, 6)
make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, ui.tileTip)

-- Full-screen color flash (damage, big moves, winning).
ui.flashFrame = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 50 }, gui)

-- Soft dark edges during a match (behind everything else on screen), so the eye goes to the lit board.
do
	ui.vignette = make("ScreenGui", { Name = "DeckWarsVignette", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, Enabled = false }, player:WaitForChild("PlayerGui"))
	local function edge(size, pos, rotation)
		local f = make("Frame", { Name = "Edge", Size = size, Position = pos, BackgroundColor3 = BLACK, BorderSizePixel = 0 }, ui.vignette)
		make("UIGradient", { Rotation = rotation, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }) }, f)
	end
	edge(UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), 90)
	edge(UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 0.76), -90)
	edge(UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0)
	edge(UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180)
end

local logLines = {}
local logCount = 0
local function log(text, color)
	logCount += 1
	local l = label(ui.logFrame, text, {
		Size = UDim2.new(1, 0, 0, 22),
		Font = BODY_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.3,
		TextColor3 = color or WHITE,
		LayoutOrder = logCount,
	})
	table.insert(logLines, l)
	if #logLines > 8 then
		table.remove(logLines, 1):Destroy()
	end
end

local bannerToken = nil
local function showBanner(text, seconds)
	local token = {}
	bannerToken = token
	ui.bannerText.Text = text
	ui.bannerText.TextTransparency = 0
	ui.bannerText.TextStrokeTransparency = 0
	ui.bannerText.Visible = true
	ui.bannerScale.Scale = 0.6
	TweenService:Create(ui.bannerScale, TweenInfo.new(0.35 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay((seconds or 1.3) * PACE, function()
		if bannerToken ~= token then
			return
		end
		TweenService:Create(ui.bannerText, TweenInfo.new(0.3 * PACE), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(0.32 * PACE, function()
			if bannerToken == token then
				ui.bannerText.Visible = false
			end
		end)
	end)
end

local function screenFlash(color, strength, seconds)
	ui.flashFrame.BackgroundColor3 = color
	ui.flashFrame.BackgroundTransparency = 1 - strength
	TweenService:Create(ui.flashFrame, TweenInfo.new((seconds or 0.5) * PACE), { BackgroundTransparency = 1 }):Play()
end

local popupToken = nil
-- Shows a card big in the middle of the screen. `from` is "top" (opponent) or "bottom" (you).
local function showCardPopup(cardId, seconds, from)
	ui.popupHolder:ClearAllChildren()
	local token = {}
	popupToken = token
	local card = makeCard(ui.popupHolder, cardId, UDim2.fromScale(1, 1))
	cardLife.wake(card, true)
	local startY = from == "top" and -1.6 or 1.6
	card.Position = UDim2.fromScale(0, startY)
	TweenService:Create(card, TweenInfo.new(0.4 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
	task.delay((seconds or 1.4) * PACE, function()
		if popupToken ~= token then
			return
		end
		TweenService:Create(card, TweenInfo.new(0.25 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.4, 0.6), Size = UDim2.fromScale(0.15, 0.15) }):Play()
		task.delay(0.27 * PACE, function()
			if popupToken == token then
				ui.popupHolder:ClearAllChildren()
			end
		end)
	end)
end

local previewKey = nil
local function showPreview(cardId, cost)
	local key = cardId .. ":" .. tostring(cost)
	if previewKey ~= key then
		ui.previewHolder:ClearAllChildren()
		cardLife.wake(makeCard(ui.previewHolder, cardId, UDim2.fromScale(1, 1), cost), true)
		-- What the card's keywords mean, under the card.
		local def = CardData.get(cardId)
		local lines = {}
		for _, kw in ipairs(CardData.Keywords) do
			if def.keywords and def.keywords[kw] then
				table.insert(lines, kw .. ": " .. CardData.KeywordText[kw])
			end
		end
		if def.type == "Building" then
			table.insert(lines, "Buildings never move or attack.")
		end
		local chant = def.type == "Creature" and CardData.Chants[def.family]
		if chant then
			table.insert(lines, "Chant: " .. chant.name .. " (" .. chant.cost .. " energy). " .. chant.text)
		end
		-- The family's own rule (how its cards build up together) and the combo words on the card.
		local text = def.text or ""
		local shown = {}
		local rule = def.type == "Creature" and CardData.FamilyRules[def.family]
		if rule and not (def.keywords and def.keywords[rule.name]) then
			table.insert(lines, rule.name .. ": " .. rule.text)
			shown[rule.name] = true
		end
		if def.type == "Building" then
			table.insert(lines, "When it breaks, it leaves 1 Scrap.")
			shown.Scrap = true
		end
		for _, word in ipairs({ "Combo", "Power", "Charge", "Soak", "Scrap" }) do
			if not shown[word] and CardData.RuleText[word] and string.find(text, word, 1, true) then
				table.insert(lines, word .. ": " .. CardData.RuleText[word])
				shown[word] = true
			end
		end
		-- (smaller text than before, because the combo rules add lines; about 30 letters per row)
		local rowsNeeded = 0
		for _, line in ipairs(lines) do
			rowsNeeded += math.max(1, math.ceil(#line / 30))
		end
		if #lines > 0 then
			local help = label(ui.previewHolder, table.concat(lines, "\n"), {
				Name = "KeywordHelp",
				Size = UDim2.new(1, 0, 0, 16 * rowsNeeded + 10),
				Position = UDim2.new(0, 0, 1, 6),
				Font = BODY_FONT,
				TextScaled = false,
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				BackgroundTransparency = 0.25,
				BackgroundColor3 = Color3.fromRGB(20, 16, 30),
			})
			corner(help, 8)
			make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4) }, help)
		end
		previewKey = key
	end
	ui.previewHolder.Visible = true
end

local function hidePreview()
	ui.previewHolder.Visible = false
end

local function tweenBar(fill, fraction)
	fraction = math.clamp(fraction, 0, 1)
	local before = fill.Size.X.Scale
	TweenService:Create(fill, TweenInfo.new(0.5 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(fraction, 1) }):Play()
	local trail = fill.Parent and fill.Parent:FindFirstChild("Trail")
	if trail then
		if fraction < before - 0.001 then
			-- lost health: the light part lingers a moment, then drains down to the new value
			TweenService:Create(trail, TweenInfo.new(0.7 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45 * PACE), { Size = UDim2.fromScale(fraction, 1) }):Play()
			local pop = fill.Parent:FindFirstChildOfClass("UIScale")
			if pop then
				pop.Scale = 1.08
				TweenService:Create(pop, TweenInfo.new(0.35 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		else
			trail.Size = UDim2.fromScale(fraction, 1)
		end
	end
end

---------------------------------------------------------------------------
-- The duel table: 30 tiles, heroes, energy crystals, card piles
---------------------------------------------------------------------------

local SIDES = { "Near", "Far" }
local COLS, ROWS = CardData.Cols, CardData.Rows
local TILES = {} -- [world column][world row] = tile part. World row 1 is the row nearest your chair.
for wc = 1, COLS do
	TILES[wc] = {}
	for wr = 1, ROWS do
		TILES[wc][wr] = board:WaitForChild("Tile_" .. wc .. "_" .. wr)
	end
end
local heroSpots = { Near = board:WaitForChild("Hero_Near"), Far = board:WaitForChild("Hero_Far") }
local heroGlows = { Near = board:WaitForChild("HeroGlow_Near"), Far = board:WaitForChild("HeroGlow_Far") }
local energyGems = { Near = {}, Far = {} }
local deckPiles = { Near = board:WaitForChild("Deck_Near"), Far = board:WaitForChild("Deck_Far") }
local discardPiles = { Near = board:WaitForChild("Discard_Near"), Far = board:WaitForChild("Discard_Far") }
for _, side in ipairs(SIDES) do
	for i = 1, CardData.MaxEnergy do
		energyGems[side][i] = board:WaitForChild("Energy_" .. side .. "_" .. i)
	end
end

-- Remember how everything looks outside a match, so it can be put back afterwards.
local looks = {}
local function remember(part)
	looks[part] = { Material = part.Material, Color = part.Color, Transparency = part.Transparency, Size = part.Size, CFrame = part.CFrame }
end
local function restore(part)
	local l = looks[part]
	if l then
		part.Material = l.Material
		part.Color = l.Color
		part.Transparency = l.Transparency
		part.Size = l.Size
		part.CFrame = l.CFrame
	end
end
for wc = 1, COLS do
	for wr = 1, ROWS do
		remember(TILES[wc][wr])
	end
end
for _, side in ipairs(SIDES) do
	for _, gem in ipairs(energyGems[side]) do
		remember(gem)
	end
	remember(deckPiles[side])
	remember(discardPiles[side])
	remember(heroGlows[side])
end

-- Height of the top surface of a part, whichever way it is turned.
local function topY(part)
	local cf, s = part.CFrame, part.Size
	local up = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
	return part.Position.Y + up / 2
end

-- The board is turned around for player 2, so your own back rows are always the ones nearest you.
-- flip() turns match (column, row) into table (column, row), and back again.
local function flip(col, row)
	if view and view.you == 2 then
		return COLS + 1 - col, ROWS + 1 - row
	end
	return col, row
end

local function tilePart(col, row)
	local wc, wr = flip(col, row)
	return TILES[wc] and TILES[wc][wr]
end

-- Where a unit stands on a tile. Models face -Z; the opponent's units are turned to face you.
local function tileCFrame(col, row, owner)
	local part = tilePart(col, row)
	if not part then
		return CFrame.new(0, 5, 0)
	end
	local p = part.Position
	local cf = CFrame.new(p.X, topY(part), p.Z)
	if view and owner ~= view.you then
		cf = cf * CFrame.Angles(0, math.pi, 0)
	end
	return cf
end

-- Heroes stand on their pedestals at the left of each half, turned a little toward the board.
local function heroCFrame(side)
	local spot = heroSpots[side]
	local p = spot.Position
	local cf = CFrame.new(p.X, topY(spot), p.Z)
	if side == "Far" then
		return cf * CFrame.Angles(0, math.pi + 0.55, 0)
	end
	return cf * CFrame.Angles(0, -0.55, 0)
end

local boardFolder = Instance.new("Folder")
boardFolder.Name = "LiveBoard"
boardFolder.Parent = workspace

-- Glowing frames on the tiles: where a creature can walk, what it can hit, where a card can go.
local glowFolder = Instance.new("Folder")
glowFolder.Name = "TableGlow"
glowFolder.Parent = workspace
local tileGlow = {} -- [world column][world row] = { bars, fill, on, tr }
do
	local function glowPart(size, cf)
		local p = Instance.new("Part")
		p.Name = "TileGlow"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 220, 90)
		p.Transparency = 1
		p.Size = size
		p.CFrame = cf
		p.Parent = glowFolder
		return p
	end
	for wc = 1, COLS do
		tileGlow[wc] = {}
		for wr = 1, ROWS do
			local tile = TILES[wc][wr]
			local p = tile.Position
			local y = topY(tile) + 0.035
			local half = tile.Size.X / 2 - 0.1
			local bars = {}
			for _, b in ipairs({ { 0, half, half * 2, 0.1 }, { 0, -half, half * 2, 0.1 }, { half, 0, 0.1, half * 2 }, { -half, 0, 0.1, half * 2 } }) do
				table.insert(bars, glowPart(Vector3.new(b[3], 0.06, b[4]), CFrame.new(p.X + b[1], y, p.Z + b[2])))
			end
			local fill = glowPart(Vector3.new(half * 2 - 0.2, 0.03, half * 2 - 0.2), CFrame.new(p.X, y - 0.01, p.Z))
			tileGlow[wc][wr] = { bars = bars, fill = fill, on = false, tr = 1, fillTr = 1 }
		end
	end
end

-- Extra aiming marks: the enemy hero (when a creature can hit it) and the tile under the mouse.
local aim = { hero = false, hoverWc = nil, hoverWr = nil }

local function glowTile(col, row, color)
	local wc, wr = flip(col, row)
	local g = tileGlow[wc] and tileGlow[wc][wr]
	if not g then
		return
	end
	g.on = true
	for _, bar in ipairs(g.bars) do
		bar.Color = color
	end
	g.fill.Color = color
end

local function clearGlows()
	for wc = 1, COLS do
		for wr = 1, ROWS do
			tileGlow[wc][wr].on = false
		end
	end
	aim.hero = false
end

local units = {} -- [uid] = entry for a creature or building: { model, cardId, kind, owner, col, row, home, ... }
local heroes = {} -- [side] = entry
local shownTerrain = {} -- [world column * 16 + world row] = family shown on that tile
local glowOverride = {} -- [side] = { color, untilTime }: hero pedestal flashes
local introPhase = false -- the opening draws play faster

local function sideOf(p)
	return (view and p == view.you) and "Near" or "Far"
end

local function otherSide(side)
	return side == "Near" and "Far" or "Near"
end

-- The unit standing on a tile (match coordinates), from what the screen is showing.
local function unitAt(col, row)
	for _, entry in pairs(units) do
		if entry.col == col and entry.row == row then
			return entry
		end
	end
	return nil
end


---------------------------------------------------------------------------
-- Animation helpers
---------------------------------------------------------------------------

-- Runs fn(alpha) every frame while alpha goes from 0 to 1 over `seconds` (scaled by PACE).
local function runTween(seconds, style, direction, fn, done)
	local value = Instance.new("NumberValue")
	value.Value = 0
	local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
		fn(value.Value)
	end)
	local tween = TweenService:Create(value, TweenInfo.new(math.max(0.01, seconds * PACE), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), { Value = 1 })
	tween.Completed:Connect(function()
		conn:Disconnect()
		value:Destroy()
		if done then
			done()
		end
	end)
	tween:Play()
	return tween
end

-- Like runTween, but for a creature or hero: a newer animation on the same model takes over,
-- and the idle bobbing pauses until the animation is done.
local function animateEntry(entry, seconds, style, direction, fn)
	entry.animId = (entry.animId or 0) + 1
	local id = entry.animId
	entry.busy = true
	entry.curLook, entry.lookYaw, entry.hopStart = 0, 0, nil
	return runTween(seconds, style, direction, function(a)
		if entry.animId == id and entry.model.Parent then
			fn(a)
		end
	end, function()
		if entry.animId == id then
			entry.busy = false
		end
	end)
end

-- Waits during the match playback. Stops the playback if the match ended meanwhile.
local ABORT = {}
local function step(seconds)
	task.wait(seconds * PACE)
	if playingMatch ~= matchId then
		error(ABORT, 0)
	end
end

local function fxPart(position, size)
	local p = Instance.new("Part")
	p.Name = "FX"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(size, size, size)
	p.CFrame = CFrame.new(position)
	p.Parent = boardFolder
	return p
end

-- A burst of glowing bits.
local function burst(position, color, count, opts)
	opts = opts or {}
	local holder = fxPart(position, opts.spread or 0.8)
	local speed = opts.speed or 6
	local life = opts.life or 0.5
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(life, life * 1.8)
	e.Speed = NumberRange.new(speed, speed * 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Acceleration = Vector3.new(0, opts.gravity or -8, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.size or 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.7) })
	e.Color = ColorSequence.new(color or WHITE)
	e.LightEmission = opts.glow or 0.35
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Parent = holder
	e:Emit(count or 25)
	Debris:AddItem(holder, 3)
end

-- A soft cloud (creatures popping, gadgets breaking).
local function smokePuff(position, color)
	local holder = fxPart(position, 1.2)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(1.5, 3.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 2
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(color or Color3.fromRGB(235, 230, 225))
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Parent = holder
	e:Emit(14)
	Debris:AddItem(holder, 3)
end

-- Numbers and words that pop up over the table and float away.
local function floatText(position, text, color, big)
	local holder = fxPart(position, 0.2)
	local bb = Instance.new("BillboardGui")
	bb.Size = big and UDim2.fromOffset(220, 80) or UDim2.fromOffset(170, 50)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = holder
	local l = label(bb, text, { TextColor3 = color or WHITE, TextStrokeTransparency = 0 })
	local scale = make("UIScale", { Scale = 0.3 }, l)
	TweenService:Create(scale, TweenInfo.new(0.3 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(holder, TweenInfo.new(1.5 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = position + Vector3.new(0, 2.5, 0) }):Play()
	task.delay(0.9 * PACE, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.5 * PACE), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(holder, 1.6 * PACE)
end

-- Tints a whole model for a moment (red when hit, white when popping).
local function flashModel(model, color, seconds)
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.15
	h.OutlineTransparency = 0.2
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = model
	TweenService:Create(h, TweenInfo.new((seconds or 0.35) * PACE), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(h, (seconds or 0.35) * PACE + 0.1)
end

-- A glowing circle on a pad that a creature rises out of. Returns a function that fades it out.
local function summonCircle(cf, color, radius)
	local center = cf.Position + Vector3.new(0, 0.03, 0)
	local flat = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	local disc = fxPart(center, 1)
	disc.Name = "SummonCircle"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 0.45
	disc.Size = Vector3.new(0.05, 0.4, 0.4)
	disc.CFrame = flat
	local core = fxPart(center, 1)
	core.Shape = Enum.PartType.Cylinder
	core.Material = Enum.Material.Neon
	core.Color = color:Lerp(WHITE, 0.7)
	core.Transparency = 0.55
	core.Size = Vector3.new(0.07, 0.3, 0.3)
	core.CFrame = flat
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 0
	light.Parent = disc
	local sparks = Instance.new("ParticleEmitter")
	sparks.EmissionDirection = Enum.NormalId.Right -- straight up, because the disc is turned on its side
	sparks.Rate = 9
	sparks.Lifetime = NumberRange.new(0.6, 1.1)
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(20, 20)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(color:Lerp(WHITE, 0.5))
	sparks.LightEmission = 0.4
	sparks.Parent = disc
	local d = radius * 2
	TweenService:Create(disc, TweenInfo.new(0.45 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, d, d) }):Play()
	TweenService:Create(core, TweenInfo.new(0.45 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.07, d * 0.62, d * 0.62) }):Play()
	TweenService:Create(light, TweenInfo.new(0.45 * PACE), { Brightness = 1.2 }):Play()
	return function()
		sparks.Enabled = false
		TweenService:Create(disc, TweenInfo.new(0.6 * PACE), { Transparency = 1, Size = Vector3.new(0.05, d * 1.15, d * 1.15) }):Play()
		TweenService:Create(core, TweenInfo.new(0.5 * PACE), { Transparency = 1 }):Play()
		TweenService:Create(light, TweenInfo.new(0.6 * PACE), { Brightness = 0 }):Play()
		Debris:AddItem(disc, 0.7 * PACE + 0.1)
		Debris:AddItem(core, 0.7 * PACE + 0.1)
	end
end

-- A glowing spark that flies from one point to another.
local function sparkTo(from, to, color, seconds)
	local s = fxPart(from, 0.32)
	s.Shape = Enum.PartType.Ball
	s.Material = Enum.Material.Neon
	s.Color = color
	s.Transparency = 0.15
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 4
	light.Brightness = 0.7
	light.Parent = s
	TweenService:Create(s, TweenInfo.new(seconds * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = to }):Play()
	Debris:AddItem(s, seconds * PACE + 0.05)
end

---------------------------------------------------------------------------
-- Creatures, buildings and heroes on the table
---------------------------------------------------------------------------

local newEntry
do
	local function findLids(model)
		local lids = {}
		for _, d in ipairs(model:GetDescendants()) do
			-- eyelids are the see-through "Lid" parts (a bin or jar lid is not an eyelid)
			if d:IsA("BasePart") and d.Name == "Lid" and d.Transparency > 0.99 then
				table.insert(lids, d)
			end
		end
		return lids
	end

	function newEntry(model, id, home)
		return {
			model = model,
			cardId = id,
			home = home,
			height = modelHeight(id),
			scale = 1,
			yaw = 0,
			phase = math.random() * 10,
			nextBlink = clock + 1 + math.random() * 3,
			lids = findLids(model),
			busy = false,
			animId = 0,
		}
	end
end

-- Small plate with attack and health that floats above a unit. Hover a unit to see its whole card.
local function attachLabel(entry)
	local bb = Instance.new("BillboardGui")
	bb.Name = "StatLabel"
	bb.Size = UDim2.fromOffset(92, 46)
	bb.StudsOffsetWorldSpace = Vector3.new(0, entry.height + 0.55, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = entry.model.PrimaryPart or entry.model:FindFirstChildWhichIsA("BasePart", true)
	bb.Parent = entry.model
	local back = make("Frame", { Size = UDim2.fromScale(1, 0.6), BackgroundColor3 = Color3.fromRGB(15, 12, 25), BackgroundTransparency = 0.3 }, bb)
	corner(back, 8)
	local stroke = make("UIStroke", { Thickness = 2, Color = WHITE, Transparency = 0.25 }, back)
	local stats = label(back, "", { Name = "Stats", Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2), TextStrokeTransparency = 0.2 })
	local keywords = label(bb, "", { Name = "Keywords", Size = UDim2.fromScale(1, 0.38), Position = UDim2.fromScale(0, 0.62), Font = BODY_FONT, TextColor3 = Color3.fromRGB(255, 230, 140), TextStrokeTransparency = 0.3 })
	local scale = make("UIScale", { Scale = 1 }, bb)
	entry.label = { gui = bb, stats = stats, keywords = keywords, scale = scale, stroke = stroke }
end

local function popLabel(entry)
	if entry.label then
		entry.label.gui.Enabled = true
		entry.label.scale.Scale = 0.4
		TweenService:Create(entry.label.scale, TweenInfo.new(0.3 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function showStats(entry)
	if not entry.label then
		return
	end
	if entry.kind == "creature" and entry.atk then
		entry.label.stats.Text = "⚔" .. entry.atk .. "  ❤" .. entry.hp
	else
		entry.label.stats.Text = "❤ " .. tostring(entry.hp or "?")
	end
	local hurt = entry.maxHp and entry.hp and entry.hp < entry.maxHp
	entry.label.stats.TextColor3 = hurt and Color3.fromRGB(255, 140, 140) or WHITE
end

-- A faint blue hexagon around the feet of a creature that is defending (until its owner's next turn).
local guardFx = {}
do
	local SIDES_N = 6
	function guardFx.set(entry, on)
		entry.defending = on or nil
		if on and not entry.guardBars then
			local r = TILES[1][1].Size.X * 0.46
			local bars = {}
			for i = 0, SIDES_N - 1 do
				local mid = (i + 0.5) * 2 * math.pi / SIDES_N
				local bar = Instance.new("Part")
				bar.Name = "GuardBar"
				bar.Anchored = true
				bar.CanCollide = false
				bar.CanQuery = false
				bar.CanTouch = false
				bar.CastShadow = false
				bar.Material = Enum.Material.Neon
				bar.Color = Color3.fromRGB(125, 180, 255)
				bar.Transparency = 1
				bar.Size = Vector3.new(r, 0.05, 0.06)
				bar.Parent = boardFolder
				local d = r * math.cos(math.pi / SIDES_N)
				table.insert(bars, { part = bar, offset = CFrame.new(math.cos(mid) * d, 0, math.sin(mid) * d) * CFrame.Angles(0, -mid + math.pi / 2, 0) })
			end
			entry.guardBars = bars
			entry.guardSince = clock
		elseif not on and entry.guardBars then
			local bars = entry.guardBars
			entry.guardBars = nil
			for _, b in ipairs(bars) do
				TweenService:Create(b.part, TweenInfo.new(0.4 * PACE), { Transparency = 1 }):Play()
				Debris:AddItem(b.part, 0.4 * PACE + 0.1)
			end
		end
	end
	-- Every frame: the hexagon follows its creature and breathes softly.
	function guardFx.update()
		local pulse = 0.5 + 0.5 * math.sin(clock * 1.4)
		for _, entry in pairs(units) do
			local bars = entry.guardBars
			if bars then
				local p = entry.model:GetPivot().Position
				local center = CFrame.new(p.X, entry.home.Position.Y + 0.13, p.Z)
				local fadeIn = math.min(1, (clock - (entry.guardSince or 0)) / 0.4)
				local tr = 1 - (0.4 - 0.06 * pulse) * fadeIn
				for _, b in ipairs(bars) do
					b.part.CFrame = center * b.offset
					b.part.Transparency = tr
				end
			end
		end
	end
end

-- The small line under a unit's stats shows only what is going on with it right now:
-- ⚡ Power, 💧 Soaked, 🔋 Charge left, Bubble, zZ (just arrived) and 🛡 (guarding).
-- Its keywords are on its card (hover the unit), which keeps the table quiet.
local function renderStatus(entry)
	if not entry.label then
		return
	end
	local words = {}
	if entry.power then
		table.insert(words, "⚡" .. entry.power)
	end
	if entry.soaked then
		table.insert(words, "💧")
	end
	if entry.charge then
		table.insert(words, "🔋" .. entry.charge)
	end
	if entry.bubble then
		table.insert(words, "Bubble")
	end
	if entry.sick then
		table.insert(words, "zZ")
	end
	if entry.defending then
		table.insert(words, "🛡")
	end
	entry.label.keywords.Text = table.concat(words, "  ")
end

local function setStats(entry, u)
	if not entry or not u then
		return
	end
	entry.atk, entry.hp, entry.maxHp = u.atk, u.hp, u.maxHp
	entry.canMove, entry.canAttack, entry.sick = u.canMove, u.canAttack, u.sick
	entry.chantNote = u.chantNote
	entry.power, entry.soaked, entry.charge = u.power, u.soaked, u.charge
	entry.bubble = table.find(u.keywords or {}, "Bubble") ~= nil
	showStats(entry)
	guardFx.set(entry, u.defending == true)
	renderStatus(entry)
end

-- Puts a creature or building on the table, shrunk to fit its tile.
-- u = { uid, id, kind ("creature" or "building"), owner, col, row }
local function spawnUnit(u)
	if units[u.uid] then
		return units[u.uid]
	end
	local model = buildModel(u.id)
	local ok, size = pcall(function()
		return model:GetExtentsSize()
	end)
	if not ok then
		size = Vector3.new(2.5, 2.5, 2.5)
	end
	local widest = math.max(size.X, size.Z, 0.5)
	local tileSize = TILES[1][1].Size.X
	local s = u.kind == "building" and math.min(0.56, tileSize * 0.96 / widest) or math.min(0.52, tileSize * 1.06 / widest)
	setScale(model, s)
	if (u.kind or "creature") == "creature" then
		-- A heavy round base, like a painted miniature: dark stone with a thin ring in its side's
		-- color (blue for yours, red for the opponent's). Its feet stand a little sunk into it.
		local mineBase = view and u.owner == view.you
		local pv = model:GetPivot()
		local function disc(name, d, h, color, material)
			local p = Instance.new("Part")
			p.Name = name
			p.Shape = Enum.PartType.Cylinder
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.Material = material
			p.Color = color
			p.Size = Vector3.new(h, d, d)
			p.CFrame = pv * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			p.Parent = model
		end
		disc("Base", 1.6, 0.1, mineBase and Color3.fromRGB(38, 44, 58) or Color3.fromRGB(58, 38, 38), Enum.Material.Slate)
		disc("BaseRing", 1.7, 0.035, mineBase and Color3.fromRGB(80, 140, 215) or Color3.fromRGB(205, 85, 85), Enum.Material.SmoothPlastic)
	end
	local home = tileCFrame(u.col, u.row, u.owner)
	local entry = newEntry(model, u.id, home)
	entry.uid, entry.kind, entry.owner, entry.col, entry.row = u.uid, u.kind or "creature", u.owner, u.col, u.row
	entry.scale = s
	entry.height = size.Y * s
	entry.hp = CardData.Cards[u.id] and CardData.Cards[u.id].hp
	model:PivotTo(home)
	-- Let the mouse find the model (clicking a creature picks it).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanQuery = true
		end
	end
	model.Parent = boardFolder
	attachLabel(entry)
	local mine = view and u.owner == view.you
	entry.label.stroke.Color = mine and Color3.fromRGB(110, 190, 255) or Color3.fromRGB(255, 110, 110)
	showStats(entry)
	units[u.uid] = entry
	return entry
end

-- The unit comes up out of its tile, a little small, and pops to full size.
local function riseUp(entry, seconds, facingCamera)
	local model, home = entry.model, entry.home
	local depth = entry.height + 0.4
	entry.yaw = facingCamera and math.pi or 0
	local yaw = entry.yaw
	model:PivotTo(home * CFrame.new(0, -depth, 0) * CFrame.Angles(0, yaw, 0))
	setScale(model, entry.scale * 0.75)
	animateEntry(entry, seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
		model:PivotTo(home * CFrame.new(0, -depth * (1 - a), 0) * CFrame.Angles(0, yaw, 0))
		setScale(model, entry.scale * (0.75 + 0.25 * math.min(a, 1.15)))
	end)
end

-- Your new creatures first look at you, then hop around to face the enemy.
local function turnToFight(entry, seconds)
	local model, home = entry.model, entry.home
	animateEntry(entry, seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, function(a)
		model:PivotTo(home * CFrame.new(0, math.sin(a * math.pi) * 0.4, 0) * CFrame.Angles(0, math.pi * (1 - a), 0))
		if a >= 1 then
			entry.yaw = 0
		end
	end)
end

-- Quick appearance (no waiting), for anything the step-by-step playback didn't show.
local function quickRise(entry)
	if entry.label then
		entry.label.gui.Enabled = false
	end
	riseUp(entry, 0.6, false)
	task.delay(0.6 * PACE, function()
		if entry.model.Parent then
			popLabel(entry)
		end
	end)
end

-- Turn to look along a direction on the table (models face -Z).
local function facing(dir)
	if dir.Magnitude < 0.01 then
		return CFrame.new()
	end
	return CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0)
end

-- Walk along a path in one smooth motion: it turns toward each step, bounces from tile to tile
-- leaning into the walk, settles on the last tile and turns to face the enemy again.
local function walkPath(entry, path)
	local model = entry.model
	local points = { entry.home.Position }
	for _, t in ipairs(path) do
		table.insert(points, tileCFrame(t.col, t.row, entry.owner).Position)
	end
	local n = #points - 1
	if n < 1 then
		return
	end
	local r0 = model:GetPivot().Rotation
	local turns = {}
	for i = 1, n do
		turns[i] = facing(points[i + 1] - points[i])
	end
	local seconds = 0.46 * n + 0.08
	animateEntry(entry, seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
		a = math.clamp(a, 0, 1)
		local u = a * n
		local i = math.min(n, math.floor(u) + 1)
		local f = u - (i - 1)
		local k = math.sin(f * math.pi)
		local pos = points[i]:Lerp(points[i + 1], f) + Vector3.new(0, k * 0.38, 0)
		local before = i == 1 and r0 or turns[i - 1]
		model:PivotTo(CFrame.new(pos) * before:Lerp(turns[i], math.min(1, f * 3)) * CFrame.Angles(-0.12 * k, 0, 0))
	end)
	step(seconds)
	local last = path[#path]
	entry.col, entry.row = last.col, last.row
	entry.home = tileCFrame(last.col, last.row, entry.owner)
	entry.yaw = 0
	local home = entry.home
	local endTurn = turns[n]
	animateEntry(entry, 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
		a = math.min(a, 1)
		model:PivotTo(CFrame.new(home.Position - Vector3.new(0, math.sin(a * math.pi) * 0.05, 0)) * endTurn:Lerp(home.Rotation, a))
	end)
end

-- Jump in an arc to another tile (pushes, Total Chaos, catching up with the server).
local function hopTo(entry, col, row, seconds, height)
	local from = entry.model:GetPivot().Position
	entry.col, entry.row = col, row
	entry.home = tileCFrame(col, row, entry.owner)
	entry.yaw = 0
	local to = entry.home
	local model = entry.model
	animateEntry(entry, seconds or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, function(a)
		local pos = from:Lerp(to.Position, a) + Vector3.new(0, math.sin(math.min(a, 1) * math.pi) * (height or 2.0), 0)
		model:PivotTo(CFrame.new(pos) * to.Rotation)
	end)
end

-- A creature pops (or a building breaks) and is taken off the table.
local function removeUnit(uid, quick, faded)
	local entry = units[uid]
	if not entry then
		return
	end
	units[uid] = nil
	guardFx.set(entry, false)
	local model = entry.model
	local start = model:GetPivot()
	if entry.label then
		entry.label.gui.Enabled = false
	end
	if faded then
		-- A creature brought back by Raise doesn't pop again: it sinks into the table in a purple mist.
		local mist = Color3.fromRGB(150, 110, 210)
		smokePuff(start.Position + Vector3.new(0, 0.3, 0), Color3.fromRGB(120, 100, 150))
		burst(start.Position + Vector3.new(0, entry.height * 0.6, 0), mist:Lerp(WHITE, 0.25), 10, { speed = 2, gravity = -1.5, life = 0.8 })
		local parts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, { d, d.Transparency })
			end
		end
		local depth = entry.height + 0.3
		animateEntry(entry, 1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.In, function(a)
			a = math.min(a, 1)
			model:PivotTo(start * CFrame.new(0, -depth * a, 0) * CFrame.Angles(0, a * 0.8, 0))
			for _, pt in ipairs(parts) do
				pt[1].Transparency = pt[2] + (1 - pt[2]) * a
			end
		end)
		Debris:AddItem(model, 1.0 * PACE + 0.1)
		return
	end
	if entry.kind == "building" then
		burst(start.Position + Vector3.new(0, 0.6, 0), Color3.fromRGB(200, 200, 210), 12, { speed = 5, glow = 0.1 })
		smokePuff(start.Position + Vector3.new(0, 0.5, 0), Color3.fromRGB(150, 150, 150))
		animateEntry(entry, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
			model:PivotTo(start * CFrame.new(0, -1.4 * a, 0) * CFrame.Angles(0.4 * a, 0, 0.3 * a))
		end)
		Debris:AddItem(model, 0.5 * PACE + 0.1)
		return
	end
	flashModel(model, WHITE, 0.5)
	local mid = start.Position + Vector3.new(0, entry.height * 0.5, 0)
	burst(mid, Color3.fromRGB(255, 235, 200), quick and 6 or 10, { speed = 6, life = 0.5, glow = 0.25 })
	smokePuff(mid)
	local seconds = quick and 0.45 or 0.75
	animateEntry(entry, seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
		model:PivotTo(start * CFrame.new(0, 0.9 * a - 2.6 * a * a, 0) * CFrame.Angles(0, a * math.pi * 2.5, 0))
		setScale(model, entry.scale * (1 - 0.85 * math.min(a, 1)))
	end)
	Debris:AddItem(model, seconds * PACE + 0.1)
end

-- Scrap heaps: little piles of plates and nuts in a corner of a tile (1 to 3 heaps per tile).
-- Junk creatures that step there pick them up.
local scrapFx = { heaps = {} } -- [match column * 16 + match row] = { n = heaps, parts = { part, ... } }
do
	local LOOKS = {
		{ Vector3.new(0.32, 0.06, 0.24), Color3.fromRGB(128, 120, 108), Enum.Material.DiamondPlate },
		{ Vector3.new(0.17, 0.17, 0.17), Color3.fromRGB(150, 112, 78), Enum.Material.CorrodedMetal },
	}
	local OFFSETS = { Vector3.new(0, 0, 0), Vector3.new(0.2, 0, -0.06), Vector3.new(0.04, 0, -0.22) }

	-- The near-left corner of the tile, out from under the creature's base.
	local function heapSpot(col, row)
		local part = tilePart(col, row)
		if not part then
			return nil
		end
		local half = part.Size.X / 2
		return Vector3.new(part.Position.X - half * 0.6, topY(part), part.Position.Z + half * 0.6)
	end

	local function newBit(i, at)
		local look = LOOKS[(i - 1) % 2 + 1]
		local p = Instance.new("Part")
		p.Name = "Scrap"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = look[1]
		p.Color = look[2]
		p.Material = look[3]
		local pos = at + OFFSETS[math.ceil(i / 2)] + Vector3.new((i % 2) * 0.1, look[1].Y / 2 + (i % 2) * 0.03, 0)
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi * 2, (math.random() - 0.5) * 0.4)
		p.Parent = boardFolder
		return p
	end

	function scrapFx.count(col, row)
		local heap = scrapFx.heaps[col * 16 + row]
		return heap and heap.n or 0
	end

	-- Puts exactly n heaps on a tile. drop: the new pieces fall onto the tile.
	function scrapFx.set(col, row, n, drop)
		local at = heapSpot(col, row)
		if not at then
			return
		end
		local key = col * 16 + row
		local heap = scrapFx.heaps[key] or { n = 0, parts = {} }
		scrapFx.heaps[key] = heap
		n = math.clamp(n or 0, 0, 3)
		while #heap.parts > n * 2 do
			table.remove(heap.parts):Destroy()
		end
		while #heap.parts < n * 2 do
			local i = #heap.parts + 1
			local p = newBit(i, at)
			table.insert(heap.parts, p)
			if drop then
				local rest = p.CFrame
				p.CFrame = rest + Vector3.new(0, 1.6, 0)
				TweenService:Create(p, TweenInfo.new((0.35 + 0.05 * i) * PACE, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = rest }):Play()
			end
		end
		heap.n = n
		if n == 0 then
			scrapFx.heaps[key] = nil
		end
	end

	-- A Junk creature picks up the heaps on a tile: the pieces fly into it.
	function scrapFx.pick(col, row, to)
		local key = col * 16 + row
		local heap = scrapFx.heaps[key]
		if not heap then
			return
		end
		for i, p in ipairs(heap.parts) do
			local seconds = (0.3 + 0.04 * i) * PACE
			TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(to) * CFrame.Angles(math.random() * 3, math.random() * 3, 0), Size = p.Size * 0.4 }):Play()
			Debris:AddItem(p, seconds + 0.05)
		end
		scrapFx.heaps[key] = nil
	end

	-- Matches the heaps on the table to the game state exactly (no animation).
	function scrapFx.sync(list)
		local want = {}
		for _, s in ipairs(list or {}) do
			want[s.col * 16 + s.row] = s.n
		end
		for key, heap in pairs(scrapFx.heaps) do
			if not want[key] then
				for _, p in ipairs(heap.parts) do
					p:Destroy()
				end
				scrapFx.heaps[key] = nil
			end
		end
		for key, n in pairs(want) do
			local col, row = math.floor(key / 16), key % 16
			if scrapFx.count(col, row) ~= n then
				scrapFx.set(col, row, n)
			end
		end
	end
end

local function heroLabelText(entry)
	return (entry.name or "Hero") .. "  ❤ " .. tostring(entry.hp or "?")
end

local function placeHero(side, heroId, hp)
	local id = "hero_" .. heroId
	local model = buildModel(id)
	local home = heroCFrame(side)
	local entry = newEntry(model, id, home)
	entry.side = side
	entry.name = CardData.Heroes[heroId] and CardData.Heroes[heroId].name or heroId
	entry.hp = hp
	model:PivotTo(home)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanQuery = true
		end
	end
	model.Parent = boardFolder
	local bb = Instance.new("BillboardGui")
	bb.Name = "HeroLabel"
	bb.Size = UDim2.fromOffset(170, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, entry.height + 0.9, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	bb.Parent = model
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(15, 12, 25), BackgroundTransparency = 0.35 }, bb)
	corner(back, 8)
	entry.heroText = label(back, heroLabelText(entry), { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), TextStrokeTransparency = 0.3 })
	heroes[side] = entry
	return entry
end

local function setHeroHp(side, hp)
	local entry = heroes[side]
	if entry and hp then
		entry.hp = hp
		entry.heroText.Text = heroLabelText(entry)
	end
	if hp and view then
		if side == "Near" then
			tweenBar(ui.meHpFill, hp / CardData.HeroMaxHp)
			ui.meHpText.Text = "❤ " .. hp
		else
			tweenBar(ui.oppHpFill, hp / CardData.HeroMaxHp)
			ui.oppHpText.Text = "❤ " .. hp
		end
	end
end

local function flashPedestal(side, color, seconds)
	glowOverride[side] = { color = color, untilTime = clock + seconds * PACE }
end

-- Energy crystals: bright = ready to spend, dim = used this turn, dark = not unlocked yet.
local gemState = { Near = {}, Far = {} }
local function setGem(side, i, state)
	if gemState[side][i] == state then
		return
	end
	gemState[side][i] = state
	local gem = energyGems[side][i]
	if state == "full" then
		gem.Material = Enum.Material.Neon
		gem.Color = Color3.fromRGB(90, 220, 255)
		gem.Transparency = 0
	elseif state == "spent" then
		gem.Material = Enum.Material.Glass
		gem.Color = Color3.fromRGB(70, 120, 150)
		gem.Transparency = 0.35
	else
		gem.Material = Enum.Material.Glass
		gem.Color = Color3.fromRGB(35, 40, 55)
		gem.Transparency = 0.6
	end
end

local shownEnergy = { Near = { 0, 0 }, Far = { 0, 0 } }
local function showEnergy(side, energy, maxEnergy)
	shownEnergy[side] = { energy, maxEnergy }
	for i = 1, #energyGems[side] do
		setGem(side, i, i <= energy and "full" or (i <= maxEnergy and "spent" or "locked"))
	end
end

-- At the start of a turn the crystals light up one after another.
local function refillEnergy(side, energy, maxEnergy)
	shownEnergy[side] = { energy, maxEnergy }
	local myMatch = matchId
	task.spawn(function()
		for i = 1, #energyGems[side] do
			if matchId ~= myMatch then
				return
			end
			setGem(side, i, i <= energy and "full" or (i <= maxEnergy and "spent" or "locked"))
			if i <= energy then
				task.wait(0.07 * PACE)
			end
		end
	end)
end

local function spendEnergy(side, cost)
	if not cost or cost <= 0 then
		return
	end
	local e = shownEnergy[side]
	showEnergy(side, math.max(0, e[1] - cost), e[2])
end

-- Card piles grow and shrink with the number of cards in them.
local pileCount = { Near = {}, Far = {} }
local function setPile(side, which, count)
	local part = which == "deck" and deckPiles[side] or discardPiles[side]
	pileCount[side][which] = count
	local base = looks[part]
	if not base then
		return
	end
	local bottom = base.CFrame.Position.Y - base.Size.Y / 2
	if count <= 0 then
		part.Transparency = 1
		return
	end
	local h = math.clamp(0.04 + count * 0.022, 0.06, 1.2)
	part.Transparency = base.Transparency
	part.Size = Vector3.new(base.Size.X, h, base.Size.Z)
	part.CFrame = base.CFrame.Rotation + Vector3.new(base.CFrame.Position.X, bottom + h / 2, base.CFrame.Position.Z)
end

-- A card back lifts off the deck and flies to its owner.
local function flyCardFromDeck(side)
	local deck = deckPiles[side]
	local top = Vector3.new(deck.Position.X, topY(deck) + 0.05, deck.Position.Z)
	local card = fxPart(top, 1)
	card.Size = Vector3.new(1.4, 0.05, 2.0)
	card.Color = Color3.fromRGB(40, 60, 150)
	card.Material = Enum.Material.SmoothPlastic
	card.Transparency = 0
	local target
	if side == "Near" then
		target = cam.pos:Lerp(cam.look, 0.3) - Vector3.new(0, 2.5, 0)
	else
		target = Vector3.new(0, 7, -13)
	end
	TweenService:Create(card, TweenInfo.new(0.45 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(target) * CFrame.Angles(math.rad(side == "Near" and 60 or -60), 0, math.rad(15)),
		Transparency = 1,
	}):Play()
	Debris:AddItem(card, 0.5 * PACE + 0.1)
	local n = pileCount[side].deck
	if n then
		setPile(side, "deck", n - 1)
	end
end

-- Terrain: every tile gets the material and color of its terrain.
local setTileTerrain
do
	local TERRAIN_LOOK = {
		-- Deep, heavy colors in each family's own hue (the same color as its cards), so you can
		-- see at a glance where your creatures get +1 attack. Textured stone, metal, ice and cloth
		-- make the tiles feel solid instead of shiny.
		Snack = { Enum.Material.Marble, Color3.fromRGB(150, 84, 50) }, -- Soda Swamp: amber
		Junk = { Enum.Material.CorrodedMetal, Color3.fromRGB(104, 94, 80) }, -- Glitter Junkyard: rusty plate
		Weather = { Enum.Material.Glacier, Color3.fromRGB(78, 112, 150) }, -- Static Snowfield: deep ice
		-- Critter and Robo used Fabric and CrackedLava, which rendered almost black under the dim
		-- table lamps in Studio, so they use brighter-reading materials (Sand, DiamondPlate) instead.
		Critter = { Enum.Material.Sand, Color3.fromRGB(84, 120, 64) }, -- Pillow Peaks: moss green felt
		Spooky = { Enum.Material.CeramicTiles, Color3.fromRGB(96, 70, 128) }, -- Mushroom Mall: dusk tiles
		Robo = { Enum.Material.DiamondPlate, Color3.fromRGB(118, 124, 142) }, -- Lava Laundromat: grey steel plate
	}

	function setTileTerrain(col, row, fam, animated)
		local wc, wr = flip(col, row)
		local k = wc * 16 + wr
		local look = TERRAIN_LOOK[fam]
		if not look or shownTerrain[k] == fam then
			return
		end
		shownTerrain[k] = fam
		local tile = TILES[wc][wr]
		-- every other tile is a little darker, so the grid is easy to read
		local color = (wc + wr) % 2 == 0 and look[2] or look[2]:Lerp(BLACK, 0.12)
		if not animated then
			tile.Material = look[1]
			tile.Color = color
			return
		end
		local base = looks[tile] and looks[tile].CFrame or tile.CFrame
		runTween(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			local k2 = math.sin(math.min(a, 1) * math.pi)
			tile.CFrame = base * CFrame.new(0, 0.25 * k2, 0) * CFrame.Angles(k2 * 0.35, 0, 0)
		end, function()
			tile.CFrame = base
		end)
		task.delay(0.2 * PACE, function()
			if shownTerrain[k] == fam then
				tile.Material = look[1]
				tile.Color = color
			end
		end)
		burst(tile.Position + Vector3.new(0, 0.4, 0), familyColor(fam), 8, { speed = 3, gravity = -3, size = 0.3 })
	end
end

-- Puts the table back the way it looks outside a match.
local function clearBoard()
	boardFolder:ClearAllChildren()
	scrapFx.heaps = {}
	cam.lean, cam.leanTarget, cam.leanPoint = 0, 0, nil
	actionCam.reset()
	units, heroes = {}, {}
	shownTerrain = {}
	glowOverride = {}
	gemState = { Near = {}, Far = {} }
	pileCount = { Near = {}, Far = {} }
	for part in pairs(looks) do
		restore(part)
	end
	clearGlows()
end

-- Everything that sits on the table at the start of a match.
local function setupTable(v)
	for p = 1, 2 do
		local side = sideOf(p)
		local pv = v.players[p]
		placeHero(side, pv.hero, pv.hp)
		quickRise(heroes[side])
		showEnergy(side, pv.energy, pv.maxEnergy)
		setPile(side, "deck", pv.deckCount + (pv.handCount or 0))
		setPile(side, "discard", pv.discardCount or 0)
	end
	-- The terrain rolls out row by row, starting at your end of the table.
	for wr = 1, ROWS do
		for wc = 1, COLS do
			local col, row = flip(wc, wr)
			setTileTerrain(col, row, v.terrain[col][row], true)
		end
		step(0.18)
	end
end

---------------------------------------------------------------------------
-- Your moves: pick a creature and click where it walks or what it hits,
-- or pick a card and click where it goes
---------------------------------------------------------------------------

local handCache = {} -- [hand uid] = { holder, card, overlay, glow, entry, cost }
local pick = nil -- what you are aiming: { kind = "unit" | "card" | "bigmove", ... }
local reselect = nil -- after a walk, pick the same creature again so it can attack

local AIM = {
	walk = Color3.fromRGB(110, 175, 240),
	hit = Color3.fromRGB(240, 95, 90),
	friend = Color3.fromRGB(130, 230, 150),
	place = Color3.fromRGB(245, 210, 110),
	picked = Color3.fromRGB(245, 245, 235),
	ready = Color3.fromRGB(140, 225, 160),
	strike = Color3.fromRGB(195, 135, 245),
}

local function cardName(id)
	return CardData.get(id).name
end

local function myTurn()
	return view ~= nil and not view.over and view.current == view.you
end

local function canAct()
	return mode == "match" and not busy and not processing and myTurn()
end

local function clearPromptButtons()
	for _, c in ipairs(ui.promptOptions:GetChildren()) do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
end

-- On your turn, the tiles under creatures that can still walk or attack glow softly.
local function showReadyGlows()
	clearGlows()
	if not canAct() or not view then
		return
	end
	local ready = {}
	for _, a in ipairs(view.legal or {}) do
		if a.uid and (a.kind == "move" or a.kind == "attack" or a.kind == "defend" or a.kind == "chant") then
			ready[a.uid] = true
		end
	end
	for uid in pairs(ready) do
		local entry = units[uid]
		if entry then
			glowTile(entry.col, entry.row, AIM.ready)
		end
	end
end

local function clearPrompt()
	ui.promptBar.Visible = false
	clearPromptButtons()
	pick = nil
	showReadyGlows()
end

local function sendAction(action)
	ui.promptBar.Visible = false
	clearPromptButtons()
	pick = nil
	clearGlows()
	busy = true
	-- The played card lifts out of your hand while the server answers.
	if action.kind == "play" and action.handUid then
		local h = handCache[action.handUid]
		if h then
			h.played = true
		end
	end
	MatchAction:FireServer(action)
end

local function showPrompt(text)
	ui.promptText.Text = text
	ui.promptBar.Visible = true
	clearPromptButtons()
end

local function addCancel()
	button(ui.promptOptions, "Cancel", Color3.fromRGB(90, 90, 100), clearPrompt)
end

-- Pick one of your creatures: blue tiles = where it can walk, green = a friend it can swap
-- places with, red = what it can hit. Its other commands are buttons: Defend and its Chant.
local function selectUnit(uid)
	local entry = units[uid]
	if not entry then
		return
	end
	clearGlows()
	pick = { kind = "unit", uid = uid }
	local walks, swaps, hits = 0, 0, 0
	local defend, chants = nil, {}
	for _, a in ipairs(view.legal or {}) do
		if a.uid == uid then
			if a.kind == "move" then
				glowTile(a.to.col, a.to.row, a.swap and AIM.friend or AIM.walk)
				if a.swap then
					swaps += 1
				else
					walks += 1
				end
			elseif a.kind == "attack" then
				if a.hero then
					aim.hero = true
				else
					glowTile(a.target.col, a.target.row, AIM.hit)
				end
				hits += 1
			elseif a.kind == "defend" then
				defend = a
			elseif a.kind == "chant" then
				table.insert(chants, a)
			end
		end
	end
	glowTile(entry.col, entry.row, AIM.picked)
	local name = cardName(entry.cardId)
	local hints = {}
	if walks > 0 then
		table.insert(hints, "blue = walk")
	end
	if swaps > 0 then
		table.insert(hints, "green = swap places")
	end
	if hits > 0 then
		table.insert(hints, "red = attack" .. (aim.hero and " (the hero too)" or ""))
	end
	if #hints > 0 then
		showPrompt(name .. ": " .. table.concat(hints, ", ") .. (defend and ", or a button" or ""))
	else
		showPrompt(name .. ": pick a command")
	end
	if defend then
		button(ui.promptOptions, "🛡 Defend", Color3.fromRGB(70, 110, 170), function()
			if canAct() then
				sendAction(defend)
			end
		end)
	end
	local family = CardData.get(entry.cardId).family
	local chant = CardData.Chants[family]
	if chant and defend then
		local text = "✨ " .. chant.name .. " · " .. chant.cost .. "⚡"
		if #chants > 0 then
			button(ui.promptOptions, text, familyColor(family):Lerp(BLACK, 0.45), function()
				if not canAct() then
					return
				end
				if not chant.target then
					sendAction(chants[1])
					return
				end
				-- An aimed chant: what it can reach glows purple.
				clearGlows()
				pick = { kind = "chant", uid = uid, cands = chants }
				for _, a in ipairs(chants) do
					if a.target then
						glowTile(a.target.col, a.target.row, AIM.strike)
					end
				end
				glowTile(entry.col, entry.row, AIM.picked)
				showPrompt(chant.name .. ": pick a glowing target")
				button(ui.promptOptions, "Back", Color3.fromRGB(90, 90, 100), function()
					if canAct() then
						selectUnit(uid)
					end
				end)
				addCancel()
			end)
		else
			-- Can't chant right now: a grey button that says why when clicked.
			local b = button(ui.promptOptions, text, Color3.fromRGB(64, 64, 72), nil, { AutoButtonColor = false, TextTransparency = 0.45 })
			b.Activated:Connect(function()
				log(chant.name .. ": " .. (entry.chantNote or "can't be used right now"), Color3.fromRGB(255, 190, 160))
			end)
		end
	end
	addCancel()
end

local function unitHasActions(uid)
	for _, a in ipairs(view.legal or {}) do
		if a.uid == uid and (a.kind == "move" or a.kind == "attack" or a.kind == "defend" or a.kind == "chant") then
			return true
		end
	end
	return false
end

-- Where a card can go (tiles) or what it can aim at (targets), for the current step.
local function showCardStep()
	clearGlows()
	clearPromptButtons()
	local name = cardName(pick.cardId)
	if pick.step == "tile" then
		for _, a in ipairs(pick.cands) do
			local t = a.tile or a.target
			if t then
				glowTile(t.col, t.row, AIM.place)
			end
		end
		local def = CardData.get(pick.cardId)
		if def.type == "Creature" then
			showPrompt("Pick a glowing tile for " .. name .. " (your back two rows)")
		elseif def.type == "Building" then
			showPrompt("Pick a glowing tile for " .. name .. " (your half of the board)")
		else
			showPrompt("Pick a tile for " .. name)
		end
	elseif pick.step == "target" then
		if pick.tile then
			glowTile(pick.tile.col, pick.tile.row, AIM.place)
		end
		for _, a in ipairs(pick.cands) do
			if a.target then
				local u = unitAt(a.target.col, a.target.row)
				glowTile(a.target.col, a.target.row, (u and u.owner == view.you) and AIM.friend or AIM.hit)
			end
		end
		showPrompt("Pick a target for " .. name)
	elseif pick.step == "terrain" then
		glowTile(pick.tile.col, pick.tile.row, AIM.place)
		showPrompt("Pick the new terrain")
		for _, a in ipairs(pick.cands) do
			local fam = a.target.terrain
			button(ui.promptOptions, CardData.Terrains[fam] or fam, familyColor(fam):Lerp(BLACK, 0.35), function()
				sendAction(a)
			end)
		end
	end
	addCancel()
end

local function onCardClicked(entry)
	if not canAct() then
		return
	end
	local cands = {}
	for _, a in ipairs(view.legal or {}) do
		if a.kind == "play" and a.handUid == entry.uid then
			table.insert(cands, a)
		end
	end
	if #cands == 0 then
		log("You can't play " .. cardName(entry.id) .. " right now", Color3.fromRGB(255, 160, 160))
		return
	end
	if #cands == 1 and not cands[1].tile and not cands[1].target then
		sendAction(cands[1]) -- a spell with nothing to aim at
		return
	end
	local def = CardData.get(entry.id)
	pick = { kind = "card", cardId = entry.id, handUid = entry.uid, cands = cands }
	if def.type ~= "Spell" or def.target == "tileAndTerrain" then
		pick.step = "tile"
	else
		pick.step = "target"
	end
	showCardStep()
end

ui.bigMoveButton.Activated:Connect(function()
	if not canAct() then
		return
	end
	local cands = {}
	for _, a in ipairs(view.legal or {}) do
		if a.kind == "bigmove" then
			table.insert(cands, a)
		end
	end
	if #cands == 0 then
		return
	end
	if #cands == 1 and not cands[1].col then
		sendAction(cands[1])
		return
	end
	clearGlows()
	pick = { kind = "bigmove", cands = cands }
	for _, a in ipairs(cands) do
		for row = 1, ROWS do
			glowTile(a.col, row, AIM.strike)
		end
	end
	showPrompt("Pick a column for the bowling ball")
	addCancel()
end)

ui.endTurnButton.Activated:Connect(function()
	if not canAct() then
		return
	end
	sendAction({ kind = "endturn" })
end)

-- A click on the board: hit = { col, row } (match coordinates) or { hero = side }.
local function onBoardClick(hit)
	if not canAct() or not view then
		return
	end
	if pick and pick.kind == "unit" then
		for _, a in ipairs(view.legal or {}) do
			if a.uid == pick.uid then
				local match = false
				if hit.hero then
					match = a.kind == "attack" and a.hero == true and hit.hero == "Far"
				elseif a.kind == "move" then
					match = a.to.col == hit.col and a.to.row == hit.row
				elseif a.kind == "attack" and a.target then
					match = a.target.col == hit.col and a.target.row == hit.row
				end
				if match then
					if a.kind == "move" then
						reselect = a.uid
					end
					sendAction(a)
					return
				end
			end
		end
	elseif pick and pick.kind == "card" and hit.col then
		local rest = {}
		for _, a in ipairs(pick.cands) do
			local t = (pick.step == "tile") and (a.tile or a.target) or a.target
			if t and t.col == hit.col and t.row == hit.row then
				table.insert(rest, a)
			end
		end
		if #rest == 0 then
			return -- not a glowing tile; keep aiming
		end
		if pick.step == "tile" then
			pick.tile = { col = hit.col, row = hit.row }
			pick.cands = rest
			if rest[1].target and rest[1].target.terrain then
				pick.step = "terrain"
				showCardStep()
			elseif #rest == 1 then
				sendAction(rest[1])
			else
				pick.step = "target"
				showCardStep()
			end
		else
			sendAction(rest[1])
		end
		return
	elseif pick and pick.kind == "bigmove" and hit.col then
		for _, a in ipairs(pick.cands) do
			if a.col == hit.col then
				sendAction(a)
				return
			end
		end
		return
	elseif pick and pick.kind == "chant" then
		for _, a in ipairs(pick.cands) do
			if a.target and hit.col and a.target.col == hit.col and a.target.row == hit.row then
				sendAction(a)
				return
			end
		end
		return -- not a glowing target; keep aiming
	end
	-- Pick one of your creatures that can still do something.
	if hit.col then
		local entry = unitAt(hit.col, hit.row)
		if entry and entry.owner == view.you and entry.kind == "creature" and unitHasActions(entry.uid) then
			selectUnit(entry.uid)
			return
		end
	end
	if pick then
		clearPrompt()
	end
end

-- The back of a card (shown while a new card flips over).
local function makeCardBack(parent, small)
	local back = make("Frame", { Name = "CardBack", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(46, 52, 128), ZIndex = 8 }, parent)
	corner(back, small and 5 or 10)
	make("UIStroke", { Thickness = small and 2 or 4, Color = Color3.fromRGB(240, 200, 90) }, back)
	make("UIGradient", { Rotation = 60, Color = ColorSequence.new(Color3.fromRGB(120, 130, 230), Color3.fromRGB(70, 40, 120)) }, back)
	label(back, "DECK\nWARS", { ZIndex = 9, Size = UDim2.fromScale(0.8, 0.4), Position = UDim2.fromScale(0.1, 0.3), TextColor3 = Color3.fromRGB(255, 225, 120), TextStrokeTransparency = 0.3 })
	return back
end

-- A card in your hand. The holder is the spot in the fan (and catches the mouse); the mover inside
-- it carries the card and its glow, so lifting, scaling and flipping move both together.
local function makeHandCard(entry)
	local holder = make("TextButton", { Name = "HandCard", Text = "", BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromOffset(110, 154), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0) }, ui.handFrame)
	local mover = make("Frame", { Name = "Mover", Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1 }, holder)
	local scale = make("UIScale", { Scale = 1 }, mover)
	local glow = make("Frame", { Name = "Glow", Size = UDim2.new(1, 10, 1, 10), Position = UDim2.fromOffset(-5, -5), BackgroundColor3 = Color3.fromRGB(130, 255, 150), BackgroundTransparency = 0.45, ZIndex = 0, Visible = false }, mover)
	corner(glow, 14)
	local card = makeCard(mover, entry.id, UDim2.fromScale(1, 1), entry.cost)
	card.ZIndex = 1
	local overlay = make("Frame", { Name = "Unplayable", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.5, ZIndex = 5 }, card)
	corner(overlay, 10)
	local comboTag = label(card, "COMBO", { Name = "ComboTag", Size = UDim2.fromScale(0.62, 0.13), Position = UDim2.fromScale(0.19, -0.06), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 205, 80), TextColor3 = Color3.fromRGB(60, 35, 10), ZIndex = 7, Visible = false })
	corner(comboTag, 6)
	local h = {
		holder = holder, mover = mover, scale = scale, card = card, overlay = overlay, glow = glow, comboTag = comboTag, entry = entry, cost = entry.cost,
		x = 0, y = 0, tx = 0, ty = 0, z = 1, lift = 0, s = 1, phase = math.random() * 6.28, hover = false,
		art = cardLife.wake(card, false),
	}
	-- Hover a card to lift it out of the fan; its creature turns around to show itself.
	holder.MouseEnter:Connect(function()
		ui.handHover = true
		h.hover = true
		if h.art then
			h.art.hover = true
		end
		holder.ZIndex = 30
		showPreview(h.entry.id, h.entry.cost)
	end)
	holder.MouseLeave:Connect(function()
		ui.handHover = false
		h.hover = false
		if h.art then
			h.art.hover = false
		end
		holder.ZIndex = h.z
		hidePreview()
	end)
	holder.Activated:Connect(function()
		onCardClicked(h.entry)
	end)
	return h
end

-- Keeps the hand cards on screen in step with the hand. New cards rise out of the bottom face down
-- and flip over; the fan spreads out or closes up smoothly as cards come and go.
local function refreshHand(me)
	local hand = me.hand or {}
	local n = #hand
	local available = math.max(300, gui.AbsoluteSize.X - 2 * 340)
	local cardW = math.clamp(math.floor((available + (n - 1) * 18) / math.max(1, n)), 70, 110)
	local spacing = n > 1 and math.min(cardW - 14, (available - cardW) / (n - 1)) or 0
	local seen = {}
	local newCards = 0
	for i, entry in ipairs(hand) do
		seen[entry.uid] = true
		local h = handCache[entry.uid]
		local k = n > 1 and ((i - 1) / (n - 1) * 2 - 1) or 0 -- -1 at the left end, 1 at the right
		local tx, ty = (i - (n + 1) / 2) * spacing, 12 * k * k -- the ends of the fan sit a little lower
		if not h then
			h = makeHandCard(entry)
			handCache[entry.uid] = h
			newCards += 1
			h.x, h.y = tx, ty
			h.enterAt = clock + (newCards - 1) * 0.14 * PACE
			h.back = makeCardBack(h.mover)
		end
		h.tx, h.ty, h.z = tx, ty, i
		h.played, h.flyTo = nil, nil
		h.holder.Visible = true
		if not h.hover then
			h.holder.ZIndex = i
		end
		h.entry = entry
		h.holder.Size = UDim2.fromOffset(cardW, math.floor(cardW * 1.4))
		if h.cost ~= entry.cost then
			h.cost = entry.cost
			local circle = h.card:FindFirstChild("CostCircle")
			local costLabel = circle and circle:FindFirstChild("Cost")
			if costLabel then
				local base = CardData.get(entry.id).cost
				costLabel.Text = tostring(entry.cost)
				costLabel.TextColor3 = entry.cost < base and Color3.fromRGB(140, 255, 150) or (entry.cost > base and Color3.fromRGB(255, 150, 150) or WHITE)
			end
		end
		local playable = entry.playable and myTurn()
		h.overlay.Visible = not playable
		h.glow.Visible = playable == true
		-- its combo is ready (another card of its family was played this turn): gold tag and glow
		local combo = entry.combo == true and myTurn()
		h.comboTag.Visible = combo == true
		h.glow.BackgroundColor3 = combo and Color3.fromRGB(255, 205, 80) or Color3.fromRGB(130, 255, 150)
	end
	for uid, h in pairs(handCache) do
		if not seen[uid] then
			h.holder:Destroy()
			handCache[uid] = nil
		end
	end
end

-- Every frame: the hand cards glide to their spots, bob gently, lift when hovered, and new ones
-- rise and flip over. Cards you play fly toward their tile.
function cardLife.updateHand(dt)
	local follow = math.min(1, dt * 12)
	for _, h in pairs(handCache) do
		h.x += (h.tx - h.x) * follow
		h.y += (h.ty - h.y) * follow
		h.holder.Position = UDim2.new(0.5, h.x, 1, h.y)
		local enter, flip = 0, 1
		if h.enterAt then
			local a = math.clamp((clock - h.enterAt) / (0.45 * PACE), 0, 1)
			local rise = 1 - (1 - a) * (1 - a) * (1 - a)
			enter = 260 * (1 - rise)
			local f = math.clamp((clock - h.enterAt - 0.32 * PACE) / (0.3 * PACE), 0, 1) -- the flip starts as it lands
			flip = math.abs(math.cos(f * math.pi))
			if h.back and f >= 0.5 then
				h.back:Destroy()
				h.back = nil
			end
			if f >= 1 then
				h.enterAt = nil
				flip = 1
			end
		end
		local liftTo = h.flyTo and 0 or (h.played and -140 or (h.hover and -58 or 0))
		h.lift += (liftTo - h.lift) * math.min(1, dt * 14)
		local bob = 0 -- cards rest still in the fan (calmer); hovering still lifts them
		local sTo = h.flyTo and 0.25 or (h.hover and 1.14 or 1)
		h.s += (sTo - h.s) * math.min(1, dt * (h.flyTo and 7 or 14))
		h.scale.Scale = h.s
		local fx, fy = 0, 0
		if h.flyTo then
			local a = math.clamp((clock - h.flyStart) / (0.4 * PACE), 0, 1)
			local e = a * a * (3 - 2 * a)
			local center = h.holder.AbsolutePosition + h.holder.AbsoluteSize / 2
			fx, fy = (h.flyTo.X - center.X) * e, (h.flyTo.Y - center.Y) * e
			if a >= 1 then
				h.holder.Visible = false
			end
		end
		h.mover.Position = UDim2.new(0.5, fx, 0.5, h.lift + bob + enter + fy)
		h.mover.Size = UDim2.fromScale(flip, 1)
		if h.glow.Visible then
			h.glow.BackgroundTransparency = 0.45
		end
	end
end

-- The opponent's card backs: new ones drop in, played ones slide away, the rest fan out.
function cardLife.setOppHand(n)
	local backs = ui.oppBacks
	while #backs < n do
		local b = makeCardBack(ui.oppHand, true)
		b.Size = UDim2.fromOffset(32, 44)
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.new(0.5, 0, 0, -70)
		table.insert(backs, b)
	end
	while #backs > n do
		local b = table.remove(backs)
		TweenService:Create(b, TweenInfo.new(0.3 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = b.Position + UDim2.fromOffset(0, 70), BackgroundTransparency = 1 }):Play()
		Debris:AddItem(b, 0.32 * PACE + 0.05)
	end
	local count = #backs
	for i, b in ipairs(backs) do
		local k = count > 1 and ((i - 1) / (count - 1) * 2 - 1) or 0
		b.ZIndex = i
		TweenService:Create(b, TweenInfo.new(0.35 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, (i - (count + 1) / 2) * 22, 0, 5 * k * k), Rotation = k * 8 }):Play()
	end
end

-- The card you just played flies from your hand to its tile (or the middle of the table for spells).
function cardLife.flyPlayed(handUid, worldPos)
	local h = handCache[handUid]
	if not h then
		return
	end
	local sp = camera:WorldToViewportPoint(worldPos)
	h.flyTo = Vector2.new(sp.X, sp.Y)
	h.flyStart = clock
	h.hover = false
	if h.art then
		h.art.hover = false
	end
end

local function clearHand()
	for _, h in pairs(handCache) do
		h.holder:Destroy()
	end
	handCache = {}
	ui.handHover = false
	for _, b in ipairs(ui.oppBacks) do
		b:Destroy()
	end
	ui.oppBacks = {}
end

local function refreshUI(v)
	local me, opp = v.players[v.you], v.players[3 - v.you]
	local myHero = CardData.Heroes[me.hero]
	local oppHero = CardData.Heroes[opp.hero]
	ui.oppName.Text = (v.botName or "Opponent") .. " · " .. oppHero.name
	ui.oppInfo.Text = string.format("Hand %d · Deck %d · Energy %d/%d", opp.handCount, opp.deckCount, opp.energy, opp.maxEnergy)
	cardLife.setOppHand(opp.handCount or 0)
	tweenBar(ui.oppHpFill, opp.hp / CardData.HeroMaxHp)
	ui.oppHpText.Text = "❤ " .. opp.hp
	ui.meName.Text = player.DisplayName .. " · " .. myHero.name
	tweenBar(ui.meHpFill, me.hp / CardData.HeroMaxHp)
	ui.meHpText.Text = "❤ " .. me.hp
	ui.energyText.Text = string.format("Energy %d/%d   Deck %d", me.energy, me.maxEnergy, me.deckCount)
	if me.bigMoveUsed then
		ui.bigMoveButton.Text = myHero.bigMove .. " (used)"
	elseif me.bigMoveReady then
		ui.bigMoveButton.Text = myHero.bigMove .. " READY!"
	else
		ui.bigMoveButton.Text = string.format("%s %d/%d", myHero.bigMove, me.bigMoveCharge, CardData.BigMoveCharge)
	end
	ui.bigMoveButton.BackgroundColor3 = (me.bigMoveReady and myTurn()) and Color3.fromRGB(190, 90, 240) or Color3.fromRGB(90, 70, 110)
	turnState = myTurn() and "you" or (v.over and "over" or "opp")
	ui.turnText.Text = turnState == "you" and "Your turn!" or (turnState == "over" and "Match over" or "Opponent is thinking")
	-- The End Turn button glows brighter once nothing else can be done.
	local left = 0
	for _, a in ipairs(v.legal or {}) do
		if a.kind ~= "endturn" then
			left += 1
		end
	end
	if not myTurn() then
		ui.endTurnButton.BackgroundColor3 = Color3.fromRGB(110, 90, 90)
	elseif left == 0 then
		ui.endTurnButton.BackgroundColor3 = Color3.fromRGB(240, 120, 40)
	else
		ui.endTurnButton.BackgroundColor3 = Color3.fromRGB(200, 100, 60)
	end
	refreshHand(me)
end

---------------------------------------------------------------------------
-- Playing back what happened, one event at a time, then syncing to the final state
---------------------------------------------------------------------------

local animateEvent, confettiBurst
local bot = { model = nil, base = nil, lean = 0, leanUntil = 0 } -- the bot opponent leans in when it plays a card
do
	local function who(p)
		return p == view.you and "You" or "Opponent"
	end

	local function entryTop(entry)
		return entry.home.Position + Vector3.new(0, entry.height + 0.5, 0)
	end

	local function entryMid(entry)
		return entry.home.Position + Vector3.new(0, math.max(0.6, entry.height * 0.55), 0)
	end

	local function heroMid(side)
		local h = heroes[side]
		if h then
			return h.home.Position + Vector3.new(0, h.height * 0.6, 0)
		end
		return heroSpots[side].Position + Vector3.new(0, 1.5, 0)
	end

	-- Direction along the table from one point to another (and how far).
	local function flatDir(from, to, fallback)
		local d = (to - from) * Vector3.new(1, 0, 1)
		if d.Magnitude < 0.05 then
			return fallback, 0
		end
		return d.Unit, d.Magnitude
	end

	-- A small, quiet puff where a hit lands: a little dust and a few warm sparks.
	local function impactPuff(position, amount)
		local n = math.clamp(amount or 1, 1, 6)
		local holder = fxPart(position, 0.5)
		local dust = Instance.new("ParticleEmitter")
		dust.Rate = 0
		dust.Lifetime = NumberRange.new(0.35, 0.6)
		dust.Speed = NumberRange.new(1.5, 3)
		dust.SpreadAngle = Vector2.new(180, 60)
		dust.Drag = 4
		dust.Acceleration = Vector3.new(0, 1.5, 0)
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.9) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		dust.Color = ColorSequence.new(Color3.fromRGB(225, 215, 200))
		dust.Rotation = NumberRange.new(0, 360)
		dust.Parent = holder
		dust:Emit(5 + n)
		burst(position, Color3.fromRGB(255, 225, 175), 3 + n, { speed = 5, size = 0.18, life = 0.25, glow = 0.3, gravity = -12 })
		Debris:AddItem(holder, 1.5)
	end

	-- A flat ring of light that spreads over the table from a point and fades: the thud of a hit.
	local function shockRing(position, color, radius, seconds)
		seconds = seconds or 0.35
		local ring = fxPart(position, 1)
		ring.Name = "ShockRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 0.45
		ring.Size = Vector3.new(0.03, 0.3, 0.3)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
		local d = radius * 2
		TweenService:Create(ring, TweenInfo.new(seconds * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.02, d, d), Transparency = 1 }):Play()
		Debris:AddItem(ring, seconds * PACE + 0.05)
	end

	-- Healing: a soft column of green light rises through the creature and fades, with a few motes.
	local function healGlow(entry)
		local base = entry.home.Position
		local h = math.max(1.2, entry.height + 0.4)
		local column = fxPart(base, 1)
		column.Name = "HealGlow"
		column.Shape = Enum.PartType.Cylinder
		column.Material = Enum.Material.Neon
		column.Color = Color3.fromRGB(130, 255, 160)
		column.Transparency = 0.72
		column.Size = Vector3.new(0.2, 1.3, 1.3)
		column.CFrame = CFrame.new(base + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		TweenService:Create(column, TweenInfo.new(0.55 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(h, 1.05, 1.05),
			CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Transparency = 1,
		}):Play()
		Debris:AddItem(column, 0.6 * PACE + 0.05)
		flashModel(entry.model, Color3.fromRGB(120, 255, 140), 0.45)
		burst(base + Vector3.new(0, h * 0.5, 0), Color3.fromRGB(150, 255, 170), 6, { speed = 1.5, gravity = 3, size = 0.2, life = 0.7 })
	end

	-- Casting a spell: light gathers into a glowing orb over the caster's side of the table,
	-- then it bursts. The spell's effect follows.
	local function castGlow(position, color)
		local orb = fxPart(position, 0.2)
		orb.Name = "CastGlow"
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Neon
		orb.Color = color:Lerp(WHITE, 0.3)
		orb.Transparency = 0.25
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 9
		light.Brightness = 0
		light.Parent = orb
		TweenService:Create(orb, TweenInfo.new(0.4 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.9, 0.9, 0.9) }):Play()
		TweenService:Create(light, TweenInfo.new(0.4 * PACE), { Brightness = 1.8 }):Play()
		step(0.42)
		TweenService:Create(orb, TweenInfo.new(0.22 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(1.8, 1.8, 1.8), Transparency = 1 }):Play()
		TweenService:Create(light, TweenInfo.new(0.25 * PACE), { Brightness = 0 }):Play()
		burst(position, color:Lerp(WHITE, 0.4), 10, { speed = 5, gravity = -2, size = 0.22, life = 0.45 })
		Debris:AddItem(orb, 0.3 * PACE + 0.05)
		step(0.15)
	end

	-- Knocked back by a hit: slides a little away from the hitter, tips back and settles.
	local function knockBack(entry, away, strength)
		local model, home = entry.model, entry.home
		local rest = (home * CFrame.Angles(0, entry.yaw, 0)).Rotation
		local axis = Vector3.new(0, 1, 0):Cross(away)
		if axis.Magnitude < 1e-3 then
			axis = Vector3.new(1, 0, 0)
		end
		local push = 0.32 * (strength or 1)
		entry.noRecoilUntil = clock + 1.2 * PACE
		animateEntry(entry, 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
			a = math.min(a, 1)
			local k = math.sin(a * math.pi) * (1 - 0.35 * a)
			model:PivotTo(CFrame.new(home.Position + away * push * k) * CFrame.fromAxisAngle(axis, 0.3 * k) * rest)
		end)
	end

	-- A defender swings back at the creature that hit it, without leaving its tile.
	local function swingBack(entry, toward)
		local model, home = entry.model, entry.home
		local unit = flatDir(home.Position, toward, home.LookVector)
		local turn = facing(unit)
		local r0 = model:GetPivot().Rotation
		local rest = (home * CFrame.Angles(0, entry.yaw, 0)).Rotation
		local axis = Vector3.new(0, 1, 0):Cross(unit)
		if axis.Magnitude < 1e-3 then
			axis = Vector3.new(1, 0, 0)
		end
		entry.noRecoilUntil = clock + 1.2 * PACE
		animateEntry(entry, 0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			a = math.min(a, 1)
			local k = math.sin(a * math.pi)
			local rot = a < 0.6 and r0:Lerp(turn, math.min(1, a / 0.25)) or turn:Lerp(rest, (a - 0.6) / 0.4)
			model:PivotTo(CFrame.new(home.Position + unit * 0.4 * k) * CFrame.fromAxisAngle(axis, 0.22 * k) * rot)
		end)
	end

	-- Wind up (turn, crouch, lean back), then leap at the target. Returns where it landed,
	-- how it was turned and the direction of the hit.
	local function leapAt(entry, targetPos, stopShort, maxReach)
		local model, home = entry.model, entry.home
		local unit, dist = flatDir(home.Position, targetPos, home.LookVector)
		local turn = facing(unit)
		local r0 = model:GetPivot().Rotation
		local reach = math.clamp(dist - (stopShort or 1.05), 0.3, maxReach or 99)
		local back = home.Position - unit * 0.3
		animateEntry(entry, 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			a = math.min(a, 1)
			model:PivotTo(CFrame.new(home.Position:Lerp(back, a) - Vector3.new(0, 0.1 * a, 0)) * r0:Lerp(turn, math.min(1, a * 1.6)) * CFrame.Angles(0.22 * a, 0, 0))
		end)
		step(0.42)
		local stop = home.Position + unit * reach
		animateEntry(entry, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
			a = math.min(a, 1)
			local pos = back:Lerp(stop, a) + Vector3.new(0, math.sin(a * math.pi) * 0.75 - 0.1 * (1 - a), 0)
			model:PivotTo(CFrame.new(pos) * turn * CFrame.Angles(0.22 - 0.52 * a, 0, 0))
		end)
		step(0.22)
		return stop, turn, unit
	end

	-- Bounce back from the hit and hop home, turning to face the enemy again.
	local function hopHome(entry, from, turn, seconds)
		local model, home = entry.model, entry.home
		local rest = (home * CFrame.Angles(0, entry.yaw, 0)).Rotation
		seconds = seconds or 0.5
		entry.noRecoilUntil = clock + seconds * PACE + 0.3
		animateEntry(entry, seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			a = math.min(a, 1)
			local pos = from:Lerp(home.Position, a) + Vector3.new(0, math.sin(a * math.pi) * 0.45, 0)
			model:PivotTo(CFrame.new(pos) * turn:Lerp(rest, a) * CFrame.Angles(-0.3 * (1 - a) * (1 - a), 0, 0))
		end)
	end

	-- A small glowing shot that arcs from one point to another (ranged attacks, catapults, rockets).
	local function projectile(from, to, color, seconds, arc)
		local shot = fxPart(from, 0.3)
		shot.Shape = Enum.PartType.Ball
		shot.Material = Enum.Material.Neon
		shot.Color = color:Lerp(WHITE, 0.25)
		shot.Transparency = 0.15
		local trail = Instance.new("ParticleEmitter")
		trail.Rate = 30
		trail.Lifetime = NumberRange.new(0.15, 0.3)
		trail.Speed = NumberRange.new(0, 0.3)
		trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		trail.Color = ColorSequence.new(color)
		trail.LightEmission = 0.3
		trail.Parent = shot
		local height = arc or math.min(2.2, (to - from).Magnitude * 0.25)
		runTween(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, function(a)
			a = math.min(a, 1)
			shot.Position = from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * height, 0)
		end, function()
			shot:Destroy()
		end)
		step(seconds)
		impactPuff(to, 2)
	end

	-- One attack, played like a short scene: the camera leans in, the attacker winds up and leaps,
	-- the hit lands (the defender is knocked back, or swings back if it hits back), and the attacker
	-- hops home. The effects stay small on purpose, so the creatures are what you watch.
	local function attackAnimation(e)
		local entry = units[e.uid]
		if not entry then
			return
		end
		local mine = e.player == view.you
		local target = e.target ~= "hero" and units[e.target] or nil
		local targetPos
		if e.target == "hero" then
			targetPos = heroMid(sideOf(e.targetPlayer or (3 - e.player)))
		elseif target then
			targetPos = entryMid(target)
		else
			return
		end
		local home = entry.home
		local partner = e.sandwich and units[e.sandwich]
		if partner then
			-- Sandwich: a friend stands right behind the target, so this hit lands 1 harder.
			floatText(entryTop(partner), "Sandwich! +1", Color3.fromRGB(255, 200, 120), false)
			local pm, prest = partner.model, partner.home * CFrame.Angles(0, partner.yaw, 0)
			animateEntry(partner, 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
				pm:PivotTo(prest * CFrame.new(0, math.sin(math.min(a, 1) * math.pi) * 0.25, 0))
			end)
		end
		leanCamera((home.Position + targetPos) / 2, e.target == "hero" and 0.6 or 1)
		local fresh = actionCam.on and not actionCam.active()
		actionCam.duel(home.Position, targetPos, { seconds = 0.6, lookUp = e.target == "hero" and 0.9 or 0.7 })
		if fresh then
			step(0.3) -- let the camera arrive before the attacker moves
		end
		if e.ranged then
			-- Ranged: a little hop in place and a shot that arcs across the tiles.
			local model = entry.model
			local unit = flatDir(home.Position, targetPos, home.LookVector)
			local turn = facing(unit)
			local r0 = model:GetPivot().Rotation
			animateEntry(entry, 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
				a = math.min(a, 1)
				local k = math.sin(a * math.pi)
				model:PivotTo(CFrame.new(home.Position + Vector3.new(0, 0.35 * k, 0) - unit * 0.15 * k) * r0:Lerp(turn, math.min(1, a * 2)) * CFrame.Angles(0.15 * k, 0, 0))
			end)
			step(0.3)
			projectile(entryMid(entry), targetPos, familyColor(CardData.get(entry.cardId).family), 0.45)
			actionCam.punch(3)
			if target then
				shockRing(target.home.Position + Vector3.new(0, 0.14, 0), Color3.fromRGB(255, 232, 190), 0.95)
				if e.guarded then
					flashModel(target.model, Color3.fromRGB(150, 200, 255), 0.35)
				end
				knockBack(target, unit, 0.8)
			end
			shakeCamera(0.06)
			hopHome(entry, home.Position, turn, 0.35)
			step(0.15)
			leanCamera(nil)
			actionCam.release(0.5)
			return
		end
		if e.target == "hero" then
			-- A creature charges a step toward the enemy hero and hurls its hit.
			local stop, turn = leapAt(entry, targetPos, 0, 1.0)
			impactPuff(stop + Vector3.new(0, 0.2, 0), 1)
			projectile(stop + Vector3.new(0, 1, 0), targetPos, Color3.fromRGB(255, 210, 120), 0.4)
			local heroEntry = heroes[sideOf(e.targetPlayer or (3 - e.player))]
			if heroEntry then
				shockRing(heroEntry.home.Position + Vector3.new(0, 0.1, 0), Color3.fromRGB(255, 200, 150), 1.4)
			end
			actionCam.punch(4)
			shakeCamera(0.08 + math.min(e.amount or 1, 6) * 0.02)
			hopHome(entry, stop, turn, 0.5)
			step(0.15)
			leanCamera(nil)
			actionCam.release(0.5)
			return
		end
		local stop, turn, unit = leapAt(entry, targetPos, 1.05)
		impactPuff(targetPos - unit * 0.4, e.amount)
		actionCam.punch(3 + math.min(e.amount or 1, 6) * 0.5)
		if target then
			-- The hit lands: a quick flash on the target and a ring of light at its feet...
			flashModel(target.model, e.guarded and Color3.fromRGB(150, 200, 255) or WHITE, e.guarded and 0.35 or 0.18)
			shockRing(target.home.Position + Vector3.new(0, 0.14, 0), Color3.fromRGB(255, 232, 190), 1.0 + math.min(e.amount or 1, 6) * 0.15)
		end
		shakeCamera(0.08 + math.min(e.amount or 1, 6) * 0.025)
		step(0.07) -- ...and everything holds for a split second (hit-stop) before the knock-back
		if target then
			if e.counter then
				swingBack(target, stop)
				if mine then
					log(cardName(target.cardId) .. " hits back!", Color3.fromRGB(255, 200, 160))
				end
			else
				knockBack(target, unit, 1)
			end
		end
		step(0.1) -- a short pause on the hit
		hopHome(entry, stop, turn, 0.5)
		step(0.2)
		leanCamera(nil)
		actionCam.release(0.5)
	end

	-- Flash when hit. Units the attack already knocked back don't flinch a second time.
	local function hitAnimation(entry, amount, color)
		local model, home = entry.model, entry.home
		flashModel(model, color, 0.4)
		if clock < (entry.noRecoilUntil or 0) then
			return
		end
		local rest = (home * CFrame.Angles(0, entry.yaw or 0, 0)).Rotation
		animateEntry(entry, 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
			local k = math.sin(math.min(a, 1) * math.pi)
			model:PivotTo(CFrame.new(home.Position) * rest * CFrame.new(0, 0, 0.25 * k) * CFrame.Angles(0.22 * k, 0, 0))
		end)
		if amount and amount >= 4 then
			shakeCamera(0.12)
		end
	end

	local function heroHit(side, amount, hp)
		local entry = heroes[side]
		if entry then
			hitAnimation(entry, amount, Color3.fromRGB(255, 60, 60))
			floatText(entryTop(entry), "-" .. amount, Color3.fromRGB(255, 80, 80), true)
		end
		flashPedestal(side, Color3.fromRGB(255, 60, 60), 0.6)
		if side == "Near" then
			screenFlash(Color3.fromRGB(255, 40, 40), 0.1, 0.45)
		end
		shakeCamera(0.1 + math.min(amount or 1, 8) * 0.025)
		setHeroHp(side, hp)
	end

	local function rollDice(resultText)
		ui.dice.Visible = true
		ui.dice.Rotation = 0
		ui.diceResult.Visible = false
		TweenService:Create(ui.dice, TweenInfo.new(0.9 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 720 }):Play()
		for _ = 1, 7 do
			ui.diceFace.Text = tostring(math.random(1, 6))
			step(0.12)
		end
		ui.diceFace.Text = "🎲"
		ui.diceResult.Text = resultText
		ui.diceResult.Position = UDim2.new(0.5, 0, 0.3, 64)
		ui.diceResult.Visible = true
		local myMatch = matchId
		task.delay(1.3 * PACE, function()
			if matchId == myMatch or mode == "menu" then
				ui.dice.Visible = false
				ui.diceResult.Visible = false
			end
		end)
	end

	function confettiBurst()
		for i = 1, 5 do
			local x = (i - 3) * 4
			burst(Vector3.new(x, 7, 0), Color3.fromHSV(i / 5, 0.7, 1), 30, { speed = 10, gravity = -10, life = 1.2, size = 0.35, glow = 0.3 })
		end
	end

	-- Granny's bowling ball rolls down a column toward the enemy and stops at the first enemy.
	local function bowlingBall(e)
		local enemy = 3 - e.player
		local rows = {}
		for r = 1, ROWS do
			table.insert(rows, r)
		end
		if e.player == 2 then
			rows = {}
			for r = ROWS, 1, -1 do
				table.insert(rows, r)
			end
		end
		local stopRow = nil
		for _, r in ipairs(rows) do
			local u = unitAt(e.col, r)
			if u and u.owner == enemy then
				stopRow = r
				break
			end
		end
		local startPart = tilePart(e.col, rows[1])
		local endPart = tilePart(e.col, stopRow or rows[#rows])
		if not startPart or not endPart then
			return
		end
		local away = (endPart.Position - startPart.Position)
		local dirUnit = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)
		local y = topY(startPart) + 0.55
		local from = Vector3.new(startPart.Position.X, y, startPart.Position.Z) - dirUnit * 1.4
		local to = Vector3.new(endPart.Position.X, y, endPart.Position.Z)
		local ball = fxPart(from, 1.1)
		ball.Shape = Enum.PartType.Ball
		ball.Material = Enum.Material.Neon
		ball.Color = Color3.fromRGB(150, 70, 230)
		ball.Transparency = 0
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(190, 120, 255)
		light.Range = 10
		light.Brightness = 3
		light.Parent = ball
		local seconds = 0.25 + 0.12 * (from - to).Magnitude / 2.8
		TweenService:Create(ball, TweenInfo.new(seconds * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = to }):Play()
		step(seconds)
		burst(to, Color3.fromRGB(200, 140, 255), 30, { speed = 9 })
		shakeCamera(0.35)
		Debris:AddItem(ball, 0.05)
	end

	-- Events that follow an action keep the action camera there; the rest send it back to the seat.
	local FOLLOW_UPS = {
		damage = true, heal = true, buff = true, pop = true, destroyed = true, heroDamage = true, heroHeal = true,
		push = true, bump = true, blocked = true, guardDown = true, bubble = true, cleanse = true, ability = true, bounce = true,
		power = true, soak = true, scrap = true, scrapPick = true, upload = true,
	}
	local SETS_OWN_SHOT = { attack = true, chant = true, defend = true, spawn = true, play = true, bigMove = true, shot = true, turn = true }

	function animateEvent(e)
		local t = e.type
		if FOLLOW_UPS[t] then
			actionCam.hold(0.55)
		elseif not SETS_OWN_SHOT[t] then
			actionCam.release(0.1)
		end
		if t == "start" then
			for col = 1, COLS do
				for row = 1, ROWS do
					setTileTerrain(col, row, e.terrain and e.terrain[col] and e.terrain[col][row], true)
				end
			end
		elseif t == "turn" then
			introPhase = false
			local side = sideOf(e.player)
			actionCam.release(0)
			actionCam.seat(e.player == view.you and "you" or "opp")
			if e.player == view.you then
				showBanner("YOUR TURN!", 1.4)
			else
				showBanner("OPPONENT'S TURN", 1.2)
			end
			refillEnergy(side, e.energy or 0, e.maxEnergy or 0)
			flashPedestal(side, Color3.fromRGB(255, 230, 140), 0.8)
			step(1.1)
		elseif t == "draw" then
			flyCardFromDeck(sideOf(e.player))
			step(introPhase and 0.12 or 0.4)
		elseif t == "play" then
			local def = CardData.get(e.card)
			local mine = e.player == view.you
			log(who(e.player) .. " played " .. def.name, mine and Color3.fromRGB(180, 230, 255) or Color3.fromRGB(255, 200, 160))
			spendEnergy(sideOf(e.player), e.cost)
			if mine and e.uid then
				cardLife.flyPlayed(e.uid, e.col and tileCFrame(e.col, e.row, e.player).Position or Vector3.new(0, 4.6, 0))
			end
			if not mine then
				bot.leanUntil = clock + 1.2 * PACE
				cardLife.setOppHand(math.max(0, #ui.oppBacks - 1))
				showCardPopup(e.card, 1.6, "top")
				step(1.9)
			elseif def.type == "Spell" then
				showCardPopup(e.card, 1.1, "bottom")
				step(1.3)
			else
				step(0.25)
			end
			if e.combo then
				-- Combo: another card of this family was already played this turn.
				local where = e.col and (tileCFrame(e.col, e.row, e.player).Position + Vector3.new(0, 2.2, 0)) or Vector3.new(0, 7, mine and 2.5 or -2.5)
				floatText(where, "Combo!", familyColor(def.family):Lerp(WHITE, 0.3), true)
				log("Combo! " .. def.name, Color3.fromRGB(255, 215, 120))
			end
			if def.type == "Spell" then
				actionCam.shot(cam.pos:Lerp(cam.look, 0.3), cam.look + Vector3.new(0, 0.5, 0), cam.fov - 4, 0.55)
				castGlow(Vector3.new(0, 6.4, mine and 2.2 or -2.2), def.family == "Any" and Color3.fromRGB(200, 150, 255) or familyColor(def.family))
				actionCam.release(0.6)
			else
				actionCam.release(0.1)
			end
		elseif t == "spawn" and e.raised then
			-- Raise: a lost creature climbs back out of its tile in a purple mist, with 1 health.
			local entry = units[e.uid] or spawnUnit({ uid = e.uid, id = e.card, kind = "creature", owner = e.player, col = e.col, row = e.row })
			local def = CardData.get(e.card)
			local mist = Color3.fromRGB(150, 110, 210)
			actionCam.focus(entry.home.Position, { facing = 1, up = 1.5, dist = 3.6, lookUp = 0.7, fov = 40, seconds = 0.5 })
			log(def.name .. " rises from the dead!", Color3.fromRGB(205, 175, 255))
			if e.hp then
				entry.hp = e.hp
				showStats(entry)
			end
			if entry.label then
				entry.label.gui.Enabled = false
			end
			local fade = summonCircle(entry.home, mist, 0.8)
			smokePuff(entry.home.Position + Vector3.new(0, 0.2, 0), Color3.fromRGB(120, 100, 150))
			local model, home = entry.model, entry.home
			local depth = entry.height + 0.4
			entry.busy = true
			entry.yaw = 0
			model:PivotTo(home * CFrame.new(0, -depth, 0))
			step(0.45)
			animateEntry(entry, 1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
				a = math.min(a, 1)
				local wobble = math.sin(a * math.pi * 5) * 0.12 * (1 - a)
				model:PivotTo(home * CFrame.new(0, -depth * (1 - a), 0) * CFrame.Angles(0, 0, wobble))
			end)
			step(1.3)
			burst(home.Position + Vector3.new(0, 0.4, 0), mist:Lerp(WHITE, 0.3), 14, { speed = 3, gravity = 2 })
			floatText(entryTop(entry), "Back!", mist:Lerp(WHITE, 0.35), false)
			popLabel(entry)
			fade()
			step(0.35)
			actionCam.release(0.4)
		elseif t == "spawn" then
			local entry = units[e.uid] or spawnUnit({ uid = e.uid, id = e.card, kind = "creature", owner = e.player, col = e.col, row = e.row })
			local def = CardData.get(e.card)
			local color = familyColor(def.family)
			local token = def.token == true
			local rare = def.rarity == "Epic" or def.rarity == "Mythic" or def.rarity == "Legendary" or def.rarity == "Secret"
			local big = not token and ((def.cost or 0) >= 4 or rare)
			if big then
				actionCam.focus(entry.home.Position, { facing = 1, up = 1.8, dist = 4.0, lookUp = 0.9, fov = 42, seconds = 0.55 })
			elseif token then
				actionCam.hold(0.6)
			else
				actionCam.release(0.1)
			end
			local fade = summonCircle(entry.home, color, token and 0.75 or 1.0)
			if entry.label then
				entry.label.gui.Enabled = false
			end
			entry.busy = true
			entry.model:PivotTo(entry.home * CFrame.new(0, -(entry.height + 0.4), 0))
			step(token and 0.15 or 0.35)
			local facingCamera = e.player == view.you and not token
			riseUp(entry, token and 0.5 or 0.9, facingCamera)
			step(token and 0.5 or 0.9)
			burst(entry.home.Position + Vector3.new(0, 0.4, 0), color, token and 8 or 12, { speed = 5, gravity = -4 })
			shakeCamera((def.cost or 0) >= 5 and 0.3 or 0.1)
			popLabel(entry)
			fade()
			if facingCamera then
				step(0.35)
				turnToFight(entry, 0.5)
				step(0.5)
			else
				step(0.2)
			end
			if big then
				actionCam.release(0.2)
			end
		elseif t == "build" then
			local entry = units[e.uid] or spawnUnit({ uid = e.uid, id = e.card, kind = "building", owner = e.player, col = e.col, row = e.row })
			local fade = summonCircle(entry.home, Color3.fromRGB(255, 210, 90), 1.0)
			if entry.label then
				entry.label.gui.Enabled = false
			end
			step(0.25)
			riseUp(entry, 0.7, false)
			step(0.7)
			burst(entry.home.Position + Vector3.new(0, 0.4, 0), Color3.fromRGB(255, 230, 150), 8, { speed = 3 })
			shakeCamera(0.06)
			popLabel(entry)
			fade()
			step(0.3)
		elseif t == "move" then
			local entry = units[e.uid]
			if entry and e.path then
				walkPath(entry, e.path)
				step(0.2)
			end
		elseif t == "push" then
			local entry = units[e.uid]
			if entry and e.to then
				floatText(entryTop(entry), "Pushed!", Color3.fromRGB(180, 230, 255), false)
				hopTo(entry, e.to.col, e.to.row, 0.45, 0.8)
				smokePuff(entry.home.Position + Vector3.new(0, 0.3, 0), Color3.fromRGB(220, 230, 240))
				step(0.55)
			end
		elseif t == "defend" then
			-- Defend: it plants its feet and raises its guard (a soft blue shimmer).
			local entry = units[e.uid]
			if entry then
				log(who(e.player) .. ": " .. cardName(entry.cardId) .. " defends", e.player == view.you and Color3.fromRGB(170, 210, 255) or Color3.fromRGB(255, 200, 160))
				actionCam.focus(entry.home.Position, { facing = e.player == view.you and -1 or 1, seconds = 0.5 })
				local model, home = entry.model, entry.home
				local rest = home * CFrame.Angles(0, entry.yaw, 0)
				animateEntry(entry, 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
					a = math.min(a, 1)
					local dip = math.sin(a * math.pi) * 0.06
					model:PivotTo(rest * CFrame.new(0, -0.07 * a - dip, 0) * CFrame.Angles(-0.06 * a, 0, 0))
				end)
				local shell = fxPart(entryMid(entry), 0.6)
				shell.Shape = Enum.PartType.Ball
				shell.Material = Enum.Material.Glass
				shell.Color = Color3.fromRGB(150, 200, 255)
				shell.Transparency = 0.75
				local size = math.max(1.4, entry.height + 0.7)
				TweenService:Create(shell, TweenInfo.new(0.5 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(size, size, size), Transparency = 1 }):Play()
				Debris:AddItem(shell, 0.55 * PACE + 0.05)
				floatText(entryTop(entry), "Guard!", Color3.fromRGB(165, 205, 255), false)
				guardFx.set(entry, true)
				step(0.6)
				actionCam.release(0.35)
			end
		elseif t == "guardDown" then
			local entry = units[e.uid]
			if entry then
				guardFx.set(entry, false)
			end
		elseif t == "blocked" then
			local entry = units[e.uid]
			if entry then
				flashModel(entry.model, Color3.fromRGB(150, 200, 255), 0.35)
				floatText(entryTop(entry), "Blocked!", Color3.fromRGB(170, 215, 255), false)
				step(0.35)
			end
		elseif t == "chant" then
			-- Chant: a glowing circle, a slow twirl with motes rising in its family's color,
			-- then the magic flies to its target (the heal, hit, push or new creature follows).
			local entry = units[e.uid]
			if entry then
				local def = CardData.get(entry.cardId)
				local chant = CardData.Chants[def.family]
				local color = familyColor(def.family)
				local mine = e.player == view.you
				local chantName = chant and chant.name or "a chant"
				log(who(e.player) .. ": " .. def.name .. " chants " .. chantName, mine and Color3.fromRGB(205, 185, 255) or Color3.fromRGB(255, 200, 160))
				spendEnergy(sideOf(e.player), chant and chant.cost or 0)
				if not mine then
					bot.leanUntil = clock + 1.0 * PACE
				end
				actionCam.focus(entry.home.Position, { facing = mine and -1 or 1, dist = 4.6, seconds = 0.55 })
				floatText(entryTop(entry), chantName, color:Lerp(WHITE, 0.45), false)
				local fade = summonCircle(entry.home, color, 0.62)
				local holder = fxPart(entryMid(entry), math.max(0.8, entry.height))
				local motes = Instance.new("ParticleEmitter")
				motes.Rate = 12
				motes.Lifetime = NumberRange.new(0.6, 1.0)
				motes.Speed = NumberRange.new(0.6, 1.4)
				motes.SpreadAngle = Vector2.new(180, 180)
				motes.Acceleration = Vector3.new(0, 2.5, 0)
				motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
				motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
				motes.Color = ColorSequence.new(color:Lerp(WHITE, 0.35))
				motes.LightEmission = 0.35
				motes.Parent = holder
				local model, home = entry.model, entry.home
				local rest = home * CFrame.Angles(0, entry.yaw, 0)
				animateEntry(entry, 0.95, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
					a = math.min(a, 1)
					model:PivotTo(rest * CFrame.new(0, math.sin(a * math.pi) * 0.32, 0) * CFrame.Angles(0, a * math.pi * 2, 0))
				end)
				step(0.95)
				motes.Enabled = false
				Debris:AddItem(holder, 1.2)
				local target = e.target and units[e.target]
				if target then
					local gust = chant and chant.id == "gust"
					actionCam.duel(entry.home.Position, target.home.Position, { seconds = 0.45 })
					projectile(entryMid(entry) + Vector3.new(0, 0.3, 0), entryMid(target), gust and Color3.fromRGB(215, 235, 255) or color, 0.4)
					if gust then
						smokePuff(entryMid(target), Color3.fromRGB(225, 235, 245))
					end
				else
					burst(entryMid(entry), color:Lerp(WHITE, 0.4), 14, { speed = 3, gravity = 3, size = 0.22 })
					step(0.2)
				end
				fade()
				actionCam.release(0.6)
			end
		elseif t == "swap" then
			-- Two of your creatures trade tiles: the one you picked hops over, the other ducks past.
			local a, b = units[e.uid], units[e.other]
			if a and b and e.from and e.to then
				local function trade(entry, col, row, height, side)
					local model = entry.model
					local from = model:GetPivot().Position
					entry.col, entry.row = col, row
					entry.home = tileCFrame(col, row, entry.owner)
					entry.yaw = 0
					local to = entry.home
					local dir = (to.Position - from) * Vector3.new(1, 0, 1)
					local sideways = dir.Magnitude > 0.01 and Vector3.new(0, 1, 0):Cross(dir.Unit) or Vector3.new(1, 0, 0)
					local turn = facing(dir)
					local r0 = model:GetPivot().Rotation
					animateEntry(entry, 0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(k)
						k = math.min(k, 1)
						local arc = math.sin(k * math.pi)
						local pos = from:Lerp(to.Position, k) + Vector3.new(0, arc * height, 0) + sideways * arc * side
						local rot = k < 0.5 and r0:Lerp(turn, k * 2) or turn:Lerp(to.Rotation, (k - 0.5) * 2)
						model:PivotTo(CFrame.new(pos) * rot)
					end)
				end
				trade(a, e.to.col, e.to.row, 0.9, 0.3)
				trade(b, e.from.col, e.from.row, 0.2, -0.3)
				step(0.75)
			end
		elseif t == "bump" then
			-- Gust blew it into something: it jolts back and bounces off.
			local entry = units[e.uid]
			if entry then
				local model, home = entry.model, entry.home
				local rest = (home * CFrame.Angles(0, entry.yaw, 0)).Rotation
				local away = -(home.LookVector * Vector3.new(1, 0, 1))
				if away.Magnitude > 0.01 then
					away = away.Unit
				end
				entry.noRecoilUntil = clock + 0.8 * PACE
				animateEntry(entry, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(k)
					k = math.sin(math.min(k, 1) * math.pi)
					model:PivotTo(CFrame.new(home.Position + away * 0.3 * k) * rest * CFrame.Angles(0.15 * k, 0, 0))
				end)
				impactPuff(home.Position + away * 0.8 + Vector3.new(0, 0.4, 0), 2)
				floatText(entryTop(entry), "Bump!", Color3.fromRGB(200, 225, 255), false)
				step(0.4)
			end
		elseif t == "attack" then
			attackAnimation(e)
		elseif t == "shot" then
			local source = units[e.uid]
			local to
			if e.target == "hero" then
				to = heroMid(sideOf(e.targetPlayer or (source and 3 - source.owner) or 1))
			else
				local target = units[e.target]
				to = target and entryMid(target)
			end
			if source and to then
				local model = source.model
				local home = source.home
				animateEntry(source, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
					setScale(model, source.scale * (1 + 0.12 * math.sin(math.min(a, 1) * math.pi)))
					model:PivotTo(home)
				end)
				actionCam.duel(home.Position, to, { seconds = 0.45 })
				projectile(entryMid(source) + Vector3.new(0, 0.4, 0), to, familyColor(CardData.get(source.cardId).family), 0.45)
				actionCam.punch(2.5)
				actionCam.release(0.45)
			end
		elseif t == "ability" then
			local entry = units[e.uid]
			if entry then
				local model = entry.model
				animateEntry(entry, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
					setScale(model, entry.scale * (1 + 0.15 * math.sin(math.min(a, 1) * math.pi)))
				end)
				burst(entryMid(entry), Color3.fromRGB(255, 240, 170), 8, { speed = 3, gravity = 3 })
				step(0.35)
			end
		elseif t == "damage" then
			local entry = units[e.uid]
			if entry then
				local knocked = clock < (entry.noRecoilUntil or 0)
				hitAnimation(entry, e.amount, Color3.fromRGB(255, 60, 60))
				local text = "-" .. tostring(e.amount)
				if e.zap then
					text ..= " ⚡Zap"
				elseif e.soaked then
					text ..= " 💧"
				end
				floatText(entryTop(entry), text, Color3.fromRGB(255, 105, 95), (e.amount or 0) >= 4)
				if not knocked then
					burst(entryMid(entry), Color3.fromRGB(255, 120, 90), 5, { speed = 4, size = 0.22, glow = 0.15 })
				end
				if e.soaked then
					-- the water splashes off: it's dry again
					burst(entryMid(entry), Color3.fromRGB(120, 180, 255), 6, { speed = 3, gravity = -12, size = 0.15, glow = 0.1 })
					entry.soaked = nil
					renderStatus(entry)
				end
				if e.hp then
					entry.hp = e.hp
					showStats(entry)
				end
				step(0.5)
			end
		elseif t == "heal" then
			local entry = units[e.uid]
			if entry then
				healGlow(entry)
				floatText(entryTop(entry), "+" .. tostring(e.amount), Color3.fromRGB(120, 255, 140), true)
				if e.hp then
					entry.hp = e.hp
					showStats(entry)
				end
				step(0.45)
			end
		elseif t == "buff" then
			local entry = units[e.uid]
			if entry then
				local text = e.keyword or string.format("+%d/+%d", e.atk or 0, e.hp or 0)
				floatText(entryTop(entry), text, Color3.fromRGB(255, 230, 120), false)
				burst(entryMid(entry), Color3.fromRGB(255, 220, 90), 8, { speed = 3, gravity = 5 })
				local model = entry.model
				animateEntry(entry, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
					setScale(model, entry.scale * (1 + 0.18 * math.sin(math.min(a, 1) * math.pi)))
				end)
				step(0.5)
			end
		elseif t == "bubble" then
			local entry = units[e.uid]
			if entry then
				local ball = fxPart(entryMid(entry), entry.height + 1)
				ball.Shape = Enum.PartType.Ball
				ball.Material = Enum.Material.Glass
				ball.Color = Color3.fromRGB(170, 220, 255)
				ball.Transparency = 0.6
				local s = entry.height + 1.4
				TweenService:Create(ball, TweenInfo.new(0.35 * PACE), { Size = Vector3.new(s, s, s), Transparency = 1 }):Play()
				Debris:AddItem(ball, 0.4 * PACE + 0.05)
				floatText(entryTop(entry), "Pop! Blocked", Color3.fromRGB(180, 230, 255), false)
				step(0.45)
			end
		elseif t == "pop" and e.faded then
			local entry = units[e.uid]
			if entry then
				log(cardName(entry.cardId) .. " fades away for good", Color3.fromRGB(205, 175, 255))
				floatText(entryTop(entry), "Gone", Color3.fromRGB(205, 175, 255), false)
			end
			removeUnit(e.uid, false, true)
			step(1.0)
		elseif t == "pop" or t == "destroyed" then
			removeUnit(e.uid)
			step(t == "pop" and 0.8 or 0.55)
		elseif t == "heroDamage" then
			heroHit(sideOf(e.player), e.amount, e.hp)
			log(who(e.player) .. " took " .. e.amount .. " damage", Color3.fromRGB(255, 150, 150))
			step(0.7)
		elseif t == "heroHeal" then
			local side = sideOf(e.player)
			local entry = heroes[side]
			if entry then
				flashModel(entry.model, Color3.fromRGB(120, 255, 140), 0.5)
				floatText(entryTop(entry), "+" .. tostring(e.amount), Color3.fromRGB(120, 255, 140), true)
			end
			flashPedestal(side, Color3.fromRGB(120, 255, 140), 0.6)
			setHeroHp(side, e.hp)
			step(0.5)
		elseif t == "roll" then
			local result = tostring(e.result)
			if CardData.Cards[e.result] then
				result = CardData.Cards[e.result].name
			end
			log("🎲 Roll: " .. result, Color3.fromRGB(255, 230, 120))
			local source = e.source and units[e.source]
			if source then
				floatText(entryTop(source), "🎲 " .. result, Color3.fromRGB(255, 230, 120), false)
			end
			rollDice("🎲 " .. result)
			step(0.6)
		elseif t == "bigMove" then
			local hero = CardData.Heroes[e.hero]
			local side = sideOf(e.player)
			showBanner(hero.name .. ": " .. hero.bigMove .. "!", 1.8)
			log(who(e.player) .. " used " .. hero.bigMove .. "!", Color3.fromRGB(230, 170, 255))
			screenFlash(Color3.fromRGB(200, 120, 255), 0.18, 0.6)
			shakeCamera(0.4)
			flashPedestal(side, Color3.fromRGB(255, 220, 90), 1.4)
			local entry = heroes[side]
			if entry then
				actionCam.focus(entry.home.Position, { facing = side == "Near" and -1 or 1, up = 1.6, dist = 4.6, lookUp = 1.2, fov = 40, seconds = 0.6 })
				local model, home = entry.model, entry.home
				animateEntry(entry, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
					local k = math.sin(math.min(a, 1) * math.pi)
					model:PivotTo(home * CFrame.new(0, 1.4 * k, 0) * CFrame.Angles(0, a * math.pi * 2, 0))
				end)
				burst(home.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 220, 90), 40, { speed = 8 })
			end
			step(1.2)
			actionCam.release(e.col and 0 or 0.5)
			if e.col then
				bowlingBall(e)
			end
		elseif t == "fatigue" then
			log(who(e.player) .. " ran out of cards!", Color3.fromRGB(255, 150, 150))
			local entry = heroes[sideOf(e.player)]
			if entry then
				floatText(entryTop(entry), "Out of cards!", Color3.fromRGB(255, 150, 150), false)
			end
			step(0.5)
		elseif t == "burn" then
			log((e.player == view.you and "Your" or "Opponent's") .. " hand was full, a card burned", Color3.fromRGB(255, 180, 120))
			local deck = deckPiles[sideOf(e.player)]
			burst(Vector3.new(deck.Position.X, topY(deck) + 0.5, deck.Position.Z), Color3.fromRGB(255, 140, 40), 25, { speed = 4, gravity = 6 })
			step(0.4)
		elseif t == "chaos" then
			showBanner("TOTAL CHAOS!", 1.4)
			shakeCamera(0.6)
			screenFlash(Color3.fromRGB(255, 200, 255), 0.15, 0.5)
			for _, mv in ipairs(e.moves or {}) do
				local entry = units[mv.uid]
				if entry then
					hopTo(entry, mv.col, mv.row, 0.8, 3.0)
				end
			end
			step(0.9)
			if e.terrain then
				for col = 1, COLS do
					for row = 1, ROWS do
						setTileTerrain(col, row, e.terrain[col] and e.terrain[col][row], true)
					end
				end
			end
			step(0.6)
		elseif t == "terrain" then
			for _, tile in ipairs(e.tiles or {}) do
				setTileTerrain(tile.col, tile.row, e.terrain, true)
			end
			step(0.7)
		elseif t == "bounce" then
			local entry = units[e.uid]
			if entry then
				units[e.uid] = nil
				local model, start = entry.model, entry.model:GetPivot()
				if entry.label then
					entry.label.gui.Enabled = false
				end
				burst(start.Position + Vector3.new(0, 1, 0), Color3.fromRGB(180, 230, 255), 10, { speed = 5 })
				animateEntry(entry, 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
					model:PivotTo(start * CFrame.new(0, 6 * a, 0) * CFrame.Angles(0, a * math.pi * 3, 0))
					setScale(model, entry.scale * (1 - 0.8 * math.min(a, 1)))
				end)
				Debris:AddItem(model, 0.55 * PACE + 0.1)
				step(0.6)
			end
		elseif t == "cleanse" then
			local entry = units[e.uid]
			if entry then
				flashModel(entry.model, WHITE, 0.6)
				burst(entryMid(entry), WHITE, 10, { speed = 3, gravity = 4 })
				floatText(entryTop(entry), "Cleansed", WHITE, false)
				entry.power = nil
				renderStatus(entry)
				step(0.45)
			end
		elseif t == "power" then
			-- Power: a small gold glint and how much it got (each Power is +1 attack, up to 3).
			local entry = units[e.uid]
			if entry then
				local why = ({ sweet = "Sweet Tooth", grudge = "Grudge", upload = "Upload", charge = "Charge", combo = "Combo" })[e.reason or ""]
				local text = "+" .. tostring(e.amount or 1) .. " ⚡"
				if why then
					text = why .. " " .. text
				end
				floatText(entryTop(entry) + Vector3.new(0, 0.3, 0), text, Color3.fromRGB(255, 215, 90), false)
				burst(entryMid(entry), Color3.fromRGB(255, 215, 90), 6, { speed = 2, gravity = 2.5, size = 0.18, life = 0.6 })
				entry.power = (e.power or 0) > 0 and e.power or nil
				if entry.atk then
					entry.atk += e.amount or 0
					showStats(entry)
				end
				renderStatus(entry)
				step(0.4)
			end
		elseif t == "soak" then
			-- Soaked: a splash of water. Its next hit taken deals 1 more (Zap creatures: 3 more).
			local entry = units[e.uid]
			if entry then
				burst(entryTop(entry) - Vector3.new(0, 0.3, 0), Color3.fromRGB(120, 180, 255), 8, { speed = 2, gravity = -14, size = 0.16, life = 0.5, glow = 0.1 })
				floatText(entryTop(entry), "Soaked 💧", Color3.fromRGB(150, 200, 255), false)
				entry.soaked = true
				renderStatus(entry)
				step(0.35)
			end
		elseif t == "scrap" then
			-- Scrap clatters onto the tile where Junk popped or a building broke.
			scrapFx.set(e.col, e.row, e.total, true)
			local part = tilePart(e.col, e.row)
			if part then
				floatText(Vector3.new(part.Position.X, topY(part) + 1.2, part.Position.Z), "Scrap +" .. tostring(e.added or 1), Color3.fromRGB(215, 200, 170), false)
			end
			step(0.45)
		elseif t == "scrapPick" then
			-- A Junk creature picks up Scrap and bolts it on: +1/+1 for each.
			local entry = units[e.uid]
			if entry then
				for _, f in ipairs(e.from or {}) do
					scrapFx.pick(f.col, f.row, entryMid(entry))
				end
				step(0.35)
				flashModel(entry.model, Color3.fromRGB(255, 220, 140), 0.35)
				floatText(entryTop(entry), string.format("+%d/+%d", e.amount or 1, e.amount or 1), Color3.fromRGB(255, 220, 140), false)
				local model = entry.model
				animateEntry(entry, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
					setScale(model, entry.scale * (1 + 0.1 * math.sin(math.min(a, 1) * math.pi)))
				end)
				entry.atk = e.atk or entry.atk
				entry.maxHp = (entry.maxHp or entry.hp or 0) + (e.amount or 0)
				entry.hp = e.hp or entry.hp
				showStats(entry)
				step(0.4)
			end
		elseif t == "upload" then
			-- Upload: the popped Robo's Power jumps to a friend next to it (the Power follows).
			local to = units[e.to]
			local part = tilePart(e.col, e.row)
			if to and part then
				sparkTo(Vector3.new(part.Position.X, topY(part) + 0.6, part.Position.Z), entryMid(to), Color3.fromRGB(255, 215, 90), 0.4)
				step(0.4)
			end
		elseif t == "endTurn" then
			step(0.2)
		elseif t == "gameOver" then
			local winner = e.winner
			for p = 1, 2 do
				local entry = heroes[sideOf(p)]
				if entry and winner and winner ~= 0 then
					local model, home = entry.model, entry.home
					if p == winner then
						animateEntry(entry, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
							model:PivotTo(home * CFrame.new(0, 1.2 * math.sin(math.min(a, 1) * math.pi), 0))
						end)
					else
						animateEntry(entry, 0.8, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out, function(a)
							model:PivotTo(home * CFrame.Angles(1.45 * math.min(a, 1), 0, 0))
						end)
					end
				end
			end
			step(1.0)
		end
	end
end

-- Make the 3D table match the final state of an update exactly.
local function syncBoard(v)
	for col = 1, COLS do
		for row = 1, ROWS do
			setTileTerrain(col, row, v.terrain[col][row], true)
		end
	end
	local seen = {}
	for _, u in ipairs(v.units) do
		seen[u.uid] = true
		local entry = units[u.uid]
		if not entry then
			entry = spawnUnit(u)
			quickRise(entry)
		elseif entry.col ~= u.col or entry.row ~= u.row then
			hopTo(entry, u.col, u.row, 0.6)
		end
		setStats(entry, u)
	end
	for uid in pairs(units) do
		if not seen[uid] then
			removeUnit(uid)
		end
	end
	scrapFx.sync(v.scrap)
	for p = 1, 2 do
		local side = sideOf(p)
		local pv = v.players[p]
		showEnergy(side, pv.energy, pv.maxEnergy)
		setPile(side, "deck", pv.deckCount)
		setPile(side, "discard", pv.discardCount or 0)
		setHeroHp(side, pv.hp)
	end
end

-- After an update has played: pick the creature that just walked again (so it can attack),
-- or show which creatures can still act.
local function afterUpdate()
	local uid = reselect
	reselect = nil
	if uid and canAct() and units[uid] then
		for _, a in ipairs(view.legal or {}) do
			if a.uid == uid and (a.kind == "attack" or a.kind == "defend" or a.kind == "chant") then
				selectUnit(uid)
				return
			end
		end
	end
	if not pick then
		showReadyGlows()
	end
end

local function showResult(result)
	local text = result == "win" and "YOU WIN!" or (result == "draw" and "IT'S A DRAW" or "YOU LOST")
	showBanner(text, 5)
	turnState = "over"
	if result == "win" then
		confettiBurst()
		screenFlash(Color3.fromRGB(255, 230, 120), 0.4, 1.0)
	elseif result == "loss" then
		screenFlash(Color3.fromRGB(40, 20, 60), 0.5, 1.2)
	end
	glideCamera(CAMS.DuelTable[1], CAMS.DuelTable[2], 3)
end

local queue = {}

local processQueue
do
	local function handleUpdate(payload)
		local firstView = view == nil or payload.started
		view = payload.view
		turnEndsAt = tonumber(view.turnEndsAt) or 0
		if firstView then
			clearBoard()
			clearHand()
			introPhase = true
			setupTable(view)
			showBanner(payload.goesFirst and "YOU GO FIRST!" or "OPPONENT GOES FIRST", 2.0)
			step(1.0)
		end
		for _, e in ipairs(payload.events or {}) do
			local ok, err = pcall(animateEvent, e)
			if not ok then
				if err == ABORT then
					error(ABORT, 0)
				end
				warn("Animation error: " .. tostring(err))
			end
			step(0.08)
		end
		syncBoard(view)
		if payload.notice then
			log(payload.notice, Color3.fromRGB(255, 220, 120))
		end
		if payload.result then
			showResult(payload.result)
		end
	end

	function processQueue()
		if processing then
			return
		end
		processing = true
		local caughtUp = false
		while #queue > 0 do
			local payload = table.remove(queue, 1)
			if payload.kind == "update" then
				playingMatch = matchId
				local ok, err = pcall(handleUpdate, payload)
				if not ok and err ~= ABORT then
					warn("Update error: " .. tostring(err))
				end
				if playingMatch == matchId and mode == "match" then
					busy = false
					if view then
						refreshUI(view)
						caughtUp = true
					end
					-- Tell the server this update has finished playing, so the game can go on.
					if type(payload.seq) == "number" then
						MatchAction:FireServer({ kind = "ack", seq = payload.seq })
					end
				end
			end
		end
		processing = false
		actionCam.release(0.3)
		-- Only once everything has played: light up what you can do next (or re-pick the creature that just walked).
		if caughtUp and mode == "match" and view then
			afterUpdate()
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

local function enterMatch()
	matchId += 1
	mode = "match"
	setStationSigns(false)
	ui.menuUI.Visible = false
	ui.stationPanel.Visible = false
	if ui.collectionUI then
		ui.collectionUI.Visible = false
	end
	highlight.Enabled = false
	ui.matchUI.Visible = true
	turnState = "opp"
	turnEndsAt = 0
	for _, l in ipairs(logLines) do
		l:Destroy()
	end
	logLines = {}
	hideCharacter(true)
	moveCamera("Seat", false, 2.2)
end

local function exitMatch()
	matchId += 1
	mode = "menu"
	setStationSigns(true)
	ui.matchUI.Visible = false
	ui.menuUI.Visible = true
	clearPrompt()
	clearBoard()
	clearHand()
	hidePreview()
	ui.popupHolder:ClearAllChildren()
	ui.dice.Visible = false
	ui.diceResult.Visible = false
	ui.bannerText.Visible = false
	view = nil
	busy = false
	queue = {}
	turnEndsAt = 0
	hideCharacter(false)
	ui.resetNav()
	ui.matchSettings.Visible = false
	moveCamera("Overview", false, 1.6)
end

MatchEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "update" then
		if payload.started then
			enterMatch()
		end
		table.insert(queue, payload)
		task.spawn(processQueue)
	elseif payload.kind == "timer" then
		if mode == "match" then
			turnEndsAt = tonumber(payload.turnEndsAt) or 0
		end
	elseif payload.kind == "error" then
		busy = false
		reselect = nil
		log(tostring(payload.message), Color3.fromRGB(255, 120, 120))
		if view then
			refreshUI(view)
			afterUpdate()
		end
	elseif payload.kind == "ended" then
		exitMatch()
	end
end)


---------------------------------------------------------------------------
-- Mouse / touch in the 3D world
---------------------------------------------------------------------------

-- What is under a point on the screen: { col, row, unit } for a tile (match coordinates),
-- { hero = "Near" | "Far" } for a hero, or nil.
local boardAt
do
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { board, boardFolder }

	function boardAt(x, y, isViewport)
		local ray = isViewport and camera:ViewportPointToRay(x, y) or camera:ScreenPointToRay(x, y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		-- A creature, building or hero model?
		local node = inst
		while node and node.Parent and node.Parent ~= boardFolder and node ~= workspace do
			node = node.Parent
		end
		if node and node.Parent == boardFolder then
			for _, entry in pairs(units) do
				if entry.model == node then
					return { col = entry.col, row = entry.row, unit = entry }
				end
			end
			for side, entry in pairs(heroes) do
				if entry.model == node then
					return { hero = side }
				end
			end
			return nil
		end
		local wc, wr = string.match(inst.Name, "^Tile_(%d+)_(%d+)$")
		if wc then
			local col, row = flip(tonumber(wc), tonumber(wr))
			return { col = col, row = row, unit = unitAt(col, row) }
		end
		local side = string.match(inst.Name, "^Hero_(%a+)$") or string.match(inst.Name, "^HeroGlow_(%a+)$")
		if side then
			return { hero = side }
		end
		return nil
	end

	UserInputService.InputBegan:Connect(function(input, processedByGui)
		if processedByGui then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- Right click lets go of whatever you were aiming.
			if mode == "match" and pick then
				clearPrompt()
			end
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local pos = input.Position
		if mode == "menu" then
			local station = stationAt(Vector2.new(pos.X, pos.Y), true)
			if station then
				selectStation(station.Name)
			end
			return
		end
		if mode ~= "match" then
			return
		end
		local hit = boardAt(pos.X, pos.Y, false)
		if hit then
			onBoardClick(hit)
		elseif pick then
			clearPrompt()
		end
	end)
end

---------------------------------------------------------------------------
-- Every frame: camera, idle animations, room ambience
---------------------------------------------------------------------------

do
	local function idleEntry(entry, amount, dt)
		if entry.busy or not entry.model.Parent then
			return
		end
		local t = clock + entry.phase
		if entry.defending then
			-- defending: crouched a little behind its guard, breathing slowly
			local breathe = math.sin(t * 1.5) * 0.015
			entry.model:PivotTo(entry.home * CFrame.new(0, -0.07 + breathe, 0) * CFrame.Angles(0, entry.yaw, 0) * CFrame.Angles(-0.06, 0, 0))
			return
		end
		if entry.sick then
			-- just summoned (zZ): a slow, sleepy nod
			local nod = math.sin(t * 1.1)
			entry.model:PivotTo(entry.home * CFrame.new(0, (nod + 1) * 0.025, 0) * CFrame.Angles(0, entry.yaw, 0) * CFrame.Angles(-0.06 - 0.04 * nod, 0, 0))
			return
		end
		-- breathing: a slow, small rise and fall (the board stays calm, so actions stand out)
		local bob = (math.sin(t * 1.3) + 1) * 0.02 * amount
		local lean = math.sin(t * 1.3 + 0.9) * 0.014 * amount
		-- once in a while it glances around
		if clock >= (entry.nextLook or 0) then
			entry.nextLook = clock + 6 + math.random() * 8
			entry.lookYaw = (math.random() - 0.5) * 0.5 * amount
		end
		entry.curLook = (entry.curLook or 0) + ((entry.lookYaw or 0) - (entry.curLook or 0)) * math.min(1, (dt or 0.03) * 1.5)
		entry.model:PivotTo(entry.home * CFrame.new(0, bob, 0) * CFrame.Angles(0, entry.yaw + entry.curLook, 0) * CFrame.Angles(lean, 0, 0))
	end

	local function blinkEntry(entry)
		if #entry.lids == 0 or clock < entry.nextBlink then
			return
		end
		entry.nextBlink = clock + 2.2 + math.random() * 3.5
		local lids = entry.lids
		for _, lid in ipairs(lids) do
			lid.Transparency = 0
		end
		task.delay(0.12, function()
			for _, lid in ipairs(lids) do
				if lid.Parent then
					lid.Transparency = 1
				end
			end
		end)
	end

	local function updateBoardLife(dt)
		for _, entry in pairs(units) do
			if entry.kind ~= "building" then
				idleEntry(entry, 1, dt)
			end
			blinkEntry(entry)
		end
		guardFx.update()
		for _, entry in pairs(heroes) do
			idleEntry(entry, 0.6, dt)
			blinkEntry(entry)
		end
		-- Pulsing tile frames while you aim; the tile under the mouse glows brighter.
		local pulse = 0.5 + 0.5 * math.sin(clock * 2.0)
		for wc = 1, COLS do
			for wr = 1, ROWS do
				local g = tileGlow[wc][wr]
				local hovered = g.on and aim.hoverWc == wc and aim.hoverWr == wr
				local tr = g.on and (hovered and 0.2 or (0.4 + 0.1 * pulse)) or 1
				local fillTr = g.on and (hovered and 0.7 or 0.9) or 1
				if g.tr ~= tr then
					g.tr = tr
					for _, bar in ipairs(g.bars) do
						bar.Transparency = tr
					end
				end
				if g.fillTr ~= fillTr then
					g.fillTr = fillTr
					g.fill.Transparency = fillTr
				end
			end
		end
		for _, side in ipairs(SIDES) do
			-- The pedestal of whoever's turn it is glows; it flashes on hits and big moves,
			-- and the enemy's glows red while the creature you picked can hit that hero.
			local glow = heroGlows[side]
			local o = glowOverride[side]
			if o and clock < o.untilTime then
				glow.Color = o.color
				glow.Transparency = 0.3
			elseif side == "Far" and aim.hero then
				glow.Color = Color3.fromRGB(255, 70, 70)
				glow.Transparency = 0.3 + 0.12 * pulse
			elseif view then
				local active = not view.over and sideOf(view.current) == side
				glow.Color = looks[glow].Color
				glow.Transparency = active and 0.5 or 0.88
			end
		end
	end

	-- What the mouse is over: the tile glows brighter, a unit shows its card, a tile shows its terrain.
	local function updateHover()
		aim.hoverWc, aim.hoverWr = nil, nil
		if not view then
			ui.tileTip.Visible = false
			return
		end
		local m = UserInputService:GetMouseLocation()
		local hit = boardAt(m.X, m.Y, true)
		local tip = nil
		if hit and hit.col then
			aim.hoverWc, aim.hoverWr = flip(hit.col, hit.row)
			local fam = view.terrain[hit.col] and view.terrain[hit.col][hit.row]
			if fam then
				tip = (CardData.Terrains[fam] or fam) .. ": " .. fam .. " creatures +1 attack"
			end
			local extra = {}
			local u = hit.unit
			if u and u.power then
				table.insert(extra, "⚡" .. u.power .. " Power: +" .. u.power .. " attack")
			end
			if u and u.soaked then
				table.insert(extra, "💧 Soaked: the next hit deals +1")
			end
			local heaps = scrapFx.count(hit.col, hit.row)
			if heaps > 0 then
				table.insert(extra, "Scrap ×" .. heaps .. ": a Junk creature that steps here gets +" .. heaps .. "/+" .. heaps)
			end
			-- Aiming at an enemy with one of your creatures right behind it: Sandwich!
			local me = pick and pick.kind == "unit" and units[pick.uid]
			if me and u and u.owner ~= view.you and u.kind == "creature" then
				local dc = u.col > me.col and 1 or (u.col < me.col and -1 or 0)
				local dr = u.row > me.row and 1 or (u.row < me.row and -1 or 0)
				local behind = unitAt(u.col + dc, u.row + dr)
				if behind and behind ~= me and behind.owner == view.you and behind.kind == "creature" then
					table.insert(extra, 1, "Sandwich! +1 damage (" .. cardName(behind.cardId) .. " is behind it)")
				end
			end
			if #extra > 0 then
				tip = table.concat(extra, " · ") .. (tip and (" · " .. tip) or "")
			end
			if not ui.handHover then
				if hit.unit then
					showPreview(hit.unit.cardId)
				else
					hidePreview()
				end
			end
		elseif hit and hit.hero then
			local h = heroes[hit.hero]
			local pv = view.players[hit.hero == "Near" and view.you or 3 - view.you]
			local hero = pv and CardData.Heroes[pv.hero]
			if hero then
				tip = hero.name .. " · " .. hero.bigMove .. ": " .. hero.text
			end
			if not ui.handHover then
				hidePreview()
			end
			local _ = h
		elseif not ui.handHover then
			hidePreview()
		end
		if tip and not ui.handHover then
			ui.tileTip.Text = tip
			ui.tileTip.Size = UDim2.fromOffset(math.clamp(utf8.len(tip) * 8, 160, 620), 26)
			ui.tileTip.Position = UDim2.fromOffset(m.X + 18, m.Y + 16)
			ui.tileTip.Visible = true
		else
			ui.tileTip.Visible = false
		end
	end

	local function updateTurnText()
		if turnState == "you" then
			ui.turnText.Text = "Your turn!"
			ui.turnText.TextColor3 = Color3.fromRGB(150, 255, 170)
			if turnEndsAt > 0 then
				local left = math.max(0, math.ceil(turnEndsAt - workspace:GetServerTimeNow()))
				ui.timerText.Text = "⏱ " .. left .. "s"
				ui.timerText.TextColor3 = left <= 10 and Color3.fromRGB(255, 110, 110) or WHITE
			else
				ui.timerText.Text = ""
			end
		elseif turnState == "over" then
			ui.turnText.Text = "Match over"
			ui.turnText.TextColor3 = WHITE
			ui.timerText.Text = ""
		else
			ui.turnText.Text = "Opponent is thinking" .. string.rep(".", math.floor(clock * 2) % 4)
			ui.turnText.TextColor3 = Color3.fromRGB(255, 220, 160)
			ui.timerText.Text = ""
		end
	end

	-- Bot Bonkers (built by the server) rocks gently in its chair and leans in when it plays.
	local function updateBot(dt)
		local model = duelTable:FindFirstChild("BotOpponent")
		if not model then
			bot.model = nil
			return
		end
		if bot.model ~= model then
			bot.model = model
			bot.base = model:GetPivot()
			bot.lean = 0
		end
		local target = clock < bot.leanUntil and 0.22 or (turnState == "opp" and 0.07 or 0)
		bot.lean += (target - bot.lean) * math.min(1, dt * 4)
		local bob = math.sin(clock * 1.6) * 0.04
		model:PivotTo(bot.base * CFrame.new(0, 2.45 + bob, 0) * CFrame.Angles(-bot.lean, 0, 0) * CFrame.new(0, -2.45, 0))
	end

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
			a.disco.CFrame = a.discoBase * CFrame.Angles(0, clock * 0.7, 0)
		end
		if clock >= a.nextColor then
			a.nextColor = clock + 0.15
			for i, tile in ipairs(a.tiles) do
				tile.Color = Color3.fromHSV((i * 0.137 + clock * 0.15) % 1, 0.75, 1)
			end
			local chase = math.floor(clock * 4)
			for i, bulb in ipairs(a.strings) do
				bulb.Transparency = ((chase + i) % 3 == 0) and 0.65 or 0
			end
			for i, pl in ipairs(a.partyLights) do
				local c = Color3.fromHSV((clock * 0.08 + i / 3) % 1, 0.65, 1)
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
		if mode ~= "pack" then
			-- (during a Pack Brawl the cinematic drives the camera)
			updateCamera(dt)
		end
		cardLife.update(dt)
		if mode == "match" then
			cardLife.updateHand(dt)
		end
		if mode == "menu" then
			local mouse = UserInputService:GetMouseLocation()
			local station = stationAt(mouse)
			if station then
				highlight.Adornee = station
				highlight.Enabled = true
			else
				highlight.Enabled = false
			end
		else
			updateTurnText()
			updateHover()
			updateBoardLife(dt)
			updateBot(dt)
			hideTimer += dt
			if hideTimer > 0.5 then
				hideTimer = 0
				hideCharacter(true)
			end
		end
		updateAmbience()
		ui.vignette.Enabled = mode == "match"
	end)
end

moveCamera("Overview", true)

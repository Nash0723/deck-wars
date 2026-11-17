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
local CardLevels = require(Shared:WaitForChild("CardLevels"))
local UIKit = require(Shared:WaitForChild("UIKit")) -- drawn icons, the level badge and Focus (one window at a time)

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
local mode = "title" -- "title", "menu", "match", "pack" (a pack opening, which moves the camera itself), "preview" (trying a match background on)
-- or "park" (walking around the Park as your avatar: Roblox's own camera and controls, see ParkClient)
local clock = 0 -- seconds since the script started (advanced every frame)
local currentStation = nil -- the station whose panel is open
-- While a station's screen is open, its own props in the room stay hoverable and clickable (the
-- rest of the room stays still, and nothing there switches screens): station -> the RoomLife scopes
-- that stay live. The Deck Shelf is left out on purpose: nothing moves while you sort your cards.
local LIVE_PROPS = {
	TrophyWall = { TrophyWall = true }, -- the trophies, pennants and certificate
	PackParty = { PackParty = true, PackShelf = true }, -- the balloons, speakers, disco ball and floor, the jars
	DuelTable = { DuelTable = true }, -- the chairs
	ShopCounter = { ShopCounter = true }, -- Pickles, the register, the candy jar...
	Radio = { Radio = true }, -- the radio (Settings)
}

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
	-- the painting over the fireplace is the Campaign map; the front door leads out to the Park
	-- (both a little to the side, so the station panel on the right doesn't cover them)
	Campaign = { Vector3.new(2.2, 10.6, -13.8), Vector3.new(2.2, 10.9, -23) },
	-- (low and a little to the side, so your avatar leaning by the door shows head to toe, left of the panel)
	ParkDoor = { Vector3.new(-6.0, 5.2, 11.5), Vector3.new(-11.8, 5.0, 23.7) },
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
	-- During a pack opening the opening owns the camera (see PackParty), and in the Park Roblox's
	-- own camera follows your avatar, so leave it alone.
	if mode == "pack" or mode == "park" then
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

-- Keep the camera ours even after the character respawns, and stop walking around
-- (except in the Park, where you walk around with Roblox's own camera and controls).
local function lockPlayer()
	if mode == "park" then
		return
	end
	task.defer(function()
		if mode ~= "park" then
			camera.CameraType = Enum.CameraType.Scriptable
		end
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
	if camera.CameraType ~= Enum.CameraType.Scriptable and mode ~= "park" then
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
-- Every menu in warm wood, cream and honey (the screens were built on a cool purple chrome).
require(Shared:WaitForChild("CozyTheme")).attach(player:WaitForChild("PlayerGui"))

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
		BackgroundColor3 = Color3.fromRGB(48, 33, 24),
		BackgroundTransparency = 0.04,
	}, parent)
	corner(f, 14)
	-- cartoon look: a thick dark outline and a soft warm shade, like polished wood
	make("UIStroke", { Thickness = 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 248, 236), Color3.fromRGB(196, 170, 140)) }, f)
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

	-- The picture in the middle of a card: a small 3D view of the creature, building or spell
	-- (a big icon for a spell that has no 3D model).
	function addCardArt(art, def, calm)
		if def.type == "Spell" and not CreatureBuilder.has(def.id) then
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
-- level: shows the card's level pips on its bottom edge (nil: no pips). boosted: the level's
-- bonus counts here (a match against bots), so the attack / health shown include it, in gold.
local function makeCard(parent, cardId, size, costOverride, calm, level, boosted)
	local compact = calm == "compact"
	local def = CardData.get(cardId)
	local hidden = def.rarity == "Secret" and costOverride == "hidden"
	local famColor = familyColor(def.family)
	local card = make("Frame", {
		Name = "Card",
		Size = size or UDim2.fromOffset(120, 168),
		BackgroundColor3 = famColor:Lerp(WHITE, 0.55),
	}, parent)
	card:SetAttribute("KeepColors", true) -- (the cozy menu colors leave cards alone)
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
	if level then
		UIKit.levelPips(card, level, CardLevels.maxLevel(cardId))
	end
	local lvBonus = (boosted and level and level > 1) and CardLevels.bonus(cardId, level) or { atk = 0, hp = 0, cost = 0 }
	local LEVEL_GOLD = Color3.fromRGB(255, 226, 140)
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
			badge("⚔ " .. (def.atk + lvBonus.atk), Color3.fromRGB(190, 85, 60), 0.06, 0)
			badge("❤ " .. (def.hp + lvBonus.hp), Color3.fromRGB(60, 150, 95), 0.94, 1)
			if lvBonus.atk > 0 or lvBonus.hp > 0 then
				for _, b in ipairs(card:GetChildren()) do
					if b.Name == "Stat" then
						b.TextColor3 = LEVEL_GOLD
					end
				end
			end
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
		local atk, hp = def.atk + lvBonus.atk, def.hp + lvBonus.hp
		local stats = def.type == "Building" and ("❤ " .. hp) or ("⚔ " .. atk .. "   ❤ " .. hp)
		label(card, stats, {
			Name = "Stats",
			Size = UDim2.fromScale(0.9, level and 0.09 or 0.11),
			Position = UDim2.fromScale(0.05, 0.865),
			TextColor3 = (lvBonus.atk > 0 or lvBonus.hp > 0) and Color3.fromRGB(150, 96, 20) or Color3.fromRGB(30, 25, 40),
		})
	end
	return card
end

-- All the on-screen panels, buttons and labels live in this table.
local ui = {}
-- The props that stay live right now ({ [scope] = true } for the open station, see LIVE_PROPS), or
-- nil. Not while a window or a match world is up.
function ui.liveScope()
	if currentStation and LIVE_PROPS[currentStation] and not Backdrops.current() and not UIKit.Focus.anyOpen(ui.stationPanel) then
		return LIVE_PROPS[currentStation]
	end
	return nil
end

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
-- (the room keeps its screen clear: the logo lives on the loading and title screens, so the
-- room's own title is an empty placeholder that the Focus code can still slide about)
ui.menuTitle.Text = ""
ui.menuTitle.Size = UDim2.fromOffset(0, 0)
-- a one-line hint just above the dock; it fades away by itself a few seconds after you arrive
label(ui.menuUI, "Click anything in the room   ·   A / D look around   ·   S goes back", {
	Name = "MenuHint",
	Size = UDim2.fromOffset(520, 18),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -130),
	Font = BODY_FONT,
	TextScaled = false,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(240, 228, 210),
	TextStrokeTransparency = 0.55,
})
-- You: your level and XP, your Gems and Coins, your win streak and today's first-win bonus. The
-- server keeps the real numbers and shows them as attributes on your Player (Level, XP, Gems...).
ui.profile = panel(ui.menuUI, UDim2.fromOffset(356, 72), UDim2.fromOffset(24, 62))
ui.profile.Name = "Profile"
UIKit.rim(ui.profile)
-- the round level badge (UIKit draws it, with the number centered both ways)
ui.levelBadge = UIKit.levelBadge(ui.profile, 48, { Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
ui.xpText = label(ui.profile, "", { Name = "XPText", Size = UDim2.new(1, -184, 0, 18), Position = UDim2.fromOffset(72, 11), Font = UIKit.BOLD_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(230, 226, 246), TextXAlignment = Enum.TextXAlignment.Left })
ui.xpBack = make("Frame", { Name = "XPBar", Size = UDim2.new(1, -184, 0, 8), Position = UDim2.fromOffset(72, 33), BackgroundColor3 = Color3.fromRGB(14, 11, 24) }, ui.profile)
corner(ui.xpBack, 4)
make("UIStroke", { Thickness = 1, Color = Color3.fromRGB(80, 70, 120), Transparency = 0.3 }, ui.xpBack)
ui.xpFill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, ui.xpBack)
corner(ui.xpFill, 4)
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 150, 80)) }, ui.xpFill) -- honey
ui.profileExtra = label(ui.profile, "", { Name = "Extra", Size = UDim2.new(1, -184, 0, 16), Position = UDim2.fromOffset(72, 46), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextColor3 = Color3.fromRGB(255, 204, 136), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
-- Gems (open packs) and Coins (shop items), stacked on the right of the card, each with its icon
-- (Roblox has no 🪙 to draw, so the coin is drawn by UIKit).
do
	local wallet = make("Frame", { Name = "Wallet", Size = UDim2.new(0, 100, 1, -14), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 }, ui.profile)
	make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, wallet)
	local gemsRow
	gemsRow, ui.gemsLabel = UIKit.currency(wallet, "Gems", "", { size = 20, height = 26 })
	gemsRow.LayoutOrder = 1
	local coinsRow
	coinsRow, ui.coinsLabel = UIKit.currency(wallet, "Coins", "", { size = 19, height = 26, iconSize = 18 })
	coinsRow.LayoutOrder = 2
	ui.gemsRow, ui.coinsRow = gemsRow, coinsRow
end
do
	local function refreshProfile()
		local gems = player:GetAttribute("Gems")
		local coins = player:GetAttribute("Coins")
		ui.gemsLabel.Text = if gems then ShopCatalog.format(gems) else ""
		ui.coinsLabel.Text = if coins then ShopCatalog.format(coins) else ""
		ui.gemsRow.Visible = gems ~= nil
		ui.coinsRow.Visible = coins ~= nil
		local level = player:GetAttribute("Level") or 1
		local xp = player:GetAttribute("XP") or 0
		local need = player:GetAttribute("XPNeeded") or Progression.xpForLevel(level)
		UIKit.setLevel(ui.levelBadge, level)
		ui.xpText.Text = "Level " .. level .. "  ·  " .. xp .. " / " .. need .. " XP"
		TweenService:Create(ui.xpFill, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.fromScale(math.clamp(xp / math.max(1, need), 0, 1), 1) }):Play()
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

-- The dock: one slim glass pill at the bottom of the screen. Round icon buttons (the name pops up
-- over the one you point at) around a big gold PLAY in the middle. Settings is the ⚙ up top.
ui.navBar = make("Frame", { Name = "Dock", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 68), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), BackgroundColor3 = Color3.fromRGB(24, 17, 13), BackgroundTransparency = 0.28 }, ui.menuUI)
corner(ui.navBar, 34)
make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(214, 168, 98), Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ui.navBar)
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 240, 220), Color3.fromRGB(150, 130, 120)) }, ui.navBar)
make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, ui.navBar)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, ui.navBar)

ui.STATION_SIZE = UDim2.fromOffset(400, 520)
ui.STATION_POS = UDim2.new(1, -24, 0.5, 14)
ui.stationPanel = panel(ui.menuUI, ui.STATION_SIZE, ui.STATION_POS, Vector2.new(1, 0.5))
ui.stationPanel.Visible = false
ui.stationPanel.Name = "StationPanel"
UIKit.rim(ui.stationPanel)
-- (stations can ask for a taller panel by scale; it never grows past the screen's comfort zone)
make("UISizeConstraint", { MaxSize = Vector2.new(620, 680), MinSize = Vector2.new(320, 360) }, ui.stationPanel)
-- While a station's panel is open on the right, the dock glides left to make room for it.
do
	local function dodge()
		local w = ui.navBar.AbsoluteSize.X
		local shift = 0
		if ui.stationPanel.Visible and w > 0 then
			local pw = ui.stationPanel.AbsoluteSize.X
			shift = ((pw > 0 and pw or 420) + 24) / 2
		end
		local ax = 0.5 + (w > 0 and shift / w or 0)
		TweenService:Create(ui.navBar, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { AnchorPoint = Vector2.new(ax, 1) }):Play()
	end
	ui.stationPanel:GetPropertyChangedSignal("Visible"):Connect(dodge)
	ui.stationPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(dodge)
end
ui.stationTitle = headingStyle(label(ui.stationPanel, "", { Name = "StationTitle", Size = UDim2.new(1, -110, 0, 32), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), TextScaled = false, TextSize = 26, TextColor3 = WHITE }))
-- a thin gold line under the title
do
	local rule = make("Frame", { Name = "TitleRule", Size = UDim2.new(1, -28, 0, 1), Position = UDim2.fromOffset(14, 52), BackgroundColor3 = Color3.fromRGB(255, 214, 120), BorderSizePixel = 0 }, ui.stationPanel)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, rule)
end
ui.stationBody = make("Frame", { Name = "StationBody", Size = UDim2.new(1, -24, 1, -72), Position = UDim2.fromOffset(12, 62), BackgroundTransparency = 1 }, ui.stationPanel)

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
		{ key = "matchLog", kind = "toggle", name = "Match log", tip = "Every play and hit in words, in the corner during matches." },
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
				label(scroll, string.upper(row.head), { Size = UDim2.new(1, -10, 0, 34), TextScaled = false, TextSize = 17, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, LayoutOrder = nextOrder() })
			else
				local key = row.key
				-- each setting sits on its own soft card
				local f = make("Frame", { Name = "Row_" .. key, Size = UDim2.new(1, -10, 0, row.tip and 62 or 42), BackgroundColor3 = Color3.fromRGB(44, 38, 64), BackgroundTransparency = 0.45, LayoutOrder = nextOrder() }, scroll)
				corner(f, 10)
				make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 1) }, f)
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

	-- Open a table for friends (1v1, 2v2, Cup), with one of your own decks or a practice deck.
	-- (Bot matches are in the Campaign.) See LobbyScreen.
	local function showDuelTablePanel()
		clearBody()
		ui.stationTitle.Text = "Duel Table"
		-- a wider, taller panel: deck tiles two by two, and nothing squeezed
		ui.stationPanel.Size = UDim2.new(0, 470, 0.78, 0)
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

	-- The Shop: this panel shows your wallet, level and boosts; its "Open the Shop" button opens the
	-- big Shop window (it doesn't open by itself, so there's one thing on screen at a time).
	local function showShopPanel()
		clearBody()
		ui.stationTitle.Text = "Shop"
		local ShopUI = require(Shared:WaitForChild("ShopUI"))
		ShopUI.stationPanel(ui.stationBody)
	end

	-- Trophies (the wall of cups in the room): the Trophy Road, your level, the daily reward, the first-win bonus and the
	-- achievements, plus a card for the Quest Hall (quests are claimed out in the Park now). Everything here comes from
	-- attributes the server keeps on your Player.
	local function showTrophyPanel()
		local dailyPrizeText = ui.dailyPrizeText
		clearBody()
		ui.stationTitle.Text = "Trophies"
		local body = make("ScrollingFrame", { Name = "TrophyList", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 6 }, ui.stationBody)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
		-- The Trophy Road on top: trophies from every match, rewards and three match backgrounds.
		require(Shared:WaitForChild("TrophyRoadUI")).render(body, 0, { BODY_FONT = BODY_FONT, MenuAction = MenuAction })
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
			make("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(170, 170, 190)) }, fill)
			return fill
		end
		local function heading(text, order)
			label(body, string.upper(text), { Size = UDim2.new(1, -8, 0, 30), TextScaled = false, TextSize = 17, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, LayoutOrder = order })
		end
		-- Level
		local lv = box(1, 60, "LevelBox")
		local lvText = label(lv, "", { Size = UDim2.new(0.6, -10, 0, 24), Position = UDim2.fromOffset(10, 6), TextScaled = false, TextSize = 18, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local lvNext = label(lv, "", { Size = UDim2.new(0.4, -10, 0, 20), Position = UDim2.new(0.6, 0, 0, 8), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Right })
		local lvFill = bar(lv, UDim2.fromOffset(10, 38), UDim2.new(1, -20, 0, 12))
		-- Daily reward
		local daily = box(2, 64, "DailyBox")
		local dText = label(daily, "", { Size = UDim2.new(1, -130, 0, 24), Position = UDim2.fromOffset(10, 6), TextScaled = false, TextSize = 18, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local dSub = label(daily, "", { Size = UDim2.new(1, -130, 0, 20), Position = UDim2.fromOffset(10, 36), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextWrapped = true, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
		local dButton = button(daily, "Claim", READY, function()
			MenuAction:FireServer("ClaimDaily")
		end, { Name = "ClaimDaily", Size = UDim2.fromOffset(104, 40), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextScaled = false, TextSize = 18 })
		-- First win and streak
		local extra = label(body, "", { Name = "Bonuses", Size = UDim2.new(1, -8, 0, 22), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(255, 205, 140), LayoutOrder = 3 })
		-- Quests: they're claimed at the Quest Hall out in the Park (QuestHallUI). Its card here shows today's three and
		-- walks you out there, with a guide light to the hall.
		heading("Quests", 4)
		require(Shared:WaitForChild("QuestHallUI")).summary(body, 5, {
			walk = function()
				require(Shared:WaitForChild("ParkClient")).enter({ guide = true })
			end,
		})
		-- Achievements: one-time goals, claimed once each.
		heading("Achievements", 10)
		local achRows = {}
		for i, a in ipairs(Progression.Achievements) do
			local f = box(10 + i, 60, "Ach_" .. a.id)
			local r = { def = a }
			r.text = label(f, "", { Size = UDim2.new(1, -124, 0, 20), Position = UDim2.fromOffset(10, 5), TextScaled = false, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
			r.sub = label(f, a.text .. ((a.shards or 0) > 0 and ("  ·  also +" .. a.shards .. " Shards") or ""), { Size = UDim2.new(1, -124, 0, 14), Position = UDim2.fromOffset(10, 25), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
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
				dText.Text = "Daily reward: day " .. Progression.dailyWeekDay(day) .. " of 7"
				dSub.Text = "Today: " .. dailyPrizeText(day)
				dButton.Text = "+" .. Progression.dailyReward(day) .. " 💎"
				dButton.Visible = true
			else
				dText.Text = "✓ Daily reward claimed"
				dSub.Text = "Day " .. Progression.dailyWeekDay(day + 1) .. " (" .. dailyPrizeText(day + 1) .. ") in " .. untilReset()
				dButton.Visible = false
			end
			local bits = {}
			bits[1] = player:GetAttribute("FirstWinReady") == true and ("⭐ First win today: +" .. Progression.FirstWinBonus .. " 💎") or "✓ First win bonus done for today"
			local streak = player:GetAttribute("WinStreak") or 0
			if streak >= 1 then
				table.insert(bits, "🔥 Streak " .. streak)
			end
			extra.Text = table.concat(bits, "   ")
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
		-- and at the bottom: take the room tour again
		local list = ui.stationBody:FindFirstChild("SettingsList")
		if list then
			local again = button(list, "🧭  Take the room tour again", Color3.fromRGB(86, 62, 40), function()
				ui.goBack()
				task.delay(0.9, function()
					ui.startTour()
				end)
			end, { Name = "TourAgain", Size = UDim2.new(1, -10, 0, 42), LayoutOrder = 9999, TextScaled = false, TextSize = 17 })
			again.TextColor3 = Color3.fromRGB(255, 236, 200)
			-- the first-time briefs of every menu, back on
			local briefs
			briefs = button(list, "💡  Show menu briefs again", Color3.fromRGB(70, 56, 104), function()
				ui.briefs.resetAll()
				briefs.Text = "✓  Every menu will brief you again"
				Juice.pop(briefs, 1.08, 0.4)
			end, { Name = "BriefsAgain", Size = UDim2.new(1, -10, 0, 42), LayoutOrder = 10000, TextScaled = false, TextSize = 17 })
			briefs.TextColor3 = Color3.fromRGB(255, 236, 200)
		end
	end

	-- The Campaign map over the fireplace (see CampaignUI).
	local function showCampaignPanel()
		clearBody()
		ui.stationTitle.Text = "Campaign"
		require(Shared:WaitForChild("DeckBuilderUI")).request()
		require(Shared:WaitForChild("CampaignUI")).show(ui.stationBody)
	end

	-- The front door: out to the Park, where everyone in the server walks around (see ParkClient).
	local function showParkPanel()
		clearBody()
		ui.stationTitle.Text = "The Park"
		require(Shared:WaitForChild("ParkClient")).doorPanel(ui.stationBody)
	end

	local STATIONS = {
		{ key = "DuelTable", name = "Duel Table", show = showDuelTablePanel },
		{ key = "Campaign", name = "Campaign", show = showCampaignPanel },
		{ key = "DeckShelf", name = "Deck Shelf", show = showDeckShelfPanel },
		{ key = "PackParty", name = "Pack Party", show = showPackPartyPanel },
		{ key = "ShopCounter", name = "Shop", show = showShopPanel },
		{ key = "TrophyWall", name = "Trophies", show = showTrophyPanel },
		{ key = "ParkDoor", name = "Park", show = showParkPanel },
		{ key = "Radio", name = "Settings", show = showSettingsPanel },
	}
	-- A short brief the first time you open each station (MenuBriefs), and a ? to see it again.
	ui.briefs = require(Shared:WaitForChild("MenuBriefs"))
	local stationByKey = {}
	for _, s in ipairs(STATIONS) do
		stationByKey[s.key] = s
	end

	-- The station the camera is at (nil = the overview) has its nav button lit up.
	local navButtons = {}
	local NAV_IDLE = Color3.fromRGB(62, 44, 32)
	local NAV_HERE = Color3.fromRGB(150, 108, 44)
	local NAV_ICONS = { DuelTable = "⚔", Campaign = "🗺", DeckShelf = "📚", PackParty = "🎁", ShopCounter = "🛒", TrophyWall = "🏆", ParkDoor = "🌳", Radio = "⚙" }
	local function markNav()
		for key, b in pairs(navButtons) do
			local here = key == currentStation
			if not b:GetAttribute("KeepColor") then
				b.BackgroundColor3 = here and NAV_HERE or NAV_IDLE
			end
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
		if ui.briefs.current() and ui.briefs.current() ~= key then
			ui.briefs.close()
		end
		currentStation = key
		markNav()
		moveCamera(key)
		ui.stationPanel.Visible = true
		s.show()
		ui.briefs.maybe(key, {
			still = function()
				return mode == "menu" and currentStation == key and ui.stationPanel.Visible
			end,
		})
	end

	local function goBack()
		ui.briefs.cancelPending()
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
	-- a drawn ✕ in the panel's corner goes back to the room, like S or Backspace
	UIKit.closeButton(ui.stationPanel, goBack, { Name = "CloseStation", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -12, 0, 12), AnchorPoint = Vector2.new(1, 0), ZIndex = 5 })
	-- and a ? beside it: this station's brief again
	ui.briefs.helpButton(ui.stationPanel, function()
		return currentStation
	end, { Name = "StationBrief", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -54, 0, 12), AnchorPoint = Vector2.new(1, 0), ZIndex = 5 })

	-- (dock order: PLAY in the middle; Settings has no dock button, it's the ⚙ up top)
	local DOCK = { Campaign = 1, DeckShelf = 2, PackParty = 3, DuelTable = 4, ShopCounter = 5, TrophyWall = 6, ParkDoor = 7 }
	for _, s in ipairs(STATIONS) do
		local order = DOCK[s.key]
		if order then
			local play = s.key == "DuelTable"
			local b = make("TextButton", {
				Name = "Nav" .. s.key,
				LayoutOrder = order,
				Size = play and UDim2.fromOffset(150, 52) or UDim2.fromOffset(50, 50),
				BackgroundColor3 = play and Color3.new(1, 1, 1) or NAV_IDLE,
				AutoButtonColor = false,
				Text = play and "⚔  PLAY" or (NAV_ICONS[s.key] or "?"),
				Font = FONT,
				TextScaled = false,
				TextSize = play and 24 or 24,
				TextColor3 = play and INK or WHITE,
			}, ui.navBar)
			corner(b, play and 26 or 25)
			if play then
				b:SetAttribute("KeepColor", true)
				make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 222, 120), Color3.fromRGB(242, 146, 52)) }, b)
				make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(110, 60, 20), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
				-- a slow shine sweeps across PLAY
				-- (a soft band, not a rotated bar: Roblox doesn't clip rotated frames)
				local shine = make("Frame", { Name = "Shine", Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, -44, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2 }, b)
				make("UIGradient", { Rotation = 0, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) }) }, shine)
				b.ClipsDescendants = true
				task.spawn(function()
					while b.Parent do
						shine.Position = UDim2.new(0, -44, 0, 0)
						TweenService:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Position = UDim2.new(1, 4, 0, 0) }):Play()
						task.wait(4.5)
					end
				end)
			else
				make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(200, 156, 90), Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
				-- the name, popping up over the button while you point at it
				local tip = label(b, s.name, { Name = "Tip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -12), Size = UDim2.fromOffset(110, 26), Font = UIKit.BOLD_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(255, 240, 214), BackgroundColor3 = Color3.fromRGB(24, 17, 13), BackgroundTransparency = 0.15, Visible = false, ZIndex = 6 })
				corner(tip, 13)
				b.MouseEnter:Connect(function()
					tip.Visible = true
				end)
				b.MouseLeave:Connect(function()
					tip.Visible = false
				end)
				local accent = make("Frame", { Name = "Accent", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(255, 214, 102), BorderSizePixel = 0 }, b)
				corner(accent, 2)
			end
			b.Activated:Connect(function()
				selectStation(s.key)
			end)
			Juice.button(b, { grow = play and 1.06 or 1.12 })
			navButtons[s.key] = b
		end
	end
	ui.navButtons = navButtons
	-- A little "!" on Trophies when there's something to collect there (the daily reward, an achievement or a Trophy
	-- Road stop), and a gold count on the Park when quest rewards wait at the Quest Hall.
	do
		local badge = label(navButtons.TrophyWall, "!", { Name = "Badge", Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, 4, 0, -6), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(230, 70, 80), BackgroundTransparency = 0, Visible = false, ZIndex = 5, TextScaled = false, TextSize = 18 })
		corner(badge, 12)
		make("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
		local park = navButtons.ParkDoor
			and label(navButtons.ParkDoor, "", { Name = "QuestBadge", Size = UDim2.fromOffset(34, 20), Position = UDim2.new(1, 8, 0, -6), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(240, 186, 60), BackgroundTransparency = 0, Visible = false, ZIndex = 5, TextScaled = false, TextSize = 14, TextColor3 = INK })
		if park then
			corner(park, 10)
			make("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, park)
		end
		local shown = 0
		local function refreshBadge()
			badge.Visible = player:GetAttribute("DailyReady") == true or (tonumber(player:GetAttribute("TrophiesReady")) or 0) > 0
			if park then
				local n = tonumber(player:GetAttribute("QuestsReady")) or 0
				park.Text = "📜" .. math.min(n, 99)
				park.Visible = n > 0
				if n > shown and park.Parent then
					Juice.pop(park, 1.25, 0.4)
				end
				shown = n
			end
		end
		player.AttributeChanged:Connect(function(name)
			if name == "DailyReady" or name == "TrophiesReady" or name == "QuestsReady" then
				refreshBadge()
			end
		end)
		refreshBadge()
	end
	-- Eight stations: on a narrow screen the whole bar shrinks to fit instead of running off the edges.
	do
		local scale = make("UIScale", { Name = "Fit" }, ui.navBar)
		local function fit()
			local want = ui.navBar.AbsoluteSize.X / math.max(scale.Scale, 0.01) + 24
			local have = ui.menuUI.AbsoluteSize.X
			if want > 24 and have > 0 then
				scale.Scale = math.clamp(have / want, 0.6, 1)
			end
		end
		ui.menuUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		task.defer(fit)
	end

	-- Keyboard / gamepad: A or Left goes to the station before, D or Right to the next one
	-- (in the order of the buttons, wrapping around); S, Down or Backspace go back to the overview.
	local PREV = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.DPadLeft] = true, [Enum.KeyCode.ButtonL1] = true }
	local NEXT = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true, [Enum.KeyCode.DPadRight] = true, [Enum.KeyCode.ButtonR1] = true }
	local BACK = { [Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true, [Enum.KeyCode.Backspace] = true, [Enum.KeyCode.ButtonB] = true }
	-- (the order is read off the screen, left to right, so it always matches the bar you see)
	local function stepStation(dir)
		local order = {}
		for _, s in ipairs(STATIONS) do
			local b = navButtons[s.key]
			if b and b.Visible then
				table.insert(order, { key = s.key, x = b.AbsolutePosition.X })
			end
		end
		if #order == 0 then
			return
		end
		table.sort(order, function(a, b)
			return a.x < b.x
		end)
		local index = nil
		for i, o in ipairs(order) do
			if o.key == currentStation then
				index = i
			end
		end
		if not index then
			index = dir > 0 and 1 or #order
		else
			index = (index - 1 + dir) % #order + 1
		end
		selectStation(order[index].key)
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

-- "+50 💎 + Small Luck Potion": what a streak day pays, in words.
function ui.dailyPrizeText(streakDay)
	local prize = Progression.dailyPrize(streakDay)
	local text = "+" .. prize.gems .. " 💎"
	local potion = prize.potion and ShopCatalog.PotionById and ShopCatalog.PotionById[prize.potion]
	if potion then
		text = text .. " + " .. potion.name
	end
	return text
end

ui.dailyPopup = panel(ui.menuUI, UDim2.fromOffset(600, 300), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))
ui.dailyPopup.Name = "DailyPopup"
ui.dailyPopup.Visible = false
ui.dailyPopup.ZIndex = 45
UIKit.rim(ui.dailyPopup)
headingStyle(label(ui.dailyPopup, "🎁 Daily reward", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 14), TextScaled = false, TextSize = 28, TextColor3 = WHITE }))
ui.dailySub = label(ui.dailyPopup, "", { Name = "Sub", Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 52), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(225, 210, 190) })
ui.dailyTiles = make("Frame", { Name = "Days", Size = UDim2.new(1, -24, 0, 112), Position = UDim2.fromOffset(12, 82), BackgroundTransparency = 1 }, ui.dailyPopup)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }, ui.dailyTiles)
ui.dailyClaim = button(ui.dailyPopup, "Claim", Color3.fromRGB(60, 170, 90), function()
	MenuAction:FireServer("ClaimDaily")
end, { Name = "ClaimDaily", Size = UDim2.fromOffset(220, 50), Position = UDim2.new(0.5, -6, 1, -14), AnchorPoint = Vector2.new(1, 1) })
button(ui.dailyPopup, "Later", Color3.fromRGB(104, 78, 60), function()
	UIKit.close(ui.dailyPopup)
end, { Name = "DailyLater", Size = UDim2.fromOffset(120, 50), Position = UDim2.new(0.5, 6, 1, -14), AnchorPoint = Vector2.new(0, 1) })

-- The week's seven days as tiles: Gems on each, a Luck Potion badge on day 2 and day 7, today
-- lit up and the days already claimed this week ticked.
local function showDailyPopup()
	local day = player:GetAttribute("DailyDay") or 1
	local n = #Progression.DailyWeek
	local today = Progression.dailyWeekDay(day)
	local week = Progression.dailyWeek(day)
	ui.dailySub.Text = (week > 1 and ("Week " .. week .. " · ") or "") .. "Come back every day. Day 2 brings a Small Luck Potion, day 7 a Big one."
	for _, c in ipairs(ui.dailyTiles:GetChildren()) do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	for i = 1, n do
		local prize = Progression.DailyWeek[i]
		local past, now, big = i < today, i == today, i == n
		local tile = make("Frame", { Name = "Day" .. i, Size = UDim2.fromOffset(big and 92 or 72, 110), BackgroundColor3 = now and Color3.fromRGB(122, 82, 44) or (big and Color3.fromRGB(84, 56, 34) or Color3.fromRGB(62, 44, 32)), LayoutOrder = i }, ui.dailyTiles)
		corner(tile, 10)
		if now then
			make("UIStroke", { Thickness = 2.5, Color = Color3.fromRGB(255, 210, 100) }, tile)
		elseif big then
			make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(220, 170, 90), Transparency = 0.3 }, tile)
		end
		label(tile, past and "✓" or ("Day " .. i), { Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 6), TextColor3 = past and Color3.fromRGB(140, 230, 150) or Color3.fromRGB(250, 238, 220) })
		label(tile, "+" .. prize.gems .. " 💎", { Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 38), Font = BODY_FONT, TextColor3 = past and Color3.fromRGB(170, 155, 140) or Color3.fromRGB(130, 220, 255) })
		local potion = prize.potion and ShopCatalog.PotionById and ShopCatalog.PotionById[prize.potion]
		if potion then
			-- a little green badge: 🍀 and how many lucky pulls
			local badge = make("Frame", { Name = "Potion", Size = UDim2.new(1, -10, 0, 30), Position = UDim2.new(0, 5, 1, -36), BackgroundColor3 = past and Color3.fromRGB(70, 84, 62) or Color3.fromRGB(64, 150, 86) }, tile)
			corner(badge, 8)
			label(badge, "🍀 x" .. potion.charges, { Size = UDim2.fromScale(1, 1), Font = UIKit.BOLD_FONT, TextScaled = false, TextSize = 15, TextColor3 = Color3.fromRGB(240, 255, 236) })
		end
	end
	local prize = Progression.dailyPrize(day)
	ui.dailyClaim.Text = "Claim +" .. prize.gems .. " 💎" .. (prize.potion and " + 🍀" or "")
	ui.dailyPopup.Visible = true
end

-- Shown once a visit, in the room, when today's reward is ready. (If you were whisked off before it
-- came up, out to the Park or into a match, it waits for you to be back in the room.)
do
	local shown, waiting = false, false
	local function check()
		if shown or waiting or ui.touring or mode ~= "menu" or player:GetAttribute("DailyReady") ~= true or player:GetAttribute("ProgressLoaded") ~= true then
			return
		end
		waiting = true
		task.delay(1.5, function()
			waiting = false
			if not shown and mode == "menu" and player:GetAttribute("DailyReady") == true then
				shown = true
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
		local coins = (tonumber(payload.coins) or 0) > 0 and ("  +" .. tostring(payload.coins) .. " Coins") or ""
		local potion = payload.potion and ("  +🍀 " .. tostring(payload.potion) .. " (" .. tostring(payload.charges) .. " lucky pulls)") or ""
		local weekDay = Progression.dailyWeekDay(tonumber(payload.day) or 1)
		LobbyScreen.toast("🎁 Day " .. weekDay .. ": +" .. tostring(payload.gems) .. " 💎" .. coins .. potion)
		chime(1)
		if payload.potion then
			Juice.confetti(gui, 0.5, 0.35, weekDay == #Progression.DailyWeek and 60 or 30)
		end
	elseif payload.what == "achievement" then
		local def = Progression.AchievementById[tostring(payload.id)]
		local shards = (tonumber(payload.shards) or 0) > 0 and ("  +" .. tostring(payload.shards) .. " Shards") or ""
		LobbyScreen.toast("🏆 " .. (def and def.name or "Achievement") .. ": +" .. tostring(payload.gems) .. " 💎" .. shards)
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
-- outlined capitals that ran off the edges of the screen). Trophies holds the achievements and the Trophy Road (the
-- quests are out at the Quest Hall in the Park).
do
	local NAMES = { ["PACK PARTY"] = "Pack Party", ["DUEL TABLE"] = "Duel Table", ["SHOP"] = "Shop", ["SETTINGS"] = "Settings", ["DECK SHELF"] = "Deck Shelf", ["TROPHY WALL"] = "Trophies", ["TROPHIES"] = "Trophies", ["PARK"] = "Park", ["CAMPAIGN"] = "Campaign" }
	-- (the server's HubRoom script makes the Campaign and Park stations out of the painting and
	-- the front door; wait a moment for them so their signs get the same look)
	stations:WaitForChild("Campaign", 5)
	stations:WaitForChild("ParkDoor", 5)
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
				text.TextColor3 = main and Color3.fromRGB(255, 226, 140) or Color3.fromRGB(250, 238, 218)
				text.TextStrokeTransparency = 1
				text.BackgroundColor3 = Color3.fromRGB(44, 30, 22)
				text.BackgroundTransparency = 0.3
				corner(text, 10)
				make("UIPadding", { PaddingTop = UDim.new(0.14, 0), PaddingBottom = UDim.new(0.14, 0), PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0) }, text)
				local stroke = make("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(176, 132, 84), Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, text)
				local owner = d
				while owner and owner.Parent ~= stations do
					owner = owner.Parent
				end
				ui.signs = ui.signs or {}
				table.insert(ui.signs, { text = text, stroke = stroke, station = owner, lit = 0 })
				-- (hidden until you point at the station in the room; not on the title screen either)
				text.TextTransparency, text.BackgroundTransparency, stroke.Transparency = 1, 1, 1
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

-- Your avatar in the room: a little decoration by the front door. It leans back against the wall
-- just right of the door, hands in its pockets, one ankle crossed over the other, and it's alive:
-- it breathes, looks around now and then (at you, at the door, across the room, down at its
-- shoes) and taps its foot once in a while. It stands half again as big as usual so it fits the
-- room's big door. Client only (nobody else sees it), and only while you're in the room: it lets
-- go (and shrinks back) the moment you walk out into the Park, and poses again when you're back.
-- The pose is worked out from the avatar's own joints, so any R15 body (or a classic R6 one)
-- stands right against the wall with its feet on the floor. Both kinds of avatar joints work:
-- the classic Motor6Ds and the newer AnimationConstraints (Roblox's upgraded avatar joints).
local leanPose = {}
do
	local WALL_Z = 23.7 -- the room side of the south wall (its wainscot)
	local RAIL = { y0 = 4.8, y1 = 5.4, z = 23.5 } -- the chair rail sticks out a little further
	local SPOT_X = -7.4 -- just right of the door frame (which ends at x = -10.5), under the poster
	local FLOOR_Y = 0
	local SCALE = 1.5 -- (the room is built big: the door is twice as tall as an avatar)
	local YAW = math.rad(-8) -- turned a touch toward the door's camera (the head turns the rest)
	local TILT = math.rad(9) -- leaning back into the wall

	-- where the head looks now and then (degrees: + turns toward the door, + pitch looks up)
	local LOOKS = {
		{ yaw = -4, pitch = 2, hold = { 3, 6 } }, -- at you
		{ yaw = 50, pitch = 0, hold = { 1.6, 3 } }, -- over at the door
		{ yaw = -32, pitch = 4, hold = { 1.6, 3 } }, -- across the room
		{ yaw = -6, pitch = -16, hold = { 1.2, 2.2 } }, -- down at its shoes
		{ yaw = 12, pitch = 14, hold = { 1.2, 2 } }, -- up at the lights
	}

	local S = nil -- { char, root, hum, animate, scale, joints = { [name] = J }, turns = { [J] = CFrame }, target, life }

	-- One joint, whichever kind it is: part0/part1, the joint's frame in each (c0/c1), and how
	-- to turn it (a Motor6D's C0 is turned; an AnimationConstraint's Transform is set each frame).
	local function wrap(j)
		if j:IsA("Motor6D") then
			return { inst = j, kind = "motor", part0 = j.Part0, part1 = j.Part1, c0 = j.C0, c1 = j.C1 }
		elseif j:IsA("AnimationConstraint") and j.Attachment0 and j.Attachment1 then
			return { inst = j, kind = "anim", part0 = j.Attachment0.Parent, part1 = j.Attachment1.Parent, c0 = j.Attachment0.CFrame, c1 = j.Attachment1.CFrame }
		end
		return nil
	end

	local function apply(J, r)
		if J.kind == "motor" then
			J.inst.C0 = J.c0 * r
		else
			J.inst.Transform = r
		end
	end

	local function setTurn(J, r)
		S.turns[J] = r
		apply(J, r)
	end

	-- the rotation that turns direction `from` onto direction `to` (the shortest way round)
	local function aim(from, to)
		from, to = from.Unit, to.Unit
		local d = math.clamp(from:Dot(to), -1, 1)
		if d > 0.99999 then
			return CFrame.new()
		end
		local axis = from:Cross(to)
		axis = axis.Magnitude > 1e-5 and axis.Unit or Vector3.xAxis
		return CFrame.fromAxisAngle(axis, math.acos(d))
	end

	-- Turns a joint so its limb's length (the limb part's own down axis) points along `dir` (in
	-- the parent part's space, as posed so far: `parentRot`). Returns the limb's rotation relative
	-- to that space, for the next joint down the chain. (The limb's own axis, not the line to the
	-- next joint: an R15 shoulder sits at the arm's inner top corner, so that line is slanted.)
	local function point(J, dir, parentRot)
		local dirInParent = parentRot and (parentRot:Inverse() * dir) or dir
		local dirInJoint = J.c0.Rotation:Inverse() * dirInParent
		local bone = J.c1.Rotation:Inverse() * Vector3.new(0, -1, 0)
		local r = aim(bone, dirInJoint)
		setTurn(J, r)
		return (parentRot or CFrame.new()) * J.c0.Rotation * r * J.c1.Rotation:Inverse()
	end

	-- Where every body part sits relative to the root, with the joints as posed.
	local function bodyFrames(char, root)
		local rel = { [root] = CFrame.new() }
		local links = {}
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("Motor6D") or d:IsA("Weld") then
				if d.Part0 and d.Part1 then
					table.insert(links, { d.Part0, d.Part1, d.C0, d.C1 })
				end
			elseif (d:IsA("AnimationConstraint") or d:IsA("RigidConstraint")) and d.Attachment0 and d.Attachment1 then
				local turn = CFrame.new()
				for J, r in pairs(S.turns) do
					if J.inst == d then
						turn = r
					end
				end
				table.insert(links, { d.Attachment0.Parent, d.Attachment1.Parent, d.Attachment0.CFrame * turn, d.Attachment1.CFrame })
			end
		end
		for _ = 1, 12 do -- (a few passes: the joints aren't in any particular order)
			local added = false
			for _, l in ipairs(links) do
				local p0, p1, c0, c1 = l[1], l[2], l[3], l[4]
				if rel[p0] and not rel[p1] then
					rel[p1] = rel[p0] * c0 * c1:Inverse()
					added = true
				elseif rel[p1] and not rel[p0] then
					-- (hats and hair hang the other way round: Part0 is the accessory's handle)
					rel[p0] = rel[p1] * c1 * c0:Inverse()
					added = true
				end
			end
			if not added then
				break
			end
		end
		return rel
	end

	local function corners(cf, size)
		local h = size / 2
		local out = {}
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					table.insert(out, cf * Vector3.new(h.X * x, h.Y * y, h.Z * z))
				end
			end
		end
		return out
	end

	local function wallAt(y)
		if y >= RAIL.y0 and y <= RAIL.y1 then
			return RAIL.z
		end
		return WALL_Z
	end

	local function pose(char)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (hum and root) then
			return false
		end
		local need = hum.RigType == Enum.HumanoidRigType.R15 and { "RightShoulder", "LeftShoulder", "RightHip", "LeftHip", "Neck" } or { "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip", "Neck" }
		for _, n in ipairs(need) do
			local found = false
			for _, d in ipairs(char:GetDescendants()) do
				if d.Name == n and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
					found = true
					break
				end
			end
			if not found then
				return false -- (still loading)
			end
		end
		-- half again as big (before the joints are read: scaling moves their attachments)
		local scale = 1
		pcall(function()
			scale = char:GetScale()
			char:ScaleTo(scale * SCALE)
		end)
		local joints = {}
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
				local J = wrap(d)
				if J and J.part0 and J.part1 then
					joints[d.Name] = J
				end
			end
		end
		local r15 = hum.RigType == Enum.HumanoidRigType.R15
		S = { char = char, root = root, hum = hum, joints = joints, turns = {}, scale = scale }
		-- the avatar's own animations stop while it poses
		local animate = char:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") then
			S.animate = animate
			animate.Enabled = false
		end
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
		for _, J in pairs(joints) do
			setTurn(J, CFrame.new())
		end

		local j = joints
		if r15 then
			-- hands in the pockets: upper arms down and a touch back, forearms forward to the hips
			for _, side in ipairs({ { "Right", 1 }, { "Left", -1 } }) do
				local sh, el = j[side[1] .. "Shoulder"], j[side[1] .. "Elbow"]
				local upperRot = point(sh, Vector3.new(0.04 * side[2], -0.99, 0.1))
				if el then
					point(el, Vector3.new(-0.45 * side[2], -0.84, -0.3), upperRot) -- (hands to the front pockets)
				end
			end
			-- the right ankle crosses over the left, resting on its toes
			local hip, knee, ankle = j.RightHip, j.RightKnee, j.RightAnkle
			local legRot = point(hip, Vector3.new(-0.4, -0.88, -0.22))
			if knee then
				point(knee, Vector3.new(-0.4, -0.88, -0.22), legRot)
			end
			if ankle then
				setTurn(ankle, CFrame.Angles(math.rad(-34), 0, 0)) -- toes down, resting on the floor
			end
			-- the head stays upright (the body leans, the head doesn't) and looks around (see life)
			setTurn(j.Neck, CFrame.Angles(-TILT, math.rad(-4), math.rad(4)))
		else
			-- (a classic body has no elbows: arms hang a touch forward, hands at the hips)
			point(j["Right Shoulder"], Vector3.new(-0.12, -0.97, -0.2))
			point(j["Left Shoulder"], Vector3.new(0.12, -0.97, -0.2))
			point(j["Right Hip"], Vector3.new(-0.22, -0.96, -0.17)) -- (no ankle to rest on: a smaller cross)
		end

		-- Stand it against the wall: the left (standing) foot on the floor, and its back (torso and
		-- arms) against the wall. (The head and hair are left out: they're upright and a little
		-- forward, and the chair rail sticks out at head height.)
		local rot = CFrame.Angles(0, YAW, 0) * CFrame.Angles(TILT, 0, 0)
		local rel = bodyFrames(char, root)
		local foot = char:FindFirstChild(r15 and "LeftFoot" or "Left Leg")
		local lowest = math.huge
		if foot and rel[foot] then
			for _, p in ipairs(corners(rot * rel[foot], foot.Size)) do
				lowest = math.min(lowest, p.Y)
			end
		else
			lowest = -(hum.HipHeight + root.Size.Y / 2)
		end
		local y = FLOOR_Y - lowest
		local headPart = char:FindFirstChild("Head")
		local z = math.huge
		for part, cf in pairs(rel) do
			if part:IsA("BasePart") and part ~= root and part ~= headPart and part.Parent == char and part.Transparency < 1 then
				for _, p in ipairs(corners(rot * cf, part.Size)) do
					z = math.min(z, wallAt(y + p.Y) - 0.03 - p.Z)
				end
			end
		end
		if z == math.huge then
			z = WALL_Z - 1.4
		end
		S.target = CFrame.new(SPOT_X, y, z) * rot
		root.Anchored = true
		root.CFrame = S.target
		S.life = { r15 = r15, yaw = -4, pitch = 2, look = LOOKS[1], nextLook = os.clock() + 3, tapAt = os.clock() + 6, last = os.clock() }
		return true
	end

	-- The little bits of life, on top of the pose: breathing, looking around, a foot tap.
	local function life()
		local L = S.life
		if not (L and L.r15) then
			return
		end
		local now = os.clock()
		local dt = math.clamp(now - L.last, 0, 0.1)
		L.last = now
		if now >= L.nextLook then
			-- every other look is back at you
			local pick = L.look ~= LOOKS[1] and LOOKS[1] or LOOKS[math.random(2, #LOOKS)]
			L.look = pick
			L.nextLook = now + pick.hold[1] + math.random() * (pick.hold[2] - pick.hold[1])
		end
		local k = 1 - math.exp(-dt * 4.5) -- (soft: the head eases there and settles)
		L.yaw += (L.look.yaw - L.yaw) * k
		L.pitch += (L.look.pitch - L.pitch) * k
		local j = S.joints
		if j.Neck then
			S.turns[j.Neck] = CFrame.Angles(-TILT + math.rad(L.pitch), math.rad(L.yaw), math.rad(4 - L.yaw * 0.05))
		end
		-- breathing: the chest rises and falls, slowly
		if j.Waist then
			S.turns[j.Waist] = CFrame.Angles(math.rad(1.3) * math.sin(now * 1.45), 0, 0)
		end
		-- now and then the crossed foot taps twice
		if j.RightAnkle then
			local u = now - L.tapAt
			local tap = 0
			if u >= 0 and u <= 0.8 then
				tap = math.abs(math.sin(u / 0.8 * math.pi * 2)) * 14
			elseif u > 0.8 then
				L.tapAt = now + 7 + math.random() * 8
			end
			S.turns[j.RightAnkle] = CFrame.Angles(math.rad(-34 + tap), 0, 0)
		end
	end

	local function release()
		if not S then
			return
		end
		for J in pairs(S.turns) do
			if J.inst.Parent then
				if J.kind == "motor" then
					J.inst.C0 = J.c0
				else
					J.inst.Transform = CFrame.new()
				end
			end
		end
		-- back to its own size before it's let go
		if S.char.Parent and S.scale then
			local scale = S.scale
			pcall(function()
				S.char:ScaleTo(scale)
			end)
		end
		if S.root.Parent then
			S.root.Anchored = false
		end
		if S.animate and S.animate.Parent then
			S.animate.Enabled = true
		end
		S = nil
	end

	-- hold the pose: the root where it belongs (the server may move it), the joints as posed
	-- (the Animator writes joints during its own step, so this runs again just before physics)
	local function hold()
		if not S then
			return
		end
		if S.root.CFrame ~= S.target then
			S.root.CFrame = S.target
		end
		life()
		for J, r in pairs(S.turns) do
			apply(J, r)
			if J.kind == "motor" and J.inst.Transform ~= CFrame.identity then
				J.inst.Transform = CFrame.identity
			end
		end
	end
	RunService.PreSimulation:Connect(hold)

	local nextTry = 0
	-- every frame: posed while `on`, let go otherwise
	function leanPose.update(on)
		local char = player.Character
		if not on or not char then
			release()
			return
		end
		if S and S.char ~= char then
			S = nil -- (a new character: the old one's joints went with it)
		end
		if not S then
			if clock < nextTry then
				return
			end
			nextTry = clock + 0.5
			if not pose(char) then
				release()
			end
			return
		end
		hold()
	end
	leanPose.release = release
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

-- Match backgrounds: the world you wear (picked at the Deck Shelf, see BackdropPicker) and the
-- ones you own (for "Surprise me") follow the save. Trying one on at the Deck Shelf puts it up
-- around the table and floats the camera through it (mode "preview") until you go back.
-- The Duel Table between matches is IdleTable's lane board at rest.
do
	local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
	local ShopUI = require(Shared:WaitForChild("ShopUI"))
	local BackdropPicker = require(Shared:WaitForChild("BackdropPicker"))
	local IdleTable = require(Shared:WaitForChild("IdleTable"))
	local function packShelf(on)
		pcall(function()
			require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackShelf")).suspend(on)
		end)
	end
	local function wear(eq)
		local c = eq and ShopCatalog.CosmeticById[eq.backdrop or ""]
		Backdrops.choice = (c and c.kind == "backdrop" and c.backdrop) or "Room"
	end
	Cosmetics.onChanged(wear)
	wear(Cosmetics.equipped())
	ShopUI.onSnapshot(function(s)
		local keys = {}
		for _, c in ipairs(ShopCatalog.Cosmetics) do
			if c.kind == "backdrop" and c.backdrop ~= "Random" and c.backdrop ~= "Room" and (c.default or (type(s.owned) == "table" and s.owned[c.id])) then
				keys[c.backdrop] = true
			end
		end
		Backdrops.setOwned(keys)
	end)
	pcall(IdleTable.attach, duelTable)
	ui.idleTable = IdleTable
	-- a match background hides the room; the Pack Shelf stops lighting itself up under it
	ui.pauseShelf = packShelf

	local preview = { token = 0, station = nil }
	function ui.previewBackdrop(key)
		if mode ~= "menu" and mode ~= "preview" then
			return false
		end
		local ok, used = pcall(Backdrops.apply, key, room, duelTable)
		if not ok then
			warn("Background preview failed: " .. tostring(used))
			Backdrops.clear()
			return false
		end
		if mode == "menu" then
			preview.station = currentStation
			mode = "preview"
			ui.menuUI.Visible = false
			ui.topGui.Enabled = false
			setStationSigns(false)
			hideCharacter(true)
			highlight.Enabled = false
			ui.setPointer(false)
		end
		packShelf(Backdrops.current() ~= nil)
		preview.token += 1
		local token = preview.token
		local shot = Backdrops.intro()
		camera.CameraType = Enum.CameraType.Scriptable
		if shot then
			glideCamera(shot.pos, shot.look, 1.6, shot.fov)
			task.delay(1.6 * PACE, function()
				if preview.token == token and mode == "preview" then
					glideCamera(shot.pos + shot.drift * 1.8, shot.look, 18, shot.fov)
				end
			end)
		else
			glideCamera(CAMS.DuelTable[1], CAMS.DuelTable[2], 1.6)
		end
		return true
	end
	function ui.endBackdropPreview()
		if mode ~= "preview" then
			return
		end
		preview.token += 1
		Backdrops.clear()
		packShelf(false)
		mode = "menu"
		ui.menuUI.Visible = true
		ui.topGui.Enabled = true
		setStationSigns(true)
		hideCharacter(false)
		moveCamera(preview.station or "DeckShelf", false, 1.4)
	end
	-- pulled into a match while trying a world on (a party or a Cup): drop the preview quietly
	function ui.cancelBackdropPreview()
		if BackdropPicker.isPreviewing() then
			BackdropPicker.cancel()
		end
		if mode == "preview" then
			mode = "menu"
		end
		preview.token += 1
		ui.topGui.Enabled = true
	end
	BackdropPicker.init({ BODY_FONT = BODY_FONT, preview = ui.previewBackdrop, endPreview = ui.endBackdropPreview })
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

-- Which menu briefs you've seen (MenuBriefs), saved with your other prefs.
ui.briefs.init({
	get = function()
		return prefs.get("SeenBriefs")
	end,
	set = function(list)
		prefs.set("SeenBriefs", list)
	end,
})

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
	FirstWinBonus = Progression.FirstWinBonus,
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
	onEnterMatch = function(payload)
		-- your first match: a small brief in the corner (it blocks nothing; ? has the full rules)
		if ui.briefs.current() then
			ui.briefs.close(true)
		end
		ui.briefs.maybe("Match", {
			place = "match",
			delay = 3,
			still = function()
				return mode == "match"
			end,
		})
		ui.cancelBackdropPreview()
		ui.idleTable.setVisible(false) -- (the match board rises in its place)
		-- Pulled into a match from the Park (a party or a Cup): back inside first.
		local ParkClient = require(Shared:WaitForChild("ParkClient"))
		if ParkClient.isInside() then
			ParkClient.leave(true)
		end
		require(Shared:WaitForChild("CampaignUI")).hide()
		-- The world around the table: a Campaign stage brings its own; otherwise the one you wear
		-- (Deck Shelf > Match background; "Card Den" keeps the room).
		local worldKey = (type(payload) == "table" and type(payload.backdrop) == "string" and Backdrops.ByKey[payload.backdrop]) and payload.backdrop or Backdrops.choice
		local ok, used = pcall(Backdrops.apply, worldKey, room, duelTable)
		if not ok then
			warn("Background failed, keeping the room: " .. tostring(used))
			Backdrops.clear()
			used = "Room"
		end
		ui.pauseShelf(Backdrops.current() ~= nil)
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
		require(Shared:WaitForChild("ShopUI")).close(true)
		ui.matchTop.Visible = true
		hideCharacter(true)
		actionCam.reset()
		if not showIntro(used) then
			moveCamera("Seat", false, 2.2)
		end
	end,
	onCampaignResult = function(c)
		if type(c) == "table" and c.snapshot then
			require(Shared:WaitForChild("CampaignUI")).setSnapshot(c.snapshot)
		end
	end,
	onExitMatch = function(lastMode)
		Backdrops.clear()
		ui.pauseShelf(false)
		ui.idleTable.setVisible(true)
		setStationSigns(true)
		ui.menuUI.Visible = true
		ui.matchTop.Visible = false
		ui.matchSettings.Visible = false
		hideCharacter(false)
		actionCam.reset()
		-- Back at the Duel Table panel, ready for the next game (the same table, after a friends' match),
		-- or at the Campaign map after a Campaign stage.
		currentStation = nil
		selectStation(lastMode == "Campaign" and "Campaign" or "DuelTable")
		LobbyScreen.onMenu()
		if ui.checkDaily then
			ui.checkDaily() -- (today's reward, if a match came up before it could)
		end
	end,
})


-- The Campaign map (the painting over the fireplace) and the Park (out the front door).
require(Shared:WaitForChild("CampaignUI")).init({
	myDecks = ui.myDecks,
	prefs = prefs,
	toast = LobbyScreen.toast,
	panel = ui.stationPanel,
})
require(Shared:WaitForChild("ParkClient")).init({
	getMode = function()
		return mode
	end,
	setMode = function(m)
		mode = m
		if m == "park" then
			-- your avatar lets go of its pose by the door right away, before the server walks it
			-- out (a pose still holding it in place would undo that move)
			leanPose.release()
		elseif m == "menu" and ui.checkDaily then
			ui.checkDaily() -- (today's reward, if it was still waiting)
		end
	end,
	gui = gui,
	topGui = ui.topGui,
	toast = LobbyScreen.toast,
	makeCard = makeCard,
	buildModel = buildModel,
	setScale = setScale,
	hideCharacter = hideCharacter,
	glideCamera = glideCamera,
	moveCamera = moveCamera,
	selectStation = function(key)
		selectStation(key)
	end,
	goBack = function()
		ui.goBack()
	end,
	-- the station panel closes without moving the camera (the door walk-out moves it)
	closeStation = function()
		currentStation = nil
		ui.stationPanel.Visible = false
		for _, b in pairs(ui.navButtons or {}) do
			if not b:GetAttribute("KeepColor") then
				b.BackgroundColor3 = Color3.fromRGB(62, 44, 32)
			end
		end
		require(Shared:WaitForChild("CampaignUI")).hide()
		highlight.Enabled = false
	end,
	menuVisible = function(on)
		ui.menuUI.Visible = on
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

	-- The ⚙ menu keeps three lines: How to play, All settings (speed, sound, the action camera and
	-- the match log are in there) and Leave match.
	ui.leaveButton.LayoutOrder = 9
	ui.camButton = button(ui.menuPanel, "", Color3.fromRGB(70, 66, 100), function()
		Settings.set("actionCam", not actionCam.on) -- (applied below, under "Applying settings")
	end, { Name = "ActionCamButton", Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 5, Visible = false })
	local allSettings = button(ui.menuPanel, "⚙ All settings", Color3.fromRGB(70, 66, 100), function()
		ui.menuPanel.Visible = false
		ui.matchSettings.Visible = true
	end, { Name = "SettingsButton", Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 2, TextScaled = false, TextSize = 19 })
	allSettings.Font = ui.helpButton and ui.helpButton.Font or allSettings.Font

	-- The 💬 emote button (emotes come from the Shop); bubbles pop up over the heroes.
	require(Shared:WaitForChild("ShopUI")).mountEmotes(ui.matchUI, function()
		return MatchScreen.heroPart(true)
	end, function()
		return MatchScreen.heroPart(false)
	end)
end

---------------------------------------------------------------------------
-- Focus: one thing on screen at a time. When a window opens, whatever would crowd it slides out of
-- the way (the title, the profile card, the station panel, the room's signs...), the room behind
-- dims and softly blurs, and the window springs in. Closing it brings everything back. UIKit.Focus
-- follows each window's Visible, so the code that opens and closes them is unchanged.
---------------------------------------------------------------------------
do
	local Focus = UIKit.Focus
	Focus.setup()
	local hint = ui.menuUI:FindFirstChild("MenuHint")
	local titleSlide = Focus.slide(ui.menuTitle, UDim2.fromOffset(0, -170))
	local hintSlide = hint and Focus.slide(hint, UDim2.fromOffset(0, 170))
	Focus.chrome("title", {
		hide = function()
			titleSlide.hide()
			if hintSlide then
				hintSlide.hide()
			end
		end,
		show = function()
			titleSlide.show()
			if hintSlide then
				hintSlide.show()
			end
		end,
	})
	Focus.chrome("profile", Focus.slide(ui.profile, UDim2.fromOffset(-440, 0)))
	Focus.chrome("nav", Focus.slide(ui.navBar, UDim2.fromOffset(0, 130)))
	-- the station panel only moves (other scripts check its Visible)
	Focus.chrome("station", Focus.anchorSlide(ui.stationPanel, Vector2.new(1.2, 0)))
	-- the floating signs over the stations (they're also off during matches and the Park)
	Focus.chrome("signs", {
		hide = function()
			setStationSigns(false)
		end,
		show = function()
			setStationSigns(true)
		end,
		allowed = function()
			return mode == "menu"
		end,
	})

	local WINDOW = { hide = { "title", "profile", "signs", "dev" }, dim = 0.38, blur = 10 }
	-- a station panel: the title and the signs step aside (it slides in by itself)
	Focus.watch(ui.stationPanel, { hide = { "title", "signs" }, animate = false })
	-- the big windows on the left: the Shop, your collection and deck editor, the tournament bracket
	local shopWindow = gui.Parent:FindFirstChild("DeckWarsShop") and gui.Parent.DeckWarsShop:FindFirstChild("ShopWindow")
	if shopWindow then
		Focus.watch(shopWindow, WINDOW)
	end
	local collection = ui.menuUI:FindFirstChild("DeckBuilder")
	if collection then
		Focus.watch(collection, WINDOW)
	end
	Focus.watch(ui.bracketPanel, WINDOW)
	-- the Party panel opens over the station panel, so that one slides away while it's open
	Focus.watch(ui.partyPanel, { hide = { "station", "title", "signs", "dev" }, dim = 0.3, blur = 8 })
	Focus.watch(ui.invitePopup, { animate = true })
	-- the daily reward: everything else steps back
	Focus.watch(ui.dailyPopup, { hide = { "title", "profile", "signs", "station", "nav", "dev" }, dim = 0.5, blur = 14 })
	-- at the table: settings, how to play, the ⚙ menu and the result
	Focus.watch(ui.matchSettings, { dim = 0.42, blur = 8 })
	Focus.watch(ui.helpPanel, { dim = 0.42, blur = 8 })
	Focus.watch(ui.menuPanel, { dim = 0.18 })
	Focus.watch(ui.resultPanel, { dim = 0.35, blur = 6 })
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
		elseif key == "matchLog" then
			MatchScreen.setLog(value)
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
		-- While a screen is open (Pack Party, the Deck Shelf, any window), clicks that miss it don't
		-- reach the room: you switch screens with the buttons at the bottom, never by accident.
		-- The open station's own props still answer clicks (the trophies, the balloons: LIVE_PROPS).
		if currentStation ~= nil or Backdrops.current() ~= nil or UIKit.Focus.anyOpen() then
			if ui.roomLife and ui.liveScope() then
				ui.roomLife.click(pos, true) -- (only that station's props answer: RoomLife.setOnly)
			end
			-- on the Park tab, clicking the (ajar) door itself walks you out to the Park
			if currentStation == "ParkDoor" and not Backdrops.current() and not UIKit.Focus.anyOpen(ui.stationPanel) then
				local hit = stationAt(pos, true)
				if hit and hit.Name == "ParkDoor" then
					require(Shared:WaitForChild("ParkClient")).enter()
				end
			end
			return
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
	-- the Pack Shelf answers the mouse from the room too (its packs peek out), so it's set up now
	local PackShelf = require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackShelf"))
	PackShelf.attach()
	local ParkDoor = require(Shared:WaitForChild("ParkClient")) -- (the front door's hover)
	-- The hover outline goes round a whole station, and two stations reach up to the ceiling: the
	-- Duel Table's hanging lamps, and Pack Party's disco ball, party lights and string lights. On
	-- your screen those ceiling pieces move into their own folder, so hovering a station outlines
	-- just the station (everything that animates them already holds on to the parts; each keeps a
	-- "CeilingOf" attribute naming its station, which Backdrops uses for the lamps' light).
	do
		local CEILING = {
			DuelTable = { TableLamp = true, TableLampCord = true, TableLampRim = true, TableLampShade = true, TableLampTop = true },
			PackParty = { DiscoBall = true, DiscoString = true, LightWire = true, PartyCan = true, PartyLight1 = true, PartyLight2 = true, PartyLight3 = true, StringLight = true },
		}
		local ceiling = room:FindFirstChild("Ceiling") or Instance.new("Folder")
		ceiling.Name = "Ceiling"
		ceiling.Parent = room
		for stationName, names in pairs(CEILING) do
			local st = stations:FindFirstChild(stationName)
			for _, d in ipairs(st and st:GetDescendants() or {}) do
				if d:IsA("BasePart") and names[d.Name] and not (d.Parent and d.Parent:IsA("BasePart")) then
					d:SetAttribute("CeilingOf", stationName)
					d.Parent = ceiling
				end
			end
		end
	end
	local ambience = { tiles = {}, strings = {}, partyLights = {}, nextColor = 0, discoAngle = 0, tileColors = {} }
	do
		local fire = room:FindFirstChild("FireLight", true)
		ambience.firePoint = fire and fire:FindFirstChildOfClass("PointLight")
		ambience.fireBase = ambience.firePoint and ambience.firePoint.Brightness or 3
		ambience.disco = room:FindFirstChild("DiscoBall", true)
		ambience.discoBase = ambience.disco and ambience.disco.CFrame
		ambience.mirrors = {}
		ambience.twinkles = {}
		-- The disco ball: a real mirror ball instead of the old sparkle cloud. Rings of little
		-- mirror tiles on a dark ball, a soft glow inside, and a few narrow beams that turn with
		-- it, so slow spots of light drift round the walls and the floor.
		local ball = ambience.disco
		if ball and not ball:FindFirstChild("MirrorTiles") then
			for _, d in ipairs(ball:GetChildren()) do
				if d:IsA("Sparkles") or d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") then
					d:Destroy()
				end
			end
			ball.Material = Enum.Material.SmoothPlastic
			ball.Color = Color3.fromRGB(58, 56, 62)
			ball.Reflectance = 0
			local r = ball.Size.X / 2
			local holder = Instance.new("Model")
			holder.Name = "MirrorTiles"
			local tile = 0.44
			for ringIndex = -3, 3 do
				local lat = ringIndex * math.rad(22.5)
				local n = math.max(5, math.floor(2 * math.pi * r * math.cos(lat) / (tile + 0.04)))
				for k = 0, n - 1 do
					local lon = (k + (ringIndex % 2) * 0.5) / n * math.pi * 2
					local mirror = Instance.new("Part")
					mirror.Name = "Mirror"
					mirror.Anchored = false
					mirror.Massless = true
					mirror.CanCollide = false
					mirror.CanTouch = false
					mirror.CanQuery = false
					mirror.CastShadow = false
					mirror.Material = Enum.Material.SmoothPlastic
					mirror.Reflectance = 0.5
					local shade = 214 + math.random(-12, 14)
					mirror.Color = Color3.fromRGB(shade, shade, math.min(255, shade + 8))
					mirror.Size = Vector3.new(tile * math.max(0.75, math.min(1, math.cos(lat) * 1.15)), tile, 0.07)
					mirror.CFrame = ball.CFrame * CFrame.Angles(0, lon, 0) * CFrame.Angles(lat, 0, 0) * CFrame.new(0, 0, -(r + 0.01))
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = ball
					weld.Part1 = mirror
					weld.Parent = mirror
					mirror.Parent = holder
					table.insert(ambience.mirrors, { part = mirror, color = mirror.Color })
				end
			end
			holder.Parent = ball.Parent
			local glow = Instance.new("PointLight")
			glow.Name = "MirrorGlow"
			glow.Color = Color3.fromRGB(255, 236, 205)
			glow.Brightness = 0.7
			glow.Range = 9
			glow.Shadows = false
			glow.Parent = ball
			-- narrow beams from the sides (they turn with the ball) and one down onto the dance floor
			local beams = {
				{ Enum.NormalId.Front, Color3.fromRGB(255, 232, 196) },
				{ Enum.NormalId.Back, Color3.fromRGB(255, 214, 190) },
				{ Enum.NormalId.Left, Color3.fromRGB(236, 230, 255) },
				{ Enum.NormalId.Right, Color3.fromRGB(255, 226, 170) },
				{ Enum.NormalId.Bottom, Color3.fromRGB(255, 244, 225) },
			}
			for _, b in ipairs(beams) do
				local spot = Instance.new("SpotLight")
				spot.Name = "MirrorBeam"
				spot.Face = b[1]
				spot.Color = b[2]
				spot.Angle = b[1] == Enum.NormalId.Bottom and 24 or 11
				spot.Brightness = b[1] == Enum.NormalId.Bottom and 0.9 or 1.6
				spot.Range = 40
				spot.Shadows = false
				spot.Parent = ball
			end
		end
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
			a.disco.CFrame = a.discoBase * CFrame.Angles(0, a.discoAngle, 0) -- (the mirror tiles are welded on)
			-- now and then a mirror catches the light: a quick soft glint
			if #a.mirrors > 0 then
				for m, untilT in pairs(a.twinkles) do
					if clock >= untilT then
						a.twinkles[m] = nil
						m.part.Material = Enum.Material.SmoothPlastic
						m.part.Color = m.color
					end
				end
				if math.random() < dt * 5 then
					local m = a.mirrors[math.random(1, #a.mirrors)]
					if not a.twinkles[m] then
						a.twinkles[m] = clock + 0.12 + math.random() * 0.1
						m.part.Material = Enum.Material.Neon
						m.part.Color = Color3.fromRGB(255, 246, 228)
					end
				end
			end
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
				-- warm hues only (rose, peach, amber), drifting slowly
				local c = Color3.fromHSV((0.97 + 0.1 * (0.5 + 0.5 * math.sin(clock * 0.15 + i * 2.1))) % 1, 0.42, 1)
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
		leanPose.update(mode ~= "park") -- your avatar leans by the front door (except out in the Park)
		if mode == "menu" then
			local mouse = UserInputService:GetMouseLocation()
			local station = stationAt(mouse)
			local packHover = ui.onMenuHover and ui.onMenuHover(mouse)
			-- while a station's panel (or any window) is open, nothing in the room gets the hover outline
			local uiOpen = currentStation ~= nil or Backdrops.current() ~= nil or UIKit.Focus.anyOpen() or ui.briefs.isOpen()
			-- ...except the open station's own props (the trophies, the balloons: LIVE_PROPS)
			local liveScope = uiOpen and ui.liveScope() or nil
			RoomLife.setOnly(liveScope)
			-- the front door eases a crack open while you point at it (in the room, or on the Park tab)
			local doorHover = station ~= nil and station.Name == "ParkDoor" and not Backdrops.current()
				and (not uiOpen or (currentStation == "ParkDoor" and not UIKit.Focus.anyOpen(ui.stationPanel)))
			ParkDoor.hoverDoor(doorHover)
			-- the chairs slide out while the Duel Table has the mouse (or its panel is open), and the
			-- packs peek out of the Pack Shelf while the Pack Party corner has it
			RoomLife.setFocus(currentStation or (not uiOpen and station and station.Name) or nil)
			PackShelf.roomHover(not uiOpen and station ~= nil and station.Name == "PackParty")
			-- the props in the room answer the mouse (not while a pack on the shelf has it, and not
			-- while a screen is open: then the room stays still and only the screen reacts)
			local prop = RoomLife.update(dt, (not packHover and (not uiOpen or liveScope ~= nil)) and mouse or nil, Backdrops.current() == nil)
			ui.setPointer(packHover == true or doorHover or (prop ~= nil and (not uiOpen or liveScope ~= nil)) or (not uiOpen and station ~= nil))
			-- the room's signs stay out of sight; the station you point at (or the one the room
			-- tour is showing) has its sign fade in
			local pointed = (not uiOpen and not packHover) and station or nil
			if ui.touring and ui.tourKey then
				pointed = stations:FindFirstChild(ui.tourKey)
			end
			for _, sg in ipairs(ui.signs or {}) do
				local want = (sg.station ~= nil and sg.station == pointed) and 1 or 0
				sg.lit += (want - sg.lit) * math.min(1, dt * 10)
				sg.text.TextTransparency = 1 - sg.lit
				sg.text.BackgroundTransparency = 1 - 0.85 * sg.lit
				sg.stroke.Transparency = 1 - 0.65 * sg.lit
			end
			if packHover or uiOpen then
				highlight.Enabled = false -- (a pack on the shelf lifts up instead; an open panel has the focus)
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
			PackShelf.roomHover(false)
			ParkDoor.hoverDoor(false)
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
		Backdrops.update(dt) -- (the moving parts of a match world)
		ui.idleTable.update(dt)
		if not Backdrops.current() then
			updateAmbience(dt) -- the room is hidden while a match background is up
		end
	end)
end

-- The opening: the title screen over a slow camera push across the room. PLAY flies the camera
-- in from low over the table up to the overview, and the menu pops in piece by piece.
do
	local TitleScreen = require(Shared:WaitForChild("TitleScreen"))
	-- the loading screen (ReplicatedFirst.LoadingScreen) covers the start while everything loads;
	-- the title begins once it's done, so it plays smoothly
	local waited = os.clock()
	while player:GetAttribute("Loaded") ~= true and os.clock() - waited < 45 do
		task.wait(0.1)
	end
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
			Juice.popIn(ui.profile, 0.2, { twist = 0, sound = false })
			local hint = ui.menuUI:FindFirstChild("MenuHint")
			if hint then
				hint.TextTransparency = 1
				TweenService:Create(hint, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
				task.delay(9, function()
					TweenService:Create(hint, TweenInfo.new(1.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end)
			end
			for _, b in ipairs(ui.navBar:GetChildren()) do
				if b:IsA("GuiButton") then
					Juice.popIn(b, 0.35 + b.LayoutOrder % 20 * 0.06, { twist = 0, pitch = 0.9 + (b.LayoutOrder % 20) * 0.05 })
				end
			end
			-- The first time you play: a short brief of the room (not a tour: every menu then briefs
			-- you itself the first time you open it). The daily reward waits until it's put away;
			-- your saved settings, which say whether you've seen it, arrive with your progress.
			ui.touring = prefs.get("SeenTour") ~= true
			task.spawn(function()
				local waited = os.clock()
				while player:GetAttribute("ProgressLoaded") ~= true and os.clock() - waited < 6 do
					task.wait(0.2)
				end
				task.wait(1.4)
				if prefs.get("SeenTour") == true or ui.briefs.seen("Room") or mode ~= "menu" or currentStation ~= nil then
					ui.touring = false
					if ui.checkDaily then
						ui.checkDaily()
					end
					return
				end
				ui.briefs.show("Room", {
					place = "center",
					firstTime = true,
					onClose = function()
						ui.touring = false
						prefs.set("SeenTour", true)
						-- the daily reward comes up once you're back in the room (not over a station)
						task.wait(0.8)
						while mode == "menu" and currentStation ~= nil do
							task.wait(0.5)
						end
						if ui.checkDaily then
							ui.checkDaily()
						end
					end,
				})
			end)
			if not ui.touring and ui.checkDaily then
				ui.checkDaily()
			end
		end,
	})
end

-- The room tour (RoomTour): the camera visits each station while a card explains it, and a gold
-- ring pulses round that station's button in the dock. Also from Settings > Room tour.
function ui.startTour()
	local RoomTour = require(Shared:WaitForChild("RoomTour"))
	if RoomTour.running() or mode ~= "menu" then
		return
	end
	ui.touring = true
	local hint = ui.menuUI:FindFirstChild("MenuHint")
	if hint then
		hint.TextTransparency = 1
		hint.TextStrokeTransparency = 1
	end
	RoomTour.start({
		parent = ui.menuUI,
		focus = function(key)
			ui.tourKey = key
			moveCamera(key, false, 1.1)
		end,
		dockButton = function(key)
			return ui.navButtons and ui.navButtons[key]
		end,
		busy = function()
			return mode ~= "menu" or currentStation ~= nil or UIKit.Focus.anyOpen()
		end,
		sound = function(name, pitch, volume)
			Juice.sound(name, pitch, volume)
		end,
		onFinish = function(startCampaign)
			ui.touring = false
			prefs.set("SeenTour", true)
			if mode == "menu" and currentStation == nil then
				if startCampaign then
					selectStation("Campaign")
				else
					moveCamera("Overview")
				end
			end
			-- the daily reward comes up once you're back in the room (not over the Campaign map)
			task.spawn(function()
				task.wait(0.8)
				while mode == "menu" and currentStation ~= nil do
					task.wait(0.5)
				end
				if ui.checkDaily then
					ui.checkDaily()
				end
			end)
		end,
	})
end

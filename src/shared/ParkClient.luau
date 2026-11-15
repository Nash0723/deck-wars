-- The Park on your screen: walking out of the room's front door into the shared park, your
-- avatar with Roblox's own camera and controls, nameplates and companions over everyone, the Top
-- Collector's cards and plaque, the Pull Altar (opens packs right there), the Trading Post (trade
-- cards with another player: the screens are in TradeUI), the Hall of Pulls, the
-- leaderboards, the big-pull banners (those show in the room too) and the park's life: ducks,
-- ripples, swaying willows, butterflies, songbirds and pollen in the sun. Client only.
--
--   ParkClient.init(ctx)        once, from DeckWarsClient (ctx: see the bottom of DeckWarsClient)
--   ParkClient.doorPanel(body)  the front door station's panel (who's out there, "Walk out")
--   ParkClient.enter() / ParkClient.leave(instant, thenStation)
--   ParkClient.isInside()
--
-- The server (ParkServer) picks the Top Collector and owns your companion and title; this only
-- shows its attributes and events. The place itself is Workspace.Park (see ParkBuilder for the names it uses).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local Park = require(here:WaitForChild("Park"))
local CardData = require(here:WaitForChild("CardData"))
local Juice = require(here:WaitForChild("Juice"))
local UIKit = require(here:WaitForChild("UIKit")) -- the drawn close ✕ and Focus
local Settings = require(here:WaitForChild("Settings")) -- (Graphics: Low turns the park's shadows off)
local TradeUI = require(here:WaitForChild("TradeUI")) -- (trading cards at the Trading Post)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild("ParkRemotes")
local ParkAction = remotes:WaitForChild("ParkAction")
local ParkEvent = remotes:WaitForChild("ParkEvent")

local rgb, make = Juice.rgb, Juice.make
local INK = rgb(18, 14, 28)
local PANEL = rgb(30, 25, 46)
local TILE = rgb(42, 36, 62)
local GOLD = rgb(255, 214, 102)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(170, 164, 190)
local GOOD = rgb(70, 190, 110)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium

local function rarityColor(rarity)
	local c = CardData.RarityColors[rarity]
	return c and rgb(c[1], c[2], c[3]) or TEXT
end

local ParkClient = {}

local S = {
	ctx = nil,
	inside = false,
	busy = false, -- walking in or out
	gui = nil, -- the Park's own ScreenGui (HUD, "My look" editor, pack panel)
	banners = nil, -- the banner ScreenGui (also used in the room)
	hall = {},
	boards = {},
	state = nil, -- the "state" event (your cards, companion, titles)
	savedLight = nil,
	plates = {}, -- [player] = BillboardGui
	pets = {}, -- [player] = { model, id, pos }
	topDrawn = nil, -- what the Top Collector's stand shows now
	editor = nil,
	packPanel = nil,
}

local function corner(p, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end

local function stroke(p, color, t)
	return make("UIStroke", { Color = color or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent, str, props)
	local t = make("TextLabel", { BackgroundTransparency = 1, Text = str, Font = BODY_FONT, TextSize = 14, TextColor3 = TEXT, TextWrapped = true, Size = UDim2.new(1, 0, 0, 18) }, parent)
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	return t
end

local function button(parent, str, color, onClick, props)
	local b = make("TextButton", { AutoButtonColor = false, BackgroundColor3 = color, Text = str, Font = TITLE_FONT, TextSize = 17, TextColor3 = TEXT, Size = UDim2.fromOffset(120, 40) }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 10)
	stroke(b, INK, 2)
	Juice.button(b)
	b.Activated:Connect(onClick)
	return b
end

local function toast(msg)
	if S.ctx and S.ctx.toast then
		S.ctx.toast(msg)
	end
end

local function parkModel()
	return workspace:FindFirstChild("Park")
end

---------------------------------------------------------------------------
-- Light: out here the park keeps the real time of day where the server is (Park.sky has the
-- moods, applySky below puts them on); back inside the room gets its own light back. On the way
-- out everything the park changes is saved, and on the way back it's all put back.
---------------------------------------------------------------------------

local LIGHT_KEYS = { "ClockTime", "GeographicLatitude", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation", "GlobalShadows" }
local EFFECT_KEYS = {
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	ColorCorrectionEffect = { "Saturation", "Contrast", "TintColor", "Brightness" },
	SunRaysEffect = { "Intensity", "Spread", "Enabled" },
	Sky = { "StarCount", "MoonAngularSize", "SunAngularSize", "CelestialBodiesShown" },
	Clouds = { "Cover", "Density", "Color", "Enabled" },
}

-- The park's own sounds: birdsong by day, crickets after dark, water lapping at the pond and the
-- campfire's crackle. They follow the Sound setting, and stop when you go home.
local AMBIENCE = {
	birds = { id = 9116971178, volume = 0.3 },
	crickets = { id = 9112764040, volume = 0.28 },
	water = { id = 9120571336, volume = 0.5, at = "Altar", range = 70 },
	fire = { id = 90029322038324, volume = 0.7, at = "Campfire", range = 45 },
}

local function stopAmbience()
	for _, s in pairs(S.ambience or {}) do
		s:Destroy()
	end
	S.ambience = nil
end

local function updateAmbience(root, dark)
	if not S.ambience then
		S.ambience = {}
		for name, def in pairs(AMBIENCE) do
			local holder = game:GetService("SoundService")
			if def.at then
				local m = root:FindFirstChild(def.at)
				holder = m and (m:FindFirstChild("FireLight", true) or m:FindFirstChildWhichIsA("BasePart", true))
			end
			if holder then
				local s = Instance.new("Sound")
				s.Name = "Park_" .. name
				s.SoundId = "rbxassetid://" .. def.id
				s.Looped = true
				s.Volume = 0
				if def.at then
					s.RollOffMode = Enum.RollOffMode.InverseTapered
					s.RollOffMinDistance = 10
					s.RollOffMaxDistance = def.range
				end
				s.Parent = holder
				s:Play()
				S.ambience[name] = s
			end
		end
	end
	local loud = Settings.volume("sfx")
	for name, s in pairs(S.ambience) do
		local mix = (name == "birds" and 1 - dark) or (name == "crickets" and dark) or 1
		s.Volume = AMBIENCE[name].volume * mix * loud
	end
end

-- The park's own shadow-casting lights (the campfire's, the Hall's spot): on or off with the
-- player's Graphics setting, like the room's lamps.
local function parkShadows(on)
	local root = parkModel()
	if not root then
		return
	end
	if not S.shadowLights or S.shadowRoot ~= root then
		S.shadowRoot = root
		S.shadowLights = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Light") and d.Shadows then
				table.insert(S.shadowLights, d)
			end
		end
	end
	for _, l in ipairs(S.shadowLights) do
		if l.Parent then
			l.Shadows = on
		end
	end
end

local function swapLight(on)
	if on and not S.savedLight then
		-- (Settings > Graphics: Low means no shadows and no sun rays out here either)
		local low = Settings.get("graphics") == "Low"
		local saved = { props = {}, effects = {}, made = {}, fx = {} }
		for _, k in ipairs(LIGHT_KEYS) do
			pcall(function()
				saved.props[k] = Lighting[k]
			end)
		end
		-- the park's effects: the ones the room has are borrowed (and put back), the rest are made
		local function effect(className, parent, name)
			local inst = parent:FindFirstChildOfClass(className)
			if inst then
				local keep = {}
				for _, k in ipairs(EFFECT_KEYS[className] or {}) do
					pcall(function()
						keep[k] = inst[k]
					end)
				end
				saved.effects[inst] = keep
			else
				inst = make(className, { Name = name }, parent)
				table.insert(saved.made, inst)
			end
			saved.fx[className] = inst
			return inst
		end
		effect("Atmosphere", Lighting, "ParkAtmosphere")
		effect("ColorCorrectionEffect", Lighting, "ParkColor")
		local rays = effect("SunRaysEffect", Lighting, "ParkSunRays")
		if low then
			rays.Enabled = false
		end
		local sky = effect("Sky", Lighting, "ParkSky")
		pcall(function()
			sky.StarCount = 3000
			sky.MoonAngularSize = 14 -- (a big, friendly moon)
			sky.SunAngularSize = 16
			sky.CelestialBodiesShown = true
		end)
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		if terrain then
			pcall(function()
				effect("Clouds", terrain, "ParkClouds").Enabled = true
			end)
		end
		local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if dof then
			saved.effects[dof] = { FarIntensity = dof.FarIntensity }
			dof.FarIntensity = 0.05
		end
		pcall(function()
			Lighting.GlobalShadows = not low
		end)
		parkShadows(not low)
		S.savedLight = saved
		S.skyTimer = 0 -- (put the sky on right away)
	elseif not on and S.savedLight then
		local saved = S.savedLight
		S.savedLight = nil
		stopAmbience()
		for k, v in pairs(saved.props) do
			pcall(function()
				Lighting[k] = v
			end)
		end
		for inst, props in pairs(saved.effects) do
			for k, v in pairs(props) do
				pcall(function()
					inst[k] = v
				end)
			end
		end
		for _, inst in ipairs(saved.made) do
			inst:Destroy()
		end
	end
end

---------------------------------------------------------------------------
-- Fades and the front door
---------------------------------------------------------------------------

local function fade(to, seconds)
	local f = S.fader
	if not f then
		return
	end
	f.Visible = true
	local tw = TweenService:Create(f, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { BackgroundTransparency = to })
	tw:Play()
	tw.Completed:Wait()
	if to >= 1 then
		f.Visible = false
	end
end

-- Behind the front door there's only the room's wall. So, on your screen, the wall gets a doorway
-- cut into it right behind the door (the cut hides behind the door frame) with a black room behind
-- it: the door swings out into real darkness instead of through the wall, whether it's just ajar
-- (hover) or wide open (walking out). Built the first time the door moves.
local function worldBox(p, cf)
	cf = cf or p.CFrame
	local h = p.Size / 2
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local c = cf * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
				lo, hi = lo:Min(c), hi:Max(c)
			end
		end
	end
	return lo, hi
end

local function doorVoid()
	if S.void and S.void.Parent then
		return S.void
	end
	local room = workspace:FindFirstChild("MenuRoom")
	local st = room and room:FindFirstChild("Stations")
	local door = st and st:FindFirstChild("ParkDoor")
	local main = door and door:FindFirstChild("Door")
	if not main then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "DoorVoid"
	local function black(name, lo, hi)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon -- (neon black ignores the room's lights: a true black)
		p.Color = Color3.new(0, 0, 0)
		p.Size = hi - lo
		p.CFrame = CFrame.new((lo + hi) / 2)
		p.Parent = model
	end
	-- (measured from the door shut, even if it has started to move)
	local rest = S.doorHinge and S.doorParts and S.doorParts[main] and S.doorHinge * S.doorParts[main] or main.CFrame
	local dLo, dHi = worldBox(main, rest)
	local wall = room:FindFirstChild("WallSouth", true)
	local wLo, wHi
	if wall then
		wLo, wHi = worldBox(wall)
	end
	local square = wall ~= nil and math.abs(wall.CFrame.RightVector.X) > 0.999 and math.abs(wall.CFrame.UpVector.Y) > 0.999
	if square and wLo.Z >= dHi.Z - 0.1 and wLo.X < dLo.X and wHi.X > dHi.X then
		-- the doorway in the wall (your screen only): the wall is swapped for three pieces around it
		local cutL, cutR, cutTop = dLo.X - 0.5, dHi.X + 0.1, dHi.Y + 0.1
		local function piece(name, lo, hi)
			local p = wall:Clone()
			p.Name = name
			p.Size = hi - lo
			p.CFrame = CFrame.new((lo + hi) / 2)
			p.Parent = wall.Parent
		end
		piece("WallSouthLeft", wLo, Vector3.new(cutL, wHi.Y, wHi.Z))
		piece("WallSouthRight", Vector3.new(cutR, wLo.Y, wLo.Z), wHi)
		piece("WallSouthTop", Vector3.new(cutL, cutTop, wLo.Z), Vector3.new(cutR, wHi.Y, wHi.Z))
		wall.Transparency = 1
		wall.CastShadow = false
		wall.CanQuery = false
		-- black linings on the cut's sides and top, then a deep black room behind the wall, wide
		-- and deep enough for the door to swing all the way open inside it
		local z0, z1 = wLo.Z, wHi.Z
		black("LiningL", Vector3.new(cutL, wLo.Y, z0), Vector3.new(cutL + 0.04, cutTop, z1))
		black("LiningR", Vector3.new(cutR - 0.04, wLo.Y, z0), Vector3.new(cutR, cutTop, z1))
		black("LiningTop", Vector3.new(cutL, cutTop - 0.04, z0), Vector3.new(cutR, cutTop, z1))
		local depth = (dHi.X - dLo.X) + 1.2
		local bL, bR = cutL - 1.2, cutR + 0.4
		black("Back", Vector3.new(bL, wLo.Y - 0.3, z1 + depth), Vector3.new(bR, cutTop + 0.6, z1 + depth + 0.2))
		black("SideL", Vector3.new(bL - 0.2, wLo.Y - 0.3, z1), Vector3.new(bL, cutTop + 0.6, z1 + depth))
		black("SideR", Vector3.new(bR, wLo.Y - 0.3, z1), Vector3.new(bR + 0.2, cutTop + 0.6, z1 + depth))
		black("Top", Vector3.new(bL, cutTop + 0.4, z1), Vector3.new(bR, cutTop + 0.6, z1 + depth))
		black("Floor", Vector3.new(bL, wLo.Y - 0.3, z0), Vector3.new(bR, wLo.Y - 0.1, z1 + depth))
	else
		-- (a room built differently: a thin black panel just behind the door, as before)
		local flat = Vector3.new(main.Position.X, 0, main.Position.Z)
		local out = main.CFrame.LookVector
		if out:Dot(flat) < 0 then
			out = -out
		end
		local p = Instance.new("Part")
		p.Name = "Panel"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.new(0, 0, 0)
		p.Size = Vector3.new(main.Size.X + 0.2, main.Size.Y + 0.2, 0.04)
		p.CFrame = CFrame.new(main.Position + out * (main.Size.Z / 2 + 0.05)) * main.CFrame.Rotation
		p.Parent = model
	end
	model.Parent = door
	S.void = model
	return model
end

-- The front door on its hinge: its moving parts, measured once from the shut door (local only).
local function doorRig()
	if S.doorHinge then
		return S.doorHinge
	end
	local room = workspace:FindFirstChild("MenuRoom")
	local st = room and room:FindFirstChild("Stations")
	local door = st and st:FindFirstChild("ParkDoor")
	local main = door and door:FindFirstChild("Door")
	if not main then
		return nil
	end
	S.doorParts = {}
	-- (the knob is on the other side; the hinge sits on the face the door swings toward, so the
	-- door's back corner turns away from the frame instead of cutting into it)
	S.doorHinge = main.CFrame * CFrame.new(-main.Size.X / 2, 0, main.Size.Z / 2)
	for _, p in ipairs(door:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == "Door" or p.Name == "DoorPanel" or p.Name == "DoorKnob" or p.Name == "DoorKnobPlate") then
			S.doorParts[p] = S.doorHinge:ToObjectSpace(p.CFrame)
		end
	end
	return S.doorHinge
end

local function poseDoor(angle)
	local hinge = S.doorHinge
	for p, rel in pairs(S.doorParts) do
		p.CFrame = hinge * CFrame.Angles(0, angle, 0) * rel
	end
	S.doorAngle = angle
end

-- The front door swings open on its hinge (local only), then closes behind you.
local function swingDoor(open, seconds)
	if not doorRig() then
		return
	end
	S.swinging = true
	local angle = open and math.rad(-90) or 0 -- (square to the wall: any further and it would bite the frame)
	local start = time()
	local from = S.doorAngle or 0
	while true do
		local a = math.clamp((time() - start) / seconds, 0, 1)
		local e = a * a * (3 - 2 * a)
		poseDoor(from + (angle - from) * e)
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	S.doorAngle = angle
	S.swinging = false
end

-- Hovering the front door (from the room, or with the Park tab open) eases it a crack open, the
-- dark doorway showing in the gap, and it settles shut again when the mouse leaves. Minimal on
-- purpose: about 14 degrees, a soft spring, a whisper of a sound. DeckWarsClient calls
-- ParkClient.hoverDoor(on) every frame in the room. It opens outward, the same way it opens when
-- you walk out, into the dark doorway behind it (doorVoid).
local DOOR_AJAR = math.rad(-14)
S.doorHover = false
S.doorAjar = 0 -- 0 shut .. 1 ajar
function ParkClient.hoverDoor(on)
	on = on == true
	if on and not S.doorHover and not S.inside and not S.busy then
		Juice.sound("whooshShort", 0.7, 0.06)
	end
	S.doorHover = on
end

local function updateDoorHover(dt)
	if S.inside or S.busy or S.swinging then
		S.doorAjar = 0
		return
	end
	if (S.doorAngle or 0) < DOOR_AJAR - 0.05 then
		return -- (still wide open from walking back in: it swings shut on its own)
	end
	local goal = S.doorHover and 1 or 0
	if S.doorAjar == goal then
		return -- at rest: nothing to move
	end
	S.doorAjar += (goal - S.doorAjar) * (1 - math.exp(-dt * 9))
	if math.abs(goal - S.doorAjar) < 0.003 then
		S.doorAjar = goal
	end
	if not doorRig() then
		return
	end
	if S.doorAjar > 0.01 then
		doorVoid() -- (the dark behind the gap)
	end
	poseDoor(DOOR_AJAR * S.doorAjar)
end

local function controls(on)
	pcall(function()
		local PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local c = PlayerModule:GetControls()
		if on then
			c:Enable()
		else
			c:Disable()
		end
	end)
end

---------------------------------------------------------------------------
-- The Top Collector: their best cards (floating overhead and on the two easels) and the plaque
---------------------------------------------------------------------------

local function cardFace(part, id, face)
	local old = part:FindFirstChild("CardGui" .. face.Name)
	if old then
		old:Destroy()
	end
	local sg = make("SurfaceGui", { Name = "CardGui" .. face.Name, Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 45, LightInfluence = 0.15, Brightness = 1.3 }, part)
	local holder = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, sg)
	if id and CardData.Cards[id] then
		local ok = S.ctx.makeCard ~= nil and pcall(S.ctx.makeCard, holder, id, UDim2.fromScale(1, 1))
		if not ok then
			text(holder, CardData.Cards[id].name, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextColor3 = rarityColor(CardData.Cards[id].rarity) })
		end
	else
		-- nobody here yet: an empty frame with a question mark
		holder.BackgroundColor3 = rgb(44, 38, 60)
		holder.BackgroundTransparency = 0
		corner(holder, 12)
		text(holder, "?", { Size = UDim2.fromScale(1, 1), Font = TITLE_FONT, TextScaled = true, TextColor3 = rgb(130, 120, 160) })
	end
end

local function drawTopCollector(m)
	local key = table.concat({ tostring(m:GetAttribute("ChampionId")), tostring(m:GetAttribute("Cards")), tostring(m:GetAttribute("Title")), tostring(m:GetAttribute("Count")) }, "|")
	if S.topDrawn == key then
		return
	end
	S.topDrawn = key
	local ids = {}
	for id in string.gmatch(m:GetAttribute("Cards") or "", "[^,]+") do
		table.insert(ids, id)
	end
	for i = 1, Park.ChampionCards do
		local p = m:FindFirstChild("Card" .. i)
		if p then
			cardFace(p, ids[i], Enum.NormalId.Front)
			if i == 1 then
				cardFace(p, ids[i], Enum.NormalId.Back) -- (it turns, so both sides)
			end
		end
	end
	-- the floating card glows in its rarity's color
	local best = ids[1] and CardData.Cards[ids[1]]
	local glow = best and rarityColor(best.rarity) or rgb(255, 220, 150)
	local c1 = m:FindFirstChild("Card1")
	if c1 then
		local l = c1:FindFirstChildOfClass("PointLight")
		if l then
			l.Color = glow
		end
		local g = c1:FindFirstChild("Glitter")
		if g then
			g.Color = ColorSequence.new(glow:Lerp(rgb(255, 255, 255), 0.35))
		end
	end
	-- the plaque: their face, name, title and how many cards they have
	local plaque = m:FindFirstChild("Plaque")
	if not plaque then
		return
	end
	local old = plaque:FindFirstChild("PlaqueGui")
	if old then
		old:Destroy()
	end
	local sg = make("SurfaceGui", { Name = "PlaqueGui", Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 50, LightInfluence = 0.1 }, plaque)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, sg)
	local userId, name = m:GetAttribute("ChampionId"), m:GetAttribute("ChampionName")
	local left = Enum.TextXAlignment.Left
	if userId and name then
		local img = make("ImageLabel", { Size = UDim2.fromOffset(104, 104), Position = UDim2.fromOffset(12, 13), BackgroundColor3 = rgb(54, 70, 62), Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150" }, f)
		corner(img, 52)
		stroke(img, GOLD, 3)
		text(f, "🏆 TOP COLLECTOR", { Position = UDim2.fromOffset(128, 8), Size = UDim2.new(1, -138, 0, 22), Font = TITLE_FONT, TextSize = 18, TextColor3 = GOLD, TextXAlignment = left })
		text(f, tostring(name), { Position = UDim2.fromOffset(128, 30), Size = UDim2.new(1, -138, 0, 40), Font = TITLE_FONT, TextScaled = true, TextColor3 = TEXT, TextXAlignment = left })
		local title = m:GetAttribute("Title")
		text(f, ((title and title ~= "") and ("«" .. title .. "»   ") or "") .. "🃏 " .. tostring(m:GetAttribute("Count") or 0) .. " cards", { Position = UDim2.fromOffset(128, 72), Size = UDim2.new(1, -138, 0, 22), TextSize = 16, TextColor3 = TEXT:Lerp(GOLD, 0.25), TextXAlignment = left })
		text(f, "The rarest cards in the park right now", { Position = UDim2.fromOffset(128, 96), Size = UDim2.new(1, -138, 0, 20), TextSize = 13, TextColor3 = DIM, TextXAlignment = left })
	else
		text(f, "🏆 TOP COLLECTOR", { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 30), Font = TITLE_FONT, TextSize = 26, TextColor3 = GOLD })
		text(f, "Nobody yet! Whoever here has the rarest cards stands on this pedestal.", { Position = UDim2.fromOffset(16, 52), Size = UDim2.new(1, -32, 0, 60), TextSize = 16, TextColor3 = DIM })
	end
end

local function watchTopCollector()
	local root = parkModel()
	local m = root and root:FindFirstChild("TopCollector")
	if not m or S.topWatched == m then
		return
	end
	S.topWatched = m
	m.AttributeChanged:Connect(function()
		drawTopCollector(m)
	end)
	drawTopCollector(m)
end

---------------------------------------------------------------------------
-- Hall of Pulls and leaderboards (SurfaceGuis drawn here)
---------------------------------------------------------------------------

local function boardGui(part, name)
	local sg = part:FindFirstChild(name)
	if sg then
		sg:Destroy()
	end
	sg = make("SurfaceGui", { Name = name, Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 30, LightInfluence = 0 }, part)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(26, 20, 36), BorderSizePixel = 0 }, sg)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

local function drawHall()
	local root = parkModel()
	local hall = root and root:FindFirstChild("HallOfPulls")
	local board = hall and hall:FindFirstChild("Board")
	if not board then
		return
	end
	local f = boardGui(board, "HallGui")
	text(f, "✨ HALL OF PULLS ✨", { Font = TITLE_FONT, TextSize = 46, Size = UDim2.new(1, 0, 0, 54), TextColor3 = GOLD, LayoutOrder = 0 })
	if #S.hall == 0 then
		text(f, "No big pulls yet. Open a pack at the altar: Mythic and up land here!", { TextSize = 24, Size = UDim2.new(1, 0, 0, 60), TextColor3 = DIM, LayoutOrder = 1 })
	end
	for i, e in ipairs(S.hall) do
		local card = CardData.Cards[e.card]
		local row = text(f, (e.far and "🌍 " or "") .. tostring(e.name) .. "  pulled  " .. (card and card.name or "?") .. "  (" .. tostring(e.rarity) .. ")", {
			TextSize = 26,
			Size = UDim2.new(1, 0, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarityColor(e.rarity),
			LayoutOrder = i,
		})
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.TextWrapped = false
	end
end

local function drawBoards()
	local root = parkModel()
	local folder = root and root:FindFirstChild("Boards")
	if not folder then
		return
	end
	for _, def in ipairs(Park.Boards) do
		local m = folder:FindFirstChild(def.key)
		local board = m and m:FindFirstChild("Board")
		if board then
			local f = boardGui(board, "BoardGui")
			text(f, def.emoji .. " " .. def.name, { Font = TITLE_FONT, TextSize = 34, Size = UDim2.new(1, 0, 0, 44), TextColor3 = GOLD, LayoutOrder = 0 })
			local rows = S.boards[def.key] or {}
			if #rows == 0 then
				text(f, "Updates every 2 minutes.", { TextSize = 20, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 })
			end
			for i, r in ipairs(rows) do
				local medal = ({ "🥇", "🥈", "🥉" })[i] or (i .. ".")
				local row = make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = i }, f)
				text(row, medal .. "  " .. tostring(r.name), { Size = UDim2.new(0.75, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 22, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = i <= 3 and GOLD:Lerp(TEXT, 0.4) or TEXT })
				text(row, tostring(r.value), { Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.fromScale(0.75, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 22, Font = TITLE_FONT, TextColor3 = GOLD })
			end
		end
	end
end

---------------------------------------------------------------------------
-- Nameplates and companions (for everyone in the Park, drawn on this screen only)
---------------------------------------------------------------------------

local function plateFor(p)
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return nil
	end
	local plate = S.plates[p]
	if plate and plate.Parent == head then
		return plate
	end
	if plate then
		plate:Destroy()
	end
	plate = make("BillboardGui", { Name = "ParkPlate", Size = UDim2.fromOffset(220, 64), StudsOffset = Vector3.new(0, 2.6, 0), AlwaysOnTop = false, LightInfluence = 0, MaxDistance = 90, Adornee = head }, head)
	text(plate, "", { Name = "Title", Size = UDim2.new(1, 0, 0, 18), TextSize = 14, Font = BODY_FONT, TextColor3 = GOLD, TextStrokeTransparency = 0.4 })
	text(plate, p.DisplayName, { Name = "PName", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 18), Font = TITLE_FONT, TextSize = 22, TextStrokeTransparency = 0.2 })
	text(plate, "", { Name = "Info", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 44), TextSize = 13, TextColor3 = DIM, TextStrokeTransparency = 0.5 })
	S.plates[p] = plate
	return plate
end

local function updatePlate(p)
	local plate = plateFor(p)
	if not plate then
		return
	end
	local title = p:GetAttribute("HubTitle")
	plate.Title.Text = (title and title ~= "") and ("«" .. title .. "»") or ""
	local best = p:GetAttribute("BestRarity")
	plate.PName.TextColor3 = (best and best ~= "" and Park.Rank[best] and Park.Rank[best] >= Park.Rank.Mythic) and rarityColor(best):Lerp(TEXT, 0.25) or TEXT
	plate.Info.Text = "Lv " .. tostring(p:GetAttribute("Level") or 1) .. "   ★ " .. tostring(p:GetAttribute("CampaignStars") or 0) .. "   🃏 " .. tostring(p:GetAttribute("CardsOwned") or 0)
end

local function dropPet(p)
	local pet = S.pets[p]
	if pet then
		if pet.model then
			pet.model:Destroy()
		end
		S.pets[p] = nil
	end
end

local function petFor(p, root)
	local id = p:GetAttribute("Companion")
	if type(id) ~= "string" or id == "" or not CardData.Cards[id] then
		dropPet(p)
		return nil
	end
	local pet = S.pets[p]
	if pet and pet.id == id and pet.model and pet.model.Parent then
		return pet
	end
	dropPet(p)
	if not S.ctx.buildModel then
		return nil
	end
	local ok, model = pcall(S.ctx.buildModel, id)
	if not ok or not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	-- about knee-to-hip high next to an avatar, whatever size the table model is
	if S.ctx.setScale then
		local okBox, _, size = pcall(model.GetBoundingBox, model)
		if okBox and size and size.Y > 0 then
			pcall(S.ctx.setScale, model, math.clamp(3.2 / size.Y, 0.2, 4))
		end
	end
	model.Name = "Companion_" .. p.UserId
	model.Parent = parkModel() or workspace
	-- how high the model's pivot is above its feet (to stand it on the ground)
	local lift = 0
	local okBox, boxCf, boxSize = pcall(model.GetBoundingBox, model)
	if okBox then
		lift = model:GetPivot().Position.Y - (boxCf.Position.Y - boxSize.Y / 2)
	end
	pet = { model = model, id = id, pos = root.Position + Vector3.new(3, 0, 3), phase = math.random() * 6, lift = lift }
	S.pets[p] = pet
	return pet
end

---------------------------------------------------------------------------
-- The park's life (your screen only): ducks gliding round the pond with ripples spreading
-- behind them, and the willows' long strands swaying a little in the breeze. The ducks follow
-- the server's clock, so everyone sees them in the same places.
---------------------------------------------------------------------------

local DUCK_LANES = {
	{ f = 0.2, speed = 0.05 },
	{ f = 0.55, speed = -0.04 },
	{ f = 0.85, speed = 0.035 },
	{ f = 0.35, speed = -0.055 },
	{ f = 0.7, speed = 0.045 },
}
local RIPPLE_LIFE, RIPPLE_EVERY, RIPPLE_BITS = 2.6, 1.1, 10

local function serverNow()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and t or os.clock()
end

-- Where duck `lane` is at time t (relative to the middle).
local function duckSpot(lane, t)
	local L = DUCK_LANES[(lane - 1) % #DUCK_LANES + 1]
	local a = lane * 1.3 + L.speed * t
	local inner, outer = 18.5, Park.pondRadius(a) - 3.6
	local r = inner + (outer - inner) * L.f + 0.8 * math.sin(t * 0.3 + lane)
	return Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
end

-- Butterflies, songbirds and pollen (made here, on your screen only).
local BUTTERFLY_COLORS = { rgb(255, 214, 60), rgb(250, 250, 240), rgb(255, 150, 60), rgb(120, 170, 255), rgb(240, 150, 210) }
local BIRD_KINDS = {
	{ body = rgb(120, 92, 70), chest = rgb(222, 110, 60) }, -- robin
	{ body = rgb(150, 130, 96), chest = rgb(236, 210, 120) }, -- finch
	{ body = rgb(96, 84, 76), chest = rgb(170, 150, 130) }, -- sparrow
}

local function lifePart(folder, name, size, color, round)
	local p = make("Part", { Name = name, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Size = size, Color = color, Material = Enum.Material.SmoothPlastic }, folder)
	if round then
		make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, p)
	end
	return p
end

local function makeLife(park, root)
	local folder = make("Folder", { Name = "ParkLife" }, workspace)
	park.life = folder
	park.butterflies, park.birds, park.pollen, park.fireflies = {}, {}, {}, {}
	local spots = root:FindFirstChild("Grounds") and root.Grounds:FindFirstChild("Spots")
	local n = 0
	for _, v in ipairs(spots and spots:GetChildren() or {}) do
		if v:IsA("Vector3Value") and v.Name == "Butterfly" then
			n += 1
			local color = BUTTERFLY_COLORS[(n - 1) % #BUTTERFLY_COLORS + 1]
			table.insert(park.butterflies, {
				home = v.Value,
				phase = n * 1.7,
				body = lifePart(folder, "Butterfly", Vector3.new(0.08, 0.08, 0.42), rgb(40, 34, 30), true),
				left = lifePart(folder, "Wing", Vector3.new(0.55, 0.03, 0.46), color, true),
				right = lifePart(folder, "Wing", Vector3.new(0.55, 0.03, 0.46), color, true),
			})
		elseif v:IsA("Vector3Value") and v.Name == "Bird" then
			for k = 1, 2 do
				n += 1
				local kind = BIRD_KINDS[(n - 1) % #BIRD_KINDS + 1]
				local parts = {
					{ lifePart(folder, "Bird", Vector3.new(0.55, 0.5, 0.75), kind.body, true), CFrame.new(0, 0.32, 0) },
					{ lifePart(folder, "Bird", Vector3.new(0.44, 0.42, 0.4), kind.chest, true), CFrame.new(0, 0.28, -0.22) },
					{ lifePart(folder, "Bird", Vector3.new(0.38, 0.38, 0.38), kind.body, true), CFrame.new(0, 0.58, -0.3) },
					{ lifePart(folder, "Bird", Vector3.new(0.08, 0.08, 0.2), rgb(70, 60, 40), false), CFrame.new(0, 0.56, -0.54) },
					{ lifePart(folder, "Bird", Vector3.new(0.26, 0.05, 0.42), kind.body:Lerp(rgb(0, 0, 0), 0.25), false), CFrame.new(0, 0.4, 0.46) * CFrame.Angles(math.rad(25), 0, 0) },
				}
				local start = Vector3.new(math.sin(n) * 1.5, 0, math.cos(n) * 1.5)
				table.insert(park.birds, { home = v.Value, pos = start, yaw = n, parts = parts, nextHop = os.clock() + n * 0.4, phase = n })
			end
		end
	end
	-- pollen drifting in the sunlight over the lawns
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + 0.4
		local area = lifePart(folder, "Pollen", Vector3.new(70, 10, 70), rgb(255, 255, 255), false)
		area.Transparency = 1
		area.CFrame = CFrame.new(Park.Origin + Vector3.new(math.sin(a) * 62, 5, math.cos(a) * 62))
		local e = make("ParticleEmitter", {
			Rate = 0,
			Lifetime = NumberRange.new(9, 14),
			Speed = NumberRange.new(0.15, 0.4),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new(0.08),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.25), NumberSequenceKeypoint.new(0.8, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 0.7,
			Color = ColorSequence.new(rgb(255, 250, 220)),
			Drag = 1,
			Acceleration = Vector3.new(0, 0.04, 0),
		}, area)
		e.Name = "Pollen"
		table.insert(park.pollen, e)
	end
	-- little paper lanterns that float out onto the pond after dark
	park.floaters = {}
	for i = 1, 7 do
		local base = lifePart(folder, "Floater", Vector3.new(0.9, 0.12, 0.9), rgb(120, 86, 58), false)
		local glow = lifePart(folder, "FloaterGlow", Vector3.new(0.75, 0.7, 0.75), rgb(255, 196, 120), false)
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.15
		if i % 2 == 1 then
			make("PointLight", { Color = rgb(255, 180, 100), Range = 10, Brightness = 1.2, Shadows = false }, glow)
		end
		table.insert(park.floaters, { lane = i, base = base, glow = glow })
	end
	-- fireflies over the pond, the campfire, the lawns (they only come out after dark)
	for _, v in ipairs(spots and spots:GetChildren() or {}) do
		if v:IsA("Vector3Value") and v.Name == "Fireflies" then
			local r = tonumber(v:GetAttribute("Radius")) or 10
			local area = lifePart(folder, "Fireflies", Vector3.new(r * 2, 4, r * 2), rgb(255, 255, 255), false)
			area.Transparency = 1
			area.CFrame = CFrame.new(v.Value + Vector3.new(0, 2.6, 0))
			local e = make("ParticleEmitter", {
				Name = "Fireflies",
				Rate = 0,
				Lifetime = NumberRange.new(4, 7),
				Speed = NumberRange.new(0.2, 0.6),
				SpreadAngle = Vector2.new(180, 180),
				Size = NumberSequence.new(0.13),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.05), NumberSequenceKeypoint.new(0.3, 0.85), NumberSequenceKeypoint.new(0.45, 0.1), NumberSequenceKeypoint.new(0.62, 0.9), NumberSequenceKeypoint.new(0.78, 0.15), NumberSequenceKeypoint.new(1, 1) }),
				LightEmission = 1,
				Color = ColorSequence.new(rgb(214, 255, 130)),
				Drag = 1,
				Acceleration = Vector3.new(0, 0.12, 0),
			}, area)
			pcall(function()
				e.Brightness = 4
			end)
			table.insert(park.fireflies, { emitter = e, rate = math.clamp(r * 0.3, 3, 9) })
		end
	end
end

local function updateLife(park, t, root)
	local now = os.clock()
	-- the paper lanterns drift slowly round the pond (hidden away by day)
	local night = (S.dark or 0) > 0.45
	local y = (root:GetAttribute("WaterLevel") or Park.WaterLevel)
	for _, f in ipairs(park.floaters or {}) do
		if night then
			local a = f.lane * 0.9 + t * 0.012 * (f.lane % 2 == 0 and 1 or -1)
			local r = 17 + (Park.pondRadius(a) - 21) * ((f.lane * 0.37) % 1) + 0.6 * math.sin(t * 0.2 + f.lane)
			local at = Park.Origin + Vector3.new(math.sin(a) * r, y + 0.08 + 0.04 * math.sin(t * 1.3 + f.lane), math.cos(a) * r)
			local cf = CFrame.new(at) * CFrame.Angles(0, t * 0.1 + f.lane, 0)
			f.base.CFrame = cf
			f.glow.CFrame = cf * CFrame.new(0, 0.42, 0)
		elseif f.base.Position.Y > -500 then
			f.base.CFrame = CFrame.new(0, -1000, 0)
			f.glow.CFrame = CFrame.new(0, -1000, 0)
		end
	end
	-- butterflies: lazy loops over their flowers, wings beating
	for _, b in ipairs(park.butterflies) do
		local function at(time)
			local p = b.phase
			return b.home + Vector3.new(
				math.sin(time * 0.53 + p) * 2.6 + math.sin(time * 1.7 + p * 2) * 0.6,
				1.4 + math.sin(time * 0.9 + p) * 0.5 + math.sin(time * 2.3 + p) * 0.15,
				math.cos(time * 0.41 + p * 1.3) * 2.6 + math.cos(time * 1.9 + p) * 0.5
			)
		end
		local here_, ahead = at(t), at(t + 0.1)
		local cf = CFrame.lookAt(here_, here_ + (ahead - here_) + Vector3.new(0, 0, 1e-4))
		local flap = math.sin(t * 16 + b.phase) * 0.9
		b.body.CFrame = cf
		b.left.CFrame = cf * CFrame.Angles(0, 0, flap) * CFrame.new(-0.28, 0, 0)
		b.right.CFrame = cf * CFrame.Angles(0, 0, -flap) * CFrame.new(0.28, 0, 0)
	end
	-- songbirds: peck, look about, hop somewhere new; they hop off if you walk right up
	local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for _, bird in ipairs(park.birds) do
		local world = bird.home + bird.pos
		local scared = me and (Vector3.new(me.Position.X, 0, me.Position.Z) - Vector3.new(world.X, 0, world.Z)).Magnitude < 5
		if bird.hop then
			local u = math.clamp((now - bird.hop.t0) / bird.hop.length, 0, 1)
			bird.pos = bird.hop.from:Lerp(bird.hop.to, u) + Vector3.new(0, math.sin(math.pi * u) * bird.hop.height, 0)
			if u >= 1 then
				bird.pos = bird.hop.to
				bird.hop = nil
				bird.nextHop = now + 0.8 + (math.sin(now * 7.1 + bird.phase) + 1) * 1.2
			end
		elseif now >= bird.nextHop or scared then
			local to
			if scared then
				local away = Vector3.new(world.X - me.Position.X, 0, world.Z - me.Position.Z)
				away = away.Magnitude > 0.01 and away.Unit or Vector3.new(1, 0, 0)
				to = bird.pos + away * 3
				if to.Magnitude > 6 then
					to = to.Unit * 6
				end
			else
				local a = now * 3.7 + bird.phase * 2.3
				to = Vector3.new(math.sin(a), 0, math.cos(a)) * (0.8 + (math.sin(now * 5.3 + bird.phase) + 1) * 1.3)
			end
			to = Vector3.new(to.X, 0, to.Z)
			local d = to - bird.pos
			if d.Magnitude > 0.05 then
				bird.yaw = math.atan2(-d.X, -d.Z)
			end
			bird.hop = { from = bird.pos, to = to, t0 = now, length = scared and 0.45 or 0.3, height = scared and 1.1 or 0.45 }
		end
		local peck = (not bird.hop and math.sin(now * 3 + bird.phase * 2) > 0.8) and 0.55 or 0
		local cf = CFrame.new(bird.home + bird.pos) * CFrame.Angles(0, bird.yaw, 0) * CFrame.Angles(-peck, 0, 0)
		for _, pr in ipairs(bird.parts) do
			pr[1].CFrame = cf * pr[2]
		end
	end
end

-- The sky right now: the hour where the server is (or Workspace.Park's ForceHour, to try a time
-- out in Studio), on the park's clock.
local function skyClockNow(root)
	local offset = tonumber(root:GetAttribute("UtcOffset")) or 0
	local t = serverNow() + offset
	local forced = root:GetAttribute("ForceHour")
	local hour = type(forced) == "number" and forced % 24 or (t % 86400) / 3600
	local lat, lon = root:GetAttribute("Latitude"), root:GetAttribute("Longitude")
	local rise, set = Park.DefaultSun[1], Park.DefaultSun[2]
	if type(lat) == "number" and type(lon) == "number" then
		local yday = os.date("!*t", math.floor(t)).yday
		rise, set = Park.sunTimes(lat, lon, yday, offset / 3600)
	end
	return Park.skyClock(hour, rise, set), lat, hour
end

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function applySky(root)
	local saved = S.savedLight
	if not saved then
		return
	end
	local c, lat, hour = skyClockNow(root)
	local k = Park.sky(c)
	pcall(function()
		Lighting.ClockTime = c
		Lighting.GeographicLatitude = type(lat) == "number" and lat or 38
		Lighting.Brightness = k.Brightness
		Lighting.ExposureCompensation = k.Exposure
		Lighting.Ambient = c3(k.Ambient)
		Lighting.OutdoorAmbient = c3(k.Outdoor)
		Lighting.ColorShift_Top = c3(k.ShiftTop)
		Lighting.ColorShift_Bottom = c3(k.ShiftBottom)
		Lighting.EnvironmentDiffuseScale = k.Diffuse
		Lighting.EnvironmentSpecularScale = k.Specular
	end)
	local fx = saved.fx
	pcall(function()
		local a = fx.Atmosphere
		if a then
			a.Density, a.Offset, a.Haze, a.Glare = k.Density, 0.1, k.Haze, k.Glare
			a.Color, a.Decay = c3(k.AtmoColor), c3(k.Decay)
		end
		local cc = fx.ColorCorrectionEffect
		if cc then
			cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = k.Saturation, k.Contrast, 0, c3(k.Tint)
		end
		local rays = fx.SunRaysEffect
		if rays then
			rays.Intensity, rays.Spread = k.Rays, 0.55
		end
		local clouds = fx.Clouds
		if clouds then
			clouds.Cover, clouds.Density, clouds.Color = k.Cover, k.CloudDensity, c3(k.CloudColor)
		end
	end)
	S.dark = Park.darkness(c)
	S.clock = c
	-- the little clock on the HUD: the time of day and where the server is
	if S.skyLabel then
		local icon = (c >= 5 and c < 7.2) and "🌅" or (c >= 7.2 and c < 17) and "☀️" or (c >= 17 and c < 19.2) and "🌇" or "🌙"
		local place = root:GetAttribute("ServerPlace")
		local label = string.format("%s  %02d:%02d", icon, math.floor(hour) % 24, math.floor((hour % 1) * 60)) .. ((type(place) == "string" and place ~= "" and place ~= ", ") and ("  ·  " .. place) or "")
		if S.skyLabel.Text ~= label then
			S.skyLabel.Text = label
		end
	end
end

-- The lamps, lanterns and string lights: glass by day, glowing warm once it's getting dark.
local LANTERN_GLOW = Color3.fromRGB(255, 196, 112)
local BULB_GLOW = Color3.fromRGB(255, 214, 150)

local function lightsRig(park, root)
	park.lights = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Lantern" or d.Name == "Bulb" or d.Name == "Glow") then
			local l = d:FindFirstChildWhichIsA("Light")
			table.insert(park.lights, {
				part = d,
				bulb = d.Name == "Bulb",
				glow = d.Name == "Glow", -- (an unseen light that only comes on after dark)
				material = d.Material,
				color = d.Color,
				transparency = d.Transparency,
				light = l,
				brightness = l and l.Brightness or 0,
				range = l and l.Range or 0,
			})
		end
	end
	local campfire = root:FindFirstChild("Campfire")
	park.fireLight = campfire and campfire:FindFirstChild("FireLight", true)
end

local function updateLights(park, dark)
	if park.lit and math.abs(park.lit - dark) < 0.02 then
		return
	end
	park.lit = dark
	local on = dark > 0.35
	for _, e in ipairs(park.lights) do
		local p = e.part
		if e.glow then
			if e.light then
				e.light.Enabled = on
				e.light.Brightness = e.brightness * dark
			end
		elseif on then
			p.Material = Enum.Material.Neon
			p.Color = (e.bulb and BULB_GLOW or LANTERN_GLOW):Lerp(e.color, 0.15)
			p.Transparency = 0
		else
			p.Material, p.Color, p.Transparency = e.material, e.color, e.transparency
		end
		if e.light then
			e.light.Enabled = on or not e.bulb
			e.light.Brightness = e.bulb and dark * 1.2 or e.brightness + dark * 1.5
			e.light.Range = e.range * (1 + dark * 0.45)
		end
	end
	-- fireflies come out, pollen settles, and the butterflies and songbirds go to sleep
	for _, f in ipairs(park.fireflies or {}) do
		f.emitter.Rate = f.rate * math.clamp((dark - 0.4) / 0.6, 0, 1)
	end
	for _, e in ipairs(park.pollen or {}) do
		e.Rate = 5 * (1 - dark)
	end
	local awake = dark < 0.6
	if park.awake ~= awake then
		park.awake = awake
		for _, b in ipairs(park.butterflies or {}) do
			for _, p in ipairs({ b.body, b.left, b.right }) do
				p.Transparency = awake and 0 or 1
			end
		end
		for _, bird in ipairs(park.birds or {}) do
			for _, pr in ipairs(bird.parts) do
				pr[1].Transparency = awake and 0 or 1
			end
		end
	end
end

-- The campfire crackles: its light flickers, brighter after dark.
local function flicker(park, t)
	local l = park.fireLight
	if l then
		local n = (math.sin(t * 13) + math.sin(t * 7.3 + 1) + math.sin(t * 21.7 + 2)) / 3
		l.Brightness = (1 + (S.dark or 0) * 1.6) * (0.85 + 0.15 * n)
	end
end

local function parkRig(root)
	if S.park and S.park.root == root then
		return S.park
	end
	local park = { root = root, ducks = {}, strands = {}, ripples = {}, frame = 0 }
	local pond = root:FindFirstChild("Pond")
	local ducks = pond and pond:FindFirstChild("Ducks")
	for _, d in ipairs(ducks and ducks:GetChildren() or {}) do
		local body = d:FindFirstChild("Body")
		local lane = d:GetAttribute("Lane")
		if body and lane then
			local duck = { lane = lane, parts = {}, nextRipple = 0 }
			for _, p in ipairs(d:GetChildren()) do
				if p:IsA("BasePart") then
					duck.parts[p] = body.CFrame:ToObjectSpace(p.CFrame)
				end
			end
			table.insert(park.ducks, duck)
		end
	end
	local trees = root:FindFirstChild("Grounds")
	local willows = trees and trees:FindFirstChild("Willows")
	for _, p in ipairs(willows and willows:GetDescendants() or {}) do
		if p:IsA("BasePart") and p.Name == "Strand" then
			-- each strand hangs from its top: remember that spot and how it sits under it
			local top = p.CFrame * CFrame.new(0, p.Size.Y / 2, 0)
			table.insert(park.strands, { part = p, top = top, rel = top:ToObjectSpace(p.CFrame), phase = p:GetAttribute("Phase") or 0 })
		end
	end
	makeLife(park, root)
	lightsRig(park, root)
	-- the glasshouse's glass doors (every piece tagged with its hinge by ParkBuilder)
	park.doors = {}
	for _, p in ipairs(root:GetDescendants()) do
		local at = p:IsA("BasePart") and p:GetAttribute("HingeAt")
		if typeof(at) == "Vector3" then
			table.insert(park.doors, { part = p, closed = p.CFrame, hinge = at, side = p:GetAttribute("Hinge") or 1, open = 0 })
		end
	end
	S.park = park
	return park
end

local function ripple(park, at)
	local folder = park.fx
	if not (folder and folder.Parent) then
		folder = make("Folder", { Name = "ParkRipples" }, workspace)
		park.fx = folder
	end
	local bits = {}
	for _ = 1, RIPPLE_BITS do
		table.insert(bits, make("Part", {
			Name = "Ripple",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.SmoothPlastic,
			Color = rgb(226, 240, 236),
			Transparency = 1,
			Size = Vector3.new(0.12, 0.03, 0.5),
		}, folder))
	end
	table.insert(park.ripples, { at = at, born = os.clock(), bits = bits })
end

-- A shooting star now and then on a dark night: a bright bead with a fading tail, far off in the sky.
local function shootingStar(dt, dark)
	if dark < 0.75 then
		return
	end
	S.starTimer = (S.starTimer or 6) - dt
	if S.starTimer > 0 then
		return
	end
	S.starTimer = 8 + math.random() * 14
	local cam = workspace.CurrentCamera
	local az, el = math.random() * math.pi * 2, math.rad(30 + math.random() * 28)
	local dir = Vector3.new(math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el))
	local from = cam.CFrame.Position + dir * 420
	local travel = Vector3.new(-dir.Z, -0.3 - math.random() * 0.35, dir.X).Unit * (170 + math.random() * 90)
	local star = Instance.new("Part")
	star.Name = "ShootingStar"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.new(2.6, 2.6, 2.6)
	star.Material = Enum.Material.Neon
	star.Color = Color3.fromRGB(255, 250, 232)
	star.Anchored, star.CanCollide, star.CanQuery, star.CanTouch, star.CastShadow = true, false, false, false, false
	star.CFrame = CFrame.new(from)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 1.3, 0), Vector3.new(0, -1.3, 0)
	a0.Parent, a1.Parent = star, star
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 250, 232))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = star
	star.Parent = workspace
	TweenService:Create(star, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(from + travel), Transparency = 0.4 }):Play()
	task.delay(1.6, function()
		star:Destroy()
	end)
end

local function parkLife(dt)
	local root = parkModel()
	if not root then
		return
	end
	local park = parkRig(root)
	local t = serverNow()
	-- the sky and the lights (a few times a second is plenty), the campfire every frame
	S.skyTimer = (S.skyTimer or 0) - dt
	if S.skyTimer <= 0 then
		S.skyTimer = 0.25
		applySky(root)
		updateLights(park, S.dark or 0)
		updateAmbience(root, S.dark or 0)
	end
	flicker(park, t)
	shootingStar(dt, S.dark or 0)
	local O = Park.Origin
	local y = root:GetAttribute("WaterLevel") or Park.WaterLevel
	-- the ducks, with a gentle bob
	for _, duck in ipairs(park.ducks) do
		local here_ = duckSpot(duck.lane, t)
		local ahead = duckSpot(duck.lane, t + 0.6)
		local dir = ahead - here_
		if dir.Magnitude > 1e-3 then
			local pos = O + here_ + Vector3.new(0, y + 0.2 + 0.03 * math.sin(t * 2 + duck.lane), 0)
			local cf = CFrame.lookAt(pos, pos + dir)
			for p, rel in pairs(duck.parts) do
				p.CFrame = cf * rel
			end
			if os.clock() >= duck.nextRipple then
				duck.nextRipple = os.clock() + RIPPLE_EVERY
				ripple(park, O + here_ - dir.Unit * 0.5 + Vector3.new(0, y + 0.02, 0))
			end
		end
	end
	-- the ripples: rings that spread and fade
	local now = os.clock()
	for i = #park.ripples, 1, -1 do
		local r = park.ripples[i]
		local u = (now - r.born) / RIPPLE_LIFE
		if u >= 1 then
			for _, b in ipairs(r.bits) do
				b:Destroy()
			end
			table.remove(park.ripples, i)
		else
			local radius = 0.6 + 2.6 * (1 - (1 - u) * (1 - u))
			local len = 2 * math.pi * radius / RIPPLE_BITS * 0.8
			for k, b in ipairs(r.bits) do
				local a = k / RIPPLE_BITS * math.pi * 2
				b.Size = Vector3.new(0.12, 0.03, len)
				b.CFrame = CFrame.new(r.at + Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius)) * CFrame.Angles(0, a + math.pi / 2, 0)
				b.Transparency = 0.5 + 0.5 * u
			end
		end
	end
	updateLife(park, t, root)
	-- the willows (every other frame is plenty)
	park.frame += 1
	if park.frame % 2 == 0 then
		local gust = 0.6 + 0.4 * math.sin(t * 0.23)
		for _, s in ipairs(park.strands) do
			local ax = 0.045 * gust * math.sin(t * 0.9 + s.phase)
			local az = 0.03 * gust * math.sin(t * 0.7 + s.phase * 1.7)
			s.part.CFrame = s.top * CFrame.Angles(ax, 0, az) * s.rel
		end
	end
end

local function parkQuiet()
	local park = S.park
	if not park then
		return
	end
	for _, r in ipairs(park.ripples) do
		for _, b in ipairs(r.bits) do
			b:Destroy()
		end
	end
	park.ripples = {}
	if park.fx then
		park.fx:Destroy()
		park.fx = nil
	end
end

-- The ground (or water, or a bridge plank) under a companion at `at`: its feet go there.
local petRay = RaycastParams.new()
petRay.FilterType = Enum.RaycastFilterType.Exclude
pcall(function()
	petRay.RespectCanCollide = true -- (plants and leaves you walk through are not ground)
end)
local function petGround(p, at, root)
	local skip = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(skip, other.Character)
		end
		local pet = S.pets[other]
		if pet and pet.model then
			table.insert(skip, pet.model)
		end
	end
	petRay.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(at.X, root.Position.Y + 2, at.Z), Vector3.new(0, -12, 0), petRay)
	if hit then
		return hit.Position.Y
	end
	local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	return root.Position.Y - root.Size.Y / 2 - (hum and hum.HipHeight or 2)
end

-- The glass doors swing open as anyone walks up to them, and close again behind them.
local DOOR_REACH, DOOR_ANGLE = 17, math.rad(78)
local function updateDoors(dt)
	local park = S.park
	if not (park and park.doors and #park.doors > 0) then
		return
	end
	local roots = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r and p:GetAttribute("InPark") == true then
			table.insert(roots, r.Position)
		end
	end
	local o = Park.Origin
	for _, d in ipairs(park.doors) do
		local near = false
		for _, pos in ipairs(roots) do
			if (pos - d.hinge).Magnitude < DOOR_REACH then
				near = true
				break
			end
		end
		local was = d.open
		d.open = math.clamp(d.open + (near and dt * 1.6 or -dt * 1.2), 0, 1)
		if d.open ~= was then
			-- (turn toward the inside of the glasshouse: whichever way brings it nearer the middle)
			if not d.dir then
				local test = CFrame.new(d.hinge) * CFrame.Angles(0, 0.3, 0) * CFrame.new(-d.hinge) * d.closed
				d.dir = ((test.Position - o).Magnitude < (d.closed.Position - o).Magnitude) and 1 or -1
			end
			local t = d.open * d.open * (3 - 2 * d.open)
			d.part.CFrame = CFrame.new(d.hinge) * CFrame.Angles(0, d.dir * DOOR_ANGLE * t, 0) * CFrame.new(-d.hinge) * d.closed
		end
	end
end

local function updatePeople(dt)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local there = p:GetAttribute("InPark") == true and root ~= nil
		if there then
			updatePlate(p)
			local pet = petFor(p, root)
			if pet then
				-- trot along behind and to the side, hopping a little while it moves
				local behind = root.CFrame * CFrame.new(2.6, 0, 3.2)
				local target = Vector3.new(behind.X, petGround(p, behind.Position, root), behind.Z)
				local before = pet.pos
				pet.pos = pet.pos:Lerp(target, math.clamp(dt * 4, 0, 1))
				local speed = (pet.pos - before).Magnitude / math.max(dt, 1 / 240)
				pet.phase += dt * (speed > 1 and 12 or 2)
				local hop = speed > 1 and math.abs(math.sin(pet.phase)) * 0.6 or math.sin(pet.phase) * 0.08
				local look = Vector3.new(root.Position.X, pet.pos.Y, root.Position.Z)
				if (look - pet.pos).Magnitude < 0.5 then
					look = pet.pos + root.CFrame.LookVector
				end
				local up = Vector3.new(0, pet.lift + hop, 0)
				pet.model:PivotTo(CFrame.lookAt(pet.pos + up, look + up))
			end
		else
			if S.plates[p] then
				S.plates[p]:Destroy()
				S.plates[p] = nil
			end
			dropPet(p)
		end
	end
end

Players.PlayerRemoving:Connect(function(p)
	if S.plates[p] then
		S.plates[p]:Destroy()
		S.plates[p] = nil
	end
	dropPet(p)
end)

---------------------------------------------------------------------------
-- Banners for big pulls (in the Park and in the room, never over a match or a pack)
---------------------------------------------------------------------------

local function banner(e)
	local mode = S.ctx.getMode and S.ctx.getMode()
	if mode ~= "menu" and mode ~= "park" then
		return
	end
	local card = CardData.Cards[e.card]
	if not card or not S.banners then
		return
	end
	local color = rarityColor(e.rarity)
	local b = make("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -90), Size = UDim2.fromOffset(560, 70), BackgroundColor3 = PANEL }, S.banners)
	corner(b, 14)
	stroke(b, color, 3)
	make("UIGradient", { Color = ColorSequence.new(color:Lerp(PANEL, 0.55), PANEL), Rotation = 90 }, b)
	text(b, (e.far and "🌍 Somewhere in Deck Wars" or "✨ In this server") .. ": " .. tostring(e.name) .. " pulled", { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), TextColor3 = DIM, TextSize = 15 })
	text(b, card.name .. "  ·  " .. card.rarity .. "!", { Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 30), Font = TITLE_FONT, TextSize = 26, TextColor3 = color })
	Juice.sound(e.rarity == "Secret" and "choir" or "twang", 1, 0.4)
	TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	task.delay(5.5, function()
		if b.Parent then
			TweenService:Create(b, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
			task.wait(0.45)
			b:Destroy()
		end
	end)
	-- a pillar of light over the altar for pulls in this server
	if not e.far and S.inside then
		local root = parkModel()
		local altar = root and root:FindFirstChild("Altar")
		local pillar = altar and altar:FindFirstChild("LightPillar")
		if pillar then
			pillar.Color = color
			pillar.Transparency = 0.25
			TweenService:Create(pillar, TweenInfo.new(6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		end
	end
end

-- Secret (and Shiny) pulls in the chat, for everyone in every server. Your own pull waits until
-- your pack opening is over, so the chat never spoils it.
local function chatPost(e)
	if not Park.chatWorthy(e) then
		return
	end
	local card = CardData.Cards[e.card]
	if not card then
		return
	end
	local color = e.shiny and Color3.fromRGB(255, 236, 140) or (e.rarity == "Secret" and Color3.fromRGB(255, 110, 220)) or rarityColor(e.rarity)
	local line = Park.chatLine(e, card.name, string.format("%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5)))
	local ok = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if not general then
			error("no RBXGeneral")
		end
		general:DisplaySystemMessage(line)
	end)
	if not ok then
		-- the old chat
		pcall(function()
			game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", { Text = string.gsub(line, "<[^>]+>", ""), Color = color })
		end)
	end
	S.lastChat = line -- (for tests)
end

local function whenNotOpening(fn)
	task.spawn(function()
		local ok, PackParty = pcall(function()
			return require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackParty"))
		end)
		local waited = 0
		while ok and PackParty.isPlaying() and waited < 90 do
			task.wait(0.5)
			waited += 0.5
		end
		fn()
	end)
end

---------------------------------------------------------------------------
-- The HUD, the "My look" editor and the pack panel
---------------------------------------------------------------------------

local function showHud(on)
	if S.hud then
		S.hud.Visible = on
	end
end

local function closeEditor()
	if S.editor then
		S.editor:Destroy()
		S.editor = nil
	end
end

-- "My look": the title on your nameplate and the creature that walks with you.
local function openEditor()
	closeEditor()
	local st = S.state
	local f = make("Frame", { Name = "LookEditor", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 470), BackgroundColor3 = PANEL }, S.gui)
	S.editor = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	text(f, "⭐ My look", { Font = TITLE_FONT, TextSize = 24, Size = UDim2.new(1, -60, 0, 32), Position = UDim2.fromOffset(16, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	UIKit.closeButton(f, closeEditor, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 10) })
	UIKit.Focus.watch(f, { dim = 0.4, blur = 8 })
	if not st or st.loading then
		text(f, "Loading your cards...", { Position = UDim2.fromOffset(16, 60), Size = UDim2.new(1, -32, 0, 20), TextColor3 = DIM })
		ParkAction:FireServer("State")
		return
	end
	-- your companion: the first creature you picked (or, with none picked, your rarest one)
	local picked = nil
	for _, id in ipairs(st.picked or {}) do
		local c = CardData.Cards[id]
		if c and c.type == "Creature" then
			picked = id
			break
		end
	end
	text(f, "Your title, and the creature that walks with you in the park. Tap it again to let your rarest creature walk instead.", { Position = UDim2.fromOffset(16, 44), Size = UDim2.new(1, -32, 0, 36), TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
	-- your title
	local titles = st.titles or {}
	local titleIndex = table.find(titles, st.title) or #titles
	local titleRow = make("Frame", { Size = UDim2.new(1, -32, 0, 34), Position = UDim2.fromOffset(16, 84), BackgroundTransparency = 1 }, f)
	local titleLabel = text(titleRow, "", { Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(40, 0), Font = TITLE_FONT, TextSize = 17, TextColor3 = GOLD, BackgroundColor3 = TILE, BackgroundTransparency = 0 })
	corner(titleLabel, 8)
	local function showTitle()
		titleLabel.Text = #titles == 0 and "No titles yet: win star chests in the Campaign or pull a Rare+" or ("Title: «" .. tostring(titles[titleIndex]) .. "»")
	end
	showTitle()
	for dir, x in pairs({ [-1] = 0, [1] = 1 }) do
		button(titleRow, dir < 0 and "◀" or "▶", TILE, function()
			if #titles == 0 then
				return
			end
			titleIndex = (titleIndex - 1 + dir) % #titles + 1
			showTitle()
		end, { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(x, x == 1 and -34 or 0, 0, 0) })
	end
	-- your creatures, rarest first
	local grid = make("ScrollingFrame", { Size = UDim2.new(1, -32, 1, -190), Position = UDim2.fromOffset(16, 126), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, f)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(80, 112), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local cells = {}
	local function mark()
		for id, cell in pairs(cells) do
			cell.Badge.Visible = id == picked
		end
	end
	local shown = 0
	for _, id in ipairs(st.owned or {}) do
		local c = CardData.Cards[id]
		if c and c.type == "Creature" and shown < 120 then
			shown += 1
			local cell = make("TextButton", { Name = id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = shown }, grid)
			if S.ctx.makeCard then
				local card = S.ctx.makeCard(cell, id, UDim2.fromScale(1, 1), nil, true)
				if card then
					for _, d in ipairs(card:GetDescendants()) do
						if d:IsA("GuiObject") then
							d.Active = false
						end
					end
				end
			end
			local badge = text(cell, "🐾", { Name = "Badge", Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -26, 0, -6), BackgroundColor3 = GOLD, BackgroundTransparency = 0, TextColor3 = INK, Font = TITLE_FONT, TextSize = 16, ZIndex = 10, Visible = false })
			corner(badge, 15)
			cells[id] = cell
			cell.Activated:Connect(function()
				picked = (picked ~= id) and id or nil
				Juice.sound("pop", 1.1, 0.3)
				mark()
			end)
		end
	end
	if shown == 0 then
		text(grid, "No creatures yet: open a pack!", { TextColor3 = DIM })
	end
	mark()
	button(f, "✓ Save", GOOD, function()
		ParkAction:FireServer("SetShowcase", { cards = picked and { picked } or {} })
		if #titles > 0 and titles[titleIndex] ~= st.title then
			task.delay(0.3, function()
				ParkAction:FireServer("SetTitle", { title = titles[titleIndex] })
			end)
		end
		closeEditor()
		toast("Saved!")
	end, { Size = UDim2.new(0.5, -20, 0, 44), Position = UDim2.new(0.25, 10, 1, -56) })
end

local function closePacks()
	if S.packPanel then
		S.packPanel:Destroy()
		S.packPanel = nil
	end
end

local function openPacks()
	if S.packPanel then
		return
	end
	local PackParty = require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackParty"))
	if PackParty.isPlaying() then
		return
	end
	closeEditor()
	local f = make("Frame", { Name = "AltarPacks", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 10), Size = UDim2.fromOffset(400, 560), BackgroundColor3 = PANEL }, S.gui)
	S.packPanel = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	text(f, "✨ Pull Altar", { Font = TITLE_FONT, TextSize = 24, Size = UDim2.new(1, -60, 0, 30), Position = UDim2.fromOffset(14, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	UIKit.closeButton(f, closePacks, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 8) })
	local area = make("Frame", { Name = "PackArea", Size = UDim2.new(1, -24, 1, -62), Position = UDim2.fromOffset(12, 52), BackgroundTransparency = 1 }, f)
	PackParty.mount(area, {
		noDive = true, -- (the Dive starts from the room's pack corner)
		isActive = function()
			return S.inside and area.Parent ~= nil
		end,
		onStart = function()
			controls(false)
			S.gui.Enabled = false
			if S.ctx.gui then
				S.ctx.gui.Enabled = false
			end
			if S.ctx.topGui then
				S.ctx.topGui.Enabled = false
			end
		end,
		onEnd = function()
			S.gui.Enabled = true
			if S.ctx.gui then
				S.ctx.gui.Enabled = true
			end
			if S.ctx.topGui then
				S.ctx.topGui.Enabled = true
			end
			if S.inside then
				controls(true)
				camera.CameraType = Enum.CameraType.Custom
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					camera.CameraSubject = hum
				end
			end
		end,
	})
end

local function buildGui()
	local pg = player:WaitForChild("PlayerGui")
	S.gui = make("ScreenGui", { Name = "ParkUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 7, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = true }, pg)
	S.banners = make("ScreenGui", { Name = "ParkBanners", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30 }, pg)
	S.fader = make("Frame", { Name = "Fader", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 50 }, make("ScreenGui", { Name = "ParkFade", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60 }, pg))
	local hud = make("Frame", { Name = "Hud", Size = UDim2.new(0, 700, 0, 52), Position = UDim2.fromOffset(16, 64), BackgroundTransparency = 1, Visible = false }, S.gui)
	S.hud = hud
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, hud)
	button(hud, "🏠 Home", rgb(150, 90, 60), function()
		ParkClient.leave(false)
	end, { Size = UDim2.fromOffset(120, 46), LayoutOrder = 1 })
	button(hud, "⭐ My look", rgb(70, 60, 120), function()
		if S.editor then
			closeEditor()
		else
			ParkAction:FireServer("State")
			openEditor()
		end
	end, { Size = UDim2.fromOffset(140, 46), LayoutOrder = 2 })
	S.skyLabel = text(hud, "", { Name = "SkyClock", Size = UDim2.fromOffset(260, 46), LayoutOrder = 3, Font = TITLE_FONT, TextSize = 17, TextColor3 = rgb(255, 245, 225), TextStrokeTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local hint = text(S.gui, "WASD to walk · E to use · the Top Collector stands across the pond", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(520, 22), TextColor3 = rgb(255, 245, 225), TextStrokeTransparency = 0.4, Visible = false })
	S.hint = hint
end

---------------------------------------------------------------------------
-- Walking in and out
---------------------------------------------------------------------------

function ParkClient.isInside()
	return S.inside
end

-- The camera stays inside the glasshouse: it can't be zoomed out through the glass walls or
-- the roof. (After Roblox's camera has moved each frame, a camera outside is pulled back along
-- the line to your character until it's inside again.)
local FENCE_R = 122 -- the glass wall stands at 127.5
local CAMERA_ZOOM = 45 -- the furthest you can zoom out in the park
local function insideGlass(p) -- p relative to the park's middle
	local r = math.sqrt(p.X * p.X + p.Z * p.Z)
	if r > FENCE_R then
		return false
	end
	local roof = 26.9 + 42 * math.sin(math.acos(math.clamp(r / 127.5, 0, 1))) -- (the dome over you)
	return p.Y < roof - 4
end
local function fenceCamera()
	if not S.inside or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local o = Park.Origin
	local cf = camera.CFrame
	local p = cf.Position - o
	if insideGlass(p) then
		return
	end
	local f = camera.Focus.Position - o
	if not insideGlass(f) then
		return
	end
	local lo, hi = 0, 1
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		if insideGlass(f:Lerp(p, mid)) then
			lo = mid
		else
			hi = mid
		end
	end
	camera.CFrame = cf.Rotation + (o + f:Lerp(p, lo))
end
pcall(function()
	RunService:BindToRenderStep("ParkCameraFence", Enum.RenderPriority.Camera.Value + 1, fenceCamera)
end)

function ParkClient.enter()
	local ctx = S.ctx
	if S.inside or S.busy or not ctx or ctx.getMode() ~= "menu" then
		return
	end
	if not parkModel() then
		toast("The Park is still being built. Try again in a moment.")
		return
	end
	S.busy = true
	ctx.closeStation()
	ctx.menuVisible(false)
	-- The door swings open into the dark, the camera lines up with the doorway, then pushes in
	-- through it (narrowing a little as it goes) until the black fills the screen.
	doorVoid()
	task.spawn(swingDoor, true, 0.75)
	Juice.sound("whoosh", 0.8, 0.25)
	ctx.glideCamera(Vector3.new(-14, 5.9, 18.6), Vector3.new(-14, 5.7, 30), 0.75, 62)
	task.wait(0.7)
	ctx.glideCamera(Vector3.new(-14, 5.7, 23.1), Vector3.new(-14, 5.7, 34), 0.6, 50)
	task.wait(0.5)
	fade(0, 0.15) -- (the screen is all doorway by now: this only makes sure it's black)
	ctx.setMode("park")
	S.inside = true
	ParkAction:FireServer("Enter")
	-- wait for the server to walk the character over (or give up after a few seconds)
	local t0 = time()
	while time() - t0 < 4 do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - Park.Origin).Magnitude < 200 then
			break
		end
		task.wait(0.05)
	end
	swapLight(true)
	ctx.hideCharacter(false)
	camera.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
	camera.FieldOfView = 70
	pcall(function()
		if S.zoomWas == nil then
			S.zoomWas = player.CameraMaxZoomDistance
		end
		player.CameraMaxZoomDistance = math.min(S.zoomWas, CAMERA_ZOOM)
	end)
	controls(true)
	watchTopCollector()
	drawHall()
	drawBoards()
	showHud(true)
	S.hint.Visible = true
	task.spawn(swingDoor, false, 0.1)
	fade(1, 0.6)
	S.busy = false
end

-- Back to the room. instant = no fade (a match is starting). thenStation = a station to open after.
function ParkClient.leave(instant, thenStation)
	local ctx = S.ctx
	if not S.inside or (S.busy and not instant) then
		return
	end
	S.busy = true
	closeEditor()
	closePacks()
	TradeUI.close()
	showHud(false)
	S.hint.Visible = false
	if not instant then
		fade(0, 0.4)
	end
	ParkAction:FireServer("Leave")
	controls(false)
	swapLight(false)
	S.inside = false
	if S.zoomWas ~= nil then
		pcall(function()
			player.CameraMaxZoomDistance = S.zoomWas
		end)
		S.zoomWas = nil
	end
	parkQuiet()
	for p in pairs(S.pets) do
		dropPet(p)
	end
	for p, plate in pairs(S.plates) do
		plate:Destroy()
		S.plates[p] = nil
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if not instant then
		ctx.setMode("menu")
		ctx.menuVisible(true)
		-- you step back in through the dark doorway: the camera starts inside it, looking into the
		-- room, glides out to where it's going, and the door swings shut behind you
		doorVoid()
		task.spawn(swingDoor, true, 0.01)
		ctx.glideCamera(Vector3.new(-14, 5.7, 23.1), Vector3.new(-14, 4.6, 10), 0, 50)
		task.wait(0.05)
		if thenStation then
			ctx.selectStation(thenStation)
		else
			ctx.goBack()
		end
		task.delay(0.9, function()
			if not S.inside then
				swingDoor(false, 0.6)
			end
		end)
		fade(1, 0.45)
	end
	S.busy = false
end

---------------------------------------------------------------------------
-- The front door's station panel
---------------------------------------------------------------------------

function ParkClient.doorPanel(body)
	local list = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	text(list, "Step outside into the park: everyone in this server walks around as their avatar.", { Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 })
	local lines = {
		"🏆  Whoever here has the rarest cards stands on the Top Collector's pedestal.",
		"✨  Open packs at the Pull Altar on the island. Mythic and up gets a banner for everyone.",
		"🤝  Swap cards with other players at the Trading Post.",
		"📜  Hall of Pulls and leaderboards: Campaign stars and levels.",
		"🐾  Pick a creature to walk with you, and wear a title you've earned.",
	}
	for i, l in ipairs(lines) do
		text(list, l, { Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM, LayoutOrder = 1 + i })
	end
	local count = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InPark") == true then
			count += 1
		end
	end
	text(list, count == 1 and "1 player is out there now." or (count .. " players are out there now."), { Size = UDim2.new(1, 0, 0, 22), Font = TITLE_FONT, TextSize = 17, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 10 })
	local go = button(list, "🌳  Walk out", GOOD, function()
		ParkClient.enter()
	end, { Name = "WalkOut", Size = UDim2.new(1, 0, 0, 52), TextSize = 24, LayoutOrder = 11 })
	Juice.shine(go, 3, UDim.new(0, 10))
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function ParkClient.init(ctx)
	S.ctx = ctx
	buildGui()
	TradeUI.init({ gui = S.gui, action = ParkAction, makeCard = ctx.makeCard, toast = toast })
	ParkEvent.OnClientEvent:Connect(function(e)
		if type(e) ~= "table" then
			return
		end
		if TradeUI.onEvent(e) then
			return
		end
		if e.kind == "entered" then
			S.hall = type(e.hall) == "table" and e.hall or S.hall
			S.boards = type(e.boards) == "table" and e.boards or S.boards
			drawHall()
			drawBoards()
		elseif e.kind == "hall" then
			S.hall = type(e.hall) == "table" and e.hall or {}
			drawHall()
		elseif e.kind == "boards" then
			S.boards = type(e.boards) == "table" and e.boards or {}
			drawBoards()
		elseif e.kind == "bigPull" then
			if e.userId == player.UserId and not e.far then
				whenNotOpening(function()
					chatPost(e)
					banner(e)
				end)
			else
				chatPost(e)
				banner(e)
			end
		elseif e.kind == "state" then
			S.state = e
			if S.editor then
				openEditor()
			end
		elseif e.kind == "toast" then
			toast(tostring(e.text))
		end
	end)
	-- The prompts out here: the altar, the Trading Post, the gates and the Duel Table in the gazebo.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or not S.inside or S.busy then
			return
		end
		if prompt.Name == "OpenPacks" then
			openPacks()
		elseif prompt.Name == "Trade" then
			closeEditor()
			closePacks()
			TradeUI.openPicker()
		elseif prompt.Name == "GoHome" then
			ParkClient.leave(false)
		elseif prompt.Name == "Campaign" then
			ParkClient.leave(false, "Campaign")
		elseif prompt.Name == "Duel" then
			ParkClient.leave(false, "DuelTable")
		end
	end)
	-- Escape closes the "My look" editor and the altar panel.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not S.inside then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			closeEditor()
			closePacks()
			TradeUI.escape()
		end
	end)
	-- Every frame out here: the floating pack, the nameplates, the companions and the park's ducks.
	local spin = 0
	RunService.RenderStepped:Connect(function(dt)
		updateDoorHover(dt) -- (in the room: the door eases ajar while you point at it)
		if not S.inside then
			return
		end
		spin += dt
		local root = parkModel()
		local altar = root and root:FindFirstChild("Altar")
		local pack = altar and altar:FindFirstChild("FloatingPack")
		if pack then
			S.packBase = S.packBase or pack.CFrame
			pack.CFrame = S.packBase * CFrame.new(0, math.sin(spin * 1.3) * 0.6, 0) * CFrame.Angles(0, spin * 0.7, math.sin(spin * 0.9) * 0.08)
		end
		-- the Top Collector's rarest card floats over them, turning a little this way and that
		local top = root and root:FindFirstChild("TopCollector")
		local card1 = top and top:FindFirstChild("Card1")
		if card1 then
			S.card1Base = S.card1Base or card1.CFrame
			card1.CFrame = S.card1Base * CFrame.new(0, math.sin(spin * 1.1) * 0.3, 0) * CFrame.Angles(0, math.sin(spin * 0.45) * 0.55, 0)
		end
		updatePeople(dt)
		updateDoors(dt)
		parkLife(dt)
	end)
	-- the Top Collector can change while you're inside (someone joins, pulls something rare)
	task.spawn(function()
		local root = workspace:WaitForChild("Park", 30)
		if root then
			watchTopCollector()
		end
	end)
end

ParkClient.S = S
return ParkClient

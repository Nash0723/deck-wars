-- Builds the Plaza (Workspace.Plaza) when the server starts: a round town square at golden hour,
-- far from the room. Everything that scripts look for has a fixed name:
--
--   Plaza.Altar               the Pull Altar in the middle (Model): Dais (with a ProximityPrompt
--                             "OpenPacks"), FloatingPack, LightPillar (shown on big pulls)
--   Plaza.Booths.Booth1..12   a booth each (Model): Floor, Back, Stand1..3 (card SurfaceGuis go
--                             here), Sign (SurfaceGui "SignGui"), Heart (ProximityPrompt "Like")
--   Plaza.HallOfPulls.Board   the Hall of Pulls (the client draws its SurfaceGui)
--   Plaza.Boards.<key>.Board  a leaderboard (key from Plaza.Boards)
--   Plaza.HomeDoor.Portal     a ProximityPrompt "GoHome" (back to your room)
--   Plaza.CampaignGate.Arch   a ProximityPrompt "Campaign" (opens the Campaign map in your room)
--   Plaza.DuelKiosk.Kiosk     a ProximityPrompt "Duel" (opens the Duel Table in your room)
--
-- If the place already has a Workspace.Plaza (built by hand in Studio), it is kept as it is: only
-- the parts above have to exist with these names.

local function req(name)
	if script then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end
local Plaza = req("Plaza")

local PlazaBuilder = {}

local O = Plaza.Origin

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

-- An anchored part. cf is relative to the Plaza's middle unless `world` is set.
local function part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(O) * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function cylinder(parent, name, diameter, height, cf, color, material, props)
	-- a cylinder standing up: Roblox cylinders lie along X, so turn it 90 degrees
	local p = part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent, name, diameter, cf, color, material, props)
	local p = part(parent, name, Vector3.new(diameter, diameter, diameter), cf, color, material, props)
	p.Shape = Enum.PartType.Ball
	return p
end

local function prompt(parent, name, action, objectText, distance)
	return make("ProximityPrompt", {
		Name = name,
		ActionText = action,
		ObjectText = objectText or "",
		MaxActivationDistance = distance or 10,
		HoldDuration = 0,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
	}, parent)
end

local function light(parent, color, range, brightness)
	return make("PointLight", { Color = color, Range = range, Brightness = brightness, Shadows = false }, parent)
end

-- A lamp post with a warm lantern.
local function lamp(parent, cf)
	local m = make("Model", { Name = "Lamp" }, parent)
	cylinder(m, "Post", 0.5, 9, cf * CFrame.new(0, 4.5, 0), rgb(40, 36, 44), Enum.Material.Metal)
	cylinder(m, "Foot", 1.4, 0.6, cf * CFrame.new(0, 0.3, 0), rgb(40, 36, 44), Enum.Material.Metal)
	local lantern = part(m, "Lantern", Vector3.new(1.3, 1.6, 1.3), cf * CFrame.new(0, 9.6, 0), rgb(255, 214, 140), Enum.Material.Neon)
	part(m, "Cap", Vector3.new(1.8, 0.3, 1.8), cf * CFrame.new(0, 10.55, 0), rgb(40, 36, 44), Enum.Material.Metal)
	light(lantern, rgb(255, 200, 130), 22, 1.6)
	return m
end

local TREE_GREENS = { rgb(86, 150, 72), rgb(110, 168, 70), rgb(70, 130, 80), rgb(150, 180, 70) }
local function tree(parent, cf, scale, i)
	local m = make("Model", { Name = "Tree" }, parent)
	local h = 7 * scale
	cylinder(m, "Trunk", 1.4 * scale, h, cf * CFrame.new(0, h / 2, 0), rgb(110, 76, 50), Enum.Material.Wood)
	local g = TREE_GREENS[(i % #TREE_GREENS) + 1]
	ball(m, "Leaves", 7 * scale, cf * CFrame.new(0, h + 1.5 * scale, 0), g, Enum.Material.Grass)
	ball(m, "Leaves", 5 * scale, cf * CFrame.new(1.8 * scale, h + 0.2 * scale, 0.8 * scale), g:Lerp(rgb(255, 255, 200), 0.1), Enum.Material.Grass)
	ball(m, "Leaves", 5 * scale, cf * CFrame.new(-1.6 * scale, h + 0.6 * scale, -1 * scale), g:Lerp(rgb(0, 0, 0), 0.1), Enum.Material.Grass)
	return m
end

---------------------------------------------------------------------------

local function buildGround(root)
	local g = make("Model", { Name = "Ground" }, root)
	cylinder(g, "Grass", 260, 2, CFrame.new(0, -1, 0), rgb(96, 156, 76), Enum.Material.Grass)
	-- the square: rings of warm stone, darker at the edge
	local rings = {
		{ 128, rgb(150, 132, 116) },
		{ 122, rgb(196, 178, 152) },
		{ 70, rgb(176, 158, 136) },
		{ 64, rgb(206, 190, 166) },
		{ 30, rgb(160, 140, 120) },
		{ 26, rgb(220, 205, 180) },
	}
	for i, r in ipairs(rings) do
		cylinder(g, "Stone" .. i, r[1], 0.2, CFrame.new(0, 0.1 + i * 0.01, 0), r[2], Enum.Material.Cobblestone)
	end
	-- four paths out to the gates
	for i = 0, 3 do
		local a = i * math.pi / 2
		part(g, "Path", Vector3.new(10, 0.2, 70), CFrame.Angles(0, a, 0) * CFrame.new(0, 0.12, 95), rgb(190, 172, 146), Enum.Material.Cobblestone)
	end
	-- a low hedge all the way round, and invisible walls so nobody falls off the world
	for i = 1, 36 do
		local a = (i / 36) * math.pi * 2
		part(g, "Hedge", Vector3.new(22, 4, 4), CFrame.Angles(0, a, 0) * CFrame.new(0, 2, 124), rgb(64, 120, 60), Enum.Material.Grass)
		part(g, "Wall", Vector3.new(24, 40, 2), CFrame.Angles(0, a, 0) * CFrame.new(0, 20, 127), rgb(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false })
	end
	-- a safety floor under everything
	part(g, "Under", Vector3.new(300, 2, 300), CFrame.new(0, -3, 0), rgb(60, 90, 50), Enum.Material.Grass, { Transparency = 1 })
	-- trees and lamps
	local trees = make("Model", { Name = "Trees" }, root)
	for i = 1, 22 do
		local a = (i / 22) * math.pi * 2 + 0.07
		if math.abs(math.sin(a * 2)) > 0.18 then -- leave the four paths free
			local r = 100 + (i % 3) * 6
			tree(trees, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, r), 1 + (i % 4) * 0.18, i)
		end
	end
	local lamps = make("Model", { Name = "Lamps" }, root)
	for i = 1, 12 do
		-- in line with the booths (in front of them and behind them), so the four paths stay clear
		local a = (i / 12) * math.pi * 2 + math.pi / 12
		lamp(lamps, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 33))
		lamp(lamps, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 60))
	end
end

local function buildAltar(root)
	local m = make("Model", { Name = "Altar" }, root)
	local dais = cylinder(m, "Dais", 18, 1.2, CFrame.new(0, 0.6, 0), rgb(232, 220, 200), Enum.Material.Marble)
	cylinder(m, "Step", 13, 1.2, CFrame.new(0, 1.8, 0), rgb(214, 200, 178), Enum.Material.Marble)
	cylinder(m, "Top", 8, 0.8, CFrame.new(0, 2.8, 0), rgb(245, 236, 220), Enum.Material.Marble)
	cylinder(m, "Glow", 6.4, 0.2, CFrame.new(0, 3.25, 0), rgb(255, 210, 120), Enum.Material.Neon)
	cylinder(m, "Pedestal", 2.4, 3, CFrame.new(0, 4.8, 0), rgb(70, 54, 110), Enum.Material.Marble)
	-- the big pack floating over it (the client spins and bobs it)
	local pack = part(m, "FloatingPack", Vector3.new(4.2, 6, 0.8), CFrame.new(0, 10.5, 0), rgb(120, 70, 200), Enum.Material.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = make("SurfaceGui", { Name = "PackFace" .. face.Name, Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 50, LightInfluence = 0 }, pack)
		local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(110, 60, 200), BorderSizePixel = 0 }, sg)
		make("UIGradient", { Color = ColorSequence.new(rgb(255, 120, 200), rgb(90, 70, 230)), Rotation = 70 }, f)
		make("TextLabel", { Size = UDim2.new(1, 0, 0.3, 0), Position = UDim2.fromScale(0, 0.35), BackgroundTransparency = 1, Text = "PACKS", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 255, 255) }, f)
		make("TextLabel", { Size = UDim2.new(1, 0, 0.12, 0), Position = UDim2.fromScale(0, 0.66), BackgroundTransparency = 1, Text = "✦ open at the altar ✦", TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = rgb(255, 236, 200) }, f)
	end
	light(pack, rgb(220, 150, 255), 26, 2)
	make("Sparkles", { SparkleColor = rgb(255, 220, 150) }, pack)
	-- the pillar of light for big pulls (invisible until then)
	local pillar = cylinder(m, "LightPillar", 7, 160, CFrame.new(0, 80, 0), rgb(255, 230, 150), Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	pillar:SetAttribute("Rarity", "")
	-- four crystals around the top step
	for i = 1, 4 do
		local a = i * math.pi / 2 + math.pi / 4
		local c = part(m, "Crystal", Vector3.new(1.2, 4, 1.2), CFrame.Angles(0, a, 0) * CFrame.new(0, 4.4, 5) * CFrame.Angles(math.rad(12), 0, math.rad(45)), rgb(160, 120, 255), Enum.Material.Glass, { Transparency = 0.2 })
		light(c, rgb(170, 130, 255), 10, 1)
	end
	prompt(dais, "OpenPacks", "Open packs", "Pull Altar", 16)
	return m
end

local AWNINGS = {
	{ rgb(230, 90, 90), rgb(255, 240, 225) },
	{ rgb(80, 150, 230), rgb(255, 245, 230) },
	{ rgb(90, 180, 110), rgb(255, 245, 225) },
	{ rgb(240, 170, 60), rgb(255, 248, 230) },
	{ rgb(170, 100, 220), rgb(255, 240, 250) },
	{ rgb(240, 120, 180), rgb(255, 245, 250) },
}

local function buildBooth(parent, i)
	local m = make("Model", { Name = "Booth" .. i }, parent)
	local base = Plaza.boothCFrame(i) - O -- relative, facing the middle
	local colors = AWNINGS[(i - 1) % #AWNINGS + 1]
	local floor = part(m, "Floor", Vector3.new(14, 0.8, 9), base * CFrame.new(0, 0.4, 0), rgb(150, 110, 78), Enum.Material.WoodPlanks)
	part(m, "Back", Vector3.new(14, 8, 0.6), base * CFrame.new(0, 4.8, 4.2), rgb(120, 86, 62), Enum.Material.Wood)
	part(m, "PostL", Vector3.new(0.6, 9, 0.6), base * CFrame.new(-6.7, 4.9, -4.2), rgb(110, 80, 58), Enum.Material.Wood)
	part(m, "PostR", Vector3.new(0.6, 9, 0.6), base * CFrame.new(6.7, 4.9, -4.2), rgb(110, 80, 58), Enum.Material.Wood)
	-- a striped awning
	for s = 0, 6 do
		part(m, "Awning", Vector3.new(2, 0.3, 9.6), base * CFrame.new(-6 + s * 2, 9.6, 0) * CFrame.Angles(math.rad(-10), 0, 0), s % 2 == 0 and colors[1] or colors[2], Enum.Material.Fabric)
	end
	-- three card stands on the back wall (the client draws the cards on them)
	for s = 1, Plaza.ShowcaseSize do
		local x = (s - 2) * 4.2
		local stand = part(m, "Stand" .. s, Vector3.new(3.2, 4.4, 0.25), base * CFrame.new(x, 4.6, 3.8), rgb(34, 28, 46), Enum.Material.SmoothPlastic)
		stand:SetAttribute("Slot", s)
		part(m, "Shelf", Vector3.new(3.6, 0.3, 0.8), base * CFrame.new(x, 2.25, 3.6), rgb(90, 64, 46), Enum.Material.Wood)
		local spot = part(m, "Spot", Vector3.new(0.4, 0.4, 0.4), base * CFrame.new(x, 7.6, 2.6), rgb(255, 240, 210), Enum.Material.Neon)
		make("SpotLight", { Face = Enum.NormalId.Bottom, Angle = 60, Range = 8, Brightness = 2, Color = rgb(255, 236, 205) }, spot)
	end
	-- the sign on top (owner, title, likes)
	local sign = part(m, "Sign", Vector3.new(10, 2.2, 0.4), base * CFrame.new(0, 11, -4.4), rgb(40, 30, 50), Enum.Material.Wood)
	local sg = make("SurfaceGui", { Name = "SignGui", Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, sign)
	make("TextLabel", { Name = "Owner", Size = UDim2.fromScale(1, 0.62), BackgroundTransparency = 1, Text = "Free booth", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 230, 160) }, sg)
	make("TextLabel", { Name = "Info", Size = UDim2.fromScale(1, 0.36), Position = UDim2.fromScale(0, 0.62), BackgroundTransparency = 1, Text = "", TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = rgb(236, 226, 255) }, sg)
	-- the heart you like the booth with
	local heart = part(m, "Heart", Vector3.new(1.6, 1.6, 1.6), base * CFrame.new(5.2, 2.2, -3.2), rgb(240, 80, 110), Enum.Material.Neon)
	heart.Shape = Enum.PartType.Ball
	cylinder(m, "HeartStand", 0.8, 1.6, base * CFrame.new(5.2, 1.1, -3.2), rgb(110, 80, 58), Enum.Material.Wood)
	local like = prompt(heart, "Like", "Like ❤", "Booth", 9)
	like.Enabled = false
	m:SetAttribute("Slot", i)
	floor:SetAttribute("Booth", i)
	return m
end

local function buildBoards(root)
	-- the Hall of Pulls: a big board on the north side, facing the altar
	local hall = make("Model", { Name = "HallOfPulls" }, root)
	local hallCf = CFrame.lookAt(Vector3.new(0, 9, -78), Vector3.new(0, 9, 0))
	part(hall, "Frame", Vector3.new(26, 16, 1), hallCf, rgb(70, 50, 40), Enum.Material.Wood)
	part(hall, "Board", Vector3.new(24, 14, 0.3), hallCf * CFrame.new(0, 0, -0.6), rgb(26, 20, 36), Enum.Material.SmoothPlastic)
	part(hall, "Roof", Vector3.new(28, 1, 3), hallCf * CFrame.new(0, 8.6, -0.5), rgb(160, 60, 70), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -13.5, 13.5 }) do
		part(hall, "Leg", Vector3.new(1.2, 17, 1.2), hallCf * CFrame.new(x, -0.5, 0), rgb(70, 50, 40), Enum.Material.Wood)
	end
	-- leaderboards on either side of it
	local boards = make("Model", { Name = "Boards" }, root)
	local ANGLES = { 160, 200, 140 } -- degrees round the square (the Hall of Pulls is at 180, north)
	for i, def in ipairs(Plaza.Boards) do
		local m = make("Model", { Name = def.key }, boards)
		local a = math.rad(ANGLES[(i - 1) % #ANGLES + 1])
		local at = Vector3.new(math.sin(a) * 80, 7, math.cos(a) * 80)
		local cf = CFrame.lookAt(at, Vector3.new(0, 7, 0))
		part(m, "Frame", Vector3.new(13, 13, 1), cf, rgb(70, 50, 40), Enum.Material.Wood)
		part(m, "Board", Vector3.new(12, 12, 0.3), cf * CFrame.new(0, 0, -0.6), rgb(26, 20, 36), Enum.Material.SmoothPlastic)
		for _, x in ipairs({ -6, 6 }) do
			part(m, "Leg", Vector3.new(1, 14, 1), cf * CFrame.new(x, -0.5, 0.2), rgb(70, 50, 40), Enum.Material.Wood)
		end
		local lantern = part(m, "Lantern", Vector3.new(1, 1, 1), cf * CFrame.new(0, 7.4, -1), rgb(255, 214, 140), Enum.Material.Neon)
		light(lantern, rgb(255, 210, 150), 14, 1.2)
	end
end

local function gate(root, name, angle, title, color, promptName, action)
	local m = make("Model", { Name = name }, root)
	local base = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, 112)
	part(m, "PillarL", Vector3.new(2, 14, 2), base * CFrame.new(-6, 7, 0), rgb(200, 186, 160), Enum.Material.Marble)
	part(m, "PillarR", Vector3.new(2, 14, 2), base * CFrame.new(6, 7, 0), rgb(200, 186, 160), Enum.Material.Marble)
	local arch = part(m, "Arch", Vector3.new(15, 2.4, 2.4), base * CFrame.new(0, 15, 0), color, Enum.Material.SmoothPlastic)
	local portal = part(m, "Portal", Vector3.new(10, 13, 0.4), base * CFrame.new(0, 6.6, 0), color:Lerp(rgb(255, 255, 255), 0.3), Enum.Material.Neon, { Transparency = 0.45, CanCollide = false })
	light(portal, color, 18, 2)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = make("SurfaceGui", { Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, arch)
		make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = title, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 255, 255) }, sg)
	end
	prompt(portal, promptName, action, title, 12)
	return m, portal
end

-- Builds Workspace.Plaza (or keeps the one already there). Returns the Plaza model.
function PlazaBuilder.build(workspaceRoot)
	local existing = workspaceRoot:FindFirstChild("Plaza")
	if existing then
		return existing, false
	end
	local root = make("Model", { Name = "Plaza" }, nil)
	buildGround(root)
	buildAltar(root)
	local booths = make("Model", { Name = "Booths" }, root)
	for i = 1, Plaza.Booths do
		buildBooth(booths, i)
	end
	buildBoards(root)
	gate(root, "HomeDoor", 0, "🏠 Home", rgb(255, 190, 110), "GoHome", "Back to your room")
	gate(root, "CampaignGate", -math.pi / 2, "🗺 Campaign", rgb(110, 200, 140), "Campaign", "Open the Campaign map")
	local kiosk = make("Model", { Name = "DuelKiosk" }, root)
	local kcf = CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 0, 104)
	part(kiosk, "Kiosk", Vector3.new(10, 1.2, 6), kcf * CFrame.new(0, 0.6, 0), rgb(120, 86, 62), Enum.Material.WoodPlanks)
	local table_ = part(kiosk, "Table", Vector3.new(8, 0.6, 4.6), kcf * CFrame.new(0, 3.4, 0), rgb(46, 110, 70), Enum.Material.Fabric)
	part(kiosk, "Leg", Vector3.new(1, 2.4, 1), kcf * CFrame.new(0, 2, 0), rgb(90, 64, 46), Enum.Material.Wood)
	local sign = part(kiosk, "Sign", Vector3.new(8, 2, 0.4), kcf * CFrame.new(0, 6.6, 2.2), rgb(40, 30, 50), Enum.Material.Wood)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = make("SurfaceGui", { Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, sign)
		make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "⚔ Duel Table", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 230, 160) }, sg)
	end
	prompt(table_, "Duel", "Play a match", "Duel Table", 12)
	local marker = make("Folder", { Name = "Spawns" }, root)
	for n = 0, 4 do
		make("CFrameValue", { Name = "Spawn" .. n, Value = Plaza.spawnCFrame(n) }, marker)
	end
	root.Parent = workspaceRoot
	return root, true
end

return PlazaBuilder

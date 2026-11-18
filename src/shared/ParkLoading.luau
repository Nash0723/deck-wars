-- ParkLoading: the little film you watch while the Park loads.
--
-- Pickles, the shopkeeper from the room's Shop counter, runs down a country path pushing his
-- cart piled with card packs: he's off to the Park too. Behind him the world scrolls by (clouds,
-- far hills, round trees, the gravel path), and the glasshouse comes up over the hills as the
-- Park finishes loading. Pickles himself is a copy of the real one in the room (his parts are
-- cloned from the Shop counter), so it's clearly the same fellow, with little legs added for
-- the run. Client only.
--
-- Going home it's the same film the other way round: at sunset Pickles runs back (right to left
-- across the screen) with an almost empty cart, and a cozy cottage with a lit window and a
-- smoking chimney comes up over the hills instead of the glasshouse.
--
--   local film = ParkLoading.show(shopCounter)                 -- covers the screen at once
--   local film = ParkLoading.show(shopCounter, { home = true }) -- the way home
--   film.progress(0.5)                                         -- brings the glasshouse (or home) closer (0..1)
--   film.finish()                                              -- fades it out (returns at once)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ParkLoading = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium
local CREAM = Color3.fromRGB(255, 246, 228)
local INK = Color3.fromRGB(40, 28, 20)

local TIPS = {
	"Pickles is taking fresh packs to the Park too.",
	"Press E at the Trading Post to swap cards with other players.",
	"The Top Collector waits across the pond.",
	"Your companion follows you around the Park.",
	"Day and night in the Park follow the real clock.",
	"Walk up to the glass doors: they open for you.",
}

local HOME_TIPS = {
	"Pickles sold nearly every pack. Time to head home!",
	"Your room keeps your decks, packs and trophies safe.",
	"The Campaign painting over the fireplace has new battles waiting.",
	"Pick your lands in the Duel Table before a match.",
	"The cat by the fire is still asleep.",
}

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function round(parent, r)
	return make("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, parent)
end

local function blob(parent, props)
	local f = make("Frame", props, parent)
	f.BorderSizePixel = 0
	round(f)
	return f
end

---------------------------------------------------------------------------
-- Pickles and his cart (3D, in a ViewportFrame)
---------------------------------------------------------------------------

local function part(model, name, size, cf, color, shape, material)
	local p = make("Part", {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Anchored = true,
		CanCollide = false,
		Material = material or Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, model)
	if shape then
		p.Shape = shape
	end
	return p
end

-- Builds Pickles (from the Shop counter if it's there) and his cart around the origin, facing -Z.
local function buildActors(world, counter, home)
	local actors = { pickles = make("Model", { Name = "Pickles" }, world), parts = {} }
	local body = counter and counter:FindFirstChild("Pickles")
	local GREEN = body and body.Color or Color3.fromRGB(110, 165, 60)
	if body then
		local base = body.CFrame
		for _, p in ipairs(counter:GetChildren()) do
			if p:IsA("BasePart") and string.sub(p.Name, 1, 6) == "Pickle" then
				local c = p:Clone()
				c.Anchored = true
				c.CFrame = base:ToObjectSpace(p.CFrame)
				c.Parent = actors.pickles
				table.insert(actors.parts, { part = c, rest = c.CFrame })
			end
		end
	else
		-- a stand-in pickle if the room isn't there
		local b = part(actors.pickles, "Pickles", Vector3.new(2.6, 4.4, 2.4), CFrame.new(), GREEN)
		make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, b)
		table.insert(actors.parts, { part = b, rest = b.CFrame })
	end
	-- little legs and shoes for the run (the one in the shop stands behind the counter)
	actors.legs = {}
	for _, side in ipairs({ -1, 1 }) do
		local hip = CFrame.new(side * 0.55, -1.7, 0.1)
		local leg = part(actors.pickles, "Leg", Vector3.new(1.1, 0.42, 0.42), hip * CFrame.new(0, -0.55, 0) * CFrame.Angles(0, 0, math.pi / 2), GREEN:Lerp(Color3.new(0, 0, 0), 0.15), Enum.PartType.Cylinder)
		local shoe = part(actors.pickles, "Shoe", Vector3.new(0.55, 0.38, 0.8), hip * CFrame.new(0, -1.15, -0.15), Color3.fromRGB(120, 72, 40), nil)
		make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, shoe)
		table.insert(actors.legs, { hip = hip, leg = leg, shoe = shoe, side = side })
	end

	-- the cart: a wooden crate on two wheels, a push bar at Pickles' hands, packs piled on top
	local cart = make("Model", { Name = "Cart" }, world)
	actors.cart = cart
	actors.cartParts = {}
	local WOOD = Color3.fromRGB(170, 112, 62)
	local DARK = Color3.fromRGB(110, 70, 38)
	local function add(p)
		table.insert(actors.cartParts, { part = p, rest = p.CFrame })
		return p
	end
	local boxCF = CFrame.new(0, -1.35, -4.9)
	add(part(cart, "Crate", Vector3.new(3.2, 1.5, 3.4), boxCF, WOOD, nil, Enum.Material.WoodPlanks))
	for _, dz in ipairs({ -1.7, 1.7 }) do
		add(part(cart, "Rim", Vector3.new(3.3, 0.22, 0.2), boxCF * CFrame.new(0, 0.7, dz), DARK, nil, Enum.Material.Wood))
	end
	for _, dx in ipairs({ -1.6, 1.6 }) do
		add(part(cart, "Rim", Vector3.new(0.2, 0.22, 3.5), boxCF * CFrame.new(dx, 0.7, 0), DARK, nil, Enum.Material.Wood))
		-- push rails from the crate up to the bar
		local a = boxCF * Vector3.new(dx * 0.9, 0.6, 1.7)
		local b = Vector3.new(dx * 0.9, -0.15, -2.1)
		local mid = (a + b) / 2
		add(part(cart, "Rail", Vector3.new(0.18, 0.18, (b - a).Magnitude), CFrame.lookAt(mid, b), DARK, nil, Enum.Material.Wood))
	end
	add(part(cart, "PushBar", Vector3.new(3.4, 0.24, 0.24), CFrame.new(0, -0.15, -2.1) * CFrame.Angles(0, 0, math.pi / 2), DARK, Enum.PartType.Cylinder, Enum.Material.Wood))
	-- card packs (bright foil) piled in the crate, and a little pennant
	local PACKS = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(110, 200, 255), Color3.fromRGB(255, 205, 80), Color3.fromRGB(150, 230, 120), Color3.fromRGB(190, 140, 255) }
	actors.packs = {}
	for k = 1, home and 3 or 7 do -- (on the way home the cart is nearly empty: he sold them)
		local x = ((k % 3) - 1) * 0.95
		local z = -0.9 + math.floor((k - 1) / 3) * 0.9
		local cf = boxCF * CFrame.new(x, 0.95 + (k % 2) * 0.12, z) * CFrame.Angles(math.rad(-25 + k * 9), math.rad(k * 23), math.rad(10 - k * 4))
		local p = add(part(cart, "Pack", Vector3.new(0.75, 1.05, 0.12), cf, PACKS[(k - 1) % #PACKS + 1], nil, Enum.Material.Foil))
		table.insert(actors.packs, { part = p, rest = cf, phase = k * 1.3 })
	end
	add(part(cart, "Pole", Vector3.new(0.1, 1.9, 0.1), boxCF * CFrame.new(1.4, 1.5, 1.4), DARK))
	local flag = add(part(cart, "Pennant", Vector3.new(0.05, 0.5, 0.9), boxCF * CFrame.new(1.4, 2.2, 1.0), Color3.fromRGB(235, 70, 70)))
	actors.flag = { part = flag, rest = flag.CFrame }
	-- the wheels (they spin)
	actors.wheels = {}
	for _, dx in ipairs({ -1.85, 1.85 }) do
		local center = boxCF * CFrame.new(dx, -0.85, 0.2)
		local w = part(cart, "Wheel", Vector3.new(0.3, 1.5, 1.5), center, DARK, Enum.PartType.Cylinder, Enum.Material.Wood)
		local hub = part(cart, "Hub", Vector3.new(0.34, 0.45, 0.45), center, Color3.fromRGB(220, 180, 90), Enum.PartType.Cylinder, Enum.Material.Metal)
		local spokes = {}
		for s = 0, 2 do
			table.insert(spokes, part(cart, "Spoke", Vector3.new(0.32, 1.25, 0.12), center * CFrame.Angles(s * math.pi / 3, 0, 0), Color3.fromRGB(220, 180, 90), nil, Enum.Material.Wood))
		end
		table.insert(actors.wheels, { wheel = w, hub = hub, spokes = spokes, center = center })
	end
	return actors
end

---------------------------------------------------------------------------
-- The film
---------------------------------------------------------------------------

function ParkLoading.show(counter, opts)
	opts = opts or {}
	local home = opts.home == true
	-- going home everything runs the other way: the world scrolls right, Pickles faces left
	local dir = home and 1 or -1
	local tips = home and HOME_TIPS or TIPS
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", { Name = "ParkLoading", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 70, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
	local root = make("CanvasGroup", { Name = "Film", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 205, 240), BorderSizePixel = 0, GroupTransparency = 1 }, gui)
	TweenService:Create(root, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()

	-- sky (a sunset on the way home)
	if home then
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 100, 180)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(240, 150, 150)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 130)) }) }, root)
	else
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 185, 240)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(190, 225, 245)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 222, 180)) }) }, root)
	end
	local sun = blob(root, { Name = "Sun", AnchorPoint = Vector2.new(0.5, 0.5), Position = home and UDim2.fromScale(0.72, 0.4) or UDim2.fromScale(0.8, 0.2), Size = home and UDim2.fromOffset(150, 150) or UDim2.fromOffset(110, 110), BackgroundColor3 = home and Color3.fromRGB(255, 170, 90) or Color3.fromRGB(255, 236, 160) })
	make("UIStroke", { Thickness = 14, Color = home and Color3.fromRGB(255, 200, 140) or Color3.fromRGB(255, 245, 200), Transparency = 0.6 }, sun)

	-- clouds (drift slowly)
	local clouds = {}
	for k = 1, 5 do
		local c = make("Frame", { Name = "Cloud", Size = UDim2.fromOffset(150 + k * 14, 46), Position = UDim2.fromScale(k * 0.23 - 0.1, 0.08 + (k % 3) * 0.07), BackgroundTransparency = 1 }, root)
		for j, spec in ipairs({ { 0, 0.35, 0.45, 0.65 }, { 0.25, 0, 0.45, 1 }, { 0.55, 0.2, 0.42, 0.8 } }) do
			blob(c, { Name = "Puff" .. j, Position = UDim2.fromScale(spec[1], spec[2]), Size = UDim2.fromScale(spec[3], spec[4]), BackgroundColor3 = home and Color3.fromRGB(255, 215, 205) or Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.08 })
		end
		table.insert(clouds, { frame = c, x = k * 0.23 - 0.1, speed = 0.008 + (k % 3) * 0.004 })
	end

	-- the glasshouse, far off: it comes up over the hills as the Park loads
	local glass = make("Frame", { Name = "Glasshouse", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.92, 0.6), Size = UDim2.fromOffset(150, 95), BackgroundTransparency = 1 }, root)
	local dome = blob(glass, { Name = "Dome", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromScale(0.78, 1.15), BackgroundColor3 = Color3.fromRGB(205, 240, 245), BackgroundTransparency = 0.25 })
	make("UIStroke", { Thickness = 3, Color = Color3.fromRGB(250, 252, 255) }, dome)
	for k = 1, 5 do
		make("Frame", { Name = "Rib", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(k / 6, 0.05), Size = UDim2.new(0, 2, 0.95, 0), BackgroundColor3 = Color3.fromRGB(250, 252, 255), BorderSizePixel = 0 }, dome)
	end
	blob(glass, { Name = "Lantern", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromRGB(255, 225, 140) })

	-- going home it's a cozy cottage instead: plaster walls, a red roof, a glowing window and a
	-- chimney that puffs smoke (the house you live in, with your room behind that window)
	local smoke = {}
	local chimney
	if home then
		glass:Destroy()
		glass = make("Frame", { Name = "Home", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.08, 0.6), Size = UDim2.fromOffset(150, 95), BackgroundTransparency = 1 }, root)
		local wall = make("Frame", { Name = "Wall", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.72, 0.62), BackgroundColor3 = Color3.fromRGB(245, 226, 196), BorderSizePixel = 0 }, glass)
		round(wall, 4)
		make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(150, 110, 80), Transparency = 0.3 }, wall)
		chimney = make("Frame", { Name = "Chimney", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.7, 0.3), Size = UDim2.fromScale(0.1, 0.32), BackgroundColor3 = Color3.fromRGB(170, 85, 70), BorderSizePixel = 0 }, glass)
		for _, side in ipairs({ -1, 1 }) do
			-- the roof: two slanted boards meeting at the ridge
			local r = make("Frame", { Name = "Roof", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + side * 0.2, 0.25), Size = UDim2.fromScale(0.52, 0.13), Rotation = side * 31, BackgroundColor3 = Color3.fromRGB(200, 80, 70), BorderSizePixel = 0 }, glass)
			round(r, 4)
			make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(120, 45, 40), Transparency = 0.2 }, r)
		end
		local gable = make("Frame", { Name = "Gable", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.36, 0.14), BackgroundColor3 = Color3.fromRGB(245, 226, 196), BorderSizePixel = 0 }, glass)
		round(gable, 3)
		local win = make("Frame", { Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.34, 0.66), Size = UDim2.fromScale(0.2, 0.22), BackgroundColor3 = Color3.fromRGB(255, 210, 110), BorderSizePixel = 0 }, glass)
		round(win, 3)
		make("UIStroke", { Thickness = 3, Color = Color3.fromRGB(120, 80, 50) }, win)
		make("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = Color3.fromRGB(120, 80, 50), BorderSizePixel = 0 }, win)
		make("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(120, 80, 50), BorderSizePixel = 0 }, win)
		blob(glass, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.34, 0.66), Size = UDim2.fromScale(0.42, 0.42), BackgroundColor3 = Color3.fromRGB(255, 220, 140), BackgroundTransparency = 0.75 })
		local door = make("Frame", { Name = "Door", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.64, 1), Size = UDim2.fromScale(0.15, 0.36), BackgroundColor3 = Color3.fromRGB(130, 80, 50), BorderSizePixel = 0 }, glass)
		round(door, 5)
		blob(door, { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.75, 0.55), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(240, 200, 90) })
	end

	-- far hills, then round trees, then the near ground and path (each layer scrolls faster)
	local function hillRow(name, y, color, count, w, h)
		local row = make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, root)
		local items = {}
		for k = 0, count do
			local hill = blob(row, { Name = "Hill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(k / count, 0, y + (k % 2) * 0.035, 0), Size = UDim2.new(w * (0.85 + (k % 3) * 0.12), 0, h, 0), BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), (k % 2) * 0.07) })
			table.insert(items, { frame = hill, x = k / count })
		end
		return { row = row, items = items, count = count, y = y }
	end
	local far = hillRow("FarHills", 0.47, Color3.fromRGB(150, 190, 170), 5, 0.4, 0.6)
	local mid = hillRow("MidHills", 0.57, Color3.fromRGB(105, 165, 95), 4, 0.48, 0.6)
	glass.Parent = root -- (in front of the far hills, behind the near ones)
	far.row.ZIndex, glass.ZIndex, mid.row.ZIndex = 1, 2, 3
	for _, d in ipairs(glass:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = d.Name == "Glow" and 1 or (d.Name == "Roof" or d.Name == "Gable" or d.Name == "Window" or d.Name == "Door") and 3 or 2
		end
	end
	if chimney then
		chimney.ZIndex = 1
	end
	for _, d in ipairs(mid.row:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 3
		end
	end

	local trees = {}
	for k = 1, 7 do
		local t = make("Frame", { Name = "Tree", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(k / 6, 0, 0.72, 0), Size = UDim2.fromOffset(70 + (k % 3) * 20, 120 + (k % 2) * 30), BackgroundTransparency = 1, ZIndex = 4 }, root)
		make("Frame", { Name = "Trunk", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.14, 0.42), BackgroundColor3 = Color3.fromRGB(120, 80, 50), BorderSizePixel = 0, ZIndex = 4 }, t)
		blob(t, { Name = "Leaves", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(1, 0.72), BackgroundColor3 = Color3.fromRGB(70, 140, 70):Lerp(Color3.fromRGB(110, 170, 80), (k % 3) / 3), ZIndex = 4 })
		table.insert(trees, { frame = t, x = k / 6 })
	end

	local ground = make("Frame", { Name = "Ground", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.32), BackgroundColor3 = Color3.fromRGB(110, 175, 80), BorderSizePixel = 0, ZIndex = 5 }, root)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(130, 190, 90), Color3.fromRGB(80, 140, 60)) }, ground)
	local path = make("Frame", { Name = "Path", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.42), Size = UDim2.fromScale(1, 0.34), BackgroundColor3 = Color3.fromRGB(225, 200, 160), BorderSizePixel = 0, ZIndex = 6 }, ground)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(235, 215, 175), Color3.fromRGB(205, 178, 135)) }, path)
	local pebbles = {}
	for k = 1, 14 do
		local p = blob(path, { Name = "Pebble", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(k / 12, 0.25 + (k % 3) * 0.25), Size = UDim2.fromOffset(14 + (k % 4) * 6, 7 + (k % 3) * 2), BackgroundColor3 = Color3.fromRGB(175, 150, 115), ZIndex = 7 })
		table.insert(pebbles, { frame = p, x = k / 12 })
	end
	local flowers = {}
	for k = 1, 10 do
		local f = blob(ground, { Name = "Flower", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(k / 9, 0.82 + (k % 2) * 0.08), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = ({ Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 230, 110), Color3.fromRGB(250, 250, 255) })[k % 3 + 1], ZIndex = 7 })
		table.insert(flowers, { frame = f, x = k / 9 })
	end

	-- Pickles and the cart, in 3D
	-- (going home the camera looks from his other side, so he runs right to left)
	local vp = make("ViewportFrame", { Name = "Runner", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(home and 0.58 or 0.42, 0, 1.08, -18), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 1, Ambient = home and Color3.fromRGB(205, 180, 175) or Color3.fromRGB(200, 195, 190), LightColor = home and Color3.fromRGB(255, 205, 160) or Color3.fromRGB(255, 245, 225), LightDirection = Vector3.new(home and 0.7 or -0.7, -0.6, 0.45), ZIndex = 9 }, root)
	local world = make("WorldModel", {}, vp)
	local cam = make("Camera", { FieldOfView = 32 }, vp)
	vp.CurrentCamera = cam
	cam.CFrame = CFrame.lookAt(Vector3.new(home and -20 or 20, 3, -7.5), Vector3.new(0, -1.1, -2.4))
	local actors = buildActors(world, counter, home)
	-- a soft shadow under them
	local shadow = blob(root, { Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(home and 0.57 or 0.43, 0.835), Size = UDim2.fromScale(0.3, 0.035), BackgroundColor3 = Color3.fromRGB(110, 85, 55), BackgroundTransparency = 0.55, ZIndex = 8 })

	-- dust puffs behind the wheels and feet
	local dust = {}
	local function puff()
		local x = home and (0.52 + math.random() * 0.18) or (0.3 + math.random() * 0.18)
		local d = blob(root, { Name = "Dust", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0.83, -math.random() * 12), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromRGB(240, 225, 200), BackgroundTransparency = 0.25, ZIndex = 8 })
		table.insert(dust, { frame = d, age = 0, vx = dir * (0.12 + math.random() * 0.08), vy = -14 - math.random() * 10 })
	end

	-- words
	local title = make("TextLabel", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(640, 64), BackgroundTransparency = 1, Font = TITLE_FONT, TextSize = 54, TextColor3 = CREAM, Text = home and "Heading home!" or "Off to the Park!", ZIndex = 20 }, root)
	make("UIStroke", { Thickness = 4, Color = INK, Transparency = 0.1 }, title)
	local barBack = make("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(360, 14), BackgroundColor3 = Color3.fromRGB(60, 40, 28), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 20 }, root)
	round(barBack)
	make("UIStroke", { Thickness = 2, Color = CREAM, Transparency = 0.3 }, barBack)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 205, 90), BorderSizePixel = 0, ZIndex = 21 }, barBack)
	round(fill)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 160, 60)) }, fill)
	local tip = make("TextLabel", { Name = "Tip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(700, 24), BackgroundTransparency = 1, Font = BODY_FONT, TextSize = 17, TextColor3 = CREAM, Text = tips[1], ZIndex = 20 }, root)
	make("UIStroke", { Thickness = 2, Color = INK, Transparency = 0.35 }, tip)

	local film = { done = false, target = 0, shown = 0 }
	local t, puffT, tipT, tipN = 0, 0, 0, 1

	local function scroll(list, speed, dt, wrapSpan)
		for _, it in ipairs(list) do
			it.x += dir * speed * dt
			if dir < 0 and it.x < -0.2 then
				it.x += wrapSpan
			elseif dir > 0 and it.x > wrapSpan - 0.2 then
				it.x -= wrapSpan
			end
			it.frame.Position = UDim2.new(it.x, 0, it.frame.Position.Y.Scale, it.frame.Position.Y.Offset)
		end
	end

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		-- the world goes by
		scroll(clouds, 0.02, dt, 1.4)
		scroll(far.items, 0.03, dt, 1 + 1 / far.count + 0.2)
		scroll(mid.items, 0.07, dt, 1 + 1 / mid.count + 0.2)
		scroll(trees, 0.16, dt, 7 / 6)
		scroll(pebbles, 0.42, dt, 14 / 12)
		scroll(flowers, 0.36, dt, 10 / 9)
		-- the glasshouse rises into view as the loading goes on
		film.shown += (film.target - film.shown) * math.min(1, dt * 3)
		local k = film.shown
		glass.Position = UDim2.fromScale(home and (0.1 + 0.18 * k) or (0.9 - 0.18 * k), 0.6 + 0.06 * (1 - k))
		glass.Size = UDim2.fromOffset(150 + 110 * k, 95 + 70 * k)
		fill.Size = UDim2.fromScale(math.clamp(0.08 + 0.92 * k, 0, 1), 1)
		-- Pickles runs: a bob, a forward lean, legs swinging; the cart bumps along
		local stride = t * 11
		local bob = math.abs(math.sin(stride)) * 0.35
		local lean = CFrame.Angles(math.rad(-10), 0, 0)
		local bodyCF = CFrame.new(0, bob, 0) * lean
		for _, it in ipairs(actors.parts) do
			it.part.CFrame = bodyCF * it.rest
		end
		for _, l in ipairs(actors.legs) do
			local swing = math.sin(stride + (l.side > 0 and 0 or math.pi)) * 0.7
			local hip = bodyCF * l.hip * CFrame.Angles(swing, 0, 0)
			l.leg.CFrame = hip * CFrame.new(0, -0.55, 0) * CFrame.Angles(0, 0, math.pi / 2)
			l.shoe.CFrame = hip * CFrame.new(0, -1.15, -0.15)
		end
		local bump = math.abs(math.sin(stride * 0.5 + 1)) * 0.12
		local cartCF = CFrame.new(0, bob * 0.6 + bump, 0)
		for _, it in ipairs(actors.cartParts) do
			it.part.CFrame = cartCF * it.rest
		end
		for _, p in ipairs(actors.packs) do
			p.part.CFrame = cartCF * p.rest * CFrame.new(0, math.abs(math.sin(stride * 0.5 + p.phase)) * 0.12, 0)
		end
		actors.flag.part.CFrame = cartCF * actors.flag.rest * CFrame.Angles(0, math.sin(t * 9) * 0.25, 0)
		local spin = -t * 9
		for _, w in ipairs(actors.wheels) do
			local c = cartCF * w.center * CFrame.Angles(spin, 0, 0)
			w.wheel.CFrame = c
			w.hub.CFrame = c
			for s, sp in ipairs(w.spokes) do
				sp.CFrame = c * CFrame.Angles(s * math.pi / 3, 0, 0)
			end
		end
		shadow.Size = UDim2.fromScale(0.3 - bob * 0.05, 0.035)
		-- the cottage's chimney puffs smoke
		if chimney and t - (film.smokeAt or -1) > 0.45 then
			film.smokeAt = t
			local s = blob(glass, { Name = "Smoke", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.0), Size = UDim2.fromScale(0.08, 0.1), BackgroundColor3 = Color3.fromRGB(235, 225, 230), BackgroundTransparency = 0.3, ZIndex = 1 })
			table.insert(smoke, { frame = s, age = 0 })
		end
		for i = #smoke, 1, -1 do
			local s = smoke[i]
			s.age += dt
			local a = s.age / 2.2
			if a >= 1 then
				s.frame:Destroy()
				table.remove(smoke, i)
			else
				s.frame.Position = UDim2.fromScale(0.7 + a * 0.25 + math.sin(s.age * 3) * 0.03, -a * 0.7)
				s.frame.Size = UDim2.fromScale(0.08 + a * 0.14, 0.1 + a * 0.18)
				s.frame.BackgroundTransparency = 0.3 + a * 0.7
			end
		end
		-- dust
		puffT += dt
		if puffT > 0.09 then
			puffT = 0
			puff()
		end
		for i = #dust, 1, -1 do
			local d = dust[i]
			d.age += dt
			local a = d.age / 0.7
			if a >= 1 then
				d.frame:Destroy()
				table.remove(dust, i)
			else
				local p = d.frame.Position
				d.frame.Position = UDim2.new(p.X.Scale + d.vx * dt, 0, p.Y.Scale, p.Y.Offset + d.vy * dt)
				local s = 18 + a * 26
				d.frame.Size = UDim2.fromOffset(s, s)
				d.frame.BackgroundTransparency = 0.25 + a * 0.75
			end
		end
		-- a new tip now and then
		tipT += dt
		if tipT > 3.2 then
			tipT = 0
			tipN = tipN % #tips + 1
			tip.Text = tips[tipN]
		end
		title.Rotation = math.sin(t * 2.2) * 1.5
	end)

	function film.progress(p)
		film.target = math.clamp(p, 0, 1)
	end

	function film.finish()
		if film.done then
			return
		end
		film.done = true
		film.target = 1
		task.spawn(function()
			task.wait(0.25)
			TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { GroupTransparency = 1 }):Play()
			task.wait(0.5)
			conn:Disconnect()
			gui:Destroy()
		end)
	end

	return film
end

return ParkLoading

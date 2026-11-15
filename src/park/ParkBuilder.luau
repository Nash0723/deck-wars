-- Builds the Park (Workspace.Park) when the server starts: a city park on a sunny afternoon,
-- far from the room. Mature oaks and maples over wide, winding gravel paths; a calm pond in the
-- middle with weeping willows, reeds, lily pads, river stones and ducks; a low wooden bridge under
-- a rose arch out to the island where the Pull Altar stands; the Top Collector's terrace on the
-- far shore (whoever here has the rarest cards stands on its pedestal); open lawns with
-- wildflowers, a big sycamore, picnic blankets and a bird bath; a white iron gazebo on the east
-- side (the Duel Table is inside) in beds of lavender, marigolds and hydrangeas; and old benches
-- in quiet nooks round the edge. The ground and the pond are real terrain (grass you can see
-- move, real water) when the place has terrain; parts otherwise.
--
-- Everything that scripts look for has a fixed name:
--
--   Park.Altar                 the Pull Altar on the island (Model): Dais (with a ProximityPrompt
--                               "OpenPacks"), FloatingPack, LightPillar (shown on big pulls)
--   Park.TopCollector          the Top Collector's terrace (Model; ParkServer sets its attributes
--                               ChampionId, ChampionName, Title, Cards, Count): AvatarSpot (where
--                               the avatar stands), Card1 (floats overhead), Card2, Card3 (easels),
--                               Plaque (the client draws all four)
--   Park.HallOfPulls.Board     the Hall of Pulls (the client draws its SurfaceGui)
--   Park.Boards.<key>.Board    a leaderboard (key from Park.Boards)
--   Park.HomeDoor.Portal       a ProximityPrompt "GoHome" (back to your room)
--   Park.CampaignGate.Portal   a ProximityPrompt "Campaign" (opens the Campaign map in your room)
--   Park.DuelKiosk.Table       a ProximityPrompt "Duel" (opens the Duel Table in your room)
--   Park.TradingPost.Desk      a ProximityPrompt "Trade" (trade cards with another player); the
--                               server also measures "at the Trading Post" from this part
--   Park.Pond.Ducks.Duck1..    the ducks (Models; the client glides them round the pond)
--   Park.Grounds.Willows          the weeping willows (the client sways their "Strand" parts)
--   Park.Grounds.Spots            Vector3Values "Butterfly" and "Bird": where the client lets
--                               butterflies flutter and songbirds hop
--   Park (attribute WaterLevel) the pond's surface height (relative to the ground)
--
-- If the place already has a Workspace.Park (built by hand in Studio), it is kept as it is: only
-- the parts above have to exist with these names.

local function req(name)
	if script then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end
local Park = req("Park")
-- (the Blender-made models and the painted ground: see ParkKit)
local Kit = script and require(script.Parent:WaitForChild("ParkKit")) or require("ParkKit")

local ParkBuilder = {}

local O = Park.Origin
Kit.Origin = O
local TAU = math.pi * 2
local WATER = Park.WaterLevel
local ISLAND = Park.IslandRadius
local STEPPING_DEG = 306 -- where the stepping stones cross the pond to the island
local pondR = Park.pondRadius

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

-- An anchored part. cf is relative to the Park's middle.
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

-- A squashed or stretched ball (a block with a sphere mesh: no collisions, nothing to click).
local function egg(parent, name, size, cf, color, material, props)
	local p = part(parent, name, size, cf, color, material, props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, p)
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

local function polar(a, r)
	return Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
end

-- A flat strip on the ground from a to b (points at ground level, relative to the middle).
local function strip(parent, name, a, b, width, top, thick, color, material, props)
	local mid = (a + b) / 2
	local y = top - thick / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
	return part(parent, name, Vector3.new(width, thick, (b - a).Magnitude), cf, color, material, props)
end

-- A beam (a thin box) from point a to point b, in 3D.
local function beam(parent, name, a, b, thick, color, material, props)
	local cf = CFrame.lookAt((a + b) / 2, b)
	return part(parent, name, Vector3.new(thick, thick, (b - a).Magnitude), cf, color, material, props)
end

local NO_TOUCH = { CanCollide = false, CanQuery = false, CanTouch = false }
local function merge(a, b)
	local out = {}
	for k, v in pairs(a) do
		out[k] = v
	end
	for k, v in pairs(b or {}) do
		out[k] = v
	end
	return out
end
local LEAVES = merge(NO_TOUCH, {})

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------

local GRASS = rgb(92, 150, 70)
local GRAVEL = rgb(204, 192, 166)
local IRON = rgb(38, 40, 38)
local WHITE_IRON = rgb(238, 238, 232)
local STONE = rgb(170, 166, 154)
local BARK = rgb(92, 70, 52)
local OAK_GREENS = { rgb(70, 112, 52), rgb(84, 128, 58), rgb(62, 102, 50), rgb(96, 136, 60) }
local MAPLE_GREENS = { rgb(104, 150, 62), rgb(118, 162, 68), rgb(92, 142, 58) }
local MAPLE_REDS = { rgb(176, 64, 44), rgb(200, 96, 48) }
local WILLOW_GREENS = { rgb(150, 182, 86), rgb(132, 170, 78), rgb(166, 192, 98) }

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------

-- Gravel along a list of points: one strip per stretch, a round patch at every bend.
-- (Next stretches sit a hair apart in height so their overlaps never flicker.)
local function gravel(parent, points, width, lift, closed)
	lift = lift or 0
	local n = #points
	for k = 1, closed and n or n - 1 do
		local b = points[k % n + 1]
		strip(parent, "Path", points[k], b, width, 0.12 + lift + (k % 2) * 0.02, 0.3, GRAVEL, Enum.Material.Pebble)
	end
	for k = 1, n do
		cylinder(parent, "PathBend", width, 0.3, CFrame.new(points[k].X, 0.09 + lift - 0.15, points[k].Z), GRAVEL, Enum.Material.Pebble)
	end
end

-- The round path along the pond's shore.
local function loopPoints()
	local pts = {}
	for i = 0, 39 do
		local a = i / 40 * TAU
		table.insert(pts, polar(a, pondR(a) + 8))
	end
	return pts
end

-- A winding path from the shore path out along angle a0, from radius r0 to r1. It sways gently
-- between the booths (where there's little room) and more out on the lawns.
local function windingPoints(a0, r0, r1, sway)
	local pts = {}
	local side = polar(a0 + math.pi / 2, 1)
	local n = 14
	for i = 0, n do
		local r = r0 + (r1 - r0) * i / n
		local roomy = math.clamp((r - 66) / 12, 0, 1)
		local lateral = sway * (0.45 + 0.55 * roomy) * math.sin(2 * math.pi * i / n)
		if r1 > 110 then
			-- (the paths to the glass doors run straight for their last stretch, on the door's axis,
			-- so the hedged avenue lines up with the doors)
			local t = math.clamp((r - 74) / 16, 0, 1)
			lateral *= 1 - t * t * (3 - 2 * t)
		end
		table.insert(pts, polar(a0, r) + side * lateral)
	end
	return pts
end

---------------------------------------------------------------------------
-- Trees
---------------------------------------------------------------------------

local function oak(parent, at, s, rng)
	local m = make("Model", { Name = "Oak" }, parent)
	local h = 8 * s
	local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	cylinder(m, "Trunk", 2.3 * s, h, cf * CFrame.new(0, h / 2, 0), BARK, Enum.Material.Wood)
	for b = 1, 3 do
		local a = b / 3 * TAU
		local from = cf * Vector3.new(0, h * 0.75, 0)
		local to = cf * Vector3.new(math.sin(a) * 3.6 * s, h + 1.6 * s, math.cos(a) * 3.6 * s)
		beam(m, "Branch", from, to, 0.9 * s, BARK, Enum.Material.Wood)
	end
	local g = OAK_GREENS[rng:NextInteger(1, #OAK_GREENS)]
	ball(m, "Leaves", 10 * s, cf * CFrame.new(0, h + 3.4 * s, 0), g, Enum.Material.Grass, LEAVES)
	for k = 1, 6 do
		local a = k / 6 * TAU + rng:NextNumber(-0.3, 0.3)
		local d = rng:NextNumber(6.5, 8.5) * s
		local shade = g:Lerp(k % 2 == 0 and rgb(0, 0, 0) or rgb(255, 255, 200), rng:NextNumber(0.03, 0.12))
		ball(m, "Leaves", d, cf * CFrame.new(math.sin(a) * 5 * s, h + rng:NextNumber(1.2, 3.2) * s, math.cos(a) * 5 * s), shade, Enum.Material.Grass, LEAVES)
	end
	Kit.dress(m, "Oak", cf, s, { Leaves = g })
	return m
end

local function maple(parent, at, s, rng, red)
	local m = make("Model", { Name = "Maple" }, parent)
	local h = 7 * s
	local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	cylinder(m, "Trunk", 1.6 * s, h, cf * CFrame.new(0, h / 2, 0), rgb(104, 82, 64), Enum.Material.Wood)
	local palette = red and MAPLE_REDS or MAPLE_GREENS
	local g = palette[rng:NextInteger(1, #palette)]
	ball(m, "Leaves", 9 * s, cf * CFrame.new(0, h + 3.4 * s, 0), g, Enum.Material.Grass, LEAVES)
	for k = 1, 5 do
		local a = k / 5 * TAU + rng:NextNumber(-0.3, 0.3)
		local shade = g:Lerp(k % 2 == 0 and rgb(0, 0, 0) or rgb(255, 255, 210), rng:NextNumber(0.03, 0.1))
		ball(m, "Leaves", rng:NextNumber(5.5, 7) * s, cf * CFrame.new(math.sin(a) * 3.8 * s, h + rng:NextNumber(1.5, 4) * s, math.cos(a) * 3.8 * s), shade, Enum.Material.Grass, LEAVES)
	end
	Kit.dress(m, "Maple", cf, s, { Leaves = g })
	return m
end

-- The lowest ground within r of p (so something wide stands on the low side of a slope).
local function lowGround(p, r)
	local lo = Kit.groundY(p.X, p.Z)
	for k = 0, 5 do
		local a = k / 6 * TAU
		lo = math.min(lo, Kit.groundY(p.X + math.sin(a) * r, p.Z + math.cos(a) * r))
	end
	return lo
end

-- A far-off tree for the woods round the park (fewer parts).
local function backTree(parent, at, s, rng)
	local m = make("Model", { Name = "Tree" }, parent)
	local h = 9 * s
	cylinder(m, "Trunk", 2 * s, h, CFrame.new(at) * CFrame.new(0, h / 2, 0), BARK, Enum.Material.Wood)
	local g = OAK_GREENS[rng:NextInteger(1, #OAK_GREENS)]:Lerp(rgb(40, 70, 40), 0.15)
	ball(m, "Leaves", 12 * s, CFrame.new(at) * CFrame.new(0, h + 3 * s, 0), g, Enum.Material.Grass, LEAVES)
	ball(m, "Leaves", 8 * s, CFrame.new(at) * CFrame.new(3.5 * s, h + 1 * s, 1.5 * s), g:Lerp(rgb(0, 0, 0), 0.08), Enum.Material.Grass, LEAVES)
	ball(m, "Leaves", 8 * s, CFrame.new(at) * CFrame.new(-3 * s, h + 1.8 * s, -2 * s), g:Lerp(rgb(255, 255, 200), 0.06), Enum.Material.Grass, LEAVES)
	Kit.dress(m, "Tree", CFrame.new(at + Vector3.new(0, lowGround(at, 1.4 * s) - 0.4, 0)) * CFrame.Angles(0, (at.X * 0.37 + at.Z * 0.91) % TAU, 0), s, { Leaves = g })
	return m
end

-- A weeping willow: a leaning trunk, a round crown and long green strands hanging down to the
-- water. The strands are named "Strand" (the client sways them a little).
local function willow(parent, at, lean, s, rng)
	local m = make("Model", { Name = "Willow" }, parent)
	local h = 7.5 * s
	-- lean toward the pond (the middle)
	local toMiddle = (Vector3.new(0, 0, 0) - at)
	toMiddle = Vector3.new(toMiddle.X, 0, toMiddle.Z).Unit
	local top = at + toMiddle * (lean * s) + Vector3.new(0, h, 0)
	beam(m, "Trunk", at + Vector3.new(0, -0.5, 0), top, 1.7 * s, rgb(84, 70, 56), Enum.Material.Wood)
	local crown = top + Vector3.new(0, 1.2 * s, 0)
	local g = WILLOW_GREENS[1]
	ball(m, "Leaves", 7 * s, CFrame.new(crown), g, Enum.Material.Grass, LEAVES)
	for k = 1, 5 do
		local a = k / 5 * TAU
		ball(m, "Leaves", 5.5 * s, CFrame.new(crown + polar(a, 3.2 * s) + Vector3.new(0, -0.6 * s, 0)), WILLOW_GREENS[k % 3 + 1], Enum.Material.Grass, LEAVES)
	end
	-- the hanging strands, in two rings round the crown
	for k = 1, 34 do
		local a = k / 34 * TAU + rng:NextNumber(-0.08, 0.08)
		local ring = (k % 2 == 0) and 5.4 or 4.2
		local hang = crown + polar(a, ring * s) + Vector3.new(0, -0.4 * s, 0)
		local len = rng:NextNumber(5.5, 8) * s
		local bottom = math.max(hang.Y - len, WATER + 0.6)
		local strand = part(m, "Strand", Vector3.new(0.35, hang.Y - bottom, 0.7), CFrame.lookAt(Vector3.new(hang.X, (hang.Y + bottom) / 2, hang.Z), Vector3.new(crown.X, (hang.Y + bottom) / 2, crown.Z)), WILLOW_GREENS[rng:NextInteger(1, #WILLOW_GREENS)], Enum.Material.Grass, LEAVES)
		strand:SetAttribute("Phase", rng:NextNumber(0, TAU))
	end
	local kcf = CFrame.lookAt(at, at + toMiddle) * CFrame.Angles(0, math.pi / 2, 0)
	if Kit.dress(m, "Willow", kcf, s, { Crown = g }) then
		Kit.willowStrands(m, kcf, s, WILLOW_GREENS, rng)
	end
	return m
end

-- The big old sycamore: a pale, patchy trunk and a wide crown to read under.
local function sycamore(parent, at)
	local m = make("Model", { Name = "Sycamore" }, parent)
	local h = 10
	local cf = CFrame.new(at)
	cylinder(m, "Trunk", 3.2, h, cf * CFrame.new(0, h / 2, 0), rgb(214, 206, 184), Enum.Material.Wood)
	-- the bark's peeled patches
	for k = 1, 9 do
		local a = k / 9 * TAU
		local y = 1.5 + (k * 1.07) % 7.5
		part(m, "Bark", Vector3.new(1.1, 1.6, 0.2), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, y, 1.55), k % 2 == 0 and rgb(150, 150, 120) or rgb(176, 160, 128), Enum.Material.Wood, NO_TOUCH)
	end
	for b = 1, 4 do
		local a = b / 4 * TAU + 0.4
		beam(m, "Branch", cf * Vector3.new(0, h * 0.7, 0), cf * Vector3.new(math.sin(a) * 7, h + 3, math.cos(a) * 7), 1.2, rgb(200, 192, 170), Enum.Material.Wood)
	end
	local g = rgb(88, 132, 60)
	ball(m, "Leaves", 13, cf * CFrame.new(0, h + 6, 0), g, Enum.Material.Grass, LEAVES)
	for k = 1, 9 do
		local a = k / 9 * TAU
		ball(m, "Leaves", k % 2 == 0 and 10 or 11.5, cf * CFrame.new(math.sin(a) * 8, h + 3.2 + (k % 3) * 0.9, math.cos(a) * 8), g:Lerp(k % 2 == 0 and rgb(0, 0, 0) or rgb(255, 255, 200), 0.08), Enum.Material.Grass, LEAVES)
	end
	Kit.dress(m, "Sycamore", cf, 1, { Leaves = g })
	return m
end

---------------------------------------------------------------------------
-- Little things: lamps, benches, blankets, flowers
---------------------------------------------------------------------------

-- An old black iron lamp post (dimly lit: it's daytime).
local function lamp(parent, at)
	local m = make("Model", { Name = "Lamp" }, parent)
	local cf = CFrame.new(at)
	cylinder(m, "Foot", 1.3, 0.8, cf * CFrame.new(0, 0.4, 0), IRON, Enum.Material.Metal)
	cylinder(m, "Post", 0.45, 9, cf * CFrame.new(0, 4.8, 0), IRON, Enum.Material.Metal)
	cylinder(m, "Collar", 0.8, 0.3, cf * CFrame.new(0, 9.2, 0), IRON, Enum.Material.Metal)
	local lantern = part(m, "Lantern", Vector3.new(1.2, 1.5, 1.2), cf * CFrame.new(0, 10.1, 0), rgb(255, 232, 186), Enum.Material.Glass, { Transparency = 0.2 })
	part(m, "Cap", Vector3.new(1.7, 0.3, 1.7), cf * CFrame.new(0, 11, 0), IRON, Enum.Material.Metal)
	ball(m, "Finial", 0.5, cf * CFrame.new(0, 11.35, 0), IRON, Enum.Material.Metal)
	light(lantern, rgb(255, 204, 140), 16, 0.7)
	Kit.dress(m, "Lamp", cf)
	return m
end

-- A weathered wooden bench with curved iron armrests, facing `look`.
local function bench(parent, at, look)
	local m = make("Model", { Name = "Bench" }, parent)
	local cf = CFrame.lookAt(at, Vector3.new(look.X, at.Y, look.Z))
	local wood = rgb(150, 134, 112)
	for s = 0, 2 do
		part(m, "Seat", Vector3.new(5.6, 0.22, 0.5), cf * CFrame.new(0, 1.75, -0.6 + s * 0.6), wood:Lerp(rgb(110, 100, 90), s * 0.12), Enum.Material.Wood)
	end
	for s = 0, 1 do
		part(m, "Backrest", Vector3.new(5.6, 0.45, 0.18), cf * CFrame.new(0, 2.5 + s * 0.65, 1.0 + s * 0.08) * CFrame.Angles(math.rad(-10), 0, 0), wood:Lerp(rgb(120, 110, 96), s * 0.1), Enum.Material.Wood)
	end
	for _, x in ipairs({ -1.3, 1.3 }) do
		local s = Instance.new("Seat") -- (sit down: two places on every bench)
		s.Name = "Seat"
		s.Anchored = true
		s.Size = Vector3.new(1.5, 0.2, 1.5)
		s.CFrame = CFrame.new(O) * cf * CFrame.new(x, 1.92, 0)
		s.Transparency = 1
		s.CanCollide = false
		s.Parent = m
	end
	for _, x in ipairs({ -2.6, 2.6 }) do
		-- the iron side: a leg in front, one behind, and a curved armrest
		part(m, "Leg", Vector3.new(0.2, 1.75, 0.2), cf * CFrame.new(x, 0.88, -0.7), IRON, Enum.Material.Metal)
		part(m, "Leg", Vector3.new(0.2, 3.4, 0.2), cf * CFrame.new(x, 1.7, 1.1) * CFrame.Angles(math.rad(-8), 0, 0), IRON, Enum.Material.Metal)
		local p0 = cf * Vector3.new(x, 1.8, -0.75)
		local p1 = cf * Vector3.new(x, 2.55, -0.85)
		local p2 = cf * Vector3.new(x, 2.75, -0.2)
		local p3 = cf * Vector3.new(x, 2.7, 0.9)
		beam(m, "Armrest", p0, p1, 0.2, IRON, Enum.Material.Metal)
		beam(m, "Armrest", p1, p2, 0.2, IRON, Enum.Material.Metal)
		beam(m, "Armrest", p2, p3, 0.2, IRON, Enum.Material.Metal)
	end
	Kit.dress(m, "Bench", cf)
	return m
end

-- A checked picnic blanket.
local function blanket(parent, at, angle, c1, c2)
	local m = make("Model", { Name = "Blanket" }, parent)
	local cf = CFrame.new(at) * CFrame.Angles(0, angle, 0)
	for i = 0, 4 do
		for j = 0, 3 do
			part(m, "Check", Vector3.new(1.4, 0.06, 1.4), cf * CFrame.new(-2.8 + i * 1.4, 0.05, -2.1 + j * 1.4), (i + j) % 2 == 0 and c1 or c2, Enum.Material.Fabric, { CanCollide = false })
		end
	end
	return m, cf
end

-- One plant in a flowerbed.
local function lavender(parent, cf, rng)
	if Kit.put("Lavender", parent, cf * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), rng:NextNumber(0.85, 1.15)) then
		return
	end
	part(parent, "LavenderLeaves", Vector3.new(1.2, 0.6, 1.2), cf * CFrame.new(0, 0.3, 0), rgb(110, 140, 100), Enum.Material.Grass, NO_TOUCH)
	for k = 1, 6 do
		local a = k / 6 * TAU
		local tip = Vector3.new(math.sin(a) * 0.5, 1.9 + rng:NextNumber(-0.2, 0.3), math.cos(a) * 0.5)
		part(parent, "Lavender", Vector3.new(0.18, 1.3, 0.18), cf * CFrame.new(tip.X * 0.6, tip.Y - 0.6, tip.Z * 0.6) * CFrame.Angles(tip.Z * 0.25, 0, -tip.X * 0.25), k % 2 == 0 and rgb(150, 118, 210) or rgb(126, 98, 190), Enum.Material.Fabric, NO_TOUCH)
	end
end

local function marigolds(parent, cf, rng)
	if Kit.put("Marigold", parent, cf * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), rng:NextNumber(0.85, 1.15)) then
		return
	end
	part(parent, "MarigoldLeaves", Vector3.new(1.4, 0.5, 1.4), cf * CFrame.new(0, 0.25, 0), rgb(84, 126, 60), Enum.Material.Grass, NO_TOUCH)
	for k = 1, 5 do
		local a = k / 5 * TAU + rng:NextNumber(0, 1)
		ball(parent, "Marigold", 0.55, cf * CFrame.new(math.sin(a) * 0.45, 0.7, math.cos(a) * 0.45), k % 2 == 0 and rgb(250, 160, 30) or rgb(255, 196, 40), Enum.Material.Fabric, NO_TOUCH)
	end
end

local HYDRANGEA = { rgb(120, 150, 230), rgb(200, 150, 220), rgb(236, 236, 250) }
local function hydrangea(parent, cf, rng, i)
	if Kit.put("Hydrangea", parent, cf * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), rng:NextNumber(0.9, 1.2), { Blooms = HYDRANGEA[(i % #HYDRANGEA) + 1] }) then
		return
	end
	ball(parent, "HydrangeaBush", 2, cf * CFrame.new(0, 0.6, 0), rgb(70, 116, 60), Enum.Material.Grass, NO_TOUCH)
	local c = HYDRANGEA[(i % #HYDRANGEA) + 1]
	for k = 1, 5 do
		local a = k / 5 * TAU + rng:NextNumber(0, 1)
		ball(parent, "Hydrangea", 0.95, cf * CFrame.new(math.sin(a) * 0.65, 1.3 + rng:NextNumber(0, 0.3), math.cos(a) * 0.65), c:Lerp(rgb(255, 255, 255), rng:NextNumber(0, 0.15)), Enum.Material.Fabric, NO_TOUCH)
	end
end



-- A patch of wildflowers in the lawn: a mix of two or three colors on thin green stems.
local FLOWERS = { rgb(250, 250, 244), rgb(255, 212, 60), rgb(116, 150, 238), rgb(232, 76, 66), rgb(238, 150, 200), rgb(196, 140, 236) }
local function wildflowers(parent, at, rng)
	local m = make("Model", { Name = "Wildflowers" }, parent)
	local mix = { FLOWERS[rng:NextInteger(1, #FLOWERS)], FLOWERS[rng:NextInteger(1, #FLOWERS)], FLOWERS[1] }
	if Kit.put("Wildflowers", m, CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), rng:NextNumber(0.85, 1.15), { BloomsA = mix[1], BloomsB = mix[2], BloomsC = mix[3] }) then
		return m
	end
	for _ = 1, 12 do
		local p = at + polar(rng:NextNumber(0, TAU), math.sqrt(rng:NextNumber()) * 3.4)
		local h = rng:NextNumber(0.6, 1.1)
		part(m, "Stem", Vector3.new(0.08, h, 0.08), CFrame.new(p + Vector3.new(0, h / 2, 0)), rgb(86, 132, 62), Enum.Material.Grass, NO_TOUCH)
		ball(m, "Flower", rng:NextNumber(0.34, 0.5), CFrame.new(p + Vector3.new(0, h, 0)), mix[rng:NextInteger(1, #mix)], Enum.Material.Fabric, NO_TOUCH)
	end
	return m
end

-- Reeds and cattails standing in the shallows.
local function reeds(parent, at, rng)
	if Kit.has("Reeds") then
		local clump = make("Model", { Name = "Reeds" }, parent)
		for _ = 1, 3 do
			local p = at + polar(rng:NextNumber(0, TAU), rng:NextNumber(0, 1.4))
			Kit.put("Reeds", clump, CFrame.new(p + Vector3.new(0, WATER - 0.6, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), rng:NextNumber(0.8, 1.15))
		end
		return clump
	end
	local m = make("Model", { Name = "Reeds" }, parent)
	for k = 1, 10 do
		local p = at + polar(rng:NextNumber(0, TAU), rng:NextNumber(0, 1.7))
		local h = rng:NextNumber(2.2, 3.8)
		local foot = CFrame.new(p + Vector3.new(0, WATER - 0.4, 0)) * CFrame.Angles(rng:NextNumber(-0.16, 0.16), rng:NextNumber(0, TAU), rng:NextNumber(-0.16, 0.16))
		if k % 3 == 0 then
			-- a cattail: a stalk with a brown head
			part(m, "Reed", Vector3.new(0.12, h, 0.12), foot * CFrame.new(0, h / 2, 0), rgb(104, 128, 64), Enum.Material.Grass, NO_TOUCH)
			part(m, "Cattail", Vector3.new(0.32, 0.9, 0.32), foot * CFrame.new(0, h - 0.6, 0), rgb(110, 72, 44), Enum.Material.Fabric, NO_TOUCH)
		else
			-- a long flat leaf
			part(m, "Reed", Vector3.new(0.06, h, 0.32), foot * CFrame.new(0, h / 2, 0), rgb(90, 130, 58):Lerp(rgb(150, 170, 80), rng:NextNumber(0, 0.4)), Enum.Material.Grass, NO_TOUCH)
		end
	end
	return m
end

-- Lily pads (and a flower or two) floating on the water.
local function lilies(parent, at, rng, n)
	local m = make("Model", { Name = "Lilies" }, parent)
	if Kit.has("LilyPad") then
		for k = 1, n do
			local p = at + polar(rng:NextNumber(0, TAU), rng:NextNumber(0, 2.4))
			local cf = CFrame.new(p + Vector3.new(0, WATER + 0.02 + k * 0.004, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			Kit.put("LilyPad", m, cf, rng:NextNumber(0.6, 1))
			if k % 3 == 1 then
				Kit.put("LilyFlower", m, cf, 1, { Flower = k % 2 == 0 and rgb(255, 250, 250) or rgb(248, 182, 210) })
			end
		end
		return m
	end
	for k = 1, n do
		local p = at + polar(rng:NextNumber(0, TAU), rng:NextNumber(0, 2.4))
		local d = rng:NextNumber(1.1, 1.9)
		cylinder(m, "LilyPad", d, 0.06, CFrame.new(p + Vector3.new(0, WATER + 0.04 + k * 0.004, 0)), rgb(70, 122, 58):Lerp(rgb(110, 150, 70), rng:NextNumber(0, 0.5)), Enum.Material.SmoothPlastic, NO_TOUCH)
		if k % 3 == 1 then
			local petals = k % 2 == 0 and rgb(255, 250, 250) or rgb(248, 182, 210)
			for j = 1, 5 do
				local a = j / 5 * TAU
				ball(m, "LilyPetal", 0.34, CFrame.new(p + polar(a, 0.2) + Vector3.new(0, WATER + 0.2, 0)), petals, Enum.Material.Fabric, NO_TOUCH)
			end
			ball(m, "LilyHeart", 0.2, CFrame.new(p + Vector3.new(0, WATER + 0.3, 0)), rgb(255, 214, 80), Enum.Material.Fabric, NO_TOUCH)
		end
	end
	return m
end

-- A clump of climbing roses: leaves with blooms among them.
local ROSES = { rgb(214, 46, 60), rgb(240, 120, 150), rgb(252, 236, 236), rgb(196, 30, 52) }
local function roses(parent, at, rng, n, spread)
	for k = 1, n do
		local off = Vector3.new(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread))
		if k % 2 == 0 then
			ball(parent, "Rose", rng:NextNumber(0.45, 0.7), CFrame.new(at + off), ROSES[rng:NextInteger(1, #ROSES)], Enum.Material.Fabric, NO_TOUCH)
		else
			ball(parent, "RoseLeaves", rng:NextNumber(0.8, 1.15), CFrame.new(at + off), rgb(58, 100, 50):Lerp(rgb(96, 136, 62), rng:NextNumber()), Enum.Material.Grass, NO_TOUCH)
		end
	end
end

-- A white iron arch grown over with roses, standing across a way through. `at` is the middle of the
-- way at ground level, `facing` the way through (flat), halfWidth from the middle to each post.
local function roseArch(parent, name, at, facing, halfWidth, postHeight, rise, rng)
	local m = make("Model", { Name = name }, parent)
	local right = Vector3.new(-facing.Z, 0, facing.X).Unit
	local depthOf = { -0.6, 0.6 }
	local tops = {}
	for d, depth in ipairs(depthOf) do
		local arc = {}
		for k = 0, 12 do
			local t = k / 12 * math.pi
			table.insert(arc, at + facing * depth + right * (-math.cos(t) * halfWidth) + Vector3.new(0, postHeight + math.sin(t) * rise, 0))
		end
		tops[d] = arc
		for _, s in ipairs({ -1, 1 }) do
			local base = at + facing * depth + right * (s * halfWidth)
			part(m, "Post", Vector3.new(0.3, postHeight, 0.3), CFrame.new(base + Vector3.new(0, postHeight / 2, 0)), WHITE_IRON, Enum.Material.Metal)
		end
		for k = 1, #arc - 1 do
			beam(m, "Arch", arc[k], arc[k + 1], 0.25, WHITE_IRON, Enum.Material.Metal)
		end
	end
	-- rungs between the two arches, and the roses climbing up and over
	for k = 1, 13, 2 do
		beam(m, "Rung", tops[1][k], tops[2][k], 0.16, WHITE_IRON, Enum.Material.Metal)
		roses(m, (tops[1][k] + tops[2][k]) / 2, rng, 5, 0.75)
	end
	for _, s in ipairs({ -1, 1 }) do
		for y = 0.8, postHeight - 0.4, 1.6 do
			roses(m, at + right * (s * halfWidth) + Vector3.new(0, y, 0), rng, 4, 0.6)
		end
	end
	return m, tops
end

-- A stone bird bath.
local function birdBath(parent, at)
	local m = make("Model", { Name = "BirdBath" }, parent)
	local c = CFrame.new(at)
	cylinder(m, "Foot", 2, 0.4, c * CFrame.new(0, 0.2, 0), STONE, Enum.Material.Slate)
	cylinder(m, "Pillar", 0.8, 2.6, c * CFrame.new(0, 1.7, 0), STONE:Lerp(rgb(255, 255, 255), 0.1), Enum.Material.Slate)
	cylinder(m, "Bowl", 3, 0.5, c * CFrame.new(0, 3.2, 0), STONE:Lerp(rgb(255, 255, 255), 0.15), Enum.Material.Slate)
	cylinder(m, "BathWater", 2.5, 0.05, c * CFrame.new(0, 3.47, 0), rgb(90, 140, 150), Enum.Material.SmoothPlastic, { Reflectance = 0.4, CanCollide = false })
	return m
end

-- A dark green litter bin.
local function bin(parent, at)
	local m = make("Model", { Name = "Bin" }, parent)
	cylinder(m, "Bin", 1.3, 2.3, CFrame.new(at + Vector3.new(0, 1.15, 0)), rgb(42, 72, 54), Enum.Material.Metal)
	cylinder(m, "Lid", 1.5, 0.22, CFrame.new(at + Vector3.new(0, 2.4, 0)), rgb(34, 58, 44), Enum.Material.Metal)
	return m
end

-- A clipped box topiary (two balls) in a stone planter.
local function topiary(parent, at)
	local m = make("Model", { Name = "Topiary" }, parent)
	part(m, "Planter", Vector3.new(2, 1.4, 2), CFrame.new(at + Vector3.new(0, 0.7, 0)), STONE:Lerp(rgb(255, 255, 255), 0.2), Enum.Material.Slate)
	part(m, "PlanterRim", Vector3.new(2.3, 0.25, 2.3), CFrame.new(at + Vector3.new(0, 1.45, 0)), STONE:Lerp(rgb(255, 255, 255), 0.3), Enum.Material.Slate)
	ball(m, "Box", 2.5, CFrame.new(at + Vector3.new(0, 2.7, 0)), rgb(56, 104, 52), Enum.Material.Grass, NO_TOUCH)
	ball(m, "Box", 1.5, CFrame.new(at + Vector3.new(0, 4.3, 0)), rgb(62, 112, 56), Enum.Material.Grass, NO_TOUCH)
	return m
end

---------------------------------------------------------------------------
-- Cozy things: seats, little lanterns, string lights, a sleeping cat. The lanterns (parts named
-- "Lantern") and the string-light bulbs ("Bulb") are lit by the client as it gets dark.
---------------------------------------------------------------------------

-- A seat you can sit on (invisible, on top of a bench or a log), facing along cf's look.
local function seat(parent, cf)
	local s = Instance.new("Seat")
	s.Name = "Seat"
	s.Anchored = true
	s.Size = Vector3.new(1.5, 0.2, 1.5)
	s.CFrame = CFrame.new(O) * cf
	s.Transparency = 1
	s.CanCollide = false
	s.TopSurface = Enum.SurfaceType.Smooth
	s.BottomSurface = Enum.SurfaceType.Smooth
	s.Parent = parent
	return s
end

-- A small glass lantern with a candle in it, standing at `at`.
local function lantern(parent, at, size)
	size = size or 1
	local m = make("Model", { Name = "SmallLantern" }, parent)
	part(m, "LanternBase", Vector3.new(0.7, 0.12, 0.7) * size, CFrame.new(at + Vector3.new(0, 0.06 * size, 0)), IRON, Enum.Material.Metal, NO_TOUCH)
	local glass = part(m, "Lantern", Vector3.new(0.55, 0.75, 0.55) * size, CFrame.new(at + Vector3.new(0, 0.5 * size, 0)), rgb(255, 232, 186), Enum.Material.Glass, merge(NO_TOUCH, { Transparency = 0.25 }))
	part(m, "LanternCap", Vector3.new(0.75, 0.14, 0.75) * size, CFrame.new(at + Vector3.new(0, 0.94 * size, 0)), IRON, Enum.Material.Metal, NO_TOUCH)
	ball(m, "LanternRing", 0.24 * size, CFrame.new(at + Vector3.new(0, 1.1 * size, 0)), IRON, Enum.Material.Metal, NO_TOUCH)
	light(glass, rgb(255, 190, 110), 10 * size, 0.3)
	return m, glass
end

-- A string of warm little bulbs hanging between two points (sagging in the middle).
local function stringLights(parent, a, b, sag)
	local m = make("Model", { Name = "StringLights" }, parent)
	local n = math.max(2, math.floor((b - a).Magnitude / 1.7))
	local prev = a
	for k = 1, n do
		local t = k / n
		local p = a + (b - a) * t - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		beam(m, "Wire", prev, p, 0.05, rgb(34, 30, 28), Enum.Material.SmoothPlastic, NO_TOUCH)
		if k < n then
			local bulb = ball(m, "Bulb", 0.34, CFrame.new(p - Vector3.new(0, 0.22, 0)), rgb(255, 238, 206), Enum.Material.Glass, merge(NO_TOUCH, { Transparency = 0.15, CastShadow = false }))
			if k % 4 == 2 then
				light(bulb, rgb(255, 196, 124), 8, 0)
			end
		end
		prev = p
	end
	return m
end

-- A ginger cat, curled up asleep (on a bench, in the sun).
local function sleepingCat(parent, cf)
	local m = make("Model", { Name = "Cat" }, parent)
	local fur, dark = rgb(232, 150, 70), rgb(196, 112, 50)
	egg(m, "Body", Vector3.new(1.3, 0.6, 1.0), cf * CFrame.new(0, 0.3, 0), fur)
	egg(m, "Head", Vector3.new(0.62, 0.52, 0.58), cf * CFrame.new(-0.52, 0.42, -0.3), fur)
	for _, x in ipairs({ -0.16, 0.16 }) do
		part(m, "Ear", Vector3.new(0.16, 0.2, 0.08), cf * CFrame.new(-0.52 + x, 0.72, -0.3) * CFrame.Angles(0, 0, x > 0 and -0.3 or 0.3), dark, Enum.Material.SmoothPlastic, NO_TOUCH)
	end
	egg(m, "Muzzle", Vector3.new(0.3, 0.2, 0.2), cf * CFrame.new(-0.58, 0.34, -0.55), rgb(250, 230, 210))
	for k = 0, 3 do
		local a = math.rad(200 - k * 50)
		egg(m, "Tail", Vector3.new(0.26, 0.24, 0.42), cf * CFrame.new(math.cos(a) * 0.62, 0.22, math.sin(a) * 0.52) * CFrame.Angles(0, -a, 0), k % 2 == 0 and fur or dark)
	end
	for _, x in ipairs({ -0.1, 0.1 }) do
		part(m, "Stripe", Vector3.new(0.9, 0.04, 0.12), cf * CFrame.new(0.15 + x * 2, 0.6, 0) * CFrame.Angles(0, 0, 0.1), dark, Enum.Material.SmoothPlastic, NO_TOUCH)
	end
	return m
end

---------------------------------------------------------------------------
-- The pond, the island and the bridge
---------------------------------------------------------------------------

local BRIDGE_FROM, BRIDGE_TO = ISLAND - 2, pondR(0) + 3.2 -- along +z (toward the Home gate)
local BRIDGE_HALF = 3

local function bridgeTop(z)
	local t = math.clamp((z - BRIDGE_FROM) / (BRIDGE_TO - BRIDGE_FROM), 0, 1)
	return 0.45 + 2.2 * math.sin(math.pi * t) -- (high enough in the middle for the ducks)
end

-- The discs the pond is made of: { x, z, radius } (one wide one in the middle and a ring of
-- small ones following the shore).
local function pondDiscs()
	local out = { { 0, 0, 27 } }
	for i = 0, 47 do
		local a = i / 48 * TAU
		local p = polar(a, pondR(a) - 7)
		table.insert(out, { p.X, p.Z, 7 })
	end
	return out
end

local function buildPond(root, terrainMade)
	local m = make("Model", { Name = "Pond" }, root)
	if not terrainMade then
		-- (no terrain: the water is a flat mirror of parts, the island a low mound of grass)
		local water = rgb(56, 96, 90)
		local W = { Reflectance = 0.4, CanCollide = false, CanQuery = false, CastShadow = false }
		for _, disc in ipairs(pondDiscs()) do
			cylinder(m, "Water", disc[3] * 2, 0.4, CFrame.new(disc[1], WATER - 0.2, disc[2]), water, Enum.Material.SmoothPlastic, W)
		end
		cylinder(m, "Island", ISLAND * 2, 1, CFrame.new(0, -0.05, 0), GRASS, Enum.Material.Grass)
	end
	-- smooth river stones round the shore and the island (none where the stepping stones land)
	local rng = Random.new(31)
	local function nearSteps(a)
		local d = (a - math.rad(STEPPING_DEG) + math.pi) % TAU - math.pi
		return math.abs(d) < 0.09
	end
	local stones = make("Model", { Name = "Stones" }, m)
	-- The ground as actually painted (terrain is drawn in 4-stud blocks, so the real water's edge
	-- wanders a little from the planned shore): its height, and whether it's water there.
	local function cast(x, z)
		local ok, hit = pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { workspace.Terrain }
			params.IgnoreWater = false
			return workspace:Raycast(O + Vector3.new(x, 40, z), Vector3.new(0, -80, 0), params)
		end)
		return ok and hit or nil
	end
	-- freshly painted terrain can't be hit by a ray straight away: wait (a few seconds at most)
	-- until the middle of the pond answers
	local painted = false
	if terrainMade then
		for _ = 1, 60 do
			local probe = cast(0, pondR(0) - 6)
			if probe then
				painted = true
				break
			end
			task.wait(0.1)
		end
	end
	local function realGround(x, z)
		local hit = painted and cast(x, z) or nil
		if not hit then
			return Kit.groundY(x, z), false
		end
		return hit.Position.Y - O.Y, hit.Material == Enum.Material.Water
	end
	-- Steps from radius r0 along angle a (outward when step > 0) until a stone d wide stands on dry
	-- ground across its whole width. Returns the spot and the lowest ground under it, or nil.
	local function dryRing(a, r0, d, step, limit)
		local half = d * 0.62
		for k = 0, math.floor(limit / math.abs(step)) do
			local r = r0 + k * step
			local lo, dry = math.huge, true
			for _, off in ipairs({ -half, 0, half }) do
				for _, side in ipairs({ -1, 1 }) do
					local p = polar(a + side * half / math.max(r, 1) * 0.7, r + off)
					local y, wet = realGround(p.X, p.Z)
					if wet or y < WATER + 0.15 then
						dry = false
					end
					lo = math.min(lo, y)
				end
			end
			if dry then
				return polar(a, r), lo
			end
		end
		return nil
	end
	local function stone(at, ground, d)
		local grey = rng:NextNumber(140, 196)
		if Kit.has("StoneA") then
			local name = d > 2.2 and "StoneA" or (d > 1.5 and "StoneB" or "StoneC")
			local wide = d > 2.2 and 3.1 or (d > 1.5 and 1.9 or 1.3)
			Kit.put(name, stones, CFrame.new(at.X, ground - 0.15, at.Z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), d / wide * 1.15, { Stone = rgb(grey, grey - 4, grey - 12) })
			return
		end
		ball(stones, "Stone", d, CFrame.new(at.X, ground - d / 2 + rng:NextNumber(0.5, 0.75), at.Z), rgb(grey, grey - 4, grey - 12), Enum.Material.SmoothPlastic)
	end
	local a = 0
	while a < TAU do
		local r = pondR(a)
		local inBridge = math.abs(math.sin(a) * r) < BRIDGE_HALF + 1 and math.cos(a) > 0
		if not inBridge and not nearSteps(a) then
			-- on the dry pebbly shore, the first dry spot out from the water (never in it)
			local d = rng:NextNumber(1.8, 2.6)
			local at, ground = dryRing(a, r + 0.5 + d * 0.5, d, 0.35, 6)
			if at then
				stone(at, ground, d)
				local d2 = rng:NextNumber(1.1, 1.5)
				local outer = (Vector3.new(at.X, 0, at.Z)).Magnitude + d * 0.55 + d2 * 0.5
				if rng:NextNumber() < 0.45 and outer + d2 * 0.6 < r + 4.3 then -- (not out on the path)
					local at2, ground2 = dryRing(a + 0.02, outer, d2, 0.3, 0.6)
					if at2 then
						stone(at2, ground2, d2)
					end
				end
			end
		end
		a += 2.1 / r
	end
	a = 0
	while a < TAU do
		local inBridge = math.abs(math.sin(a) * ISLAND) < BRIDGE_HALF + 0.6 and math.cos(a) > 0
		if not inBridge and not nearSteps(a) then
			-- round the island's edge, stepping in from the water until dry (and clear of the altar)
			local d = rng:NextNumber(1.5, 2.1)
			local at, ground = dryRing(a, ISLAND - d * 0.4, d, -0.3, 2.5)
			if at and Vector3.new(at.X, 0, at.Z).Magnitude - d * 0.6 > 9.4 then
				stone(at, ground, d)
			end
		end
		a += 2 / ISLAND
	end
	-- reeds in the shallows and lily pads in the quiet corners
	local plants = make("Model", { Name = "WaterPlants" }, m)
	for _, deg in ipairs({ 24, 82, 160, 246, 322 }) do
		local ang = math.rad(deg)
		reeds(plants, polar(ang, pondR(ang) - 1.2), rng)
	end
	for _, spot in ipairs({ { 108, -1.9, 7 }, { 268, -2, 8 }, { 180, -1.8, 5 } }) do
		local ang = math.rad(spot[1])
		lilies(plants, polar(ang, pondR(ang) + spot[2]), rng, spot[3])
	end
	lilies(plants, polar(math.rad(140), ISLAND + 2.4), rng, 4)
	-- no walls round the water: it's a real pond (wade in at the shore, swim in the middle), and
	-- a line of flat stepping stones crosses to the island on the far side from the bridge
	local hop = make("Model", { Name = "SteppingStones" }, m)
	do
		local a = math.rad(STEPPING_DEG)
		local from, to = pondR(a) - 1.4, ISLAND + 1.6
		local n = math.max(3, math.ceil((from - to) / 3.4))
		for k = 0, n do
			local r = from + (to - from) * k / n
			local at = polar(a + (k % 2 == 0 and 0.025 or -0.025), r)
			local top = WATER + 0.45
			local d = 2.7 + (k % 3) * 0.25
			cylinder(hop, "Step", d * 0.85, 1.6, CFrame.new(at.X, top - 0.8, at.Z), rgb(150, 146, 136), Enum.Material.Slate, { Transparency = Kit.has("StoneA") and 1 or 0 })
			if Kit.has("StoneA") then
				local y = top + 0.05 - 0.348 * d -- (the stone's crown level with the step you stand on)
				local s = Kit.put("StoneA", hop, CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, k * 1.9, 0), d / 3.1 * 1.05, { Stone = rgb(158, 154, 144) })
				-- its foot, down to the pond bed (so it doesn't float in the water)
				local bed, foot = Kit.groundY(at.X, at.Z), y + 0.3
				if foot - bed > 0.5 then
					cylinder(hop, "Footing", d * 0.72, foot - bed, CFrame.new(at.X, (foot + bed) / 2, at.Z), rgb(98, 100, 90), Enum.Material.Slate, NO_TOUCH)
				end
				for _, p in ipairs(s and s:GetDescendants() or {}) do
					if p:IsA("BasePart") then
						p.CanCollide = false -- (the plain step underneath is what you stand on)
					end
				end
			end
		end
	end
	-- the low arched wooden bridge
	local bridge = make("Model", { Name = "Bridge" }, m)
	local wood = rgb(140, 104, 72)
	local steps = 14
	local function at(z, y, x)
		return Vector3.new(x or 0, y, z)
	end
	for k = 0, steps - 1 do
		local z0 = BRIDGE_FROM + (BRIDGE_TO - BRIDGE_FROM) * k / steps
		local z1 = BRIDGE_FROM + (BRIDGE_TO - BRIDGE_FROM) * (k + 1) / steps
		local y0, y1 = bridgeTop(z0) - 0.18, bridgeTop(z1) - 0.18
		local cf = CFrame.lookAt(at((z0 + z1) / 2, (y0 + y1) / 2), at(z1, y1))
		part(bridge, "Deck", Vector3.new(BRIDGE_HALF * 2, 0.36, (at(z1, y1) - at(z0, y0)).Magnitude + 0.05), cf, wood:Lerp(rgb(110, 80, 56), (k % 2) * 0.15), Enum.Material.WoodPlanks)
	end
	-- the arched beams underneath and the rails on both sides
	for _, x in ipairs({ -BRIDGE_HALF + 0.3, BRIDGE_HALF - 0.3 }) do
		for k = 0, steps - 1 do
			local z0 = BRIDGE_FROM + (BRIDGE_TO - BRIDGE_FROM) * k / steps
			local z1 = BRIDGE_FROM + (BRIDGE_TO - BRIDGE_FROM) * (k + 1) / steps
			beam(bridge, "Beam", at(z0, bridgeTop(z0) - 0.6, x), at(z1, bridgeTop(z1) - 0.6, x), 0.5, rgb(100, 74, 52), Enum.Material.Wood)
		end
	end
	for _, x in ipairs({ -BRIDGE_HALF + 0.15, BRIDGE_HALF - 0.15 }) do
		local prev = nil
		for k = 0, steps, 2 do
			local z = BRIDGE_FROM + (BRIDGE_TO - BRIDGE_FROM) * k / steps
			local top = bridgeTop(z)
			part(bridge, "Post", Vector3.new(0.35, 2.5, 0.35), CFrame.new(x, top + 1.1, z), rgb(110, 80, 56), Enum.Material.Wood)
			if k == 0 or k == steps then
				lantern(bridge, Vector3.new(x + (x > 0 and 0.1 or -0.1), top + (Kit.has("Bridge") and 3.36 or 2.38), z), 0.8)
			end
			local railAt = at(z, top + 2.35, x)
			if prev then
				beam(bridge, "Rail", prev, railAt, 0.3, rgb(150, 112, 78), Enum.Material.Wood)
			end
			prev = railAt
		end
		-- (an invisible wall along each side, so nobody hops off into the pond)
	end
	Kit.dress(bridge, "Bridge", CFrame.new())
	-- a rose arch where the bridge meets the shore
	roseArch(m, "RoseArch", Vector3.new(0, 0, BRIDGE_TO - 0.9), Vector3.new(0, 0, 1), BRIDGE_HALF + 0.75, 7, 2.2, rng)
	-- the ducks
	local ducks = make("Model", { Name = "Ducks" }, m)
	local KINDS = {
		{ body = rgb(150, 140, 124), chest = rgb(120, 72, 52), head = rgb(36, 104, 62) }, -- mallard
		{ body = rgb(246, 244, 236), chest = rgb(240, 238, 228), head = rgb(246, 244, 236) }, -- white
		{ body = rgb(150, 116, 82), chest = rgb(140, 106, 74), head = rgb(140, 106, 74) }, -- brown hen
	}
	for i = 1, 5 do
		local kind = KINDS[(i - 1) % #KINDS + 1]
		local d = make("Model", { Name = "Duck" .. i }, ducks)
		local ang = i / 5 * TAU
		local base = CFrame.new(polar(ang, (ISLAND + pondR(ang)) / 2) + Vector3.new(0, WATER, 0)) * CFrame.Angles(0, ang + math.pi / 2, 0)
		local body = egg(d, "Body", Vector3.new(0.95, 0.6, 1.45), base * CFrame.new(0, 0.2, 0.05), kind.body)
		egg(d, "Chest", Vector3.new(0.8, 0.6, 0.7), base * CFrame.new(0, 0.3, -0.45), kind.chest)
		egg(d, "Tail", Vector3.new(0.5, 0.35, 0.6), base * CFrame.new(0, 0.42, 0.7) * CFrame.Angles(math.rad(25), 0, 0), kind.body:Lerp(rgb(0, 0, 0), 0.15))
		egg(d, "Head", Vector3.new(0.5, 0.52, 0.55), base * CFrame.new(0, 0.85, -0.62), kind.head)
		egg(d, "Beak", Vector3.new(0.24, 0.12, 0.36), base * CFrame.new(0, 0.8, -0.98), rgb(248, 178, 40))
		for _, x in ipairs({ -0.2, 0.2 }) do
			egg(d, "Eye", Vector3.new(0.09, 0.09, 0.09), base * CFrame.new(x, 0.92, -0.78), rgb(20, 20, 20))
		end
		local dressed = Kit.dress(d, "Duck", base, 1, { Body = kind.body, Head = kind.head }, true)
		body = dressed and dressed.Body or body
		body:SetAttribute("Lane", i)
		d:SetAttribute("Lane", i)
	end
	return m
end

---------------------------------------------------------------------------
-- The layout
---------------------------------------------------------------------------

-- Where the four winding paths go (from the shore path out): { angle, to radius, sway }
local PATHS = {
	{ a = 0, to = 124, sway = 6 }, -- south, to the Home door in the glass
	{ a = -math.pi / 2, to = 124, sway = 5 }, -- west, to the Campaign door in the glass
	{ a = math.rad(128), to = 84, sway = 4 }, -- north-east, to the Hall of Pulls
	{ a = math.pi / 2, to = 71, sway = 3 }, -- east, to the gazebo's steps
	{ a = math.rad(152), to = 42.5, sway = 0 }, -- up the steps of the Top Collector's terrace
	{ a = math.rad(240), to = 102, sway = 3 }, -- past the sycamore to the Trading Post
}
local GAZEBO = Vector3.new(84, 0, 0)
-- The Top Collector's terrace: on the far shore, a little off to the side of the island (so the
-- altar never hides it), turned to face you as you walk in from the Home gate.
local TERRACE = polar(math.rad(152), 57)
local TERRACE_FACING = (Vector3.new(0, 0, 100) - TERRACE).Unit
local TERRACE_TOP = 1
local HALL = polar(math.rad(128), 92) -- (north-east, behind the trees: out of the view from the gate)
local HALL_FRONT = -HALL.Unit
local HALL_SIDE = Vector3.new(-HALL_FRONT.Z, 0, HALL_FRONT.X)
local SYCAMORE = polar(math.rad(232), 90)
local BLANKET1 = SYCAMORE + Vector3.new(7, 0, 5)
local BLANKET2 = polar(math.rad(302), 90)
local BIRDBATH = SYCAMORE + Vector3.new(16, 0, 14)
local CAMPFIRE = polar(math.rad(48), 80) -- a campfire circle on the south-east lawn
local TRADING = polar(math.rad(240), 112) -- the Trading Post, on the west lawn beyond the sycamore
local ALCOVES = { 30, 60, 120, 150, 210, 300, 330 } -- quiet nooks round the edge, degrees
local SHORE_LAMPS = { 35, 100, 140, 173, 222, 260, 306, 325 } -- (none in the way of the paths or the terrace; 306 lights the stepping stones)
local SHORE_BENCHES = { 42, 180, 215, 318 }

-- The leaderboards stand either side of the Hall of Pulls.
local function boardSpot(i)
	return HALL + HALL_SIDE * ((i % 2 == 1) and 21 or -21) + HALL_FRONT * (3 + math.floor((i - 1) / 2) * 6)
end

local function shoreSpot(deg, out)
	local a = math.rad(deg)
	return polar(a, pondR(a) + out)
end

local function allPathPoints()
	local list = {}
	for _, p in ipairs(PATHS) do
		table.insert(list, windingPoints(p.a, pondR(p.a) + 8, p.to, p.sway))
	end
	return list
end

-- Spots that trees and flowers keep away from: { point, radius }.
local function keepClear(pathPoints)
	local list = {}
	local function add(p, r)
		table.insert(list, { Vector3.new(p.X, 0, p.Z), r })
	end
	for _, pts in ipairs(pathPoints) do
		for _, q in ipairs(pts) do
			add(q, 9.5)
		end
	end
	for _, q in ipairs(loopPoints()) do
		add(q, 10)
	end
	for _, deg in ipairs(SHORE_LAMPS) do
		add(shoreSpot(deg, 12.6), 6)
	end
	for _, deg in ipairs(SHORE_BENCHES) do
		add(shoreSpot(deg, 13.2), 8)
	end
	add(TERRACE, 25)
	add(HALL, 18)
	add(HALL + HALL_FRONT * 16, 16)
	add(GAZEBO, 22)
	add(SYCAMORE, 22)
	add(BLANKET2, 12)
	add(BIRDBATH, 8)
	add(CAMPFIRE, 15)
	add(TRADING, 21)
	add(Vector3.new(0, 0, 116), 16) -- the doors out
	add(Vector3.new(-116, 0, 0), 16)
	for i = 1, #Park.Boards do
		add(boardSpot(i), 13)
	end
	for _, deg in ipairs(ALCOVES) do
		add(polar(math.rad(deg), 118), 11)
	end
	return list
end

local function isClear(p, clear, taken, gap)
	if math.abs(p.X) < 34 and p.Z < -64 then
		return false -- the Hall of Pulls and its boards, and the view of them across the pond
	end
	if math.abs(p.X) < 24 and p.Z > 36 then
		return false -- the view from the Home gate, over the lawn to the pond and the island
	end
	for _, c in ipairs(clear) do
		if (c[1] - p).Magnitude < c[2] then
			return false
		end
	end
	for _, q in ipairs(taken) do
		if (q - p).Magnitude < gap then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- The ground (terrain when there is some to paint, parts otherwise), paths and the edge
---------------------------------------------------------------------------

-- Paints the park's ground into the place's terrain: a lawn of real grass, the pond as real water
-- over mud, the island a little higher, and worn ground under the gravel paths (so no grass blades
-- poke through them). Returns true if it worked.
local function terrainGround(terrain, pathPoints)
	do
		return Kit.paintGround(terrain, O, { pondR = pondR, island = ISLAND, loop = loopPoints(), paths = pathPoints })
	end
	local M = Enum.Material
	local function at(x, y, z)
		return CFrame.new(O + Vector3.new(x, y, z))
	end
	terrain:FillCylinder(at(0, -6, 0), 12, 196, M.Grass) -- (down to -12, the top at 0)
	for _, disc in ipairs(pondDiscs()) do
		terrain:FillCylinder(at(disc[1], -6, disc[2]), 4, disc[3], M.Mud)
		terrain:FillCylinder(at(disc[1], -2, disc[2]), 4, disc[3], M.Water)
	end
	terrain:FillCylinder(at(0, -1.75, 0), 4.5, ISLAND, M.Grass)
	local function worn(a, b, width)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(O + Vector3.new(mid.X, -2, mid.Z), O + Vector3.new(b.X, -2, b.Z))
		terrain:FillBlock(cf, Vector3.new(width, 4, (b - a).Magnitude + 1), M.Ground)
	end
	local loop = loopPoints()
	for k = 1, #loop do
		worn(loop[k], loop[k % #loop + 1], 6)
	end
	for _, pts in ipairs(pathPoints) do
		for k = 1, #pts - 1 do
			worn(pts[k], pts[k + 1], 7)
		end
	end
	pcall(function()
		terrain:SetMaterialColor(M.Grass, rgb(96, 152, 70))
		terrain:SetMaterialColor(M.Ground, rgb(168, 152, 124))
		terrain:SetMaterialColor(M.Mud, rgb(66, 58, 46))
	end)
	-- a calm, clear, mirror-like pond
	for k, v in pairs({ WaterColor = rgb(48, 92, 86), WaterReflectance = 1, WaterTransparency = 0.45, WaterWaveSize = 0.04, WaterWaveSpeed = 6, Decoration = true }) do
		pcall(function()
			terrain[k] = v
		end)
	end
	return true
end

local function buildGround(root, pathPoints, terrainMade)
	local g = make("Model", { Name = "Ground" }, root)
	if not terrainMade then
		cylinder(g, "Grass", 380, 2, CFrame.new(0, -1, 0), GRASS, Enum.Material.Grass)
	end
	-- the gravel paths
	local paths = make("Model", { Name = "Paths" }, g)
	gravel(paths, loopPoints(), 7, 0, true)
	for i, pts in ipairs(pathPoints) do
		gravel(paths, pts, 8.5, 0.05 + i * 0.01, false)
	end
	-- the bridge's foot, onto the shore path
	strip(paths, "Path", Vector3.new(0, 0, BRIDGE_TO - 1.5), Vector3.new(0, 0, pondR(0) + 8), 6, 0.15, 0.3, GRAVEL, Enum.Material.Pebble)
	-- little round gravel squares at the gates
	cylinder(paths, "GateSquare", 16, 0.3, CFrame.new(0, 0.2 - 0.15, 110), GRAVEL, Enum.Material.Pebble)
	cylinder(paths, "GateSquare", 16, 0.3, CFrame.new(-110, 0.2 - 0.15, 0), GRAVEL, Enum.Material.Pebble)
	if terrainMade then
		paths:ClearAllChildren() -- (the paths are painted into the ground)
	end
	-- (the glasshouse's glass wall is the edge: see buildGlasshouse)
	-- a safety floor under everything
	part(g, "Under", Vector3.new(380, 2, 380), CFrame.new(0, -14, 0), rgb(60, 90, 50), Enum.Material.Grass, { Transparency = 1 })
end

---------------------------------------------------------------------------
-- The glasshouse: the whole park stands under a Victorian palm house of white iron and glass.
-- Its glass wall (radius GLASS_R) is where the park ends: you can see the woods outside but not
-- walk out. The roof is a shallow glass dome on white iron ribs with a little lantern on top.
-- After dark, uplights at the foot of the wall light the glass so you can see where it is.
---------------------------------------------------------------------------

local GLASS_R = 127.5 -- the glass wall's radius
local GLASS_BAYS = 32 -- bays round the wall (a bay is centred on the Home gate, a = 0)
local GLASS_TOP = 26 -- the top of the wall (the cornice)
local DOME_RISE = 42 -- how much higher the roof's crown is than the cornice
local DOME_STEPS = 8 -- roof sections from the cornice to the lantern ring
local DOME_TOP_R = 14 -- radius of the ring the lantern stands on
local GLASS_COLOR = rgb(214, 236, 232)
local GLASS_WALL = { Transparency = 0.84, Reflectance = 0.12, CastShadow = false }
local GLASS_ROOF = merge(NO_TOUCH, { Transparency = 0.88, Reflectance = 0.1, CastShadow = false })
local FRAME = WHITE_IRON
local LIMESTONE = rgb(206, 198, 180)

-- A point on the roof: rib angle a, section t (0 = cornice .. 1 = lantern ring).
local function domePoint(a, t)
	local thetaMax = math.acos(DOME_TOP_R / GLASS_R)
	local th = thetaMax * t
	return polar(a, GLASS_R * math.cos(th)) + Vector3.new(0, GLASS_TOP + 0.9 + DOME_RISE * math.sin(th), 0)
end

-- A row of beams along an arc in a vertical plane: from point a to point b, bulging up by `rise`.
local function arch(parent, name, a, b, rise, thick, color, n)
	local prev = a
	for k = 1, n do
		local t = k / n
		local p = a:Lerp(b, t) + Vector3.new(0, rise * math.sin(math.pi * t), 0)
		beam(parent, name, prev, p, thick, color, Enum.Material.Metal, NO_TOUCH)
		prev = p
	end
end

local function buildGlasshouse(root, terrainMade)
	local m = make("Model", { Name = "Glasshouse" }, root)
	local wall = make("Model", { Name = "Wall" }, m)
	local roof = make("Model", { Name = "Roof" }, m)
	local half = math.pi / GLASS_BAYS
	local doors = { [0] = "HomeDoor", [GLASS_BAYS * 3 / 4] = "CampaignGate" }
	local base = terrainMade and -1.6 or -0.2
	for i = 0, GLASS_BAYS - 1 do
		local c = i / GLASS_BAYS * TAU
		local p0, p1 = polar(c - half, GLASS_R), polar(c + half, GLASS_R)
		local mid = polar(c, GLASS_R * math.cos(half))
		local inward = -polar(c, 1)
		local face = CFrame.lookAt(mid, mid + inward) -- (looking into the park)
		local width = (p1 - p0).Magnitude
		-- the stone plinth and the glass above it
		part(wall, "Plinth", Vector3.new(width + 1.2, 1.4 - base + 1, 2.2), face * CFrame.new(0, (base - 1 + 1.4) / 2, 0), LIMESTONE, Enum.Material.Limestone)
		part(wall, "PlinthCap", Vector3.new(width + 1.4, 0.3, 2.6), face * CFrame.new(0, 1.55, 0), LIMESTONE:Lerp(rgb(255, 255, 255), 0.2), Enum.Material.Limestone, NO_TOUCH)
		part(wall, "Glass", Vector3.new(width, GLASS_TOP - 1.7, 0.3), face * CFrame.new(0, (GLASS_TOP + 1.7) / 2, 0), GLASS_COLOR, Enum.Material.SmoothPlastic, GLASS_WALL)
		-- the white ironwork: a mullion down the middle, two transoms, arched tops to each half
		part(wall, "Mullion", Vector3.new(0.45, GLASS_TOP - 1.7, 0.5), face * CFrame.new(0, (GLASS_TOP + 1.7) / 2, -0.1), FRAME, Enum.Material.Metal, NO_TOUCH)
		for _, y in ipairs({ 9.5, 17.5 }) do
			part(wall, "Transom", Vector3.new(width, 0.4, 0.5), face * CFrame.new(0, y, -0.1), FRAME, Enum.Material.Metal, NO_TOUCH)
		end
		for _, side in ipairs({ -1, 1 }) do
			local a = face * Vector3.new(side * width / 2, 19.5, -0.15)
			local b = face * Vector3.new(0, 19.5, -0.15)
			arch(wall, "Arch", side < 0 and a or b, side < 0 and b or a, width / 4 * 0.9, 0.32, FRAME, 6)
		end
		-- the cornice along the top
		part(wall, "Cornice", Vector3.new(width + 1.3, 1.2, 1.6), face * CFrame.new(0, GLASS_TOP + 0.3, 0), FRAME, Enum.Material.Metal, NO_TOUCH)
		-- the column between this bay and the next
		local colAt = polar(c + half, GLASS_R)
		local col = CFrame.lookAt(colAt, colAt - polar(c + half, 1))
		part(wall, "Column", Vector3.new(1.3, GLASS_TOP - 1.4, 1.3), col * CFrame.new(0, (GLASS_TOP + 1.4) / 2, -0.2), FRAME, Enum.Material.Metal)
		part(wall, "ColumnFoot", Vector3.new(2, 1.6, 2), col * CFrame.new(0, 2.3, -0.2), FRAME, Enum.Material.Metal, NO_TOUCH)
		part(wall, "Capital", Vector3.new(2.1, 0.7, 2.1), col * CFrame.new(0, GLASS_TOP - 0.7, -0.2), FRAME, Enum.Material.Metal, NO_TOUCH)
		-- an uplight at the foot of every other column (lights the glass after dark)
		if i % 2 == 0 then
			part(wall, "Uplight", Vector3.new(0.9, 0.5, 0.9), col * CFrame.new(0, 1.95, -1.6), rgb(150, 120, 80), Enum.Material.Metal, NO_TOUCH)
			local bulb = part(wall, "Lantern", Vector3.new(0.6, 0.12, 0.6), col * CFrame.new(0, 2.25, -1.6), rgb(255, 224, 170), Enum.Material.Glass, merge(NO_TOUCH, { CastShadow = false }))
			make("SpotLight", { Face = Enum.NormalId.Top, Angle = 40, Range = 30, Brightness = 1.6, Color = rgb(255, 214, 160), Shadows = false }, bulb)
		end
		-- a grand doorway behind each gate (glass doors, closed: the gates do the travelling)
		if doors[i] then
			local d = make("Model", { Name = "Doorway" }, wall)
			for _, x in ipairs({ -6.2, 6.2 }) do
				part(d, "DoorPost", Vector3.new(1.4, 15, 1.4), face * CFrame.new(x, 8.9, -0.6), FRAME, Enum.Material.Metal)
				local glow = part(d, "Lantern", Vector3.new(1, 1.3, 1), face * CFrame.new(x, 13.2, -1.6), rgb(255, 232, 186), Enum.Material.Glass, merge(NO_TOUCH, { Transparency = 0.2 }))
				light(glow, rgb(255, 206, 140), 14, 0.4)
			end
			arch(d, "DoorArch", face * Vector3.new(-6.2, 16.4, -0.6), face * Vector3.new(6.2, 16.4, -0.6), 3.4, 0.9, FRAME, 8)
			-- two tall glass doors in gold frames; they swing open (on each player's screen) when
			-- someone walks up to them. Every piece of a door carries its hinge: "Hinge" (which
			-- side) and "HingeAt" (the hinge's point), for the client to turn it about.
			local GOLD_TRIM = rgb(222, 178, 84)
			for _, x in ipairs({ -3.05, 3.05 }) do
				local side = x > 0 and 1 or -1
				local hinge = face * Vector3.new(x + side * 2.95, 8.6, -0.45)
				local function swing(p)
					p:SetAttribute("Hinge", side)
					p:SetAttribute("HingeAt", O + hinge)
					return p
				end
				swing(part(d, "Door", Vector3.new(5.9, 14.4, 0.25), face * CFrame.new(x, 8.6, -0.45), rgb(226, 240, 236), Enum.Material.SmoothPlastic, { Transparency = 0.5, Reflectance = 0.15, CastShadow = false }))
				for _, y in ipairs({ 1.6, 15.6 }) do
					swing(part(d, "DoorTrim", Vector3.new(5.9, 0.3, 0.35), face * CFrame.new(x, y, -0.5), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH))
				end
				for _, dx in ipairs({ -2.8, 2.8 }) do
					swing(part(d, "DoorTrim", Vector3.new(0.3, 14.3, 0.35), face * CFrame.new(x + dx, 8.6, -0.5), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH))
				end
				swing(part(d, "DoorTrim", Vector3.new(5.6, 0.25, 0.35), face * CFrame.new(x, 9, -0.5), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH))
				swing(part(d, "DoorTrim", Vector3.new(0.25, 0.25, 6.9), face * CFrame.new(x, 12.3, -0.5) * CFrame.Angles(math.rad(90), 0, math.rad(32)), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH))
				swing(part(d, "DoorTrim", Vector3.new(0.25, 0.25, 6.9), face * CFrame.new(x, 12.3, -0.5) * CFrame.Angles(math.rad(90), 0, math.rad(-32)), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH))
				swing(cylinder(d, "DoorHandle", 0.25, 2.6, face * CFrame.new(x - side * 2.3, 7.6, -0.75), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH))
			end
			-- a stained-glass fanlight in the arch over the doors: rays of coloured glass round a gold sun
			local fanColors = { rgb(255, 196, 80), rgb(80, 200, 190), rgb(236, 110, 150), rgb(150, 110, 230), rgb(120, 200, 110) }
			for k = 0, 10 do
				local phi = math.pi * (k + 0.5) / 11
				local reach = 1 / math.sqrt((math.cos(phi) / 5.9) ^ 2 + (math.sin(phi) / 3.2) ^ 2)
				part(d, "Fanlight", Vector3.new(reach - 0.6, 1.25, 0.1), face * CFrame.new(0, 16.4, -0.4) * CFrame.Angles(0, 0, phi) * CFrame.new((reach - 0.6) / 2 + 0.6, 0, 0), fanColors[k % #fanColors + 1], Enum.Material.Glass, merge(NO_TOUCH, { Transparency = 0.2, CastShadow = false }))
			end
			local sun = cylinder(d, "FanSun", 2.4, 0.2, face * CFrame.new(0, 16.4, -0.45) * CFrame.Angles(math.rad(90), 0, 0), rgb(255, 214, 102), Enum.Material.Neon, NO_TOUCH)
			light(sun, rgb(255, 214, 150), 10, 0.4)
			part(d, "Threshold", Vector3.new(13.8, 0.4, 3), face * CFrame.new(0, 1.5, -1.4), LIMESTONE, Enum.Material.Limestone)
		end
	end
	-- the roof: ribs from every column up to the lantern ring, rings across them, glass between
	for i = 0, GLASS_BAYS - 1 do
		local a = (i + 0.5) / GLASS_BAYS * TAU
		local b = (i + 1.5) / GLASS_BAYS * TAU
		for k = 0, DOME_STEPS - 1 do
			local t0, t1 = k / DOME_STEPS, (k + 1) / DOME_STEPS
			local p00, p01 = domePoint(a, t0), domePoint(a, t1)
			local p10, p11 = domePoint(b, t0), domePoint(b, t1)
			beam(roof, "Rib", p00, p01, 0.8, FRAME, Enum.Material.Metal, NO_TOUCH)
			beam(roof, "Ring", p01, p11, 0.4, FRAME, Enum.Material.Metal, NO_TOUCH)
			-- one pane per section (a rectangle as wide as the wider edge; the ribs hide the seams)
			local centre = (p00 + p01 + p10 + p11) / 4
			local across = ((p10 - p00) + (p11 - p01)) / 2
			local up = ((p01 - p00) + (p11 - p10)) / 2
			local normal = across:Cross(up).Unit
			if normal.Y < 0 then
				normal = -normal
			end
			local w = math.max((p10 - p00).Magnitude, (p11 - p01).Magnitude) + 0.1
			local cf = CFrame.fromMatrix(centre, across.Unit, normal)
			part(roof, "Glass", Vector3.new(w, 0.15, up.Magnitude + 0.1), cf, GLASS_COLOR, Enum.Material.SmoothPlastic, GLASS_ROOF)
		end
	end
	-- the lantern on top: a glass drum, a white cap and a finial
	local top = domePoint(0, 1)
	local lantern = make("Model", { Name = "Lantern" }, roof)
	cylinder(lantern, "Glass", DOME_TOP_R * 2 + 1, 0.3, CFrame.new(0, top.Y, 0), GLASS_COLOR, Enum.Material.SmoothPlastic, GLASS_ROOF)
	for k = 0, 7 do
		local a = k / 8 * TAU
		local p = polar(a, DOME_TOP_R - 3)
		part(lantern, "Post", Vector3.new(0.6, 6, 0.6), CFrame.new(p.X, top.Y + 3, p.Z), FRAME, Enum.Material.Metal, NO_TOUCH)
		local q = polar(a + TAU / 8, DOME_TOP_R - 3)
		local mid = (p + q) / 2
		part(lantern, "Pane", Vector3.new((q - p).Magnitude, 6, 0.15), CFrame.lookAt(Vector3.new(mid.X, top.Y + 3, mid.Z), Vector3.new(0, top.Y + 3, 0)), GLASS_COLOR, Enum.Material.SmoothPlastic, GLASS_ROOF)
	end
	cylinder(lantern, "Cap", (DOME_TOP_R - 2) * 2, 0.8, CFrame.new(0, top.Y + 6.4, 0), FRAME, Enum.Material.Metal, NO_TOUCH)
	cylinder(lantern, "Cap", (DOME_TOP_R - 6) * 2, 0.8, CFrame.new(0, top.Y + 7.2, 0), FRAME, Enum.Material.Metal, NO_TOUCH)
	ball(lantern, "Finial", 1.6, CFrame.new(0, top.Y + 8.4, 0), FRAME, Enum.Material.Metal, NO_TOUCH)
	part(lantern, "Spike", Vector3.new(0.3, 3, 0.3), CFrame.new(0, top.Y + 10.4, 0), FRAME, Enum.Material.Metal, NO_TOUCH)
	return m
end

---------------------------------------------------------------------------
-- Finishing touches once everything stands
---------------------------------------------------------------------------

-- A warm light that only comes on after dark (named "Glow": the client switches it).
local function glow(parent, at, range, brightness, color)
	local p = part(parent, "Glow", Vector3.new(0.4, 0.4, 0.4), CFrame.new(at), rgb(255, 255, 255), Enum.Material.SmoothPlastic, merge(NO_TOUCH, { Transparency = 1, CastShadow = false }))
	local l = light(p, color or rgb(255, 206, 150), range, brightness)
	l.Enabled = false
	return p
end

-- The long wild grass grows through anything standing in it: keep it to mown lawn under the
-- benches, the buildings, the boards and the gates (terrain only).
-- A formal border along a stretch of the avenues to the doors: a clipped box hedge with a
-- rounded top, sprinkled with pastel blooms, and a tall cone topiary at each end of the stretch,
-- crowned with a little gold lantern-bead that glows after dark.
local function jasmine(parent, a, b, rng)
	local HEDGE_GREEN = rgb(68, 120, 56)
	local BLOOMS = { rgb(244, 160, 196), rgb(196, 168, 240), rgb(255, 206, 156), rgb(250, 246, 236) }
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	if len < 0.5 then
		return
	end
	local hedgeCount = #parent:GetChildren() + 1
	local m = make("Model", { Name = "Hedge" }, parent)
	local dir = d.Unit
	local p0, p1 = a + dir * 0.9, b - dir * 0.9 -- (room for the topiaries at the ends)
	local mid = (p0 + p1) / 2
	local run = (p1 - p0).Magnitude
	local along = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(mid.X, 0, mid.Z) + dir)
	part(m, "Box", Vector3.new(1.7, 1.8, run), along * CFrame.new(0, 0.6, 0), HEDGE_GREEN, Enum.Material.Grass)
	local cap = part(m, "BoxTop", Vector3.new(run, 1.7, 1.7), along * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, math.pi / 2, 0), HEDGE_GREEN:Lerp(rgb(110, 160, 80), 0.18), Enum.Material.Grass, NO_TOUCH)
	cap.Shape = Enum.PartType.Cylinder
	local bloom = BLOOMS[hedgeCount % #BLOOMS + 1]
	local count = math.max(2, math.floor(run / 1.1))
	for k = 1, count do
		local z = -run / 2 + run * (k - 0.5) / count
		local x = rng:NextNumber(-0.45, 0.45)
		local c = bloom:Lerp(rgb(255, 255, 255), rng:NextNumber(0, 0.25))
		for f = 1, 3 do
			local ang = f * 2.1 + k
			ball(m, "Bloom", rng:NextNumber(0.3, 0.42), along * CFrame.new(x + math.cos(ang) * 0.22, 2.3 + rng:NextNumber(-0.05, 0.1), z + math.sin(ang) * 0.22), c, Enum.Material.SmoothPlastic, merge(NO_TOUCH, { CastShadow = false }))
		end
	end
	-- the cone topiary at the start of the stretch (the next stretch puts one at its own start)
	local t = make("Model", { Name = "Cone" }, m)
	local at = CFrame.new(a.X, 0, a.Z)
	cylinder(t, "Pot", 1.9, 1, at * CFrame.new(0, 0.5, 0), rgb(214, 204, 186), Enum.Material.Limestone)
	cylinder(t, "PotRim", 2.15, 0.25, at * CFrame.new(0, 1.05, 0), rgb(222, 178, 84), Enum.Material.Metal, NO_TOUCH)
	local sizes = { 2.1, 1.75, 1.4, 1.05, 0.7 }
	for k, sz in ipairs(sizes) do
		ball(t, "Leaves", sz, at * CFrame.new(0, 1.6 + (k - 1) * 0.78, 0), HEDGE_GREEN:Lerp(rgb(96, 150, 72), k * 0.06), Enum.Material.Grass, NO_TOUCH)
	end
	ball(t, "Bead", 0.42, at * CFrame.new(0, 5.15, 0), rgb(255, 214, 120), Enum.Material.Neon, NO_TOUCH)
	if hedgeCount % 2 == 0 then
		glow(t, Vector3.new(a.X, 5.4, a.Z), 9, 0.6, rgb(255, 210, 150))
	end
end

local function clearGrassUnder(root, terrain)
	local list = {}
	for _, name in ipairs({ "TradingPost", "Boards", "HallOfPulls", "TopCollector", "Gazebo", "DuelKiosk", "Campfire", "HomeDoor", "CampaignGate" }) do
		table.insert(list, root:FindFirstChild(name))
	end
	local grounds = root:FindFirstChild("Grounds")
	for _, group in ipairs({ "Benches", "Picnic", "BirdBath", "Lamps" }) do
		local g = grounds and grounds:FindFirstChild(group)
		if g then
			for _, c in ipairs(g:IsA("Model") and g:GetChildren() or {}) do
				table.insert(list, c)
			end
			table.insert(list, g)
		end
	end
	local cozy = root:FindFirstChild("Cozy")
	for _, c in ipairs(cozy and cozy:GetChildren() or {}) do
		table.insert(list, c)
	end
	for _, inst in ipairs(list) do
		local ok, cf, size
		if inst:IsA("Model") then
			ok, cf, size = pcall(inst.GetBoundingBox, inst)
		elseif inst:IsA("BasePart") then
			ok, cf, size = true, inst.CFrame, inst.Size
		end
		if ok and size and math.max(size.X, size.Z) < 60 then
			local c = cf.Position
			local hx, hz = size.X / 2 + 3, size.Z / 2 + 3
			local region = Region3.new(Vector3.new(c.X - hx, -14, c.Z - hz), Vector3.new(c.X + hx, 10, c.Z + hz)):ExpandToGrid(4)
			pcall(terrain.ReplaceMaterial, terrain, region, 4, Enum.Material.Grass, Enum.Material.LeafyGrass)
		end
	end
end

-- The bushes, hedges and topiary are meshes you'd walk straight through: give each a plain
-- invisible box to bump into.
local SOLID_PLANTS = { Jasmine = 0.85, Hydrangea = 0.8, Bush = 0.85, Topiary = 0.8, Avatar = 0.7, BirdBath = 0.8 }
local function solidify(root)
	for _, m in ipairs(root:GetDescendants()) do
		local shrink = m:IsA("Model") and SOLID_PLANTS[m.Name]
		if shrink and not m:FindFirstChild("Collider") then
			local ok, cf, size = pcall(m.GetBoundingBox, m)
			if ok and size.Y > 0.8 then
				local p = Instance.new("Part")
				p.Name = "Collider"
				p.Anchored = true
				p.Size = Vector3.new(size.X * shrink, size.Y, size.Z * shrink)
				p.CFrame = cf
				p.Transparency = 1
				p.CastShadow = false
				p.CanTouch = false
				p.Parent = m
			end
		end
	end
end

---------------------------------------------------------------------------
-- The park: trees, willows, the sycamore lawn, lamps, benches, nooks and flowers
---------------------------------------------------------------------------

local function buildPark(root, pathPoints)
	local park = make("Model", { Name = "Grounds" }, root)
	local rng = Random.new(20261107)
	local clear = keepClear(pathPoints)
	-- oaks and maples over the lawns and along the paths
	local trees = make("Model", { Name = "Trees" }, park)
	local taken = {}
	local tries = 0
	while #taken < 40 and tries < 8000 do
		tries += 1
		local p = polar(rng:NextNumber(0, TAU), rng:NextNumber(46, 116))
		if isClear(p, clear, taken, 13) then
			table.insert(taken, p)
			local s = rng:NextNumber(1.05, 1.4)
			if #taken % 3 == 0 then
				maple(trees, p, s * 0.95, rng, #taken % 9 == 0)
			else
				oak(trees, p, s, rng)
			end
		end
	end
	-- the woods round the park, past the hedge
	local woods = make("Model", { Name = "Woods" }, park)
	local back = {}
	tries = 0
	while #back < 120 and tries < 6000 do
		tries += 1
		local p = polar(rng:NextNumber(0, TAU), rng:NextNumber(133, 225)) -- (up the hills round the glasshouse)
		local ok = true
		for _, q in ipairs(back) do
			if (q - p).Magnitude < 12 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(back, p)
			backTree(woods, p, rng:NextNumber(1.1, 1.6), rng)
		end
	end
	-- weeping willows on the pond's shore, and one on the island
	local willows = make("Model", { Name = "Willows" }, park)
	for _, deg in ipairs({ 52, 100, 205, 292 }) do -- (none between the Home gate and the terrace)
		local at = shoreSpot(deg, 4.4)
		willow(willows, at + Vector3.new(0, lowGround(at, 2) - 0.5, 0), 1.6, rng:NextNumber(1, 1.15), rng)
	end
	local isle = polar(math.rad(215), ISLAND - 4)
	willow(willows, isle + Vector3.new(0, lowGround(isle, 2) - 0.5, 0), -1.1, 0.95, rng) -- (leaning out over the water)
	-- the sycamore, the picnic blankets and the bird bath
	sycamore(park, SYCAMORE)
	local picnic = make("Model", { Name = "Picnic" }, park)
	local _, b1 = blanket(picnic, BLANKET1, 0.35, rgb(196, 54, 54), rgb(246, 238, 222))
	local basket = b1 * CFrame.new(1.6, 0.55, -1)
	part(picnic, "Basket", Vector3.new(1.6, 0.9, 1.1), basket, rgb(170, 128, 76), Enum.Material.Fabric)
	part(picnic, "BasketLid", Vector3.new(1.7, 0.12, 1.2), basket * CFrame.new(0, 0.5, 0), rgb(150, 110, 64), Enum.Material.Fabric)
	local handleTop = (basket * CFrame.new(0, 1.1, 0)).Position
	beam(picnic, "Handle", (basket * CFrame.new(-0.6, 0.55, 0)).Position, handleTop, 0.12, rgb(130, 94, 54), Enum.Material.Wood)
	beam(picnic, "Handle", handleTop, (basket * CFrame.new(0.6, 0.55, 0)).Position, 0.12, rgb(130, 94, 54), Enum.Material.Wood)
	part(picnic, "Book", Vector3.new(0.9, 0.18, 1.2), b1 * CFrame.new(-1.4, 0.14, 0.8) * CFrame.Angles(0, 0.4, 0), rgb(60, 90, 140), Enum.Material.SmoothPlastic, { CanCollide = false })
	ball(picnic, "Apple", 0.45, b1 * CFrame.new(-0.2, 0.3, -1.3), rgb(200, 40, 40), Enum.Material.SmoothPlastic, NO_TOUCH)
	ball(picnic, "Apple", 0.45, b1 * CFrame.new(0.3, 0.3, -1.6), rgb(150, 200, 70), Enum.Material.SmoothPlastic, NO_TOUCH)
	blanket(picnic, BLANKET2, -0.5, rgb(64, 110, 190), rgb(240, 240, 232))
	birdBath(park, BIRDBATH)
	-- black iron lamps along the shore path, and some along the winding paths
	local lamps = make("Model", { Name = "Lamps" }, park)
	for _, deg in ipairs(SHORE_LAMPS) do
		lamp(lamps, shoreSpot(deg, 12.6))
	end
	for _, pts in ipairs(pathPoints) do
		for k = 2, #pts - 2, 8 do
			local p, q = pts[k], pts[k + 1]
			if Vector3.new(p.X, 0, p.Z).Magnitude > 50 then
				local side = Vector3.new(-(q - p).Z, 0, (q - p).X).Unit
				local at = p + side * (k % 8 == 2 and 7.4 or -7.4)
				if (at - SYCAMORE).Magnitude > 22 and (at - TRADING).Magnitude > 18 then -- (not on the picnic lawn)
					lamp(lamps, at)
				end
			end
		end
	end
	-- benches by the pond, facing the water, each with a bin and a shrub or two behind it
	local benches = make("Model", { Name = "Benches" }, park)
	for i, deg in ipairs(SHORE_BENCHES) do
		local at = shoreSpot(deg, 13.2)
		bench(benches, at, Vector3.new(0, 0, 0))
		local out = Vector3.new(at.X, 0, at.Z).Unit
		local side = Vector3.new(-out.Z, 0, out.X)
		bin(benches, at + side * 3.8)
		ball(benches, "Shrub", 3, CFrame.new(at + out * 2.6 + side * -1.6 + Vector3.new(0, 0.9, 0)), rgb(60, 106, 54), Enum.Material.Grass)
		hydrangea(benches, CFrame.new(at + out * 2.6 + side * 1.6), rng, i)
	end
	-- quiet nooks round the edge: a bench between two hedges, on a little gravel patch
	for _, deg in ipairs(ALCOVES) do
		local a = math.rad(deg)
		local cf = CFrame.lookAt(polar(a, 118), Vector3.new(0, 0, 0))
		for _, x in ipairs({ -4.5, 4.5 }) do
			part(benches, "NookHedge", Vector3.new(2.6, 3.8, 9), cf * CFrame.new(x, 1.9, -1.5), rgb(58, 108, 54), Enum.Material.Grass)
		end
		part(benches, "NookGravel", Vector3.new(6.6, 0.3, 9), cf * CFrame.new(0, -0.01, -1.5), GRAVEL, Enum.Material.Pebble)
		bench(benches, (cf * CFrame.new(0, 0, 2)).Position, Vector3.new(0, 0, 0))
	end
	-- jasmine borders along the winding paths, out on the lawns
	local borders = make("Model", { Name = "Borders" }, park)
	for i, pts in ipairs(pathPoints) do
		for k = 1, #pts - 1 do
			local p, q = pts[k], pts[k + 1]
			local r = Vector3.new(p.X, 0, p.Z).Magnitude
			if r > 72 and r < 104 and i <= 2 then
				local side = Vector3.new(-(q - p).Z, 0, (q - p).X).Unit * 5.3
				jasmine(borders, p + side, q + side, rng)
				jasmine(borders, p - side, q - side, rng)
			end
		end
	end
	-- wildflowers scattered over the lawns
	local meadow = make("Model", { Name = "Meadow" }, park)
	local patches = {}
	tries = 0
	while #patches < 18 and tries < 4000 do
		tries += 1
		local p = polar(rng:NextNumber(0, TAU), rng:NextNumber(44, 112))
		if isClear(p, clear, patches, 14) then
			local nearTree = false
			for _, q in ipairs(taken) do
				if (q - p).Magnitude < 5 then
					nearTree = true
					break
				end
			end
			if not nearTree then
				table.insert(patches, p)
				wildflowers(meadow, p, rng)
			end
		end
	end
	-- where the client lets butterflies flutter (flowerbeds, wildflowers) and songbirds hop
	local spots = make("Folder", { Name = "Spots" }, park)
	for i = 1, math.min(6, #patches) do
		make("Vector3Value", { Name = "Butterfly", Value = O + patches[i] }, spots)
	end
	for _, deg in ipairs({ 20, 160, 200, 340 }) do
		make("Vector3Value", { Name = "Butterfly", Value = O + GAZEBO + polar(math.rad(deg), 11.5) }, spots)
	end
	for _, at in ipairs({ BLANKET1 + Vector3.new(-3, 0, 3), BIRDBATH + Vector3.new(2.5, 0, 1), BLANKET2 + Vector3.new(4, 0, -2), TERRACE + TERRACE_FACING * 17 }) do
		make("Vector3Value", { Name = "Bird", Value = O + at }, spots)
	end
	return park
end

---------------------------------------------------------------------------
-- The gazebo (with the Duel Table inside) and its flowerbeds
---------------------------------------------------------------------------

local function buildGazebo(root)
	local m = make("Model", { Name = "Gazebo" }, root)
	local c = CFrame.new(GAZEBO)
	local floorTop = 1.4
	cylinder(m, "Plinth", 18, floorTop, c * CFrame.new(0, floorTop / 2, 0), STONE, Enum.Material.Slate)
	-- steps on the pond side (west)
	for s = 1, 2 do
		part(m, "Step", Vector3.new(2, floorTop * s / 3, 6), c * CFrame.new(-9 - (3 - s) * 1.6 + 0.6, floorTop * s / 6, 0), STONE, Enum.Material.Slate)
	end
	-- eight white posts, railings (open to the west) and lacy arches under the roof
	local R = 7.6
	local postTop = floorTop + 8
	local corners = {}
	for k = 0, 7 do
		local a = math.rad(22.5 + k * 45)
		local p = GAZEBO + polar(a, R)
		corners[k] = p
		part(m, "Post", Vector3.new(0.45, 8, 0.45), CFrame.new(p + Vector3.new(0, floorTop + 4, 0)), WHITE_IRON, Enum.Material.Metal)
		ball(m, "PostCap", 0.7, CFrame.new(p + Vector3.new(0, postTop + 0.1, 0)), WHITE_IRON, Enum.Material.Metal)
	end
	for k = 0, 7 do
		local p0, p1 = corners[k], corners[(k + 1) % 8]
		local mid = (p0 + p1) / 2
		local west = (mid - GAZEBO).X < -6 -- the side facing the pond is the way in
		if not west then
			beam(m, "Rail", p0 + Vector3.new(0, floorTop + 2.7, 0), p1 + Vector3.new(0, floorTop + 2.7, 0), 0.22, WHITE_IRON, Enum.Material.Metal)
			beam(m, "Rail", p0 + Vector3.new(0, floorTop + 0.45, 0), p1 + Vector3.new(0, floorTop + 0.45, 0), 0.18, WHITE_IRON, Enum.Material.Metal)
			for b = 1, 4 do
				local q = p0 + (p1 - p0) * (b / 5)
				part(m, "Baluster", Vector3.new(0.12, 2.25, 0.12), CFrame.new(q + Vector3.new(0, floorTop + 1.58, 0)), WHITE_IRON, Enum.Material.Metal)
			end
		end
		-- the eave beam and a shallow lacy arch under it
		beam(m, "Eave", p0 + Vector3.new(0, postTop, 0), p1 + Vector3.new(0, postTop, 0), 0.35, WHITE_IRON, Enum.Material.Metal)
		local prev = p0 + Vector3.new(0, postTop - 0.2, 0)
		for s = 1, 6 do
			local t = s / 6
			local q = p0 + (p1 - p0) * t + Vector3.new(0, postTop - 0.2 - math.sin(math.pi * t) * 1.1, 0)
			beam(m, "Arch", prev, q, 0.14, WHITE_IRON, Enum.Material.Metal)
			prev = q
		end
	end
	-- the roof: a stepped white dome with a little ball on top
	local layers = { { 17.5, 0.35 }, { 16, 0.5 }, { 13.6, 0.5 }, { 11, 0.5 }, { 8.4, 0.5 }, { 5.8, 0.5 }, { 3.4, 0.5 }, { 1.6, 0.5 } }
	local y = postTop + 0.3
	for i, l in ipairs(layers) do
		cylinder(m, "Roof", l[1], l[2], c * CFrame.new(0, y + l[2] / 2, 0), WHITE_IRON:Lerp(rgb(200, 204, 200), i * 0.02), Enum.Material.Metal)
		y += l[2] * 0.85
	end
	cylinder(m, "Spire", 0.3, 1.6, c * CFrame.new(0, y + 0.8, 0), WHITE_IRON, Enum.Material.Metal)
	ball(m, "Finial", 0.8, c * CFrame.new(0, y + 1.7, 0), WHITE_IRON, Enum.Material.Metal)
	-- flowerbeds round it (not across the steps): lavender and marigolds in front, hydrangeas behind
	local beds = make("Model", { Name = "Flowerbeds" }, m)
	local rng = Random.new(77)
	local a = math.rad(-60)
	local i = 0
	while a < math.rad(240) do
		-- (gazebo angles: 270 degrees is west, toward the pond)
		local soil = c * CFrame.Angles(0, a, 0)
		part(beds, "Soil", Vector3.new(2.9, 0.3, 4.6), soil * CFrame.new(0, 0.12, 11), rgb(84, 62, 46), Enum.Material.Ground, { CanCollide = false })
		part(beds, "Edging", Vector3.new(2.9, 0.5, 0.35), soil * CFrame.new(0, 0.25, 13.4), STONE, Enum.Material.Slate)
		if i % 2 == 0 then
			lavender(beds, soil * CFrame.new(0, 0.2, 9.9), rng)
		else
			marigolds(beds, soil * CFrame.new(0, 0.2, 9.9), rng)
		end
		hydrangea(beds, soil * CFrame.new(0, 0.2, 12.2), rng, i)
		i += 1
		a += 2.3 / 11
	end
	-- the Duel Table in the middle
	local kiosk = make("Model", { Name = "DuelKiosk" }, root)
	cylinder(kiosk, "Kiosk", 14.5, 0.1, c * CFrame.new(0, floorTop + 0.02, 0), rgb(160, 120, 84), Enum.Material.WoodPlanks)
	local table_ = part(kiosk, "Table", Vector3.new(6.4, 0.5, 4.2), c * CFrame.new(0, floorTop + 3, 0), rgb(46, 110, 70), Enum.Material.Fabric)
	part(kiosk, "TableRim", Vector3.new(6.8, 0.35, 4.6), c * CFrame.new(0, floorTop + 2.6, 0), rgb(110, 78, 54), Enum.Material.Wood)
	part(kiosk, "Leg", Vector3.new(1, 2.5, 1), c * CFrame.new(0, floorTop + 1.25, 0), WHITE_IRON, Enum.Material.Metal)
	for _, x in ipairs({ -4.4, 4.4 }) do
		cylinder(kiosk, "Stool", 1.8, 0.4, c * CFrame.new(x, floorTop + 1.9, 0), rgb(150, 112, 78), Enum.Material.Wood)
		cylinder(kiosk, "StoolLeg", 0.5, 1.7, c * CFrame.new(x, floorTop + 0.85, 0), WHITE_IRON, Enum.Material.Metal)
	end
	Kit.dress(m, "Gazebo", c)
	-- the sign over the way in, facing the pond
	local sign = part(kiosk, "Sign", Vector3.new(6, 1.5, 0.3), CFrame.lookAt(GAZEBO + Vector3.new(-9, postTop + 1.2, 0), Vector3.new(-100, postTop + 1.2, 0)), rgb(44, 70, 52), Enum.Material.Wood)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = make("SurfaceGui", { Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, sign)
		make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "⚔ Duel Table", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 236, 170) }, sg)
	end
	prompt(table_, "Duel", "Play a match", "Duel Table", 12)
	return m
end


---------------------------------------------------------------------------
-- The cozy touches: string lights between the lamps round the pond and under the gazebo's eaves,
-- a campfire circle with log seats, lanterns in the nooks, on the bridge and by the blankets,
-- seats on the stools, a reading nook or two, a sleeping cat, and where the fireflies come out.
---------------------------------------------------------------------------

local function buildCampfire(root)
	local m = make("Model", { Name = "Campfire" }, root)
	local rng = Random.new(4242)
	local c = CAMPFIRE
	cylinder(m, "Dirt", 11, 0.2, CFrame.new(c + Vector3.new(0, 0, 0)), rgb(126, 108, 84), Enum.Material.Ground) -- (a worn patch round the fire)
	for k = 1, 11 do
		local a = k / 11 * TAU
		local d = rng:NextNumber(0.8, 1.1)
		local grey = rng:NextNumber(110, 150)
		ball(m, "FireStone", d, CFrame.new(c + polar(a, 1.9) + Vector3.new(0, 0.05, 0)), rgb(grey, grey - 6, grey - 12), Enum.Material.Slate)
	end
	for k = 1, 3 do
		local log = part(m, "FireLog", Vector3.new(2.6, 0.45, 0.45), CFrame.new(c + Vector3.new(0, 0.42, 0)) * CFrame.Angles(0, k / 3 * math.pi, 0) * CFrame.Angles(0, 0, math.rad(12)), rgb(84, 56, 36), Enum.Material.Wood, NO_TOUCH)
		log.Shape = Enum.PartType.Cylinder
	end
	local embers = ball(m, "Embers", 1.4, CFrame.new(c + Vector3.new(0, -0.3, 0)), rgb(255, 118, 40), Enum.Material.Neon, NO_TOUCH)
	make("Fire", { Size = 3.6, Heat = 7, Color = rgb(255, 136, 48), SecondaryColor = rgb(255, 214, 110) }, embers)
	make("Smoke", { Size = 1.2, Opacity = 0.03, RiseVelocity = 3, Color = rgb(210, 210, 210) }, embers)
	make("PointLight", { Name = "FireLight", Color = rgb(255, 156, 76), Range = 20, Brightness = 1.4, Shadows = true }, embers)
	-- four log benches round it (sit down!), a blanket over two of them
	for k = 0, 3 do
		local a = k / 4 * TAU + math.pi / 4
		local at = c + polar(a, 5.6)
		local cf = CFrame.lookAt(at, Vector3.new(c.X, 0, c.Z))
		local log = part(m, "LogSeat", Vector3.new(4.4, 1.2, 1.2), cf * CFrame.new(0, 0.5, 0), rgb(120, 86, 58), Enum.Material.Wood)
		log.Shape = Enum.PartType.Cylinder
		for _, x in ipairs({ -1, 1 }) do
			cylinder(m, "LogEnd", 1.05, 0.06, cf * CFrame.new(x * 2.2, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(196, 160, 112), Enum.Material.Wood, NO_TOUCH)
			seat(m, cf * CFrame.new(x * 1.05, 1.15, 0))
		end
		if k % 2 == 0 then
			part(m, "Throw", Vector3.new(1.7, 0.08, 1.5), cf * CFrame.new(1, 1.12, 0.05) * CFrame.Angles(0.15, 0, 0), k == 0 and rgb(178, 52, 52) or rgb(70, 104, 150), Enum.Material.Fabric, NO_TOUCH)
		end
	end
	-- firewood, a stump with a lantern, two marshmallow sticks
	local wood = c + polar(0, 8.2)
	for k = 0, 5 do
		local row = k < 3 and 0 or 1
		local log = part(m, "Firewood", Vector3.new(1.8, 0.42, 0.42), CFrame.new(wood + Vector3.new(0, 0.22 + row * 0.38, (k % 3 - 1) * 0.42 + row * 0.2)) * CFrame.Angles(0, math.pi / 2, 0), rgb(104, 72, 46), Enum.Material.Wood)
		log.Shape = Enum.PartType.Cylinder
	end
	local stump = c + polar(math.pi, 8)
	cylinder(m, "Stump", 1.5, 1.3, CFrame.new(stump + Vector3.new(0, 0.65, 0)), rgb(112, 82, 56), Enum.Material.Wood)
	cylinder(m, "StumpTop", 1.4, 0.05, CFrame.new(stump + Vector3.new(0, 1.32, 0)), rgb(200, 164, 116), Enum.Material.Wood, NO_TOUCH)
	lantern(m, stump + Vector3.new(0, 1.34, 0), 1.1)
	for _, a in ipairs({ 0.9, 2.6 }) do
		local foot = c + polar(a, 3.6) + Vector3.new(0, 0.1, 0)
		local tip = c + polar(a, 1.2) + Vector3.new(0, 1.3, 0)
		beam(m, "Stick", foot, tip, 0.08, rgb(150, 116, 70), Enum.Material.Wood, NO_TOUCH)
		egg(m, "Marshmallow", Vector3.new(0.28, 0.28, 0.36), CFrame.lookAt(tip, tip + (tip - foot)), rgb(250, 240, 220))
	end
	-- string lights between four poles round the circle
	local tops = {}
	for k = 0, 3 do
		local a = k / 4 * TAU
		local at = c + polar(a, 8.6)
		cylinder(m, "Pole", 0.35, 8.4, CFrame.new(at + Vector3.new(0, 4.2, 0)), rgb(110, 82, 56), Enum.Material.Wood)
		tops[k] = at + Vector3.new(0, 8.2, 0)
	end
	for k = 0, 3 do
		stringLights(m, tops[k], tops[(k + 1) % 4], 1.2)
	end
	return m
end

local function buildCozy(root, pathPoints)
	local m = make("Model", { Name = "Cozy" }, root)
	-- little lantern posts along the winding paths (pools of warm light after dark)
	for i, pts in ipairs(pathPoints) do
		if i <= 4 then
			for k = 3, #pts - 1, 4 do
				local p, q = pts[k], pts[k + 1]
				if Vector3.new(p.X, 0, p.Z).Magnitude > 40 then
					local side = Vector3.new(-(q - p).Z, 0, (q - p).X).Unit * ((k % 4 == 1) and 6.6 or -6.6)
					local at = p + side
					cylinder(m, "Bollard", 0.5, 1.8, CFrame.new(at + Vector3.new(0, 0.9, 0)), IRON, Enum.Material.Metal)
					lantern(m, at + Vector3.new(0, 1.8, 0), 0.85)
				end
			end
		end
	end
	-- string lights between the lamps round the pond (one right over the way in from the gate)
	for _, pair in ipairs({}) do -- (none now: the string lights are kept for the gazebo and the campfire)
		local a, b = shoreSpot(pair[1], 12.6), shoreSpot(pair[2], 12.6)
		local dir = (b - a).Unit
		stringLights(m, a + dir * 0.3 + Vector3.new(0, 9, 0), b - dir * 0.3 + Vector3.new(0, 9, 0), 1.6)
	end
	-- the gazebo: lights under the eaves, a lantern over the table, seats on the stools
	local R, floorTop = 7.6, 1.4
	local postTop = floorTop + 8
	for k = 0, 7 do
		local p0 = GAZEBO + polar(math.rad(22.5 + k * 45), R) + Vector3.new(0, postTop - 0.25, 0)
		local p1 = GAZEBO + polar(math.rad(22.5 + (k + 1) * 45), R) + Vector3.new(0, postTop - 0.25, 0)
		stringLights(m, p0, p1, 0.5)
	end
	local hang = GAZEBO + Vector3.new(0, postTop + 0.3, 0)
	part(m, "Chain", Vector3.new(0.08, 1.5, 0.08), CFrame.new(hang - Vector3.new(0, 0.75, 0)), IRON, Enum.Material.Metal, NO_TOUCH)
	lantern(m, hang - Vector3.new(0, 2.5, 0), 1.4)
	for _, x in ipairs({ -4.4, 4.4 }) do
		local at = GAZEBO + Vector3.new(x, floorTop + 2.15, 0)
		seat(m, CFrame.lookAt(at, Vector3.new(GAZEBO.X, at.Y, GAZEBO.Z)))
	end
	-- the campfire circle
	buildCampfire(root)
	-- a candle lantern by the picnic basket
	lantern(m, BLANKET1 + Vector3.new(2.6, 0.06, 1.6), 0.9)
	-- the Top Collector's terrace: lanterns either side of the steps and lights along the sides
	local F = CFrame.lookAt(TERRACE, TERRACE + TERRACE_FACING)
	local function L(x, y, z)
		return F * Vector3.new(-x, y, -z)
	end
	for _, x in ipairs({ -1, 1 }) do
		lantern(m, L(x * 3.4, TERRACE_TOP, 12.4), 1.1)
		stringLights(m, L(x * 8.6, TERRACE_TOP + 9.2, -6.8), L(x * 10.2, TERRACE_TOP + 9, 6.4), 1)
	end
	-- the nooks round the edge: a lantern on a post by each bench, a book or two
	for i, deg in ipairs(ALCOVES) do
		local cf = CFrame.lookAt(polar(math.rad(deg), 118), Vector3.new(0, 0, 0))
		local post = (cf * CFrame.new(3.1, 0, 2.4)).Position
		cylinder(m, "LanternPost", 0.25, 3.2, CFrame.new(post + Vector3.new(0, 1.6, 0)), IRON, Enum.Material.Metal)
		lantern(m, post + Vector3.new(0, 3.2, 0), 1)
		if i % 3 == 1 then
			local bench = cf * CFrame.new(0, 0, 2)
			for b = 0, 2 do
				part(m, "Book", Vector3.new(0.85, 0.16, 1.15), bench * CFrame.new(1.7, 1.95 + b * 0.16, -0.1) * CFrame.Angles(0, b * 0.25, 0), ({ rgb(150, 60, 60), rgb(60, 100, 140), rgb(200, 170, 90) })[b + 1], Enum.Material.SmoothPlastic, NO_TOUCH)
			end
			cylinder(m, "Mug", 0.4, 0.5, bench * CFrame.new(-1.9, 2.1, 0), rgb(236, 230, 220), Enum.Material.SmoothPlastic, NO_TOUCH)
		end
	end
	-- a ginger cat asleep on a bench by the pond
	local catBench = shoreSpot(SHORE_BENCHES[4], 13.2)
	local catCf = CFrame.lookAt(catBench, Vector3.new(0, 0, 0)) * CFrame.new(-1.4, 1.86, -0.1)
	sleepingCat(m, catCf)
	local catAt = (CFrame.new(O) * catCf).Position
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Seat") and (d.CFrame.Position - catAt).Magnitude < 1.4 then
			d:Destroy() -- (the cat has that seat)
		end
	end
	-- where the fireflies come out at night (the client makes them)
	local spots = root:FindFirstChild("Grounds") and root.Grounds:FindFirstChild("Spots")
	if spots then
		for _, f in ipairs({ { Vector3.new(0, 0, 0), 26 }, { CAMPFIRE, 12 }, { SYCAMORE, 14 }, { GAZEBO, 15 }, { BLANKET2, 12 }, { TERRACE, 12 } }) do
			local v = make("Vector3Value", { Name = "Fireflies", Value = O + f[1] }, spots)
			v:SetAttribute("Radius", f[2])
		end
	end
	return m
end

---------------------------------------------------------------------------
-- The Pull Altar, the Top Collector, the Hall of Pulls, the boards and the gates
---------------------------------------------------------------------------

local function buildAltar(root)
	local m = make("Model", { Name = "Altar" }, root)
	local dais = cylinder(m, "Dais", 18, 1.2, CFrame.new(0, 0.6, 0), rgb(232, 220, 200), Enum.Material.Marble)
	cylinder(m, "Step", 13, 1.2, CFrame.new(0, 1.8, 0), rgb(214, 200, 178), Enum.Material.Marble)
	cylinder(m, "Top", 8, 0.8, CFrame.new(0, 2.8, 0), rgb(245, 236, 220), Enum.Material.Marble)
	cylinder(m, "Glow", 6.4, 0.2, CFrame.new(0, 3.25, 0), rgb(255, 210, 120), Enum.Material.Neon)
	cylinder(m, "Pedestal", 2.4, 3, CFrame.new(0, 4.8, 0), rgb(150, 142, 150), Enum.Material.Marble)
	-- the big pack floating over it (the client spins and bobs it)
	local pack = part(m, "FloatingPack", Vector3.new(3.4, 4.8, 0.6), CFrame.new(0, 9.2, 0), rgb(96, 78, 132), Enum.Material.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = make("SurfaceGui", { Name = "PackFace" .. face.Name, Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 50, LightInfluence = 0 }, pack)
		local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(96, 78, 132), BorderSizePixel = 0 }, sg)
		make("UIGradient", { Color = ColorSequence.new(rgb(168, 132, 176), rgb(84, 92, 140)), Rotation = 70 }, f)
		make("TextLabel", { Size = UDim2.new(1, 0, 0.3, 0), Position = UDim2.fromScale(0, 0.35), BackgroundTransparency = 1, Text = "PACKS", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 255, 255) }, f)
		make("TextLabel", { Size = UDim2.new(1, 0, 0.12, 0), Position = UDim2.fromScale(0, 0.66), BackgroundTransparency = 1, Text = "★ open at the altar ★", TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = rgb(255, 236, 200) }, f)
	end
	light(pack, rgb(238, 220, 255), 16, 1) -- (a soft glow: the park stays calm)
	-- the pillar of light for big pulls (invisible until then)
	local pillar = cylinder(m, "LightPillar", 7, 160, CFrame.new(0, 80, 0), rgb(255, 230, 150), Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	pillar:SetAttribute("Rarity", "")
	-- four crystals around the top step
	for i = 1, 4 do
		local a = i * math.pi / 2 + math.pi / 4
		local c = part(m, "Crystal", Vector3.new(0.9, 3, 0.9), CFrame.Angles(0, a, 0) * CFrame.new(0, 4.1, 5) * CFrame.Angles(math.rad(12), 0, math.rad(45)), rgb(196, 186, 226), Enum.Material.Glass, { Transparency = 0.35 })
		light(c, rgb(214, 200, 255), 8, 0.5)
	end
	prompt(dais, "OpenPacks", "Open packs", "Pull Altar", 16)
	return m
end


---------------------------------------------------------------------------
-- The Top Collector's terrace: round stone steps up to a terrace on the far shore, facing the way
-- in. On it a marble pedestal (ParkServer stands the champion's avatar on AvatarSpot), their
-- rarest card floating over them (Card1, the client turns it slowly) and the next two on gold
-- easels (Card2, Card3), a plaque with their name (Plaque), a white rose arch with the sign, box
-- topiaries in planters and two lamps lighting the pedestal.
---------------------------------------------------------------------------

local GOLD = rgb(226, 184, 84)
local MARBLE = rgb(240, 234, 222)

local function easel(parent, name, at, lookAt)
	local m = make("Model", { Name = name .. "Easel" }, parent)
	local base = CFrame.lookAt(at, Vector3.new(lookAt.X, at.Y, lookAt.Z))
	local wood = rgb(176, 136, 70)
	-- three legs: two in front, one behind
	for _, x in ipairs({ -1.3, 1.3 }) do
		beam(m, "Leg", (base * CFrame.new(x, 0, 0.3)).Position, (base * CFrame.new(x * 0.45, 6.6, 0.75)).Position, 0.2, wood, Enum.Material.Wood)
	end
	beam(m, "Leg", (base * CFrame.new(0, 0, 2.2)).Position, (base * CFrame.new(0, 6.4, 0.85)).Position, 0.2, wood, Enum.Material.Wood)
	part(m, "Ledge", Vector3.new(3.8, 0.22, 0.6), base * CFrame.new(0, 1.6, 0.25), GOLD, Enum.Material.Metal)
	-- the card, leaning back on the legs, in a thin gold frame
	local cardCf = base * CFrame.new(0, 1.7 + 2.15, 0.62) * CFrame.Angles(math.rad(10), 0, 0)
	part(m, "Frame", Vector3.new(3.45, 4.75, 0.12), cardCf * CFrame.new(0, 0, 0.08), GOLD, Enum.Material.Metal)
	local card = part(parent, name, Vector3.new(3.1, 4.34, 0.1), cardCf, rgb(30, 26, 40), Enum.Material.SmoothPlastic, { CanCollide = false })
	return card
end

local function buildTopCollector(root)
	local m = make("Model", { Name = "TopCollector" }, root)
	local rng = Random.new(808)
	local c = CFrame.new(TERRACE)
	-- (laid out facing TERRACE_FACING: x to the stand's left, z toward the front)
	local F = CFrame.lookAt(TERRACE, TERRACE + TERRACE_FACING)
	local function L(x, y, z)
		return F * Vector3.new(-x, y, -z)
	end
	local front = TERRACE_FACING
	local paving = STONE:Lerp(rgb(255, 255, 255), 0.3)
	-- round stone steps up to the terrace, with a ring of darker stone round the pedestal
	cylinder(m, "Step", 29.6, 0.34, c * CFrame.new(0, 0.17, 0), paving:Lerp(rgb(0, 0, 0), 0.05), Enum.Material.Slate)
	cylinder(m, "Step", 28.2, 0.67, c * CFrame.new(0, 0.335, 0), paving:Lerp(rgb(0, 0, 0), 0.02), Enum.Material.Slate)
	cylinder(m, "Terrace", 26.8, TERRACE_TOP, c * CFrame.new(0, TERRACE_TOP / 2, 0), paving, Enum.Material.Slate)
	cylinder(m, "Inlay", 12, 0.04, c * CFrame.new(0, TERRACE_TOP + 0.02, 0), rgb(150, 140, 126), Enum.Material.Slate, NO_TOUCH)
	cylinder(m, "Inlay", 11, 0.06, c * CFrame.new(0, TERRACE_TOP + 0.03, 0), paving:Lerp(rgb(255, 250, 235), 0.4), Enum.Material.Marble, NO_TOUCH)
	-- the marble pedestal with a gold band
	local t = TERRACE_TOP
	cylinder(m, "PedestalBase", 6.2, 0.6, c * CFrame.new(0, t + 0.3, 0), MARBLE:Lerp(rgb(0, 0, 0), 0.06), Enum.Material.Marble)
	cylinder(m, "Pedestal", 4.8, 2.4, c * CFrame.new(0, t + 1.8, 0), MARBLE, Enum.Material.Marble)
	cylinder(m, "PedestalBand", 4.95, 0.28, c * CFrame.new(0, t + 2.6, 0), GOLD, Enum.Material.Metal)
	cylinder(m, "PedestalCap", 5.6, 0.36, c * CFrame.new(0, t + 3.18, 0), MARBLE:Lerp(rgb(255, 255, 255), 0.3), Enum.Material.Marble)
	local standY = t + 3.36
	-- where the avatar stands (facing the way in)
	local spotAt = TERRACE + Vector3.new(0, standY, 0)
	part(m, "AvatarSpot", Vector3.new(2, 0.1, 1), CFrame.lookAt(spotAt, spotAt + front), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	-- the rarest card, floating over the pedestal (both faces drawn by the client)
	local floatAt = TERRACE + Vector3.new(0, standY + 8.2, 0)
	local card1 = part(m, "Card1", Vector3.new(3.1, 4.34, 0.12), CFrame.lookAt(floatAt, floatAt + front), rgb(30, 26, 40), Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false, CastShadow = false })
	light(card1, rgb(255, 220, 150), 14, 1.5)
	make("ParticleEmitter", {
		Name = "Glitter",
		Rate = 8,
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.18, 0),
		Transparency = NumberSequence.new(0.1, 1),
		LightEmission = 1,
		Color = ColorSequence.new(rgb(255, 230, 160)),
	}, card1)
	-- the next two on easels either side, turned a little toward the way in
	local lookAt = TERRACE + front * 70
	easel(m, "Card2", L(-6.6, t, 1.6), lookAt)
	easel(m, "Card3", L(6.6, t, 1.6), lookAt)
	-- the plaque on a slanted stone lectern in front
	local lectern = L(0, t, 5.4)
	part(m, "Lectern", Vector3.new(2.4, 1.5, 1), CFrame.lookAt(lectern + Vector3.new(0, 0.75, 0), lectern + Vector3.new(0, 0.75, 0) + front), MARBLE:Lerp(rgb(0, 0, 0), 0.08), Enum.Material.Marble)
	local plaqueAt = lectern + Vector3.new(0, 1.75, 0) + front * 0.2
	local plaqueCf = CFrame.lookAt(plaqueAt, plaqueAt + front) * CFrame.Angles(math.rad(48), 0, 0)
	part(m, "PlaqueFrame", Vector3.new(5.8, 2.9, 0.22), plaqueCf * CFrame.new(0, 0, 0.06), GOLD, Enum.Material.Metal)
	part(m, "Plaque", Vector3.new(5.5, 2.6, 0.2), plaqueCf, rgb(30, 38, 36), Enum.Material.Marble)
	-- the rose arch behind, with the sign on top
	local _, tops = roseArch(m, "RoseArch", L(0, t, -6.2), front, 8.6, 9.6, 3.4, rng)
	local apex = (tops[1][7] + tops[2][7]) / 2
	local signAt = apex + Vector3.new(0, 2.6, 0)
	local sign = part(m, "Sign", Vector3.new(9, 1.8, 0.3), CFrame.lookAt(signAt, signAt + front), rgb(36, 64, 48), Enum.Material.Wood)
	part(m, "SignTrim", Vector3.new(9.4, 2.2, 0.2), CFrame.lookAt(signAt, signAt + front) * CFrame.new(0, 0, 0.12), GOLD, Enum.Material.Metal)
	for _, x in ipairs({ -2.5, 2.5 }) do
		local foot = (CFrame.lookAt(apex, apex + front) * CFrame.new(x, 0, 0)).Position
		part(m, "SignPost", Vector3.new(0.18, 1.8, 0.18), CFrame.new(foot + Vector3.new(0, 0.9, 0)), WHITE_IRON, Enum.Material.Metal)
	end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = make("SurfaceGui", { Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, sign)
		make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "🏆 TOP COLLECTOR", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 228, 150) }, sg)
	end
	-- box topiaries by the steps and at the back
	for _, x in ipairs({ -1, 1 }) do
		topiary(m, L(x * 7, t, 10.6))
		topiary(m, L(x * 11.4, t, -2.5))
	end
	-- two lamps lighting the pedestal
	for _, x in ipairs({ -1, 1 }) do
		local foot = L(x * 10.2, t, 6.4)
		local l = lamp(m, foot)
		local lantern = l:FindFirstChild("Lantern")
		if lantern then
			local spot = part(l, "SpotHead", Vector3.new(0.5, 0.5, 0.5), CFrame.lookAt(foot + Vector3.new(0, 9.4, 0), TERRACE + Vector3.new(0, standY + 3, 0)), IRON, Enum.Material.Metal)
			make("SpotLight", { Face = Enum.NormalId.Front, Angle = 40, Range = 18, Brightness = 2.2, Color = rgb(255, 238, 210), Shadows = true }, spot)
		end
	end
	return m
end

-- A park notice board: green painted wood under a little shingled roof.
local BOARD_GREEN = rgb(56, 84, 60)
local function buildBoards(root)
	-- the Hall of Pulls: a big board behind the Top Collector's terrace, facing the pond
	local hall = make("Model", { Name = "HallOfPulls" }, root)
	local hallCf = CFrame.lookAt(HALL + Vector3.new(0, 11, 0), Vector3.new(0, 11, 0))
	part(hall, "Frame", Vector3.new(26, 16, 1), hallCf, BOARD_GREEN, Enum.Material.Wood)
	part(hall, "Board", Vector3.new(24, 14, 0.3), hallCf * CFrame.new(0, 0, -0.6), rgb(30, 44, 38), Enum.Material.SmoothPlastic)
	part(hall, "Roof", Vector3.new(28, 1, 3.4), hallCf * CFrame.new(0, 8.6, -0.5), rgb(96, 66, 52), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -13.5, 13.5 }) do
		part(hall, "Leg", Vector3.new(1.2, 19, 1.2), hallCf * CFrame.new(x, -1.5, 0), BOARD_GREEN, Enum.Material.Wood)
	end
	for _, x in ipairs({ -8, 8 }) do
		topiary(hall, HALL + HALL_SIDE * x + HALL_FRONT * 5.5)
	end
	-- the leaderboards either side of it (see boardSpot)
	local boards = make("Model", { Name = "Boards" }, root)
	for i, def in ipairs(Park.Boards) do
		local m = make("Model", { Name = def.key }, boards)
		local at = boardSpot(i) + Vector3.new(0, 7, 0)
		local cf = CFrame.lookAt(at, Vector3.new(0, 7, 0))
		part(m, "Frame", Vector3.new(13, 13, 1), cf, BOARD_GREEN, Enum.Material.Wood)
		part(m, "Board", Vector3.new(12, 12, 0.3), cf * CFrame.new(0, 0, -0.6), rgb(30, 44, 38), Enum.Material.SmoothPlastic)
		part(m, "Roof", Vector3.new(14.5, 0.8, 2.6), cf * CFrame.new(0, 7, -0.4), rgb(96, 66, 52), Enum.Material.WoodPlanks)
		for _, x in ipairs({ -6, 6 }) do
			part(m, "Leg", Vector3.new(1, 14, 1), cf * CFrame.new(x, -0.5, 0.2), BOARD_GREEN, Enum.Material.Wood)
		end
		local lantern = part(m, "Lantern", Vector3.new(1, 1, 1), cf * CFrame.new(0, 7.9, -1.2), rgb(255, 222, 160), Enum.Material.Glass, { Transparency = 0.2 })
		light(lantern, rgb(255, 210, 150), 12, 0.8)
	end
end

-- A park gate: stone pillars, a black iron arch with the name on it, iron railings either side.
-- A way out: one of the glasshouse's grand doorways (see buildGlasshouse) at `angle`. This adds
-- the sign over the doors, a soft glow just inside them and the prompt that takes you there.
local function gate(root, name, angle, title, color, promptName, action)
	local m = make("Model", { Name = name }, root)
	local mid = polar(angle, GLASS_R * math.cos(math.pi / GLASS_BAYS))
	local face = CFrame.lookAt(mid, mid - polar(angle, 1)) -- (looking into the park; -Z is inward)
	local portal = part(m, "Portal", Vector3.new(11.4, 14, 0.2), face * CFrame.new(0, 8.6, -1.1), color:Lerp(rgb(255, 255, 255), 0.45), Enum.Material.Neon, { Transparency = 0.8, CanCollide = false, CastShadow = false })
	light(portal, color, 18, 1.1)
	-- golden motes drifting in the doorway
	make("ParticleEmitter", { Name = "Motes", Rate = 5, Lifetime = NumberRange.new(2.5, 4), Speed = NumberRange.new(0.3, 0.8), SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.18), NumberSequenceKeypoint.new(1, 0) }), Color = ColorSequence.new(rgb(255, 226, 150)), LightEmission = 1, Transparency = NumberSequence.new(0.2), Acceleration = Vector3.new(0, 0.4, 0) }, portal)

	-- The porch: a white-columned glass porch out from the door, a marquee sign on top, a carpet
	-- runner up to the doors, a mosaic in the floor and a big planter on each side.
	local porch = make("Model", { Name = "Porch" }, m)
	local GOLD_TRIM = rgb(222, 178, 84)
	local FRONT, BACK, W = -7, -1.4, 8.6 -- (how far in the porch reaches, and its half width)
	part(porch, "Floor", Vector3.new(W * 2 + 2.4, 0.5, BACK - FRONT + 1.2), face * CFrame.new(0, 0.25, (FRONT + BACK) / 2 - 0.3), LIMESTONE, Enum.Material.Limestone)
	part(porch, "FloorEdge", Vector3.new(W * 2 + 2.8, 0.2, 0.5), face * CFrame.new(0, 0.42, FRONT - 0.9), LIMESTONE:Lerp(rgb(255, 255, 255), 0.25), Enum.Material.Limestone, NO_TOUCH)
	-- the mosaic: a star in rings, the door's own colour at its heart
	local mosaic = face * CFrame.new(0, 0.52, (FRONT + BACK) / 2) * CFrame.Angles(0, 0, math.rad(90))
	cylinder(porch, "Mosaic", 6.4, 0.06, face * CFrame.new(0, 0.53, (FRONT + BACK) / 2), rgb(70, 60, 56), Enum.Material.Marble, NO_TOUCH)
	cylinder(porch, "Mosaic", 5.6, 0.07, face * CFrame.new(0, 0.54, (FRONT + BACK) / 2), GOLD_TRIM, Enum.Material.Marble, NO_TOUCH)
	cylinder(porch, "Mosaic", 4.8, 0.08, face * CFrame.new(0, 0.55, (FRONT + BACK) / 2), rgb(236, 230, 214), Enum.Material.Marble, NO_TOUCH)
	for k = 0, 7 do
		local long = k % 2 == 0
		part(porch, "MosaicStar", Vector3.new(long and 4.4 or 3, 0.09, 0.55), face * CFrame.new(0, 0.56, (FRONT + BACK) / 2) * CFrame.Angles(0, k * math.pi / 8, 0), long and color or GOLD_TRIM, Enum.Material.Marble, NO_TOUCH)
	end
	cylinder(porch, "Mosaic", 1.2, 0.1, face * CFrame.new(0, 0.57, (FRONT + BACK) / 2), color, Enum.Material.Neon, NO_TOUCH)
	local _ = mosaic
	-- the carpet runner, out along the path, with gold edging
	local runnerColor = color:Lerp(rgb(150, 30, 40), 0.65)
	part(porch, "Runner", Vector3.new(4.4, 0.06, 16), face * CFrame.new(0, 0.53, BACK - 8.3), runnerColor, Enum.Material.Fabric, NO_TOUCH)
	for _, x in ipairs({ -2.15, 2.15 }) do
		part(porch, "RunnerEdge", Vector3.new(0.18, 0.07, 16), face * CFrame.new(x, 0.54, BACK - 8.3), GOLD_TRIM, Enum.Material.Fabric, NO_TOUCH)
	end
	-- four white columns, a beam round the top and a glass roof on iron ribs
	for _, x in ipairs({ -W, W }) do
		for _, z in ipairs({ FRONT, BACK - 0.4 }) do
			cylinder(porch, "Column", 1.3, 14.4, face * CFrame.new(x, 7.7, z), FRAME, Enum.Material.Marble)
			part(porch, "ColumnBase", Vector3.new(2, 0.7, 2), face * CFrame.new(x, 0.85, z), FRAME, Enum.Material.Marble, NO_TOUCH)
			part(porch, "ColumnCap", Vector3.new(2.1, 0.6, 2.1), face * CFrame.new(x, 14.9, z), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH)
			for k = 0, 3 do -- (the fluting)
				part(porch, "Flute", Vector3.new(0.12, 13.4, 0.12), face * CFrame.new(x, 7.7, z) * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0.66, 0, 0), FRAME:Lerp(rgb(170, 170, 170), 0.3), Enum.Material.Marble, NO_TOUCH)
			end
		end
		part(porch, "SideBeam", Vector3.new(1, 1, BACK - FRONT + 0.6), face * CFrame.new(x, 15.7, (FRONT + BACK) / 2 - 0.2), FRAME, Enum.Material.Metal, NO_TOUCH)
		-- a lantern on each front column
		local lanternAt = face * CFrame.new(x + (x > 0 and 1.1 or -1.1), 11.2, FRONT)
		part(porch, "LanternArm", Vector3.new(1.2, 0.2, 0.2), face * CFrame.new(x + (x > 0 and 0.6 or -0.6), 12.2, FRONT), IRON, Enum.Material.Metal, NO_TOUCH)
		local glass = part(porch, "Lantern", Vector3.new(1, 1.5, 1), lanternAt, rgb(255, 232, 186), Enum.Material.Glass, merge(NO_TOUCH, { Transparency = 0.2 }))
		part(porch, "LanternCap", Vector3.new(1.3, 0.3, 1.3), lanternAt * CFrame.new(0, 0.9, 0), IRON, Enum.Material.Metal, NO_TOUCH)
		light(glass, rgb(255, 206, 140), 16, 0.5)
	end
	part(porch, "FrontBeam", Vector3.new(W * 2 + 1.6, 1.2, 1.2), face * CFrame.new(0, 15.7, FRONT), FRAME, Enum.Material.Metal, NO_TOUCH)
	part(porch, "FrontBeamTrim", Vector3.new(W * 2 + 1.7, 0.25, 1.3), face * CFrame.new(0, 15.05, FRONT), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH)
	for k = 0, 4 do
		local z = FRONT + (BACK - FRONT) * k / 4
		arch(porch, "RoofRib", face * Vector3.new(-W, 16.2, z), face * Vector3.new(W, 16.2, z), 1.6, 0.35, FRAME, 8)
	end
	-- the glass roof: a gentle vault, one pane per rib bay
	for k = 0, 7 do
		local t0, t1 = k / 8, (k + 1) / 8
		local p0 = face * Vector3.new(-W + 2 * W * t0, 16.25 + 1.6 * math.sin(math.pi * t0), (FRONT + BACK) / 2)
		local p1 = face * Vector3.new(-W + 2 * W * t1, 16.25 + 1.6 * math.sin(math.pi * t1), (FRONT + BACK) / 2)
		local mid = (p0 + p1) / 2
		local across = (p1 - p0)
		local depth = face.LookVector
		local up = across:Cross(depth).Unit
		if up.Y < 0 then
			up = -up
		end
		part(porch, "RoofGlass", Vector3.new(across.Magnitude + 0.1, 0.12, BACK - FRONT + 0.4), CFrame.fromMatrix(mid, across.Unit, up), GLASS_COLOR, Enum.Material.SmoothPlastic, GLASS_ROOF)
	end
	-- the marquee sign over the porch, ringed with bulbs that light up after dark
	local sign = part(porch, "Sign", Vector3.new(13, 3, 0.5), face * CFrame.new(0, 19.6, FRONT - 0.1), rgb(30, 26, 40), Enum.Material.Metal)
	part(porch, "SignFrame", Vector3.new(14, 4, 0.35), face * CFrame.new(0, 19.6, FRONT + 0.15), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH)
	local sg = make("SurfaceGui", { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, sign)
	local label = make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = title, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 236, 190) }, sg)
	make("UIStroke", { Color = color:Lerp(rgb(0, 0, 0), 0.4), Thickness = 3 }, label)
	make("UIPadding", { PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0) }, label)
	local bulbs = 0
	for k = 0, 13 do
		local x = -6.5 + 13 * k / 13
		for _, y in ipairs({ 17.85, 21.35 }) do
			bulbs += 1
			local b = ball(porch, "Bulb", 0.36, face * CFrame.new(x, y, FRONT - 0.15), rgb(255, 238, 206), Enum.Material.Glass, merge(NO_TOUCH, { Transparency = 0.15, CastShadow = false }))
			if bulbs % 6 == 1 then
				light(b, rgb(255, 196, 124), 8, 0)
			end
		end
	end
	for _, x in ipairs({ -6.8, 6.8 }) do
		for _, y in ipairs({ 18.7, 19.6, 20.5 }) do
			ball(porch, "Bulb", 0.36, face * CFrame.new(x, y, FRONT - 0.15), rgb(255, 238, 206), Enum.Material.Glass, merge(NO_TOUCH, { Transparency = 0.15, CastShadow = false }))
		end
	end
	-- a big stone planter each side, with a clipped spiral topiary
	for _, x in ipairs({ -W - 3.2, W + 3.2 }) do
		local at = face * CFrame.new(x, 0, FRONT - 1)
		local pot = make("Model", { Name = "Topiary" }, porch)
		cylinder(pot, "Plinth", 3.2, 0.8, at * CFrame.new(0, 0.4, 0), LIMESTONE, Enum.Material.Limestone)
		cylinder(pot, "Urn", 2.6, 2.4, at * CFrame.new(0, 2, 0), LIMESTONE:Lerp(rgb(255, 255, 255), 0.15), Enum.Material.Marble)
		cylinder(pot, "UrnLip", 3.1, 0.4, at * CFrame.new(0, 3.3, 0), GOLD_TRIM, Enum.Material.Metal, NO_TOUCH)
		for k = 0, 4 do
			ball(pot, "Leaves", 2.6 - k * 0.42, at * CFrame.new(math.sin(k * 1.9) * 0.25, 4.4 + k * 1.25, math.cos(k * 1.9) * 0.25), rgb(58, 108, 54):Lerp(rgb(90, 140, 70), k * 0.1), Enum.Material.Grass, NO_TOUCH)
		end
		ball(pot, "TopiaryStar", 0.5, at * CFrame.new(0, 10.6, 0), GOLD_TRIM, Enum.Material.Neon, NO_TOUCH)
	end
	prompt(portal, promptName, action, title, 14)
	return m, portal
end


-- Builds Workspace.Park (or keeps the one already there). Returns the Park model.
---------------------------------------------------------------------------
-- The Trading Post: a little timber-framed market house beyond the sycamore, with two counters
-- under striped awnings and tables inside to sit down at across from someone.
---------------------------------------------------------------------------

local function buildTradingPost(root)
	local m = make("Model", { Name = "TradingPost" }, root)
	local cf = CFrame.lookAt(TRADING, Vector3.new(0, 0, 0)) -- (its front, -Z, faces the pond)
	local wood, plaster, board = rgb(92, 68, 50), rgb(236, 226, 204), rgb(150, 112, 78)
	part(m, "Plinth", Vector3.new(23.2, 0.8, 15.2), cf * CFrame.new(0, 0.4, 0), STONE, Enum.Material.Slate)
	part(m, "Step", Vector3.new(9, 0.4, 1.8), cf * CFrame.new(0, 0.2, -8.4), STONE, Enum.Material.Slate)
	for _, x in ipairs({ -10.6, -4.2, 4.2, 10.6 }) do
		for _, z in ipairs({ -6.6, 6.6 }) do
			part(m, "Post", Vector3.new(0.7, 9, 0.7), cf * CFrame.new(x, 5.3, z), wood, Enum.Material.Wood)
		end
	end
	part(m, "Wall", Vector3.new(21.2, 8.85, 0.4), cf * CFrame.new(0, 5.225, 6.6), plaster, Enum.Material.SmoothPlastic)
	for _, x in ipairs({ -10.6, 10.6 }) do
		part(m, "Wall", Vector3.new(0.4, 8.85, 13.2), cf * CFrame.new(x, 5.225, 0), plaster, Enum.Material.SmoothPlastic)
	end
	for _, x in ipairs({ -7.4, 7.4 }) do
		part(m, "Wall", Vector3.new(5.7, 3.3, 1.2), cf * CFrame.new(x, 2.45, -6.6), plaster, Enum.Material.SmoothPlastic) -- (the counters)
	end
	for _, s in ipairs({ -1, 1 }) do
		part(m, "Roof", Vector3.new(25, 0.5, 10.7), cf * CFrame.new(0, 12.78, s * 4.3) * CFrame.Angles(math.rad(34.9 * s), 0, 0), rgb(118, 102, 90), Enum.Material.Slate, { CanCollide = false })
	end
	Kit.dress(m, "TradingPost", cf)
	-- (unseen, in the middle of the floor: the "Trade" prompt, and where trades are measured from)
	local desk = part(m, "Desk", Vector3.new(1, 1, 1), cf * CFrame.new(0, 3.2, -1), plaster, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	prompt(desk, "Trade", "Trade cards", "Trading Post", 15)
	-- what stands inside and around it
	local inside = make("Model", { Name = "Inside" }, m)
	for _, x in ipairs({ -5.4, 5.4 }) do
		cylinder(inside, "TableTop", 4.2, 0.3, cf * CFrame.new(x, 3.55, 1.2), board, Enum.Material.WoodPlanks)
		cylinder(inside, "TableLeg", 0.7, 2.6, cf * CFrame.new(x, 2.1, 1.2), wood, Enum.Material.Wood)
		for _, z in ipairs({ -2, 4.4 }) do
			cylinder(inside, "Stool", 1.7, 0.3, cf * CFrame.new(x, 2.55, z), board, Enum.Material.WoodPlanks)
			cylinder(inside, "StoolLeg", 0.45, 1.6, cf * CFrame.new(x, 1.6, z), wood, Enum.Material.Wood)
			seat(inside, cf * CFrame.new(x, 2.75, z) * CFrame.Angles(0, z < 1.2 and math.pi or 0, 0)) -- (facing the table)
		end
	end
	local sign = part(inside, "Sign", Vector3.new(8, 1.7, 0.3), cf * CFrame.new(0, 8.75, -7.15), rgb(44, 70, 52), Enum.Material.Wood)
	local sg = make("SurfaceGui", { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, sign)
	make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "🤝 Trading Post", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 236, 170) }, sg)
	local rng = Random.new(77)
	for _, x in ipairs({ -7.4, 7.4 }) do
		lantern(inside, (cf * CFrame.new(x, 4.26, -6.6)).Position, 0.9) -- (one on each counter)
	end
	for _, x in ipairs({ -4.2, 4.2 }) do
		lantern(inside, (cf * CFrame.new(x, 8.5, 0.6)).Position, 1.3) -- (and one under each roof beam, over the tables)
	end
	for _, x in ipairs({ -11.22, 11.22 }) do
		for i, z in ipairs({ -1.5, 0, 1.5 }) do
			local flower = i % 2 == 1 and lavender or marigolds
			flower(inside, cf * CFrame.new(x, 3.8, z), rng) -- (in the window boxes)
		end
		Kit.put("Bush", inside, cf * CFrame.new(x * 1.18, 0, 5.2), 1.3)
	end
	return m
end

function ParkBuilder.build(workspaceRoot)
	local existing = workspaceRoot:FindFirstChild("Park")
	if existing then
		return existing, false
	end
	local root = make("Model", { Name = "Park" }, nil)
	local pathPoints = allPathPoints()
	-- real terrain if the place has some to paint into (parts otherwise, e.g. in the tests)
	local terrainMade = false
	local terrain = workspaceRoot:FindFirstChildOfClass("Terrain")
	if terrain and ParkBuilder.UseTerrain then
		terrainMade = pcall(terrainGround, terrain, pathPoints)
	end
	WATER = terrainMade and Kit.WaterLevel or Park.WaterLevel
	root:SetAttribute("WaterLevel", WATER)
	root:SetAttribute("Terrain", terrainMade)
	buildGround(root, pathPoints, terrainMade)
	buildPond(root, terrainMade)
	buildAltar(root)
	buildTopCollector(root)
	buildBoards(root)
	buildGazebo(root)
	buildTradingPost(root)
	buildPark(root, pathPoints)
	buildCozy(root, pathPoints)
	gate(root, "HomeDoor", 0, "🏠 Home", rgb(255, 196, 120), "GoHome", "Back to your room")
	gate(root, "CampaignGate", -math.pi / 2, "🗺 Campaign", rgb(120, 206, 150), "Campaign", "Open the Campaign map")
	buildGlasshouse(root, terrainMade)
	-- lights where you go after dark: the boards, the Hall of Pulls and the Trading Post
	local glows = make("Model", { Name = "Glows" }, root)
	for i = 1, #Park.Boards do
		local at = boardSpot(i)
		glow(glows, at - Vector3.new(at.X, 0, at.Z).Unit * 6 + Vector3.new(0, 7, 0), 18, 0.9)
	end
	glow(glows, HALL + HALL_FRONT * 7 + Vector3.new(0, 8, 0), 22, 1)
	glow(glows, TRADING + Vector3.new(0, 7, 0), 20, 1)
	glow(glows, TRADING - Vector3.new(TRADING.X, 0, TRADING.Z).Unit * 11 + Vector3.new(0, 6, 0), 16, 0.7)
	glow(glows, GAZEBO + Vector3.new(0, 6, 0), 16, 0.6)
	if terrainMade then
		pcall(clearGrassUnder, root, terrain)
	end
	solidify(root)
	local marker = make("Folder", { Name = "Spawns" }, root)
	for n = 0, 4 do
		make("CFrameValue", { Name = "Spawn" .. n, Value = Park.spawnCFrame(n) }, marker)
	end
	root.Parent = workspaceRoot
	return root, true
end

ParkBuilder.UseTerrain = true -- (paint the lawn and the pond into terrain when the place has it)
-- (for the tests and the map preview)
ParkBuilder.Gazebo = GAZEBO
ParkBuilder.Terrace = TERRACE
ParkBuilder.bridgeTop = bridgeTop

return ParkBuilder

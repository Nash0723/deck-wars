-- Builds the biome scenery (src/shared/TableScenery.luau) for a 1v1 board inside the fake Roblox
-- and prints every part as a JSON line, for preview/scenery.py to render.
-- Usage (from the repo root):
--   luaurun -D FAR=Snack,Junk,Weather,Critter -D NEAR=Spooky,Robo,Snack,Junk preview/scenery_dump.luau mock_roblox > /tmp/parts.jsonl

local Mock = require("RobloxMock")
for k, v in pairs(Mock.env) do
	_G[k] = v
end
local env = setmetatable({}, { __index = _G })
for k, v in pairs(Mock.env) do
	env[k] = v
end
local TableScenery = __loadchunk(__readfile("src/shared/TableScenery.luau"), "TableScenery", env)()

local FamilyColors = { Snack = { 255, 150, 90 }, Junk = { 140, 130, 110 }, Weather = { 120, 190, 255 }, Critter = { 150, 220, 110 }, Spooky = { 170, 110, 220 }, Robo = { 200, 200, 215 } }
local LOOK = {
	Snack = { Enum.Material.Sand, 0.12 },
	Junk = { Enum.Material.CorrodedMetal, 0.3 },
	Weather = { Enum.Material.Snow, 0.05 },
	Critter = { Enum.Material.Grass, 0.25 },
	Spooky = { Enum.Material.Slate, 0.3 },
	Robo = { Enum.Material.DiamondPlate, 0.25 },
}
local function groundColor(f)
	local c = FamilyColors[f]
	return Color3.fromRGB(c[1], c[2], c[3]):Lerp(Color3.fromRGB(30, 26, 32), LOOK[f][2])
end

local function split(s)
	local out = {}
	for w in string.gmatch(s, "[^,]+") do
		table.insert(out, w)
	end
	return out
end
local far = split(FAR or "Snack,Junk,Weather,Critter")
local near = split(NEAR or "Spooky,Robo,Snack,Junk")
local SEED = SEED or 0

local folder = Instance.new("Folder")
local pitch, width, half, frame, base = 3.075, 4, 7.35, 0.36, 4.1
local groundTop = base + 0.26
local function laneX(lane)
	return (lane - (width + 1) / 2) * pitch
end

local function num(x)
	return string.format("%.4f", x)
end
local function dumpPart(p, family)
	local shape = "B"
	if p:FindFirstChildOfClass("SpecialMesh") then
		shape = "E"
	elseif p.Shape == Enum.PartType.Ball then
		shape = "S"
	elseif p.Shape == Enum.PartType.Cylinder then
		shape = "C"
	end
	local cf = p.CFrame
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local c = p.Color
	print(string.format(
		'{"shape":"%s","size":[%s,%s,%s],"pos":[%s,%s,%s],"R":[[%s,%s,%s],[%s,%s,%s],[%s,%s,%s]],"color":[%s,%s,%s],"mat":"%s","tr":%s,"name":"%s","fam":"%s"}',
		shape, num(p.Size.X), num(p.Size.Y), num(p.Size.Z), num(cf.Position.X), num(cf.Position.Y), num(cf.Position.Z),
		num(r.X), num(u.X), num(-l.X), num(r.Y), num(u.Y), num(-l.Y), num(r.Z), num(u.Z), num(-l.Z),
		num(c.R), num(c.G), num(c.B), p.Material.Name, num(p.Transparency), p.Name, family
	))
end

-- what stands beside the field in 1v1: the heroes (left), the decks and the trash pile (right) and
-- the path the cards fly along between them
local AVOID = { { -8.75, 3.9, 1.9 }, { -8.75, -3.9, 1.9 }, { 9.65, 8.55, 1.5 }, { 9.65, -8.55, 1.5 }, { 9.65, 0, 1.5 } }
for _, zs in ipairs({ 1, -1 }) do
	for _, f in ipairs({ 0.25, 0.5, 0.75 }) do
		table.insert(AVOID, { 9.65, zs * 8.55 * f, 0.6 })
	end
end

local total, glows = 0, 0
for side, lands in pairs({ [1] = near, [-1] = far }) do
	for lane = 1, width do
		local fam = lands[lane]
		local out = TableScenery.build({
			family = fam,
			cx = laneX(lane),
			pitch = pitch,
			groundTop = groundTop,
			base = base,
			half = half,
			frameOut = half + frame,
			dir = side,
			mine = side == 1,
			seed = (side == 1 and 1 or 2) * 997 + lane * 131 + SEED,
			parent = folder,
			ground = groundColor(fam),
			groundMaterial = LOOK[fam][1],
			outer = (lane == 1 and -1) or (lane == width and 1) or nil,
			fieldEdge = pitch * width / 2 + frame,
			avoid = AVOID,
		})
		for _, p in ipairs(out.parts) do
			if p.Transparency < 0.99 then
				dumpPart(p, fam)
			end
		end
		total += #out.parts
		glows += #out.life
	end
end
print(string.format("# parts %d, glows %d, mock errors %d, warnings %d", total, glows, Mock.errors, Mock.warnings))

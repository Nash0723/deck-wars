-- The layered effects (src/shared/LayerFx.luau) inside the fake Roblox.
-- Plays every recipe in the world and on the screen, and checks that each one builds its four
-- layers, never produces a size or position that isn't a number, stays inside its room, cleans
-- up after itself, and that nothing is drawn while a sheet has no uploaded id.
-- Usage (from the repo root): luaurun mock_roblox/fxharness.luau mock_roblox
-- With -D FX_DUMP=1 it also prints every frame of every effect (vfx/render_preview.py turns
-- that into the preview pictures).

local M = require("RobloxMock")
local SRC = "src/"

for k, v in pairs(M.env) do
	_G[k] = v
end

local game = M.service("Game", "DataModel")
local Workspace = M.service("Workspace")
local ReplicatedStorage = M.service("ReplicatedStorage")
local RunService = M.service("RunService")
for _, s in ipairs({ Workspace, ReplicatedStorage, RunService }) do
	s.Parent = game
end
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.CFrame = CFrame.lookAt(Vector3.new(0, 16, 12), Vector3.new(0, 4.2, 1.25))
camera.FieldOfView = 48
camera.Parent = Workspace
Workspace.CurrentCamera = camera
M.onFrame = function()
	RunService.RenderStepped:Fire(1 / 30)
	RunService.Heartbeat:Fire(1 / 30)
end

local shared = Instance.new("Folder")
shared.Name = "DeckWars"
shared.Parent = ReplicatedStorage
local cache = {}
local function makeEnv(scriptInst)
	local env = setmetatable({}, { __index = _G })
	for k, v in pairs(M.env) do
		env[k] = v
	end
	env.game = game
	env.workspace = Workspace
	env.script = scriptInst
	env.require = function(mod)
		local r = M.rec(mod)
		if cache[mod] == nil then
			local f = __loadchunk(__readfile(r.sourcePath), r.sourcePath, makeEnv(mod))
			cache[mod] = f()
		end
		return cache[mod]
	end
	return env
end
local mods = {}
for _, n in ipairs({ "Settings", "VfxAssets", "LayerFx" }) do
	local m = Instance.new("ModuleScript")
	m.Name = n
	M.rec(m).sourcePath = SRC .. "shared/" .. n .. ".luau"
	m.Parent = shared
	mods[n] = m
end
local LayerFx = makeEnv(nil).require(mods.LayerFx)
local Assets = LayerFx.Assets

local ok, bad = 0, 0
local function check(cond, what)
	if cond then
		ok += 1
	else
		bad += 1
		print("FAIL " .. what)
	end
end

local names = {}
for name in pairs(LayerFx.Recipes) do
	table.insert(names, name)
end
table.sort(names)

---------------------------------------------------------------------------
-- 1. The shipped ids: every sheet is either uploaded or cleanly skipped
---------------------------------------------------------------------------
local SHEETS = { "burst", "slash", "ring", "circle", "pillar", "bolt", "puff", "bloom", "shield", "shard", "flame", "spark", "bits" }
local uploaded = 0
for _, s in ipairs(SHEETS) do
	local id = Assets[s]
	check(type(id) == "string", "VfxAssets." .. s .. " should be a string")
	if id ~= "" then
		uploaded += 1
		check(string.match(id, "^rbxassetid://%d+$") ~= nil, "VfxAssets." .. s .. " is not an asset id: " .. tostring(id))
	end
end
print(string.format("%d of %d sheets have an uploaded id", uploaded, #SHEETS))

-- With a sheet missing, its effects draw nothing at all.
do
	local keep = {}
	for _, s in ipairs(SHEETS) do
		keep[s] = Assets[s]
		Assets[s] = ""
	end
	for _, name in ipairs(names) do
		check(LayerFx.ready(name) == false, name .. " should not be ready without its sheets")
		check(LayerFx.play(name, Vector3.new(0, 5, 0), {}) == nil, name .. " should not play without its sheets")
	end
	check(Workspace:FindFirstChild("LayerFx") == nil or #Workspace.LayerFx:GetChildren() == 0, "nothing is built without sheets")
	for _, s in ipairs(SHEETS) do
		Assets[s] = keep[s]
	end
end

-- From here on every sheet has an id (made-up ones where nothing is uploaded yet).
for i, s in ipairs(SHEETS) do
	if Assets[s] == "" then
		Assets[s] = "rbxassetid://" .. (9000 + i)
	end
end

---------------------------------------------------------------------------
-- 2. Every recipe: layers, numbers, cleanup
---------------------------------------------------------------------------
local function finite(n)
	return type(n) == "number" and n == n and n > -1e6 and n < 1e6
end

local function watch(name, root, frames, dumpAs)
	-- root: the gui that holds the sprites. Steps time and looks at every frame.
	local seenLayer = {}
	local peak = 0
	for f = 1, frames do
		M.advance(1 / 30 + 1e-5)
		if not root.Parent then
			break
		end
		local line = {}
		for _, img in ipairs(root:GetChildren()) do
			if img:IsA("ImageLabel") and img.Visible then
				local sx, sy = img.Size.X.Scale, img.Size.Y.Scale
				local px, py = img.Position.X.Scale, img.Position.Y.Scale
				check(finite(sx) and finite(sy) and finite(px) and finite(py) and finite(img.Rotation), name .. ": a number went wrong on " .. img.Name)
				check(img.ImageTransparency >= 0 and img.ImageTransparency <= 1, name .. ": transparency out of range on " .. img.Name)
				check(sx >= 0 and sy >= 0, name .. ": negative size on " .. img.Name)
				-- nothing visible should leave the container (the room around the effect)
				if img.ImageTransparency < 0.98 then
					peak = math.max(peak, math.abs(px - 0.5) + sx / 2, math.abs(py - 0.5) + sy / 2)
				end
				if img.ImageTransparency < 0.6 then
					seenLayer[img.Name] = true
				end
				if dumpAs then
					table.insert(line, string.format("%s,%d,%d,%.4f,%.4f,%.4f,%.4f,%.2f,%.3f,%d,%d,%d,%d,%.2f,%.2f", img.Name,
						img.ImageRectOffset.X, img.ImageRectOffset.Y, px, py, sx, sy, img.Rotation, img.ImageTransparency,
						math.floor(img.ImageColor3.R * 255 + 0.5), math.floor(img.ImageColor3.G * 255 + 0.5), math.floor(img.ImageColor3.B * 255 + 0.5), img.ZIndex,
						img.AnchorPoint.X, img.AnchorPoint.Y))
				end
			end
		end
		if dumpAs then
			print("FRAME " .. dumpAs .. " " .. f .. " " .. table.concat(line, ";"))
		end
	end
	return seenLayer, peak
end

local PAL = { hit = "ember", bigHit = "blood", slash = "steel", slam = "gold", circle = "arcane", pillar = "holy", bolt = "frost", puff = "smoke", bloom = "verdant", shield = "frost", shards = "frost", flame = "ember", glint = "gold", nova = "arcane" }

for _, name in ipairs(names) do
	local recipe = LayerFx.Recipes[name]
	check(LayerFx.ready(name), name .. " is ready")
	-- in the world
	local done = false
	local h = LayerFx.play(name, Vector3.new(0, 5, 0), { palette = PAL[name], size = 4, to = Vector3.new(2, 5, -4), aim = Vector3.new(1, 0, -1), onDone = function()
		done = true
	end })
	check(h ~= nil, name .. " plays in the world")
	local anchor = Workspace.LayerFx:FindFirstChild("Fx_" .. name)
	check(anchor ~= nil and anchor.Anchored and not anchor.CanCollide and not anchor.CanQuery, name .. ": anchor part is inert")
	local gui = anchor and anchor:FindFirstChild("Layers")
	check(gui ~= nil and gui:IsA(recipe.flat and "SurfaceGui" or "BillboardGui"), name .. ": the right kind of gui")
	if gui then
		local frames = math.ceil(recipe.len * 30) + 3
		local seen, peak = watch(name, gui, frames)
		local layers = 0
		for _ in pairs(seen) do
			layers += 1
		end
		check(layers >= 4, name .. ": at least four layers show (" .. layers .. ")")
		check(peak <= 0.5 + 1e-3, string.format("%s: stays inside its room in the world (%.3f)", name, peak))
		if recipe.travels then
			check((anchor.Position - Vector3.new(2, 5, -4)).Magnitude < 0.01 or anchor.Parent == nil, name .. ": arrives at its target")
		end
	end
	M.advance(0.2)
	check(done, name .. ": onDone fired")
	check(anchor == nil or anchor.Parent == nil, name .. ": cleaned up")
	-- on the screen
	local screen = Instance.new("ScreenGui")
	screen.Parent = Workspace
	local h2 = LayerFx.screen(name, screen, UDim2.fromScale(0.5, 0.5), 300, { palette = PAL[name], turn = name == "slash" and -90 or nil })
	check(h2 ~= nil, name .. " plays on the screen")
	local holder = screen:FindFirstChild("Fx_" .. name)
	check(holder ~= nil, name .. ": screen holder")
	if holder then
		watch(name, holder, math.ceil(recipe.len * 30) + 3, FX_DUMP and name or nil)
		M.advance(0.2)
		check(holder.Parent == nil, name .. ": screen effect cleaned up")
	end
	screen:Destroy()
end
check(LayerFx.count() == 0, "no effects left running")

-- 3. Driven by hand (Pack Brawl's clock), a delayed start, and stopping early.
do
	local h = LayerFx.play("hit", Vector3.new(0, 5, 0), { manual = true })
	check(LayerFx.count() == 0, "a manual effect isn't on the frame loop")
	for i = 0, 10 do
		h:set(i / 10)
	end
	h:stop()
	check(#Workspace.LayerFx:GetChildren() == 0, "manual effect stopped and removed")
	local d = LayerFx.play("hit", Vector3.new(0, 5, 0), { delay = 0.5 })
	M.advance(0.3)
	local gui = Workspace.LayerFx:FindFirstChild("Fx_hit").Layers
	local showing = 0
	for _, img in ipairs(gui:GetChildren()) do
		if img.Visible then
			showing += 1
		end
	end
	check(showing == 0, "a delayed effect shows nothing before its time")
	M.advance(0.4)
	showing = 0
	for _, img in ipairs(gui:GetChildren()) do
		if img.Visible then
			showing += 1
		end
	end
	check(showing > 0, "a delayed effect starts after its delay")
	d:stop()
	M.advance(0.1)
	check(LayerFx.count() == 0 and #Workspace.LayerFx:GetChildren() == 0, "stopped effect is gone")
end

print(string.format("%d ok, %d failed, %d errors, %d warnings", ok, bad, M.errors, M.warnings))
if bad > 0 or M.errors > 0 or M.warnings > 0 then
	error("fx harness failed")
end

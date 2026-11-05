-- The menu room's props answering the mouse (src/shared/RoomLife.luau), inside the fake Roblox.
-- Finds every kind of prop in the room, points at each one and clicks each one, and checks that
-- it moves the right way, never flies off or turns into NaN, and goes back exactly where it was.
-- Usage (from the repo root): luaurun mock_roblox/roomharness.luau mock_roblox

local M = require("RobloxMock")
local SRC = "src/"

for k, v in pairs(M.env) do
	_G[k] = v
end

local game = M.service("Game", "DataModel")
local Workspace = M.service("Workspace")
local ReplicatedStorage = M.service("ReplicatedStorage")
local RunService = M.service("RunService")
local SoundService = M.service("SoundService")
local Debris = M.service("Debris")
for _, s in ipairs({ Workspace, ReplicatedStorage, RunService, SoundService, Debris }) do
	s.Parent = game
end
M.service("ContentProvider").Parent = game
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = Workspace
Workspace.CurrentCamera = camera

M.build(require("WorldData")(), Workspace)
local room = Workspace:FindFirstChild("MenuRoom")

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
for _, n in ipairs({ "Settings", "TableSounds", "RoomLife" }) do
	local m = Instance.new("ModuleScript")
	m.Name = n
	M.rec(m).sourcePath = SRC .. "shared/" .. n .. ".luau"
	m.Parent = shared
	mods[n] = m
end
local RoomLife = makeEnv(nil).require(mods.RoomLife)

local ok, bad = 0, 0
local function check(cond, what)
	if cond then
		ok += 1
	else
		bad += 1
		print("FAIL " .. what)
	end
end

-- The mouse points at whatever part `aim` is (nil = nothing).
local aim = nil
M.raycastHook = function(origin, dir, params)
	if not aim then
		return nil
	end
	return { Instance = aim, Position = aim.Position, Normal = Vector3.new(0, 1, 0), Distance = (aim.Position - origin).Magnitude }
end
local MOUSE = Vector2.new(640, 360)
local function run(seconds, mouse, active)
	local n = math.floor(seconds * 60 + 0.5)
	for _ = 1, n do
		RoomLife.update(1 / 60, mouse, active ~= false)
	end
end

---------------------------------------------------------------------------
-- 1. Every kind of prop is found, and every part that belongs to one is claimed
---------------------------------------------------------------------------
local found = RoomLife.attach(room)
local EXPECT = {
	binder = 24, cardbox = 5, shelflamp = 1, balloon = 5, speaker = 2, discoball = 1, discotile = 36, packjar = 2,
	pickles = 1, register = 1, candyjar = 9, packbox = 18, displaypack = 5, awning = 8, trophy = 6, pennant = 5,
	certificate = 2, radio = 1, fireplace = 1, candle = 2, clock = 1, mantletrophy = 1, poster = 1, poster2 = 1,
	lamp = 4, plant = 5, curtain = 6, window = 3,
}
local counts = RoomLife.counts()
local total = 0
for kind, n in pairs(EXPECT) do
	check(counts[kind] == n, string.format("%s: expected %d, found %s", kind, n, tostring(counts[kind])))
	total += n
end
for kind in pairs(counts) do
	check(EXPECT[kind] ~= nil, "unexpected kind " .. kind)
end
check(found == total, "attach returned " .. found .. ", expected " .. total)
print(string.format("found %d props of %d kinds", found, #(function()
	local t = {}
	for k in pairs(counts) do
		table.insert(t, k)
	end
	return t
end)()))

-- the companions: every one in the room is claimed by exactly one prop
local claimed = {}
for _, p in ipairs(RoomLife.props) do
	for _, e in ipairs(p.parts) do
		check(claimed[e.part] == nil, "part claimed twice: " .. e.part:GetFullName())
		claimed[e.part] = p
	end
end
local function countIn(container, name)
	local n, c = 0, 0
	for _, d in ipairs(container:GetChildren()) do
		if d.Name == name and d:IsA("BasePart") then
			n += 1
			if claimed[d] then
				c += 1
			end
		end
	end
	return n, c
end
local stations = room.Stations
for _, spec in ipairs({
	{ stations.DeckShelf, { "BinderLabel", "BinderRing" } },
	{ stations.PackParty, { "BalloonKnot", "BalloonString", "SpeakerCone", "SpeakerDust" } },
	{ stations.PackParty.PackShelf, { "PackJarLid", "MiniPack" } },
	{ stations.ShopCounter, { "JarCandy", "PickleBump", "PicklesEye", "PicklesPupil", "PicklesArm", "PicklesHand", "RegisterKey", "AwningScallop" } },
	{ stations.TrophyWall, { "TrophyHandle", "TrophyBase", "TrophyStem", "TrophyRim", "Seal" } },
	{ stations.Radio, { "RadioNeedle", "RadioKnob", "RadioAntenna", "MusicNote", "MusicNoteHead" } },
	{ room.Structure, { "Leaf", "LeafTop", "CurtainFold", "Tieback", "Star", "LampBulb", "LampCord", "Flame", "ClockHand", "Log" } },
}) do
	for _, name in ipairs(spec[2]) do
		local n, c = countIn(spec[1], name)
		check(n > 0 and n == c, string.format("%s: %d of %d claimed", name, c, n))
	end
end
-- the door and the fireplace painting belong to the lobby (Plaza door, Campaign map)
check(claimed[room.Structure:FindFirstChild("Door")] == nil, "the door must be left alone")
check(claimed[room.Structure:FindFirstChild("PaintingFrame")] == nil, "the painting must be left alone")
-- the pack shelf's packs belong to PackShelf
for _, d in ipairs(stations.PackParty.PackShelf:GetDescendants()) do
	if d:IsA("BasePart") and d.Parent.Name:match("^ShelfPack_") then
		check(claimed[d] == nil, "pack part claimed: " .. d:GetFullName())
	end
end
-- each trophy has its 16 handle pieces, each binder its label and ring
for _, p in ipairs(RoomLife.kinds.trophy) do
	check(#p.parts == 20, "trophy parts " .. #p.parts)
end
for _, p in ipairs(RoomLife.kinds.binder) do
	check(#p.parts == 3, "binder parts " .. #p.parts)
end

---------------------------------------------------------------------------
-- Helpers to see what moved
---------------------------------------------------------------------------
local function snapshot()
	local s = {}
	for _, p in ipairs(RoomLife.props) do
		for _, e in ipairs(p.parts) do
			s[e.part] = e.part.CFrame
		end
	end
	return s
end
local HOME = snapshot()

-- left alone, something fidgets on its own every so often (then the tests turn that off)
do
	local moved = false
	for _ = 1, 60 * 30 do
		RoomLife.update(1 / 60, nil, true)
		for part, cf in pairs(HOME) do
			if part.Name ~= "PicklesPupil" and (part.CFrame.Position - cf.Position).Magnitude > 0.02 then
				moved = true
			end
		end
	end
	check(moved, "something fidgets on its own within 30 s")
	RoomLife.idleFidgets = false
	run(4, nil)
end
local function isNaN(v)
	return v ~= v
end
local function offset(part)
	local a, b = HOME[part], part.CFrame
	local d = (b.Position - a.Position).Magnitude
	-- how far the corners of a 1-stud box turn, as a measure of rotation
	local r = 0
	for _, v in ipairs({ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }) do
		r = math.max(r, ((b * v - b.Position) - (a * v - a.Position)).Magnitude)
	end
	return d, r
end
local function maxMove(p)
	local md, mr = 0, 0
	for _, e in ipairs(p.parts) do
		local d, r = offset(e.part)
		local cf = e.part.CFrame
		if isNaN(cf.X) or isNaN(cf.Y) or isNaN(cf.Z) then
			return math.huge, math.huge
		end
		md, mr = math.max(md, d), math.max(mr, r)
	end
	return md, mr
end
-- (Pickles' pupils keep following the cursor, so they don't count as "away from home")
local function allHome()
	local worst = 0
	for part, cf in pairs(HOME) do
		local d, r = 0, 0
		if part.Name ~= "PicklesPupil" then
			d, r = offset(part)
		end
		worst = math.max(worst, d, r)
	end
	return worst
end
local function sample(p, seconds, mouse)
	local md, mr = 0, 0
	for _ = 1, math.floor(seconds * 60) do
		RoomLife.update(1 / 60, mouse, true)
		local d, r = maxMove(p)
		md, mr = math.max(md, d), math.max(mr, r)
	end
	return md, mr
end

-- how far each kind may move, in studs (and in turn, as corner travel on a 1-stud box)
local LIMIT = { pickles = { 4.2, 2.5 }, radio = { 1.0, 1.5 }, trophy = { 1.4, 2.5 }, cardbox = { 1.4, 2.5 }, displaypack = { 1.0, 2.5 }, mantletrophy = { 1.0, 2.5 }, packjar = { 1.6, 2.5 }, clock = { 1.0, 2.5 } }

---------------------------------------------------------------------------
-- 2. Point at one of each kind, then away; then click one of each kind
---------------------------------------------------------------------------
local STILL = { discoball = true, discotile = true, fireplace = true, candle = true, window = true }
for kind, list in pairs(RoomLife.kinds) do
	local p = list[1]
	aim = p.anchor
	local md, mr = sample(p, 1.2, MOUSE)
	check(RoomLife.hovered() == p, kind .. ": not hovered")
	local lim = LIMIT[kind] or { 1.0, 1.2 }
	if STILL[kind] then
		check(md < 1e-6, kind .. ": should not move its parts (" .. md .. ")")
	else
		check(md + mr > 0.01, kind .. ": didn't move when pointed at")
	end
	check(md <= lim[1] and mr <= lim[2], string.format("%s: moved too far on hover (%.2f studs, %.2f turn)", kind, md, mr))
	aim = nil
	run(4, MOUSE)
	local worst = allHome()
	check(worst < 1e-6, string.format("%s: not home after hover (%.2g)", kind, worst))

	aim = p.anchor
	local got = RoomLife.click(MOUSE, true)
	check(got == p, kind .. ": click didn't hit it")
	aim = nil
	md, mr = sample(p, 2.0, MOUSE)
	check(md <= lim[1] + 0.6 and mr <= lim[2] + 1.2, string.format("%s: moved too far on click (%.2f studs, %.2f turn)", kind, md, mr))
	run(4, MOUSE)
	worst = allHome()
	check(worst < 1e-6, string.format("%s: not home after click (%.2g)", kind, worst))
end

---------------------------------------------------------------------------
-- 3. Directions: things come toward the room, not into the wall
---------------------------------------------------------------------------
local function moveWhileHovered(p, part, seconds)
	aim = p.anchor
	run(seconds or 0.8, MOUSE)
	local d = part.CFrame.Position - HOME[part].Position
	return d
end
local function centerToRoom(part)
	local v = -HOME[part].Position
	return Vector3.new(v.X, 0, v.Z).Unit
end
do
	local b = RoomLife.kinds.binder[5]
	local d = moveWhileHovered(b, b.anchor)
	check(d:Dot(centerToRoom(b.anchor)) > 0.3, "binder slides out toward the room")
	aim = nil
	run(3, MOUSE)
end
do
	local p = RoomLife.kinds.pennant[2]
	local d = moveWhileHovered(p, p.anchor)
	check(d:Dot(centerToRoom(p.anchor)) > 0.02, "pennant swings away from the wall")
	aim = nil
	run(3, MOUSE)
end
do
	local p = RoomLife.kinds.curtain[1]
	local low = p.lo.Y
	aim = p.anchor
	run(0.8, MOUSE)
	local bottom = p.anchor.CFrame * Vector3.new(0, -p.anchor.Size.Y / 2, 0)
	local home = HOME[p.anchor] * Vector3.new(0, -p.anchor.Size.Y / 2, 0)
	check((bottom - home):Dot(p.out) > 0.05, "curtain swings into the room")
	check(low < bottom.Y + 0.5, "curtain stays low")
	aim = nil
	run(3, MOUSE)
end
do
	local p = RoomLife.kinds.packbox[3]
	aim = p.anchor
	run(0.8, MOUSE)
	local top = p.anchor.CFrame * Vector3.new(0, p.anchor.Size.Y / 2, 0)
	local home = HOME[p.anchor] * Vector3.new(0, p.anchor.Size.Y / 2, 0)
	check((top - home):Dot(centerToRoom(p.anchor)) > 0.05, "pack box tips toward the room")
	aim = nil
	run(3, MOUSE)
end
do
	local p = RoomLife.kinds.register[1]
	local drawer
	for _, e in ipairs(p.parts) do
		if e.name == "RegisterDrawer" then
			drawer = e.part
		end
	end
	local d = moveWhileHovered(p, drawer)
	check(d:Dot(Vector3.new(0, 0, -1)) > 0.1, "register drawer slides out toward the counter front")
	aim = nil
	run(3, MOUSE)
end
do
	-- Pickles waves, his pupils look at the cursor's side, and he blinks
	local p = RoomLife.kinds.pickles[1]
	local waved = false
	for _, e in ipairs(p.parts) do
		if e.wave and e.name == "PicklesHand" then
			local d = moveWhileHovered(p, e.part, 1.0)
			waved = d.Y > 0.5
		end
	end
	check(waved, "Pickles raises a hand to wave")
	aim = nil
	run(3, MOUSE)
	p.look = p.anchor.Position + p.side * 6
	RoomLife.update(1 / 60, MOUSE, true)
	local moved = 0
	for _, e in ipairs(p.parts) do
		if e.name == "PicklesPupil" then
			moved += (e.part.Position - HOME[e.part].Position):Dot(p.side)
		end
	end
	check(moved > 0.05, "Pickles' pupils follow the cursor")
	local blinked = false
	for _ = 1, 60 * 10 do
		RoomLife.update(1 / 60, nil, true)
		for _, e in ipairs(p.parts) do
			if e.mesh and e.mesh.Scale.Y < e.meshScale.Y * 0.5 then
				blinked = true
			end
		end
	end
	check(blinked, "Pickles blinks")
end
do
	-- the clock's hands turn when pointed at
	local p = RoomLife.kinds.clock[1]
	local turned = 0
	aim = p.anchor
	run(1.2, MOUSE)
	for _, e in ipairs(p.parts) do
		if e.name == "ClockHand" then
			local _, r = offset(e.part)
			turned = math.max(turned, r)
		end
	end
	check(turned > 0.05, "clock hands turn to the time")
	aim = nil
	run(3, MOUSE)
end
do
	-- the fire flares, the disco ball spins faster, the dance floor lights up
	local fire = RoomLife.kinds.fireplace[1]
	aim = fire.anchor
	run(0.8, MOUSE)
	check(RoomLife.fireBoost() > 1.2, "fire flares when pointed at")
	check(fire.fire == nil or fire.fire.Size > fire.fireSize, "fire grows")
	aim = nil
	run(4, MOUSE)
	check(math.abs(RoomLife.fireBoost() - 1) < 1e-6, "fire calms down")
	check(fire.fire == nil or fire.fire.Size == fire.fireSize, "fire back to its size")

	local disco = RoomLife.kinds.discoball[1]
	aim = disco.anchor
	run(0.8, MOUSE)
	check(RoomLife.discoBoost() > 3, "disco ball spins faster")
	aim = nil
	run(4, MOUSE)

	local tile = RoomLife.kinds.discotile[15]
	aim = tile.anchor
	run(0.3, MOUSE)
	check(RoomLife.tilesBusy(), "dance floor busy")
	check(RoomLife.tileGlow(tile.anchor) > 0.5, "tile under the cursor glows")
	local far = RoomLife.kinds.discotile[36]
	RoomLife.click(MOUSE, true)
	local reached = false
	for _ = 1, 60 do
		RoomLife.update(1 / 60, MOUSE, true)
		if RoomLife.tileGlow(far.anchor) > 0.2 then
			reached = true
		end
	end
	check(reached, "a click ripple runs across the floor")
	aim = nil
	run(3, MOUSE)
	check(not RoomLife.tilesBusy(), "dance floor calms down")
end
do
	-- a candle puffs out and lights again; a window gets a shooting star
	local c = RoomLife.kinds.candle[1]
	aim = c.anchor
	RoomLife.click(MOUSE, true)
	run(0.5, MOUSE)
	check(c.flame == nil or c.flame.Scale.X < 0.01, "candle puffed out")
	aim = nil
	run(3, MOUSE)
	check(c.flame == nil or (c.flame.Scale - c.flameScale).Magnitude < 1e-6, "candle relit")

	local w = RoomLife.kinds.window[1]
	aim = w.anchor
	RoomLife.click(MOUSE, true)
	local fx = Workspace:FindFirstChild("RoomLifeFx")
	run(0.3, MOUSE)
	check(fx and fx:FindFirstChild("ShootingStar") ~= nil, "shooting star crosses the window")
	aim = nil
	run(2, MOUSE)
	check(fx and #fx:GetChildren() == 0, "shooting star gone")
end

---------------------------------------------------------------------------
-- 4. Sitting down mid-wobble puts everything back at once; a long session never drifts
---------------------------------------------------------------------------
do
	for _, kind in ipairs({ "binder", "balloon", "trophy", "plant", "radio" }) do
		aim = RoomLife.kinds[kind][1].anchor
		RoomLife.click(MOUSE, true)
	end
	run(0.2, MOUSE)
	check(allHome() > 0.01, "things are moving")
	RoomLife.update(1 / 60, nil, false) -- (the client does this the moment a match starts)
	check(allHome() < 1e-9, "everything snaps home when the room goes inactive")
	check(RoomLife.hovered() == nil, "nothing hovered when inactive")
	check(RoomLife.fireBoost() == 1, "fire back to normal")

	-- sweep the mouse across everything for a while, clicking now and then
	math.randomseed(7)
	for i = 1, 1500 do
		local p = RoomLife.props[math.random(1, #RoomLife.props)]
		aim = p.anchor
		if i % 9 == 0 then
			RoomLife.click(MOUSE, true)
		end
		run(0.1, MOUSE)
	end
	aim = nil
	run(5, MOUSE)
	check(allHome() < 1e-6, string.format("everything home after a long sweep (%.2g)", allHome()))
	RoomLife.rest()
	check(allHome() < 1e-9, "rest() is exact")
end

M.advance(3) -- (lets the delayed sparkle clean-ups run)
print(string.format("roomharness: %d ok, %d failed", ok, bad))
if bad > 0 then
	error("room harness failed")
end
